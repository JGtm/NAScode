#!/bin/bash
###########################################################
# ENCODAGE VIDÉO
###########################################################

# Texte affiché dans la barre de progression FFmpeg
# Pour afficher le nom du fichier : PROGRESS_DISPLAY_TEXT="$base_name"
# Pour afficher un texte fixe : PROGRESS_DISPLAY_TEXT="Traitement en cours"
PROGRESS_DISPLAY_TEXT_USE_FILENAME=false  # true = nom du fichier, false = texte fixe
PROGRESS_DISPLAY_TEXT_FIXED="Traitement en cours"

###########################################################
# SOUS-FONCTIONS ENCODAGE (FORMAT / SCALE)
###########################################################

# Note: les fonctions suivantes sont désormais centralisées dans :
# - lib/video_params.sh : _select_output_pix_fmt, _build_downscale_filter_if_needed,
#   _compute_output_height_for_bitrate, _compute_effective_bitrate_kbps_for_height,
#   _build_effective_suffix_for_dims
# - lib/stream_mapping.sh : _build_stream_mapping

###########################################################
# SOUS-FONCTIONS D'ENCODAGE (PASS 1 / PASS 2)
###########################################################

# Prépare les paramètres vidéo adaptés au fichier source (bitrate, filtres, etc.)
# Retourne via variables globales : VIDEO_BITRATE, VIDEO_MAXRATE, VIDEO_BUFSIZE,
#                                   X265_VBV_STRING, VIDEO_FILTER_OPTS, OUTPUT_PIX_FMT
# En mode film-adaptive, utilise les variables ADAPTIVE_TARGET_KBPS, ADAPTIVE_MAXRATE_KBPS,
# ADAPTIVE_BUFSIZE_KBPS si elles sont définies.
_setup_video_encoding_params() {
    local input_file="$1"
    
    # Récupérer les propriétés du flux vidéo source
    local input_props
    input_props=$(get_video_stream_props "$input_file")
    local input_width input_height input_pix_fmt
    IFS='|' read -r input_width input_height input_pix_fmt <<< "$input_props"

    # Pixel format de sortie (10-bit si source 10-bit)
    OUTPUT_PIX_FMT=$(_select_output_pix_fmt "$input_pix_fmt")

    # Filtre de downscale si nécessaire
    local downscale_filter
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")
    
    VIDEO_FILTER_OPTS=""
    if [[ -n "$downscale_filter" ]]; then
        VIDEO_FILTER_OPTS="-vf $downscale_filter"
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${CYAN}  ⬇️  Downscale activé : ${input_width}x${input_height} → max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
        fi
    fi
    
    # Affichage 10-bit si applicable
    if [[ "$NO_PROGRESS" != true ]] && [[ -n "$input_pix_fmt" ]]; then
        if [[ "$OUTPUT_PIX_FMT" == "yuv420p10le" ]]; then
            echo -e "${CYAN}  🎨 Sortie 10-bit activée${NOCOLOR}"
        fi
    fi

    # Calcul du bitrate selon le mode
    local effective_target effective_maxrate effective_bufsize
    
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]] && \
       [[ -n "${ADAPTIVE_TARGET_KBPS:-}" ]] && [[ "${ADAPTIVE_TARGET_KBPS}" =~ ^[0-9]+$ ]]; then
        # Mode film-adaptive : utiliser les paramètres calculés par analyse de complexité
        # (Bitrate déjà affiché par display_complexity_analysis)
        effective_target="${ADAPTIVE_TARGET_KBPS}"
        effective_maxrate="${ADAPTIVE_MAXRATE_KBPS}"
        effective_bufsize="${ADAPTIVE_BUFSIZE_KBPS}"
    else
        # Mode standard : calcul basé sur la résolution de sortie
        local output_height
        output_height=$(_compute_output_height_for_bitrate "$input_width" "$input_height")

        effective_target=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
        effective_maxrate=$(_compute_effective_bitrate_kbps_for_height "${MAXRATE_KBPS}" "$output_height")
        effective_bufsize=$(_compute_effective_bitrate_kbps_for_height "${BUFSIZE_KBPS}" "$output_height")
    fi

    VIDEO_BITRATE="${effective_target}k"
    VIDEO_MAXRATE="${effective_maxrate}k"
    VIDEO_BUFSIZE="${effective_bufsize}k"
    
    # Construire les paramètres de base pour l'encodeur (VBV + mode extras)
    # Pour x265: "vbv-maxrate=X:vbv-bufsize=Y:amp=0:rect=0:..."
    # Pour svtav1: "tune=0:film-grain=8:..."
    local encoder="${VIDEO_ENCODER:-libx265}"
    local vbv_params=""
    
    # Paramètres VBV selon l'encodeur
    case "$encoder" in
        libx265)
            vbv_params="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"
            ;;
        libsvtav1|libaom-av1)
            # Ces encodeurs utilisent -maxrate/-bufsize directement via FFmpeg
            vbv_params=""
            ;;
    esac
    
    # Ajouter les paramètres spécifiques au mode (tuning, optimisations)
    local mode_params
    mode_params=$(get_encoder_mode_params "$encoder" "${CONVERSION_MODE:-serie}")
    
    # Combiner VBV + mode params
    ENCODER_BASE_PARAMS="$vbv_params"
    if [[ -n "$mode_params" ]]; then
        if [[ -n "$ENCODER_BASE_PARAMS" ]]; then
            ENCODER_BASE_PARAMS="${ENCODER_BASE_PARAMS}:${mode_params}"
        else
            ENCODER_BASE_PARAMS="$mode_params"
        fi
    fi

    # SVT-AV1: inclure le keyint dans -svtav1-params (en plus du -g générique)
    # pour coller à la commande type et garder un paramétrage centralisé.
    if [[ "$encoder" == "libsvtav1" ]]; then
        if [[ "$ENCODER_BASE_PARAMS" != *"keyint="* ]]; then
            local mode_keyint
            mode_keyint=$(get_mode_keyint "${CONVERSION_MODE:-serie}")
            if [[ -n "$mode_keyint" ]]; then
                if [[ -n "$ENCODER_BASE_PARAMS" ]]; then
                    ENCODER_BASE_PARAMS="${ENCODER_BASE_PARAMS}:keyint=${mode_keyint}"
                else
                    ENCODER_BASE_PARAMS="keyint=${mode_keyint}"
                fi
            fi
        fi
    fi
    
    # Rétro-compatibilité : garder X265_VBV_STRING pour les tests existants
    X265_VBV_STRING="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"
}

