#!/bin/bash
###########################################################
# CONVERSION VIDÉO
# Logique de conversion FFmpeg et fonctions associées
###########################################################

###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
###########################################################

get_video_metadata() {
    local file="$1"
    local metadata_output
    
    # Récupération de toutes les métadonnées en une seule commande pour optimisation
    metadata_output=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS:format=bit_rate,duration \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null)
    
    # Parsing des résultats
    local bitrate_stream=$(echo "$metadata_output" | grep '^bit_rate=' | head -1 | cut -d'=' -f2)
    local bitrate_bps=$(echo "$metadata_output" | grep '^TAG:BPS=' | cut -d'=' -f2)
    local bitrate_container=$(echo "$metadata_output" | grep '^\[FORMAT\]' -A 10 | grep '^bit_rate=' | cut -d'=' -f2)
    local codec=$(echo "$metadata_output" | grep '^codec_name=' | cut -d'=' -f2)
    local duration=$(echo "$metadata_output" | grep '^duration=' | cut -d'=' -f2)
    
    # Nettoyage des valeurs
    bitrate_stream=$(clean_number "$bitrate_stream")
    bitrate_bps=$(clean_number "$bitrate_bps")
    bitrate_container=$(clean_number "$bitrate_container")
    
    # Détermination du bitrate prioritaire
    local bitrate=0
    if [[ -n "$bitrate_stream" ]]; then 
        bitrate="$bitrate_stream"
    elif [[ -n "$bitrate_bps" ]]; then 
        bitrate="$bitrate_bps"
    elif [[ -n "$bitrate_container" ]]; then 
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
# LOGIQUE DE SKIP
###########################################################

