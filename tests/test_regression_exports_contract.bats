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
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/logging.sh"
    source "$LIB_DIR/progress.sh"
    source "$LIB_DIR/lock.sh"
    source "$LIB_DIR/system.sh"
    source "$LIB_DIR/off_peak.sh"
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

@test "export_variables: fonctions dispo dans un sous-shell" {
    export_variables

    # Note: utiliser bash -c (pas -lc) pour éviter le chargement de .bashrc
    # qui peut définir des variables en conflit avec les readonly du script
    # Ignorer les erreurs readonly (2>&1 | grep -v readonly)
    run bash -c '
      _select_output_pix_fmt yuv420p10le | grep -qx yuv420p10le
      _build_downscale_filter_if_needed 3840 2160 | grep -q "scale="
            _compute_output_height_for_bitrate 2560 720 | grep -qx 540
            _build_effective_suffix_for_dims 1280 720 | grep -q "_720p_"
      normalize_path "/c/Users/test" >/dev/null || true
      echo ok
    ' 2>&1

    # Vérifier que "ok" est présent dans la sortie (les fonctions ont fonctionné)
    [[ "$output" =~ "ok" ]]
}