###########################################################
# ENCODAGE UNIFIÉ
###########################################################

# Note: get_encoder_params_flag() est définie dans codec_profiles.sh et exportée.
# Ne pas dupliquer ici.

# Construit les paramètres internes de l'encodeur
# Usage: _build_encoder_params_internal "libx265" "pass1" "vbv-maxrate=2520:vbv-bufsize=3780"
_build_encoder_params_internal() {
    local encoder="${1:-libx265}"
    local mode="$2"           # pass1, pass2, crf
    local base_params="$3"    # VBV params et extras
    
    local full_params=""
    
    case "$encoder" in
        libx265)
            # x265 : paramètres classiques avec pass=N pour two-pass
            case "$mode" in
                "pass1")
                    full_params="pass=1:${base_params}"
                    if [[ "${X265_PASS1_FAST:-false}" == true ]]; then
                        full_params="${full_params}:no-slow-firstpass=1"
                    fi
                    ;;
                "pass2")
                    full_params="pass=2:${base_params}"
                    ;;
                "crf")
                    full_params="${base_params}"
                    ;;
            esac
            ;;
            
        libsvtav1)
            # SVT-AV1 : paramètres via -svtav1-params
            # Le two-pass SVT-AV1 utilise --pass 1/2 dans les params
            case "$mode" in
                "pass1")
                    full_params="pass=1"
                    [[ -n "$base_params" ]] && full_params="${full_params}:${base_params}"
                    ;;
                "pass2")
                    full_params="pass=2"
                    [[ -n "$base_params" ]] && full_params="${full_params}:${base_params}"
                    ;;
                "crf")
                    full_params="${base_params}"
                    ;;
            esac
            ;;
            
        libaom-av1)
            # libaom-av1 : pas de params flag, utilise -pass directement
            # Les paramètres seront gérés différemment
            full_params=""
            ;;
            
        *)
            full_params="${base_params}"
            ;;
    esac
    
    echo "$full_params"
}

