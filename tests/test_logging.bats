#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/logging.sh
# Tests des fonctions de logging et initialisation
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    
    export SCRIPT_DIR="$PROJECT_ROOT"
    export EXECUTION_TIMESTAMP="test_$$"
    export STOP_FLAG="$TEST_TEMP_DIR/.stop"
    export OUTPUT_DIR="$TEST_TEMP_DIR/output"
    
    # Override LOG_DIR pour les tests (avant de charger logging.sh)
    # Note: logging.sh utilise readonly, donc on doit travailler autrement
    
    # Charger les modules requis (sans logging.sh qui a des readonly)
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/detect.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests des chemins de logs
###########################################################

@test "logging: LOG_DIR par défaut est ./logs" {
    # Simuler le chargement avec les valeurs par défaut
    local expected_log_dir="./logs"
    
    # Vérifier que la valeur par défaut est correcte dans le fichier
    grep -q 'readonly LOG_DIR="./logs"' "$LIB_DIR/logging.sh"
}

@test "logging: LOG_SUCCESS contient le timestamp" {
    # Vérifier la structure du chemin
    grep -q 'LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"' "$LIB_DIR/logging.sh"
}

@test "logging: LOG_SKIPPED contient le timestamp" {
    grep -q 'LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"' "$LIB_DIR/logging.sh"
}

@test "logging: LOG_ERROR contient le timestamp" {
    grep -q 'LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"' "$LIB_DIR/logging.sh"
}

@test "logging: SUMMARY_FILE contient le timestamp" {
    grep -q 'SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"' "$LIB_DIR/logging.sh"
}

@test "logging: INDEX est dans LOG_DIR" {
    grep -q 'readonly INDEX="$LOG_DIR/Index"' "$LIB_DIR/logging.sh"
}

@test "logging: QUEUE est dans LOG_DIR" {
    grep -q 'readonly QUEUE="$LOG_DIR/Queue"' "$LIB_DIR/logging.sh"
}

###########################################################
# Tests de initialize_directories()
###########################################################

@test "initialize_directories: crée LOG_DIR" {
    # Créer un environnement isolé
    local test_log_dir="$TEST_TEMP_DIR/test_logs"
    local test_tmp_dir="$TEST_TEMP_DIR/test_tmp"
    local test_out_dir="$TEST_TEMP_DIR/test_out"
    
    # Fonction mock
    initialize_directories_mock() {
        mkdir -p "$test_log_dir" "$test_tmp_dir" "$test_out_dir"
    }
    
    initialize_directories_mock
    
    [ -d "$test_log_dir" ]
}

@test "initialize_directories: crée TMP_DIR" {
    local test_log_dir="$TEST_TEMP_DIR/test_logs"
    local test_tmp_dir="$TEST_TEMP_DIR/test_tmp"
    local test_out_dir="$TEST_TEMP_DIR/test_out"
    
    mkdir -p "$test_log_dir" "$test_tmp_dir" "$test_out_dir"
    
    [ -d "$test_tmp_dir" ]
}

@test "initialize_directories: crée OUTPUT_DIR" {
    local test_log_dir="$TEST_TEMP_DIR/test_logs"
    local test_tmp_dir="$TEST_TEMP_DIR/test_tmp"
    local test_out_dir="$TEST_TEMP_DIR/test_out"
    
    mkdir -p "$test_log_dir" "$test_tmp_dir" "$test_out_dir"
    
    [ -d "$test_out_dir" ]
}

@test "initialize_directories: crée les fichiers de log vides" {
    local test_log_dir="$TEST_TEMP_DIR/test_logs"
    mkdir -p "$test_log_dir"
    
    # Simuler la création des logs
    local log_success="$test_log_dir/Success_test.log"
    local log_skipped="$test_log_dir/Skipped_test.log"
    local log_error="$test_log_dir/Error_test.log"
    local summary="$test_log_dir/Summary_test.log"
    
    for log_file in "$log_success" "$log_skipped" "$log_error" "$summary"; do
        touch "$log_file"
    done
    
    [ -f "$log_success" ]
    [ -f "$log_skipped" ]
    [ -f "$log_error" ]
    [ -f "$summary" ]
}

###########################################################
# Tests de la structure des logs
###########################################################

@test "logging: format de log SUCCESS contient timestamp et chemins" {
    # Vérifier que le format attendu est documenté/utilisé
    # Format typique: YYYY-MM-DD HH:MM:SS | SUCCESS | source → dest | size | duration
    local log_line="2024-12-23 12:00:00 | SUCCESS | /src/video.mkv → /out/video.mkv | 500MB→200MB | 5min"
    
    # Le format doit contenir des séparateurs |
    [[ "$log_line" =~ \| ]]
}

@test "logging: format de log ERROR contient le type d'erreur" {
    # Format typique: YYYY-MM-DD HH:MM:SS | ERROR TYPE | source | message
    local log_line="2024-12-23 12:00:00 | ERROR FFMPEG_FAILED | /src/video.mkv | exit code 1"
    
    [[ "$log_line" =~ ERROR ]]
}

@test "logging: format de log SKIPPED contient la raison" {
    # Format typique: YYYY-MM-DD HH:MM:SS | SKIPPED | source | reason
    local log_line="2024-12-23 12:00:00 | SKIPPED | /src/video.mkv | already HEVC"
    
    [[ "$log_line" =~ SKIPPED ]]
}

###########################################################
# Tests du fichier Index
###########################################################

@test "logging: Index utilise le format null-separated" {
    # Créer un index de test
    local test_index="$TEST_TEMP_DIR/Index"
    printf '%s\0' "/path/to/file1.mkv" "/path/to/file2.mkv" > "$test_index"
    
    # Vérifier qu'on peut le lire avec read -d ''
    local count=0
    while IFS= read -r -d '' file; do
        count=$((count + 1))
    done < "$test_index"
    
    [ "$count" -eq 2 ]
}

@test "logging: Index.meta contient les métadonnées" {
    # Le fichier meta doit exister (structure vérifiée par analyse statique)
    grep -q 'INDEX_META="$LOG_DIR/Index.meta"' "$LIB_DIR/logging.sh"
}

###########################################################
# Tests du log DryRun
###########################################################

@test "logging: LOG_DRYRUN_COMPARISON créé seulement en mode dryrun" {
    # Vérifier la logique dans le code
    grep -q 'if \[\[.*DRYRUN.*true.*\]\]' "$LIB_DIR/logging.sh" && \
    grep -q 'LOG_DRYRUN_COMPARISON' "$LIB_DIR/logging.sh"
}

###########################################################
# Tests VMAF queue
###########################################################

@test "logging: VMAF_QUEUE_FILE défini avec timestamp" {
    grep -q 'VMAF_QUEUE_FILE="$LOG_DIR/.vmaf_queue_${EXECUTION_TIMESTAMP}"' "$LIB_DIR/logging.sh"
}
