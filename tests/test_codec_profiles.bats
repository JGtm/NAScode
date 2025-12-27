#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/codec_profiles.sh
# Tests des fonctions de profils de codecs et encodeurs
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal
    source "$LIB_DIR/codec_profiles.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests get_codec_encoder()
###########################################################

@test "get_codec_encoder: retourne libx265 pour hevc" {
    result=$(get_codec_encoder "hevc")
    [ "$result" = "libx265" ]
}

@test "get_codec_encoder: retourne libsvtav1 pour av1" {
    result=$(get_codec_encoder "av1")
    [ "$result" = "libsvtav1" ]
}

@test "get_codec_encoder: fallback libx265 pour codec inconnu" {
    result=$(get_codec_encoder "unknown_codec")
    [ "$result" = "libx265" ]
}

@test "get_codec_encoder: fallback libx265 sans argument" {
    result=$(get_codec_encoder)
    [ "$result" = "libx265" ]
}

###########################################################
# Tests get_codec_suffix()
###########################################################

@test "get_codec_suffix: retourne x265 pour hevc" {
    result=$(get_codec_suffix "hevc")
    [ "$result" = "x265" ]
}

@test "get_codec_suffix: retourne av1 pour av1" {
    result=$(get_codec_suffix "av1")
    [ "$result" = "av1" ]
}

@test "get_codec_suffix: fallback x265 pour codec inconnu" {
    result=$(get_codec_suffix "unknown")
    [ "$result" = "x265" ]
}

###########################################################
# Tests is_codec_match()
###########################################################

@test "is_codec_match: hevc matche hevc" {
    is_codec_match "hevc" "hevc"
}

@test "is_codec_match: h265 matche hevc" {
    is_codec_match "h265" "hevc"
}

@test "is_codec_match: av1 matche av1" {
    is_codec_match "av1" "av1"
}

@test "is_codec_match: hevc ne matche pas av1" {
    ! is_codec_match "hevc" "av1"
}

@test "is_codec_match: av1 ne matche pas hevc" {
    ! is_codec_match "av1" "hevc"
}

###########################################################
# Tests is_codec_supported()
###########################################################

@test "is_codec_supported: hevc est supporté" {
    is_codec_supported "hevc"
}

@test "is_codec_supported: av1 est supporté" {
    is_codec_supported "av1"
}

@test "is_codec_supported: vp9 n'est pas supporté" {
    ! is_codec_supported "vp9"
}

###########################################################
# Tests list_supported_codecs()
###########################################################

@test "list_supported_codecs: contient hevc" {
    result=$(list_supported_codecs)
    [[ "$result" =~ "hevc" ]]
}

@test "list_supported_codecs: contient av1" {
    result=$(list_supported_codecs)
    [[ "$result" =~ "av1" ]]
}

###########################################################
# Tests get_codec_rank()
###########################################################

@test "get_codec_rank: av1 a le rang le plus élevé" {
    av1_rank=$(get_codec_rank "av1")
    hevc_rank=$(get_codec_rank "hevc")
    [ "$av1_rank" -gt "$hevc_rank" ]
}

@test "get_codec_rank: hevc et h265 ont le même rang" {
    hevc_rank=$(get_codec_rank "hevc")
    h265_rank=$(get_codec_rank "h265")
    [ "$hevc_rank" -eq "$h265_rank" ]
}

@test "get_codec_rank: h264 a rang 0 (non supporté)" {
    result=$(get_codec_rank "h264")
    [ "$result" -eq 0 ]
}

###########################################################
# Tests is_codec_better_or_equal()
###########################################################

@test "is_codec_better_or_equal: av1 >= hevc" {
    run is_codec_better_or_equal "av1" "hevc"
    [ "$status" -eq 0 ]
}

@test "is_codec_better_or_equal: av1 >= av1" {
    run is_codec_better_or_equal "av1" "av1"
    [ "$status" -eq 0 ]
}

@test "is_codec_better_or_equal: hevc >= hevc" {
    run is_codec_better_or_equal "hevc" "hevc"
    [ "$status" -eq 0 ]
}

@test "is_codec_better_or_equal: hevc < av1 (false)" {
    run is_codec_better_or_equal "hevc" "av1"
    [ "$status" -ne 0 ]
}

@test "is_codec_better_or_equal: h264 < hevc (false)" {
    run is_codec_better_or_equal "h264" "hevc"
    [ "$status" -ne 0 ]
}

