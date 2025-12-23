#!/bin/bash
###########################################################
# PARAMÈTRES AUDIO (Opus, codec selection)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
###########################################################

###########################################################
# ANALYSE AUDIO
###########################################################

# Analyse l'audio d'un fichier et détermine si la conversion Opus est avantageuse.
# Usage: get_audio_conversion_info <input_file>
# Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert to opus)
get_audio_conversion_info() {
    local input_file="$1"
    
    # Si Opus désactivé, toujours copier
    if [[ "${OPUS_ENABLED:-false}" != true ]]; then
        echo "copy|0|0"
        return 0
    fi
    
    # Récupérer les infos audio du premier flux audio
    local audio_info
    audio_info=$(ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$input_file" 2>/dev/null)
    
    local audio_codec audio_bitrate audio_bitrate_tag
    audio_codec=$(echo "$audio_info" | grep '^codec_name=' | cut -d'=' -f2)
    audio_bitrate=$(echo "$audio_info" | grep '^bit_rate=' | cut -d'=' -f2)
    audio_bitrate_tag=$(echo "$audio_info" | grep '^TAG:BPS=' | cut -d'=' -f2)
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$audio_bitrate" || "$audio_bitrate" == "N/A" ]]; then
        audio_bitrate="$audio_bitrate_tag"
    fi
    
    # Convertir en kbps
    audio_bitrate=$(clean_number "$audio_bitrate")
    local audio_bitrate_kbps=0
    if [[ -n "$audio_bitrate" && "$audio_bitrate" =~ ^[0-9]+$ ]]; then
        audio_bitrate_kbps=$((audio_bitrate / 1000))
    fi
    
    # Déterminer si la conversion est avantageuse
    local should_convert=0
    
    # Ne pas convertir si déjà en Opus
    if [[ "$audio_codec" == "opus" ]]; then
        should_convert=0
    # Convertir si le bitrate source est supérieur au seuil
    elif [[ "$audio_bitrate_kbps" -gt "${OPUS_CONVERSION_THRESHOLD_KBPS:-160}" ]]; then
        should_convert=1
    fi
    
    echo "${audio_codec}|${audio_bitrate_kbps}|${should_convert}"
}

###########################################################
# CONSTRUCTION PARAMÈTRES FFMPEG
###########################################################

# Construit les paramètres audio FFmpeg selon l'analyse.
# Usage: build_audio_params <input_file>
# Retourne: chaîne de paramètres ffmpeg (ex: "-c:a copy" ou "-c:a libopus -b:a 128k ...")
build_audio_params() {
    local input_file="$1"
    
    local audio_info should_convert
    audio_info=$(get_audio_conversion_info "$input_file")
    should_convert=$(echo "$audio_info" | cut -d'|' -f3)
    
    if [[ "$should_convert" -eq 1 ]]; then
        # Conversion vers Opus avec normalisation des layouts audio
        # -af "aformat=channel_layouts=..." normalise les layouts non-standard
        echo "-c:a libopus -b:a ${OPUS_TARGET_BITRATE_KBPS:-128}k -af aformat=channel_layouts=7.1|5.1|stereo|mono"
    else
        # Copier l'audio tel quel
        echo "-c:a copy"
    fi
}
