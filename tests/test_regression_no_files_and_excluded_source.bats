#!/usr/bin/env bats
###########################################################
# TESTS NON-RÉGRESSION - Cas limites (queue vide / source exclue)
# - "Aucun fichier à traiter" ne doit pas provoquer de blocage (exit 0)
# - Si la source est exclue par EXCLUDES, le script doit échouer explicitement (exit 1)
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_EMPTY_DIR="$TEST_TEMP_DIR/src_empty"
    export OUT_DIR="$TEST_TEMP_DIR/out"

    mkdir -p "$WORKDIR" "$SRC_EMPTY_DIR" "$OUT_DIR"

    # Source volontairement "exclue" par la config par défaut (EXCLUDES_REGEX inclut /Converted/)
    export SRC_EXCLUDED_DIR="$TEST_TEMP_DIR/Converted/src"
    mkdir -p "$SRC_EXCLUDED_DIR"
}

teardown() {
    teardown_test_env
}

@test "queue vide (aucun fichier vidéo): le run (dry-run) sort 0 et n'accroche pas" {
    run bash -lc 'set -euo pipefail;
        cd "$WORKDIR";
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_EMPTY_DIR" -o "$OUT_DIR" \
            --dry-run --keep-index --no-suffix --no-progress
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun fichier à traiter"* ]]
}

@test "source exclue explicitement (par EXCLUDES): le run échoue avec erreur" {
    run bash -lc 'set -euo pipefail;
        cd "$WORKDIR";
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_EXCLUDED_DIR" -o "$OUT_DIR" \
            --dry-run --keep-index --no-suffix --no-progress
    '

    [ "$status" -eq 1 ]
    [[ "$output" == *"Le répertoire source est exclu"* ]]
}
