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
