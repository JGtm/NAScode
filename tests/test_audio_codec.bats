#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Codec audio (-a/--audio)
# Tests des fonctions de conversion audio (AAC, AC3, Opus)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    # Charger les modules une seule fois
    if [[ -z "${_AUDIO_TEST_LOADED:-}" ]]; then
        export SCRIPT_DIR="$PROJECT_ROOT"
        source "$LIB_DIR/ui.sh"
        source "$LIB_DIR/detect.sh"
        source "$LIB_DIR/config.sh"
        source "$LIB_DIR/codec_profiles.sh"
        source "$LIB_DIR/utils.sh"
        source "$LIB_DIR/audio_params.sh"
        source "$LIB_DIR/video_params.sh"
        source "$LIB_DIR/stream_mapping.sh"
        source "$LIB_DIR/transcode_video.sh"
        # Initialiser le mode conversion (définit TARGET_BITRATE_KBPS, etc.)
        set_conversion_mode_parameters "series"
        _AUDIO_TEST_LOADED=1
    fi
    
    # Variables modifiables uniquement
    AUDIO_CODEC="copy"
    AUDIO_BITRATE_KBPS=0
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _get_audio_conversion_info()
###########################################################

@test "_get_audio_conversion_info: retourne copy si AUDIO_CODEC=copy" {
    AUDIO_CODEC="copy"
    
    local result
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    
    [[ "$result" == "copy|0|0" ]]
}

@test "_get_audio_conversion_info: should_convert=0 quand AUDIO_CODEC=copy" {
    AUDIO_CODEC="copy"
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    [ "$should_convert" -eq 0 ]
}

###########################################################
# Tests de la logique anti-upscaling
###########################################################

@test "anti-upscaling: même codec mais bitrate élevé → downscale (stub)" {
    # Stub ffprobe pour simuler audio AAC à 256kbps
    # Même codec (AAC) mais bitrate source > cible * 1.1 (176k)
    # Nouvelle logique smart : downscale pour réduire le bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=aac"
echo "bit_rate=256000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="aac"  # Cible = même codec
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Règle smart codec: Même codec mais 256k > 176k → downscale (should_convert=1)
    [ "$should_convert" -eq 1 ]
}

@test "codec inefficace: E-AC3 toujours converti même sans bitrate détectable (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 sans bitrate détectable
    # E-AC3 est un codec INEFFICACE (rang 2) → toujours convertir vers codec efficace
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=N/A"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="opus"  # Cible Opus (efficace)
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # E-AC3 est inefficace → TOUJOURS convertir vers Opus
    [ "$should_convert" -eq 1 ]
}

@test "codec inefficace: AC3 toujours converti même à bas bitrate (stub)" {
    # Stub ffprobe pour simuler audio AC3 à 128kbps (< cible Opus 128k)
    # AC3 est un codec INEFFICACE (rang 1) → toujours convertir, pas d'anti-upscaling
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=ac3"
echo "bit_rate=128000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="opus"  # Cible Opus 128k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert source_codec source_bitrate
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    source_codec=$(echo "$result" | cut -d'|' -f1)
    source_bitrate=$(echo "$result" | cut -d'|' -f2)
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Vérifier que le format de retour est correct
    [ "$source_codec" = "ac3" ]
    [ "$source_bitrate" -eq 128 ]
    # AC3 est inefficace → TOUJOURS convertir vers Opus
    [ "$should_convert" -eq 1 ]
}

@test "codec inefficace: E-AC3 toujours converti même à bitrate modéré (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 à 170kbps
    # E-AC3 est un codec INEFFICACE → toujours convertir vers Opus
    # Pas de marge de tolérance pour les codecs inefficaces
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=170000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="opus"  # Cible Opus 128k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # E-AC3 est inefficace → TOUJOURS convertir vers Opus
    [ "$should_convert" -eq 1 ]
}

