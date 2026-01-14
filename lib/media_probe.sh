#!/bin/bash
###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. ffprobe peut retourner des codes non-zéro pour des
#    fichiers corrompus (comportement géré par le code)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

# Récupère TOUTES les métadonnées nécessaires en un seul appel ffprobe.
# Optimise les performances en évitant les appels multiples.
# Usage: get_full_media_metadata <file>
# Retourne: video_bitrate|video_codec|duration|width|height|pix_fmt|audio_codec|audio_bitrate
get_full_media_metadata() {
    local file="$1"
    
    # Appel unique ffprobe pour format + streams
    # On récupère tout ce qui est potentiellement utile
    local output
    output=$(ffprobe_safe -v error \
        -show_entries format=duration,bit_rate \
        -show_entries stream=index,codec_type,codec_name,bit_rate,width,height,pix_fmt:stream_tags=BPS \
        -of default=noprint_wrappers=0 \
        "$file" 2>/dev/null || true)
    
    # Parsing avec awk pour extraire les infos vidéo (premier flux vidéo) et audio (premier flux audio)
    local parsed
    parsed=$(echo "$output" | awk -F= '
    BEGIN {
        v_idx=-1; a_idx=-1;
        # Global results
        res_v_bitrate=0; res_v_codec=""; res_v_width=0; res_v_height=0; res_v_pix_fmt="";
        res_a_codec=""; res_a_bitrate=0;
        
        # Format info
        f_duration=0; f_bitrate=0;
        
        # Current stream info
        curr_idx=-1; curr_type=""; curr_codec=""; curr_bitrate=0; curr_width=0; curr_height=0; curr_pix_fmt=""; curr_bps=0;
    }

    # Function to commit current stream
    function commit_stream() {
        if (curr_idx == -1) return;
        
        if (curr_type == "video" && v_idx == -1) {
            v_idx = curr_idx;
            res_v_codec = curr_codec;
            res_v_bitrate = curr_bitrate;
            if (res_v_bitrate == 0 || res_v_bitrate == "N/A") res_v_bitrate = curr_bps;
            res_v_width = curr_width;
            res_v_height = curr_height;
            res_v_pix_fmt = curr_pix_fmt;
        }
        if (curr_type == "audio" && a_idx == -1) {
            a_idx = curr_idx;
            res_a_codec = curr_codec;
            res_a_bitrate = curr_bitrate;
            if (res_a_bitrate == 0 || res_a_bitrate == "N/A") res_a_bitrate = curr_bps;
        }
    }

    /^\[STREAM\]/ {
        commit_stream();
        curr_idx = -2; # Mark as inside stream but index not yet found
        # Reset current stream vars
        curr_type=""; curr_codec=""; curr_bitrate=0; curr_width=0; curr_height=0; curr_pix_fmt=""; curr_bps=0;
    }

    /^\[\/STREAM\]/ {
        commit_stream();
        curr_idx = -1;
    }

    /^\[FORMAT\]/ {
        commit_stream(); # Safety
        curr_idx = -1;
    }

    /^index=/ {
        curr_idx = $2;
    }

    /^codec_type=/ { curr_type = $2 }
    /^codec_name=/ { curr_codec = $2 }
    /^bit_rate=/ {
        if (curr_idx != -1) curr_bitrate = $2
        else f_bitrate = $2
    }
    /^width=/ { curr_width = $2 }
    /^height=/ { curr_height = $2 }
    /^pix_fmt=/ { curr_pix_fmt = $2 }
    /^TAG:BPS=/ { curr_bps = $2 }
    /^duration=/ { f_duration = $2 }
    
    END {
        commit_stream(); # Commit the last stream
        
        # Final logic
        if (res_v_bitrate == 0 || res_v_bitrate == "N/A") res_v_bitrate = f_bitrate;
        
        # Cleanup
        if (res_v_bitrate == "N/A") res_v_bitrate=0;
        if (res_a_bitrate == "N/A") res_a_bitrate=0;
        if (f_duration == "N/A") f_duration=0;
        
        print res_v_bitrate "|" res_v_codec "|" f_duration "|" res_v_width "|" res_v_height "|" res_v_pix_fmt "|" res_a_codec "|" res_a_bitrate
    }
    ')
    
    echo "$parsed"
}

get_video_metadata() {
    local file="$1"
    local metadata_output
    local format_output
    
    # Récupération des métadonnées du stream vidéo
    metadata_output=$(ffprobe_safe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)
    
    # Récupération séparée des métadonnées du format (container)
    # Note: -select_streams empêche l'accès aux infos format, donc requête séparée
    format_output=$(ffprobe_safe -v error \
        -show_entries format=bit_rate,duration \
        "$file" 2>/dev/null || true)
    
    # Parsing des résultats stream (format: key=value)
    local bitrate_stream
    bitrate_stream=$(echo "$metadata_output" | awk -F= '/^bit_rate=/{print $2; exit}')
    local bitrate_bps
    bitrate_bps=$(echo "$metadata_output" | awk -F= '/^TAG:BPS=/{print $2}')
    local codec
    codec=$(echo "$metadata_output" | awk -F= '/^codec_name=/{print $2}')
    
    # Parsing des résultats format (container)
    local bitrate_container
    bitrate_container=$(echo "$format_output" | awk -F= '/^bit_rate=/{print $2}')
    local duration
    duration=$(echo "$format_output" | awk -F= '/^duration=/{print $2}')
    
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
# ANALYSE DES PROPRIÉTÉS AUDIO
###########################################################

# Récupère les infos audio du premier flux audio d'un fichier.
# Centralise les appels ffprobe audio pour éviter les duplications.
# Usage: _probe_audio_info <file>
# Retour: codec|bitrate_kbps (bitrate en kbps, 0 si non disponible)
_probe_audio_info() {
    local file="$1"
    
    local audio_info
    audio_info=$(ffprobe_safe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)
    
    local codec bitrate bitrate_tag bitrate_kbps
    codec=$(echo "$audio_info" | awk -F= '/^codec_name=/{print $2; exit}')
    bitrate=$(echo "$audio_info" | awk -F= '/^bit_rate=/{print $2; exit}')
    bitrate_tag=$(echo "$audio_info" | awk -F= '/^TAG:BPS=/{print $2; exit}')
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$bitrate" || "$bitrate" == "N/A" ]]; then
        bitrate="$bitrate_tag"
    fi
    
    # Convertir en kbps
    if declare -f clean_number &>/dev/null; then
        bitrate=$(clean_number "$bitrate")
    fi
    bitrate_kbps=0
    if [[ -n "$bitrate" && "$bitrate" =~ ^[0-9]+$ ]]; then
        bitrate_kbps=$((bitrate / 1000))
    fi
    
    echo "${codec}|${bitrate_kbps}"
}

# Récupère le nombre de canaux et le layout audio du premier flux audio.
# Usage: _probe_audio_channels <file>
# Retour: channels|channel_layout (ex: "6|5.1" ou "2|stereo" ou "6|" si layout indéfini)
_probe_audio_channels() {
    local file="$1"
    
    local audio_info
    audio_info=$(ffprobe_safe -v error \
        -select_streams a:0 \
        -show_entries stream=channels,channel_layout \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)
    
    local channels channel_layout
    channels=$(echo "$audio_info" | awk -F= '/^channels=/{print $2; exit}')
    channel_layout=$(echo "$audio_info" | awk -F= '/^channel_layout=/{print $2; exit}')
    
    # Valeurs par défaut si non disponibles
    [[ -z "$channels" || "$channels" == "N/A" ]] && channels="2"
    [[ "$channel_layout" == "N/A" ]] && channel_layout=""
    
    echo "${channels}|${channel_layout}"
}

# Récupère les infos audio complètes (codec, bitrate, channels) en un seul appel.
# Usage: _probe_audio_full <file>
# Retour: codec|bitrate_kbps|channels|channel_layout
_probe_audio_full() {
    local file="$1"
    
    local audio_info
    audio_info=$(ffprobe_safe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate,channels,channel_layout:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)
    
    local codec bitrate bitrate_tag bitrate_kbps channels channel_layout
    codec=$(echo "$audio_info" | awk -F= '/^codec_name=/{print $2; exit}')
    bitrate=$(echo "$audio_info" | awk -F= '/^bit_rate=/{print $2; exit}')
    bitrate_tag=$(echo "$audio_info" | awk -F= '/^TAG:BPS=/{print $2; exit}')
    channels=$(echo "$audio_info" | awk -F= '/^channels=/{print $2; exit}')
    channel_layout=$(echo "$audio_info" | awk -F= '/^channel_layout=/{print $2; exit}')
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$bitrate" || "$bitrate" == "N/A" ]]; then
        bitrate="$bitrate_tag"
    fi
    
    # Convertir en kbps
    if declare -f clean_number &>/dev/null; then
        bitrate=$(clean_number "$bitrate")
    fi
    bitrate_kbps=0
    if [[ -n "$bitrate" && "$bitrate" =~ ^[0-9]+$ ]]; then
        bitrate_kbps=$((bitrate / 1000))
    fi
    
    # Valeurs par défaut
    [[ -z "$channels" || "$channels" == "N/A" ]] && channels="2"
    [[ "$channel_layout" == "N/A" ]] && channel_layout=""
    
    echo "${codec}|${bitrate_kbps}|${channels}|${channel_layout}"
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
    out=$(ffprobe_safe -v error \
        -select_streams v:0 \
        -show_entries stream=width,height,pix_fmt \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)

    local width height pix_fmt
    width=$(echo "$out" | awk -F= '/^width=/{print $2; exit}')
    height=$(echo "$out" | awk -F= '/^height=/{print $2; exit}')
    pix_fmt=$(echo "$out" | awk -F= '/^pix_fmt=/{print $2; exit}')

    echo "${width}|${height}|${pix_fmt}"
}

###########################################################
# DÉTECTION HARDWARE ACCELERATION
###########################################################

# Détecte et définit la variable HWACCEL utilisée pour le décodage matériel.
# Appelée une fois au démarrage pour configurer le décodeur.
detect_hwaccel() {
    # shellcheck disable=SC2034
    HWACCEL=""

    # macOS -> videotoolbox
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # shellcheck disable=SC2034
        HWACCEL="videotoolbox"
    else
        # shellcheck disable=SC2034
        HWACCEL="cuda"
    fi
}
