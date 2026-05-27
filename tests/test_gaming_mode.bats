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

@test "gaming: cap LIMIT_FPS à 29.97 par défaut (économie bits/frame)" {
    unset LIMIT_FPS
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${LIMIT_FPS:-}" = "true" ]
}

@test "gaming: respecte LIMIT_FPS=false env override (préserver 60+fps)" {
    LIMIT_FPS=false
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${LIMIT_FPS:-}" = "false" ]
    unset LIMIT_FPS
}

@test "gaming: ne force PAS l'audio stéréo (préserve multicanal)" {
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${AUDIO_FORCE_STEREO:-}" = "false" ]
}

###########################################################
# Override ADAPTIVE_BPP_BASE — c'est le levier clé du mode
###########################################################

@test "gaming: ADAPTIVE_BPP_BASE override à 0.16 par défaut (compense cap 30fps)" {
    unset ADAPTIVE_BPP_BASE_GAMING
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    [ "${ADAPTIVE_BPP_BASE:-}" = "0.16" ]
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

@test "gaming: bitrate target 1080p30 est ~10 Mbit/s à BPP=0.16 et C=1.0" {
    # Vérifie la formule R = W × H × FPS × BPP × C avec BPP gaming.
    # En 1080p30, BPP 0.16 donne ~10 Mbit/s — équivalent à un encode 60fps
    # à BPP 0.080 (file size identique) mais 2× plus de bits par frame.
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    local result
    # original_bitrate_bps élevé pour ne pas déclencher le garde-fou 75% source.
    result=$(compute_adaptive_target_bitrate 1920 1080 30 "1.0" "48000000")
    # Attendu : 1920*1080*30*0.16/1000 = 9953 kbps.
    [ "$result" -ge 9000 ]
    [ "$result" -le 11000 ]
}

@test "gaming: bitrate target scale linéairement avec FPS (60 = 2× 30)" {
    # Même si le mode cap à 30 en pratique, la formule R = W×H×FPS×BPP×C
    # reste linéaire en FPS pour tout FPS passé en argument.
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    local r30 r60
    r30=$(compute_adaptive_target_bitrate 1920 1080 30 "1.0" "100000000")
    r60=$(compute_adaptive_target_bitrate 1920 1080 60 "1.0" "100000000")
    local ratio_pct=$(( r60 * 100 / r30 ))
    [ "$ratio_pct" -ge 195 ]
    [ "$ratio_pct" -le 205 ]
}

@test "gaming: bitrate target 4K30 ~40 Mbit/s (haute résolution)" {
    source "$LIB_DIR/complexity.sh"
    CONVERSION_MODE="gaming"
    set_conversion_mode_parameters
    local result
    # Source 200 Mbit/s pour ne pas déclencher le cap 75% source.
    result=$(compute_adaptive_target_bitrate 3840 2160 30 "1.0" "200000000")
    # 3840*2160*30*0.16/1000 = 39813 kbps
    [ "$result" -ge 38000 ]
    [ "$result" -le 42000 ]
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