@test "codec inefficace: E-AC3 à haut bitrate converti (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 à 384kbps
    # E-AC3 est un codec INEFFICACE → toujours convertir vers Opus
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=384000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="opus"  # Cible Opus 128k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert source_codec source_bitrate
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    source_codec=$(echo "$result" | cut -d'|' -f1)
    source_bitrate=$(echo "$result" | cut -d'|' -f2)
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Vérifier le format de retour
    [ "$source_codec" = "eac3" ]
    [ "$source_bitrate" -eq 384 ]
    # E-AC3 est inefficace → TOUJOURS convertir vers Opus
    [ "$should_convert" -eq 1 ]
}

@test "anti-upscaling: conversion vers Opus avec gain suffisant (stub)" {
    # Stub ffprobe pour simuler audio AAC à 256kbps
    # Cible Opus 128k, seuil = 128 * 1.1 = 140.8k
    # 256k > 140.8k donc conversion
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=aac"
echo "bit_rate=256000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="opus"  # Cible Opus 128k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # 256k > 140.8k → should_convert=1
    [ "$should_convert" -eq 1 ]
}

@test "smart-codec: source efficace conservée même si cible différente (stub)" {
    # Stub ffprobe pour simuler audio AAC à 256kbps
    # AAC (rang 4) est EFFICACE (seuil = 3)
    # Smart codec: on garde le codec source (AAC) au lieu de downgrader vers AC3 (inefficace)
    # Mais on vérifie si le bitrate source dépasse la limite AAC (160k)
    # 256k > 160k * 1.1 = 176k donc downscale dans le même codec (AAC)
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=aac"
echo "bit_rate=256000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="ac3"  # Cible AC3 (inefficace)
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Smart codec: AAC efficace, 256k > 176k (limite AAC) → downscale
    [ "$should_convert" -eq 1 ]
}

###########################################################
# Tests de _should_convert_audio()
###########################################################

@test "_should_convert_audio: retourne 1 (false) si AUDIO_CODEC=copy" {
    AUDIO_CODEC="copy"
    
    run _should_convert_audio "/fake/file.mkv"
    [ "$status" -eq 1 ]
}

@test "_should_convert_audio: retourne 0 (true) si conversion avantageuse (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 à 640kbps
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=640000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="aac"  # Cible AAC 160k
    AUDIO_BITRATE_KBPS=0
    
    run _should_convert_audio "/fake/file.mkv"
    # 640k >> 160k * 1.1 → conversion avantageuse → retourne 0 (true)
    [ "$status" -eq 0 ]
}

@test "_should_convert_audio: retourne 1 (false) si même codec (stub)" {
    # Stub ffprobe pour simuler audio AAC à 160kbps
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=aac"
echo "bit_rate=160000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    
    run _should_convert_audio "/fake/file.mkv"
    # Même codec → pas de conversion → retourne 1 (false)
    [ "$status" -eq 1 ]
}

###########################################################
# Tests de _get_audio_target_bitrate()
###########################################################

@test "_get_audio_target_bitrate: retourne bitrate custom si défini" {
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=320
    
    local result
    result=$(_get_audio_target_bitrate)
    
    [ "$result" -eq 320 ]
}

@test "_get_audio_target_bitrate: retourne défaut AAC si pas de custom" {
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    
    local result
    result=$(_get_audio_target_bitrate)
    
    [ "$result" -eq "${AUDIO_BITRATE_AAC_DEFAULT:-160}" ]
}

@test "_get_audio_target_bitrate: retourne défaut AC3 si pas de custom" {
    AUDIO_CODEC="ac3"
    AUDIO_BITRATE_KBPS=0
    
    local result
    result=$(_get_audio_target_bitrate)
    
    [ "$result" -eq "${AUDIO_BITRATE_AC3_DEFAULT:-384}" ]
}

