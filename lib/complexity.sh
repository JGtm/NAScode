#!/bin/bash
###########################################################
# ANALYSE DE COMPLEXITÉ VIDÉO
#
# Module pour le mode adaptatif : calcule un coefficient
# de complexité basé sur l'analyse statistique des frames.
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. L'analyse peut échouer (fallback au mode normal)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

# ----- Constantes du mode adaptatif -----
# NOTE: Ces constantes sont définies dans lib/constants.sh (chargé en premier).
# Les valeurs ci-dessous servent de fallback si constants.sh n'est pas chargé (tests isolés).
: "${ADAPTIVE_BPP_BASE:=0.032}"
: "${ADAPTIVE_C_MIN:=0.85}"
: "${ADAPTIVE_C_MAX:=1.25}"
: "${ADAPTIVE_STDDEV_LOW:=0.20}"
: "${ADAPTIVE_STDDEV_HIGH:=0.45}"
: "${ADAPTIVE_SAMPLE_DURATION:=10}"
: "${ADAPTIVE_SAMPLE_COUNT:=20}"
: "${ADAPTIVE_MARGIN_START_PCT:=5}"
: "${ADAPTIVE_MARGIN_END_PCT:=8}"
: "${ADAPTIVE_MIN_BITRATE_KBPS:=800}"
: "${ADAPTIVE_MAXRATE_FACTOR:=1.4}"
: "${ADAPTIVE_BUFSIZE_FACTOR:=2.5}"

# Constantes SI/TI (Spatial/Temporal Information)
: "${ADAPTIVE_WEIGHT_STDDEV:=0.40}"
: "${ADAPTIVE_WEIGHT_SI:=0.30}"
: "${ADAPTIVE_WEIGHT_TI:=0.30}"
: "${ADAPTIVE_SI_MAX:=100}"
: "${ADAPTIVE_TI_MAX:=50}"
: "${ADAPTIVE_USE_SITI:=true}"

###########################################################
# SPINNER ANIMÉ POUR ANALYSE SI/TI
###########################################################

# Affiche un spinner animé pendant l'analyse SI/TI.
# Doit être lancé en arrière-plan et tué une fois l'analyse terminée.
# Usage: _start_siti_spinner &
#        spinner_pid=$!
#        ...analyse...
#        kill $spinner_pid 2>/dev/null
_start_siti_spinner() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while true; do
        printf "\r\033[K  %s Analyse SI/TI..." "${frames[i]}" >&2
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
}

###########################################################
# ANALYSE DES FRAMES
###########################################################

# Génère N positions d'échantillonnage réparties uniformément.
# Évite les génériques début/fin selon les marges configurées.
# Usage: _generate_sample_positions <duration_seconds> <sample_count>
# Retourne: positions séparées par des espaces
_generate_sample_positions() {
    local duration_int="$1"
    local count="${2:-$ADAPTIVE_SAMPLE_COUNT}"
    
    # Marges en secondes (calculées à partir des pourcentages)
    local margin_start=$(( duration_int * ADAPTIVE_MARGIN_START_PCT / 100 ))
    local margin_end=$(( duration_int * ADAPTIVE_MARGIN_END_PCT / 100 ))
    
    # Plage utilisable
    local usable_start="$margin_start"
    local usable_end=$(( duration_int - margin_end ))
    local usable_range=$(( usable_end - usable_start ))
    
    # Sécurité : si la plage est trop petite
    if [[ "$usable_range" -lt "$count" ]]; then
        echo "$margin_start"
        return
    fi
    
    # Générer les positions uniformément réparties
    local positions=()
    local step=$(( usable_range / (count + 1) ))
    
    for ((i=1; i<=count; i++)); do
        positions+=( $(( usable_start + step * i )) )
    done
    
    echo "${positions[*]}"
}

