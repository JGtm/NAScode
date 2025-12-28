#!/bin/bash
###########################################################
# PARAMÈTRES AUDIO (AAC, AC3, Opus, codec selection)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
###########################################################

###########################################################
# BITRATE CIBLE
###########################################################

# Retourne le bitrate cible pour le codec audio configuré
# Usage: _get_audio_target_bitrate
# Retourne: bitrate en kbps
_get_audio_target_bitrate() {
    # Si un bitrate custom est défini, l'utiliser
    if [[ "${AUDIO_BITRATE_KBPS:-0}" -gt 0 ]]; then
        echo "$AUDIO_BITRATE_KBPS"
        return 0
    fi
    
    # Sinon utiliser le défaut selon le codec
    case "${AUDIO_CODEC:-copy}" in
        aac)  echo "${AUDIO_BITRATE_AAC_DEFAULT:-160}" ;;
        ac3)  echo "${AUDIO_BITRATE_AC3_DEFAULT:-384}" ;;
        opus) echo "${AUDIO_BITRATE_OPUS_DEFAULT:-128}" ;;
        *)    echo "0" ;;
    esac
}

###########################################################
# ANALYSE AUDIO
###########################################################

# Analyse l'audio d'un fichier et détermine si la conversion est avantageuse.
# Logique anti-upscaling : ne convertit que si on y gagne vraiment.
# Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert)
_get_audio_conversion_info() {
    local input_file="$1"
    
    # Si mode copy, toujours copier
    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|0|0"
        return 0
    fi
    
    # Récupérer les infos audio du premier flux audio
    local audio_info
    audio_info=$(ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$input_file" 2>/dev/null || true)
    
    local source_codec source_bitrate source_bitrate_tag
    source_codec=$(echo "$audio_info" | awk -F= '/^codec_name=/{print $2; exit}')
    source_bitrate=$(echo "$audio_info" | awk -F= '/^bit_rate=/{print $2; exit}')
    source_bitrate_tag=$(echo "$audio_info" | awk -F= '/^TAG:BPS=/{print $2; exit}')
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$source_bitrate" || "$source_bitrate" == "N/A" ]]; then
        source_bitrate="$source_bitrate_tag"
    fi
    
    # Convertir en kbps
    source_bitrate=$(clean_number "$source_bitrate")
    local source_bitrate_kbps=0
    if [[ -n "$source_bitrate" && "$source_bitrate" =~ ^[0-9]+$ ]]; then
        source_bitrate_kbps=$((source_bitrate / 1000))
    fi
    
    # Déterminer si la conversion est avantageuse
    local should_convert=0
    local target_codec="${AUDIO_CODEC:-copy}"
    local target_bitrate
    target_bitrate=$(_get_audio_target_bitrate)
    
    # Règle 1 : Ne pas convertir si déjà dans le codec cible
    if [[ "$source_codec" == "$target_codec" ]]; then
        should_convert=0
    # Règle 2 : Ne pas convertir si bitrate source inconnu (sécurité)
    elif [[ "$source_bitrate_kbps" -eq 0 ]]; then
        should_convert=0
    # Règle 3 : Ne pas convertir si le bitrate source est déjà ≤ cible (anti-upscaling)
    elif [[ "$source_bitrate_kbps" -le "$target_bitrate" ]]; then
        should_convert=0
    # Règle 4 : Convertir si on gagne au moins 10% de bitrate
    elif [[ "$source_bitrate_kbps" -gt $((target_bitrate * 110 / 100)) ]]; then
        should_convert=1
    fi
    
    echo "${source_codec}|${source_bitrate_kbps}|${should_convert}"
}

# Détermine si l'audio d'un fichier doit être converti.
# Wrapper simple pour _get_audio_conversion_info.
# Usage: _should_convert_audio <input_file>
# Retourne: 0 si l'audio doit être converti, 1 sinon
_should_convert_audio() {
    local input_file="$1"
    
    local audio_info should_convert
    audio_info=$(_get_audio_conversion_info "$input_file")
    should_convert=$(echo "$audio_info" | cut -d'|' -f3)
    
    if [[ "$should_convert" -eq 1 ]]; then
        return 0  # Doit être converti
    fi
    return 1  # Pas besoin de conversion
}

###########################################################
# CONSTRUCTION PARAMÈTRES FFMPEG
###########################################################

# Construit les paramètres audio FFmpeg selon la configuration
# Usage: _build_audio_params <input_file>
_build_audio_params() {
    local input_file="$1"
    
    local audio_info should_convert
    audio_info=$(_get_audio_conversion_info "$input_file")
    should_convert=$(echo "$audio_info" | cut -d'|' -f3)
    
    if [[ "$should_convert" -eq 1 ]]; then
        local target_bitrate
        target_bitrate=$(_get_audio_target_bitrate)
        
        case "${AUDIO_CODEC:-copy}" in
            aac)
                # AAC avec normalisation des layouts audio
                echo "-c:a aac -b:a ${target_bitrate}k"
                ;;
            ac3)
                # AC3 (Dolby Digital)
                echo "-c:a ac3 -b:a ${target_bitrate}k"
                ;;
            opus)
                # Opus avec normalisation des layouts audio (évite les erreurs VLC)
                echo "-c:a libopus -b:a ${target_bitrate}k -af aformat=channel_layouts=7.1|5.1|stereo|mono"
                ;;
            *)
                echo "-c:a copy"
                ;;
        esac
    else
        # Copier l'audio tel quel
        echo "-c:a copy"
    fi
}
