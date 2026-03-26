#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/media_probe.sh
# Tests des fonctions ffprobe (propriétés de stream)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/media_probe.sh"
}

teardown() {
    teardown_test_env
}

@test "get_video_stream_props: retourne width|height|pix_fmt" {
    command -v ffmpeg >/dev/null 2>&1 || skip "ffmpeg requis"
    command -v ffprobe >/dev/null 2>&1 || skip "ffprobe requis"

    local test_file="$TEST_TEMP_DIR/sample_128x72.mkv"

    ffmpeg -y -hide_banner -loglevel error \
        -f lavfi -i "testsrc=size=128x72:rate=30" \
        -t 1 -pix_fmt yuv420p -c:v libx264 -preset ultrafast \
        "$test_file"

    local props
    props=$(get_video_stream_props "$test_file")

    local w h pix
    IFS='|' read -r w h pix <<< "$props"

    [ "$w" -eq 128 ]
    [ "$h" -eq 72 ]
    [ "$pix" = "yuv420p" ]
}

@test "get_video_metadata: retourne bitrate|codec|duration" {
    command -v ffmpeg >/dev/null 2>&1 || skip "ffmpeg requis"
    command -v ffprobe >/dev/null 2>&1 || skip "ffprobe requis"

    local test_file="$TEST_TEMP_DIR/sample_meta.mkv"

    ffmpeg -y -hide_banner -loglevel error \
        -f lavfi -i "testsrc=size=64x64:rate=25" \
        -t 1 -pix_fmt yuv420p -c:v libx264 -preset ultrafast \
        "$test_file"

    local meta
    meta=$(get_video_metadata "$test_file")

    local bitrate codec duration
    IFS='|' read -r bitrate codec duration <<< "$meta"

    [[ "$bitrate" =~ ^[0-9]+$ ]]
    [ -n "$codec" ]
    [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

@test "_probe_audio_channels: retourne channels|channel_layout (stub)" {
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "channels=6"
echo "channel_layout=6 channels"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"

    local out channels layout
    out=$(_probe_audio_channels "/fake/file.mkv")
    IFS='|' read -r channels layout <<< "$out"

    [ "$channels" -eq 6 ]
    [ "$layout" = "6 channels" ]
}

@test "_probe_audio_full: retourne codec|bitrate_kbps|channels|layout (stub)" {
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=384000"
echo "channels=6"
echo "channel_layout=6 channels"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"

    local out codec bitrate_kbps channels layout
    out=$(_probe_audio_full "/fake/file.mkv")
    IFS='|' read -r codec bitrate_kbps channels layout <<< "$out"

    [ "$codec" = "eac3" ]
    [ "$bitrate_kbps" -eq 384 ]
    [ "$channels" -eq 6 ]
    [ "$layout" = "6 channels" ]
}

@test "get_full_media_metadata: retourne les champs attendus pour un fichier valide (stub)" {
    local stub_dir="$TEST_TEMP_DIR/stub_full"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "[STREAM]"
echo "index=0"
echo "codec_type=video"
echo "codec_name=h264"
echo "bit_rate=2000000"
echo "width=1920"
echo "height=1080"
echo "pix_fmt=yuv420p"
echo "[/STREAM]"
echo "[STREAM]"
echo "index=1"
echo "codec_type=audio"
echo "codec_name=aac"
echo "bit_rate=192000"
echo "[/STREAM]"
echo "[FORMAT]"
echo "duration=120.0"
echo "bit_rate=2200000"
echo "[/FORMAT]"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"

    run get_full_media_metadata "/fake/file.mkv"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "h264" ]]
    [[ "$output" =~ "aac" ]]
    [[ "$output" =~ "1920" ]]
}

@test "get_full_media_metadata: retourne code 1 si pas de stream vidéo (fichier audio seul)" {
    local stub_dir="$TEST_TEMP_DIR/stub_audio_only"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Fichier audio uniquement, pas de stream vidéo
echo "[STREAM]"
echo "index=0"
echo "codec_type=audio"
echo "codec_name=aac"
echo "bit_rate=192000"
echo "[/STREAM]"
echo "[FORMAT]"
echo "duration=60.0"
echo "[/FORMAT]"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"

    run get_full_media_metadata "/fake/audio_only.m4a"
    [ "$status" -eq 1 ]
}

@test "get_full_media_metadata: retourne code 1 si ffprobe échoue (fichier corrompu)" {
    local stub_dir="$TEST_TEMP_DIR/stub_corrupt"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simule ffprobe sur un fichier corrompu : sortie vide, code d'erreur
exit 1
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"

    run get_full_media_metadata "/fake/corrupt.mkv"
    [ "$status" -eq 1 ]
}