@test "is_codec_better_or_equal: h265 >= hevc (alias)" {
    run is_codec_better_or_equal "h265" "hevc"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests get_encoder_mode_params()
###########################################################

@test "get_encoder_mode_params: libx265 serie retourne des params" {
    result=$(get_encoder_mode_params "libx265" "serie")
    [ -n "$result" ]
    [[ "$result" =~ "sao=0" ]]
}

@test "get_encoder_mode_params: libx265 film retourne vide (défauts)" {
    result=$(get_encoder_mode_params "libx265" "film")
    [ -z "$result" ]
}

@test "get_encoder_mode_params: libsvtav1 serie retourne tune=0" {
    result=$(get_encoder_mode_params "libsvtav1" "serie")
    [[ "$result" =~ "tune=0" ]]
}

@test "get_encoder_mode_params: libsvtav1 serie retourne enable-overlays=1" {
    result=$(get_encoder_mode_params "libsvtav1" "serie")
    [[ "$result" =~ "enable-overlays=1" ]]
}

@test "get_encoder_mode_params: libsvtav1 film retourne film-grain" {
    result=$(get_encoder_mode_params "libsvtav1" "film")
    [[ "$result" =~ "film-grain" ]]
}

###########################################################
# Tests get_encoder_params_flag()
###########################################################

@test "get_encoder_params_flag: libx265 retourne -x265-params" {
    result=$(get_encoder_params_flag "libx265")
    [ "$result" = "-x265-params" ]
}

@test "get_encoder_params_flag: libsvtav1 retourne -svtav1-params" {
    result=$(get_encoder_params_flag "libsvtav1")
    [ "$result" = "-svtav1-params" ]
}

@test "get_encoder_params_flag: libaom-av1 retourne vide" {
    result=$(get_encoder_params_flag "libaom-av1")
    [ -z "$result" ]
}

###########################################################
# Tests build_encoder_params()
###########################################################

@test "build_encoder_params: combine base et mode params" {
    result=$(build_encoder_params "libx265" "serie" "vbv-maxrate=2520:vbv-bufsize=3780")
    [[ "$result" =~ "vbv-maxrate=2520" ]]
    [[ "$result" =~ "sao=0" ]]
}

@test "build_encoder_params: base vide avec mode params" {
    result=$(build_encoder_params "libx265" "serie" "")
    [[ "$result" =~ "sao=0" ]]
}

@test "build_encoder_params: base seule si pas de mode params" {
    result=$(build_encoder_params "libx265" "film" "vbv-maxrate=3200")
    [ "$result" = "vbv-maxrate=3200" ]
}

###########################################################
# Tests build_vbv_params()
###########################################################

@test "build_vbv_params: libx265 génère vbv-maxrate:vbv-bufsize" {
    result=$(build_vbv_params "libx265" 2520 3780)
    [ "$result" = "vbv-maxrate=2520:vbv-bufsize=3780" ]
}

@test "build_vbv_params: libsvtav1 retourne vide (VBV via FFmpeg)" {
    result=$(build_vbv_params "libsvtav1" 2520 3780)
    [ -z "$result" ]
}

###########################################################
# Tests get_mode_keyint()
###########################################################

@test "get_mode_keyint: serie retourne 600" {
    result=$(get_mode_keyint "serie")
    [ "$result" -eq 600 ]
}

@test "get_mode_keyint: film retourne 240" {
    result=$(get_mode_keyint "film")
    [ "$result" -eq 240 ]
}

###########################################################
# Tests is_pass1_fast()
###########################################################

@test "is_pass1_fast: serie retourne true" {
    result=$(is_pass1_fast "serie")
    [ "$result" = "true" ]
}

@test "is_pass1_fast: film retourne false" {
    result=$(is_pass1_fast "film")
    [ "$result" = "false" ]
}

###########################################################
# Tests convert_preset()
###########################################################

@test "convert_preset: medium -> libsvtav1 retourne ~5" {
    result=$(convert_preset "medium" "libsvtav1")
    [ "$result" -eq 5 ]
}

@test "convert_preset: slow -> libsvtav1 retourne ~4" {
    result=$(convert_preset "slow" "libsvtav1")
    [ "$result" -eq 4 ]
}

@test "convert_preset: medium -> libx265 retourne medium" {
    result=$(convert_preset "medium" "libx265")
    [ "$result" = "medium" ]
}

@test "convert_preset: medium -> libaom-av1 retourne ~4" {
    result=$(convert_preset "medium" "libaom-av1")
    [ "$result" -eq 4 ]
}

###########################################################
# Tests d'intégration avec VIDEO_CODEC
###########################################################

@test "VIDEO_CODEC: défaut est hevc" {
    # Recharger pour tester la valeur par défaut
    unset VIDEO_CODEC
    source "$LIB_DIR/codec_profiles.sh"
    [ "${VIDEO_CODEC:-hevc}" = "hevc" ]
}

@test "VIDEO_CODEC: peut être changé avant chargement" {
    VIDEO_CODEC="av1"
    source "$LIB_DIR/codec_profiles.sh"
    [ "$VIDEO_CODEC" = "av1" ]
}