# Extrait les tailles de frames sur un segment donné.
# Usage: _get_frame_sizes <file> <start_seconds> <duration_seconds>
# Retourne: liste de tailles de frames (une par ligne)
_get_frame_sizes() {
    local file="$1"
    local start_sec="$2"
    local duration_sec="$3"
    
    ffprobe_safe -v error \
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

###########################################################
# ANALYSE SI/TI (Spatial/Temporal Information)
# Basé sur ITU-T P.910 - métriques standard de complexité vidéo
###########################################################

# Calcule SI (Spatial Information) et TI (Temporal Information) sur un échantillon.
# Utilise le filtre FFmpeg 'siti' disponible depuis FFmpeg 5.0+
# Usage: _compute_siti <file> <start_seconds> <duration_seconds>
# Retourne: SI|TI (valeurs moyennes)
_compute_siti() {
    local file="$1"
    local start_sec="$2"
    local duration_sec="$3"
    
    # Essayer d'utiliser le filtre siti (FFmpeg 5+)
    local siti_output
    siti_output=$(ffmpeg -hide_banner -ss "$start_sec" -t "$duration_sec" -i "$file" \
        -vf "siti=print_summary=1" -f null - 2>&1)
    
    # Parser la sortie pour extraire SI et TI moyens
    local si ti
    si=$(echo "$siti_output" | grep -oP 'SI:\s*\K[0-9.]+' | tail -1)
    ti=$(echo "$siti_output" | grep -oP 'TI:\s*\K[0-9.]+' | tail -1)
    
    # Fallback si le filtre siti n'est pas disponible
    if [[ -z "$si" ]] || [[ -z "$ti" ]]; then
        # Retourner des valeurs neutres (milieu de plage)
        echo "50|25"
        return 0
    fi
    
    echo "${si}|${ti}"
}

# Vérifie si le filtre siti est disponible dans FFmpeg
_is_siti_available() {
    ffmpeg -hide_banner -filters 2>/dev/null | grep -q "siti"
}

# Normalise une valeur SI entre 0 et 1
# SI typique: 0-100 (peut dépasser pour contenus très texturés)
_normalize_si() {
    local si="$1"
    awk -v si="$si" -v max="$ADAPTIVE_SI_MAX" 'BEGIN { 
        norm = si / max
        if (norm > 1) norm = 1
        if (norm < 0) norm = 0
        printf "%.4f", norm
    }'
}

# Normalise une valeur TI entre 0 et 1
# TI typique: 0-50 (peut dépasser pour contenus très dynamiques)
_normalize_ti() {
    local ti="$1"
    awk -v ti="$ti" -v max="$ADAPTIVE_TI_MAX" 'BEGIN {
        norm = ti / max
        if (norm > 1) norm = 1
        if (norm < 0) norm = 0
        printf "%.4f", norm
    }'
}

# Analyse SI/TI sur plusieurs échantillons et retourne les moyennes.
# Usage: _analyze_siti_multi <file> <duration_seconds> <positions_array>
# Retourne: SI_avg|TI_avg
_analyze_siti_multi() {
    local file="$1"
    local duration_int="$2"
    shift 2
    local positions=("$@")
    
    local sample_duration="${ADAPTIVE_SAMPLE_DURATION}"
    local si_sum=0 ti_sum=0 count=0
    local margin_end=$(( duration_int * ADAPTIVE_MARGIN_END_PCT / 100 ))
    local margin_start=$(( duration_int * ADAPTIVE_MARGIN_START_PCT / 100 ))
    local max_start=$(( duration_int - sample_duration - margin_end ))
    
    for pos in "${positions[@]}"; do
        # Ajuster la position
        [[ "$pos" -gt "$max_start" ]] && pos="$max_start"
        [[ "$pos" -lt "$margin_start" ]] && pos="$margin_start"
        
        local siti_result si ti
        siti_result=$(_compute_siti "$file" "$pos" "$sample_duration")
        IFS='|' read -r si ti <<< "$siti_result"
        
        if [[ "$si" =~ ^[0-9.]+$ ]] && [[ "$ti" =~ ^[0-9.]+$ ]]; then
            si_sum=$(awk -v sum="$si_sum" -v val="$si" 'BEGIN { printf "%.4f", sum + val }')
            ti_sum=$(awk -v sum="$ti_sum" -v val="$ti" 'BEGIN { printf "%.4f", sum + val }')
            ((count++))
        fi
    done
    
    if [[ "$count" -eq 0 ]]; then
        echo "50|25"
        return
    fi
    
    local si_avg ti_avg
    si_avg=$(awk -v sum="$si_sum" -v n="$count" 'BEGIN { printf "%.2f", sum / n }')
    ti_avg=$(awk -v sum="$ti_sum" -v n="$count" 'BEGIN { printf "%.2f", sum / n }')
    
    echo "${si_avg}|${ti_avg}"
}

###########################################################
# ANALYSE COMBINÉE (stddev + SI + TI)
###########################################################

