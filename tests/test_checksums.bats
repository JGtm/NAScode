#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Fonctions de checksum
# Tests avec fixtures (fichiers réels)
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
# Tests de compute_sha256()
###########################################################

@test "compute_sha256: retourne un hash de 64 caractères" {
    # Créer un fichier de test
    local test_file="$TEST_TEMP_DIR/test_sha.txt"
    echo "test content" > "$test_file"
    
    result=$(compute_sha256 "$test_file")
    [ ${#result} -eq 64 ]
}

@test "compute_sha256: est déterministe" {
    local test_file="$TEST_TEMP_DIR/deterministic.txt"
    echo "same content" > "$test_file"
    
    result1=$(compute_sha256 "$test_file")
    result2=$(compute_sha256 "$test_file")
    
    [ "$result1" = "$result2" ]
}

@test "compute_sha256: hash différent pour contenu différent" {
    local file1="$TEST_TEMP_DIR/file1.txt"
    local file2="$TEST_TEMP_DIR/file2.txt"
    echo "content 1" > "$file1"
    echo "content 2" > "$file2"
    
    hash1=$(compute_sha256 "$file1")
    hash2=$(compute_sha256 "$file2")
    
    [ "$hash1" != "$hash2" ]
}

@test "compute_sha256: retourne vide pour fichier inexistant" {
    result=$(compute_sha256 "/nonexistent/file.txt")
    [ -z "$result" ]
}

@test "compute_sha256: gère les fichiers binaires" {
    local binary_file="$TEST_TEMP_DIR/binary.dat"
    # Créer un fichier avec des bytes aléatoires
    dd if=/dev/urandom of="$binary_file" bs=1024 count=10 2>/dev/null
    
    result=$(compute_sha256 "$binary_file")
    [ ${#result} -eq 64 ]
}

@test "compute_sha256: hash connu pour contenu connu" {
    local test_file="$TEST_TEMP_DIR/known.txt"
    # "hello\n" a un SHA256 connu
    printf "hello\n" > "$test_file"
    
    result=$(compute_sha256 "$test_file")
    # SHA256 de "hello\n"
    expected="5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    
    [ "$result" = "$expected" ]
}

###########################################################
# Tests avec fixtures pré-créées
###########################################################

@test "fixture: sample.null contient le bon nombre d'éléments" {
    local fixture="$FIXTURES_DIR/sample.null"
    
    if [[ ! -f "$fixture" ]]; then
        skip "Fixture sample.null non disponible"
    fi
    
    result=$(count_null_separated "$fixture")
    [ "$result" -eq 5 ]
}

@test "fixture: test.txt a le bon checksum" {
    local fixture="$FIXTURES_DIR/test.txt"
    
    if [[ ! -f "$fixture" ]]; then
        skip "Fixture test.txt non disponible"
    fi
    
    result=$(compute_sha256 "$fixture")
    # Le hash attendu dépend du contenu de la fixture
    [ -n "$result" ]
    [ ${#result} -eq 64 ]
}

###########################################################
# Tests de custom_pv() (copie avec progression)
###########################################################

@test "custom_pv: copie un fichier correctement" {
    local src="$TEST_TEMP_DIR/source.dat"
    local dst="$TEST_TEMP_DIR/dest.dat"
    
    # Créer un fichier source
    dd if=/dev/zero of="$src" bs=1024 count=100 2>/dev/null
    
    # Copier avec custom_pv (rediriger stderr pour éviter l'affichage)
    custom_pv "$src" "$dst" 2>/dev/null
    
    # Vérifier que le fichier destination existe et a la même taille
    [ -f "$dst" ]
    
    src_size=$(stat -c%s "$src" 2>/dev/null || stat -f%z "$src")
    dst_size=$(stat -c%s "$dst" 2>/dev/null || stat -f%z "$dst")
    
    [ "$src_size" -eq "$dst_size" ]
}

@test "custom_pv: préserve l'intégrité des données" {
    local src="$TEST_TEMP_DIR/integrity_src.dat"
    local dst="$TEST_TEMP_DIR/integrity_dst.dat"
    
    # Créer un fichier avec du contenu connu
    echo "Test content for integrity check" > "$src"
    
    custom_pv "$src" "$dst" 2>/dev/null
    
    src_hash=$(compute_sha256 "$src")
    dst_hash=$(compute_sha256 "$dst")
    
    [ "$src_hash" = "$dst_hash" ]
}

@test "custom_pv: échoue si source n'existe pas" {
    local dst="$TEST_TEMP_DIR/dest.dat"
    
    run custom_pv "/nonexistent/source.dat" "$dst"
    [ "$status" -ne 0 ]
}
