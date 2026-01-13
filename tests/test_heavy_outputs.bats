#!/usr/bin/env bats
###########################################################
# TESTS - sorties "Heavier" (anti-boucle)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules_fast

    export DRYRUN=false
    export LIMIT_FILES=0
    export HEAVY_OUTPUT_ENABLED=true
    export HEAVY_OUTPUT_DIR_SUFFIX="_Heavier"

    export OUTPUT_DIR="$TEST_TEMP_DIR/Converted"
    mkdir -p "$OUTPUT_DIR"
}

teardown() {
    teardown_test_env
}

@test "_check_output_exists: skip si la sortie Heavier existe déjà" {
    local src_dir="$TEST_TEMP_DIR/src"
    mkdir -p "$src_dir"
    local file_original="$src_dir/video.mkv"
    touch "$file_original"

    local filename="video.mkv"
    local final_output="$OUTPUT_DIR/Show/S01/video_x.mkv"

    local heavy_output
    heavy_output=$(compute_heavy_output_path "$final_output" "$OUTPUT_DIR")
    mkdir -p "$(dirname "$heavy_output")"
    touch "$heavy_output"

    run _check_output_exists "$file_original" "$filename" "$final_output"
    [ "$status" -eq 0 ]
}