@test "_get_audio_target_bitrate: retourne défaut Opus si pas de custom" {
    AUDIO_CODEC="opus"
    AUDIO_BITRATE_KBPS=0
    
    local result
    result=$(_get_audio_target_bitrate)
    
    [ "$result" -eq "${AUDIO_BITRATE_OPUS_DEFAULT:-128}" ]
}

@test "_get_audio_target_bitrate: retourne 0 pour copy" {
    AUDIO_CODEC="copy"
    
    local result
    result=$(_get_audio_target_bitrate)
    
    [ "$result" -eq 0 ]
}

###########################################################
# Tests de _build_audio_params()
###########################################################

@test "_build_audio_params: retourne '-c:a copy' si AUDIO_CODEC=copy" {
    AUDIO_CODEC="copy"
    
    local result
    result=$(_build_audio_params "/fake/file.mkv")
    
    [[ "$result" == "-c:a copy" ]]
}

@test "_build_audio_params: ne plante pas avec aac" {
    AUDIO_CODEC="aac"
    
    run _build_audio_params "/fake/file.mkv"
    [ "$status" -eq 0 ]
}

@test "_build_audio_params: ne plante pas avec ac3" {
    AUDIO_CODEC="ac3"
    
    run _build_audio_params "/fake/file.mkv"
    [ "$status" -eq 0 ]
}

@test "_build_audio_params: ne plante pas avec opus" {
    AUDIO_CODEC="opus"
    
    run _build_audio_params "/fake/file.mkv"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests d'intégration avec args.sh
###########################################################

@test "args: -a aac définit AUDIO_CODEC" {
    source "$LIB_DIR/args.sh"
    
    AUDIO_CODEC="copy"
    parse_arguments -a aac
    
    [ "$AUDIO_CODEC" = "aac" ]
}

@test "args: --audio ac3 définit AUDIO_CODEC" {
    source "$LIB_DIR/args.sh"
    
    AUDIO_CODEC="copy"
    parse_arguments --audio ac3
    
    [ "$AUDIO_CODEC" = "ac3" ]
}

@test "args: -a opus définit AUDIO_CODEC" {
    source "$LIB_DIR/args.sh"
    
    AUDIO_CODEC="copy"
    parse_arguments -a opus
    
    [ "$AUDIO_CODEC" = "opus" ]
}

@test "args: -a invalide échoue" {
    source "$LIB_DIR/args.sh"
    
    run parse_arguments --audio mp3
    [ "$status" -ne 0 ]
}

@test "args: -a/--audio apparaît dans l'aide" {
    source "$LIB_DIR/args.sh"
    
    run show_help
    [[ "$output" =~ "-a" ]] || [[ "$output" =~ "--audio" ]]
    [[ "$output" =~ "aac" ]] || [[ "$output" =~ "audio" ]]
}

###########################################################
# Tests du suffixe avec codec audio
###########################################################

@test "_build_effective_suffix_for_dims: inclut _aac si AUDIO_CODEC=aac" {
    AUDIO_CODEC="aac"
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result" =~ "_aac" ]]
}

@test "_build_effective_suffix_for_dims: inclut _ac3 si AUDIO_CODEC=ac3" {
    AUDIO_CODEC="ac3"
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result" =~ "_ac3" ]]
}

@test "_build_effective_suffix_for_dims: inclut _opus si AUDIO_CODEC=opus" {
    AUDIO_CODEC="opus"
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result" =~ "_opus" ]]
}

@test "_build_effective_suffix_for_dims: n'inclut pas _aac/_ac3/_opus si copy" {
    AUDIO_CODEC="copy"
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ ! "$result" =~ "_aac" ]]
    [[ ! "$result" =~ "_ac3" ]]
    [[ ! "$result" =~ "_opus" ]]
}

###########################################################
# Tests de config.sh avec codec audio
###########################################################

