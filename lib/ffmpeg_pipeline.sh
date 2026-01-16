#!/bin/bash
###########################################################
# PIPELINE FFMPEG
# Exécution unifiée des commandes FFmpeg (passthrough, CRF, two-pass)
# Extrait de transcode_video.sh pour modularité
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. FFmpeg peut retourner des codes non-zéro gérés
# 3. Les modules sont sourcés, pas exécutés directement
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

# Crée un fichier marqueur temporaire pour la notification de progression Discord
# Usage: _create_progress_marker_file
# Retourne le chemin du fichier sur stdout
_create_progress_marker_file() {
    local marker_file
    marker_file=$(mktemp 2>/dev/null || echo "")
    if [[ -z "$marker_file" ]]; then
        marker_file="/tmp/nascode_progress_marker_$$.txt"
    fi
    # Supprimer le fichier pour qu'AWK puisse le créer
    rm -f "$marker_file" 2>/dev/null || true
    printf '%s' "$marker_file"
}

# Lance un watcher en arrière-plan qui surveille le fichier marqueur
# et envoie une notification Discord quand il apparaît
# Usage: _start_progress_watcher <marker_file> <filename> <watcher_pid_var>
# Le PID du watcher est stocké dans la variable dont le nom est passé en $3
_start_progress_watcher() {
    local marker_file="$1"
    local filename="$2"
    local pid_var_name="$3"
    
    # Vérifier si les notifications Discord sont activées
    if ! declare -f _notify_discord_is_enabled &>/dev/null || ! _notify_discord_is_enabled; then
        eval "$pid_var_name=0"
        return 0
    fi
    
    # Timeout max pour le watcher (évite les zombies)
    local max_wait="${DISCORD_PROGRESS_UPDATE_DELAY:-15}"
    max_wait=$((max_wait + 30))  # Marge supplémentaire
    
    (
        local elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            if [[ -f "$marker_file" ]]; then
                # Lire les métriques du fichier
                local speed eta
                speed=$(grep -E '^speed=' "$marker_file" 2>/dev/null | cut -d'=' -f2 || echo "")
                eta=$(grep -E '^eta=' "$marker_file" 2>/dev/null | cut -d'=' -f2 || echo "")
                
                # Envoyer la notification si on a des données valides
                if [[ -n "$speed" ]]; then
                    notify_event file_progress_update "$filename" "$speed" "$eta" 2>/dev/null || true
                fi
                
                # Supprimer le fichier marqueur
                rm -f "$marker_file" 2>/dev/null || true
                break
            fi
            sleep 1
            ((elapsed++))
        done
        # Nettoyage si timeout
        rm -f "$marker_file" 2>/dev/null || true
    ) &
    
    eval "$pid_var_name=$!"
}

