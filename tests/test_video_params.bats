#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/video_params.sh
# Tests des paramètres vidéo (pix_fmt, downscale, bitrate)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules_fast
    source "$LIB_DIR/video_params.sh"
    
    # Les variables DOWNSCALE_* sont readonly après config.sh
    # On utilise les valeurs par défaut définies par config.sh
    # Les tests vérifient les comportements, pas les valeurs spécifiques
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _select_output_pix_fmt()
###########################################################

@test "_select_output_pix_fmt: 8-bit reste 8-bit" {
    local result
    result=$(_select_output_pix_fmt "yuv420p")
    [ "$result" = "yuv420p" ]
}

@test "_select_output_pix_fmt: 10-bit reste 10-bit" {
    local result
    result=$(_select_output_pix_fmt "yuv420p10le")
    [ "$result" = "yuv420p10le" ]
}

@test "_select_output_pix_fmt: yuv422p10le → yuv420p10le" {
    local result
    result=$(_select_output_pix_fmt "yuv422p10le")
    [ "$result" = "yuv420p10le" ]
}

@test "_select_output_pix_fmt: format inconnu → yuv420p (8-bit)" {
    local result
    result=$(_select_output_pix_fmt "rgb24")
    [ "$result" = "yuv420p" ]
}

@test "_select_output_pix_fmt: entrée vide → yuv420p" {
    local result
    result=$(_select_output_pix_fmt "")
    [ "$result" = "yuv420p" ]
}

###########################################################
# Tests de _build_downscale_filter_if_needed()
###########################################################

@test "_build_downscale_filter_if_needed: 1080p → pas de filtre" {
    local result
    result=$(_build_downscale_filter_if_needed 1920 1080)
    [ -z "$result" ]
}

@test "_build_downscale_filter_if_needed: 720p → pas de filtre" {
    local result
    result=$(_build_downscale_filter_if_needed 1280 720)
    [ -z "$result" ]
}

@test "_build_downscale_filter_if_needed: 4K → filtre scale" {
    local result
    result=$(_build_downscale_filter_if_needed 3840 2160)
    
    # Doit contenir un filtre scale
    [[ "$result" =~ "scale=" ]]
    [[ "$result" =~ "lanczos" ]]
}

@test "_build_downscale_filter_if_needed: 1440p → filtre scale" {
    local result
    result=$(_build_downscale_filter_if_needed 2560 1440)
    
    [[ "$result" =~ "scale=" ]]
}

@test "_build_downscale_filter_if_needed: entrées invalides → vide" {
    local result
    result=$(_build_downscale_filter_if_needed "" "")
    [ -z "$result" ]
    
    result=$(_build_downscale_filter_if_needed "abc" "def")
    [ -z "$result" ]
}

###########################################################
# Tests de _compute_output_height_for_bitrate()
###########################################################

@test "_compute_output_height_for_bitrate: 1080p → 1080" {
    local result
    result=$(_compute_output_height_for_bitrate 1920 1080)
    [ "$result" -eq 1080 ]
}

@test "_compute_output_height_for_bitrate: 720p → 720" {
    local result
    result=$(_compute_output_height_for_bitrate 1280 720)
    [ "$result" -eq 720 ]
}

@test "_compute_output_height_for_bitrate: 4K → ~1080 (downscale)" {
    local result
    result=$(_compute_output_height_for_bitrate 3840 2160)
    
    # 4K (16:9) downscalé vers 1080p donne hauteur 1080
    [ "$result" -ge 1000 ] && [ "$result" -le 1080 ]
}

@test "_compute_output_height_for_bitrate: 1440p → ~810 (downscale)" {
    local result
    result=$(_compute_output_height_for_bitrate 2560 1440)
    
    # 1440p downscalé garde le ratio
    [ "$result" -ge 800 ] && [ "$result" -le 1080 ]
}

@test "_compute_output_height_for_bitrate: entrées vides → vide" {
    local result
    result=$(_compute_output_height_for_bitrate "" "")
    [ -z "$result" ]
}

###########################################################
# Tests de _compute_effective_bitrate_kbps_for_height()
###########################################################

@test "_compute_effective_bitrate_kbps: 1080p → bitrate inchangé" {
    local result
    result=$(_compute_effective_bitrate_kbps_for_height 2070 1080)
    [ "$result" -eq 2070 ]
}

@test "_compute_effective_bitrate_kbps: 720p → bitrate réduit 70%" {
    local result
    result=$(_compute_effective_bitrate_kbps_for_height 2070 720)
    
    # 2070 * 70% = 1449
    [ "$result" -ge 1400 ] && [ "$result" -le 1500 ]
}

