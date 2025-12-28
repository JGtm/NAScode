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
        source "$LIB_DIR/config.sh"
        source "$LIB_DIR/utils.sh"
        source "$LIB_DIR/audio_params.sh"
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

@test "anti-upscaling: même codec → pas de conversion (stub)" {
    # Stub ffprobe pour simuler audio AAC à 256kbps
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
    
    # Règle 1: Même codec → should_convert=0
    [ "$should_convert" -eq 0 ]
}

@test "anti-upscaling: bitrate source inconnu → pas de conversion (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 sans bitrate détectable
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
    
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Règle 2: Bitrate inconnu → should_convert=0 (sécurité)
    [ "$should_convert" -eq 0 ]
}

@test "anti-upscaling: bitrate source ≤ cible → pas de conversion (stub)" {
    # Stub ffprobe pour simuler audio AC3 à 128kbps (< cible AAC 160k)
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
    
    AUDIO_CODEC="aac"  # Cible AAC 160k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert source_bitrate
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    source_bitrate=$(echo "$result" | cut -d'|' -f2)
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Règle 3: 128k ≤ 160k → should_convert=0 (anti-upscaling)
    [ "$source_bitrate" -eq 128 ]
    [ "$should_convert" -eq 0 ]
}

@test "anti-upscaling: bitrate source dans la marge 10% → pas de conversion (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 à 170kbps
    # Cible AAC 160k, seuil = 160 * 1.1 = 176k
    # 170k < 176k donc pas de conversion
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
    
    AUDIO_CODEC="aac"  # Cible AAC 160k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Règle 4: 170k < 176k (seuil 10%) → should_convert=0
    [ "$should_convert" -eq 0 ]
}

@test "anti-upscaling: bitrate source > seuil 10% → conversion (stub)" {
    # Stub ffprobe pour simuler audio E-AC3 à 180kbps
    # Cible AAC 160k, seuil = 160 * 1.1 = 176k
    # 180k > 176k donc conversion
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=180000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    PATH="$stub_dir:$PATH"
    
    AUDIO_CODEC="aac"  # Cible AAC 160k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert source_bitrate
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    source_bitrate=$(echo "$result" | cut -d'|' -f2)
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # Règle 4: 180k > 176k (seuil 10%) → should_convert=1
    [ "$source_bitrate" -eq 180 ]
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

@test "anti-upscaling: conversion vers AC3 refusée si pas de gain (stub)" {
    # Stub ffprobe pour simuler audio AAC à 256kbps
    # Cible AC3 384k, seuil = 384 * 1.1 = 422.4k
    # 256k < 384k donc pas de conversion (on perdrait de la qualité)
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
    
    AUDIO_CODEC="ac3"  # Cible AC3 384k
    AUDIO_BITRATE_KBPS=0
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    # 256k < 384k → should_convert=0 (anti-upscaling)
    [ "$should_convert" -eq 0 ]
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