# Arrête le watcher de progression et nettoie le fichier marqueur
# Usage: _stop_progress_watcher <watcher_pid> <marker_file>
_stop_progress_watcher() {
    local watcher_pid="$1"
    local marker_file="$2"
    
    # Tuer le watcher s'il tourne encore
    if [[ -n "$watcher_pid" ]] && [[ "$watcher_pid" -gt 0 ]]; then
        kill "$watcher_pid" 2>/dev/null || true
        wait "$watcher_pid" 2>/dev/null || true
    fi
    
    # Nettoyage du fichier marqueur
    if [[ -n "$marker_file" ]]; then
        rm -f "$marker_file" 2>/dev/null || true
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
    # shellcheck disable=SC2034
    SAMPLE_KEYFRAME_POS="$keyframe_pos"

    # Formater pour affichage
    local seek_h=$((keyframe_int / 3600))
    local seek_m=$(((keyframe_int % 3600) / 60))
    local seek_s=$((keyframe_int % 60))
    local seek_formatted
    seek_formatted=$(printf "%02d:%02d:%02d" "$seek_h" "$seek_m" "$seek_s")

    if [[ "$available_range" -gt 0 ]]; then
        echo -e "${YELLOW}  🎯 $(msg MSG_FFMPEG_SEGMENT "$sample_len" "$seek_formatted")${NOCOLOR}"
    else
        print_warning "$(msg MSG_FFMPEG_SHORT_VIDEO "$sample_len" "$seek_formatted")"
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

    # ===== PRÉPARATION NOTIFICATION PROGRESSION DISCORD =====
    local progress_marker_file=""
    local progress_watcher_pid=0
    local progress_marker_delay="${DISCORD_PROGRESS_UPDATE_DELAY:-15}"
    
    # Créer le fichier marqueur et lancer le watcher uniquement si :
    # - Ce n'est pas du passthrough (trop rapide pour être utile)
    # - La durée est suffisante (> 60s après délai)
    if [[ "$mode" != "passthrough" ]] && [[ "${effective_duration%.*}" -gt $((progress_marker_delay + 30)) ]]; then
        progress_marker_file=$(_create_progress_marker_file)
        _start_progress_watcher "$progress_marker_file" "$base_name" progress_watcher_pid
    fi

    # ===== EXÉCUTION SELON LE MODE =====
    
    # Texte à afficher dans la barre de progression
    local progress_display_text
    if [[ "$PROGRESS_DISPLAY_TEXT_USE_FILENAME" == true ]]; then
        progress_display_text="$base_name"
    else
        progress_display_text="$(_get_progress_display_text_fixed)"
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

            if [[ -n "${NASCODE_WORKDIR:-}" ]] && [[ -d "${NASCODE_WORKDIR}" ]]; then
                (cd "${NASCODE_WORKDIR}" && "${cmd[@]}" 2> "$ffmpeg_log_temp") | \
                    awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
                        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
                        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="📋" -v END_MSG="$(msg MSG_PROGRESS_DONE)" \
                        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
            else
                "${cmd[@]}" 2> "$ffmpeg_log_temp" | \
                    awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
                        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
                        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="📋" -v END_MSG="$(msg MSG_PROGRESS_DONE)" \
                        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
            fi

            # CRITIQUE : capturer PIPESTATUS immédiatement après le pipeline
            local ffmpeg_rc=${PIPESTATUS[0]:-0}
            local awk_rc=${PIPESTATUS[1]:-0}

            if [[ "$ffmpeg_rc" -ne 0 || "$awk_rc" -ne 0 ]]; then
                _ffmpeg_pipeline_show_error "$(msg MSG_FFMPEG_REMUX_ERROR)" "$ffmpeg_log_temp"
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
                # Exporter les variables pour le watcher Discord (utilisées par AWK via _run_ffmpeg_encode)
                export PROGRESS_MARKER_FILE="$progress_marker_file"
                export PROGRESS_MARKER_DELAY="$progress_marker_delay"
                
                if ! _run_ffmpeg_encode "crf" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "$audio_params" "$stream_mapping" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    _stop_progress_watcher "$progress_watcher_pid" "$progress_marker_file"
                    _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                    return 1
                fi
            else
                # Mode two-pass
                # Pour two-pass, on n'active le marqueur que sur pass2 (l'encodage réel)
                
                # Pass 1 : Analyse (pas de notification)
                export PROGRESS_MARKER_FILE=""
                export PROGRESS_MARKER_DELAY="$progress_marker_delay"
                
                if ! _run_ffmpeg_encode "pass1" "$tmp_input" "" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "" "" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    _stop_progress_watcher "$progress_watcher_pid" "$progress_marker_file"
                    _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                    return 1
                fi

                # Pass 2 : Encodage (avec notification)
                export PROGRESS_MARKER_FILE="$progress_marker_file"
                
                if ! _run_ffmpeg_encode "pass2" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                        "$encoder_base_params" "$audio_params" "$stream_mapping" \
                                        "$progress_slot" "$is_parallel" "$awk_time_func"; then
                    rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
                    rm -f "svtav1_2pass.log" "ffmpeg2pass-0.log" 2>/dev/null || true
                    _stop_progress_watcher "$progress_watcher_pid" "$progress_marker_file"
                    _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
                    return 1
                fi

                # Nettoyage fichiers two-pass
                rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
                rm -f "svtav1_2pass.log" "ffmpeg2pass-0.log" 2>/dev/null || true
            fi
            ;;

        *)
            log_error "$(msg MSG_FFMPEG_UNKNOWN_MODE "$mode")"
            _ffmpeg_pipeline_release_slot_if_needed "$is_parallel" "$progress_slot"
            return 1
            ;;
    esac

    # Arrêter le watcher de progression et nettoyer
    _stop_progress_watcher "$progress_watcher_pid" "$progress_marker_file"

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
