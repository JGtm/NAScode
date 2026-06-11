#!/usr/bin/env bats
###########################################################
# TESTS DE CARACTÉRISATION - presets de mode (config.sh)
#
# Verrouille la signature EXACTE de chaque mode (variables résultantes après
# set_conversion_mode_parameters) afin de refactorer la duplication des presets
# adaptatifs sans dérive de comportement. Si un refactor change une valeur, le
# test casse immédiatement.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal_fast   # sources ui, config, codec_profiles (+ detect mocké)
}

teardown() {
    teardown_test_env
}

# Calcule la signature d'un mode : key=value;... pour les variables clés.
_mode_signature() {
    local mode="$1"
    CONVERSION_MODE="$mode"
    VIDEO_CODEC="hevc"
    set_conversion_mode_parameters >/dev/null 2>&1
    local v out=""
    for v in SINGLE_PASS_MODE CRF_VALUE ENCODER_PRESET X265_PASS1_FAST FILM_KEYINT \
             ADAPTIVE_COMPLEXITY_MODE ENCODER_MODE_PROFILE AUDIO_FORCE_STEREO \
             AUDIO_TRANSLATE_EQUIV_QUALITY VIDEO_EQUIV_QUALITY_CAP LIMIT_FPS \
             AUTO_BOOST_ENABLED ADAPTIVE_BPP_BASE TARGET_BITRATE_KBPS \
             MAXRATE_KBPS BUFSIZE_KBPS; do
        out+="${v}=${!v:-_unset_};"
    done
    printf '%s' "$out"
}

@test "mode film : signature inchangée" {
    local sig; sig=$(_mode_signature film)
    [ "$sig" = "SINGLE_PASS_MODE=false;CRF_VALUE=21;ENCODER_PRESET=medium;X265_PASS1_FAST=false;FILM_KEYINT=240;ADAPTIVE_COMPLEXITY_MODE=false;ENCODER_MODE_PROFILE=film;AUDIO_FORCE_STEREO=false;AUDIO_TRANSLATE_EQUIV_QUALITY=false;VIDEO_EQUIV_QUALITY_CAP=true;LIMIT_FPS=false;AUTO_BOOST_ENABLED=_unset_;ADAPTIVE_BPP_BASE=_unset_;TARGET_BITRATE_KBPS=2035;MAXRATE_KBPS=3200;BUFSIZE_KBPS=4800;" ]
}

@test "mode serie : signature inchangée" {
    local sig; sig=$(_mode_signature serie)
    [ "$sig" = "SINGLE_PASS_MODE=true;CRF_VALUE=21;ENCODER_PRESET=medium;X265_PASS1_FAST=true;FILM_KEYINT=360;ADAPTIVE_COMPLEXITY_MODE=false;ENCODER_MODE_PROFILE=serie;AUDIO_FORCE_STEREO=true;AUDIO_TRANSLATE_EQUIV_QUALITY=false;VIDEO_EQUIV_QUALITY_CAP=true;LIMIT_FPS=true;AUTO_BOOST_ENABLED=_unset_;ADAPTIVE_BPP_BASE=_unset_;TARGET_BITRATE_KBPS=2070;MAXRATE_KBPS=2520;BUFSIZE_KBPS=3780;" ]
}

@test "mode adaptatif : signature inchangée" {
    local sig; sig=$(_mode_signature adaptatif)
    [ "$sig" = "SINGLE_PASS_MODE=true;CRF_VALUE=21;ENCODER_PRESET=medium;X265_PASS1_FAST=false;FILM_KEYINT=240;ADAPTIVE_COMPLEXITY_MODE=true;ENCODER_MODE_PROFILE=adaptatif;AUDIO_FORCE_STEREO=false;AUDIO_TRANSLATE_EQUIV_QUALITY=true;VIDEO_EQUIV_QUALITY_CAP=true;LIMIT_FPS=false;AUTO_BOOST_ENABLED=_unset_;ADAPTIVE_BPP_BASE=_unset_;TARGET_BITRATE_KBPS=2500;MAXRATE_KBPS=3500;BUFSIZE_KBPS=6250;" ]
}

@test "mode gaming : signature inchangée" {
    local sig; sig=$(_mode_signature gaming)
    [ "$sig" = "SINGLE_PASS_MODE=true;CRF_VALUE=21;ENCODER_PRESET=medium;X265_PASS1_FAST=false;FILM_KEYINT=240;ADAPTIVE_COMPLEXITY_MODE=true;ENCODER_MODE_PROFILE=adaptatif;AUDIO_FORCE_STEREO=false;AUDIO_TRANSLATE_EQUIV_QUALITY=true;VIDEO_EQUIV_QUALITY_CAP=true;LIMIT_FPS=true;AUTO_BOOST_ENABLED=_unset_;ADAPTIVE_BPP_BASE=0.20;TARGET_BITRATE_KBPS=12500;MAXRATE_KBPS=17500;BUFSIZE_KBPS=31250;" ]
}

@test "mode adaptatif-vmaf : signature inchangée" {
    local sig; sig=$(_mode_signature adaptatif-vmaf)
    [ "$sig" = "SINGLE_PASS_MODE=true;CRF_VALUE=21;ENCODER_PRESET=medium;X265_PASS1_FAST=false;FILM_KEYINT=240;ADAPTIVE_COMPLEXITY_MODE=false;ENCODER_MODE_PROFILE=adaptatif;AUDIO_FORCE_STEREO=false;AUDIO_TRANSLATE_EQUIV_QUALITY=true;VIDEO_EQUIV_QUALITY_CAP=true;LIMIT_FPS=false;AUTO_BOOST_ENABLED=true;ADAPTIVE_BPP_BASE=_unset_;TARGET_BITRATE_KBPS=2500;MAXRATE_KBPS=3500;BUFSIZE_KBPS=6250;" ]
}
