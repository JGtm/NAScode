#!/usr/bin/env bats
###########################################################
# TESTS DE NON-RÉGRESSION - Couverture supplémentaire
#
# Ce fichier ajoute des tests pour les cas limites :
# 1. Fallback HWACCEL (GPU absent → software)
# 2. Mapping sous-titres FR/EN avec fallback
# 3. Média corrompu / échec ffmpeg
# 4. Audio Opus copy vs convert (décisionnel)
# 5. Downscale 4K vers 1080p
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/transcode_video.sh"
    source "$LIB_DIR/media_probe.sh"
    
    # Nettoyer le lock global
    rm -f /tmp/conversion_video.lock
}

teardown() {
    rm -f /tmp/conversion_video.lock
    teardown_test_env
}

###########################################################
# SECTION 1: FALLBACK HWACCEL (simulation absence GPU)
###########################################################

@test "HWACCEL: detect_hwaccel définit une valeur par défaut" {
    detect_hwaccel
    
    # HWACCEL doit être défini (videotoolbox sur Mac, cuda sinon)
    [ -n "$HWACCEL" ]
}

@test "HWACCEL: fallback software quand HWACCEL=none" {
    # Forcer mode software
    HWACCEL="none"
    
    # Les fonctions doivent accepter HWACCEL vide ou "none"
    # Test que les paramètres vidéo se construisent sans erreur
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    # Vérifier que le script ne plante pas avec HWACCEL=none
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    [ -n "$result" ]
}

@test "HWACCEL: fallback software quand HWACCEL vide" {
    # Forcer mode software
    HWACCEL=""
    
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    # Vérifier que le script ne plante pas avec HWACCEL vide
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    [ -n "$result" ]
}

###########################################################
# SECTION 2: MAPPING SOUS-TITRES FR/EN AVEC FALLBACK
###########################################################

@test "SUBTITLES: _build_stream_mapping retourne mapping vidéo+audio de base" {
    # Créer un fichier factice (ffprobe échouera mais la fonction doit gérer)
    local fake_file="$TEST_TEMP_DIR/fake.mkv"
    touch "$fake_file"
    
    local result
    result=$(_build_stream_mapping "$fake_file")
    
    # Doit contenir au minimum -map 0:v (fallback) et -map 0:a?
    [[ "$result" =~ "-map 0:v" ]]
    [[ "$result" =~ "-map 0:a" ]]
}

@test "VIDEO: _build_stream_mapping exclut attached_pic (cover art)" {
    # Créer un stub ffprobe qui simule 2 flux vidéo :
    # - v:0 = attached_pic (cover)
    # - v:1 = vidéo principale
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"

    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
if [[ "$*" =~ "-select_streams v" ]]; then
    echo "0,1"
    echo "1,0"
fi
if [[ "$*" =~ "-select_streams s" ]]; then
    echo "2,fre"
fi
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"

    PATH="$stub_dir:$PATH"

    local result
    result=$(_build_stream_mapping "/fake/file.mkv")

    # Expect absolute index 1 (main video)
    [[ "$result" =~ "-map 0:1" ]]
    # Should not contain index 0 (cover art)
    [[ ! "$result" =~ "-map 0:0" ]]
}

@test "SUBTITLES: fichier avec sous-titres FR uniquement conserve FR" {
    # Créer un stub ffprobe qui simule un fichier avec subs FR+EN
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler un fichier avec sous-titres FR (index 2) et EN (index 3)
if [[ "$*" =~ "-select_streams v" ]]; then
    # Vidéo principale uniquement (pas d'attached_pic)
    echo "0,0"
fi
if [[ "$*" =~ "-select_streams s" ]]; then
    echo "2,fre"
    echo "3,eng"
fi
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    # Utiliser le stub
    PATH="$stub_dir:$PATH"
    
    local result
    result=$(_build_stream_mapping "/fake/file.mkv")
    
    # Doit mapper le sous-titre FR (index 2) mais pas EN (index 3)
    [[ "$result" =~ "-map 0:2" ]]
    [[ ! "$result" =~ "-map 0:3" ]]
}

@test "SUBTITLES: fichier sans sous-titres FR garde tous les sous-titres (fallback)" {
    # Créer un stub ffprobe qui simule un fichier avec subs EN+ES uniquement
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler un fichier avec sous-titres EN (index 2) et ES (index 3) - pas de FR
if [[ "$*" =~ "-select_streams v" ]]; then
    # Vidéo principale uniquement (pas d'attached_pic)
    echo "0,0"
fi
if [[ "$*" =~ "-select_streams s" ]]; then
    echo "2,eng"
    echo "3,spa"
fi
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    # Utiliser le stub
    PATH="$stub_dir:$PATH"
    
    local result
    result=$(_build_stream_mapping "/fake/file.mkv")
    
    # Aucun FR trouvé → doit garder tous les sous-titres avec -map 0:s?
    [[ "$result" =~ "-map 0:s?" ]]
}

@test "SUBTITLES: fichier avec plusieurs pistes FR les garde toutes" {
    # Créer un stub ffprobe qui simule un fichier avec 2 pistes FR
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler un fichier avec 2 sous-titres FR (forced + full)
if [[ "$*" =~ "-select_streams s" ]]; then
    echo "2,fre"
    echo "3,eng"
    echo "4,fra"
fi
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    
    local result
    result=$(_build_stream_mapping "/fake/file.mkv")
    
    # Doit mapper les deux pistes FR (index 2 et 4)
    [[ "$result" =~ "-map 0:2" ]]
    [[ "$result" =~ "-map 0:4" ]]
    [[ ! "$result" =~ "-map 0:3" ]]
}

