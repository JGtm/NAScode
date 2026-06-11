#!/usr/bin/env bats
###########################################################
# TESTS RÉGRESSION - Finalisation / transferts
# But: éviter le cas "sortie manquante" + résumé à 0.
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    # Environnement minimal
    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/utils.sh"

    # Logs isolés par test (ne pas dépendre de logging.sh qui force ./logs)
    export LOG_SUCCESS="$TEST_TEMP_DIR/success.log"
    export LOG_SKIPPED="$TEST_TEMP_DIR/skipped.log"
    export LOG_ERROR="$TEST_TEMP_DIR/error.log"
    export LOG_SESSION="$LOG_ERROR"
    export SUMMARY_FILE="$TEST_TEMP_DIR/summary.log"
    : > "$LOG_SUCCESS"
    : > "$LOG_SKIPPED"
    : > "$LOG_ERROR"
    : > "$SUMMARY_FILE"

    # Fichiers compteurs pour le gain de place
    export TOTAL_SIZE_BEFORE_FILE="$TEST_TEMP_DIR/.total_size_before"
    export TOTAL_SIZE_AFTER_FILE="$TEST_TEMP_DIR/.total_size_after"
    echo "0" > "$TOTAL_SIZE_BEFORE_FILE"
    echo "0" > "$TOTAL_SIZE_AFTER_FILE"

    # Désactiver les waits longs dans _finalize_try_move
    export MOVE_RETRY_MAX_TRY=1
    export MOVE_RETRY_SLEEP_SECONDS=0

    # Stubs pour éviter des dépendances
    process_vmaf_queue() { :; }

    # Charger les modules testés
    source "$LIB_DIR/summary.sh"
    source "$LIB_DIR/finalize.sh"
}

teardown() {
    teardown_test_env
}

@test "_finalize_try_move: fallback utilise bien le nom final et retourne 1" {
    export FALLBACK_DIR="$TEST_TEMP_DIR/fallback"

    local tmp_output="$TEST_TEMP_DIR/tmp_out.bin"
    printf 'data' > "$tmp_output"

    local final_output="$TEST_TEMP_DIR/does_not_exist/out.mkv"

    run _finalize_try_move "$tmp_output" "$final_output" "/src/orig.mkv"
    [ "$status" -eq 1 ]

    local expected="$FALLBACK_DIR/out.mkv"
    [ "$output" = "$expected" ]
    [ -f "$expected" ]
}

@test "_finalize_try_move: publie atomiquement et ne laisse pas de .partial" {
    local tmp_output="$TEST_TEMP_DIR/tmp_out.bin"
    printf 'hello world data' > "$tmp_output"

    local dest_dir="$TEST_TEMP_DIR/dest"
    mkdir -p "$dest_dir"
    local final_output="$dest_dir/out.mkv"

    run _finalize_try_move "$tmp_output" "$final_output" "/src/orig.mkv"
    [ "$status" -eq 0 ]
    [ "$output" = "$final_output" ]

    # Sortie publiée, intègre, et aucun artefact .partial / tmp résiduel
    [ -f "$final_output" ]
    [ ! -f "${final_output}.partial" ]
    [ ! -f "$tmp_output" ]
    [ "$(cat "$final_output")" = "hello world data" ]
}

@test "_finalize_try_move: taille incohérente → quarantaine .corrupt, ne publie pas (statut 3)" {
    # Stub déterministe par chemin (un compteur ne survivrait pas aux sous-shells
    # de substitution de commande) : la source tmp "pèse" 100, le .partial acheminé
    # "paraît" tronqué à 50 → mismatch détecté AVANT publication.
    get_file_size_bytes() {
        case "$1" in
            *.partial) echo 50 ;;
            *)         echo 100 ;;
        esac
    }

    local tmp_output="$TEST_TEMP_DIR/tmp_out.bin"
    printf 'data' > "$tmp_output"
    local dest_dir="$TEST_TEMP_DIR/dest"
    mkdir -p "$dest_dir"
    local final_output="$dest_dir/out.mkv"

    run _finalize_try_move "$tmp_output" "$final_output" "/src/orig.mkv"
    [ "$status" -eq 3 ]

    # La sortie finale n'est JAMAIS publiée ; pas de .partial résiduel
    [ ! -f "$final_output" ]
    [ ! -f "${final_output}.partial" ]
    # Un fichier de quarantaine existe et c'est le chemin retourné
    [[ "$output" == "${final_output}.corrupt-"* ]]
    ls "${dest_dir}"/out.mkv.corrupt-* >/dev/null 2>&1
}

