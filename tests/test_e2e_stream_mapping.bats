#!/usr/bin/env bats
###########################################################
# TESTS END-TO-END - Stream mapping (sous-titres)
#
# Objectif : valider que le mapping des sous-titres appliqué
# par NAScode fonctionne sur des fichiers réels (ffmpeg).
# - Si des sous-titres FR existent : ne garder que FR.
# - Sinon : garder tous les sous-titres.
#
# Prérequis : ffmpeg avec libx265.
###########################################################

load 'test_helper'

check_ffmpeg_available() {
    if ! command -v ffmpeg &>/dev/null; then
        skip "ffmpeg non disponible"
    fi
    if ! command -v ffprobe &>/dev/null; then
        skip "ffprobe non disponible"
    fi
    if ! ffmpeg -encoders 2>/dev/null | grep -q libx265; then
        skip "libx265 non disponible dans ffmpeg"
    fi
}

setup() {
    setup_test_env
    check_ffmpeg_available

    rm -f /tmp/conversion_video.lock
    rm -f /tmp/conversion_stop_flag

    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"

    # Forcer les logs dans le WORKDIR (isolement, pas de pollution du repo)
    export LOG_DIR="$WORKDIR/logs"

    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR"
}

teardown() {
    rm -f /tmp/conversion_video.lock
    rm -f /tmp/conversion_stop_flag
    teardown_test_env
}

# Génère un MKV avec 2 sous-titres (SRT) + 2 pistes audio.
# Args:
#   $1: out_file
#   $2: srt1_path
#   $3: lang1 (fra/eng/spa...)
#   $4: srt2_path
#   $5: lang2
_generate_mkv_with_subs() {
    local out_file="$1"
    local srt1="$2"
    local lang1="$3"
    local srt2="$4"
    local lang2="$5"

    # Vidéo courte + 2 audios (pour éviter les fichiers "trop simples")
    ffmpeg -y -hide_banner -loglevel error \
        -f lavfi -i "color=c=black:s=640x360:d=2" \
        -f lavfi -i "sine=frequency=440:duration=2" \
        -f lavfi -i "sine=frequency=880:duration=2" \
        -i "$srt1" \
        -i "$srt2" \
        -map 0:v:0 -map 1:a:0 -map 2:a:0 -map 3:0 -map 4:0 \
        -c:v libx264 -preset ultrafast -crf 35 \
        -c:a aac -b:a 96k \
        -c:s srt \
        -metadata:s:s:0 language="$lang1" \
        -metadata:s:s:1 language="$lang2" \
        "$out_file"
}

_count_sub_streams() {
    local file="$1"
    ffprobe -v error -select_streams s \
        -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l
}

@test "E2E SUBS: si FR+EN, ne garder que FR" {
    local fr_srt="$SRC_DIR/fr.srt"
    local en_srt="$SRC_DIR/en.srt"

    cat > "$fr_srt" <<'EOF'
1
00:00:00,000 --> 00:00:01,000
Bonjour
EOF

    cat > "$en_srt" <<'EOF'
1
00:00:00,000 --> 00:00:01,000
Hello
EOF

    local input_file="$SRC_DIR/input_fr_en.mkv"
    _generate_mkv_with_subs "$input_file" "$fr_srt" "fra" "$en_srt" "eng"

    # Sanity : on a bien 2 sous-titres en entrée
    local in_sub_count
    in_sub_count=$(_count_sub_streams "$input_file")
    [ "$in_sub_count" -eq 2 ]

    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '

    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    [ "$status" -eq 0 ]

    local out_file
    local heavy_dir
    heavy_dir="${OUT_DIR}${HEAVY_OUTPUT_DIR_SUFFIX:-_Heavier}"
    out_file=$(find "$OUT_DIR" "$heavy_dir" -type f -name "*.mkv" 2>/dev/null | head -1)
    [ -n "$out_file" ]

    local out_sub_count
    out_sub_count=$(_count_sub_streams "$out_file")

    # FR présent -> mapping doit en conserver 1 seul
    [ "$out_sub_count" -eq 1 ]
}

@test "E2E SUBS: si pas de FR, garder tous les sous-titres" {
    local en_srt="$SRC_DIR/en2.srt"
    local es_srt="$SRC_DIR/es.srt"

    cat > "$en_srt" <<'EOF'
1
00:00:00,000 --> 00:00:01,000
Hello
EOF

    cat > "$es_srt" <<'EOF'
1
00:00:00,000 --> 00:00:01,000
Hola
EOF

    local input_file="$SRC_DIR/input_en_es.mkv"
    _generate_mkv_with_subs "$input_file" "$en_srt" "eng" "$es_srt" "spa"

    local in_sub_count
    in_sub_count=$(_count_sub_streams "$input_file")
    [ "$in_sub_count" -eq 2 ]

    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '

    [ "$status" -eq 0 ]

    local out_file
    local heavy_dir
    heavy_dir="${OUT_DIR}${HEAVY_OUTPUT_DIR_SUFFIX:-_Heavier}"
    out_file=$(find "$OUT_DIR" "$heavy_dir" -type f -name "*.mkv" 2>/dev/null | head -1)
    [ -n "$out_file" ]

    local out_sub_count
    out_sub_count=$(_count_sub_streams "$out_file")

    # Pas de FR -> mapping garde tout (donc 2)
    [ "$out_sub_count" -eq 2 ]
}
