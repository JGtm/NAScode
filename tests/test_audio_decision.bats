#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/audio_decision.sh
# Tests de la logique de décision audio "Smart Codec"
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules_fast
    source "$LIB_DIR/audio_decision.sh"
    
    # Valeurs par défaut pour les tests
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    AUDIO_TRANSLATE_EQUIV_QUALITY=false
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _normalize_audio_codec()
###########################################################

@test "_normalize_audio_codec: opus reste opus" {
    local result
    result=$(_normalize_audio_codec "opus")
    [ "$result" = "opus" ]
}

@test "_normalize_audio_codec: libopus devient opus" {
    local result
    result=$(_normalize_audio_codec "libopus")
    [ "$result" = "opus" ]
}

@test "_normalize_audio_codec: aac_latm devient aac" {
    local result
    result=$(_normalize_audio_codec "aac_latm")
    [ "$result" = "aac" ]
}

@test "_normalize_audio_codec: ec-3 devient eac3" {
    local result
    result=$(_normalize_audio_codec "ec-3")
    [ "$result" = "eac3" ]
}

@test "_normalize_audio_codec: gère les majuscules" {
    local result
    result=$(_normalize_audio_codec "AAC")
    [ "$result" = "aac" ]
}

@test "_normalize_audio_codec: chaîne vide retourne vide" {
    local result
    result=$(_normalize_audio_codec "")
    [ -z "$result" ]
}

###########################################################
# Tests de get_audio_codec_rank()
###########################################################

@test "get_audio_codec_rank: opus a le rang le plus élevé (efficace)" {
    local rank
    rank=$(get_audio_codec_rank "opus")
    [ "$rank" -eq 5 ]
}

@test "get_audio_codec_rank: aac est efficace (rang 4)" {
    local rank
    rank=$(get_audio_codec_rank "aac")
    [ "$rank" -eq 4 ]
}

@test "get_audio_codec_rank: ac3 est inefficace (rang 1)" {
    local rank
    rank=$(get_audio_codec_rank "ac3")
    [ "$rank" -eq 1 ]
}

@test "get_audio_codec_rank: flac est lossless (rang 10+)" {
    local rank
    rank=$(get_audio_codec_rank "flac")
    [ "$rank" -ge 10 ]
}

@test "get_audio_codec_rank: truehd est premium (rang 11)" {
    local rank
    rank=$(get_audio_codec_rank "truehd")
    [ "$rank" -eq 11 ]
}

@test "get_audio_codec_rank: codec inconnu a rang 0" {
    local rank
    rank=$(get_audio_codec_rank "unknown_codec")
    [ "$rank" -eq 0 ]
}

###########################################################
# Tests de is_audio_codec_efficient()
###########################################################

@test "is_audio_codec_efficient: opus est efficace" {
    is_audio_codec_efficient "opus"
}

@test "is_audio_codec_efficient: aac est efficace" {
    is_audio_codec_efficient "aac"
}

@test "is_audio_codec_efficient: vorbis est efficace (rang 3)" {
    is_audio_codec_efficient "vorbis"
}

@test "is_audio_codec_efficient: ac3 n'est PAS efficace" {
    ! is_audio_codec_efficient "ac3"
}

@test "is_audio_codec_efficient: eac3 n'est PAS efficace" {
    ! is_audio_codec_efficient "eac3"
}

@test "is_audio_codec_efficient: mp3 n'est PAS efficace" {
    ! is_audio_codec_efficient "mp3"
}

###########################################################
# Tests de is_audio_codec_lossless()
###########################################################

@test "is_audio_codec_lossless: flac est lossless" {
    is_audio_codec_lossless "flac"
}

@test "is_audio_codec_lossless: truehd est lossless" {
    is_audio_codec_lossless "truehd"
}

@test "is_audio_codec_lossless: dts-hd est lossless" {
    is_audio_codec_lossless "dts-hd"
}

@test "is_audio_codec_lossless: aac n'est PAS lossless" {
    ! is_audio_codec_lossless "aac"
}

@test "is_audio_codec_lossless: opus n'est PAS lossless" {
    ! is_audio_codec_lossless "opus"
}

###########################################################
# Tests de is_audio_codec_premium_passthrough()
###########################################################

@test "is_audio_codec_premium_passthrough: flac est premium" {
    is_audio_codec_premium_passthrough "flac"
}

@test "is_audio_codec_premium_passthrough: truehd est premium" {
    is_audio_codec_premium_passthrough "truehd"
}

@test "is_audio_codec_premium_passthrough: dts est premium" {
    is_audio_codec_premium_passthrough "dts"
}

@test "is_audio_codec_premium_passthrough: aac n'est PAS premium" {
    ! is_audio_codec_premium_passthrough "aac"
}

###########################################################
# Tests de is_audio_codec_better_or_equal()
###########################################################

@test "is_audio_codec_better_or_equal: opus >= aac" {
    is_audio_codec_better_or_equal "opus" "aac"
}

@test "is_audio_codec_better_or_equal: aac >= ac3" {
    is_audio_codec_better_or_equal "aac" "ac3"
}

@test "is_audio_codec_better_or_equal: opus >= opus (égal)" {
    is_audio_codec_better_or_equal "opus" "opus"
}

@test "is_audio_codec_better_or_equal: ac3 < aac (false)" {
    ! is_audio_codec_better_or_equal "ac3" "aac"
}

###########################################################
# Tests de get_audio_codec_target_bitrate()
###########################################################