@test "_finalize_log_and_verify: move_status=3 → ERROR QUARANTINED, ni SUCCESS ni queue VMAF" {
    local corrupt="$TEST_TEMP_DIR/out.mkv.corrupt-x"
    printf 'partialdata' > "$corrupt"  # 11 octets

    local tmp_input="$TEST_TEMP_DIR/tmp_in.bin"
    local ffmpeg_log_temp="$TEST_TEMP_DIR/ffmpeg.log"
    printf 'x' > "$tmp_input"
    printf 'log' > "$ffmpeg_log_temp"

    export VMAF_QUEUE_FILE="$TEST_TEMP_DIR/.vmaf_queue"
    : > "$VMAF_QUEUE_FILE"
    # Détecte tout appel indu à la mise en queue VMAF
    _queue_vmaf_analysis() { echo "QUEUED" >> "$VMAF_QUEUE_FILE"; }

    _finalize_log_and_verify "/src/orig.mkv" "$corrupt" "$tmp_input" "$ffmpeg_log_temp" "" 1 11 "$TEST_TEMP_DIR/out.mkv" 3

    # Erreur de quarantaine loggée
    run grep -F "| ERROR QUARANTINED |" "$LOG_SESSION"
    [ "$status" -eq 0 ]
    # Pas de SUCCESS pour un fichier quarantiné
    run grep -F "| SUCCESS |" "$LOG_SESSION"
    [ "$status" -ne 0 ]
    # Pas de mise en queue VMAF
    [ ! -s "$VMAF_QUEUE_FILE" ]
}

@test "_finalize_log_and_verify: fichier final manquant -> ERROR TRANSFER_FAILED et show_summary compte une erreur" {
    local tmp_input="$TEST_TEMP_DIR/tmp_in.bin"
    local ffmpeg_log_temp="$TEST_TEMP_DIR/ffmpeg.log"
    printf 'x' > "$tmp_input"
    printf 'ffmpeg' > "$ffmpeg_log_temp"

    # final_actual n'existe pas
    local final_actual="$TEST_TEMP_DIR/missing/out.mkv"

    # checksum/tailles "avant" (simulées)
    local checksum_before
    checksum_before=$(printf 'abc' | compute_sha256)

    run _finalize_log_and_verify "/src/orig.mkv" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "$checksum_before" 1 3 "$TEST_TEMP_DIR/expected/out.mkv" 0
    [ "$status" -eq 0 ]

    # Doit logger une erreur TRANSFER_FAILED
    run grep -F "| ERROR TRANSFER_FAILED |" "$LOG_ERROR"
    [ "$status" -eq 0 ]

    # Résumé: Erreurs >= 1 et pas de "Aucun fichier à traiter"
    export START_TS_TOTAL=1
    run show_summary
    [[ "$output" != *"Aucun fichier à traiter"* ]]

    # Le format du résumé utilise maintenant print_summary_item avec alignement
    run grep -E "Erreurs.*1" "$SUMMARY_FILE"
    [ "$status" -eq 0 ]

    # Le fichier résumé ne doit pas contenir de codes couleurs ANSI
    run grep -q $'\x1b' "$SUMMARY_FILE"
    [ "$status" -ne 0 ]
}

###########################################################
# Tests gain de place (space savings)
###########################################################

@test "_format_size_bytes: formate correctement les octets" {
    run _format_size_bytes 500
    [ "$output" = "500 octets" ]
}

@test "_format_size_bytes: formate correctement les Ko" {
    run _format_size_bytes 2048
    [[ "$output" =~ "2.00 Ko" ]]
}