# Analyse la complexité d'un fichier vidéo via multi-échantillonnage.
# Prend N échantillons répartis sur la durée pour une meilleure représentativité.
# Si ADAPTIVE_USE_SITI=true, combine stddev + SI + TI selon les pondérations.
# Usage: analyze_video_complexity <file> <duration_seconds> [show_progress]
# Retourne: stddev|SI_avg|TI_avg (3 métriques séparées par |)
analyze_video_complexity() {
    local file="$1"
    local duration="$2"
    local show_progress="${3:-false}"
    
    # Validation des entrées
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        echo "0|50|25"
        return 1
    fi
    
    if [[ -z "$duration" ]] || ! [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "0|50|25"
        return 1
    fi
    
    # Convertir la durée en entier pour les calculs (LC_NUMERIC pour gérer les décimales)
    local duration_int
    duration_int=$(LC_NUMERIC=C printf "%.0f" "$duration")

    # Note UX: l'analyse peut s'exécuter dans un sous-shell ($( ... )).
    # On imprime donc un titre explicite sur stderr pour éviter la confusion en parallèle.
    if [[ "$show_progress" == true ]] && [[ "${NO_PROGRESS:-false}" != true ]] && [[ "${UI_QUIET:-false}" != true ]]; then
        local filename
        filename=$(basename "$file")
        local counter_prefix=""
        if declare -f _get_counter_prefix &>/dev/null; then
            counter_prefix=$(_get_counter_prefix)
        fi
        echo -e "${counter_prefix}▶️ Analyse de complexité du fichier : ${filename}" >&2
    fi
    
    # Minimum requis : 60 secondes pour une analyse fiable
    if [[ "$duration_int" -lt 60 ]]; then
        # Fichier trop court : analyser tout le fichier (stddev seulement)
        if [[ "$show_progress" == true ]] && [[ "${NO_PROGRESS:-false}" != true ]]; then
            _show_analysis_progress 1 1
        fi
        local all_frames stddev
        all_frames=$(_get_frame_sizes "$file" 0 "$duration_int")
        stddev=$(_compute_normalized_stddev "$all_frames")
        # Valeurs SI/TI neutres pour fichiers courts
        echo "${stddev}|50|25"
        return 0
    fi
    
    # Points d'échantillonnage : N positions réparties uniformément
    # Évite les génériques de début/fin selon les marges configurées
    local sample_duration="${ADAPTIVE_SAMPLE_DURATION}"
    local sample_count="${ADAPTIVE_SAMPLE_COUNT}"
    
    # Générer les positions dynamiquement
    local positions_str
    positions_str=$(_generate_sample_positions "$duration_int" "$sample_count")
    read -ra positions <<< "$positions_str"
    
    # Marge de sécurité pour ne pas dépasser la fin
    local margin_end=$(( duration_int * ADAPTIVE_MARGIN_END_PCT / 100 ))
    local margin_start=$(( duration_int * ADAPTIVE_MARGIN_START_PCT / 100 ))
    
    # S'assurer qu'on ne dépasse pas la fin et qu'on respecte les marges
    local max_start=$(( duration_int - sample_duration - margin_end ))
    local all_frames=""
    local total_samples=${#positions[@]}
    local current_sample=0
    
    for pos in "${positions[@]}"; do
        ((current_sample++))
        
        # Ajuster la position si nécessaire
        [[ "$pos" -gt "$max_start" ]] && pos="$max_start"
        [[ "$pos" -lt "$margin_start" ]] && pos="$margin_start"
        
        # Afficher la progression si demandé
        if [[ "$show_progress" == true ]] && [[ "${NO_PROGRESS:-false}" != true ]]; then
            _show_analysis_progress "$current_sample" "$total_samples"
        fi
        
        # Collecter les frames de cet échantillon
        local frames
        frames=$(_get_frame_sizes "$file" "$pos" "$sample_duration")
        
        if [[ -n "$all_frames" ]]; then
            all_frames=$(printf "%s\n%s" "$all_frames" "$frames")
        else
            all_frames="$frames"
        fi
    done
    
    # Calculer stddev des frames
    local stddev
    stddev=$(_compute_normalized_stddev "$all_frames")
    
    # Analyse SI/TI si activée et disponible
    local si_avg="50" ti_avg="25"
    if [[ "${ADAPTIVE_USE_SITI:-true}" == true ]]; then
        if _is_siti_available; then
            local siti_result
            # Utiliser un sous-ensemble des positions pour SI/TI (plus rapide)
            local siti_positions=("${positions[@]:0:5}")  # 5 premiers échantillons
            
            # Lancer le spinner en arrière-plan si progress activé
            local spinner_pid=""
            if [[ "$show_progress" == true ]] && [[ "${NO_PROGRESS:-false}" != true ]]; then
                _start_siti_spinner &
                spinner_pid=$!
            fi
            
            siti_result=$(_analyze_siti_multi "$file" "$duration_int" "${siti_positions[@]}")
            IFS='|' read -r si_avg ti_avg <<< "$siti_result"
            
            # Arrêter le spinner
            if [[ -n "$spinner_pid" ]]; then
                kill "$spinner_pid" 2>/dev/null || true
                wait "$spinner_pid" 2>/dev/null || true
                printf "\r\033[K" >&2
            fi
        fi
    fi
    
    # Retourner les 3 métriques séparées
    echo "${stddev}|${si_avg}|${ti_avg}"
}

# Affiche une barre de progression pour l'analyse de complexité
# Usage: _show_analysis_progress <current> <total>
_show_analysis_progress() {
    local current="$1"
    local total="$2"
    local percent=$((current * 100 / total))

    local status_label
    if [[ "$percent" -ge 100 ]]; then
        status_label="⚡ Calcul terminé"
    else
        status_label="⚡ Calcul en cours"
    fi

        # Aligner avec la progression FFmpeg :
        # "  <emoji> <label sur 25 chars> <bar> ..."
        local emoji="⚡"
        local label_text="${status_label#${emoji} }"
    
    # Construire la barre de progression (20 caractères)
    local bar_width=20
    local filled=$((percent * bar_width / 100))
    local bar="╢"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=filled; i<bar_width; i++)); do bar+="░"; done
    bar+="╟"
    
    # Afficher sur stderr pour ne pas polluer la sortie
    if [[ "$percent" -ge 100 ]]; then
        # Terminé : afficher avec ✓ et nouvelle ligne pour garder visible
           printf "\r\033[K  %s %-25.25s %s 100%%\n" "$emoji" "$label_text" "$bar" >&2
    else
           printf "\r\033[K  %s %-25.25s %s %3d%%" "$emoji" "$label_text" "$bar" "$percent" >&2
    fi
}

