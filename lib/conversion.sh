#!/bin/bash
###########################################################
# CONVERSION VIDÉO
# Logique de conversion FFmpeg et fonctions associées
###########################################################

###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
###########################################################

# NOTE: Les fonctions ffprobe ont été déplacées dans lib/media_probe.sh
# - get_video_metadata
# - get_video_stream_props

###########################################################
# ANALYSE DES PROPRIÉTÉS VIDÉO (RÉSOLUTION / PIX_FMT)
###########################################################

# NOTE: La logique d'encodage (10-bit/downscale + _execute_conversion) a été déplacée dans lib/transcode_video.sh

###########################################################
# ANALYSE DES MÉTADONNÉES AUDIO
# TODO: Réactiver quand VLC supportera mieux Opus surround dans MKV
###########################################################

# # Activer la conversion audio vers Opus
# AUDIO_OPUS_ENABLED=true
# # Bitrate cible pour l'audio Opus (kbps)
# readonly AUDIO_OPUS_TARGET_KBPS=128
# # Seuil minimum pour considérer la conversion audio avantageuse (kbps)
# # On ne convertit que si le bitrate source est > seuil (évite de ré-encoder du déjà compressé)
# readonly AUDIO_CONVERSION_THRESHOLD_KBPS=160
#
# # Analyse l'audio d'un fichier et détermine si la conversion Opus est avantageuse
# # Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert to opus)
# get_audio_metadata() {
#     local file="$1"
#     
#     # Récupérer les infos audio du premier flux audio
#     local audio_info
#     audio_info=$(ffprobe -v error \
#         -select_streams a:0 \
#         -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
#         -of default=noprint_wrappers=1 \
#         "$file" 2>/dev/null)
#     
#     local audio_codec=$(echo "$audio_info" | grep '^codec_name=' | cut -d'=' -f2)
#     local audio_bitrate=$(echo "$audio_info" | grep '^bit_rate=' | cut -d'=' -f2)
#     local audio_bitrate_tag=$(echo "$audio_info" | grep '^TAG:BPS=' | cut -d'=' -f2)
#     
#     # Utiliser le tag BPS si bitrate direct non disponible
#     if [[ -z "$audio_bitrate" || "$audio_bitrate" == "N/A" ]]; then
#         audio_bitrate="$audio_bitrate_tag"
#     fi
#     
#     # Convertir en kbps
#     audio_bitrate=$(clean_number "$audio_bitrate")
#     local audio_bitrate_kbps=0
#     if [[ -n "$audio_bitrate" && "$audio_bitrate" =~ ^[0-9]+$ ]]; then
#         audio_bitrate_kbps=$((audio_bitrate / 1000))
#     fi
#     
#     # Déterminer si la conversion est avantageuse
#     local should_convert=0
#     
#     # Ne pas convertir si déjà en Opus
#     if [[ "$audio_codec" == "opus" ]]; then
#         should_convert=0
#     # Convertir si le bitrate source est supérieur au seuil
#     elif [[ "$audio_bitrate_kbps" -gt "$AUDIO_CONVERSION_THRESHOLD_KBPS" ]]; then
#         should_convert=1
#     fi
#     
#     echo "${audio_codec}|${audio_bitrate_kbps}|${should_convert}"
# }

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
    # Éviter le ./ quand le fichier est à la racine de SOURCE
    [[ "$relative_dir" == "." ]] && relative_dir=""
    local final_dir="$output_dir"
    [[ -n "$relative_dir" ]] && final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"
    
    local effective_suffix="$SUFFIX_STRING"
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
    
    # Tronquer le nom de fichier à 30 caractères pour uniformité
    local display_name="$filename"
    if [[ ${#display_name} -gt 30 ]]; then
        display_name="${display_name:0:27}..."
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}→ Téléchargement de $display_name${NOCOLOR}"
    else
        echo -e "${CYAN}→ $display_name${NOCOLOR}"
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
    
    if _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$size_before_mb"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi
    
    # Incrémenter le compteur de fichiers traités (signal pour le FIFO writer)
    increment_processed_count || true
}