@test "_format_size_bytes: formate correctement les Mo" {
    run _format_size_bytes 5242880
    [[ "$output" =~ "5.00 Mo" ]]
}

@test "_format_size_bytes: formate correctement les Go" {
    run _format_size_bytes 2147483648
    [[ "$output" =~ "2.00 Go" ]]
}

@test "_finalize_log_and_verify: incrémente les compteurs de taille sur succès" {
    # Créer un fichier "original" de 1000 octets
    local file_original="$TEST_TEMP_DIR/original.mkv"
    dd if=/dev/zero of="$file_original" bs=1000 count=1 2>/dev/null
    
    # Créer un fichier "converti" de 500 octets
    local final_actual="$TEST_TEMP_DIR/converted.mkv"
    dd if=/dev/zero of="$final_actual" bs=500 count=1 2>/dev/null
    
    local tmp_input="$TEST_TEMP_DIR/tmp_in.bin"
    local ffmpeg_log_temp="$TEST_TEMP_DIR/ffmpeg.log"
    touch "$tmp_input" "$ffmpeg_log_temp"
    
    # Initialiser les compteurs
    echo "0" > "$TOTAL_SIZE_BEFORE_FILE"
    echo "0" > "$TOTAL_SIZE_AFTER_FILE"
    
    # Appeler la fonction
    _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "" 1 0 "$final_actual" 0
    
    # Vérifier que les compteurs ont été incrémentés
    local before=$(cat "$TOTAL_SIZE_BEFORE_FILE")
    local after=$(cat "$TOTAL_SIZE_AFTER_FILE")
    
    [ "$before" -eq 1000 ]
    [ "$after" -eq 500 ]
}

@test "_finalize_log_and_verify: accumule les tailles sur plusieurs fichiers" {
    # Premier fichier : 1000 -> 400
    local file1="$TEST_TEMP_DIR/file1.mkv"
    local conv1="$TEST_TEMP_DIR/conv1.mkv"
    dd if=/dev/zero of="$file1" bs=1000 count=1 2>/dev/null
    dd if=/dev/zero of="$conv1" bs=400 count=1 2>/dev/null
    
    # Deuxième fichier : 2000 -> 800
    local file2="$TEST_TEMP_DIR/file2.mkv"
    local conv2="$TEST_TEMP_DIR/conv2.mkv"
    dd if=/dev/zero of="$file2" bs=2000 count=1 2>/dev/null
    dd if=/dev/zero of="$conv2" bs=800 count=1 2>/dev/null
    
    local tmp="$TEST_TEMP_DIR/tmp.bin"
    local log="$TEST_TEMP_DIR/log.txt"
    touch "$tmp" "$log"
    
    echo "0" > "$TOTAL_SIZE_BEFORE_FILE"
    echo "0" > "$TOTAL_SIZE_AFTER_FILE"
    
    # Simuler deux conversions
    _finalize_log_and_verify "$file1" "$conv1" "$tmp" "$log" "" 1 0 "$conv1" 0
    touch "$tmp" "$log"  # Recréer car supprimés
    _finalize_log_and_verify "$file2" "$conv2" "$tmp" "$log" "" 2 0 "$conv2" 0
    
    local before=$(cat "$TOTAL_SIZE_BEFORE_FILE")
    local after=$(cat "$TOTAL_SIZE_AFTER_FILE")
    
    # Total : 3000 -> 1200
    [ "$before" -eq 3000 ]
    [ "$after" -eq 1200 ]
}

@test "show_summary: affiche l'espace économisé quand des fichiers ont été convertis" {
    # Simuler des conversions réussies
    echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | /src/a.mkv → /out/a.mkv | 100MB → 40MB" >> "$LOG_SUCCESS"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | /src/b.mkv → /out/b.mkv | 200MB → 80MB" >> "$LOG_SUCCESS"
    
    # Simuler les compteurs (300 Mo -> 120 Mo = 180 Mo économisés, 60%)
    echo "314572800" > "$TOTAL_SIZE_BEFORE_FILE"  # 300 Mo
    echo "125829120" > "$TOTAL_SIZE_AFTER_FILE"   # 120 Mo
    
    export START_TS_TOTAL=1
    run show_summary
    
    # Vérifier que l'espace économisé est affiché
    [[ "$output" =~ "Espace économisé" ]]
    [[ "$output" =~ "Mo" ]]
}

