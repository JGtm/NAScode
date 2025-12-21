#!/bin/bash
###########################################################
# ANALYSE DES MÉTADONNÉES AUDIO
# TODO: Réactiver quand VLC supportera mieux Opus surround dans MKV
###########################################################

# # Activer la conversion audio vers Opus
# AUDIO_OPUS_ENABLED=true
# # Bitrate cible pour l'audio Opus (kbps)
# readonly AUDIO_OPUS_TARGET_KBPS=128
# # Seuil minimum pour considérer la conversion audio avantageuse (kbps)
# # On ne convertit que si le bitrate source est > seuil (évite de ré-encoder du déjà compressé)
# readonly AUDIO_CONVERSION_THRESHOLD_KBPS=160
#
# # Analyse l'audio d'un fichier et détermine si la conversion Opus est avantageuse
# # Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert to opus)
# get_audio_metadata() {
#     local file="$1"
#     
#     # Récupérer les infos audio du premier flux audio
#     local audio_info
#     audio_info=$(ffprobe -v error \
#         -select_streams a:0 \
#         -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
#         -of default=noprint_wrappers=1 \
#         "$file" 2>/dev/null)
#     
#     local audio_codec=$(echo "$audio_info" | grep '^codec_name=' | cut -d'=' -f2)
#     local audio_bitrate=$(echo "$audio_info" | grep '^bit_rate=' | cut -d'=' -f2)
#     local audio_bitrate_tag=$(echo "$audio_info" | grep '^TAG:BPS=' | cut -d'=' -f2)
#     
#     # Utiliser le tag BPS si bitrate direct non disponible
#     if [[ -z "$audio_bitrate" || "$audio_bitrate" == "N/A" ]]; then
#         audio_bitrate="$audio_bitrate_tag"
#     fi
#     
#     # Convertir en kbps
#     audio_bitrate=$(clean_number "$audio_bitrate")
#     local audio_bitrate_kbps=0
#     if [[ -n "$audio_bitrate" && "$audio_bitrate" =~ ^[0-9]+$ ]]; then
#         audio_bitrate_kbps=$((audio_bitrate / 1000))
#     fi
#     
#     # Déterminer si la conversion est avantageuse
#     local should_convert=0
#     
#     # Ne pas convertir si déjà en Opus
#     if [[ "$audio_codec" == "opus" ]]; then
#         should_convert=0
#     # Convertir si le bitrate source est supérieur au seuil
#     elif [[ "$audio_bitrate_kbps" -gt "$AUDIO_CONVERSION_THRESHOLD_KBPS" ]]; then
#         should_convert=1
#     fi
#     
#     echo "${audio_codec}|${audio_bitrate_kbps}|${should_convert}"
# }

###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
###########################################################

get_video_metadata() {
    local file="$1"
    local metadata_output
    local format_output
    
    # Récupération des métadonnées du stream vidéo
    metadata_output=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null)
    
    # Récupération séparée des métadonnées du format (container)
    # Note: -select_streams empêche l'accès aux infos format, donc requête séparée
    format_output=$(ffprobe -v error \
        -show_entries format=bit_rate,duration \
        "$file" 2>/dev/null)
    
    # Parsing des résultats stream (format: key=value)
    local bitrate_stream=$(echo "$metadata_output" | awk -F= '/^bit_rate=/{print $2; exit}')
    local bitrate_bps=$(echo "$metadata_output" | awk -F= '/^TAG:BPS=/{print $2}')
    local codec=$(echo "$metadata_output" | awk -F= '/^codec_name=/{print $2}')
    
    # Parsing des résultats format (container)
    local bitrate_container=$(echo "$format_output" | awk -F= '/^bit_rate=/{print $2}')
    local duration=$(echo "$format_output" | awk -F= '/^duration=/{print $2}')
    
    # Nettoyage des valeurs
    bitrate_stream=$(clean_number "$bitrate_stream")
    bitrate_bps=$(clean_number "$bitrate_bps")
    bitrate_container=$(clean_number "$bitrate_container")
    
    # Détermination du bitrate prioritaire
    # Priorité : bitrate stream > tag BPS > bitrate container (fallback)
    local bitrate=0
    if [[ -n "$bitrate_stream" && "$bitrate_stream" -gt 0 ]]; then 
        bitrate="$bitrate_stream"
    elif [[ -n "$bitrate_bps" && "$bitrate_bps" -gt 0 ]]; then 
        bitrate="$bitrate_bps"
    elif [[ -n "$bitrate_container" && "$bitrate_container" -gt 0 ]]; then 
        bitrate="$bitrate_container"
    fi
    
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then 
        bitrate=0
    fi
    
    if [[ -z "$duration" ]] || ! [[ "$duration" =~ ^[0-9.]+$ ]]; then 
        duration=1
    fi
    
    # Retour des valeurs séparées par des pipes
    echo "${bitrate}|${codec}|${duration}"
}

###########################################################
# ANALYSE DES PROPRIÉTÉS VIDÉO (RÉSOLUTION / PIX_FMT)
###########################################################

# Récupère des infos de base sur le flux vidéo (résolution + pixel format).
# Usage: get_video_stream_props <file>
# Retour: width|height|pix_fmt (valeurs vides si non disponibles)
get_video_stream_props() {
    local file="$1"
    local out
    out=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=width,height,pix_fmt \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null)

    local width height pix_fmt
    width=$(echo "$out" | awk -F= '/^width=/{print $2; exit}')
    height=$(echo "$out" | awk -F= '/^height=/{print $2; exit}')
    pix_fmt=$(echo "$out" | awk -F= '/^pix_fmt=/{print $2; exit}')

    echo "${width}|${height}|${pix_fmt}"
}
