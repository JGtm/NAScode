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
    local format_output
    
    # Récupération des métadonnées du stream vidéo
    metadata_output=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null)
    
    # Récupération séparée des métadonnées du format (container)
    # Note: -select_streams empêche l'accès aux infos format, donc requête séparée
    format_output=$(ffprobe -v error \
        -show_entries format=bit_rate,duration \
        "$file" 2>/dev/null)
    
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

    # Préparer les paramètres vidéo
    local ff_bitrate="${TARGET_BITRATE_FFMPEG:-${TARGET_BITRATE_KBPS}k}"
    local ff_maxrate="${MAXRATE_FFMPEG:-${MAXRATE_KBPS}k}"
    local ff_bufsize="${BUFSIZE_FFMPEG:-${BUFSIZE_KBPS}k}"
    local x265_vbv="${X265_VBV_PARAMS:-vbv-maxrate=${MAXRATE_KBPS}:vbv-bufsize=${BUFSIZE_KBPS}}"

    # TODO: Réactiver la conversion audio Opus quand VLC supportera mieux Opus surround dans MKV
    # # Analyser l'audio et déterminer les paramètres de conversion
    # local audio_info
    # audio_info=$(get_audio_metadata "$tmp_input")
    # local audio_codec audio_bitrate_kbps audio_should_convert
    # IFS='|' read -r audio_codec audio_bitrate_kbps audio_should_convert <<< "$audio_info"
    # 
    # # Construire les paramètres audio pour FFmpeg
    # local audio_params=""
    # if [[ "$audio_should_convert" -eq 1 ]]; then
    #     # Conversion vers Opus 128 kbps (meilleure qualité/taille que AAC)
    #     # -af "aformat=channel_layouts=..." normalise les layouts audio non-standard
    #     # (ex: 5.1(side) → 5.1) pour éviter l'erreur "Invalid channel layout"
    #     # Ordre de préférence : 7.1 > 5.1 > stereo > mono
    #     audio_params="-c:a libopus -b:a ${AUDIO_OPUS_TARGET_KBPS}k -af aformat=channel_layouts=7.1|5.1|stereo|mono"
    # else
    #     # Copier l'audio tel quel (déjà optimisé ou Opus)
    #     audio_params="-c:a copy"
    # fi
    
    # Copier l'audio tel quel (en attendant meilleur support VLC pour Opus)
    local audio_params="-c:a copy"

    # Mode sample : trouver le keyframe exact pour garantir la synchronisation avec VMAF
    local sample_seek_params=""
    local sample_duration_params=""
    local effective_duration="$duration_secs"
    
    if [[ "$SAMPLE_MODE" == true ]]; then
        # Convertir duration_secs en entier (Bash ne supporte pas l'arithmétique flottante)
        local duration_int=${duration_secs%.*}
        local margin_start="${SAMPLE_MARGIN_START:-180}"
        local margin_end="${SAMPLE_MARGIN_END:-120}"
        local sample_len="${SAMPLE_DURATION:-30}"
        local available_range=$((duration_int - margin_start - margin_end - sample_len))
        
        local target_pos
        if [[ "$available_range" -gt 0 ]]; then
            # Position aléatoire dans la plage disponible
            local random_offset=$((RANDOM % available_range))
            target_pos=$((margin_start + random_offset))
        else
            # Vidéo trop courte, prendre le milieu
            target_pos=$((duration_int / 3))
        fi
        
        # Trouver le keyframe le plus proche de target_pos (en utilisant ffprobe)
        # On cherche le keyframe >= target_pos pour être sûr d'avoir assez de contenu après
        local keyframe_pos
        keyframe_pos=$(ffprobe -v error -select_streams v:0 -skip_frame nokey \
            -show_entries packet=pts_time -of csv=p=0 \
            -read_intervals "${target_pos}%+30" "$tmp_input" 2>/dev/null | head -1)
        
        # Si pas de keyframe trouvé, utiliser la position cible
        if [[ -z "$keyframe_pos" ]] || [[ ! "$keyframe_pos" =~ ^[0-9.]+$ ]]; then
            keyframe_pos="$target_pos"
        fi
        
        # Convertir en entier pour l'affichage et le stockage
        local keyframe_int=${keyframe_pos%.*}
        
        # Utiliser la position exacte du keyframe
        sample_seek_params="-ss $keyframe_pos"
        sample_duration_params="-t $sample_len"
        effective_duration="$sample_len"
        
        # Stocker la position EXACTE du keyframe pour VMAF (format décimal)
        SAMPLE_KEYFRAME_POS="$keyframe_pos"
        
        # Formater la position en HH:MM:SS pour l'affichage
        local seek_h=$((keyframe_int / 3600))
        local seek_m=$(((keyframe_int % 3600) / 60))
        local seek_s=$((keyframe_int % 60))
        local seek_formatted=$(printf "%02d:%02d:%02d" "$seek_h" "$seek_m" "$seek_s")
        
        if [[ "$available_range" -gt 0 ]]; then
            echo -e "${CYAN}  🎯 Mode échantillon : segment de ${sample_len}s à partir de ${seek_formatted}${NOCOLOR}"
        else
            echo -e "${YELLOW}  ⚠️ Vidéo courte : segment de ${sample_len}s à partir de ${seek_formatted}${NOCOLOR}"
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
    # Construire les paramètres pass 1 avec option fast si activée
    local x265_params_pass1="pass=1:${x265_base_params}"
    if [[ "${X265_PASS1_FAST:-false}" == true ]]; then
        # no-slow-firstpass : analyse rapide, gain ~15% en temps, impact qualité négligeable
        x265_params_pass1="${x265_params_pass1}:no-slow-firstpass=1"
    fi
    
    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        $sample_seek_params \
        -hwaccel $HWACCEL \
        -i "$tmp_input" $sample_duration_params -pix_fmt yuv420p \
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
        -i "$tmp_input" $sample_duration_params -pix_fmt yuv420p \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$ff_bitrate" -x265-params "$x265_params_pass2" \
        -maxrate "$ff_maxrate" -bufsize "$ff_bufsize" \
        $audio_params \
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
