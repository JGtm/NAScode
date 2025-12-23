#!/bin/bash
###########################################################
# MAPPAGE DES FLUX (stream mapping)
# 
# Fonctions pures pour la sélection des flux vidéo,
# audio et sous-titres.
###########################################################

###########################################################
# SÉLECTION SOUS-TITRES FR
###########################################################

# Cherche un flux de sous-titres français dans le fichier.
# Usage: find_french_subtitle_stream <input_file>
# Retourne: index du flux (ex: "0:s:0") ou chaîne vide si non trouvé
find_french_subtitle_stream() {
    local input_file="$1"
    
    # Liste tous les flux de sous-titres avec leurs tags language
    local streams_info
    streams_info=$(ffprobe -v error \
        -select_streams s \
        -show_entries stream=index:stream_tags=language \
        -of csv=p=0 \
        "$input_file" 2>/dev/null)
    
    local stream_index=0
    while IFS=',' read -r index language; do
        # Normaliser la langue en minuscules
        language=$(echo "$language" | tr '[:upper:]' '[:lower:]')
        
        # Chercher les variantes françaises
        if [[ "$language" == "fre" || "$language" == "fra" || "$language" == "french" ]]; then
            echo "0:s:$stream_index"
            return 0
        fi
        ((stream_index++))
    done <<< "$streams_info"
    
    echo ""
}

# Cherche un flux de sous-titres anglais dans le fichier.
# Usage: find_english_subtitle_stream <input_file>
# Retourne: index du flux (ex: "0:s:0") ou chaîne vide si non trouvé
find_english_subtitle_stream() {
    local input_file="$1"
    
    # Liste tous les flux de sous-titres avec leurs tags language
    local streams_info
    streams_info=$(ffprobe -v error \
        -select_streams s \
        -show_entries stream=index:stream_tags=language \
        -of csv=p=0 \
        "$input_file" 2>/dev/null)
    
    local stream_index=0
    while IFS=',' read -r index language; do
        # Normaliser la langue en minuscules
        language=$(echo "$language" | tr '[:upper:]' '[:lower:]')
        
        # Chercher les variantes anglaises
        if [[ "$language" == "eng" || "$language" == "en" || "$language" == "english" ]]; then
            echo "0:s:$stream_index"
            return 0
        fi
        ((stream_index++))
    done <<< "$streams_info"
    
    echo ""
}

###########################################################
# CONSTRUCTION MAPPING SOUS-TITRES
###########################################################

# Construit les paramètres de mapping des sous-titres selon les préférences.
# Usage: build_subtitle_mapping <input_file> [strategy]
# Strategy: "fr_only" | "fr_en" | "all" | "none"
# Retourne: paramètres ffmpeg (ex: "-map 0:s:0 -c:s copy")
build_subtitle_mapping() {
    local input_file="$1"
    local strategy="${2:-fr_en}"
    
    case "$strategy" in
        "none")
            echo "-sn"
            return 0
            ;;
        "all")
            echo "-map 0:s? -c:s copy"
            return 0
            ;;
        "fr_only")
            local fr_stream
            fr_stream=$(find_french_subtitle_stream "$input_file")
            if [[ -n "$fr_stream" ]]; then
                echo "-map $fr_stream -c:s copy"
            else
                echo "-sn"
            fi
            return 0
            ;;
        "fr_en"|*)
            # Stratégie par défaut: FR prioritaire, sinon EN, sinon rien
            local fr_stream en_stream
            fr_stream=$(find_french_subtitle_stream "$input_file")
            
            if [[ -n "$fr_stream" ]]; then
                echo "-map $fr_stream -c:s copy"
                return 0
            fi
            
            en_stream=$(find_english_subtitle_stream "$input_file")
            if [[ -n "$en_stream" ]]; then
                echo "-map $en_stream -c:s copy"
                return 0
            fi
            
            # Aucun sous-titre FR ou EN trouvé
            echo "-sn"
            return 0
            ;;
    esac
}

###########################################################
# ANALYSE DES SOUS-TITRES
###########################################################

# Liste tous les sous-titres avec leurs langues et types.
# Usage: list_subtitle_streams <input_file>
# Retourne: liste au format "index|language|codec|title" par ligne
list_subtitle_streams() {
    local input_file="$1"
    
    ffprobe -v error \
        -select_streams s \
        -show_entries stream=index,codec_name:stream_tags=language,title \
        -of csv=p=0 \
        "$input_file" 2>/dev/null | \
    while IFS=',' read -r index codec language title; do
        echo "${index}|${language:-und}|${codec}|${title:-}"
    done
}

# Compte le nombre de flux de sous-titres.
# Usage: count_subtitle_streams <input_file>
# Retourne: nombre de flux
count_subtitle_streams() {
    local input_file="$1"
    
    local count
    count=$(ffprobe -v error \
        -select_streams s \
        -show_entries stream=index \
        -of csv=p=0 \
        "$input_file" 2>/dev/null | wc -l)
    
    echo "$count"
}
