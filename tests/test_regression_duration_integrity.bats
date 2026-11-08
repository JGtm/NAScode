#!/usr/bin/env bats
###########################################################
# TESTS RÉGRESSION - Sorties tronquées
# Une copie NAS interrompue produisait un film coupé, logué SUCCESS, puis
# ignoré à chaque run ; un sous-titre trop long déclenchait de fausses alertes.
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/media_probe.sh"
    source "$LIB_DIR/finalize.sh"
    source "$LIB_DIR/conversion_prep.sh"

    export LOG_SESSION="$TEST_TEMP_DIR/session.log"
    : > "$LOG_SESSION"
    export STOP_FLAG="$TEST_TEMP_DIR/stop"
    export SAMPLE_MODE=false DRYRUN=false LIMIT_FILES=0

    SRC="$TEST_TEMP_DIR/source.mkv"
    TMP_IN="$TEST_TEMP_DIR/tmp.in.mkv"
    TMP_OUT="$TEST_TEMP_DIR/tmp.out.mkv"
    FFLOG="$TEST_TEMP_DIR/ffmpeg.log"
    echo src > "$SRC"
    echo in > "$TMP_IN"
    echo out > "$TMP_OUT"
    echo log > "$FFLOG"
    export DUR_SRC=7174.688 DUR_IN=7174.688 DUR_OUT=7174.700

    # Simule ffprobe selon le fichier interrogé (dernier argument).
    ffprobe_safe() {
        case "${*: -1}" in
            "$SRC") echo "duration=$DUR_SRC" ;;
            "$TMP_IN") echo "duration=$DUR_IN" ;;
            *) echo "duration=$DUR_OUT" ;;
        esac
    }
}

teardown() {
    teardown_test_env
}

###########################################################
# Lecture de la durée vidéo
###########################################################

@test "get_video_duration_seconds: lit le tag DURATION d'un MKV" {
    ffprobe_safe() { printf 'duration=N/A\r\nTAG:DURATION=01:52:33.459000000\r\n'; }
    run get_video_duration_seconds "$SRC"
    [ "$output" = "6753.459" ]
}

@test "get_video_duration_seconds: accepte un tag suffixé par la langue" {
    ffprobe_safe() { printf 'duration=N/A\nTAG:language=eng\nTAG:DURATION-eng=00:00:10.500000000\n'; }
    run get_video_duration_seconds "$SRC"
    [ "$output" = "10.500" ]
}

@test "get_video_duration_seconds: sans tag, dernier paquet vidéo plutôt que le conteneur" {
    ffprobe_safe() {
        case "$*" in
            *packet=pts_time*) printf '6753.000\n6753.417\n6753.250\n' ;;
            *format=duration*) echo "7056.666" ;;
            *) echo "duration=N/A" ;;
        esac
    }
    run get_video_duration_seconds "$SRC"
    [ "$output" = "6753.417" ]
}

@test "get_video_duration_seconds: durée du conteneur en dernier recours" {
    ffprobe_safe() {
        case "$*" in
            *format=duration*) echo "42.5" ;;
            *) : ;;
        esac
    }
    run get_video_duration_seconds "$SRC"
    [ "$output" = "42.5" ]
}

@test "get_video_duration_seconds: fichier réel, un sous-titre trop long ne compte pas" {
    command -v ffmpeg >/dev/null 2>&1 || skip "ffmpeg absent"
    ffprobe_safe() { ffprobe "$@"; }

    local srt="$TEST_TEMP_DIR/long.srt" mkv="$TEST_TEMP_DIR/long.mkv"
    printf '1\n00:00:30,000 --> 00:00:40,000\nFin\n\n' > "$srt"
    ffmpeg -nostdin -v error -y -f lavfi -i color=c=black:s=64x64:r=10:d=3 -i "$srt" \
        -map 0:v -map 1:s -c:v mpeg4 -c:s srt "$mkv"

    run get_video_duration_seconds "$mkv"
    [ "$status" -eq 0 ]
    awk -v d="$output" 'BEGIN { exit (d > 2.5 && d < 3.5) ? 0 : 1 }'
}

###########################################################
# Comparaison
###########################################################

@test "compare_video_durations: tolère 2 s sur un fichier court" {
    export DUR_SRC=60 DUR_OUT=61.5
    run compare_video_durations "$SRC" "$TMP_OUT"
    [ "$status" -eq 0 ]
}

@test "compare_video_durations: un film de 2 h amputé de 30 s est détecté" {
    export DUR_SRC=7200 DUR_OUT=7170
    run compare_video_durations "$SRC" "$TMP_OUT"
    [ "$status" -eq 1 ]
    [ "$output" = "7200.000|7170.000" ]
}

