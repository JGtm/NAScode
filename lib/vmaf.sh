#!/bin/bash
###########################################################
# ANALYSE VMAF
# Calcul du score VMAF (qualité vidéo perceptuelle)
###########################################################

###########################################################
# CALCUL DU SCORE VMAF
###########################################################

# Calcul du score VMAF (qualité vidéo perceptuelle)
# Usage : compute_vmaf_score <fichier_original> <fichier_converti> [filename_display] [current_index] [total_count]
# Retourne le score VMAF moyen (0-100) ou "NA" si indisponible
compute_vmaf_score() {
    local original="$1"
    local converted="$2"
    local filename_display="${3:-}"
    local current_index="${4:-}"
    local total_count="${5:-}"
    
    # Vérifier que libvmaf est disponible
    if [[ "$HAS_LIBVMAF" -ne 1 ]]; then
        echo "NA"
        return 0
    fi
    
    # Vérifier que les deux fichiers existent
    if [[ ! -f "$original" ]] || [[ ! -f "$converted" ]]; then
        echo "NA"
        return 0
    fi
    
    # Fichiers temporaires dans logs/vmaf/
    local vmaf_dir="${LOG_DIR}/vmaf"
    mkdir -p "$vmaf_dir" 2>/dev/null || true
    local file_hash
    file_hash=$(compute_md5_prefix "$filename_display")
    local vmaf_log_file="${vmaf_dir}/vmaf_${file_hash}_${$}_${RANDOM}.json"
    local progress_file="${vmaf_dir}/vmaf_progress_$$.txt"
    
    # Obtenir la durée totale de la vidéo en microsecondes pour la progression
    local duration_us=0
    local duration_str
    duration_str=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$converted" 2>/dev/null)
    if [[ -n "$duration_str" ]]; then
        # Convertir en microsecondes (durée est en secondes avec décimales)
        duration_us=$(awk "BEGIN {printf \"%.0f\", $duration_str * 1000000}")
    fi
    
    # Calculer le score VMAF avec subsampling (1 frame sur 5 pour accélérer)
    # n_subsample=5 : analyse seulement 20% des frames (5x plus rapide)
    if [[ "$NO_PROGRESS" != true ]] && [[ "$duration_us" -gt 0 ]] && [[ -n "$filename_display" ]]; then
        # Lancer ffmpeg en arrière-plan avec progression vers fichier
        ffmpeg -hide_banner -nostdin -i "$converted" -i "$original" \
            -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=$vmaf_log_file:n_subsample=5" \
            -progress "$progress_file" \
            -f null - >/dev/null 2>&1 &
        local ffmpeg_pid=$!
        
        local last_percent=-1
        # Afficher la progression en lisant le fichier (écrire sur /dev/tty pour éviter capture)
        while kill -0 "$ffmpeg_pid" 2>/dev/null; do
            if [[ -f "$progress_file" ]]; then
                local out_time_us
                out_time_us=$(grep -o 'out_time_us=[0-9]*' "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2)
                if [[ -n "$out_time_us" ]] && [[ "$out_time_us" =~ ^[0-9]+$ ]] && [[ "$out_time_us" -gt 0 ]]; then
                    local percent=$((out_time_us * 100 / duration_us))
                    [[ $percent -gt 100 ]] && percent=100
                    # Afficher seulement si le pourcentage a changé
                    if [[ "$percent" -ne "$last_percent" ]]; then
                        last_percent=$percent
                        # Barre de progression
                        local filled=$((percent / 5))
                        local empty=$((20 - filled))
                        local bar=""
                        for ((i=0; i<filled; i++)); do bar+="█"; done
                        for ((i=0; i<empty; i++)); do bar+="░"; done
                        # Tronquer le titre à 30 caractères max
                        local short_name="$filename_display"
                        if [[ ${#short_name} -gt 30 ]]; then
                            short_name="${short_name:0:27}..."
                        fi
                        # Construire le préfixe avec compteur si disponible
                        local counter_prefix=""
                        if [[ -n "$current_index" ]] && [[ -n "$total_count" ]]; then
                            counter_prefix="[$current_index/$total_count] "
                        fi
                        # Écrire sur stderr (fd 2) pour éviter capture par $()
                        # Compteur et nom de fichier en CYAN
                        printf "\r  \033[0;36m%s%-30s\033[0m VMAF [%s] %3d%%" "$counter_prefix" "$short_name" "$bar" "$percent" >&2
                    fi
                fi
            fi
            sleep 0.2
        done
        wait "$ffmpeg_pid" 2>/dev/null
        printf "\r%100s\r" "" >&2  # Effacer la ligne de progression
    else
        # Sans barre de progression
        ffmpeg -hide_banner -nostdin -i "$converted" -i "$original" \
            -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=$vmaf_log_file:n_subsample=5" \
            -f null - >/dev/null 2>&1
    fi
    
    # Nettoyer le fichier de progression
    rm -f "$progress_file" 2>/dev/null || true
    
    # Extraire le score VMAF depuis le fichier JSON
    local vmaf_score=""
    if [[ -f "$vmaf_log_file" ]] && [[ -s "$vmaf_log_file" ]]; then
        vmaf_score=$(grep -o '"mean"[[:space:]]*:[[:space:]]*[0-9.]*' "$vmaf_log_file" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Nettoyer le fichier temporaire
    rm -f "$vmaf_log_file" 2>/dev/null || true
    
    if [[ -n "$vmaf_score" ]]; then
        # Arrondir à 2 décimales
        printf "%.2f" "$vmaf_score"
    else
        echo "NA"
    fi
}

###########################################################
# GESTION DE LA QUEUE VMAF
###########################################################

# Enregistrer une paire de fichiers pour analyse VMAF ultérieure
# Usage : _queue_vmaf_analysis <fichier_original> <fichier_converti>
# Les analyses seront effectuées à la fin de toutes les conversions
_queue_vmaf_analysis() {
    local file_original="$1"
    local final_actual="$2"
    
    # Vérifier que évaluation VMAF est activée
    if [[ "$VMAF_ENABLED" != true ]]; then
        return 0
    fi
    
    # Vérifier que libvmaf est disponible
    if [[ "$HAS_LIBVMAF" -ne 1 ]]; then
        return 0
    fi
    
    # Vérifier que les deux fichiers existent
    if [[ ! -f "$file_original" ]] || [[ ! -f "$final_actual" ]]; then
        return 0
    fi
    
    # Enregistrer la paire dans le fichier de queue (format: original|converti)
    echo "${file_original}|${final_actual}" >> "$VMAF_QUEUE_FILE" 2>/dev/null || true
}

# Traiter toutes les analyses VMAF en attente
# Appelé à la fin de toutes les conversions, avant le résumé
process_vmaf_queue() {
    if [[ ! -f "$VMAF_QUEUE_FILE" ]] || [[ ! -s "$VMAF_QUEUE_FILE" ]]; then
        return 0
    fi
    
    local vmaf_count
    vmaf_count=$(wc -l < "$VMAF_QUEUE_FILE" 2>/dev/null | tr -d ' ') || vmaf_count=0
    
    if [[ "$vmaf_count" -eq 0 ]]; then
        return 0
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo ""
        echo -e "${BLUE}📊 Analyse VMAF de $vmaf_count fichier(s)...${NOCOLOR}"
    fi
    
    local current=0
    while IFS='|' read -r file_original final_actual; do
        ((current++)) || true
        
        # Vérifier que les fichiers existent toujours
        if [[ ! -f "$file_original" ]] || [[ ! -f "$final_actual" ]]; then
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "  ${YELLOW}⚠${NOCOLOR} [$current/$vmaf_count] Fichier(s) introuvable(s), ignoré"
            fi
            continue
        fi
        
        local filename
        filename=$(basename "$final_actual")
        
        # Calculer le score VMAF (avec barre de progression intégrée)
        local vmaf_score
        vmaf_score=$(compute_vmaf_score "$file_original" "$final_actual" "$filename" "$current" "$vmaf_count")
        
        # Interpréter le score VMAF
        local vmaf_quality=""
        if [[ "$vmaf_score" != "NA" ]]; then
            local vmaf_int=${vmaf_score%.*}
            if [[ "$vmaf_int" -ge 90 ]]; then
                vmaf_quality="EXCELLENT"
            elif [[ "$vmaf_int" -ge 80 ]]; then
                vmaf_quality="TRES_BON"
            elif [[ "$vmaf_int" -ge 70 ]]; then
                vmaf_quality="BON"
            else
                vmaf_quality="DEGRADE"
            fi
        fi
        
        # Logger le score VMAF
        if [[ -n "$LOG_SUCCESS" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | VMAF | $file_original → $final_actual | score:${vmaf_score} | quality:${vmaf_quality:-NA}" >> "$LOG_SUCCESS" 2>/dev/null || true
        fi
        
        if [[ "$NO_PROGRESS" != true ]]; then
            local status_icon="${GREEN}✓${NOCOLOR}"
            if [[ "$vmaf_score" == "NA" ]]; then
                status_icon="${YELLOW}?${NOCOLOR}"
            elif [[ "$vmaf_quality" == "DEGRADE" ]]; then
                status_icon="${RED}✗${NOCOLOR}"
            fi
            # Tronquer le nom de fichier à 30 caractères pour aligner
            local short_fn="$filename"
            if [[ ${#short_fn} -gt 30 ]]; then
                short_fn="${short_fn:0:27}..."
            fi
            # Compteur et nom de fichier en CYAN
            printf "\r  %s ${CYAN}[%d/%d] %-30s${NOCOLOR} : %s (%s)%20s\n" "$status_icon" "$current" "$vmaf_count" "$short_fn" "$vmaf_score" "${vmaf_quality:-NA}" "" >&2
        fi
        
    done < "$VMAF_QUEUE_FILE"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${GREEN}✅ Analyses VMAF terminées${NOCOLOR}"
    fi
    
    # Nettoyer le fichier de queue
    rm -f "$VMAF_QUEUE_FILE" 2>/dev/null || true
}
