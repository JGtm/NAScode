#!/usr/bin/env bats
###########################################################
# TESTS - Journal des tentatives (lib/attempts.sh)
# Reprise sans retraiter les films déjà convertis sans gain,
# amorçage depuis _Heavier et cumul du résumé entre plusieurs runs.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/ui_options.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/attempts.sh"

    export LOG_DIR="$TEST_TEMP_DIR/logs"
    mkdir -p "$LOG_DIR"
    export ATTEMPTS_FILE="$LOG_DIR/Attempts.tsv"
    export LOG_SESSION="$LOG_DIR/session.log"
    : > "$LOG_SESSION"
    export SOURCE="/z" OUTPUT_DIR="$TEST_TEMP_DIR/Converted" HEAVY_OUTPUT_DIR_SUFFIX="_Heavier"
    export CONVERSION_MODE=film VIDEO_CODEC=hevc VIDEO_ENCODER=libx265 CRF_VALUE=21
    export HEAVY_MIN_SAVINGS_PERCENT=10 RETRY_HEAVIER=false DRYRUN=false SAMPLE_MODE=false
    export NO_PROGRESS=true
}

teardown() {
    teardown_test_env
}

# Filtre une liste "taille<TAB>chemin" et affiche les chemins conservés
_filter() {
    printf '%s\n' "$@" | attempts_filter_index_lines "$LOG_DIR/skipped" | cut -f2-
}

###########################################################
# Empreinte
###########################################################

@test "attempts_fingerprint: stable, et change avec les paramètres d'encodage" {
    local a b c
    a=$(attempts_fingerprint)
    b=$(attempts_fingerprint)
    CRF_VALUE=23 c=$(attempts_fingerprint)
    [ "$a" = "$b" ]
    [ "$a" != "$c" ]
    [[ "$a" =~ ^[0-9a-f]{8}$ ]]
}

@test "attempts_fingerprint: le seuil de gain n'en fait pas partie" {
    local a b
    a=$(attempts_fingerprint)
    HEAVY_MIN_SAVINGS_PERCENT=5 b=$(attempts_fingerprint)
    [ "$a" = "$b" ]
}

###########################################################
# Filtrage de la queue
###########################################################

@test "filtre: un film tenté sans gain avec les mêmes paramètres sort de la queue" {
    attempts_record heavier "/z/Batman.mkv" 5000 5000
    attempts_record converted "/z/Hook.mkv" 4000 2000

    run _filter $'5000\t/z/Batman.mkv' $'4000\t/z/Hook.mkv' $'3000\t/z/Neuf.mkv'
    [ "$status" -eq 0 ]
    [ "$output" = $'/z/Hook.mkv\n/z/Neuf.mkv' ]
    [ "$(cat "$LOG_DIR/skipped")" = "/z/Batman.mkv" ]
}

@test "filtre: source modifiée (autre taille) → retentée" {
    attempts_record heavier "/z/Batman.mkv" 5000 5000
    run _filter $'5100\t/z/Batman.mkv'
    [ "$output" = "/z/Batman.mkv" ]
}

@test "filtre: paramètres changés → retentée" {
    attempts_record heavier "/z/Batman.mkv" 5000 5000
    CRF_VALUE=26 run _filter $'5000\t/z/Batman.mkv'
    [ "$output" = "/z/Batman.mkv" ]
}

@test "filtre: seuil abaissé sous le gain obtenu → retentée" {
    attempts_record heavier "/z/Endgame.mkv" 10000 9100   # 9 % de gain
    run _filter $'10000\t/z/Endgame.mkv'
    [ -z "$output" ]
    HEAVY_MIN_SAVINGS_PERCENT=5 run _filter $'10000\t/z/Endgame.mkv'
    [ "$output" = "/z/Endgame.mkv" ]
}

@test "filtre: --retry-heavier retente tout" {
    attempts_record heavier "/z/Batman.mkv" 5000 5000
    RETRY_HEAVIER=true run _filter $'5000\t/z/Batman.mkv'
    [ "$output" = "/z/Batman.mkv" ]
}

@test "filtre: seule la dernière tentative compte" {
    attempts_record heavier "/z/Batman.mkv" 5000 5000
    attempts_record converted "/z/Batman.mkv" 5000 3000
    run _filter $'5000\t/z/Batman.mkv'
    [ "$output" = "/z/Batman.mkv" ]
}

@test "filtre: chemin avec espaces, accents et apostrophe" {
    local p="/z/Star Wars/L'Empire contre-attaque (1980) é.mkv"
    attempts_record heavier "$p" 7000 7000
    run _filter "7000"$'\t'"$p"
    [ -z "$output" ]
}

@test "record: rien n'est noté en dry-run ni en mode extrait" {
    DRYRUN=true attempts_record heavier "/z/A.mkv" 1 1
    SAMPLE_MODE=true attempts_record heavier "/z/B.mkv" 1 1
    [ ! -s "$ATTEMPTS_FILE" ]
}