# Construit les paramètres spécifiques à l'encodeur pour FFmpeg
# Usage: _build_encoder_ffmpeg_args <encoder> <mode> <base_params>
# Retourne: les arguments FFmpeg pour l'encodeur
_build_encoder_ffmpeg_args() {
    local encoder="${1:-libx265}"
    local mode="$2"           # pass1, pass2, crf
    local base_params="$3"    # VBV params et extras
    
    local encoder_args=""
    local params_flag=""
    local full_params=""
    
    # Obtenir le flag des paramètres encodeur (-x265-params, -svtav1-params, etc.)
    params_flag=$(get_encoder_params_flag "$encoder")
    
    # Construire les paramètres selon l'encodeur et le mode
    case "$encoder" in
        libx265)
            # x265 : paramètres classiques avec pass=N pour two-pass
            case "$mode" in
                "pass1")
                    full_params="pass=1:${base_params}"
                    if [[ "${X265_PASS1_FAST:-false}" == true ]]; then
                        full_params="${full_params}:no-slow-firstpass=1"
                    fi
                    ;;
                "pass2")
                    full_params="pass=2:${base_params}"
                    ;;
                "crf")
                    full_params="${base_params}"
                    ;;
            esac
            encoder_args="-c:v libx265 ${params_flag} \"${full_params}\""
            ;;
            
        libsvtav1)
            # SVT-AV1 : paramètres via -svtav1-params
            # Note: SVT-AV1 utilise -b:v pour le bitrate cible, pas de pass explicite
            # Le two-pass SVT-AV1 se fait via --pass 1/2 dans les params
            case "$mode" in
                "pass1")
                    full_params="pass=1:${base_params}"
                    ;;
                "pass2")
                    full_params="pass=2:${base_params}"
                    ;;
                "crf")
                    full_params="${base_params}"
                    ;;
            esac
            if [[ -n "$full_params" ]]; then
                encoder_args="-c:v libsvtav1 ${params_flag} \"${full_params}\""
            else
                encoder_args="-c:v libsvtav1"
            fi
            ;;
            
        libaom-av1)
            # libaom-av1 : options directes (pas de -params flag standard)
            # Two-pass utilise -pass 1/2 comme option FFmpeg directe
            case "$mode" in
                "pass1")
                    encoder_args="-c:v libaom-av1 -pass 1"
                    ;;
                "pass2")
                    encoder_args="-c:v libaom-av1 -pass 2"
                    ;;
                "crf")
                    encoder_args="-c:v libaom-av1"
                    ;;
            esac
            # libaom utilise cpu-used au lieu de preset
            local aom_cpu_used
            aom_cpu_used=$(convert_preset "$ENCODER_PRESET" "libaom-av1")
            encoder_args="${encoder_args} -cpu-used ${aom_cpu_used}"
            ;;
            
        *)
            # Fallback générique
            encoder_args="-c:v $encoder"
            ;;
    esac
    
    echo "$encoder_args"
}

# Retourne l'option -tune appropriée pour l'encodeur
# Usage: _get_tune_option <encoder>
_get_tune_option() {
    local encoder="${1:-libx265}"
    
    # Seul x265 supporte -tune fastdecode comme option directe
    if [[ "$encoder" == "libx265" ]]; then
        if [[ "${FILM_TUNE_FASTDECODE:-true}" == true ]]; then
            echo "-tune fastdecode"
            return
        fi
    fi
    # Les autres encodeurs gèrent le tune via leurs params internes
    echo ""
}

# Retourne l'option preset appropriée pour l'encodeur
# Usage: _get_preset_option <encoder> <preset>
_get_preset_option() {
    local encoder="${1:-libx265}"
    local preset="${2:-medium}"
    
    case "$encoder" in
        libx265)
            echo "-preset $preset"
            ;;
        libsvtav1)
            # SVT-AV1 utilise -preset avec des valeurs numériques 0-13
            local svt_preset
            if [[ -n "${SVTAV1_PRESET:-}" ]]; then
                svt_preset="$SVTAV1_PRESET"
            elif [[ -n "${SVTAV1_PRESET_DEFAULT:-}" ]]; then
                svt_preset="$SVTAV1_PRESET_DEFAULT"
            else
                svt_preset=$(convert_preset "$preset" "libsvtav1")
            fi
            echo "-preset $svt_preset"
            ;;
        libaom-av1)
            # libaom utilise -cpu-used (géré dans _build_encoder_ffmpeg_args)
            echo ""
            ;;
        *)
            echo "-preset $preset"
            ;;
    esac
}

