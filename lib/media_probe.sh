#!/bin/bash
###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
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
    output=$(ffprobe -v error \
        -show_entries format=duration,bit_rate \
        -show_entries stream=index,codec_type,codec_name,bit_rate,width,height,pix_fmt:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)
    
    # Parsing avec awk pour extraire les infos vidéo (premier flux vidéo) et audio (premier flux audio)
    local parsed
    parsed=$(echo "$output" | awk -F= '
    BEGIN {
        v_idx=-1; a_idx=-1;
        v_codec=""; v_bitrate=0; v_width=0; v_height=0; v_pix_fmt=""; v_bps=0;
        a_codec=""; a_bitrate=0; a_bps=0;
        f_duration=0; f_bitrate=0;
        current_index=-1; current_type="";
    }
    /^index=/ { current_index=$2 }
    /^codec_type=/ { current_type=$2 }
    /^codec_name=/ { 
        if (current_type=="video" && v_idx==-1) { v_idx=current_index; v_codec=$2 }
        if (current_type=="audio" && a_idx==-1) { a_idx=current_index; a_codec=$2 }
    }
    /^bit_rate=/ {
        if (current_type=="video" && current_index==v_idx) v_bitrate=$2
        if (current_type=="audio" && current_index==a_idx) a_bitrate=$2
        if (current_index==-1) f_bitrate=$2  # format bit_rate n a pas d index
    }
    /^width=/ { if (current_type=="video" && current_index==v_idx) v_width=$2 }
    /^height=/ { if (current_type=="video" && current_index==v_idx) v_height=$2 }
    /^pix_fmt=/ { if (current_type=="video" && current_index==v_idx) v_pix_fmt=$2 }
    /^TAG:BPS=/ {
        if (current_type=="video" && current_index==v_idx) v_bps=$2
        if (current_type=="audio" && current_index==a_idx) a_bps=$2
    }
    /^duration=/ { f_duration=$2 }
    
    END {
        # Logique bitrate vidéo : stream > bps > container
        final_v_bitrate = v_bitrate;
        if (final_v_bitrate == 0 || final_v_bitrate == "N/A") final_v_bitrate = v_bps;
        if (final_v_bitrate == 0 || final_v_bitrate == "N/A") final_v_bitrate = f_bitrate;
        
        # Logique bitrate audio : stream > bps
        final_a_bitrate = a_bitrate;
        if (final_a_bitrate == 0 || final_a_bitrate == "N/A") final_a_bitrate = a_bps;
        
        # Nettoyage "N/A"
        if (final_v_bitrate == "N/A") final_v_bitrate=0;
        if (final_a_bitrate == "N/A") final_a_bitrate=0;
        if (f_duration == "N/A") f_duration=0;
        
        print final_v_bitrate "|" v_codec "|" f_duration "|" v_width "|" v_height "|" v_pix_fmt "|" a_codec "|" final_a_bitrate
    }
    ')
    
    echo "$parsed"
}

get_video_metadata() {
    local file="$1"
    local metadata_output
    local format_output
    
    # Récupération des métadonnées du stream vidéo
    metadata_output=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null || true)
    
    # Récupération séparée des métadonnées du format (container)
    # Note: -select_streams empêche l'accès aux infos format, donc requête séparée
    format_output=$(ffprobe -v error \
        -show_entries format=bit_rate,duration \
        "$file" 2>/dev/null || true)
    
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
    HWACCEL=""

    # macOS -> videotoolbox
    if [[ "$(uname -s)" == "Darwin" ]]; then
        HWACCEL="videotoolbox"
    else
        HWACCEL="cuda"
    fi
}
