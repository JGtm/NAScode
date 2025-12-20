#!/bin/bash
###########################################################
# ENCODAGE VIDÉO
# Logique d'encodage FFmpeg/x265 (incluant adaptation 10-bit/downscale)
###########################################################

###########################################################
# SOUS-FONCTIONS ENCODAGE (FORMAT / SCALE)
###########################################################

# Détermine le pixel format de sortie.
# - Si la source est 10-bit (Main10 etc.), on garde du 10-bit (yuv420p10le)
# - Sinon on reste en 8-bit (yuv420p)
_select_output_pix_fmt() {
    local input_pix_fmt="$1"
    local out_pix_fmt="yuv420p"

    # Heuristique simple et robuste : les pix_fmt 10-bit contiennent généralement "10".
    # Ex: yuv420p10le, yuv422p10le, yuv444p10le
    if [[ "$input_pix_fmt" == *"10"* ]]; then
        out_pix_fmt="yuv420p10le"
    fi

    echo "$out_pix_fmt"
}

# Construit le filtre vidéo (optionnel) pour limiter la résolution à 1080p.
# Retourne une chaîne vide si aucun downscale n'est requis.
_build_downscale_filter_if_needed() {
    local width="$1"
    local height="$2"

    if [[ -z "$width" || -z "$height" ]]; then
        echo ""
        return 0
    fi
    if ! [[ "$width" =~ ^[0-9]+$ ]] || ! [[ "$height" =~ ^[0-9]+$ ]]; then
        echo ""
        return 0
    fi

    # Règle "safe qualité" : si la vidéo dépasse le cadre 1080p (largeur > 1920 OU hauteur > 1080),
    # on downscale pour réduire le nombre de pixels à bitrate constant.
    if [[ "$width" -le "${DOWNSCALE_MAX_WIDTH}" && "$height" -le "${DOWNSCALE_MAX_HEIGHT}" ]]; then
        echo ""
        return 0
    fi

    # Conserver le ratio, ne jamais upscaler, et forcer des dimensions paires (requis par YUV 4:2:0).
    # min(W/iw, H/ih) donne le facteur de réduction pour tenir dans 1920x1080.
    # trunc(x/2)*2 garantit un multiple de 2.
    local s="scale=w='trunc(iw*min(${DOWNSCALE_MAX_WIDTH}/iw\\,${DOWNSCALE_MAX_HEIGHT}/ih)/2)*2':h='trunc(ih*min(${DOWNSCALE_MAX_WIDTH}/iw\\,${DOWNSCALE_MAX_HEIGHT}/ih)/2)*2':flags=lanczos"
    echo "$s"
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
    #  -pix_fmt yuv420p10le : format de pixels YUV 4:2:0 en 10 bits (si source 10-bit)

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

    # ==================== ADAPTATION SOURCE (10-bit + downscale) ====================
    # Objectif :
    # - éviter le banding : conserver du 10-bit quand l'entrée est 10-bit
    # - éviter une qualité catastrophique : downscale au-delà de 1080p pour un bitrate cible prévu 1080p
    local input_props
    input_props=$(get_video_stream_props "$tmp_input")
    local input_width input_height input_pix_fmt
    IFS='|' read -r input_width input_height input_pix_fmt <<< "$input_props"

    local output_pix_fmt
    output_pix_fmt=$(_select_output_pix_fmt "$input_pix_fmt")

    local downscale_filter
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")

    # Note: on passe "-vf ..." sous forme de chaîne pour rester compatible avec la construction
    # existante des commandes ffmpeg (style du script).
    local video_filter_opts=""
    if [[ -n "$downscale_filter" ]]; then
        video_filter_opts="-vf $downscale_filter"
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${CYAN}  ⬇️  Downscale activé : ${input_width}x${input_height} → max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
        fi
    fi
    if [[ "$NO_PROGRESS" != true ]] && [[ -n "$input_pix_fmt" ]]; then
        if [[ "$output_pix_fmt" == "yuv420p10le" ]]; then
            echo -e "${CYAN}  🎨 Sortie 10-bit activée (source: $input_pix_fmt)${NOCOLOR}"
        fi
    fi

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
        -i "$tmp_input" $sample_duration_params $video_filter_opts -pix_fmt "$output_pix_fmt" \
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
        -i "$tmp_input" $sample_duration_params $video_filter_opts -pix_fmt "$output_pix_fmt" \
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
