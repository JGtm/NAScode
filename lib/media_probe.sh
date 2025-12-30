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
