#!/bin/bash
###########################################################
# ANALYSE DE COMPLEXITÉ VIDÉO
#
# Module pour le mode film-adaptive : calcule un coefficient
# de complexité basé sur l'analyse statistique des frames.
###########################################################

# ----- Constantes du mode film-adaptive -----
# BPP (Bits Per Pixel) de référence pour HEVC
# Calibré pour produire ~2000-3500 kbps en 1080p@24fps
readonly ADAPTIVE_BPP_BASE=0.045

# Coefficient de complexité : bornes min/max
readonly ADAPTIVE_C_MIN=0.75
readonly ADAPTIVE_C_MAX=1.35

# Seuils de mapping std-dev → coefficient C
# Basés sur l'écart-type normalisé des tailles de frames
# Ces valeurs sont à affiner avec un corpus de test réel
readonly ADAPTIVE_STDDEV_LOW=0.15    # En dessous : contenu statique
readonly ADAPTIVE_STDDEV_HIGH=0.35   # Au dessus : contenu complexe

# Durée d'échantillon par point (secondes)
readonly ADAPTIVE_SAMPLE_DURATION=10

# Plancher qualité (kbps minimum)
readonly ADAPTIVE_MIN_BITRATE_KBPS=800

# Facteur multiplicateur pour maxrate (ratio vs target)
readonly ADAPTIVE_MAXRATE_FACTOR=1.4

# Facteur multiplicateur pour bufsize (ratio vs target)
readonly ADAPTIVE_BUFSIZE_FACTOR=2.5

###########################################################
# ANALYSE DES FRAMES
###########################################################

# Extrait les tailles de frames sur un segment donné.
# Usage: _get_frame_sizes <file> <start_seconds> <duration_seconds>
# Retourne: liste de tailles de frames (une par ligne)
_get_frame_sizes() {
    local file="$1"
    local start_sec="$2"
    local duration_sec="$3"
    
    ffprobe -v error \
        -select_streams v:0 \
        -read_intervals "${start_sec}%+${duration_sec}" \
        -show_entries frame=pkt_size \
        -of csv=p=0 \
        "$file" 2>/dev/null | grep -E '^[0-9]+$'
}

# Calcule l'écart-type normalisé des tailles de frames.
# Usage: _compute_normalized_stddev <frame_sizes_newline_separated>
# Retourne: écart-type divisé par la moyenne (coefficient de variation)
_compute_normalized_stddev() {
    local frame_data="$1"
    
    echo "$frame_data" | awk '
    BEGIN { n=0; sum=0; sumsq=0 }
    /^[0-9]+$/ {
        n++
        sum += $1
        sumsq += $1 * $1
    }
    END {
        if (n < 2) { print "0"; exit }
        mean = sum / n
        if (mean <= 0) { print "0"; exit }
        variance = (sumsq / n) - (mean * mean)
        if (variance < 0) variance = 0
        stddev = sqrt(variance)
        # Coefficient de variation (normalisé)
        cv = stddev / mean
        printf "%.4f\n", cv
    }'
}