###########################################################
# Amorçage depuis _Heavier
###########################################################

_setup_seed() {
    export INDEX="$LOG_DIR/Index"
    local heavy="$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX"
    mkdir -p "$heavy/Marvel"
    # Sorties sans gain suffisant : 0 % et 9 % (seuil 10 %)
    printf 'x%.0s' {1..100} > "$heavy/The Batman (2022).mkv"
    printf 'x%.0s' {1..91} > "$heavy/Marvel/Endgame_x265_1080p.mkv"
    printf '%s\n' $'100\t/z/The Batman (2022).mkv' $'100\t/z/Marvel/Endgame.mkv' \
        $'100\t/z/Marvel/Endgame 2.mkv' $'100\t/z/Autre.mkv' > "$INDEX"
}

@test "amorçage: chaque sortie de _Heavier est rattachée à sa source" {
    _setup_seed
    attempts_seed_from_heavy
    run awk -F'\t' '!/^#/ { print $2 "|" $5 "|" $6 "|" $8 }' "$ATTEMPTS_FILE"
    [ "${#lines[@]}" -eq 2 ]
    [[ "$output" == *"heavier|100|100|/z/The Batman (2022).mkv"* ]]
    # Nom suivi d'un suffixe "_…" : rattaché à Endgame, pas à « Endgame 2 »
    [[ "$output" == *"heavier|100|91|/z/Marvel/Endgame.mkv"* ]]
    grep -q $'^#SEED\t.*\t2$' "$ATTEMPTS_FILE"
}

@test "amorçage: une seule fois, et les films amorcés sortent de la queue" {
    _setup_seed
    attempts_seed_from_heavy
    attempts_seed_from_heavy
    [ "$(grep -c '^#SEED' "$ATTEMPTS_FILE")" -eq 1 ]
    run _filter $'100\t/z/The Batman (2022).mkv' $'100\t/z/Autre.mkv'
    [ "$output" = "/z/Autre.mkv" ]
}

@test "amorçage: les sorties lourdes déjà supprimées sont retrouvées dans les logs" {
    _setup_seed
    printf '%s\n' $'1000\t/z/Star Wars/Jedi (1983).mkv' $'2000\t/z/Refait.mkv' \
        $'3000\t/z/Interrompu.mkv' >> "$INDEX"
    cat > "$LOG_DIR/Session_20261101_100000.log" <<'EOF'
2026-11-01 10:00:00 | HEAVY_OUTPUT_REDIRECT | /z/Star Wars/Jedi (1983).mkv -> /c/C_Heavier/Jedi (1983).mkv | savings:8% (threshold:10%)
2026-11-01 11:00:00 | HEAVY_OUTPUT_REDIRECT | /z/Refait.mkv -> /c/C_Heavier/Refait.mkv | savings:0% (threshold:10%)
2026-11-01 11:00:00 | HEAVY_OUTPUT_REDIRECT | /z/The Batman (2022).mkv -> /c/C_Heavier/The Batman (2022).mkv | savings:0% (threshold:10%)
2026-11-01 12:00:00 | ERROR | /z/Interrompu.mkv | ffmpeg
EOF
    cat > "$LOG_DIR/Session_20261105_100000.log" <<'EOF'
2026-11-05 10:00:00 | REPLACED | /z/Refait.mkv -> /z/Refait.mkv | size:2000B->900B
EOF
    attempts_seed_from_heavy
    run awk -F'\t' '!/^#/ { print $2 "|" $5 "|" $6 "|" $8 }' "$ATTEMPTS_FILE"
    # 2 depuis _Heavier + Jedi depuis les logs ; Batman pas en double, Refait remplacé depuis
    [ "${#lines[@]}" -eq 3 ]
    [[ "$output" == *"heavier|1000|920|/z/Star Wars/Jedi (1983).mkv"* ]]
    [[ "$output" != *"Refait"* && "$output" != *"Interrompu"* ]]
    [ "$(grep -c 'The Batman' "$ATTEMPTS_FILE")" -eq 1 ]
    grep -q $'^#SEED\t.*\t3$' "$ATTEMPTS_FILE"
}

###########################################################
# Cumul entre plusieurs runs
###########################################################

@test "cumul: dernière tentative par film, borné par le dernier passage complet" {
    attempts_record converted "/z/Vieux.mkv" 9000 1000
    attempts_mark_campaign_end
    attempts_record converted "/z/A.mkv" 4000 2000
    attempts_record converted "/z/A.mkv" 4000 1500          # reconverti : compté une fois
    attempts_record heavier "/z/B.mkv" 3000 3000
    attempts_record converted "/y/Autre source.mkv" 8000 1000
    export ATTEMPTS_START_LINE=3                            # lignes 1-3 : runs précédents

    run attempts_campaign_totals
    IFS='|' read -r nc before after nh first old <<< "$output"
    [ "$nc" -eq 1 ]
    [ "$before" -eq 4000 ]
    [ "$after" -eq 1500 ]
    [ "$nh" -eq 1 ]
    [ -n "$first" ]
    [ "$old" -eq 1 ]           # ligne 3 (A, 1re version) ; Vieux est effacé par le #END
}