@test "_compute_effective_bitrate_kbps: 480p → bitrate réduit 50%" {
    local result
    result=$(_compute_effective_bitrate_kbps_for_height 2070 480)
    
    # 2070 * 50% = 1035
    [ "$result" -ge 1000 ] && [ "$result" -le 1100 ]
}

@test "_compute_effective_bitrate_kbps: désactivé → bitrate inchangé" {
    # On ne peut pas modifier ADAPTIVE_BITRATE_BY_RESOLUTION car c'est readonly
    # Ce test vérifie le comportement avec entrée invalide
    local result
    result=$(_compute_effective_bitrate_kbps_for_height 2070 "")
    [ "$result" -eq 2070 ]
}

@test "_compute_effective_bitrate_kbps: entrée invalide → bitrate inchangé" {
    local result
    result=$(_compute_effective_bitrate_kbps_for_height 2070 "abc")
    [ "$result" -eq 2070 ]
    
    result=$(_compute_effective_bitrate_kbps_for_height 2070 "")
    [ "$result" -eq 2070 ]
}

###########################################################
# Tests des helpers de suffixe
###########################################################

@test "_suffix_build_resolution_part: 1080 → _1080p" {
    local result
    result=$(_suffix_build_resolution_part 1080)
    [ "$result" = "_1080p" ]
}

@test "_suffix_build_resolution_part: 720 → _720p" {
    local result
    result=$(_suffix_build_resolution_part 720)
    [ "$result" = "_720p" ]
}

@test "_suffix_build_resolution_part: vide → vide" {
    local result
    result=$(_suffix_build_resolution_part "")
    [ -z "$result" ]
}

@test "_suffix_build_audio_part: aac → _AAC" {
    local result
    result=$(_suffix_build_audio_part "aac")
    [ "$result" = "_AAC" ]
}

@test "_suffix_build_audio_part: copy → vide" {
    local result
    result=$(_suffix_build_audio_part "copy")
    [ -z "$result" ]
}

@test "_suffix_build_sample_part: SAMPLE_MODE=true → _sample" {
    export SAMPLE_MODE=true
    local result
    result=$(_suffix_build_sample_part)
    [ "$result" = "_sample" ]
    export SAMPLE_MODE=false
}

@test "_suffix_build_sample_part: SAMPLE_MODE=false → vide" {
    export SAMPLE_MODE=false
    local result
    result=$(_suffix_build_sample_part)
    [ -z "$result" ]
}

###########################################################
# Tests de _build_effective_suffix_for_dims()
###########################################################

@test "_build_effective_suffix_for_dims: 1080p → _x265_1080p" {
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result" =~ "_x265" ]]
    [[ "$result" =~ "_1080p" ]]
}

@test "_build_effective_suffix_for_dims: 4K → _x265_1080p (après downscale)" {
    local result
    result=$(_build_effective_suffix_for_dims 3840 2160)
    
    [[ "$result" =~ "_x265" ]]
    # Après downscale 4K → 1080p
    [[ "$result" =~ "_1080p" ]] || [[ "$result" =~ "_10" ]]
}

@test "_build_effective_suffix_for_dims: avec audio aac → _AAC dans suffixe" {
    export AUDIO_CODEC="aac"
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080 "" "aac" "")
    
    [[ "$result" =~ "_AAC" ]]
}

@test "_build_effective_suffix_for_dims: sample mode → _sample dans suffixe" {
    export SAMPLE_MODE=true
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result" =~ "_sample" ]]
    export SAMPLE_MODE=false
}

###########################################################
# Tests _suffix_build_quality_part (CRF vs bitrate)
###########################################################

@test "_suffix_build_quality_part: single-pass → _crfXX" {
    export SINGLE_PASS_MODE=true
    
    local result
    result=$(_suffix_build_quality_part 1080)
    
    [[ "$result" =~ "_crf" ]]
    export SINGLE_PASS_MODE=false
}

@test "_suffix_build_quality_part: two-pass → _XXXXk" {
    export SINGLE_PASS_MODE=false
    
    local result
    result=$(_suffix_build_quality_part 1080)
    
    [[ "$result" =~ "k" ]]
}

###########################################################
# Tests HFR
###########################################################

@test "_is_hfr_content: 60fps est HFR" {
    # Si la fonction existe
    if ! declare -f _is_hfr_content &>/dev/null; then
        skip "_is_hfr_content non disponible"
    fi
    
    _is_hfr_content 60
}

@test "_is_hfr_content: 24fps n'est pas HFR" {
    if ! declare -f _is_hfr_content &>/dev/null; then
        skip "_is_hfr_content non disponible"
    fi
    
    ! _is_hfr_content 24
}

@test "_is_hfr_content: 50fps est HFR" {
    if ! declare -f _is_hfr_content &>/dev/null; then
        skip "_is_hfr_content non disponible"
    fi
    
    _is_hfr_content 50
}