# Analyse la complexité d'un fichier vidéo via multi-échantillonnage.
# Prend 3 échantillons à 25%, 50% et 75% de la durée.
# Usage: analyze_video_complexity <file> <duration_seconds>
# Retourne: coefficient de variation moyen (écart-type normalisé)
analyze_video_complexity() {
    local file="$1"
    local duration="$2"
    
    # Validation des entrées
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi
    
    if [[ -z "$duration" ]] || ! [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "0"
        return 1
    fi
    
    # Convertir la durée en entier pour les calculs
    local duration_int
    duration_int=$(printf "%.0f" "$duration")
    
    # Minimum requis : 60 secondes pour une analyse fiable
    if [[ "$duration_int" -lt 60 ]]; then
        # Fichier trop court : analyser tout le fichier
        local all_frames
        all_frames=$(_get_frame_sizes "$file" 0 "$duration_int")
        _compute_normalized_stddev "$all_frames"
        return 0
    fi
    
    # Points d'échantillonnage : 25%, 50%, 75%
    local sample_duration="${ADAPTIVE_SAMPLE_DURATION}"
    local margin=30  # Marge pour éviter les génériques
    
    local pos_25=$(( (duration_int * 25 / 100) ))
    local pos_50=$(( (duration_int * 50 / 100) ))
    local pos_75=$(( (duration_int * 75 / 100) ))
    
    # S'assurer qu'on ne dépasse pas la fin
    local max_start=$(( duration_int - sample_duration - margin ))
    [[ "$pos_25" -gt "$max_start" ]] && pos_25="$max_start"
    [[ "$pos_50" -gt "$max_start" ]] && pos_50="$max_start"
    [[ "$pos_75" -gt "$max_start" ]] && pos_75="$max_start"
    [[ "$pos_25" -lt "$margin" ]] && pos_25="$margin"
    
    # Collecter les frames des 3 échantillons
    local frames_25 frames_50 frames_75
    frames_25=$(_get_frame_sizes "$file" "$pos_25" "$sample_duration")
    frames_50=$(_get_frame_sizes "$file" "$pos_50" "$sample_duration")
    frames_75=$(_get_frame_sizes "$file" "$pos_75" "$sample_duration")
    
    # Combiner et calculer l'écart-type global
    local all_frames
    all_frames=$(printf "%s\n%s\n%s" "$frames_25" "$frames_50" "$frames_75")
    
    _compute_normalized_stddev "$all_frames"
}

# Mappe le coefficient de variation vers le coefficient de complexité C.
# Usage: _map_stddev_to_complexity <normalized_stddev>
# Retourne: coefficient C entre ADAPTIVE_C_MIN et ADAPTIVE_C_MAX
_map_stddev_to_complexity() {
    local stddev="$1"
    
    awk -v stddev="$stddev" \
        -v low="$ADAPTIVE_STDDEV_LOW" \
        -v high="$ADAPTIVE_STDDEV_HIGH" \
        -v c_min="$ADAPTIVE_C_MIN" \
        -v c_max="$ADAPTIVE_C_MAX" \
    'BEGIN {
        if (stddev <= low) {
            print c_min
        } else if (stddev >= high) {
            print c_max
        } else {
            # Interpolation linéaire
            ratio = (stddev - low) / (high - low)
            c = c_min + ratio * (c_max - c_min)
            printf "%.2f\n", c
        }
    }'
}

# Décrit le niveau de complexité en texte lisible.
# Usage: _describe_complexity <coefficient_C>
# Retourne: description textuelle
_describe_complexity() {
    local c="$1"
    
    awk -v c="$c" -v c_min="$ADAPTIVE_C_MIN" -v c_max="$ADAPTIVE_C_MAX" '
    BEGIN {
        range = c_max - c_min
        third = range / 3
        
        if (c <= c_min + third) {
            print "statique (dialogues/interviews)"
        } else if (c <= c_min + 2*third) {
            print "standard (film typique)"
        } else {
            print "complexe (action/grain/pluie)"
        }
    }'
}

###########################################################
# CALCUL DU BITRATE ADAPTATIF
###########################################################