# Retourne l'option bitrate/CRF appropriée pour l'encodeur et le mode
# Usage: _get_bitrate_option <encoder> <mode>
_get_bitrate_option() {
    local encoder="${1:-libx265}"
    local mode="$2"  # crf ou autre
    
    if [[ "$mode" == "crf" ]]; then
        case "$encoder" in
            libx265)
                echo "-crf $CRF_VALUE"
                ;;
            libsvtav1)
                # SVT-AV1 utilise -crf aussi (0-63, défaut ~35)
                # Valeur configurable (commande type: -crf 32)
                local svt_crf=""
                if [[ -n "${SVTAV1_CRF:-}" ]]; then
                    svt_crf="$SVTAV1_CRF"
                elif [[ -n "${SVTAV1_CRF_DEFAULT:-}" ]]; then
                    svt_crf="$SVTAV1_CRF_DEFAULT"
                else
                    # Mapping approximatif : CRF x265 21 ≈ CRF SVT-AV1 30
                    svt_crf=$(( CRF_VALUE + 9 ))
                fi
                [[ $svt_crf -gt 63 ]] && svt_crf=63
                echo "-crf $svt_crf"
                ;;
            libaom-av1)
                # libaom utilise -crf aussi (0-63)
                local aom_crf=$(( CRF_VALUE + 9 ))
                [[ $aom_crf -gt 63 ]] && aom_crf=63
                echo "-crf $aom_crf"
                ;;
            *)
                echo "-crf $CRF_VALUE"
                ;;
        esac
    else
        echo "-b:v $VIDEO_BITRATE"
    fi
}

