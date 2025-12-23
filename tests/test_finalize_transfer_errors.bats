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
    source "$LIB_DIR/colors.sh"
    source "$LIB_DIR/utils.sh"

    # Logs isolés par test (ne pas dépendre de logging.sh qui force ./logs)
    export LOG_SUCCESS="$TEST_TEMP_DIR/success.log"
    export LOG_SKIPPED="$TEST_TEMP_DIR/skipped.log"
    export LOG_ERROR="$TEST_TEMP_DIR/error.log"
    export SUMMARY_FILE="$TEST_TEMP_DIR/summary.log"
    : > "$LOG_SUCCESS"
    : > "$LOG_SKIPPED"
    : > "$LOG_ERROR"
    : > "$SUMMARY_FILE"

    # Désactiver les waits longs dans _finalize_try_move
    export MOVE_RETRY_MAX_TRY=1
    export MOVE_RETRY_SLEEP_SECONDS=0

    # Stubs pour éviter des dépendances
    process_vmaf_queue() { :; }

    # Charger le module testé
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
}
