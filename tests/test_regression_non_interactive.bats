#!/usr/bin/env bats
###########################################################
# TESTS NON-RÉGRESSION - Non-interactif
# Vérifie qu'un run destiné à être non-interactif ne déclenche
# pas de prompts (régressions de read -p)
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"

    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR"
    touch "$SRC_DIR/a.mkv"
}

teardown() {
    teardown_test_env
}

@test "dry-run -k -x: pas de questions interactives dans stdout" {
        run bash -lc 'set -euo pipefail;
            cd "$WORKDIR";
            printf "n\n" | bash "$PROJECT_ROOT/nascode" \
                -s "$SRC_DIR" -o "$OUT_DIR" \
                -d -k -x -n -l 1
        '
    [ "$status" -eq 0 ]

    # Non-régression : pas de prompt interactif imprimé.
    assert_output_has_no_prompt_lines

    # Non-régression : le dry-run a vraiment été exécuté (artefacts attendus).
    [ -d "$WORKDIR/logs" ]
    [ -f "$WORKDIR/logs/Index" ]
    # Note: logs/Queue est un artefact temporaire nettoyé par le cleanup.
    assert_glob_exists "$WORKDIR/logs/Session_*.log"
    assert_glob_exists "$WORKDIR/logs/Summary_*.log"
    assert_glob_exists "$WORKDIR/logs/DryRun_Comparison_*.log"
}