# Calcule le bitrate cible adaptatif pour un fichier.
# Usage: compute_adaptive_target_bitrate <width> <height> <fps> <complexity_C> <original_bitrate_bps>
# Retourne: bitrate cible en kbps (après garde-fous)
compute_adaptive_target_bitrate() {
    local width="$1"
    local height="$2"
    local fps="$3"
    local complexity_c="$4"
    local original_bitrate_bps="$5"
    
    # Validation des entrées
    if [[ -z "$width" ]] || [[ -z "$height" ]] || [[ -z "$fps" ]]; then
        echo "0"
        return 1
    fi
    
    # Valeur par défaut pour C si non fourni
    [[ -z "$complexity_c" ]] && complexity_c="1.0"
    
    # Calcul R_target = (W × H × FPS × BPP_base / 1000) × C
    local r_target
    r_target=$(awk -v w="$width" -v h="$height" -v fps="$fps" \
                   -v bpp="$ADAPTIVE_BPP_BASE" -v c="$complexity_c" '
    BEGIN {
        r = (w * h * fps * bpp / 1000) * c
        printf "%.0f\n", r
    }')
    
    # Garde-fou 1 : ne pas dépasser 75% du bitrate original
    if [[ -n "$original_bitrate_bps" ]] && [[ "$original_bitrate_bps" =~ ^[0-9]+$ ]] && [[ "$original_bitrate_bps" -gt 0 ]]; then
        local original_kbps=$(( original_bitrate_bps / 1000 ))
        local max_from_original=$(( original_kbps * 75 / 100 ))
        
        if [[ "$r_target" -gt "$max_from_original" ]]; then
            r_target="$max_from_original"
        fi
    fi
    
    # Garde-fou 2 : plancher qualité
    if [[ "$r_target" -lt "$ADAPTIVE_MIN_BITRATE_KBPS" ]]; then
        r_target="$ADAPTIVE_MIN_BITRATE_KBPS"
    fi
    
    echo "$r_target"
}

# Calcule le maxrate adaptatif.
# Usage: compute_adaptive_maxrate <target_bitrate_kbps>
# Retourne: maxrate en kbps
compute_adaptive_maxrate() {
    local target_kbps="$1"
    awk -v t="$target_kbps" -v f="$ADAPTIVE_MAXRATE_FACTOR" 'BEGIN { printf "%.0f\n", t * f }'
}

# Calcule le bufsize adaptatif.
# Usage: compute_adaptive_bufsize <target_bitrate_kbps>
# Retourne: bufsize en kbps
compute_adaptive_bufsize() {
    local target_kbps="$1"
    awk -v t="$target_kbps" -v f="$ADAPTIVE_BUFSIZE_FACTOR" 'BEGIN { printf "%.0f\n", t * f }'
}

###########################################################
# API PUBLIQUE
###########################################################

# Analyse complète d'un fichier pour le mode film-adaptive.
# Usage: get_adaptive_encoding_params <file>
# Retourne: target_kbps|maxrate_kbps|bufsize_kbps|complexity_C|complexity_desc
#
# Exemple: 2450|3430|6125|1.12|standard (film typique)
get_adaptive_encoding_params() {
    local file="$1"
    
    # Récupérer les métadonnées
    local metadata
    metadata=$(get_full_media_metadata "$file")
    
    local video_bitrate video_codec duration width height pix_fmt audio_codec audio_bitrate
    IFS='|' read -r video_bitrate video_codec duration width height pix_fmt audio_codec audio_bitrate <<< "$metadata"
    
    # Récupérer le FPS
    local fps
    fps=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$file" 2>/dev/null | head -1)
    
    # Convertir le FPS (format "24000/1001" ou "24")
    if [[ "$fps" == *"/"* ]]; then
        fps=$(awk -F/ '{if($2>0) printf "%.3f", $1/$2; else print $1}' <<< "$fps")
    fi
    [[ -z "$fps" ]] && fps="24"
    
    # Analyser la complexité
    local stddev complexity_c complexity_desc
    stddev=$(analyze_video_complexity "$file" "$duration")
    complexity_c=$(_map_stddev_to_complexity "$stddev")
    complexity_desc=$(_describe_complexity "$complexity_c")
    
    # Calculer les paramètres d'encodage
    local target_kbps maxrate_kbps bufsize_kbps
    target_kbps=$(compute_adaptive_target_bitrate "$width" "$height" "$fps" "$complexity_c" "$video_bitrate")
    maxrate_kbps=$(compute_adaptive_maxrate "$target_kbps")
    bufsize_kbps=$(compute_adaptive_bufsize "$target_kbps")
    
    echo "${target_kbps}|${maxrate_kbps}|${bufsize_kbps}|${complexity_c}|${complexity_desc}|${stddev}"
}

# Affiche les informations d'analyse de complexité (pour l'UI).
# Usage: display_complexity_analysis <file> <complexity_C> <complexity_desc> <stddev> <target_kbps>
display_complexity_analysis() {
    local file="$1"
    local complexity_c="$2"
    local complexity_desc="$3"
    local stddev="$4"
    local target_kbps="$5"
    
    if [[ "${NO_PROGRESS:-false}" == true ]]; then
        return 0
    fi
    
    local filename
    filename=$(basename "$file")
    
    echo -e "${CYAN}  📊 Analyse de complexité :${NOCOLOR}"
    echo -e "${DIM}     └─ Coefficient de variation : ${stddev}${NOCOLOR}"
    echo -e "${DIM}     └─ Complexité (C) : ${complexity_c} → ${complexity_desc}${NOCOLOR}"
    echo -e "${DIM}     └─ Bitrate adaptatif : ${target_kbps} kbps${NOCOLOR}"
}
