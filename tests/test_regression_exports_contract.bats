#!/usr/bin/env bats
###########################################################
# TESTS NON-RÉGRESSION - Contrat d'exports
# Vérifie que les fonctions nécessaires au mode parallèle sont
# bien exportées et disponibles dans un sous-shell.
###########################################################

load 'test_helper'

setup() {
    setup_test_env

    # Réplique l'environnement minimal attendu par les modules
    export SCRIPT_DIR="$PROJECT_ROOT"

    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/ui_options.sh"
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/codec_profiles.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/logging.sh"
    source "$LIB_DIR/progress.sh"
    source "$LIB_DIR/lock.sh"
    source "$LIB_DIR/system.sh"
    source "$LIB_DIR/off_peak.sh"
    source "$LIB_DIR/args.sh"
    source "$LIB_DIR/index.sh"
    source "$LIB_DIR/counters.sh"
    source "$LIB_DIR/queue.sh"
    source "$LIB_DIR/vmaf.sh"
    source "$LIB_DIR/media_probe.sh"
    source "$LIB_DIR/audio_params.sh"
    source "$LIB_DIR/video_params.sh"
    source "$LIB_DIR/stream_mapping.sh"
    source "$LIB_DIR/complexity.sh"
    source "$LIB_DIR/ffmpeg_pipeline.sh"
    source "$LIB_DIR/transcode_video.sh"
    source "$LIB_DIR/conversion.sh"
    source "$LIB_DIR/processing.sh"
    source "$LIB_DIR/summary.sh"
    source "$LIB_DIR/finalize.sh"
    source "$LIB_DIR/transfer.sh"
    source "$LIB_DIR/exports.sh"
}

teardown() {
    teardown_test_env
}

@test "export_variables: fonctions dispo dans un sous-shell" {
    export_variables

    # Note: utiliser bash -c (pas -lc) pour éviter le chargement de .bashrc
    # qui peut définir des variables en conflit avec les readonly du script.
    # Invariant testé : les fonctions sont bien exportées et visibles dans un sous-shell.
    run bash -c '
        set -euo pipefail
        required_fns=(
            _select_output_pix_fmt
            _build_downscale_filter_if_needed
            _compute_output_height_for_bitrate
            _build_effective_suffix_for_dims
            compute_video_params_adaptive
            should_skip_conversion
            convert_file
        )
        for fn in "${required_fns[@]}"; do
            declare -F "$fn" >/dev/null
        done
    ' 2>&1

    [ "$status" -eq 0 ]
}