###########################################################
# SECTION 3: AUDIO CODEC COPY VS CONVERT (DÉCISIONNEL)
###########################################################

@test "AUDIO: _get_audio_conversion_info retourne copy si AUDIO_CODEC=copy" {
    AUDIO_CODEC="copy"
    
    local result
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    
    # should_convert (3ème champ) doit être 0
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 0 ]
}

@test "AUDIO: audio AAC haut bitrate déclenche downscale si cible AAC (stub)" {
    # Créer un stub ffprobe qui simule un fichier avec audio AAC haut bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler audio AAC à 256kbps (> cible 160k * 1.1 = 176k)
echo "codec_name=aac"
echo "bit_rate=256000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    AUDIO_CODEC="aac"
    
    local result
    result=$(_get_audio_conversion_info "/fake/aac_audio.mkv")
    
    # Smart codec: même codec AAC mais 256k > 176k → should_convert=1 (downscale)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 1 ]
}

@test "AUDIO: audio E-AC3 déclenche conversion vers codec efficace (stub)" {
    # Créer un stub ffprobe qui simule un fichier avec audio E-AC3
    # E-AC3 est un codec INEFFICACE → toujours convertir vers Opus/AAC
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler audio E-AC3 à 768kbps
echo "codec_name=eac3"
echo "bit_rate=768000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    AUDIO_CODEC="opus"  # Cible Opus (efficace)
    
    local result
    result=$(_get_audio_conversion_info "/fake/eac3_audio.mkv")
    
    # should_convert doit être 1 (E-AC3 est inefficace → toujours convertir)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 1 ]
}

@test "AUDIO: audio AAC bas bitrate est converti vers Opus si cible=opus (stub)" {
    # Créer un stub ffprobe qui simule un fichier avec audio AAC bas bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler audio AAC à 128kbps
echo "codec_name=aac"
echo "bit_rate=128000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    AUDIO_CODEC="opus"
    
    local result
    result=$(_get_audio_conversion_info "/fake/aac_low.mkv")
    
    # should_convert doit être 1 car Opus (rang 5) est plus efficace que AAC (rang 4)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 1 ]
}

@test "AUDIO: audio AAC bas bitrate reste en copy si cible=aac (stub)" {
    # Créer un stub ffprobe qui simule un fichier avec audio AAC bas bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler audio AAC à 128kbps (< seuil 160 par défaut)
echo "codec_name=aac"
echo "bit_rate=128000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    AUDIO_CODEC="aac"  # Cible = même codec que source
    
    local result
    result=$(_get_audio_conversion_info "/fake/aac_low.mkv")
    
    # should_convert doit être 0 (même codec, bitrate OK)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 0 ]
}

@test "AUDIO: _build_audio_params retourne copy si AUDIO_CODEC=copy" {
    AUDIO_CODEC="copy"
    
    local result
    result=$(_build_audio_params "/fake/file.mkv")
    
    [[ "$result" == "-c:a copy" ]]
}

@test "AUDIO: _build_audio_params retourne aac si conversion vers AAC (stub)" {
    # Créer un stub ffprobe qui simule audio E-AC3 haut bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=eac3"
echo "bit_rate=768000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    
    local result
    result=$(_build_audio_params "/fake/high_eac3.mkv")
    
    # Doit contenir aac et le bitrate cible (160k par défaut)
    [[ "$result" =~ "aac" ]]
    [[ "$result" =~ "160k" ]] || [[ "$result" =~ "${AUDIO_BITRATE_AAC_DEFAULT}k" ]]
}

###########################################################
# SECTION 4: DOWNSCALE 4K VERS 1080P
###########################################################

@test "DOWNSCALE: _build_downscale_filter_if_needed génère filtre pour 4K" {
    local result
    result=$(_build_downscale_filter_if_needed 3840 2160)
    
    # Doit contenir un filtre scale
    [[ "$result" =~ "scale=" ]]
    [[ "$result" =~ "lanczos" ]]
}

@test "DOWNSCALE: _build_downscale_filter_if_needed vide pour 1080p" {
    local result
    result=$(_build_downscale_filter_if_needed 1920 1080)
    
    # Pas de filtre nécessaire
    [ -z "$result" ]
}

@test "DOWNSCALE: _compute_output_height_for_bitrate calcule 1080 pour 4K" {
    local result
    result=$(_compute_output_height_for_bitrate 3840 2160)
    
    # 4K downscalé vers 1080p
    [ "$result" -eq 1080 ]
}

@test "DOWNSCALE: suffixe inclut résolution de sortie correcte (4K→1080p)" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    set_conversion_mode_parameters
    
    local result
    result=$(_build_effective_suffix_for_dims 3840 2160)
    
    # Doit inclure 1080p (pas 2160p)
    [[ "$result" =~ "_1080p_" ]]
    [[ ! "$result" =~ "_2160p_" ]]
}

@test "DOWNSCALE: suffixe inclut bitrate adapté pour 720p" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    set_conversion_mode_parameters
    
    local result
    result=$(_build_effective_suffix_for_dims 1280 720)
    
    # Bitrate série 720p = 2070 * 70% = 1449k
    [[ "$result" =~ "_1449k_" ]]
    [[ "$result" =~ "_720p_" ]]
}
