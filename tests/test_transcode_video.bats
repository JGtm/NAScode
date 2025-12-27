#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/transcode_video.sh
# Tests des fonctions d'adaptation vidéo (pix_fmt / downscale)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/transcode_video.sh"
}

teardown() {
    teardown_test_env
}

@test "_select_output_pix_fmt: conserve le 10-bit" {
    result=$(_select_output_pix_fmt "yuv420p10le")
    [ "$result" = "yuv420p10le" ]
}

@test "_select_output_pix_fmt: reste en 8-bit par défaut" {
    result=$(_select_output_pix_fmt "yuv420p")
    [ "$result" = "yuv420p" ]
}

@test "_select_output_pix_fmt: 10-bit même si pix_fmt exotique" {
    result=$(_select_output_pix_fmt "yuv422p10le")
    [ "$result" = "yuv420p10le" ]
}

@test "_build_downscale_filter_if_needed: vide pour 1920x1080" {
    result=$(_build_downscale_filter_if_needed 1920 1080)
    [ -z "$result" ]
}

@test "_build_downscale_filter_if_needed: non-vide pour 3840x2160" {
    result=$(_build_downscale_filter_if_needed 3840 2160)
    [ -n "$result" ]
    [[ "$result" =~ scale= ]]
}

@test "_build_downscale_filter_if_needed: non-vide si hauteur > 1080" {
    result=$(_build_downscale_filter_if_needed 1280 1440)
    [ -n "$result" ]
}

@test "_build_downscale_filter_if_needed: vide si largeur/hauteur invalides" {
    result=$(_build_downscale_filter_if_needed "" "")
    [ -z "$result" ]

    result=$(_build_downscale_filter_if_needed "abc" "1080")
    [ -z "$result" ]
}

@test "_compute_output_height_for_bitrate: inchangé sans downscale" {
    result=$(_compute_output_height_for_bitrate 1280 720)
    [ "$result" -eq 720 ]
}

@test "_compute_output_height_for_bitrate: 4K downscale vers 1080" {
    result=$(_compute_output_height_for_bitrate 3840 2160)
    [ "$result" -eq 1080 ]
}

@test "_compute_output_height_for_bitrate: ultra-wide (2560x720) downscale vers 540" {
    result=$(_compute_output_height_for_bitrate 2560 720)
    [ "$result" -eq 540 ]
}

@test "_compute_effective_bitrate_kbps_for_height: applique le facteur 720p" {
    # Valeur base = mode série (2070), profil 720p => 70%
    result=$(_compute_effective_bitrate_kbps_for_height 2070 720)
    [ "$result" -eq 1449 ]
}

@test "_compute_effective_bitrate_kbps_for_height: ne change pas au-dessus de 720p" {
    result=$(_compute_effective_bitrate_kbps_for_height 2070 1080)
    [ "$result" -eq 2070 ]
}

@test "_build_effective_suffix_for_dims: inclut bitrate+résolution+preset (720p)" {
    # 1280x720 => out_height=720 => scale 70% => 1449k
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    VIDEO_CODEC="hevc"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1280 720)
    # Vérifier le pattern : _<codec>_<bitrate>k_<height>p_<preset>_tuned
    [[ "$result" =~ ^_x265_[0-9]+k_720p_medium_tuned$ ]]
    [[ "$result" =~ "_1449k_" ]]
}

@test "_build_effective_suffix_for_dims: reflète 1080p quand hauteur 1080" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    VIDEO_CODEC="hevc"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    # Vérifier le pattern : _<codec>_<bitrate>k_<height>p_<preset>_tuned
    [[ "$result" =~ ^_x265_[0-9]+k_1080p_medium_tuned$ ]]
    [[ "$result" =~ "_2070k_" ]]
}

###########################################################
# Tests du mode single-pass CRF
###########################################################

@test "_build_effective_suffix_for_dims: affiche CRF en mode single-pass (1080p)" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="hevc"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    # Vérifier le pattern CRF : _<codec>_crf<N>_<height>p_<preset>_tuned
    [[ "$result" =~ ^_x265_crf[0-9]+_1080p_medium_tuned$ ]]
}

@test "_build_effective_suffix_for_dims: affiche CRF en mode single-pass (720p)" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="hevc"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1280 720)
    # Vérifier le pattern CRF : _<codec>_crf<N>_<height>p_<preset>_tuned
    [[ "$result" =~ ^_x265_crf[0-9]+_720p_medium_tuned$ ]]
}

@test "_build_effective_suffix_for_dims: CRF identique quelle que soit la résolution" {
    # En mode CRF, la valeur CRF est constante (pas d'adaptation par résolution)
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="hevc"
    set_conversion_mode_parameters

    result_720=$(_build_effective_suffix_for_dims 1280 720)
    result_1080=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result_720" =~ "_crf" ]]
    [[ "$result_1080" =~ "_crf" ]]
}

###########################################################
# Tests multi-codec (AV1)
###########################################################

@test "_build_effective_suffix_for_dims: AV1 utilise suffixe _av1" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    VIDEO_CODEC="av1"
    VIDEO_ENCODER="libsvtav1"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    [[ "$result" =~ ^_av1_ ]]
    [[ "$result" =~ "_1080p_" ]]
}

@test "_build_effective_suffix_for_dims: AV1 CRF utilise suffixe _av1" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="av1"
    VIDEO_ENCODER="libsvtav1"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    [[ "$result" =~ ^_av1_crf ]]
}
