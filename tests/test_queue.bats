#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/queue.sh
# Tests des fonctions de gestion de file d'attente
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    
    # Charger les modules une seule fois (évite les conflits readonly)
    if [[ -z "${_QUEUE_TEST_LOADED:-}" ]]; then
        export SCRIPT_DIR="$PROJECT_ROOT"
        source "$LIB_DIR/ui.sh"
        source "$LIB_DIR/config.sh"
        source "$LIB_DIR/utils.sh"
        source "$LIB_DIR/queue.sh"
        _QUEUE_TEST_LOADED=1
    fi
    
    # Créer un répertoire temporaire pour les tests
    TEST_QUEUE_DIR="$TMP_DIR/queue_tests_$$"
    mkdir -p "$TEST_QUEUE_DIR"
    
    # Créer une structure de fichiers vidéo simulée
    TEST_VIDEO_DIR="$TEST_QUEUE_DIR/videos"
    mkdir -p "$TEST_VIDEO_DIR/season1"
    mkdir -p "$TEST_VIDEO_DIR/season2"
    
    # Créer des fichiers vidéo factices
    echo "video1" > "$TEST_VIDEO_DIR/movie.mkv"
    echo "video2" > "$TEST_VIDEO_DIR/season1/ep01.mkv"
    echo "video3" > "$TEST_VIDEO_DIR/season1/ep02.mkv"
    echo "video4" > "$TEST_VIDEO_DIR/season2/ep01.mp4"
    
    # Configurer les variables modifiables pour les tests
    SOURCE="$TEST_VIDEO_DIR"
    OUTPUT_DIR="$TEST_QUEUE_DIR/output"
    LOG_DIR="$TEST_QUEUE_DIR/logs"
    INDEX="$LOG_DIR/Index"
    INDEX_READABLE="$LOG_DIR/Index_readable.txt"
    INDEX_META="$LOG_DIR/Index.meta"
    QUEUE="$LOG_DIR/Queue"
    QUEUE_FULL="$LOG_DIR/Queue.full"
    EXCLUDES=()
    EXCLUDES_REGEX=""
    SORT_MODE="name_asc"
    LIMIT_FILES=0
    RANDOM_MODE=false
    KEEP_INDEX=false
    NO_PROGRESS=true
    MIN_SIZE_BYTES=0
    
    mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
}

teardown() {
    rm -rf "$TEST_QUEUE_DIR" 2>/dev/null || true
    teardown_test_env
}

###########################################################
# Tests de validate_queue_file()
###########################################################

@test "validate_queue_file: retourne erreur si fichier n'existe pas" {
    run validate_queue_file "/nonexistent/file.queue"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "n'existe pas" ]]
}

@test "validate_queue_file: retourne erreur si fichier vide" {
    touch "$TEST_QUEUE_DIR/empty.queue"
    
    run validate_queue_file "$TEST_QUEUE_DIR/empty.queue"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "vide" ]]
}

@test "validate_queue_file: accepte un fichier queue valide" {
    # Créer une queue valide (null-separated)
    printf '%s\0' "file1.mkv" "file2.mkv" > "$TEST_QUEUE_DIR/valid.queue"
    
    run validate_queue_file "$TEST_QUEUE_DIR/valid.queue"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "validé" ]] || [[ "$output" =~ "valide" ]]
}

###########################################################
# Tests de _normalize_source_path()
###########################################################

@test "_normalize_source_path: supprime le slash final" {
    local result
    result=$(_normalize_source_path "/path/to/dir/")
    [[ "$result" != */ ]]
}