@test "cumul: un passage complet d'une autre source ne remet pas à zéro" {
    attempts_record converted "/z/A.mkv" 4000 2000
    SOURCE=/y attempts_mark_campaign_end
    run attempts_campaign_totals
    [[ "$output" == 1\|4000\|2000\|0\|* ]]
}

@test "résumé: section cumul affichée seulement si des runs précédents y contribuent" {
    source "$LIB_DIR/summary.sh"
    attempts_record converted "/z/A.mkv" 4000 2000
    export ATTEMPTS_START_LINE=0
    run _render_campaign_totals
    [ -z "$output" ]

    export ATTEMPTS_START_LINE=1
    attempts_record converted "/z/B.mkv" 6000 2000
    run _render_campaign_totals
    [[ "$output" == *"CUMUL DEPUIS LE"* ]]
    [[ "$output" == *"Films convertis"*"2"* ]]
    [[ "$output" == *"60.0%"* ]]
}

###########################################################
# Intégration
###########################################################

@test "finalisation: sortie dans _Heavier notée heavier, sortie publiée notée converted" {
    source "$LIB_DIR/summary.sh"
    source "$LIB_DIR/finalize.sh"
    export TOTAL_SIZE_BEFORE_FILE="$TEST_TEMP_DIR/.b" TOTAL_SIZE_AFTER_FILE="$TEST_TEMP_DIR/.a"
    echo 0 > "$TOTAL_SIZE_BEFORE_FILE"; echo 0 > "$TOTAL_SIZE_AFTER_FILE"
    process_vmaf_queue() { :; }
    mkdir -p "$TEST_TEMP_DIR/z" "$OUTPUT_DIR" "$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX"
    local src="$TEST_TEMP_DIR/z/Film.mkv" heavy="$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX/Film.mkv"
    local src2="$TEST_TEMP_DIR/z/Hook.mkv" out="$OUTPUT_DIR/Hook.mkv"
    head -c 3000 /dev/zero > "$src"; head -c 3000 /dev/zero > "$heavy"
    head -c 3000 /dev/zero > "$src2"; head -c 1000 /dev/zero > "$out"

    _finalize_log_and_verify "$src" "$heavy" "" "" "" 1 3000 "$heavy" 0
    _finalize_log_and_verify "$src2" "$out" "" "" "" 1 1000 "$out" 0
    run awk -F'\t' '!/^#/ { print $2 "|" $5 "|" $6 }' "$ATTEMPTS_FILE"
    [ "$output" = $'heavier|3000|3000\nconverted|3000|1000' ]
}

@test "anti-boucle _Heavier: n'empêche pas un film que le journal autorise à retenter" {
    source "$LIB_DIR/conversion_prep.sh"
    export LIMIT_FILES=0
    compute_heavy_output_path() { echo "$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX/Film.mkv"; }
    mkdir -p "$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX"
    touch "$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX/Film.mkv"

    # Absent du journal : l'ancien garde-fou s'applique
    run _check_output_exists "/z/Film.mkv" "Film.mkv" "$OUTPUT_DIR/Film.mkv"
    [ "$status" -eq 0 ]

    # Tenté avec d'autres paramètres : le journal l'a laissé dans la queue
    CRF_VALUE=30 attempts_record heavier "/z/Film.mkv" 3000 3000
    run _check_output_exists "/z/Film.mkv" "Film.mkv" "$OUTPUT_DIR/Film.mkv"
    [ "$status" -eq 1 ]
}

@test "amorçage: sortie posée à plat (ancien bug) rattachée par nom unique" {
    export INDEX="$LOG_DIR/Index"
    local heavy="$OUTPUT_DIR$HEAVY_OUTPUT_DIR_SUFFIX"
    mkdir -p "$heavy"
    printf 'x%.0s' {1..100} > "$heavy/Transformers 2 (2009).mkv"
    printf 'x%.0s' {1..100} > "$heavy/Doublon.mkv"
    printf '%s\n' $'100\t/z/Transformers/Transformers 2 (2009).mkv' \
        $'100\t/z/A/Doublon.mkv' $'100\t/z/B/Doublon.mkv' > "$INDEX"
    attempts_seed_from_heavy
    run awk -F'\t' '!/^#/ { print $8 }' "$ATTEMPTS_FILE"
    # Nom ambigu (deux sources « Doublon ») : on ne devine pas
    [ "$output" = "/z/Transformers/Transformers 2 (2009).mkv" ]
}