should_skip_conversion() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    
    # --- Validation fichier vidéo ---
    if [[ -z "$codec" ]]; then
        echo -e "${BLUE}⏭️  SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
        return 0
    fi
    
    # Calcul de la tolérance en bits
    local base_threshold_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * SKIP_TOLERANCE_PERCENT * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))
    
    # Validation du format x265 et du bitrate
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            echo -e "${BLUE}⏭️  SKIPPED (Déjà x265 & bitrate optimisé) : $filename${NOCOLOR}" >&2
            if [[ -n "$LOG_SKIPPED" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà x265 et bitrate optimisé) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
            fi
            return 0
        fi
        if [[ -n "$LOG_PROGRESS" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage X265) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
        fi
    fi
    
    return 1
}

###########################################################
# SOUS-FONCTIONS DE PRE-CONVERSION
###########################################################

_prepare_file_paths() {
    local file_original="$1"
    local output_dir="$2"
    
    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        return 1
    fi

    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")
    local final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"
    
    local effective_suffix="$SUFFIX_STRING"
    if [[ "$DRYRUN" == true ]]; then
        effective_suffix="${effective_suffix}${DRYRUN_SUFFIX}"
    fi

    local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
    
    echo "$filename|$final_dir|$base_name|$effective_suffix|$final_output"
}

_check_output_exists() {
    local file_original="$1"
    local filename="$2"
    local final_output="$3"
    
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        echo -e "${BLUE}⏭️  SKIPPED (Fichier de sortie existe déjà) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
        # Alimenter la queue avec le prochain candidat si limite active
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue || true
        fi
        return 0
    fi
    return 1
}

_handle_dryrun_mode() {
    local final_dir="$1"
    local final_output="$2"
    
    if [[ "$DRYRUN" == true ]]; then
        mkdir -p "$final_dir"
        touch "$final_output"
        return 0
    fi
    return 1
}

_get_temp_filename() {
    local file_original="$1"
    local suffix="$2"
    local md5p
    md5p=$(compute_md5_prefix "$file_original")
    echo "$TMP_DIR/tmp_${md5p}_${RANDOM}${suffix}"
}

_setup_temp_files_and_logs() {
    local filename="$1"
    local file_original="$2"
    local final_dir="$3"
    
    mkdir -p "$final_dir" 2>/dev/null || true
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "▶️  Démarrage du fichier : $filename"
    fi
    if [[ -n "$LOG_PROGRESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
    fi
}

_check_disk_space() {
    local file_original="$1"
    
    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}' 2>/dev/null) || return 0
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERREUR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        return 1
    fi
    return 0
}

_analyze_video() {
    local file_original="$1"
    local filename="$2"
    
    local metadata
    metadata=$(get_video_metadata "$file_original")
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata"
    
    if should_skip_conversion "$codec" "$bitrate" "$filename" "$file_original"; then
        # Alimenter la queue avec le prochain candidat si limite active
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue || true
        fi
        return 1
    fi
    
    echo "$bitrate|$codec|$duration_secs"
    return 0
}

_copy_to_temp_storage() {
    local file_original="$1"
    local filename="$2"
    local tmp_input="$3"
    local ffmpeg_log_temp="$4"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}→ Transfert de [$filename] vers dossier temporaire...${NOCOLOR}"
    else
        echo -e "${CYAN}→ $filename${NOCOLOR}"
    fi

    if ! custom_pv "$file_original" "$tmp_input" "$CYAN"; then
        echo -e "${RED}❌ ERREUR Impossible de déplacer (custom_pv) : $file_original${NOCOLOR}"
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR custom_pv copy failed | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null
        return 1
    fi

    return 0
}

###########################################################
# EXÉCUTION DE LA CONVERSION FFMPEG
###########################################################

_execute_conversion() {
    local tmp_input="$1"
    local tmp_output="$2"
    local ffmpeg_log_temp="$3"
    local duration_secs="$4"
    local base_name="$5"

    # Options de l'encodage (principales) :
    #  -g 600               : taille GOP (nombre d'images entre I-frames)
    #  -keyint_min 600      : intervalle minimum entre keyframes (force des I-frames régulières)
    #  -c:v libx265         : encodeur logiciel x265 (HEVC)
    #  -preset slow         : préréglage qualité/temps (lent = meilleure compression)
    #  -tune fastdecode     : optimiser l'encodeur pour un décodage plus rapide
    #  -pix_fmt yuv420p10le : format de pixels YUV 4:2:0 en 10 bits

    # timestamp de départ portable
    START_TS="$(date +%s)"
    START_TS_TOTAL="$(date +%s)"

    # Two-pass encoding : analyse puis encodage
    # Pass 1 : analyse rapide pour générer les statistiques
    # Pass 2 : encodage final avec répartition optimale du bitrate

    # Préparer les paramètres
    local ff_bitrate="${TARGET_BITRATE_FFMPEG:-${TARGET_BITRATE_KBPS}k}"
    local ff_maxrate="${MAXRATE_FFMPEG:-${MAXRATE_KBPS}k}"
    local ff_bufsize="${BUFSIZE_FFMPEG:-${BUFSIZE_KBPS}k}"
    local x265_vbv="${X265_VBV_PARAMS:-vbv-maxrate=${MAXRATE_KBPS}:vbv-bufsize=${BUFSIZE_KBPS}}"

    # Mode sample : paramètres -ss (seek) et -t (durée) pour encoder un segment
    local sample_seek_params=""
    local sample_duration_params=""
    local effective_duration="$duration_secs"
    
    if [[ "$SAMPLE_MODE" == true ]]; then
        local margin_start="${SAMPLE_MARGIN_START:-180}"
        local margin_end="${SAMPLE_MARGIN_END:-120}"
        local sample_len="${SAMPLE_DURATION:-30}"
        local available_range=$((duration_secs - margin_start - margin_end - sample_len))
        
        if [[ "$available_range" -gt 0 ]]; then
            # Position aléatoire dans la plage disponible
            local random_offset=$((RANDOM % available_range))
            local seek_pos=$((margin_start + random_offset))
            sample_seek_params="-ss $seek_pos"
            sample_duration_params="-t $sample_len"
            effective_duration="$sample_len"
            SAMPLE_SEEK_POS="$seek_pos"  # Stocker pour VMAF
            echo -e "${CYAN}  🎯 Mode sample : segment de ${sample_len}s à partir de ${seek_pos}s${NOCOLOR}"
        else
            # Vidéo trop courte, prendre le milieu
            local seek_pos=$((duration_secs / 3))
            sample_seek_params="-ss $seek_pos"
            sample_duration_params="-t $sample_len"
            effective_duration="$sample_len"
            SAMPLE_SEEK_POS="$seek_pos"  # Stocker pour VMAF
            echo -e "${YELLOW}  ⚠️ Vidéo courte : segment de ${sample_len}s à partir de ${seek_pos}s${NOCOLOR}"
        fi
    fi

    # Script AWK adapté selon la disponibilité de systime() (gawk vs awk BSD)
    local awk_time_func
    if [[ "$HAS_GAWK" -eq 1 ]]; then
        awk_time_func='function get_time() { return systime() }'
    else
        awk_time_func='function get_time() { cmd="date +%s"; cmd | getline t; close(cmd); return t }'
    fi

    # Acquérir un slot pour affichage de progression en mode parallèle
    local progress_slot=0
    local is_parallel=0
    if [[ "${PARALLEL_JOBS:-1}" -gt 1 ]]; then
        is_parallel=1
        progress_slot=$(acquire_progress_slot)
    fi

    # ==================== PASS 1 : ANALYSE ====================
    # Utiliser -passlogfile de ffmpeg (gère les chemins Windows correctement)
    local x265_base_params="${x265_vbv}"
    # Ajouter les paramètres x265 spécifiques au mode (ex: no-amp:no-rect pour séries)
    if [[ -n "${X265_EXTRA_PARAMS:-}" ]]; then
        x265_base_params="${x265_base_params}:${X265_EXTRA_PARAMS}"
    fi
    local x265_params_pass1="pass=1:${x265_base_params}"
    
    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        $sample_seek_params \
        -hwaccel $HWACCEL \
        -i "$tmp_input" $sample_duration_params -pix_fmt yuv420p10le \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$ff_bitrate" -x265-params "$x265_params_pass1" \
        -maxrate "$ff_maxrate" -bufsize "$ff_bufsize" \
        -an \
        -f null /dev/null \
        -progress pipe:1 -nostats 2> "${ffmpeg_log_temp}.pass1" | \
    awk -v DURATION="$effective_duration" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" \
        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="🔍" -v END_MSG="Analyse OK" \
        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

    # Vérifier le succès du pass 1
    local pass1_rc=${PIPESTATUS[0]:-0}
    if [[ "$pass1_rc" -ne 0 ]]; then
        echo -e "${RED}❌ Erreur lors de l'analyse (pass 1)${NOCOLOR}" >&2
        if [[ -f "${ffmpeg_log_temp}.pass1" ]]; then
            tail -n 40 "${ffmpeg_log_temp}.pass1" >&2 || true
        fi
        if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
            release_progress_slot "$progress_slot"
        fi
        return 1
    fi

    # ==================== PASS 2 : ENCODAGE ====================
    START_TS="$(date +%s)"
    local x265_params_pass2="pass=2:${x265_base_params}"

    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        $sample_seek_params \
        -hwaccel $HWACCEL \
        -i "$tmp_input" $sample_duration_params -pix_fmt yuv420p10le \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$ff_bitrate" -x265-params "$x265_params_pass2" \
        -maxrate "$ff_maxrate" -bufsize "$ff_bufsize" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
    awk -v DURATION="$effective_duration" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" \
        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="🎬" -v END_MSG="Terminé ✅" \
        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

    # Nettoyer les fichiers de stats
    rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true


    # Libérer le slot de progression
    if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
        release_progress_slot "$progress_slot"
    fi

    # Récupère les codes de sortie du pipeline (0 = succès).
    local ffmpeg_rc=0
    local awk_rc=0
    if [[ ${#PIPESTATUS[@]} -ge 1 ]]; then
        ffmpeg_rc=${PIPESTATUS[0]:-0}
        awk_rc=${PIPESTATUS[1]:-0}
    fi

    if [[ "$ffmpeg_rc" -eq 0 && "$awk_rc" -eq 0 ]]; then
        return 0
    else
        if [[ -f "$ffmpeg_log_temp" ]]; then
            echo "--- Dernières lignes du log ffmpeg ($ffmpeg_log_temp) ---" >&2
            tail -n 80 "$ffmpeg_log_temp" >&2 || true
            echo "--- Fin du log ffmpeg ---" >&2
        else
            echo "(Aucun fichier de log ffmpeg trouvé: $ffmpeg_log_temp)" >&2
        fi
        return 1
    fi
}

###########################################################
# FONCTION DE CONVERSION PRINCIPALE
###########################################################

convert_file() {
    set -o pipefail

    local file_original="$1"
    local output_dir="$2"
    
    local path_info
    path_info=$(_prepare_file_paths "$file_original" "$output_dir") || return 1
    
    IFS='|' read -r filename final_dir base_name effective_suffix final_output <<< "$path_info"
    
    if _check_output_exists "$file_original" "$filename" "$final_output"; then
        increment_processed_count || true
        return 0
    fi
    
    if _handle_dryrun_mode "$final_dir" "$final_output"; then
        increment_processed_count || true
        return 0
    fi
    
    local tmp_input=$(_get_temp_filename "$file_original" ".in")
    local tmp_output=$(_get_temp_filename "$file_original" ".out.mkv")
    local ffmpeg_log_temp=$(_get_temp_filename "$file_original" "_err.log")
    
    _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    
    _check_disk_space "$file_original" || return 1
    
    local metadata_info
    if ! metadata_info=$(_analyze_video "$file_original" "$filename"); then
        # Analyse a indiqué qu'on doit skip ce fichier
        increment_processed_count || true
        return 0
    fi
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata_info"
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')
    
    _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp" || return 1
    
    if _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$sizeBeforeMB"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi
    
    # Incrémenter le compteur de fichiers traités (signal pour le FIFO writer)
    increment_processed_count || true
}
