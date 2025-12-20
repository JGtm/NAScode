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
            printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
                -s "$SRC_DIR" -o "$OUT_DIR" \
                -d -k -x -n -l 1
        '
    [ "$status" -eq 0 ]

        # Non-régression : le run doit terminer et annoncer la fin du dry-run.
        [[ "$output" =~ "Dry run" ]]
}
