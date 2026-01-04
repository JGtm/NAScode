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
