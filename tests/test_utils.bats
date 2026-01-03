#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/utils.sh
# Tests des fonctions utilitaires pures
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de clean_number()
###########################################################

@test "clean_number: extrait les chiffres d'une chaîne" {
    result=$(clean_number "abc123def")
    [ "$result" = "123" ]
}

@test "clean_number: gère une chaîne vide" {
    result=$(clean_number "")
    [ "$result" = "0" ]
}

@test "clean_number: gère une chaîne sans chiffres" {
    result=$(clean_number "abcdef")
    [ "$result" = "0" ]
}

@test "clean_number: conserve un nombre pur" {
    result=$(clean_number "42")
    [ "$result" = "42" ]
}

@test "clean_number: supprime les espaces et unités" {
    result=$(clean_number "1500 kb/s")
    [ "$result" = "1500" ]
}

@test "clean_number: gère les nombres avec virgules/points" {
    result=$(clean_number "1,234.56")
    [ "$result" = "123456" ]
}

###########################################################
# Tests de count_null_separated()
###########################################################

@test "count_null_separated: compte correctement 3 éléments" {
    local test_file="$TEST_TEMP_DIR/test_null.txt"
    create_null_separated_file "$test_file" "file1.mkv" "file2.mkv" "file3.mkv"
    
    result=$(count_null_separated "$test_file")
    [ "$result" -eq 3 ]
}

@test "count_null_separated: retourne 0 pour fichier inexistant" {
    result=$(count_null_separated "/nonexistent/file")
    [ "$result" -eq 0 ]
}

@test "count_null_separated: compte 1 élément" {
    local test_file="$TEST_TEMP_DIR/single.txt"
    create_null_separated_file "$test_file" "single_file.mkv"
    
    result=$(count_null_separated "$test_file")
    [ "$result" -eq 1 ]
}

@test "count_null_separated: retourne 0 pour fichier vide" {
    local test_file="$TEST_TEMP_DIR/empty.txt"
    touch "$test_file"
    
    result=$(count_null_separated "$test_file")
    [ "$result" -eq 0 ]
}

###########################################################
# Tests de is_excluded()
###########################################################

@test "_build_excludes_regex + is_excluded: exclut un dossier 'tests' partout" {
    EXCLUDES=("tests")
    EXCLUDES_REGEX="$(_build_excludes_regex)"

    is_excluded "/c/Users/Guillaume/Downloads/Series/NAScode/tests/fixtures/test_video_2s.mkv"
    [ "$?" -eq 0 ]

    ! is_excluded "/c/Users/Guillaume/Downloads/Series/NAScode/testsuite/fixtures/test_video_2s.mkv"
}

@test "is_excluded: détecte un fichier dans /Converted/" {
    EXCLUDES_REGEX='/Converted/|/\.plexignore|\.part$'
    
    is_excluded "/path/to/Converted/file.mkv"
    [ $? -eq 0 ]
}

@test "is_excluded: détecte un fichier .plexignore" {
    EXCLUDES_REGEX='/Converted/|/\.plexignore|\.part$'
    
    is_excluded "/path/to/.plexignore"
    [ $? -eq 0 ]
}

@test "is_excluded: détecte un fichier .part" {
    EXCLUDES_REGEX='/Converted/|/\.plexignore|\.part$'
    
    is_excluded "/downloads/video.mkv.part"
    [ $? -eq 0 ]
}

@test "is_excluded: accepte un fichier normal" {
    EXCLUDES_REGEX='/Converted/|/\.plexignore|\.part$'
    
    ! is_excluded "/videos/movie.mkv"
}

@test "is_excluded: accepte quand EXCLUDES_REGEX est vide" {
    EXCLUDES_REGEX=""
    
    ! is_excluded "/any/path/file.mkv"
}

###########################################################
# Tests de compute_md5_prefix()
###########################################################