@test "_normalize_source_path: gère les chemins relatifs" {
    # Créer un répertoire de test
    mkdir -p "$TEST_QUEUE_DIR/subdir"
    cd "$TEST_QUEUE_DIR"
    
    local result
    result=$(_normalize_source_path "./subdir")
    
    # Le résultat doit être un chemin absolu
    [[ "$result" = /* ]] || [[ "$result" =~ ^[A-Z]: ]]
}

###########################################################
# Tests de _validate_index_source()
###########################################################

@test "_validate_index_source: retourne 1 si pas de métadonnées" {
    rm -f "$INDEX_META"
    
    run _validate_index_source
    [ "$status" -eq 1 ]
}

@test "_validate_index_source: retourne 0 si source correspond" {
    # Créer les métadonnées avec la bonne source
    echo "SOURCE=$SOURCE" > "$INDEX_META"
    
    run _validate_index_source
    [ "$status" -eq 0 ]
}

@test "_validate_index_source: retourne 1 si source différente" {
    # Créer les métadonnées avec une source différente
    echo "SOURCE=/different/path" > "$INDEX_META"
    
    run _validate_index_source
    [ "$status" -eq 1 ]
}

###########################################################
# Tests de _save_index_metadata()
###########################################################

@test "_save_index_metadata: crée le fichier de métadonnées" {
    rm -f "$INDEX_META"
    
    _save_index_metadata
    
    [ -f "$INDEX_META" ]
    grep -q "SOURCE=$SOURCE" "$INDEX_META"
    grep -q "CREATED=" "$INDEX_META"
    grep -q "OUTPUT_DIR=$OUTPUT_DIR" "$INDEX_META"
}

@test "_validate_index_source: supprime l'index si REGENERATE_INDEX=true" {
    touch "$INDEX" "$INDEX_READABLE" "$INDEX_META"
    REGENERATE_INDEX=true
    
    run _validate_index_source
    
    [ "$status" -eq 1 ]
    [ ! -f "$INDEX" ]
    [ ! -f "$INDEX_READABLE" ]
    [ ! -f "$INDEX_META" ]
}

###########################################################
# Tests de _build_queue_from_index()
###########################################################

@test "_build_queue_from_index: trie par nom ascendant" {
    # Créer un index avec des tailles et chemins
    echo -e "100\t$TEST_VIDEO_DIR/b_file.mkv" > "$INDEX"
    echo -e "200\t$TEST_VIDEO_DIR/a_file.mkv" >> "$INDEX"
    echo -e "150\t$TEST_VIDEO_DIR/c_file.mkv" >> "$INDEX"
    
    SORT_MODE="name_asc"
    _build_queue_from_index
    
    # Vérifier l'ordre (a, b, c)
    local first
    first=$(tr '\0' '\n' < "$QUEUE" | head -1)
    [[ "$first" =~ "a_file.mkv" ]]
}

@test "_build_queue_from_index: trie par taille décroissante" {
    echo -e "100\t$TEST_VIDEO_DIR/small.mkv" > "$INDEX"
    echo -e "300\t$TEST_VIDEO_DIR/large.mkv" >> "$INDEX"
    echo -e "200\t$TEST_VIDEO_DIR/medium.mkv" >> "$INDEX"
    
    SORT_MODE="size_desc"
    _build_queue_from_index
    
    # Le plus gros en premier
    local first
    first=$(tr '\0' '\n' < "$QUEUE" | head -1)
    [[ "$first" =~ "large.mkv" ]]
}

@test "_build_queue_from_index: applique MIN_SIZE_BYTES (filtre taille)" {
    echo -e "100\t$TEST_VIDEO_DIR/small.mkv" > "$INDEX"
    echo -e "300\t$TEST_VIDEO_DIR/large.mkv" >> "$INDEX"
    echo -e "200\t$TEST_VIDEO_DIR/medium.mkv" >> "$INDEX"

    MIN_SIZE_BYTES=200
    SORT_MODE="size_desc"
    _build_queue_from_index

    # La queue ne doit pas contenir small.mkv
    run bash -lc "tr '\\0' '\\n' < '$QUEUE'"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "small.mkv" ]]
    [[ "$output" =~ "large.mkv" ]]
    [[ "$output" =~ "medium.mkv" ]]
}

@test "_build_queue_from_index: trie par taille croissante" {
    echo -e "100\t$TEST_VIDEO_DIR/small.mkv" > "$INDEX"
    echo -e "300\t$TEST_VIDEO_DIR/large.mkv" >> "$INDEX"
    echo -e "200\t$TEST_VIDEO_DIR/medium.mkv" >> "$INDEX"
    
    SORT_MODE="size_asc"
    _build_queue_from_index
    
    # Le plus petit en premier
    local first
    first=$(tr '\0' '\n' < "$QUEUE" | head -1)
    [[ "$first" =~ "small.mkv" ]]
}

###########################################################
# Tests de _apply_queue_limitations()
###########################################################

@test "_apply_queue_limitations: limite le nombre de fichiers" {
    # Créer une queue de 5 fichiers
    printf '%s\0' "file1" "file2" "file3" "file4" "file5" > "$QUEUE"
    
    LIMIT_FILES=3
    RANDOM_MODE=false
    _apply_queue_limitations
    
    local count
    count=$(tr '\0' '\n' < "$QUEUE" | wc -l)
    [ "$count" -eq 3 ]
}

@test "_apply_queue_limitations: ne modifie pas si pas de limite" {
    printf '%s\0' "file1" "file2" "file3" > "$QUEUE"
    
    LIMIT_FILES=0
    _apply_queue_limitations
    
    local count
    count=$(tr '\0' '\n' < "$QUEUE" | wc -l)
    [ "$count" -eq 3 ]
}

###########################################################
# Tests de _validate_queue_not_empty()
###########################################################

@test "_validate_queue_not_empty: passe si queue non vide" {
    printf '%s\0' "file1" > "$QUEUE"
    
    run _validate_queue_not_empty
    [ "$status" -eq 0 ]
}

@test "_validate_queue_not_empty: quitte si queue vide" {
    > "$QUEUE"  # Fichier vide
    
    run _validate_queue_not_empty
    [ "$status" -eq 0 ]  # exit 0 dans la fonction
}

###########################################################
# Tests de _count_total_video_files()
###########################################################

@test "_count_total_video_files: compte les fichiers vidéo" {
    local count
    count=$(_count_total_video_files "$OUTPUT_DIR")
    
    # On a créé 4 fichiers vidéo dans setup
    [ "$count" -eq 4 ]
}

@test "_count_total_video_files: exclut le répertoire de sortie" {
    # Ajouter un fichier dans le répertoire de sortie
    echo "excluded" > "$OUTPUT_DIR/excluded.mkv"
    
    local count
    count=$(_count_total_video_files "$OUTPUT_DIR")
    
    # Le fichier dans OUTPUT_DIR ne doit pas être compté
    [ "$count" -eq 4 ]
}

###########################################################
# Tests d'intégration
###########################################################

@test "intégration: build_queue crée un index et une queue valides" {
    # Nettoyer les fichiers existants
    rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META" "$QUEUE"
    
    build_queue
    
    # Vérifier que les fichiers sont créés
    [ -f "$INDEX" ]
    [ -f "$INDEX_READABLE" ]
    [ -f "$INDEX_META" ]
    [ -f "$QUEUE" ]
    
    # Vérifier que la queue contient des fichiers
    local count
    count=$(tr '\0' '\n' < "$QUEUE" | wc -l)
    [ "$count" -gt 0 ]
}

@test "intégration: build_queue réutilise l'index existant avec --keep-index" {
    # Créer un index existant
    echo -e "100\t$TEST_VIDEO_DIR/existing.mkv" > "$INDEX"
    echo "SOURCE=$SOURCE" > "$INDEX_META"
    
    KEEP_INDEX=true
    build_queue
    
    # L'index ne doit pas avoir été régénéré (même contenu)
    grep -q "existing.mkv" "$INDEX"
}

###########################################################
# Tests de increment_processed_count()
###########################################################

@test "increment_processed_count: incrémente le compteur" {
    PROCESSED_COUNT_FILE="$TEST_QUEUE_DIR/processed_count"
    echo "5" > "$PROCESSED_COUNT_FILE"
    
    increment_processed_count
    
    [ "$(cat "$PROCESSED_COUNT_FILE")" -eq 6 ]
}

@test "increment_processed_count: ne fait rien si pas de fichier compteur" {
    PROCESSED_COUNT_FILE=""
    
    run increment_processed_count
    [ "$status" -eq 0 ]
}

###########################################################
# Tests avec espaces dans les chemins
###########################################################

@test "edge case: gère les chemins avec espaces" {
    # Créer un fichier avec des espaces dans le chemin
    mkdir -p "$TEST_VIDEO_DIR/season with spaces"
    echo "video" > "$TEST_VIDEO_DIR/season with spaces/episode 01.mkv"
    
    # Nettoyer et reconstruire
    rm -f "$INDEX" "$INDEX_META" "$QUEUE"
    build_queue
    
    # Vérifier que le fichier est dans la queue
    tr '\0' '\n' < "$QUEUE" | grep -q "episode 01.mkv"
}
