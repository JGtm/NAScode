#!/bin/bash
###########################################################
# PRÉPARATION DE LA CONVERSION
# Chemins, fichiers temporaires, espace disque, transfert
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les opérations de préparation peuvent échouer
#    partiellement (comportement géré par le code)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

###########################################################
# PRÉPARATION DES CHEMINS
###########################################################

_prepare_file_paths() {
    local file_original="$1"
    local output_dir="$2"
    local opt_width="${3:-}"
    local opt_height="${4:-}"
    local opt_audio_codec="${5:-}"
    local opt_audio_bitrate="${6:-}"
    local source_video_codec="${7:-}"
    
    local filename_raw
    filename_raw=$(basename "$file_original")
    local filename
    filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        return 1
    fi

    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir
    relative_dir=$(dirname "$relative_path")
    # Éviter le ./ quand le fichier est à la racine de SOURCE
    [[ "$relative_dir" == "." ]] && relative_dir=""
    local final_dir="$output_dir"
    [[ -n "$relative_dir" ]] && final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"

    # Suffixe effectif (par fichier) : inclut bitrate adapté + résolution + codec audio effectif.
    # Fallback : si les fonctions ne sont pas chargées (tests/unitaires), on garde SUFFIX_STRING.
    local effective_suffix="$SUFFIX_STRING"
    
    # Si un suffixe personnalisé est forcé via -S "valeur", on l'utilise tel quel
    if [[ "${SUFFIX_MODE:-ask}" == custom:* ]]; then
        effective_suffix="${SUFFIX_MODE#custom:}"
    elif [[ -n "$SUFFIX_STRING" ]] && declare -f _build_effective_suffix_for_dims &>/dev/null; then
        local input_width="$opt_width"
        local input_height="$opt_height"
        
        # Si pas de dimensions fournies, on probe (fallback)
        if [[ -z "$input_width" || -z "$input_height" ]] && declare -f get_video_stream_props &>/dev/null; then
            local stream_props
            stream_props=$(get_video_stream_props "$file_original")
            local _pix_fmt
            IFS='|' read -r input_width input_height _pix_fmt <<< "$stream_props"
        fi
        
        # Passer le fichier original pour déterminer le codec audio effectif (smart codec)
        # Passer aussi le codec vidéo source pour utiliser le bon suffixe en cas de passthrough
        effective_suffix=$(_build_effective_suffix_for_dims "$input_width" "$input_height" "$file_original" "$opt_audio_codec" "$opt_audio_bitrate" "$source_video_codec")
    fi

    if [[ "$DRYRUN" == true ]]; then
        effective_suffix="${effective_suffix}${DRYRUN_SUFFIX}"
    fi

    local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
    # Normaliser le chemin pour éviter les problèmes de comparaison
    if declare -f normalize_path &>/dev/null; then
        final_output=$(normalize_path "$final_output")
    fi
    
    echo "$filename|$final_dir|$base_name|$effective_suffix|$final_output"
}

###########################################################
# VÉRIFICATIONS PRÉ-CONVERSION
###########################################################

_check_output_exists() {
    local file_original="$1"
    local filename="$2"
    local final_output="$3"
    
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        local counter_prefix
        counter_prefix=$(_get_counter_prefix)
        echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (Fichier de sortie déjà existant) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        fi

        if declare -f notify_event &>/dev/null; then
            notify_event file_skipped "$filename" "Fichier de sortie déjà existant" || true
        fi

        # Alimenter la queue avec le prochain candidat si limite active
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue || true
        fi
        return 0
    fi

    # Anti-boucle : si une sortie "Heavier" existe déjà pour ce fichier, ne pas re-traiter.
    if [[ "$DRYRUN" != true ]] && [[ "${HEAVY_OUTPUT_ENABLED:-true}" == true ]] && declare -f compute_heavy_output_path &>/dev/null; then
        local heavy_output
        heavy_output=$(compute_heavy_output_path "$final_output" "$OUTPUT_DIR" 2>/dev/null || echo "")
        if [[ -n "$heavy_output" ]] && [[ -f "$heavy_output" ]]; then
            local counter_prefix
            counter_prefix=$(_get_counter_prefix)
            echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (Sortie 'Heavier' déjà existante) : $filename${NOCOLOR}" >&2
            if [[ -n "$LOG_SESSION" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Heavier output exists) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
            fi

            if declare -f notify_event &>/dev/null; then
                notify_event file_skipped "$filename" "Sortie 'Heavier' déjà existante" || true
            fi
            if [[ "$LIMIT_FILES" -gt 0 ]]; then
                update_queue || true
            fi
            return 0
        fi
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

###########################################################
# FICHIERS TEMPORAIRES
###########################################################

_get_temp_filename() {
    local file_original="$1"
    local suffix="$2"
    local md5p
    md5p=$(compute_md5_prefix "$file_original")
    echo "$TMP_DIR/tmp_${md5p}_${RANDOM}${suffix}"
}

_get_temp_workdir() {
    local file_original="$1"
    local md5p
    md5p=$(compute_md5_prefix "$file_original")
    echo "$TMP_DIR/work_${md5p}_${EXECUTION_TIMESTAMP}_$$_${RANDOM}"
}

_setup_temp_files_and_logs() {
    local filename="$1"
    local file_original="$2"
    local final_dir="$3"
    local print_start="${4:-true}"
    local log_start="${5:-true}"
    
    mkdir -p "$final_dir" 2>/dev/null || true
    if [[ "$print_start" == true ]] && [[ "$NO_PROGRESS" != true ]] && [[ "${UI_QUIET:-false}" != true ]]; then
        echo ""
        local counter_str
        counter_str=$(_get_counter_prefix)
        echo -e "${counter_str}▶️ Démarrage du fichier : $filename"
    fi

    # Notification Discord (best-effort) : démarrage fichier
    if declare -f notify_event &>/dev/null; then
        notify_event file_started "$filename" || true
    fi
    if [[ "$log_start" == true ]] && [[ -n "$LOG_PROGRESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
    fi
}

###########################################################
# ESPACE DISQUE
###########################################################

_check_disk_space() {
    local file_original="$1"
    
    local free_space_mb
    free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}' 2>/dev/null) || return 0
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        return 1
    fi
    return 0
}

###########################################################
# TRANSFERT VERS STOCKAGE TEMPORAIRE
###########################################################

_copy_to_temp_storage() {
    local file_original="$1"
    local filename="$2"
    local tmp_input="$3"
    local ffmpeg_log_temp="$4"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_transfer_item "$filename"
    else
        if [[ "${UI_QUIET:-false}" != true ]]; then
            echo -e "${CYAN}→ $filename${NOCOLOR}"
        fi
    fi

    if ! custom_pv "$file_original" "$tmp_input" "$CYAN"; then
        print_error "ERREUR Impossible de déplacer (custom_pv) : $file_original"
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR custom_pv copy failed | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null
        return 1
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_transfer_item_end
    fi

    return 0
}

###########################################################
# ANALYSE VIDÉO (HELPER)
###########################################################

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