@test "config: build_dynamic_suffix inclut _aac si AUDIO_CODEC=aac" {
    AUDIO_CODEC="aac"
    FORCE_NO_SUFFIX=false
    SAMPLE_MODE=false
    
    build_dynamic_suffix
    
    [[ "$SUFFIX_STRING" =~ "_aac" ]]
}

@test "config: AUDIO_BITRATE_AAC_DEFAULT est défini et valide" {
    [ -n "$AUDIO_BITRATE_AAC_DEFAULT" ]
    [ "$AUDIO_BITRATE_AAC_DEFAULT" -gt 0 ]
    [ "$AUDIO_BITRATE_AAC_DEFAULT" -le 512 ]
}

@test "config: AUDIO_BITRATE_AC3_DEFAULT est défini et valide" {
    [ -n "$AUDIO_BITRATE_AC3_DEFAULT" ]
    [ "$AUDIO_BITRATE_AC3_DEFAULT" -gt 0 ]
    [ "$AUDIO_BITRATE_AC3_DEFAULT" -le 640 ]
}

@test "config: AUDIO_BITRATE_OPUS_DEFAULT est défini et valide" {
    [ -n "$AUDIO_BITRATE_OPUS_DEFAULT" ]
    [ "$AUDIO_BITRATE_OPUS_DEFAULT" -gt 0 ]
    [ "$AUDIO_BITRATE_OPUS_DEFAULT" -le 512 ]
}

@test "config: AUDIO_CONVERSION_THRESHOLD_KBPS est défini" {
    [ -n "$AUDIO_CONVERSION_THRESHOLD_KBPS" ]
    [ "$AUDIO_CONVERSION_THRESHOLD_KBPS" -gt 0 ]
}

###########################################################
# Tests de format_option_audio()
###########################################################

@test "format_option_audio: affiche AAC avec bitrate" {
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    
    run format_option_audio
    [ "$status" -eq 0 ]
    [[ "$output" =~ "AAC" ]]
    [[ "$output" =~ "160k" ]] || [[ "$output" =~ "k" ]]
}

@test "format_option_audio: affiche AC3 avec Dolby Digital" {
    AUDIO_CODEC="ac3"
    AUDIO_BITRATE_KBPS=0
    
    run format_option_audio
    [ "$status" -eq 0 ]
    [[ "$output" =~ "AC3" ]]
    [[ "$output" =~ "Dolby" ]] || [[ "$output" =~ "384k" ]]
}

@test "format_option_audio: affiche Opus avec bitrate" {
    AUDIO_CODEC="opus"
    AUDIO_BITRATE_KBPS=0
    
    run format_option_audio
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Opus" ]]
}

@test "format_option_audio: retourne erreur pour copy" {
    AUDIO_CODEC="copy"
    
    run format_option_audio
    [ "$status" -ne 0 ]
}

###########################################################
# Tests de la hiérarchie des codecs audio (smart codec)
###########################################################

@test "get_audio_codec_rank: opus est le meilleur (rang 5)" {
    local rank
    rank=$(get_audio_codec_rank "opus")
    [ "$rank" -eq 5 ]
}

@test "get_audio_codec_rank: aac est rang 4" {
    local rank
    rank=$(get_audio_codec_rank "aac")
    [ "$rank" -eq 4 ]
}

@test "get_audio_codec_rank: eac3 est rang 2 (inefficace)" {
    local rank
    rank=$(get_audio_codec_rank "eac3")
    [ "$rank" -eq 2 ]
}

@test "get_audio_codec_rank: ac3 est rang 1 (inefficace)" {
    local rank
    rank=$(get_audio_codec_rank "ac3")
    [ "$rank" -eq 1 ]
}

@test "get_audio_codec_rank: flac est lossless (rang 10)" {
    local rank
    rank=$(get_audio_codec_rank "flac")
    [ "$rank" -eq 10 ]
}

@test "is_audio_codec_better_or_equal: opus >= aac" {
    is_audio_codec_better_or_equal "opus" "aac"
}

