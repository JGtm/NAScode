#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Audio Multi-channel & --no-lossless
# Tests des règles: DTS passthrough, EAC3 default, downmix 5.1
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    if [[ -z "${_MULTICHANNEL_TEST_LOADED:-}" ]]; then
        export SCRIPT_DIR="$PROJECT_ROOT"
        source "$LIB_DIR/ui.sh"
        # Mock detect.sh variables
        export HAS_MD5SUM=1 HAS_MD5=0 HAS_PYTHON3=1 HAS_DATE_NANO=1 HAS_PERL_HIRES=0
        export HAS_GAWK=1 HAS_SHA256SUM=1 HAS_SHASUM=0 HAS_OPENSSL=1
        export HAS_LIBVMAF=0 FFMPEG_VMAF=""
        export IS_MSYS=0 IS_MACOS=0 IS_LINUX=1
        export HAS_LIBSVTAV1=1 HAS_LIBX265=1 HAS_LIBAOM=0
        source "$LIB_DIR/config.sh"
        source "$LIB_DIR/codec_profiles.sh"
        source "$LIB_DIR/utils.sh"
        source "$LIB_DIR/media_probe.sh"
        source "$LIB_DIR/audio_params.sh"
        _MULTICHANNEL_TEST_LOADED=1
    fi
    
    # Reset defaults
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    NO_LOSSLESS=false
    FORCE_AUDIO_CODEC=false
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests is_audio_codec_premium_passthrough()
###########################################################

@test "is_audio_codec_premium_passthrough: DTS retourne true" {
    run is_audio_codec_premium_passthrough "dts"
    [ "$status" -eq 0 ]
}

@test "is_audio_codec_premium_passthrough: DTS-HD retourne true" {
    run is_audio_codec_premium_passthrough "dts-hd"
    [ "$status" -eq 0 ]
}

@test "is_audio_codec_premium_passthrough: TrueHD retourne true" {
    run is_audio_codec_premium_passthrough "truehd"
    [ "$status" -eq 0 ]
}

@test "is_audio_codec_premium_passthrough: FLAC retourne true" {
    run is_audio_codec_premium_passthrough "flac"
    [ "$status" -eq 0 ]
}

@test "is_audio_codec_premium_passthrough: AAC retourne false" {
    run is_audio_codec_premium_passthrough "aac"
    [ "$status" -eq 1 ]
}

@test "is_audio_codec_premium_passthrough: EAC3 retourne false" {
    run is_audio_codec_premium_passthrough "eac3"
    [ "$status" -eq 1 ]
}

###########################################################
# Tests get_audio_codec_rank() - DTS reclassé en premium
###########################################################

@test "get_audio_codec_rank: DTS a rang >= 10 (premium)" {
    local rank
    rank=$(get_audio_codec_rank "dts")
    [ "$rank" -ge 10 ]
}

@test "get_audio_codec_rank: DTS-HD a rang >= 10 (premium)" {
    local rank
    rank=$(get_audio_codec_rank "dts-hd")
    [ "$rank" -ge 10 ]
}

@test "get_audio_codec_rank: TrueHD a rang >= 10 (premium)" {
    local rank
    rank=$(get_audio_codec_rank "truehd")
    [ "$rank" -ge 10 ]
}

@test "get_audio_codec_rank: AC3 a rang < 10 (inefficace)" {
    local rank
    rank=$(get_audio_codec_rank "ac3")
    [ "$rank" -lt 10 ]
}

###########################################################
# Tests _compute_eac3_target_bitrate_kbps() - anti-upscale
###########################################################

@test "_compute_eac3_target_bitrate_kbps: source inconnue → plafond 384" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 0)
    [ "$result" -eq 384 ]
}

@test "_compute_eac3_target_bitrate_kbps: source 640 → plafond 384" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 640)
    [ "$result" -eq 384 ]
}

@test "_compute_eac3_target_bitrate_kbps: source 300 → garde 300 (anti-upscale)" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 300)
    [ "$result" -eq 300 ]
}

@test "_compute_eac3_target_bitrate_kbps: source 384 → garde 384 (exactement le plafond)" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 384)
    [ "$result" -eq 384 ]
}

###########################################################
# Tests _get_multichannel_target_bitrate()
###########################################################

@test "_get_multichannel_target_bitrate: opus → 224k" {
    local result
    result=$(_get_multichannel_target_bitrate "opus")
    [ "$result" -eq 224 ]
}

