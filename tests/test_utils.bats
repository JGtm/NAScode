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
