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
    
    # Doit contenir au minimum -map 0:v et -map 0:a?
    [[ "$result" =~ "-map 0:v" ]]
    [[ "$result" =~ "-map 0:a" ]]
}

@test "SUBTITLES: fichier avec sous-titres FR uniquement conserve FR" {
    # Créer un stub ffprobe qui simule un fichier avec subs FR+EN
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler un fichier avec sous-titres FR (index 2) et EN (index 3)
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
# SECTION 3: AUDIO OPUS COPY VS CONVERT (DÉCISIONNEL)
###########################################################

@test "OPUS: _get_audio_conversion_info retourne copy si Opus désactivé" {
    OPUS_ENABLED=false
    
    local result
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    
    # should_convert (3ème champ) doit être 0
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 0 ]
}

@test "OPUS: audio déjà en Opus n'est pas reconverti (stub)" {
    # Créer un stub ffprobe qui simule un fichier avec audio Opus
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler audio Opus à 128kbps
echo "codec_name=opus"
echo "bit_rate=128000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    OPUS_ENABLED=true
    
    local result
    result=$(_get_audio_conversion_info "/fake/opus_audio.mkv")
    
    # should_convert doit être 0 (déjà Opus)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 0 ]
}

@test "OPUS: audio AAC haut bitrate déclenche conversion (stub)" {
    # Créer un stub ffprobe qui simule un fichier avec audio AAC haut bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
# Simuler audio AAC à 256kbps (> seuil 160 par défaut)
echo "codec_name=aac"
echo "bit_rate=256000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    OPUS_ENABLED=true
    # OPUS_CONVERSION_THRESHOLD_KBPS est readonly à 160, on utilise la valeur par défaut
    
    local result
    result=$(_get_audio_conversion_info "/fake/aac_audio.mkv")
    
    # should_convert doit être 1 (AAC 256k > seuil 160k)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 1 ]
}

@test "OPUS: audio AAC bas bitrate ne déclenche pas conversion (stub)" {
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
    OPUS_ENABLED=true
    # OPUS_CONVERSION_THRESHOLD_KBPS est readonly à 160, on utilise la valeur par défaut
    
    local result
    result=$(_get_audio_conversion_info "/fake/aac_low.mkv")
    
    # should_convert doit être 0 (bitrate 128k < seuil 160k)
    local should_convert
    should_convert=$(echo "$result" | cut -d'|' -f3)
    [ "$should_convert" -eq 0 ]
}

@test "OPUS: _build_audio_params retourne copy si conversion non nécessaire" {
    OPUS_ENABLED=false
    
    local result
    result=$(_build_audio_params "/fake/file.mkv")
    
    [[ "$result" == "-c:a copy" ]]
}

@test "OPUS: _build_audio_params retourne libopus si conversion nécessaire (stub)" {
    # Créer un stub ffprobe qui simule audio AAC haut bitrate
    local stub_dir="$TEST_TEMP_DIR/stub"
    mkdir -p "$stub_dir"
    
    cat > "$stub_dir/ffprobe" << 'STUB'
#!/bin/bash
echo "codec_name=aac"
echo "bit_rate=320000"
exit 0
STUB
    chmod +x "$stub_dir/ffprobe"
    
    PATH="$stub_dir:$PATH"
    OPUS_ENABLED=true
    # OPUS_TARGET_BITRATE_KBPS est readonly à 128, on utilise la valeur par défaut
    
    local result
    result=$(_build_audio_params "/fake/high_aac.mkv")
    
    # Doit contenir libopus et le bitrate cible (128k par défaut)
    [[ "$result" =~ "libopus" ]]
    [[ "$result" =~ "128k" ]]
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