@test "get_audio_codec_target_bitrate: opus cible 128k" {
    local bitrate
    bitrate=$(get_audio_codec_target_bitrate "opus")
    [ "$bitrate" -eq 128 ]
}

@test "get_audio_codec_target_bitrate: aac cible 160k" {
    local bitrate
    bitrate=$(get_audio_codec_target_bitrate "aac")
    [ "$bitrate" -eq 160 ]
}

@test "get_audio_codec_target_bitrate: ac3 cible 640k" {
    local bitrate
    bitrate=$(get_audio_codec_target_bitrate "ac3")
    [ "$bitrate" -eq 640 ]
}

@test "get_audio_codec_target_bitrate: flac retourne 0 (lossless)" {
    local bitrate
    bitrate=$(get_audio_codec_target_bitrate "flac")
    [ "$bitrate" -eq 0 ]
}

###########################################################
# Tests de get_audio_ffmpeg_encoder()
###########################################################

@test "get_audio_ffmpeg_encoder: opus utilise libopus" {
    local encoder
    encoder=$(get_audio_ffmpeg_encoder "opus")
    [ "$encoder" = "libopus" ]
}

@test "get_audio_ffmpeg_encoder: aac utilise aac" {
    local encoder
    encoder=$(get_audio_ffmpeg_encoder "aac")
    [ "$encoder" = "aac" ]
}

###########################################################
# Tests de get_audio_codec_efficiency()
###########################################################

@test "get_audio_codec_efficiency: opus est le plus efficace (50)" {
    local eff
    eff=$(get_audio_codec_efficiency "opus")
    [ "$eff" -eq 50 ]
}

@test "get_audio_codec_efficiency: aac est efficace (65)" {
    local eff
    eff=$(get_audio_codec_efficiency "aac")
    [ "$eff" -eq 65 ]
}

@test "get_audio_codec_efficiency: ac3 est inefficace (120)" {
    local eff
    eff=$(get_audio_codec_efficiency "ac3")
    [ "$eff" -eq 120 ]
}

@test "get_audio_codec_efficiency: flac retourne 0 (lossless, pas de traduction)" {
    local eff
    eff=$(get_audio_codec_efficiency "flac")
    [ "$eff" -eq 0 ]
}

###########################################################
# Tests de translate_audio_bitrate_kbps_between_codecs()
###########################################################

@test "translate_audio_bitrate: ac3 640k → aac ~350k" {
    local result
    result=$(translate_audio_bitrate_kbps_between_codecs "ac3" "aac" "640")
    
    # AC3 (eff 120) → AAC (eff 65) : 640 * 65/120 ≈ 347
    [ -n "$result" ]
    [[ "$result" =~ ^[0-9]+$ ]]
    [ "$result" -ge 300 ] && [ "$result" -le 400 ]
}

@test "translate_audio_bitrate: aac 160k → opus ~123k" {
    local result
    result=$(translate_audio_bitrate_kbps_between_codecs "aac" "opus" "160")
    
    # AAC (eff 65) → Opus (eff 50) : 160 * 50/65 ≈ 123
    [ -n "$result" ]
    [[ "$result" =~ ^[0-9]+$ ]]
    [ "$result" -ge 100 ] && [ "$result" -le 150 ]
}

@test "translate_audio_bitrate: même codec retourne vide" {
    local result
    result=$(translate_audio_bitrate_kbps_between_codecs "aac" "aac" "160")
    
    [ -z "$result" ]
}

@test "translate_audio_bitrate: bitrate invalide retourne vide" {
    local result
    result=$(translate_audio_bitrate_kbps_between_codecs "ac3" "aac" "")
    [ -z "$result" ]
    
    result=$(translate_audio_bitrate_kbps_between_codecs "ac3" "aac" "abc")
    [ -z "$result" ]
}

###########################################################
# Tests de _is_audio_multichannel()
###########################################################

@test "_is_audio_multichannel: 6 canaux = multicanal (5.1)" {
    _is_audio_multichannel 6
}

@test "_is_audio_multichannel: 8 canaux = multicanal (7.1)" {
    _is_audio_multichannel 8
}

@test "_is_audio_multichannel: 2 canaux = stéréo (pas multicanal)" {
    ! _is_audio_multichannel 2
}

@test "_is_audio_multichannel: 1 canal = mono (pas multicanal)" {
    ! _is_audio_multichannel 1
}

###########################################################
# Tests de _compute_eac3_target_bitrate_kbps()
###########################################################

@test "_compute_eac3_target_bitrate_kbps: cap à 384k par défaut" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 500)
    [ "$result" -eq 384 ]
}

@test "_compute_eac3_target_bitrate_kbps: garde source si < cap" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 256)
    [ "$result" -eq 256 ]
}

@test "_compute_eac3_target_bitrate_kbps: utilise cap si source=0" {
    local result
    result=$(_compute_eac3_target_bitrate_kbps 0)
    [ "$result" -eq 384 ]
}

###########################################################
# Tests de _get_multichannel_target_bitrate()
###########################################################

@test "_get_multichannel_target_bitrate: opus 5.1 → 224k" {
    local result
    result=$(_get_multichannel_target_bitrate "opus")
    [ "$result" -eq 224 ]
}

@test "_get_multichannel_target_bitrate: aac 5.1 → 320k" {
    local result
    result=$(_get_multichannel_target_bitrate "aac")
    [ "$result" -eq 320 ]
}

@test "_get_multichannel_target_bitrate: eac3 5.1 → 384k" {
    local result
    result=$(_get_multichannel_target_bitrate "eac3")
    [ "$result" -eq 384 ]
}