@test "is_audio_codec_better_or_equal: aac >= eac3 (aac efficace, eac3 inefficace)" {
    is_audio_codec_better_or_equal "aac" "eac3"
}

@test "is_audio_codec_better_or_equal: aac < opus (retourne false)" {
    ! is_audio_codec_better_or_equal "aac" "opus"
}

@test "get_audio_codec_target_bitrate: opus retourne 128" {
    local bitrate
    bitrate=$(get_audio_codec_target_bitrate "opus")
    [ "$bitrate" -eq 128 ]
}

@test "get_audio_codec_target_bitrate: aac retourne 160" {
    local bitrate
    bitrate=$(get_audio_codec_target_bitrate "aac")
    [ "$bitrate" -eq 160 ]
}

###########################################################
# Tests des fonctions is_audio_codec_efficient et is_audio_codec_lossless
###########################################################

@test "is_audio_codec_efficient: opus est efficace" {
    is_audio_codec_efficient "opus"
}

@test "is_audio_codec_efficient: aac est efficace" {
    is_audio_codec_efficient "aac"
}

@test "is_audio_codec_efficient: vorbis est efficace" {
    is_audio_codec_efficient "vorbis"
}

@test "is_audio_codec_efficient: eac3 n'est PAS efficace" {
    ! is_audio_codec_efficient "eac3"
}

@test "is_audio_codec_efficient: ac3 n'est PAS efficace" {
    ! is_audio_codec_efficient "ac3"
}

@test "is_audio_codec_efficient: mp3 n'est PAS efficace" {
    ! is_audio_codec_efficient "mp3"
}

@test "is_audio_codec_lossless: flac est lossless" {
    is_audio_codec_lossless "flac"
}

@test "is_audio_codec_lossless: truehd est lossless" {
    is_audio_codec_lossless "truehd"
}

@test "is_audio_codec_lossless: opus n'est PAS lossless" {
    ! is_audio_codec_lossless "opus"
}

@test "is_audio_codec_lossless: aac n'est PAS lossless" {
    ! is_audio_codec_lossless "aac"
}

###########################################################
# Tests des options --force-audio et --force-video
###########################################################

@test "args: --force-audio définit FORCE_AUDIO_CODEC=true" {
    source "$LIB_DIR/args.sh"
    
    FORCE_AUDIO_CODEC=false
    parse_arguments --force-audio
    
    [ "$FORCE_AUDIO_CODEC" = "true" ]
}

@test "args: --force-video définit FORCE_VIDEO_CODEC=true" {
    source "$LIB_DIR/args.sh"
    
    FORCE_VIDEO_CODEC=false
    parse_arguments --force-video
    
    [ "$FORCE_VIDEO_CODEC" = "true" ]
}

@test "args: --force définit les deux flags" {
    source "$LIB_DIR/args.sh"
    
    FORCE_AUDIO_CODEC=false
    FORCE_VIDEO_CODEC=false
    parse_arguments --force
    
    [ "$FORCE_AUDIO_CODEC" = "true" ]
    [ "$FORCE_VIDEO_CODEC" = "true" ]
}

@test "args: -a eac3 est accepté" {
    source "$LIB_DIR/args.sh"
    
    AUDIO_CODEC="copy"
    parse_arguments -a eac3
    
    [ "$AUDIO_CODEC" = "eac3" ]
}

###########################################################
# Tests de la logique smart codec avec FORCE
###########################################################

@test "smart-codec: FORCE_AUDIO_CODEC force la conversion même si même codec (stub)" {
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=aac"
echo "bit_rate=140000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="aac"
    FORCE_AUDIO_CODEC=true
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Sans FORCE: même codec + bitrate OK → copy (should_convert=0)
    # Avec FORCE: même codec mais 140k < 160k → copy (pas besoin de downscale)
    [ "$should_convert" -eq 0 ]
    
    FORCE_AUDIO_CODEC=false  # Reset
}
