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
