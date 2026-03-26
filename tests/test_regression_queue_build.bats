#!/usr/bin/env bats
###########################################################
# TESTS NON-RÉGRESSION - Queue
# Vérifie la construction de la queue via un run dry-run,
# ainsi que le respect de --limit.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    command -v ffmpeg  >/dev/null 2>&1 || skip "ffmpeg requis"
    command -v ffprobe >/dev/null 2>&1 || skip "ffprobe requis"

    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"

    mkdir -p "$WORKDIR" "$SRC_DIR/sub" "$OUT_DIR"

    # Fichiers .mkv minimaux valides — get_full_media_metadata() valide
    # maintenant la présence d'un codec vidéo (fichiers vides = rejetés).
    _make_video() {
        ffmpeg -y -loglevel error \
            -f lavfi -i "nullsrc=size=64x64:rate=1" \
            -t 1 -pix_fmt yuv420p -c:v libx264 -preset ultrafast \
            "$1" 2>/dev/null
    }
    _make_video "$SRC_DIR/a.mkv"
    _make_video "$SRC_DIR/b.mkv"
    _make_video "$SRC_DIR/sub/c.mkv"
}

teardown() {
    teardown_test_env
}

@test "--limit: le run ne traite que N éléments" {
        run bash -lc 'set -euo pipefail;
            cd "$WORKDIR";
            printf "n\n" | bash "$PROJECT_ROOT/nascode" -s "$SRC_DIR" -o "$OUT_DIR" -d -k -x -n -l 1
        '
    [ "$status" -eq 0 ]

    local out_count
    out_count=$(find "$OUT_DIR" -type f -name "*.mkv" | wc -l)
    [ "$out_count" -eq 1 ]
}