# Exécute un encodage ffmpeg avec le mode spécifié.
# Usage: _run_ffmpeg_encode <mode> <input_file> <output_file> <ffmpeg_log> <base_name> 
#                           <encoder_base_params> <audio_params> <stream_mapping>
#                           <progress_slot> <is_parallel> <awk_time_func>
# Modes: "pass1" (analyse), "pass2" (encodage two-pass), "crf" (single-pass)
# Retourne: 0 si succès, 1 si erreur
_run_ffmpeg_encode() {
    local mode="$1"
    local input_file="$2"
    local output_file="$3"
    local ffmpeg_log="$4"
    local base_name="$5"
    local encoder_base_params="$6"
    local audio_params="$7"
    local stream_mapping="$8"
    local progress_slot="$9"
    local is_parallel="${10}"
    local awk_time_func="${11}"

    START_TS="$(date +%s)"
    
    # Encodeur à utiliser (défaut: libx265 pour rétro-compatibilité)
    local encoder="${VIDEO_ENCODER:-libx265}"
    
    # Construire les options hwaccel (vide si non disponible = fallback software)
    local hwaccel_opts=""
    if [[ -n "${HWACCEL:-}" && "${HWACCEL}" != "none" ]]; then
        hwaccel_opts="-hwaccel $HWACCEL"
    fi

    # Configuration selon le mode
    local output_dest audio_opt stream_opt log_suffix emoji end_msg
    
    case "$mode" in
        "pass1")
            audio_opt="-an"
            stream_opt=""
            output_dest="-f null /dev/null"
            log_suffix=".pass1"
            emoji="🔍"
            end_msg="Analyse OK"
            ;;
        "pass2")
            audio_opt="$audio_params"
            stream_opt="$stream_mapping -f matroska"
            output_dest="$output_file"
            log_suffix=""
            emoji="🎬"
            end_msg="Terminé ✅"
            ;;
        "crf")
            audio_opt="$audio_params"
            stream_opt="$stream_mapping -f matroska"
            output_dest="$output_file"
            log_suffix=""
            emoji="⚡"
            end_msg="Terminé ✅"
            ;;
        *)
            log_error "Mode d'encodage inconnu: $mode"
            return 1
            ;;
    esac

    # Paramètres GOP selon le mode (film: 240, série: 600)
    local keyint_value="${FILM_KEYINT:-600}"
    
    # Texte à afficher dans la barre de progression
    local progress_display_text
    if [[ "$PROGRESS_DISPLAY_TEXT_USE_FILENAME" == true ]]; then
        progress_display_text="$base_name"
    else
        progress_display_text="$PROGRESS_DISPLAY_TEXT_FIXED"
    fi
    
    # Options spécifiques à l'encodeur
    local tune_opt preset_opt bitrate_opt
    tune_opt=$(_get_tune_option "$encoder")
    preset_opt=$(_get_preset_option "$encoder" "$ENCODER_PRESET")
    bitrate_opt=$(_get_bitrate_option "$encoder" "$mode")
    
    # Construire les paramètres encodeur spécifiques
    local encoder_params_flag encoder_full_params
    encoder_params_flag=$(get_encoder_params_flag "$encoder")
    encoder_full_params=$(_build_encoder_params_internal "$encoder" "$mode" "$encoder_base_params")

    # Exécution FFmpeg avec construction dynamique selon l'encodeur
    if [[ -n "$encoder_params_flag" && -n "$encoder_full_params" ]]; then
        # Encodeur avec paramètres spécifiques (x265, svtav1)
        $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
            $SAMPLE_SEEK_PARAMS \
            $hwaccel_opts \
            -i "$input_file" $SAMPLE_DURATION_PARAMS $VIDEO_FILTER_OPTS -pix_fmt "$OUTPUT_PIX_FMT" \
            -g "$keyint_value" -keyint_min "$keyint_value" \
            -c:v "$encoder" $preset_opt \
            $tune_opt $bitrate_opt $encoder_params_flag "$encoder_full_params" \
            -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
            $audio_opt \
            $stream_opt \
            $output_dest \
            -progress pipe:1 -nostats 2> "${ffmpeg_log}${log_suffix}" | \
        awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
            -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
            -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="$emoji" -v END_MSG="$end_msg" \
            "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
    else
        # Encodeur sans paramètres spécifiques (libaom, etc.)
        $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
            $SAMPLE_SEEK_PARAMS \
            $hwaccel_opts \
            -i "$input_file" $SAMPLE_DURATION_PARAMS $VIDEO_FILTER_OPTS -pix_fmt "$OUTPUT_PIX_FMT" \
            -g "$keyint_value" -keyint_min "$keyint_value" \
            -c:v "$encoder" $preset_opt \
            $tune_opt $bitrate_opt \
            -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
            $audio_opt \
            $stream_opt \
            $output_dest \
            -progress pipe:1 -nostats 2> "${ffmpeg_log}${log_suffix}" | \
        awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
            -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
            -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="$emoji" -v END_MSG="$end_msg" \
            "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
    fi

    # CRITIQUE : capturer PIPESTATUS immédiatement après le pipeline
    local ffmpeg_rc=${PIPESTATUS[0]:-0}
    local awk_rc=${PIPESTATUS[1]:-0}

    if [[ "$ffmpeg_rc" -eq 0 && "$awk_rc" -eq 0 ]]; then
        return 0
    fi
    
    # Gestion d'erreur - ne pas afficher les logs si interruption volontaire
    # Code 255 = signal reçu, 130 = SIGINT (128+2), 143 = SIGTERM (128+15)
    if [[ "${_INTERRUPTED:-0}" -ne 1 && "$ffmpeg_rc" -ne 255 && "$ffmpeg_rc" -lt 128 ]]; then
        local log_file="${ffmpeg_log}${log_suffix}"
        if [[ "$mode" == "pass1" ]]; then
            log_error "Erreur lors de l'analyse (pass 1)"
        fi
        if [[ -f "$log_file" ]]; then
            echo "--- Dernières lignes du log ffmpeg ($log_file) ---" >&2
            tail -n 40 "$log_file" >&2 || true
            echo "--- Fin du log ffmpeg ---" >&2
        fi
    fi
    return 1
}