@test "compare_video_durations: durée illisible → code 2" {
    export DUR_OUT=""
    run compare_video_durations "$SRC" "$TMP_OUT"
    [ "$status" -eq 2 ]
}

###########################################################
# Copie vers le stockage temporaire
###########################################################

@test "custom_pv: copie complète → succès" {
    head -c 5000 /dev/zero > "$TEST_TEMP_DIR/a.bin"
    run custom_pv "$TEST_TEMP_DIR/a.bin" "$TEST_TEMP_DIR/b.bin" ""
    [ "$status" -eq 0 ]
    [ "$(get_file_size_bytes "$TEST_TEMP_DIR/b.bin")" -eq 5000 ]
}

@test "custom_pv: dd en échec → erreur et copie partielle supprimée" {
    head -c 5000 /dev/zero > "$TEST_TEMP_DIR/a.bin"
    dd() { head -c 100 /dev/zero > "$TEST_TEMP_DIR/b.bin"; return 1; }
    run custom_pv "$TEST_TEMP_DIR/a.bin" "$TEST_TEMP_DIR/b.bin" ""
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_TEMP_DIR/b.bin" ]
}

@test "custom_pv: copie courte malgré un code 0 → erreur" {
    head -c 5000 /dev/zero > "$TEST_TEMP_DIR/a.bin"
    dd() { head -c 100 /dev/zero > "$TEST_TEMP_DIR/b.bin"; return 0; }
    run custom_pv "$TEST_TEMP_DIR/a.bin" "$TEST_TEMP_DIR/b.bin" ""
    [ "$status" -eq 1 ]
    [ ! -e "$TEST_TEMP_DIR/b.bin" ]
}

###########################################################
# Contrôle après encodage
###########################################################

@test "_finalize_output_duration_ok: sortie complète → poursuite" {
    run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 0 ]
    [ -f "$TMP_OUT" ]
    [ ! -s "$LOG_SESSION" ]
}

@test "_finalize_output_duration_ok: sortie tronquée → rejetée et jamais SUCCESS" {
    export DUR_OUT=3314.311
    run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 1 ]
    [ ! -e "$TMP_OUT" ]
    grep -q "ERROR DURATION | $SRC | source:7174.688s output:3314.311s" "$LOG_SESSION"
    ! grep -q "SUCCESS" "$LOG_SESSION"
}

@test "_finalize_output_duration_ok: sortie illisible → rejetée" {
    export DUR_OUT=""
    run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 1 ]
    [ ! -e "$TMP_OUT" ]
}

@test "_finalize_output_duration_ok: source illisible → comparaison à la copie locale" {
    export DUR_SRC="" DUR_OUT=3314.311
    run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 1 ]
    grep -q "ERROR DURATION" "$LOG_SESSION"
}

@test "_finalize_output_duration_ok: aucune référence lisible → publié avec avertissement" {
    export DUR_SRC="" DUR_IN=""
    run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 0 ]
    [ -f "$TMP_OUT" ]
    grep -q "DURATION_UNVERIFIED" "$LOG_SESSION"
}

@test "_finalize_output_duration_ok: mode extrait et arrêt demandé ne sont pas contrôlés" {
    export DUR_OUT=30
    SAMPLE_MODE=true run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 0 ]
    touch "$STOP_FLAG"
    run _finalize_output_duration_ok "$SRC" "$TMP_IN" "$TMP_OUT" "$FFLOG"
    [ "$status" -eq 0 ]
    [ -f "$TMP_OUT" ]
}

###########################################################
# Sortie déjà présente au lancement
###########################################################

@test "_check_output_exists: sortie complète → skip" {
    run _check_output_exists "$SRC" "film.mkv" "$TMP_OUT"
    [ "$status" -eq 0 ]
    [ -f "$TMP_OUT" ]
    grep -q "SKIPPED (Output file exists)" "$LOG_SESSION"
}

@test "_check_output_exists: sortie tronquée → écartée puis reconvertie" {
    export DUR_OUT=3314.311
    run _check_output_exists "$SRC" "film.mkv" "$TMP_OUT"
    [ "$status" -eq 1 ]
    [ ! -e "$TMP_OUT" ]
    ls "$TMP_OUT".corrupt-* >/dev/null
    grep -q "INCOMPLETE_OUTPUT" "$LOG_SESSION"
    ! grep -q "SKIPPED" "$LOG_SESSION"
}

@test "_check_output_exists: durée illisible → sortie conservée et skip" {
    export DUR_SRC=""
    run _check_output_exists "$SRC" "film.mkv" "$TMP_OUT"
    [ "$status" -eq 0 ]
    [ -f "$TMP_OUT" ]
}
