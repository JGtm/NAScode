#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Mode `gaming`
#
# Variante du mode adaptatif calibrée pour du contenu high-motion
# (replays OBS, captures de jeux, screencasts). Override
# ADAPTIVE_BPP_BASE pour adapter le bitrate target à des sources
# 60+ fps avec peu de redondance temporelle.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules_fast
}

teardown() {
    teardown_test_env
}

###########################################################
# Reconnaissance du mode
###########################################################

@test "gaming: mode reconnu par set_conversion_mode_parameters" {
    CONVERSION_MODE="gaming"
    run set_conversion_mode_parameters
    [ "$status" -eq 0 ]
}

@test "gaming: active ADAPTIVE_COMPLEXITY_MODE (analyse par fichier)" {
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${ADAPTIVE_COMPLEXITY_MODE:-}" = "true" ]
}

@test "gaming: hérite du profil SVT-AV1 adaptatif (params perceptuels sans film-grain)" {
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${ENCODER_MODE_PROFILE:-}" = "adaptatif" ]
}

@test "gaming: utilise CRF 21 single-pass capped CRF" {
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${CRF_VALUE:-}" = "21" ]
    [ "${SINGLE_PASS_MODE:-}" = "true" ]
}

@test "gaming: n'active PAS AUTO_BOOST_ENABLED (≠ adaptatif-vmaf)" {
    CONVERSION_MODE="gaming"
    AUTO_BOOST_ENABLED=false
    set_conversion_mode_parameters
    [ "${AUTO_BOOST_ENABLED:-false}" != "true" ]
}

@test "gaming: ne force PAS LIMIT_FPS (préserve 60/120/144+ fps natif)" {
    unset LIMIT_FPS
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${LIMIT_FPS:-}" != "true" ]
}

@test "gaming: ne force PAS l'audio stéréo (préserve multicanal)" {
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${AUDIO_FORCE_STEREO:-}" = "false" ]
}

###########################################################
# Override ADAPTIVE_BPP_BASE — c'est le levier clé du mode
###########################################################

@test "gaming: ADAPTIVE_BPP_BASE override à 0.080 par défaut" {
    unset ADAPTIVE_BPP_BASE_GAMING
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${ADAPTIVE_BPP_BASE:-}" = "0.080" ]
}

@test "gaming: respecte ADAPTIVE_BPP_BASE_GAMING env override (plus haut)" {
    ADAPTIVE_BPP_BASE_GAMING="0.10"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${ADAPTIVE_BPP_BASE:-}" = "0.10" ]
    unset ADAPTIVE_BPP_BASE_GAMING
}

@test "gaming: respecte ADAPTIVE_BPP_BASE_GAMING env override (plus bas)" {
    ADAPTIVE_BPP_BASE_GAMING="0.06"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${ADAPTIVE_BPP_BASE:-}" = "0.06" ]
    unset ADAPTIVE_BPP_BASE_GAMING
}

###########################################################
# Calcul du bitrate target — la philosophie du mode
###########################################################

@test "gaming: bitrate target 1080p60 est ~10 Mbit/s à BPP=0.080 et C=1.0" {
    # Vérifie la formule R = W × H × FPS × BPP × C avec BPP gaming.
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    # original_bitrate_bps élevé (48 Mbit/s style replay OBS) pour que le
    # garde-fou "max 75% du source" (= 36 Mbit/s) ne déclenche pas.
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 60 "1.0" "48000000")
    # Attendu : 1920*1080*60*0.080/1000 = 9953 kbps (avant garde-fous).
    [ "$result" -ge 9000 ]
    [ "$result" -le 11000 ]
}

@test "gaming: bitrate target 1080p30 ≈ moitié du 1080p60 (scale linéaire avec FPS)" {
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    local r30 r60
    r30=$(compute_adaptive_target_bitrate 1920 1080 30 "1.0" "48000000")
    r60=$(compute_adaptive_target_bitrate 1920 1080 60 "1.0" "48000000")
    # r60 / r30 ≈ 2 (tolérance 5%)
    local ratio_pct=$(( r60 * 100 / r30 ))
    [ "$ratio_pct" -ge 195 ]
    [ "$ratio_pct" -le 205 ]
}

@test "gaming: bitrate target 1080p144 ~24 Mbit/s (high refresh rate)" {
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    local result
    # Source 100 Mbit/s pour ne pas déclencher le cap 75% source.
    result=$(compute_adaptive_target_bitrate 1920 1080 144 "1.0" "100000000")
    # 1920*1080*144*0.080/1000 = 23888 kbps
    [ "$result" -ge 22000 ]
    [ "$result" -le 26000 ]
}

@test "gaming: garde-fou 'max 75% du source' s'applique aussi en gaming" {
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    local result
    # Source à 5 Mbit/s : 75% = 3750 kbps. La formule donnerait ~10 Mbit/s
    # pour 1080p60, donc le garde-fou devrait plafonner.
    result=$(compute_adaptive_target_bitrate 1920 1080 60 "1.0" "5000000")
    [ "$result" -le 3800 ]
}

###########################################################
# Mode reconnu dans l'erreur "Modes disponibles"
###########################################################

@test "config: message d'erreur 'Modes disponibles' mentionne gaming" {
    grep -q 'gaming' "$LIB_DIR/config.sh"
}
