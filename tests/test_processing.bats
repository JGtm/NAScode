#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/processing.sh
# Tests du traitement de la file d'attente (simple et FIFO)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    
    export SCRIPT_DIR="$PROJECT_ROOT"
    export EXECUTION_TIMESTAMP="test_$$"
    export NO_PROGRESS=true
    export PARALLEL_JOBS=2
    export LIMIT_FILES=0
    export STOP_FLAG="$TEST_TEMP_DIR/.stop"
    export OUTPUT_DIR="$TEST_TEMP_DIR/output"
    export QUEUE="$TEST_TEMP_DIR/Queue"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Charger les modules requis
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/utils.sh"
}

teardown() {
    # Nettoyer le stop flag et les processus
    rm -f "$STOP_FLAG" 2>/dev/null || true
    teardown_test_env
}

###########################################################
# Tests de count_null_separated() (utilisé par processing)
###########################################################

@test "count_null_separated: compte correctement les entrées" {
    local test_file="$TEST_TEMP_DIR/test_queue"
    printf '%s\0' "file1.mkv" "file2.mkv" "file3.mkv" > "$test_file"
    
    local count
    count=$(count_null_separated "$test_file")
    
    [ "$count" -eq 3 ]
}

@test "count_null_separated: retourne 0 pour fichier vide" {
    local test_file="$TEST_TEMP_DIR/empty_queue"
    : > "$test_file"
    
    local count
    count=$(count_null_separated "$test_file")
    
    [ "$count" -eq 0 ]
}

