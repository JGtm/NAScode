#!/bin/bash
###########################################################
# PIPELINE FFMPEG
# Exécution unifiée des commandes FFmpeg (passthrough, CRF, two-pass)
# Extrait de transcode_video.sh pour modularité
###########################################################

###########################################################
# HELPERS PIPELINE FFMPEG
###########################################################

_ffmpeg_pipeline_release_slot_if_needed() {
    local is_parallel="${1:-0}"
    local progress_slot="${2:-0}"

    if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
        release_progress_slot "$progress_slot"
    fi
}

_ffmpeg_pipeline_show_error() {
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
    keyframe_pos=$(ffprobe_safe -v error -select_streams v:0 -skip_frame nokey \
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
        print_warning "Vidéo courte : segment de ${sample_len}s à partir de ${seek_formatted}"
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

    # Préparer les paramètres du mode sample (seek + durée) - AVANT tout traitement
    # Définit SAMPLE_SEEK_PARAMS, SAMPLE_DURATION_PARAMS, EFFECTIVE_DURATION, SAMPLE_KEYFRAME_POS
    _setup_sample_mode_params "$tmp_input" "$duration_secs"

    # Préparer les paramètres audio
    local audio_params
    audio_params=$(_build_audio_params "$tmp_input")

    # Préparer le mapping des streams (filtre sous-titres FR)
    local stream_mapping
    stream_mapping=$(_build_stream_mapping "$tmp_input")

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
            # En mode sample, on applique seek+durée pour ne copier que le segment
            local -a cmd
            cmd=()

            if [[ -n "${IO_PRIORITY_CMD:-}" ]]; then
                _cmd_append_words cmd "$IO_PRIORITY_CMD"
            fi

            cmd+=(ffmpeg -y -loglevel warning)

            _cmd_append_words cmd "${SAMPLE_SEEK_PARAMS:-}"

            cmd+=(-i "$tmp_input")

            _cmd_append_words cmd "${SAMPLE_DURATION_PARAMS:-}"

            cmd+=(-c:v copy)

            _cmd_append_words cmd "$audio_params"
            _cmd_append_words cmd "$stream_mapping"

            cmd+=(-f matroska "$tmp_output" -progress pipe:1 -nostats)

            "${cmd[@]}" 2> "$ffmpeg_log_temp" | \
                awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
                    -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
                    -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="📋" -v END_MSG="Terminé ✅" \
                    "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

            # CRITIQUE : capturer PIPESTATUS immédiatement après le pipeline
            local ffmpeg_rc=${PIPESTATUS[0]:-0}
            local awk_rc=${PIPESTATUS[1]:-0}

            if [[ "$ffmpeg_rc" -ne 0 || "$awk_rc" -ne 0 ]]; then
                _ffmpeg_pipeline_show_error "Erreur lors du remuxage" "$ffmpeg_log_temp"
                _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                return 1
            fi
            ;;

        "crf"|"twopass")
            # Modes avec encodage vidéo : préparer les paramètres vidéo
            _setup_video_encoding_params "$tmp_input"
            # Note: _setup_sample_mode_params est appelé en amont (PRÉPARATION COMMUNE)

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
                    _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                    return 1
                fi
            else
                # Mode two-pass
                # Pass 1 : Analyse
                if ! _run_ffmpeg_encode "pass1" "$tmp_input" "" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "" "" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                    return 1
                fi

                # Pass 2 : Encodage
                if ! _run_ffmpeg_encode "pass2" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "$audio_params" "$stream_mapping" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
                    rm -f "svtav1_2pass.log" "ffmpeg2pass-0.log" 2>/dev/null || true
                    _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                    return 1
                fi

                # Nettoyage fichiers two-pass
                rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
                rm -f "svtav1_2pass.log" "ffmpeg2pass-0.log" 2>/dev/null || true
            fi
            ;;

        *)
            log_error "Mode FFmpeg inconnu: $mode"
            _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
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
