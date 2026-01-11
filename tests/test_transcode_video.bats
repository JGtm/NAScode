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
    AUDIO_CODEC="copy"  # Forcer copy pour un suffixe prévisible
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1280 720)
    # Vérifier le pattern : _<codec>_<bitrate>k_<height>p_<preset>
    [[ "$result" =~ ^_x265_[0-9]+k_720p_medium$ ]]
    [[ "$result" =~ "_1449k_" ]]
}

@test "_build_effective_suffix_for_dims: reflète 1080p quand hauteur 1080" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    VIDEO_CODEC="hevc"
    AUDIO_CODEC="copy"  # Forcer copy pour un suffixe prévisible
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    # Vérifier le pattern : _<codec>_<bitrate>k_<height>p_<preset>
    [[ "$result" =~ ^_x265_[0-9]+k_1080p_medium$ ]]
    [[ "$result" =~ "_2070k_" ]]
}

###########################################################
# Tests du mode single-pass CRF
###########################################################

@test "_build_effective_suffix_for_dims: affiche CRF en mode single-pass (1080p)" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="hevc"
    AUDIO_CODEC="copy"  # Forcer copy pour un suffixe prévisible
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    # Vérifier le pattern CRF : _<codec>_crf<N>_<height>p_<preset>
    [[ "$result" =~ ^_x265_crf[0-9]+_1080p_medium$ ]]
}

@test "_build_effective_suffix_for_dims: affiche CRF en mode single-pass (720p)" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="hevc"
    AUDIO_CODEC="copy"  # Forcer copy pour un suffixe prévisible
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1280 720)
    # Vérifier le pattern CRF : _<codec>_crf<N>_<height>p_<preset>
    [[ "$result" =~ ^_x265_crf[0-9]+_720p_medium$ ]]
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
    # Skip si libsvtav1 n'est pas disponible dans FFmpeg
    if ! ffmpeg -encoders 2>/dev/null | grep -q libsvtav1; then
        skip "libsvtav1 non disponible dans FFmpeg"
    fi
    
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
    # Skip si libsvtav1 n'est pas disponible dans FFmpeg
    if ! ffmpeg -encoders 2>/dev/null | grep -q libsvtav1; then
        skip "libsvtav1 non disponible dans FFmpeg"
    fi
    
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    VIDEO_CODEC="av1"
    VIDEO_ENCODER="libsvtav1"
    set_conversion_mode_parameters

    result=$(_build_effective_suffix_for_dims 1920 1080)
    [[ "$result" =~ ^_av1_crf ]]
}

###########################################################
# Tests _get_preset_option() pour SVT-AV1
###########################################################

@test "_get_preset_option: libx265 retourne -preset medium" {
    ENCODER_PRESET="medium"
    result=$(_get_preset_option "libx265" "medium")
    [ "$result" = "-preset medium" ]
}

@test "_get_preset_option: libsvtav1 utilise SVTAV1_PRESET_DEFAULT" {
    # SVTAV1_PRESET_DEFAULT=8 par défaut dans codec_profiles.sh
    result=$(_get_preset_option "libsvtav1" "medium")
    [ "$result" = "-preset 8" ]
}

@test "_get_preset_option: libsvtav1 avec SVTAV1_PRESET override" {
    SVTAV1_PRESET="6"
    result=$(_get_preset_option "libsvtav1" "medium")
    [ "$result" = "-preset 6" ]
    unset SVTAV1_PRESET
}

###########################################################
# Tests _get_bitrate_option() pour SVT-AV1
###########################################################

@test "_get_bitrate_option: libx265 CRF retourne -crf N" {
    CRF_VALUE=21
    result=$(_get_bitrate_option "libx265" "crf")
    [ "$result" = "-crf 21" ]
}

@test "_get_bitrate_option: libsvtav1 CRF utilise SVTAV1_CRF_DEFAULT" {
    # SVTAV1_CRF_DEFAULT=32 par défaut
    result=$(_get_bitrate_option "libsvtav1" "crf")
    [ "$result" = "-crf 32" ]
}

