#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/conversion.sh
# Vérifie la décision de conversion (skip / video_passthrough / full)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal_fast
    source "$LIB_DIR/conversion.sh"
}

teardown() {
    teardown_test_env
}

_reset_state() {
    # Valeurs minimales nécessaires à _determine_conversion_mode
    CONVERSION_MODE="serie"
    VIDEO_CODEC="hevc"
    ADAPTIVE_COMPLEXITY_MODE=false

    # Configure MAXRATE_KBPS, etc.
    set_conversion_mode_parameters

    # Désactiver les logs pour éviter les écritures involontaires
    LOG_SESSION=""
    LOG_PROGRESS=""

    # Par défaut, audio OK (pas de conversion)
    unset -f _should_convert_audio 2>/dev/null || true
}

@test "_determine_conversion_mode: codec vide => skip" {
    _reset_state

    local status
    if _determine_conversion_mode "" "0" "file.mkv" "/source/file.mkv" "" "" ""; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 1 ]
    [ "$CONVERSION_ACTION" = "skip" ]
}

@test "_determine_conversion_mode: hevc + bitrate sous seuil => skip" {
    _reset_state

    # MAXRATE_KBPS pour serie = 2520 kbps, tolérance 10% => seuil ~2 772 000 bps
    local status
    if _determine_conversion_mode "hevc" "2000000" "file.mkv" "/source/file.mkv" "aac" "160" ""; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 1 ]
    [ "$CONVERSION_ACTION" = "skip" ]
}

@test "_determine_conversion_mode: hevc + bitrate ok mais audio à optimiser => video_passthrough" {
    _reset_state

    _should_convert_audio() { return 0; }

    _determine_conversion_mode "hevc" "2000000" "file.mkv" "/source/file.mkv" "dts" "1500" ""
    local status=$?
    [ "$status" -eq 0 ]
    [ "$CONVERSION_ACTION" = "video_passthrough" ]
}

@test "_determine_conversion_mode: bitrate trop élevé => full" {
    _reset_state

    _determine_conversion_mode "hevc" "4000000" "file.mkv" "/source/file.mkv" "aac" "160" ""
    local status=$?
    [ "$status" -eq 0 ]
    [ "$CONVERSION_ACTION" = "full" ]
}
