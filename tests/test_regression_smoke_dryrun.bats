#!/usr/bin/env bats
###########################################################
# TESTS NON-RÉGRESSION - Smoke / Dry-run
# Vérifie qu'un run complet en dry-run fonctionne et reste stable
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    command -v ffmpeg  >/dev/null 2>&1 || skip "ffmpeg requis"
    command -v ffprobe >/dev/null 2>&1 || skip "ffprobe requis"

    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"

    # Forcer les logs dans le WORKDIR (isolement, pas de pollution du repo)
    export LOG_DIR="$WORKDIR/logs"

    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR"

    # Arborescence — les fichiers .mkv doivent être de vraies vidéos minimales
    # car get_full_media_metadata() valide maintenant la présence d'un codec vidéo.
    mkdir -p "$SRC_DIR/Season 01" "$SRC_DIR/Converted" "$SRC_DIR/logs"

    _make_video() {
        ffmpeg -y -loglevel error \
            -f lavfi -i "nullsrc=size=64x64:rate=1" \
            -t 1 -pix_fmt yuv420p -c:v libx264 -preset ultrafast \
            "$1" 2>/dev/null
    }
    _make_video "$SRC_DIR/a.mkv"
    _make_video "$SRC_DIR/b.mkv"
    _make_video "$SRC_DIR/Season 01/ep01.mkv"
    # Les fichiers ignorés n'ont pas besoin d'être valides (jamais lus par ffprobe)
    touch "$SRC_DIR/Converted/ignored.mkv" \
          "$SRC_DIR/logs/ignored2.mkv" \
          "$SRC_DIR/c.part"
}

teardown() {
    teardown_test_env
}

@test "dry-run: exécution complète OK, queue/logs créés, exclusions respectées" {
        run bash -lc 'set -euo pipefail;
            cd "$WORKDIR";
            printf "n\n" | bash "$PROJECT_ROOT/nascode" \
                -s "$SRC_DIR" -o "$OUT_DIR" \
                --dry-run --keep-index --no-suffix --no-progress \
                --exclude "\\.part$" \
                --limit 2
        '
    [ "$status" -eq 0 ]

    # Logs et queue (dans WORKDIR pour ne pas polluer le repo)
    [ -d "$WORKDIR/logs" ]
    # Queue est supprimé au cleanup, on vérifie Queue.full qui persiste
    [ -f "$WORKDIR/logs/Queue.full" ]

    # Le log de dry-run doit exister
    compgen -G "$WORKDIR/logs/DryRun_Comparison_*.log" >/dev/null

    # La queue ne doit pas contenir les exclusions évidentes
    # Queue est supprimé, on utilise Queue_readable qui contient la queue finale (limitée)
    local queue_readable
    queue_readable=$(ls "$WORKDIR/logs/Queue_readable_"*.txt | head -1)
    [ -f "$queue_readable" ]
    
    ! grep -q "Converted/ignored.mkv" "$queue_readable"
    ! grep -q "logs/ignored2.mkv" "$queue_readable"
    ! grep -q "c.part" "$queue_readable"

    # La limite doit se refléter dans le nombre de fichiers touchés en sortie
    # (en dry-run, convert_file touche les fichiers de sortie)
    local out_count
    out_count=$(find "$OUT_DIR" -type f -name "*.mkv" | wc -l)
    [ "$out_count" -eq 2 ]
}
