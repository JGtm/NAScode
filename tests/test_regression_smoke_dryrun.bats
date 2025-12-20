#!/usr/bin/env bats
###########################################################
# TESTS NON-RÉGRESSION - Smoke / Dry-run
# Vérifie qu'un run complet en dry-run fonctionne et reste stable
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"

    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR"

    # Arborescence et fichiers factices
    mkdir -p "$SRC_DIR/Season 01" "$SRC_DIR/Converted" "$SRC_DIR/logs"
    touch "$SRC_DIR/a.mkv" \
          "$SRC_DIR/b.mkv" \
          "$SRC_DIR/Season 01/ep01.mkv" \
          "$SRC_DIR/Converted/ignored.mkv" \
          "$SRC_DIR/logs/ignored2.mkv" \
          "$SRC_DIR/c.part"
}

teardown() {
    teardown_test_env
}

@test "dry-run: exécution complète OK, queue/logs créés, exclusions respectées" {
        run bash -lc 'set -euo pipefail;
            cd "$WORKDIR";
            printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
                -s "$SRC_DIR" -o "$OUT_DIR" \
                --dry-run --keep-index --no-suffix --no-progress \
                --exclude "\\.part$" \
                --limit 2
        '
    [ "$status" -eq 0 ]

    # Logs et queue (dans WORKDIR pour ne pas polluer le repo)
    [ -d "$WORKDIR/logs" ]
    [ -f "$WORKDIR/logs/Queue" ]

    # Le log de dry-run doit exister
    compgen -G "$WORKDIR/logs/DryRun_Comparison_*.log" >/dev/null

    # La queue ne doit pas contenir les exclusions évidentes
    tr '\0' '\n' < "$WORKDIR/logs/Queue" > "$TEST_TEMP_DIR/queue.txt"
    ! grep -q "Converted/ignored.mkv" "$TEST_TEMP_DIR/queue.txt"
    ! grep -q "logs/ignored2.mkv" "$TEST_TEMP_DIR/queue.txt"
    ! grep -q "c.part" "$TEST_TEMP_DIR/queue.txt"

    # La limite doit se refléter dans le nombre de fichiers touchés en sortie
    # (en dry-run, convert_file touche les fichiers de sortie)
    local out_count
    out_count=$(find "$OUT_DIR" -type f -name "*.mkv" | wc -l)
    [ "$out_count" -eq 2 ]
}