@test "show_summary: n'affiche pas l'espace économisé si aucune conversion" {
    # Pas de SUCCESS dans les logs
    echo "0" > "$TOTAL_SIZE_BEFORE_FILE"
    echo "0" > "$TOTAL_SIZE_AFTER_FILE"
    
    export START_TS_TOTAL=1
    run show_summary
    
    # Ne doit pas afficher "Espace économisé"
    [[ "$output" != *"Espace économisé"* ]]
}

@test "show_summary: VMAF NA est compté comme anomalie" {
    # Forcer le rendu non-compact pour une vérification stable via SUMMARY_FILE
    export COLUMNS=999
    export VMAF_ENABLED=true

    # Simuler deux lignes VMAF dans le log de session (LOG_SESSION=$LOG_ERROR dans setup)
    echo "$(date '+%Y-%m-%d %H:%M:%S') | VMAF | /src/a.mkv → /out/a.mkv | score:NA | quality:NA" >> "$LOG_SESSION"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | VMAF | /src/b.mkv → /out/b.mkv | score:65.00 | quality:DEGRADE" >> "$LOG_SESSION"

    export START_TS_TOTAL=1
    run show_summary
    [ "$status" -eq 0 ]

    # Doit afficher une anomalie VMAF=2
    run grep -E "VMAF.*2" "$SUMMARY_FILE"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests --keep-metadata (préservation mtime/atime)
###########################################################

# Helper : retourne mtime epoch d'un fichier (portable Linux/macOS).
_get_mtime() {
    local f="$1"
    stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null
}

@test "_finalize_preserve_mtime: KEEP_METADATA=false → ne fait rien et retourne 1" {
    export KEEP_METADATA=false

    local src="$TEST_TEMP_DIR/source.mkv"
    local dst="$TEST_TEMP_DIR/dest.mkv"
    : > "$src"
    sleep 1
    : > "$dst"

    local mtime_dst_before
    mtime_dst_before=$(_get_mtime "$dst")

    run _finalize_preserve_mtime "$src" "$dst"
    [ "$status" -eq 1 ]

    # mtime non modifié
    local mtime_dst_after
    mtime_dst_after=$(_get_mtime "$dst")
    [ "$mtime_dst_before" = "$mtime_dst_after" ]

    # Aucune trace KEEP_METADATA dans les logs
    run grep -F "KEEP_METADATA" "$LOG_SESSION"
    [ "$status" -ne 0 ]
}

@test "_finalize_preserve_mtime: KEEP_METADATA=true réplique le mtime de la source" {
    export KEEP_METADATA=true

    local src="$TEST_TEMP_DIR/source.mkv"
    local dst="$TEST_TEMP_DIR/dest.mkv"
    : > "$src"
    # Forcer un mtime ancien sur la source
    touch -t 202001011200.00 "$src"
    sleep 1
    : > "$dst"

    local mtime_src
    mtime_src=$(_get_mtime "$src")
    local mtime_dst_before
    mtime_dst_before=$(_get_mtime "$dst")
    [ "$mtime_src" != "$mtime_dst_before" ]

    run _finalize_preserve_mtime "$src" "$dst"
    [ "$status" -eq 0 ]

    local mtime_dst_after
    mtime_dst_after=$(_get_mtime "$dst")
    [ "$mtime_dst_after" = "$mtime_src" ]

    # Trace OK loggée
    run grep -F "| KEEP_METADATA |" "$LOG_SESSION"
    [ "$status" -eq 0 ]
    run grep -F "status:OK" "$LOG_SESSION"
    [ "$status" -eq 0 ]
}

@test "_finalize_preserve_mtime: source manquante → SKIPPED loggé, pas d'erreur" {
    export KEEP_METADATA=true

    local src="$TEST_TEMP_DIR/missing_src.mkv"  # n'existe pas
    local dst="$TEST_TEMP_DIR/dest.mkv"
    : > "$dst"

    run _finalize_preserve_mtime "$src" "$dst"
    [ "$status" -eq 1 ]

    run grep -E "KEEP_METADATA.*status:SKIPPED.*reason:source_missing" "$LOG_SESSION"
    [ "$status" -eq 0 ]
    # Pas de ligne ERROR KEEP_METADATA
    run grep -F "ERROR KEEP_METADATA" "$LOG_SESSION"
    [ "$status" -ne 0 ]
}

@test "_finalize_preserve_mtime: cible manquante → ERROR KEEP_METADATA loggé" {
    export KEEP_METADATA=true

    local src="$TEST_TEMP_DIR/source.mkv"
    : > "$src"
    local dst="$TEST_TEMP_DIR/missing_target.mkv"  # n'existe pas

    run _finalize_preserve_mtime "$src" "$dst"
    [ "$status" -eq 1 ]

    run grep -E "ERROR KEEP_METADATA.*reason:target_missing" "$LOG_SESSION"
    [ "$status" -eq 0 ]
}

@test "_finalize_log_and_verify: KEEP_METADATA=true propage le mtime sur le fichier final" {
    export KEEP_METADATA=true

    # Source de référence avec mtime ancien
    local file_original="$TEST_TEMP_DIR/original.mkv"
    dd if=/dev/zero of="$file_original" bs=1000 count=1 2>/dev/null
    touch -t 202101011200.00 "$file_original"

    # Fichier final déjà déplacé (taille identique pour éviter SIZE_MISMATCH)
    local final_actual="$TEST_TEMP_DIR/converted.mkv"
    dd if=/dev/zero of="$final_actual" bs=1000 count=1 2>/dev/null

    local tmp_input="$TEST_TEMP_DIR/tmp_in.bin"
    local ffmpeg_log_temp="$TEST_TEMP_DIR/ffmpeg.log"
    touch "$tmp_input" "$ffmpeg_log_temp"

    local mtime_src
    mtime_src=$(_get_mtime "$file_original")

    # Pas de checksum_before → verify_status="SKIPPED" (déclenche quand même la copie mtime)
    _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "" 1 1000 "$final_actual" 0

    local mtime_dst
    mtime_dst=$(_get_mtime "$final_actual")
    [ "$mtime_dst" = "$mtime_src" ]

    run grep -F "| KEEP_METADATA |" "$LOG_SESSION"
    [ "$status" -eq 0 ]
}

@test "_finalize_log_and_verify: KEEP_METADATA=false n'altère pas le mtime du fichier final" {
    export KEEP_METADATA=false

    local file_original="$TEST_TEMP_DIR/original.mkv"
    dd if=/dev/zero of="$file_original" bs=1000 count=1 2>/dev/null
    touch -t 202101011200.00 "$file_original"

    local final_actual="$TEST_TEMP_DIR/converted.mkv"
    dd if=/dev/zero of="$final_actual" bs=1000 count=1 2>/dev/null

    local tmp_input="$TEST_TEMP_DIR/tmp_in.bin"
    local ffmpeg_log_temp="$TEST_TEMP_DIR/ffmpeg.log"
    touch "$tmp_input" "$ffmpeg_log_temp"

    local mtime_src
    mtime_src=$(_get_mtime "$file_original")
    local mtime_dst_before
    mtime_dst_before=$(_get_mtime "$final_actual")

    _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "" 1 1000 "$final_actual" 0

    local mtime_dst_after
    mtime_dst_after=$(_get_mtime "$final_actual")
    # mtime n'a pas pris la valeur de la source
    [ "$mtime_dst_after" != "$mtime_src" ] || [ "$mtime_dst_before" = "$mtime_src" ]
    # Et n'a pas changé par effet de bord
    [ "$mtime_dst_after" = "$mtime_dst_before" ]

    # Aucune trace KEEP_METADATA
    run grep -F "KEEP_METADATA" "$LOG_SESSION"
    [ "$status" -ne 0 ]
}