@test "compute_md5_prefix: retourne 8 caractères" {
    result=$(compute_md5_prefix "test string")
    [ ${#result} -eq 8 ]
}

@test "compute_md5_prefix: est déterministe" {
    result1=$(compute_md5_prefix "same input")
    result2=$(compute_md5_prefix "same input")
    [ "$result1" = "$result2" ]
}

@test "compute_md5_prefix: différent pour entrées différentes" {
    result1=$(compute_md5_prefix "input1")
    result2=$(compute_md5_prefix "input2")
    [ "$result1" != "$result2" ]
}

@test "compute_md5_prefix: gère les caractères spéciaux" {
    result=$(compute_md5_prefix "fichier avec espaces & accénts.mkv")
    [ ${#result} -eq 8 ]
}

###########################################################
# Tests de now_ts()
###########################################################

@test "now_ts: retourne un timestamp numérique" {
    result=$(now_ts)
    # Vérifie que c'est un nombre (entier ou décimal)
    [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]]
}

@test "now_ts: retourne une valeur croissante" {
    ts1=$(now_ts)
    sleep 0.1
    ts2=$(now_ts)
    
    # Comparer avec awk pour les nombres décimaux
    result=$(awk "BEGIN {print ($ts2 >= $ts1) ? 1 : 0}")
    [ "$result" -eq 1 ]
}

###########################################################
# Tests de format_duration_seconds()
###########################################################

@test "format_duration_seconds: formate 0 secondes" {
    result=$(format_duration_seconds 0)
    [ "$result" = "00:00:00" ]
}

@test "format_duration_seconds: formate moins d'une minute" {
    result=$(format_duration_seconds 45)
    [ "$result" = "00:00:45" ]
}

@test "format_duration_seconds: formate une minute exacte" {
    result=$(format_duration_seconds 60)
    [ "$result" = "00:01:00" ]
}

@test "format_duration_seconds: formate une heure exacte" {
    result=$(format_duration_seconds 3600)
    [ "$result" = "01:00:00" ]
}

@test "format_duration_seconds: formate une durée mixte" {
    # 2h 15m 33s = 7200 + 900 + 33 = 8133
    result=$(format_duration_seconds 8133)
    [ "$result" = "02:15:33" ]
}

@test "format_duration_seconds: gère les grandes durées" {
    # 25h = 90000 secondes
    result=$(format_duration_seconds 90000)
    [ "$result" = "25:00:00" ]
}

@test "format_duration_seconds: gère une entrée vide" {
    result=$(format_duration_seconds "")
    [ "$result" = "00:00:00" ]
}

###########################################################
# Tests de format_duration_compact()
###########################################################

@test "format_duration_compact: formate 0 secondes" {
    result=$(format_duration_compact 0)
    [ "$result" = "0s" ]
}

@test "format_duration_compact: formate moins d'une minute" {
    result=$(format_duration_compact 45)
    [ "$result" = "45s" ]
}

@test "format_duration_compact: formate minutes et secondes" {
    result=$(format_duration_compact 125)  # 2m 5s
    [ "$result" = "2m 5s" ]
}

@test "format_duration_compact: formate heures, minutes et secondes" {
    # 2h 15m 33s = 7200 + 900 + 33 = 8133
    result=$(format_duration_compact 8133)
    [ "$result" = "2h 15m 33s" ]
}

@test "format_duration_compact: formate une heure exacte" {
    result=$(format_duration_compact 3600)
    [ "$result" = "1h 0m 0s" ]
}

@test "format_duration_compact: gère une entrée vide" {
    result=$(format_duration_compact "")
    [ "$result" = "0s" ]
}

###########################################################
# Tests de get_file_size_bytes()
###########################################################

@test "get_file_size_bytes: retourne la taille d'un fichier existant" {
    local test_file="$TEST_TEMP_DIR/size_test.txt"
    echo -n "12345" > "$test_file"  # 5 bytes exactement
    
    result=$(get_file_size_bytes "$test_file")
    [ "$result" -eq 5 ]
}

@test "get_file_size_bytes: retourne 0 pour fichier vide" {
    local test_file="$TEST_TEMP_DIR/empty.txt"
    touch "$test_file"
    
    result=$(get_file_size_bytes "$test_file")
    [ "$result" -eq 0 ]
}

@test "get_file_size_bytes: retourne 0 pour fichier inexistant" {
    result=$(get_file_size_bytes "/nonexistent/file.txt")
    [ "$result" -eq 0 ]
}

@test "get_file_size_bytes: gère les fichiers avec espaces dans le nom" {
    local test_file="$TEST_TEMP_DIR/file with spaces.txt"
    echo -n "test" > "$test_file"  # 4 bytes
    
    result=$(get_file_size_bytes "$test_file")
    [ "$result" -eq 4 ]
}

###########################################################
# Tests de normalize_path_for_ffprobe()
###########################################################

@test "normalize_path_for_ffprobe: convertit /c/ en C:/" {
    result=$(normalize_path_for_ffprobe "/c/Users/test/video.mkv")
    [ "$result" = "C:/Users/test/video.mkv" ]
}

@test "normalize_path_for_ffprobe: convertit /d/ en D:/" {
    result=$(normalize_path_for_ffprobe "/d/Videos/film.mkv")
    [ "$result" = "D:/Videos/film.mkv" ]
}

@test "normalize_path_for_ffprobe: conserve chemin Unix normal" {
    result=$(normalize_path_for_ffprobe "/home/user/video.mkv")
    [ "$result" = "/home/user/video.mkv" ]
}

@test "normalize_path_for_ffprobe: conserve chemin Windows natif" {
    result=$(normalize_path_for_ffprobe "C:/Users/test/video.mkv")
    [ "$result" = "C:/Users/test/video.mkv" ]
}

@test "normalize_path_for_ffprobe: gère les accents dans le chemin" {
    result=$(normalize_path_for_ffprobe "/c/Vidéos/Séries/épisode.mkv")
    [ "$result" = "C:/Vidéos/Séries/épisode.mkv" ]
}

@test "normalize_path_for_ffprobe: gère les apostrophes dans le chemin" {
    result=$(normalize_path_for_ffprobe "/c/Films/L'Odyssée/film.mkv")
    [ "$result" = "C:/Films/L'Odyssée/film.mkv" ]
}

@test "normalize_path_for_ffprobe: gère les espaces dans le chemin" {
    result=$(normalize_path_for_ffprobe "/c/Ma Vidéo/Mon Film/test.mkv")
    [ "$result" = "C:/Ma Vidéo/Mon Film/test.mkv" ]
}

@test "normalize_path_for_ffprobe: gère chemin vide" {
    result=$(normalize_path_for_ffprobe "")
    [ "$result" = "" ]
}
