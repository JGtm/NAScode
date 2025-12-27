#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Wiring
# Vérifie que l'ordre de chargement des modules est cohérent
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    # Réplique l'environnement minimal attendu par config.sh
    export SCRIPT_DIR="$PROJECT_ROOT"

    # Charger les modules dans un ordre proche de nascode
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/logging.sh"
    source "$LIB_DIR/progress.sh"
    source "$LIB_DIR/lock.sh"
    source "$LIB_DIR/system.sh"
    source "$LIB_DIR/args.sh"
    source "$LIB_DIR/queue.sh"
    source "$LIB_DIR/vmaf.sh"
    source "$LIB_DIR/media_probe.sh"
    source "$LIB_DIR/transcode_video.sh"
    source "$LIB_DIR/conversion.sh"
    source "$LIB_DIR/processing.sh"
    source "$LIB_DIR/finalize.sh"
    source "$LIB_DIR/transfer.sh"
    source "$LIB_DIR/exports.sh"
}

teardown() {
    teardown_test_env
}

@test "fonctions clés disponibles après sourcing" {
    function_exists get_video_metadata
    function_exists get_video_stream_props
    function_exists _execute_conversion
    function_exists convert_file
}