@test "_get_bitrate_option: libsvtav1 avec SVTAV1_CRF override" {
    SVTAV1_CRF="28"
    result=$(_get_bitrate_option "libsvtav1" "crf")
    [ "$result" = "-crf 28" ]
    unset SVTAV1_CRF
}

@test "_get_bitrate_option: two-pass retourne -b:v" {
    VIDEO_BITRATE="2070k"
    result=$(_get_bitrate_option "libx265" "pass2")
    [ "$result" = "-b:v 2070k" ]
}

###########################################################
# Tests _build_encoder_params_internal() pour SVT-AV1
###########################################################

@test "_build_encoder_params_internal: libsvtav1 pass1 inclut pass=1" {
    result=$(_build_encoder_params_internal "libsvtav1" "pass1" "tune=0")
    [[ "$result" =~ "pass=1" ]]
    [[ "$result" =~ "tune=0" ]]
}

@test "_build_encoder_params_internal: libsvtav1 pass2 inclut pass=2" {
    result=$(_build_encoder_params_internal "libsvtav1" "pass2" "tune=0:keyint=240")
    [[ "$result" =~ "pass=2" ]]
    [[ "$result" =~ "keyint=240" ]]
}

@test "_build_encoder_params_internal: libsvtav1 crf sans pass" {
    result=$(_build_encoder_params_internal "libsvtav1" "crf" "tune=0:enable-overlays=1")
    [[ ! "$result" =~ "pass=" ]]
    [[ "$result" =~ "tune=0" ]]
    [[ "$result" =~ "enable-overlays=1" ]]
}

###########################################################
# Tests MBR (Maximum BitRate) pour SVT-AV1 CRF contraint
###########################################################

@test "_setup_video_encoding_params: SVT-AV1 ajoute mbr en mode single-pass" {
    # Setup minimal pour SVT-AV1 en mode single-pass CRF
    SINGLE_PASS_MODE=true
    VIDEO_ENCODER="libsvtav1"
    EFFECTIVE_VIDEO_ENCODER="libsvtav1"
    TARGET_CODEC="av1"
    TARGET_BITRATE_KBPS=2070
    MAXRATE_KBPS=2520
    BUFSIZE_KBPS=3780
    ENCODER_PRESET="medium"
    FILM_KEYINT=240
    ENCODER_MODE_PROFILE="film"
    NO_PROGRESS=true
    
    _setup_video_encoding_params 1920 1080 "yuv420p"
    
    # Vérifier que mbr est dans ENCODER_BASE_PARAMS
    [[ "$ENCODER_BASE_PARAMS" =~ "mbr=" ]]
}

@test "_setup_video_encoding_params: SVT-AV1 mbr utilise effective_maxrate" {
    SINGLE_PASS_MODE=true
    VIDEO_ENCODER="libsvtav1"
    EFFECTIVE_VIDEO_ENCODER="libsvtav1"
    TARGET_CODEC="av1"
    TARGET_BITRATE_KBPS=1000
    MAXRATE_KBPS=1500
    BUFSIZE_KBPS=2250
    ENCODER_PRESET="medium"
    FILM_KEYINT=240
    ENCODER_MODE_PROFILE="film"
    NO_PROGRESS=true
    
    _setup_video_encoding_params 1280 720 "yuv420p"
    
    # mbr doit être présent avec une valeur (effective_maxrate après ajustement 720p)
    [[ "$ENCODER_BASE_PARAMS" =~ "mbr=" ]]
    # Vérifier qu'on a bien une valeur numérique
    local mbr_value
    mbr_value=$(echo "$ENCODER_BASE_PARAMS" | grep -oP 'mbr=\K[0-9]+')
    [[ -n "$mbr_value" ]]
    [[ "$mbr_value" -gt 0 ]]
}

###########################################################
# Note: _get_encoder_params_flag_internal() a été supprimée (duplication).
# Utiliser get_encoder_params_flag() de codec_profiles.sh à la place.
# Les tests correspondants sont dans test_codec_profiles.bats.
###########################################################