# Prépare les paramètres du mode sample (seek + durée)
# Retourne via variables globales : SAMPLE_SEEK_PARAMS, SAMPLE_DURATION_PARAMS, EFFECTIVE_DURATION
_setup_sample_mode_params() {
    local input_file="$1"
    local duration_secs="$2"
    
    SAMPLE_SEEK_PARAMS=""
    SAMPLE_DURATION_PARAMS=""
    EFFECTIVE_DURATION="$duration_secs"

    if [[ "$SAMPLE_MODE" != true ]]; then
        return 0
    fi

    # Convertir duration_secs en entier
    local duration_int=${duration_secs%.*}
    local margin_start="${SAMPLE_MARGIN_START:-180}"
    local margin_end="${SAMPLE_MARGIN_END:-120}"
    local sample_len="${SAMPLE_DURATION:-30}"
    local available_range=$((duration_int - margin_start - margin_end - sample_len))

    local target_pos
    if [[ "$available_range" -gt 0 ]]; then
        local random_offset=$((RANDOM % available_range))
        target_pos=$((margin_start + random_offset))
    else
        target_pos=$((duration_int / 3))
    fi

    # Trouver le keyframe le plus proche
    local keyframe_pos
    keyframe_pos=$(ffprobe -v error -select_streams v:0 -skip_frame nokey \
        -show_entries packet=pts_time -of csv=p=0 \
        -read_intervals "${target_pos}%+30" "$input_file" 2>/dev/null | head -1 || true)

    if [[ -z "$keyframe_pos" ]] || [[ ! "$keyframe_pos" =~ ^[0-9.]+$ ]]; then
        keyframe_pos="$target_pos"
    fi

    local keyframe_int=${keyframe_pos%.*}
    
    SAMPLE_SEEK_PARAMS="-ss $keyframe_pos"
    SAMPLE_DURATION_PARAMS="-t $sample_len"
    EFFECTIVE_DURATION="$sample_len"
    SAMPLE_KEYFRAME_POS="$keyframe_pos"

    # Formater pour affichage
    local seek_h=$((keyframe_int / 3600))
    local seek_m=$(((keyframe_int % 3600) / 60))
    local seek_s=$((keyframe_int % 60))
    local seek_formatted=$(printf "%02d:%02d:%02d" "$seek_h" "$seek_m" "$seek_s")

    if [[ "$available_range" -gt 0 ]]; then
        echo -e "${YELLOW}  🎯 Segment de ${sample_len}s à partir de ${seek_formatted}${NOCOLOR}"
    else
        echo -e "${YELLOW}  ⚠️ Vidéo courte : segment de ${sample_len}s à partir de ${seek_formatted}${NOCOLOR}"
    fi
}

###########################################################
# EXÉCUTION FFMPEG UNIFIÉE
###########################################################