@test "_get_multichannel_target_bitrate: aac → 320k" {
    local result
    result=$(_get_multichannel_target_bitrate "aac")
    [ "$result" -eq 320 ]
}

@test "_get_multichannel_target_bitrate: eac3 → 384k" {
    local result
    result=$(_get_multichannel_target_bitrate "eac3")
    [ "$result" -eq 384 ]
}

###########################################################
# Tests _get_target_audio_layout() - toujours 5.1 si multichannel
###########################################################

@test "_get_target_audio_layout: 2 channels → stereo" {
    local result
    result=$(_get_target_audio_layout 2)
    [ "$result" = "stereo" ]
}

@test "_get_target_audio_layout: 6 channels → 5.1" {
    local result
    result=$(_get_target_audio_layout 6)
    [ "$result" = "5.1" ]
}

@test "_get_target_audio_layout: 8 channels → 5.1 (downmix)" {
    local result
    result=$(_get_target_audio_layout 8)
    [ "$result" = "5.1" ]
}

###########################################################
# Tests _get_smart_audio_decision() - DTS/TrueHD passthrough
###########################################################

@test "smart decision: DTS 5.1 → copy (passthrough)" {
    AUDIO_CODEC="aac"
    NO_LOSSLESS=false
    
    local result action
    result=$(_get_smart_audio_decision "/fake.mkv" "dts" "1509" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    
    [ "$action" = "copy" ]
}

@test "smart decision: DTS 7.1 → convert EAC3 (downmix required)" {
    AUDIO_CODEC="aac"
    NO_LOSSLESS=false
    
    local result action codec
    result=$(_get_smart_audio_decision "/fake.mkv" "dts" "1509" "8")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    
    [ "$action" = "convert" ]
    [ "$codec" = "eac3" ]
}

@test "smart decision: TrueHD 5.1 → copy (passthrough)" {
    AUDIO_CODEC="aac"
    NO_LOSSLESS=false
    
    local result action
    result=$(_get_smart_audio_decision "/fake.mkv" "truehd" "0" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    
    [ "$action" = "copy" ]
}

@test "smart decision: TrueHD 7.1 → convert EAC3 (downmix required)" {
    AUDIO_CODEC="aac"
    NO_LOSSLESS=false
    
    local result action codec
    result=$(_get_smart_audio_decision "/fake.mkv" "truehd" "0" "8")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    
    [ "$action" = "convert" ]
    [ "$codec" = "eac3" ]
}

###########################################################
# Tests _get_smart_audio_decision() - --no-lossless
###########################################################

@test "smart decision: DTS 5.1 + --no-lossless → convert EAC3" {
    AUDIO_CODEC="aac"
    NO_LOSSLESS=true
    
    local result action codec
    result=$(_get_smart_audio_decision "/fake.mkv" "dts" "1509" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    
    [ "$action" = "convert" ]
    [ "$codec" = "eac3" ]
}

@test "smart decision: FLAC stereo + --no-lossless → convert codec cible" {
    AUDIO_CODEC="aac"
    NO_LOSSLESS=true
    
    local result action codec
    result=$(_get_smart_audio_decision "/fake.mkv" "flac" "0" "2")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    
    [ "$action" = "convert" ]
    [ "$codec" = "aac" ]
}

@test "smart decision: TrueHD 5.1 + --no-lossless → convert EAC3 384k" {
    AUDIO_CODEC="opus"  # Même avec opus en cible, multichannel no-lossless → EAC3
    NO_LOSSLESS=true
    
    local result action codec bitrate
    result=$(_get_smart_audio_decision "/fake.mkv" "truehd" "0" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    bitrate=$(echo "$result" | cut -d'|' -f3)
    
    [ "$action" = "convert" ]
    [ "$codec" = "eac3" ]
    [ "$bitrate" -eq 384 ]
}

###########################################################
# Tests _get_smart_audio_decision() - EAC3 multichannel
###########################################################

@test "smart decision: EAC3 5.1 384k → copy" {
    AUDIO_CODEC="aac"
    
    local result action
    result=$(_get_smart_audio_decision "/fake.mkv" "eac3" "384" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    
    [ "$action" = "copy" ]
}

@test "smart decision: EAC3 5.1 448k → downscale 384k" {
    AUDIO_CODEC="aac"
    
    local result action codec bitrate
    result=$(_get_smart_audio_decision "/fake.mkv" "eac3" "448" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    bitrate=$(echo "$result" | cut -d'|' -f3)
    
    [ "$action" = "downscale" ]
    [ "$codec" = "eac3" ]
    [ "$bitrate" -eq 384 ]
}

@test "smart decision: EAC3 7.1 → convert EAC3 (downmix)" {
    AUDIO_CODEC="aac"
    
    local result action reason
    result=$(_get_smart_audio_decision "/fake.mkv" "eac3" "640" "8")
    action=$(echo "$result" | cut -d'|' -f1)
    reason=$(echo "$result" | cut -d'|' -f4)
    
    [ "$action" = "convert" ]
    [[ "$reason" == *"downmix"* ]]
}

###########################################################
# Tests _get_smart_audio_decision() - AC3 → EAC3
###########################################################

@test "smart decision: AC3 5.1 640k → convert EAC3 384k" {
    AUDIO_CODEC="aac"
    
    local result action codec bitrate
    result=$(_get_smart_audio_decision "/fake.mkv" "ac3" "640" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    bitrate=$(echo "$result" | cut -d'|' -f3)
    
    [ "$action" = "convert" ]
    [ "$codec" = "eac3" ]
    [ "$bitrate" -eq 384 ]
}

###########################################################
# Tests _get_smart_audio_decision() - AAC multichannel
###########################################################

@test "smart decision: AAC 5.1 200k sans --force-audio → copy (anti-upscale)" {
    AUDIO_CODEC="aac"
    FORCE_AUDIO_CODEC=false
    
    local result action reason
    result=$(_get_smart_audio_decision "/fake.mkv" "aac" "200" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    reason=$(echo "$result" | cut -d'|' -f4)
    
    # AAC 200k < seuil anti-upscale 256k → copy
    [ "$action" = "copy" ]
    [[ "$reason" == *"anti_upscale"* ]]
}

@test "smart decision: AAC 5.1 400k avec --force-audio → downscale AAC 320k" {
    AUDIO_CODEC="aac"
    FORCE_AUDIO_CODEC=true
    
    local result action codec bitrate
    result=$(_get_smart_audio_decision "/fake.mkv" "aac" "400" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    bitrate=$(echo "$result" | cut -d'|' -f3)
    
    [ "$action" = "downscale" ]
    [ "$codec" = "aac" ]
    [ "$bitrate" -eq 320 ]
}

###########################################################
# Tests _get_smart_audio_decision() - Opus multichannel
###########################################################

@test "smart decision: Opus 5.1 cible avec -a opus → Opus 224k" {
    AUDIO_CODEC="opus"
    
    local result action codec bitrate
    result=$(_get_smart_audio_decision "/fake.mkv" "ac3" "640" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    bitrate=$(echo "$result" | cut -d'|' -f3)
    
    [ "$action" = "convert" ]
    [ "$codec" = "opus" ]
    [ "$bitrate" -eq 224 ]
}

@test "smart decision: Opus 5.1 existant 200k → copy" {
    AUDIO_CODEC="opus"
    
    local result action
    result=$(_get_smart_audio_decision "/fake.mkv" "opus" "200" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    
    [ "$action" = "copy" ]
}

@test "smart decision: Opus 5.1 existant 300k → downscale 224k" {
    AUDIO_CODEC="opus"
    
    local result action codec bitrate
    result=$(_get_smart_audio_decision "/fake.mkv" "opus" "300" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    codec=$(echo "$result" | cut -d'|' -f2)
    bitrate=$(echo "$result" | cut -d'|' -f3)
    
    [ "$action" = "downscale" ]
    [ "$codec" = "opus" ]
    [ "$bitrate" -eq 224 ]
}

###########################################################
# Tests anti-upscale seuil 256k
###########################################################

@test "smart decision: source multichannel 200k → copy (anti-upscale < 256k)" {
    AUDIO_CODEC="aac"
    
    local result action reason
    result=$(_get_smart_audio_decision "/fake.mkv" "mp3" "200" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    reason=$(echo "$result" | cut -d'|' -f4)
    
    # MP3 200k < 256k seuil anti-upscale → copy
    [ "$action" = "copy" ]
    [[ "$reason" == *"anti_upscale"* ]]
}

@test "smart decision: source multichannel 300k → convert (> 256k seuil)" {
    AUDIO_CODEC="aac"
    
    local result action
    result=$(_get_smart_audio_decision "/fake.mkv" "mp3" "300" "6")
    action=$(echo "$result" | cut -d'|' -f1)
    
    # MP3 300k > 256k seuil → convert vers EAC3
    [ "$action" = "convert" ]
}
