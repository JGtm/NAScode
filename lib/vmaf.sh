#!/bin/bash
###########################################################
# CALCUL DU SCORE VMAF
###########################################################

# Calcul du score VMAF (qualité vidéo perceptuelle)
# Usage : compute_vmaf_score <fichier_original> <fichier_converti> [filename_display] [current_index] [total_count] [keyframe_pos]
# Retourne le score VMAF moyen (0-100) ou "NA" si indisponible
compute_vmaf_score() {
    local original="$1"
    local converted="$2"
    local filename_display="${3:-}"
    local current_index="${4:-}"
    local total_count="${5:-}"
    local keyframe_pos="${6:-}"  # Position du keyframe (mode sample)
    
    # FFmpeg à utiliser pour VMAF (peut être différent du principal)
    local ffmpeg_cmd="${FFMPEG_VMAF:-ffmpeg}"
    
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
    
    # Vérifier que le fichier converti n'est pas vide (dryrun crée des fichiers de 0 octets)
    local converted_size
    converted_size=$(get_file_size_bytes "$converted")
    if [[ "$converted_size" -eq 0 ]]; then
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
    
    # Construire les options d'input et le filtre lavfi selon le mode (normal ou sample)
    # En mode sample : on utilise la position exacte du keyframe passée en paramètre
    local lavfi_filter
    local original_input_opts=""
    local hwaccel_opts=""
    local sample_duration="${SAMPLE_DURATION:-30}"

    # VMAF requiert des résolutions identiques.
    # Or, la conversion peut downscaler automatiquement (>1080p). Dans ce cas,
    # on scale l'original à la résolution EXACTE du fichier converti.
    local conv_dims
    conv_dims=$(ffprobe_safe -v error -select_streams v:0 -show_entries stream=width,height \
        -of csv=p=0:s=x "$converted" 2>/dev/null | head -1)
    local conv_w="" conv_h=""
    if [[ -n "$conv_dims" ]] && [[ "$conv_dims" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        conv_w="${BASH_REMATCH[1]}"
        conv_h="${BASH_REMATCH[2]}"
    fi

    # Chaîne scale appliquée à l'original si on a une résolution cible valide.
    # Le format=yuv420p force une base commune (utile quand la sortie est 10-bit).
    local ref_chain="format=yuv420p"
    local dist_chain="format=yuv420p"
    if [[ -n "$conv_w" && -n "$conv_h" ]]; then
        ref_chain="scale=w=${conv_w}:h=${conv_h}:flags=lanczos,format=yuv420p"
    fi
    
    # Utiliser hwaccel si disponible pour accélérer le décodage
    if [[ -n "${HWACCEL:-}" ]] && [[ "$HWACCEL" != "none" ]]; then
        hwaccel_opts="-hwaccel $HWACCEL"
    fi
    
    if [[ -n "$keyframe_pos" ]]; then
        # Mode sample : utiliser la position EXACTE du keyframe
        # -ss avec la position précise du keyframe = seek direct au bon endroit
        # -t pour limiter la durée (identique à la conversion)
        original_input_opts="-ss ${keyframe_pos} -t ${sample_duration}"
        # setpts remet les timestamps à 0 pour synchroniser les deux flux
        # On ajoute aussi un format commun et un scale éventuel pour garantir la compatibilité VMAF.
        lavfi_filter="[0:v]setpts=PTS-STARTPTS,${dist_chain}[dist];[1:v]setpts=PTS-STARTPTS,${ref_chain}[ref];[dist][ref]libvmaf=log_fmt=json:log_path=$vmaf_log_file:n_subsample=10:model=version=vmaf_v0.6.1neg"
    else
        # Mode normal : comparaison directe
        # On force un format commun et on scale l'original si besoin (downscale côté conversion).
        lavfi_filter="[0:v]${dist_chain}[dist];[1:v]${ref_chain}[ref];[dist][ref]libvmaf=log_fmt=json:log_path=$vmaf_log_file:n_subsample=5:model=version=vmaf_v0.6.1neg"
    fi

    # Obtenir la durée totale de la vidéo en microsecondes pour la progression
    local duration_us=0
    local duration_str
    duration_str=$(ffprobe_safe -v error -select_streams v:0 -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$converted" 2>/dev/null)
    if [[ -n "$duration_str" ]]; then
        # Convertir en microsecondes (durée est en secondes avec décimales)
        duration_us=$(awk "BEGIN {printf \"%.0f\", $duration_str * 1000000}")
    fi
    
    # Calculer le score VMAF avec subsampling (1 frame sur 5 pour accélérer)
    # n_subsample=5 : analyse seulement 20% des frames (5x plus rapide)
    # model=version=vmaf_v0.6.1neg : utilise VMAF NEG qui pénalise les enhancements artificiels
    local enable_progress=false
    if [[ "$NO_PROGRESS" != true ]] && [[ "$duration_us" -gt 0 ]] && [[ -n "$filename_display" ]]; then
        enable_progress=true
    fi

    # Construire la commande FFmpeg (commune aux deux modes)
    # Note: On utilise $ffmpeg_cmd qui peut être un FFmpeg alternatif avec libvmaf.
    local -a cmd
    cmd=()

    # Permettre un wrapper ffmpeg (ex: "ffmpeg", "path/ffmpeg")
    # Si la variable contient des options, elles seront splittées (convention interne).
    local -a ffmpeg_cmd_arr
    read -r -a ffmpeg_cmd_arr <<< "$ffmpeg_cmd"
    cmd+=("${ffmpeg_cmd_arr[@]}")
    cmd+=(-hide_banner -nostdin -i "$converted")
    _cmd_append_words cmd "$hwaccel_opts"
    _cmd_append_words cmd "$original_input_opts"
    cmd+=(-i "$original")
    cmd+=(-lavfi "$lavfi_filter")
    if [[ "$enable_progress" == true ]]; then
        cmd+=(-progress "$progress_file")
    fi
    cmd+=(-f null -)

    if [[ "$enable_progress" == true ]]; then
        "${cmd[@]}" >/dev/null 2>&1 &
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
                        # Barre de progression avec bordures arrondies
                        local filled=$((percent / 5))
                        local empty=$((20 - filled))
                        local bar="╢"
                        for ((i=0; i<filled; i++)); do bar+="█"; done
                        for ((i=0; i<empty; i++)); do bar+="░"; done
                        bar+="╟"
                        # Tronquer le titre à 45 caractères max
                        local display_name="$filename_display"
                        if [[ ${#display_name} -gt 45 ]]; then
                            display_name="${display_name:0:42}..."
                        fi
                        # Construire le préfixe avec compteur si disponible
                        local counter_prefix=""
                        if [[ -n "$current_index" ]] && [[ -n "$total_count" ]]; then
                            counter_prefix="[$current_index/$total_count] "
                        fi
                        # Écrire sur stderr (fd 2) pour éviter capture par $()
                        # Compteur et nom de fichier en CYAN, espace initial pour aligner avec l'icône de statut
                        printf "\r    \033[0;36m%s%-45s\033[0m %s %3d%%" "$counter_prefix" "$display_name" "$bar" "$percent" >&2
                    fi
                fi
            fi
            sleep 0.2
        done
        wait "$ffmpeg_pid" 2>/dev/null
        printf "\r%100s\r" "" >&2  # Effacer la ligne de progression
    else
        "${cmd[@]}" >/dev/null 2>&1
    fi
    
    # Nettoyer les fichiers temporaires
    rm -f "$progress_file" 2>/dev/null || true
    
    # Extraire le score VMAF depuis le fichier JSON
    # Le format JSON de libvmaf contient : "pooled_metrics": { "vmaf": { "mean": XX.XX, ... } }
    local vmaf_score=""
    if [[ -f "$vmaf_log_file" ]] && [[ -s "$vmaf_log_file" ]]; then
        # Essayer d'extraire le score VMAF mean depuis pooled_metrics
        # Format: "mean": 92.456789 (le score est normalement entre 0 et 100)
        vmaf_score=$(grep -oE '"mean"[[:space:]]*:[[:space:]]*[0-9]+\.?[0-9]*' "$vmaf_log_file" 2>/dev/null | head -1 | grep -oE '[0-9]+\.?[0-9]*$')
    fi
    
    # Nettoyer le fichier temporaire
    rm -f "$vmaf_log_file" 2>/dev/null || true
    
    if [[ -n "$vmaf_score" ]]; then
        # Vérifier si le score est normalisé entre 0 et 1 (certaines versions)
        # Si c'est le cas, multiplier par 100 pour avoir l'échelle 0-100
        local score_int=${vmaf_score%%.*}
        if [[ "$score_int" -eq 0 ]] && [[ $(awk "BEGIN {print ($vmaf_score > 0)}") -eq 1 ]]; then
            # Score entre 0 et 1 (ex: 0.92) -> convertir en 0-100 (ex: 92)
            vmaf_score=$(awk "BEGIN {printf \"%.2f\", $vmaf_score * 100}")
        fi
        # Utiliser awk pour le formatage (insensible à la locale)
        awk "BEGIN {printf \"%.2f\", $vmaf_score}"
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
    
    # Enregistrer la paire dans le fichier de queue
    # Format: original|converti|keyframe_pos (keyframe_pos vide si mode normal)
    local keyframe_pos="${SAMPLE_KEYFRAME_POS:-}"
    echo "${file_original}|${final_actual}|${keyframe_pos}" >> "$VMAF_QUEUE_FILE" 2>/dev/null || true
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

    # Notif Discord (best-effort) : début VMAF
    local _vmaf_total_start_ts
    _vmaf_total_start_ts=$(date +%s 2>/dev/null || echo "")
    if declare -f notify_event &>/dev/null; then
        local _vmaf_mode="normal"
        [[ "${SAMPLE_MODE:-false}" == true ]] && _vmaf_mode="sample"
        notify_event vmaf_started "$vmaf_count" "${_vmaf_mode}" || true
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_vmaf_start "$vmaf_count"
        echo ""  # Saut de ligne après l'en-tête pour aérer l'affichage
    fi
    
    local current=0

    # Stats pour résumé Discord
    local ok_count=0 na_count=0 degraded_count=0
    local sum_scores="0" min_score="" max_score=""
    local -a worst_lines=()

    _vmaf_is_number() {
        [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
    }

    _vmaf_float_lt() {
        local a="${1:-}" b="${2:-}"
        awk -v a="$a" -v b="$b" 'BEGIN{exit !(a<b)}'
    }

    _vmaf_float_gt() {
        local a="${1:-}" b="${2:-}"
        awk -v a="$a" -v b="$b" 'BEGIN{exit !(a>b)}'
    }

    _vmaf_trunc_name() {
        local s="${1:-}"
        if [[ ${#s} -gt 60 ]]; then
            printf '%s' "${s:0:57}..."
        else
            printf '%s' "$s"
        fi
    }

    _vmaf_maybe_add_worst() {
        local file="${1:-}"
        local score="${2:-}"
        local quality="${3:-NA}"

        _vmaf_is_number "$score" || return 0

        local line
        line="- $(_vmaf_trunc_name "$file") : ${score} (${quality})"

        # Insertion triée (3 pires scores, ordre croissant)
        local i
        for i in 0 1 2; do
            local cur_score=""
            if [[ -n "${worst_lines[$i]:-}" ]]; then
                cur_score=$(printf '%s' "${worst_lines[$i]}" | grep -oE ':[[:space:]]*[0-9]+(\.[0-9]+)?' | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' || true)
            fi

            if [[ -z "${worst_lines[$i]:-}" ]]; then
                worst_lines[$i]="$line"
                return 0
            fi

            if [[ -n "$cur_score" ]] && _vmaf_float_lt "$score" "$cur_score"; then
                # shift down
                worst_lines[2]="${worst_lines[1]:-}"
                worst_lines[1]="${worst_lines[0]:-}"
                worst_lines[$i]="$line"
                return 0
            fi
        done
        return 0
    }
    while IFS='|' read -r file_original final_actual keyframe_pos; do
        ((current++)) || true
        
        local filename
        filename=$(basename "$final_actual")
        # Tronquer le nom pour l'affichage
        local display_name="$filename"
        if [[ ${#display_name} -gt 45 ]]; then
            display_name="${display_name:0:42}..."
        fi
        
        # Vérifier que les fichiers existent toujours
        if [[ ! -f "$file_original" ]] || [[ ! -f "$final_actual" ]]; then
            if [[ "$NO_PROGRESS" != true ]]; then
                printf "  ${YELLOW}⚠${NOCOLOR} ${CYAN}[%d/%d] %-45s${NOCOLOR} : NA (fichier introuvable)\n" "$current" "$vmaf_count" "$display_name" >&2
            fi
            continue
        fi
        
        # Vérifier que le fichier converti n'est pas vide (dryrun crée des fichiers de 0 octets)
        local converted_size
        converted_size=$(get_file_size_bytes "$final_actual")
        if [[ "$converted_size" -eq 0 ]]; then
            if [[ "$NO_PROGRESS" != true ]]; then
                printf "  ${YELLOW}⚠${NOCOLOR} ${CYAN}[%d/%d] %-45s${NOCOLOR} : NA (fichier vide)\n" "$current" "$vmaf_count" "$display_name" >&2
            fi
            continue
        fi

        # Notif Discord (best-effort) : début VMAF par fichier
        if declare -f notify_event &>/dev/null; then
            notify_event vmaf_file_started "$current" "$vmaf_count" "$filename" || true
        fi
        
        # Mesurer le temps d'analyse VMAF
        local vmaf_start_time vmaf_end_time vmaf_duration vmaf_duration_str
        vmaf_start_time=$(date +%s)
        local vmaf_score
        vmaf_score=$(compute_vmaf_score "$file_original" "$final_actual" "$filename" "$current" "$vmaf_count" "$keyframe_pos")
        vmaf_end_time=$(date +%s)
        vmaf_duration=$((vmaf_end_time - vmaf_start_time))
        # Format hh:mm:ss
        printf -v vmaf_duration_str '%02d:%02d:%02d' $((vmaf_duration/3600)) $((vmaf_duration%3600/60)) $((vmaf_duration%60))
        
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

        # Notif Discord (best-effort) : résultat VMAF par fichier
        if declare -f notify_event &>/dev/null; then
            notify_event vmaf_file_completed "$current" "$vmaf_count" "$filename" "$vmaf_score" "${vmaf_quality:-NA}" || true
        fi

        # Stats (pour notif Discord)
        if [[ "$vmaf_score" == "NA" ]]; then
            na_count=$((na_count + 1))
        elif _vmaf_is_number "$vmaf_score"; then
            ok_count=$((ok_count + 1))
            sum_scores=$(awk -v s="$sum_scores" -v v="$vmaf_score" 'BEGIN{printf "%.6f", s+v}')

            if [[ -z "$min_score" ]]; then
                min_score="$vmaf_score"
                max_score="$vmaf_score"
            else
                _vmaf_float_lt "$vmaf_score" "$min_score" && min_score="$vmaf_score"
                _vmaf_float_gt "$vmaf_score" "$max_score" && max_score="$vmaf_score"
            fi

            [[ "$vmaf_quality" == "DEGRADE" ]] && degraded_count=$((degraded_count + 1))
            _vmaf_maybe_add_worst "$filename" "$vmaf_score" "${vmaf_quality:-NA}"
        fi
        
        # Logger le score VMAF
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | VMAF | $file_original → $final_actual | score:${vmaf_score} | quality:${vmaf_quality:-NA}" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        
        if [[ "$NO_PROGRESS" != true ]]; then
            local status_icon="${GREEN}✓${NOCOLOR}"
            if [[ "$vmaf_score" == "NA" ]]; then
                status_icon="${YELLOW}?${NOCOLOR}"
            elif [[ "$vmaf_quality" == "DEGRADE" ]]; then
                status_icon="${RED}✗${NOCOLOR}"
            fi
            # Tronquer le nom de fichier à 45 caractères pour aligner
            local display_name_final="$filename"
            if [[ ${#display_name_final} -gt 45 ]]; then
                display_name_final="${display_name_final:0:42}..."
            fi
            # Compteur et nom de fichier en CYAN, ajout du temps d'analyse à la fin
            printf "\r  %s ${CYAN}[%d/%d] %-45s${NOCOLOR} : %s (%s) | %s\n" "$status_icon" "$current" "$vmaf_count" "$display_name_final" "$vmaf_score" "${vmaf_quality:-NA}" "$vmaf_duration_str" >&2
        fi
        
    done < "$VMAF_QUEUE_FILE"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_vmaf_complete
    fi

    # Notif Discord (best-effort) : fin VMAF + scores
    if declare -f notify_event &>/dev/null; then
        local _vmaf_total_end_ts _vmaf_total_secs _vmaf_total_fmt
        _vmaf_total_end_ts=$(date +%s 2>/dev/null || echo "")
        _vmaf_total_secs=0
        if [[ -n "${_vmaf_total_start_ts:-}" ]] && [[ -n "${_vmaf_total_end_ts:-}" ]] && [[ "${_vmaf_total_start_ts}" =~ ^[0-9]+$ ]] && [[ "${_vmaf_total_end_ts}" =~ ^[0-9]+$ ]]; then
            _vmaf_total_secs=$((_vmaf_total_end_ts - _vmaf_total_start_ts))
        fi
        printf -v _vmaf_total_fmt '%02d:%02d:%02d' $((_vmaf_total_secs/3600)) $((_vmaf_total_secs%3600/60)) $((_vmaf_total_secs%60))

        local avg_score="NA"
        if [[ "$ok_count" -gt 0 ]]; then
            avg_score=$(awk -v s="$sum_scores" -v n="$ok_count" 'BEGIN{printf "%.2f", s/n}')
        fi

        local min_out="${min_score:-NA}"
        local max_out="${max_score:-NA}"
        if _vmaf_is_number "$min_out"; then min_out=$(awk -v v="$min_out" 'BEGIN{printf "%.2f", v}'); fi
        if _vmaf_is_number "$max_out"; then max_out=$(awk -v v="$max_out" 'BEGIN{printf "%.2f", v}'); fi

        # Nettoyer les lignes worst (retirer les vides)
        local -a worst_nonempty=()
        local w
        for w in "${worst_lines[@]:-}"; do
            [[ -n "$w" ]] && worst_nonempty+=("$w")
        done

        notify_event vmaf_completed "$vmaf_count" "$ok_count" "$na_count" "$avg_score" "$min_out" "$max_out" "$degraded_count" "${_vmaf_total_fmt}" "${worst_nonempty[@]}" || true
    fi
    
    # Nettoyer le fichier de queue
    rm -f "$VMAF_QUEUE_FILE" 2>/dev/null || true
}