# Fonction unifiée pour l'exécution FFmpeg avec différents modes.
# Combine la logique de passthrough, CRF et two-pass en une seule fonction.
#
# Usage: _execute_ffmpeg_pipeline <mode> <input> <output> <log> <duration> <basename>
# Modes:
#   - passthrough : vidéo copiée, seul l'audio est traité
#   - crf         : single-pass CRF (quality-based)
#   - twopass     : two-pass ABR (bitrate-based)
#
# Retourne: 0 si succès, 1 si erreur
_execute_ffmpeg_pipeline() {
    local mode="$1"
    local tmp_input="$2"
    local tmp_output="$3"
    local ffmpeg_log_temp="$4"
    local duration_secs="$5"
    local base_name="$6"

    # Chronos : début du traitement
    FILE_START_TS="$(date +%s)"
    START_TS="$FILE_START_TS"

    # ===== PRÉPARATION COMMUNE =====
    
    # Script AWK pour progression (gawk vs BSD awk)
    local awk_time_func
    if [[ "$HAS_GAWK" -eq 1 ]]; then
        awk_time_func='function get_time() { return systime() }'
    else
        awk_time_func='function get_time() { cmd="date +%s"; cmd | getline t; close(cmd); return t }'
    fi

    # Acquérir un slot pour affichage de progression
    local progress_slot=0
    local is_parallel=0
    if [[ "${PARALLEL_JOBS:-1}" -gt 1 ]]; then
        is_parallel=1
        progress_slot=$(acquire_progress_slot)
    fi

    # Durée effective pour la progression
    local effective_duration="$duration_secs"
    if [[ -z "$effective_duration" || "$effective_duration" == "N/A" ]]; then
        effective_duration=0
    fi
    EFFECTIVE_DURATION="$effective_duration"

    # Préparer les paramètres audio
    local audio_params
    audio_params=$(_build_audio_params "$tmp_input")

    # Préparer le mapping des streams (filtre sous-titres FR)
    local stream_mapping
    stream_mapping=$(_build_stream_mapping "$tmp_input")

    # Helper pour libérer le slot et retourner en erreur
    _pipeline_cleanup_and_fail() {
        if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
            release_progress_slot "$progress_slot"
        fi
        return 1
    }

    # Helper pour afficher les erreurs FFmpeg
    _pipeline_show_error() {
        local error_msg="$1"
        local log_file="$2"
        
        if [[ "${_INTERRUPTED:-0}" -ne 1 ]]; then
            log_error "$error_msg"
            if [[ -f "$log_file" ]]; then
                local err_preview
                err_preview=$(tail -10 "$log_file" 2>/dev/null || echo "(log indisponible)")
                echo -e "${RED}--- Extrait du log FFmpeg ---${NOCOLOR}"
                echo "$err_preview"
                echo -e "${RED}-----------------------------${NOCOLOR}"
            fi
        fi
    }

    # ===== EXÉCUTION SELON LE MODE =====
    
    # Texte à afficher dans la barre de progression
    local progress_display_text
    if [[ "$PROGRESS_DISPLAY_TEXT_USE_FILENAME" == true ]]; then
        progress_display_text="$base_name"
    else
        progress_display_text="$PROGRESS_DISPLAY_TEXT_FIXED"
    fi
    
    case "$mode" in
        "passthrough")
            # Mode passthrough : vidéo copiée, audio traité
            $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
                -i "$tmp_input" \
                -c:v copy \
                $audio_params \
                $stream_mapping -f matroska \
                "$tmp_output" \
                -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
            awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
                -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
                -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="📋" -v END_MSG="Terminé ✅" \
                "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

            local ffmpeg_rc=${PIPESTATUS[0]:-0}
            local awk_rc=${PIPESTATUS[1]:-0}

            if [[ "$ffmpeg_rc" -ne 0 || "$awk_rc" -ne 0 ]]; then
                _pipeline_show_error "Erreur lors du remuxage" "$ffmpeg_log_temp"
                _pipeline_cleanup_and_fail
                return 1
            fi
            ;;

        "crf"|"twopass")
            # Modes avec encodage vidéo : préparer les paramètres vidéo
            _setup_video_encoding_params "$tmp_input"
            _setup_sample_mode_params "$tmp_input" "$duration_secs"

            # Paramètres de base pour l'encodeur
            local encoder_base_params="${ENCODER_BASE_PARAMS:-}"
            if [[ -z "$encoder_base_params" ]]; then
                encoder_base_params="${X265_VBV_STRING}"
                if [[ -n "${X265_EXTRA_PARAMS:-}" ]]; then
                    encoder_base_params="${encoder_base_params}:${X265_EXTRA_PARAMS}"
                fi
            fi

            if [[ "$mode" == "crf" ]]; then
                # Mode single-pass CRF
                if ! _run_ffmpeg_encode "crf" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "$audio_params" "$stream_mapping" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    _pipeline_cleanup_and_fail
                    return 1
                fi
            else
                # Mode two-pass
                # Pass 1 : Analyse
                if ! _run_ffmpeg_encode "pass1" "$tmp_input" "" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "" "" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    _pipeline_cleanup_and_fail
                    return 1
                fi

                # Pass 2 : Encodage
                if ! _run_ffmpeg_encode "pass2" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "$audio_params" "$stream_mapping" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
                    rm -f "svtav1_2pass.log" "ffmpeg2pass-0.log" 2>/dev/null || true
                    _pipeline_cleanup_and_fail
                    return 1
                fi

                # Nettoyage fichiers two-pass
                rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
                rm -f "svtav1_2pass.log" "ffmpeg2pass-0.log" 2>/dev/null || true
            fi
            ;;

        *)
            log_error "Mode FFmpeg inconnu: $mode"
            _pipeline_cleanup_and_fail
            return 1
            ;;
    esac

    # Libérer le slot de progression
    if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
        release_progress_slot "$progress_slot"
    fi

    return 0
}

###########################################################
# WRAPPERS RÉTRO-COMPATIBLES
###########################################################

# Exécute une conversion où la vidéo est copiée et seul l'audio est traité.
# Wrapper rétro-compatible pour _execute_ffmpeg_pipeline "passthrough"
# Usage: _execute_video_passthrough <input> <output> <log> <duration> <basename>
_execute_video_passthrough() {
    _execute_ffmpeg_pipeline "passthrough" "$@"
}

# Exécute la conversion vidéo complète (CRF ou two-pass selon config).
# Wrapper rétro-compatible pour _execute_ffmpeg_pipeline
# Usage: _execute_conversion <input> <output> <log> <duration> <basename>
_execute_conversion() {
    local mode="twopass"
    if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
        mode="crf"
    fi
    _execute_ffmpeg_pipeline "$mode" "$@"
}

