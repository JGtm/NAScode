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

@test "_determine_conversion_mode: AV1 + bitrate sous seuil traduit (cible HEVC) => skip" {
    _reset_state

    # MAXRATE_KBPS (HEVC/serie)=2520, tolérance 10% -> 2772k
    # Traduit en AV1 : 2772 * 50/70 ≈ 1980k
    local status
    if _determine_conversion_mode "av1" "1900000" "file.mkv" "/source/file.mkv" "aac" "160" ""; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 1 ]
    [ "$CONVERSION_ACTION" = "skip" ]
}

@test "_determine_conversion_mode: AV1 + bitrate au-dessus seuil traduit (cible HEVC) => full + no-downgrade" {
    _reset_state

    _determine_conversion_mode "av1" "2000000" "file.mkv" "/source/file.mkv" "aac" "160" "" || true
    [ "$CONVERSION_ACTION" = "full" ]

    # Pas de downgrade : on ré-encode en AV1 pour plafonner le bitrate
    [ "$EFFECTIVE_VIDEO_CODEC" = "av1" ]
}

###########################################################
# Précédence CLI > preset de mode (SINGLE_PASS_MODE / -2)
###########################################################

@test "set_conversion_mode_parameters: -2 (two-pass) conservé en mode serie" {
    CONVERSION_MODE="serie"
    VIDEO_CODEC="hevc"
    SINGLE_PASS_MODE=false
    SINGLE_PASS_MODE_SET_BY_CLI=true

    set_conversion_mode_parameters

    # serie respecte le choix utilisateur : two-pass conservé
    [ "$SINGLE_PASS_MODE" = "false" ]
}

@test "set_conversion_mode_parameters: mode adaptatif conserve son single-pass (-2 non passé)" {
    CONVERSION_MODE="adaptatif"
    VIDEO_CODEC="av1"
    SINGLE_PASS_MODE=true
    unset SINGLE_PASS_MODE_SET_BY_CLI

    set_conversion_mode_parameters

    [ "$SINGLE_PASS_MODE" = "true" ]
}

@test "set_conversion_mode_parameters: -2 en mode adaptatif force le single-pass (design) et le signale" {
    CONVERSION_MODE="adaptatif"
    VIDEO_CODEC="av1"
    SINGLE_PASS_MODE=false
    SINGLE_PASS_MODE_SET_BY_CLI=true

    # Valeur résultante : le single-pass du mode est conservé
    set_conversion_mode_parameters
    [ "$SINGLE_PASS_MODE" = "true" ]

    # Et l'utilisateur est averti (au lieu d'un écrasement silencieux)
    CONVERSION_MODE="adaptatif"
    VIDEO_CODEC="av1"
    SINGLE_PASS_MODE=false
    SINGLE_PASS_MODE_SET_BY_CLI=true
    run set_conversion_mode_parameters
    [[ "$output" == *"Two-pass"* ]]
}