###########################################################
# CALCUL DU SCORE COMBINÉ ET COEFFICIENT C
###########################################################

# Calcule un score combiné normalisé à partir des 3 métriques.
# Usage: _compute_combined_score <stddev> <si> <ti>
# Retourne: score entre 0 et 1
_compute_combined_score() {
    local stddev="$1"
    local si="$2"
    local ti="$3"
    
    # Normaliser stddev entre 0 et 1 (basé sur les seuils)
    local stddev_norm
    stddev_norm=$(awk -v s="$stddev" -v low="$ADAPTIVE_STDDEV_LOW" -v high="$ADAPTIVE_STDDEV_HIGH" '
    BEGIN {
        if (s <= low) { print 0; exit }
        if (s >= high) { print 1; exit }
        printf "%.4f", (s - low) / (high - low)
    }')
    
    # Normaliser SI et TI
    local si_norm ti_norm
    si_norm=$(_normalize_si "$si")
    ti_norm=$(_normalize_ti "$ti")
    
    # Score pondéré
    awk -v s="$stddev_norm" -v si="$si_norm" -v ti="$ti_norm" \
        -v ws="$ADAPTIVE_WEIGHT_STDDEV" -v wsi="$ADAPTIVE_WEIGHT_SI" -v wti="$ADAPTIVE_WEIGHT_TI" '
    BEGIN {
        score = s * ws + si * wsi + ti * wti
        if (score < 0) score = 0
        if (score > 1) score = 1
        printf "%.4f", score
    }'
}

# Mappe le score combiné vers le coefficient de complexité C.
# Usage: _map_score_to_complexity <combined_score>
# Retourne: coefficient C entre ADAPTIVE_C_MIN et ADAPTIVE_C_MAX
_map_score_to_complexity() {
    local score="$1"
    
    awk -v score="$score" -v c_min="$ADAPTIVE_C_MIN" -v c_max="$ADAPTIVE_C_MAX" '
    BEGIN {
        c = c_min + score * (c_max - c_min)
        printf "%.2f", c
    }'
}

# Mappe les métriques combinées (stddev + SI + TI) vers le coefficient C.
# Usage: _map_metrics_to_complexity <stddev> <si> <ti>
# Retourne: coefficient C entre ADAPTIVE_C_MIN et ADAPTIVE_C_MAX
_map_metrics_to_complexity() {
    local stddev="$1"
    local si="${2:-50}"
    local ti="${3:-25}"
    
    # Si SI/TI désactivé ou valeurs neutres, utiliser l'ancien mapping stddev seul
    if [[ "${ADAPTIVE_USE_SITI:-true}" != true ]] || [[ "$si" == "50" && "$ti" == "25" ]]; then
        _map_stddev_to_complexity "$stddev"
        return
    fi
    
    local combined_score
    combined_score=$(_compute_combined_score "$stddev" "$si" "$ti")
    _map_score_to_complexity "$combined_score"
}

# Mappe le coefficient de variation vers le coefficient de complexité C.
# (Legacy - conservé pour rétro-compatibilité des tests)
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

# Analyse complète d'un fichier pour le mode adaptatif.
# Usage: get_adaptive_encoding_params <file>
# Retourne: target_kbps|maxrate_kbps|bufsize_kbps|complexity_C|complexity_desc|metrics
#
# Exemple: 2450|3430|6125|1.12|standard (film typique)|0.32|45.2|18.3
get_adaptive_encoding_params() {
    local file="$1"
    
    # Récupérer les métadonnées
    local metadata
    metadata=$(get_full_media_metadata "$file")
    
    local video_bitrate _video_codec duration width height _pix_fmt _audio_codec _audio_bitrate
    IFS='|' read -r video_bitrate _video_codec duration width height _pix_fmt _audio_codec _audio_bitrate <<< "$metadata"
    
    # Récupérer le FPS
    local fps
    fps=$(ffprobe_safe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$file" 2>/dev/null | head -1)
    
    # Convertir le FPS (format "24000/1001" ou "24")
    if [[ "$fps" == *"/"* ]]; then
        fps=$(awk -F/ '{if($2>0) printf "%.3f", $1/$2; else print $1}' <<< "$fps")
    fi
    [[ -z "$fps" ]] && fps="24"
    
    # Analyser la complexité (retourne stddev|SI|TI)
    local analysis_result stddev si_avg ti_avg
    analysis_result=$(analyze_video_complexity "$file" "$duration" true)
    IFS='|' read -r stddev si_avg ti_avg <<< "$analysis_result"
    
    # Calculer le coefficient C avec les 3 métriques
    local complexity_c complexity_desc
    complexity_c=$(_map_metrics_to_complexity "$stddev" "$si_avg" "$ti_avg")
    complexity_desc=$(_describe_complexity "$complexity_c")
    
    # Calculer les paramètres d'encodage
    local target_kbps maxrate_kbps bufsize_kbps
    target_kbps=$(compute_adaptive_target_bitrate "$width" "$height" "$fps" "$complexity_c" "$video_bitrate")
    maxrate_kbps=$(compute_adaptive_maxrate "$target_kbps")
    bufsize_kbps=$(compute_adaptive_bufsize "$target_kbps")
    
    # Retourner les résultats avec les métriques détaillées
    echo "${target_kbps}|${maxrate_kbps}|${bufsize_kbps}|${complexity_c}|${complexity_desc}|${stddev}|${si_avg}|${ti_avg}"
}

# Affiche les informations d'analyse de complexité (pour l'UI).
# Usage: display_complexity_analysis <file> <complexity_C> <complexity_desc> <stddev> <target_kbps> [si] [ti]
display_complexity_analysis() {
    local file="$1"
    local complexity_c="$2"
    local complexity_desc="$3"
    local stddev="$4"
    local target_kbps="$5"
    local si="${6:-}"
    local ti="${7:-}"
    
    # --no-progress ne doit pas cacher les infos (seulement les barres de progression).
    # --quiet (UI_QUIET) doit rester silencieux.
    if [[ "${UI_QUIET:-false}" == true ]]; then
        return 0
    fi
    
    local filename
    filename=$(basename "$file")

    echo -e "  📊 Résultats d'analyse :"
    echo -e "${DIM}     └─ Coefficient de variation (stddev) : ${stddev}${NOCOLOR}"
    
    # Afficher SI/TI si disponibles et non neutres
    if [[ -n "$si" ]] && [[ -n "$ti" ]] && [[ "${ADAPTIVE_USE_SITI:-true}" == true ]]; then
        if [[ "$si" != "50" ]] || [[ "$ti" != "25" ]]; then
            echo -e "${DIM}     └─ Complexité spatiale (SI) : ${si}${NOCOLOR}"
            echo -e "${DIM}     └─ Complexité temporelle (TI) : ${ti}${NOCOLOR}"
        fi
    fi
    
    echo -e "${DIM}     └─ Complexité (C) : ${complexity_c} → ${complexity_desc^}${NOCOLOR}"
    echo -e "${DIM}     └─ Bitrate cible (encodage) : ${target_kbps} kbps${NOCOLOR}"
}