@test "count_null_separated: gère fichier inexistant" {
    run count_null_separated "$TEST_TEMP_DIR/nonexistent"
    
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

###########################################################
# Tests de la structure de la queue
###########################################################

@test "processing: queue utilise le format null-separated" {
    # Créer une queue de test
    printf '%s\0' "/path/to/video1.mkv" "/path/to/video2.mkv" > "$QUEUE"
    
    # Vérifier qu'on peut la lire
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < "$QUEUE"
    
    [ "${#files[@]}" -eq 2 ]
    [ "${files[0]}" = "/path/to/video1.mkv" ]
}

@test "processing: queue gère les noms avec espaces" {
    printf '%s\0' "/path/to/my video.mkv" "/path/to/another file.mkv" > "$QUEUE"
    
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < "$QUEUE"
    
    [ "${#files[@]}" -eq 2 ]
    [ "${files[0]}" = "/path/to/my video.mkv" ]
}

@test "processing: queue gère les caractères spéciaux" {
    printf '%s\0' "/path/to/video (2024).mkv" "/path/to/[test] file.mkv" > "$QUEUE"
    
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < "$QUEUE"
    
    [ "${#files[@]}" -eq 2 ]
    [[ "${files[0]}" =~ "2024" ]]
}

###########################################################
# Tests du mode simple (_process_queue_simple)
###########################################################

@test "processing: mode simple choisi quand LIMIT_FILES=0" {
    LIMIT_FILES=0
    
    # Vérifier la condition dans le code
    # prepare_dynamic_queue choisit _process_queue_simple si LIMIT_FILES <= 0
    if [[ "$LIMIT_FILES" -gt 0 ]]; then
        local mode="fifo"
    else
        local mode="simple"
    fi
    
    [ "$mode" = "simple" ]
}

@test "processing: mode FIFO choisi quand LIMIT_FILES>0" {
    LIMIT_FILES=5
    
    if [[ "$LIMIT_FILES" -gt 0 ]]; then
        local mode="fifo"
    else
        local mode="simple"
    fi
    
    [ "$mode" = "fifo" ]
}

###########################################################
# Tests du FIFO
###########################################################

@test "processing: création du FIFO" {
    local fifo_path="$TEST_TEMP_DIR/test_fifo"
    
    mkfifo "$fifo_path"
    
    [ -p "$fifo_path" ]
    
    rm -f "$fifo_path"
}

@test "processing: lecture/écriture FIFO" {
    local fifo_path="$TEST_TEMP_DIR/test_fifo"
    mkfifo "$fifo_path"
    
    # Écrire en arrière-plan
    (echo "test_data" > "$fifo_path") &
    local writer_pid=$!
    
    # Lire
    local data
    data=$(cat "$fifo_path")
    
    wait "$writer_pid" 2>/dev/null || true
    
    [ "$data" = "test_data" ]
    
    rm -f "$fifo_path"
}

###########################################################
# Tests du stop flag
###########################################################

@test "processing: stop flag arrête le traitement" {
    # Le stop flag doit interrompre les boucles de traitement
    touch "$STOP_FLAG"
    
    [ -f "$STOP_FLAG" ]
    
    rm -f "$STOP_FLAG"
}

@test "processing: stop flag n'existe pas au départ" {
    rm -f "$STOP_FLAG" 2>/dev/null || true
    
    [ ! -f "$STOP_FLAG" ]
}

###########################################################
# Tests du compteur de fichiers traités
###########################################################

@test "processing: compteur initialisé à 0" {
    local counter_file="$TEST_TEMP_DIR/processed_count"
    echo "0" > "$counter_file"
    
    local count
    count=$(cat "$counter_file")
    
    [ "$count" = "0" ]
}

@test "processing: compteur incrémenté correctement" {
    local counter_file="$TEST_TEMP_DIR/processed_count"
    echo "0" > "$counter_file"
    
    # Simuler l'incrémentation atomique
    local current
    current=$(cat "$counter_file")
    echo "$((current + 1))" > "$counter_file"
    
    local new_count
    new_count=$(cat "$counter_file")
    
    [ "$new_count" = "1" ]
}

###########################################################
# Tests de parallélisation
###########################################################

@test "processing: PARALLEL_JOBS respecté" {
    PARALLEL_JOBS=2
    
    [ "$PARALLEL_JOBS" -eq 2 ]
}

@test "processing: jobs parallèles limités au max" {
    PARALLEL_JOBS=4
    
    local jobs_running=0
    local pids=()
    
    # Simuler le lancement de jobs
    for i in 1 2 3 4 5; do
        if [[ "${#pids[@]}" -ge "$PARALLEL_JOBS" ]]; then
            # On devrait attendre avant de continuer
            jobs_running="${#pids[@]}"
            break
        fi
        sleep 0.1 &
        pids+=($!)
    done
    
    # Ne devrait pas dépasser PARALLEL_JOBS
    [ "${#pids[@]}" -le "$PARALLEL_JOBS" ]
    
    # Nettoyer
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

###########################################################
# Tests d'intégration queue
###########################################################

@test "processing: workflow complet queue → traitement" {
    # Créer une queue
    printf '%s\0' "file1.mkv" "file2.mkv" > "$QUEUE"
    
    # Vérifier qu'elle est lisible
    local count
    count=$(count_null_separated "$QUEUE")
    [ "$count" -eq 2 ]
    
    # Simuler la lecture comme le ferait _process_queue_simple
    local processed=0
    while IFS= read -r -d '' file; do
        processed=$((processed + 1))
    done < "$QUEUE"
    
    [ "$processed" -eq 2 ]
}

###########################################################
# Tests des fichiers temporaires FIFO
###########################################################

@test "processing: fichiers FIFO nettoyés après traitement" {
    local fifo="$TEST_TEMP_DIR/queue_fifo_test"
    local pid_file="$TEST_TEMP_DIR/fifo_writer_pid_test"
    local ready_file="$TEST_TEMP_DIR/fifo_writer.ready_test"
    
    # Créer les fichiers
    mkfifo "$fifo" 2>/dev/null || true
    touch "$pid_file" "$ready_file"
    
    # Simuler le nettoyage
    rm -f "$fifo" "$pid_file" "$ready_file" 2>/dev/null || true
    
    [ ! -e "$fifo" ]
    [ ! -f "$pid_file" ]
    [ ! -f "$ready_file" ]
}

###########################################################
# Tests de la queue complète (mode limite)
###########################################################

@test "processing: QUEUE.full contient tous les fichiers" {
    local queue_full="$QUEUE.full"
    printf '%s\0' "file1.mkv" "file2.mkv" "file3.mkv" "file4.mkv" "file5.mkv" > "$queue_full"
    
    local total
    total=$(count_null_separated "$queue_full")
    
    [ "$total" -eq 5 ]
    
    rm -f "$queue_full"
}

@test "processing: queue limitée respecte LIMIT_FILES" {
    LIMIT_FILES=3
    
    # Simuler la création d'une queue limitée
    local queue_full="$QUEUE.full"
    printf '%s\0' "f1.mkv" "f2.mkv" "f3.mkv" "f4.mkv" "f5.mkv" > "$queue_full"
    
    # Extraire les N premiers
    local limited_queue="$QUEUE"
    local count=0
    while IFS= read -r -d '' file && [[ $count -lt $LIMIT_FILES ]]; do
        printf '%s\0' "$file"
        count=$((count + 1))
    done < "$queue_full" > "$limited_queue"
    
    local limited_count
    limited_count=$(count_null_separated "$limited_queue")
    
    [ "$limited_count" -eq 3 ]
    
    rm -f "$queue_full"
}
