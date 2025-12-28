#!/bin/bash
###########################################################
# LOGIQUE DE SKIP ET CONVERSION
###########################################################

# Modes de conversion possibles (retournés par _determine_conversion_mode)
# - "skip"             : fichier ignoré (vidéo conforme, audio OK ou mode copy)
# - "video_passthrough": vidéo copiée, seul l'audio est converti
# - "full"             : conversion complète (vidéo + audio)
CONVERSION_ACTION=""

# Détermine le mode de conversion à appliquer pour un fichier.
# Usage: _determine_conversion_mode <codec> <bitrate> <filename> <file_original>
# Définit CONVERSION_ACTION et retourne 0 si une action est nécessaire, 1 si skip total
_determine_conversion_mode() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    
    CONVERSION_ACTION=""
    
    # --- Validation fichier vidéo ---
    if [[ -z "$codec" ]]; then
        CONVERSION_ACTION="skip"
        return 1
    fi
    
    # Calcul dynamique du seuil : MAXRATE_KBPS * (1 + tolérance)
    local base_threshold_bits=$((MAXRATE_KBPS * 1000))
    local tolerance_bits=$((MAXRATE_KBPS * SKIP_TOLERANCE_PERCENT * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))
    
    # Détecter si le fichier est déjà encodé dans un codec "meilleur ou égal" au codec cible
    local target_codec="${VIDEO_CODEC:-hevc}"
    local is_better_or_equal_codec=false
    
    if declare -f is_codec_better_or_equal &>/dev/null; then
        if is_codec_better_or_equal "$codec" "$target_codec"; then
            is_better_or_equal_codec=true
        fi
    else
        case "$codec" in
            av1) is_better_or_equal_codec=true ;;
            hevc|h265) [[ "$target_codec" == "hevc" ]] && is_better_or_equal_codec=true ;;
        esac
    fi
    
    # Vidéo conforme (bon codec + bitrate optimisé) ?
    local video_is_ok=false
    if [[ "$is_better_or_equal_codec" == true ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            video_is_ok=true
        fi
    fi
    
    if [[ "$video_is_ok" == true ]]; then
        # Vidéo OK - vérifier si l'audio peut être optimisé
        if declare -f _should_convert_audio &>/dev/null && _should_convert_audio "$file_original"; then
            # Audio à optimiser → mode passthrough vidéo
            CONVERSION_ACTION="video_passthrough"
            return 0
        else
            # Audio OK aussi → skip complet
            CONVERSION_ACTION="skip"
            return 1
        fi
    fi
    
    # Vidéo non conforme → conversion complète
    CONVERSION_ACTION="full"
    return 0
}

should_skip_conversion() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    
    # Déterminer le mode de conversion
    _determine_conversion_mode "$codec" "$bitrate" "$filename" "$file_original"
    local result=$?
    
    # Affichage et logging selon le mode
    case "$CONVERSION_ACTION" in
        "skip")
            if [[ -z "$codec" ]]; then
                echo -e "${BLUE}⏭️  SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}" >&2
                if [[ -n "$LOG_SKIPPED" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
                fi
            else
                local codec_display="${codec^^}"
                [[ "$codec" == "hevc" || "$codec" == "h265" ]] && codec_display="x265"
                echo -e "${BLUE}⏭️  SKIPPED (Déjà ${codec_display} & bitrate optimisé) : $filename${NOCOLOR}" >&2
                if [[ -n "$LOG_SKIPPED" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà ${codec_display} et bitrate optimisé) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
                fi
            fi
            return 0
            ;;
        "video_passthrough")
            # Log discret - comportement transparent pour l'utilisateur
            if [[ -n "$LOG_PROGRESS" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | VIDEO_PASSTHROUGH | Audio à optimiser | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
            fi
            return 1  # Ne pas skip - traiter le fichier
            ;;
        "full")
            # Détecter si le fichier est dans un codec meilleur/égal mais avec bitrate trop élevé
            local target_codec="${VIDEO_CODEC:-hevc}"
            local is_better_or_equal=false
            if declare -f is_codec_better_or_equal &>/dev/null; then
                is_codec_better_or_equal "$codec" "$target_codec" && is_better_or_equal=true
            else
                case "$codec" in
                    av1) is_better_or_equal=true ;;
                    hevc|h265) [[ "$target_codec" == "hevc" ]] && is_better_or_equal=true ;;
                esac
            fi
            
            if [[ "$is_better_or_equal" == true && -n "$LOG_PROGRESS" ]]; then
                local codec_display="${codec^^}"
                [[ "$codec" == "hevc" || "$codec" == "h265" ]] && codec_display="X265"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage ${codec_display}) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
            fi
            return 1
            ;;
    esac
    
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
    # Éviter le ./ quand le fichier est à la racine de SOURCE
    [[ "$relative_dir" == "." ]] && relative_dir=""
    local final_dir="$output_dir"
    [[ -n "$relative_dir" ]] && final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"

    # Suffixe effectif (par fichier) : inclut bitrate adapté + résolution + codec audio effectif.
    # Fallback : si les fonctions ne sont pas chargées (tests/unitaires), on garde SUFFIX_STRING.
    local effective_suffix="$SUFFIX_STRING"
    if [[ -n "$SUFFIX_STRING" ]] && declare -f get_video_stream_props &>/dev/null && declare -f _build_effective_suffix_for_dims &>/dev/null; then
        local stream_props
        stream_props=$(get_video_stream_props "$file_original")
        local input_width input_height _pix_fmt
        IFS='|' read -r input_width input_height _pix_fmt <<< "$stream_props"
        # Passer le fichier original pour déterminer le codec audio effectif (smart codec)
        effective_suffix=$(_build_effective_suffix_for_dims "$input_width" "$input_height" "$file_original")
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

_check_output_exists() {
    local file_original="$1"
    local filename="$2"
    local final_output="$3"
    
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        echo -e "${BLUE}⏭️  SKIPPED (Fichier de sortie déjà existant) : $filename${NOCOLOR}" >&2
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
        print_transfer_item "$filename"
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
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_transfer_item_end
    fi

    return 0
}

###########################################################
# EXÉCUTION DE LA CONVERSION FFMPEG
###########################################################

# NOTE: _execute_conversion a été déplacée dans lib/transcode_video.sh

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
    
    local size_before_mb=$(du -m "$file_original" | awk '{print $1}')
    
    _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp" || return 1
    
    # Choix du mode de conversion selon CONVERSION_ACTION (défini par _analyze_video → should_skip_conversion)
    local conversion_success=false
    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        # Mode passthrough : vidéo copiée, seul l'audio est converti
        if _execute_video_passthrough "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
            conversion_success=true
        fi
    else
        # Mode standard : conversion complète (vidéo + audio)
        if _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
            conversion_success=true
        fi
    fi
    
    if [[ "$conversion_success" == true ]]; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$size_before_mb"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi
    
    # Incrémenter le compteur de fichiers traités (signal pour le FIFO writer)
    increment_processed_count || true
}
