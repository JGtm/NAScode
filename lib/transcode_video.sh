#!/bin/bash
###########################################################
# ENCODAGE VIDÉO
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
# ADAPTATION BITRATE PAR RÉSOLUTION (720p)
###########################################################

# Estime la hauteur de sortie après application éventuelle du downscale 1080p.
# Retourne vide si les entrées sont invalides.
_compute_output_height_for_bitrate() {
    local src_width="$1"
    local src_height="$2"

    if [[ -z "$src_width" || -z "$src_height" ]]; then
        echo ""
        return 0
    fi
    if ! [[ "$src_width" =~ ^[0-9]+$ ]] || ! [[ "$src_height" =~ ^[0-9]+$ ]]; then
        echo ""
        return 0
    fi

    # Pas de downscale : hauteur inchangée
    if [[ "$src_width" -le "${DOWNSCALE_MAX_WIDTH}" && "$src_height" -le "${DOWNSCALE_MAX_HEIGHT}" ]]; then
        echo "$src_height"
        return 0
    fi

    # Reproduire la logique du filtre : facteur = min(Wmax/iw, Hmax/ih), puis arrondi à pair.
    local computed_height
    computed_height=$(awk \
        -v iw="$src_width" \
        -v ih="$src_height" \
        -v mw="${DOWNSCALE_MAX_WIDTH}" \
        -v mh="${DOWNSCALE_MAX_HEIGHT}" \
        'BEGIN {
            if (iw <= 0 || ih <= 0) { print ""; exit }
            fw = mw / iw;
            fh = mh / ih;
            f = (fw < fh ? fw : fh);
            if (f > 1) f = 1;
            oh = int((ih * f) / 2) * 2;
            if (oh < 2) oh = 2;
            print oh;
        }')

    echo "$computed_height"
}

# Calcule un bitrate effectif (kbps) selon la hauteur de sortie estimée.
_compute_effective_bitrate_kbps_for_height() {
    local base_kbps="$1"
    local output_height="$2"

    if [[ -z "$base_kbps" ]] || ! [[ "$base_kbps" =~ ^[0-9]+$ ]]; then
        echo "$base_kbps"
        return 0
    fi
    if [[ "${ADAPTIVE_BITRATE_BY_RESOLUTION:-false}" != true ]]; then
        echo "$base_kbps"
        return 0
    fi
    if [[ -z "$output_height" ]] || ! [[ "$output_height" =~ ^[0-9]+$ ]]; then
        echo "$base_kbps"
        return 0
    fi

    if [[ "$output_height" -le "${ADAPTIVE_720P_MAX_HEIGHT}" ]]; then
        local scale_percent="${ADAPTIVE_720P_SCALE_PERCENT}"
        if [[ -z "$scale_percent" ]] || ! [[ "$scale_percent" =~ ^[0-9]+$ ]] || [[ "$scale_percent" -le 0 ]]; then
            echo "$base_kbps"
            return 0
        fi
        # Arrondi au plus proche
        echo $(( (base_kbps * scale_percent + 50) / 100 ))
        return 0
    fi

    echo "$base_kbps"
}

# Construit le suffixe effectif par fichier à partir des dimensions source.
# Inclut : bitrate effectif ou CRF + hauteur de sortie estimée (ex: 720p) + preset.
# Format two-pass: _x265_<bitrate>k_<height>p_<preset>[_tuned][_opus][_sample]
# Format single-pass: _x265_crf<value>_<height>p_<preset>[_tuned][_opus][_sample]
_build_effective_suffix_for_dims() {
    local src_width="$1"
    local src_height="$2"

    local suffix="_x265"

    # Résolution de sortie estimée (après downscale éventuel)
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$src_width" "$src_height")

    # Mode single-pass CRF ou two-pass bitrate
    if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
        suffix="${suffix}_crf${CRF_VALUE}"
    else
        # Bitrate effectif (selon hauteur) pour two-pass
        local effective_bitrate_kbps
        effective_bitrate_kbps=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
        if [[ -n "$effective_bitrate_kbps" ]] && [[ "$effective_bitrate_kbps" =~ ^[0-9]+$ ]]; then
            suffix="${suffix}_${effective_bitrate_kbps}k"
        else
            suffix="${suffix}_${TARGET_BITRATE_KBPS}k"
        fi
    fi

    # Ajout de la résolution (si connue)
    if [[ -n "$output_height" ]] && [[ "$output_height" =~ ^[0-9]+$ ]]; then
        suffix="${suffix}_${output_height}p"
    fi

    # Preset d'encodage
    suffix="${suffix}_${ENCODER_PRESET}"

    # Indicateur si paramètres x265 spéciaux (tuned)
    if [[ -n "${X265_EXTRA_PARAMS:-}" ]]; then
        suffix="${suffix}_tuned"
    fi

    # Indicateur conversion audio Opus
    if [[ "${OPUS_ENABLED:-false}" == true ]]; then
        suffix="${suffix}_opus"
    fi

    # Indicateur mode sample (segment de test)
    if [[ "${SAMPLE_MODE:-false}" == true ]]; then
        suffix="${suffix}_sample"
    fi

    echo "$suffix"
}

###########################################################
# ANALYSE AUDIO ET PARAMÈTRES OPUS (expérimental)
###########################################################

# Analyse l'audio d'un fichier et détermine si la conversion Opus est avantageuse.
# Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert to opus)
_get_audio_conversion_info() {
    local input_file="$1"
    
    # Si Opus désactivé, toujours copier
    if [[ "${OPUS_ENABLED:-false}" != true ]]; then
        echo "copy|0|0"
        return 0
    fi
    
    # Récupérer les infos audio du premier flux audio
    local audio_info
    audio_info=$(ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$input_file" 2>/dev/null)
    
    local audio_codec audio_bitrate audio_bitrate_tag
    audio_codec=$(echo "$audio_info" | grep '^codec_name=' | cut -d'=' -f2)
    audio_bitrate=$(echo "$audio_info" | grep '^bit_rate=' | cut -d'=' -f2)
    audio_bitrate_tag=$(echo "$audio_info" | grep '^TAG:BPS=' | cut -d'=' -f2)
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$audio_bitrate" || "$audio_bitrate" == "N/A" ]]; then
        audio_bitrate="$audio_bitrate_tag"
    fi
    
    # Convertir en kbps
    audio_bitrate=$(clean_number "$audio_bitrate")
    local audio_bitrate_kbps=0
    if [[ -n "$audio_bitrate" && "$audio_bitrate" =~ ^[0-9]+$ ]]; then
        audio_bitrate_kbps=$((audio_bitrate / 1000))
    fi
    
    # Déterminer si la conversion est avantageuse
    local should_convert=0
    
    # Ne pas convertir si déjà en Opus
    if [[ "$audio_codec" == "opus" ]]; then
        should_convert=0
    # Convertir si le bitrate source est supérieur au seuil
    elif [[ "$audio_bitrate_kbps" -gt "${OPUS_CONVERSION_THRESHOLD_KBPS:-160}" ]]; then
        should_convert=1
    fi
    
    echo "${audio_codec}|${audio_bitrate_kbps}|${should_convert}"
}

# Construit les paramètres audio FFmpeg selon l'analyse
_build_audio_params() {
    local input_file="$1"
    
    local audio_info should_convert
    audio_info=$(_get_audio_conversion_info "$input_file")
    should_convert=$(echo "$audio_info" | cut -d'|' -f3)
    
    if [[ "$should_convert" -eq 1 ]]; then
        # Conversion vers Opus avec normalisation des layouts audio
        # -af "aformat=channel_layouts=..." normalise les layouts non-standard
        echo "-c:a libopus -b:a ${OPUS_TARGET_BITRATE_KBPS:-128}k -af aformat=channel_layouts=7.1|5.1|stereo|mono"
    else
        # Copier l'audio tel quel
        echo "-c:a copy"
    fi
}

###########################################################
# MAPPING DES STREAMS (FILTRAGE SOUS-TITRES)
###########################################################

# Construit les paramètres de mapping des streams pour ffmpeg.
# - Mappe tous les flux vidéo et audio
# - Filtre les sous-titres pour ne garder que le français (fre/fra)
# Retourne une chaîne de paramètres -map pour ffmpeg.
_build_stream_mapping() {
    local input_file="$1"
    
    # Toujours mapper vidéo et audio
    local mapping="-map 0:v -map 0:a?"
    
    # Récupérer les index des sous-titres français
    # On cherche les streams de type subtitle avec language=fre ou fra
    local fr_subs
    fr_subs=$(ffprobe -v error -select_streams s \
        -show_entries stream=index:stream_tags=language \
        -of csv=p=0 "$input_file" 2>/dev/null | \
        grep -E ',fre$|,fra$|,french$' | cut -d',' -f1)
    
    if [[ -n "$fr_subs" ]]; then
        # Ajouter chaque sous-titre français
        while IFS= read -r idx; do
            if [[ -n "$idx" ]] && [[ "$idx" =~ ^[0-9]+$ ]]; then
                mapping="$mapping -map 0:$idx"
            fi
        done <<< "$fr_subs"
    else
        # Aucun sous-titre FR trouvé, on garde tous les sous-titres
        mapping="$mapping -map 0:s?"
    fi
    
    echo "$mapping"
}

###########################################################
# SOUS-FONCTIONS D'ENCODAGE (PASS 1 / PASS 2)
###########################################################

# Prépare les paramètres vidéo adaptés au fichier source (bitrate, filtres, etc.)
# Retourne via variables globales : VIDEO_BITRATE, VIDEO_MAXRATE, VIDEO_BUFSIZE,
#                                   X265_VBV_STRING, VIDEO_FILTER_OPTS, OUTPUT_PIX_FMT
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
            echo -e "${CYAN}  🎨 Sortie 10-bit activée (source: $input_pix_fmt)${NOCOLOR}"
        fi
    fi

    # Calcul du bitrate adapté à la résolution de sortie
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$input_width" "$input_height")

    local effective_target effective_maxrate effective_bufsize
    effective_target=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
    effective_maxrate=$(_compute_effective_bitrate_kbps_for_height "${MAXRATE_KBPS}" "$output_height")
    effective_bufsize=$(_compute_effective_bitrate_kbps_for_height "${BUFSIZE_KBPS}" "$output_height")

    VIDEO_BITRATE="${effective_target}k"
    VIDEO_MAXRATE="${effective_maxrate}k"
    VIDEO_BUFSIZE="${effective_bufsize}k"
    X265_VBV_STRING="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"
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
        -read_intervals "${target_pos}%+30" "$input_file" 2>/dev/null | head -1)

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
        echo -e "${CYAN}  🎯 Mode échantillon : segment de ${sample_len}s à partir de ${seek_formatted}${NOCOLOR}"
    else
        echo -e "${YELLOW}  ⚠️ Vidéo courte : segment de ${sample_len}s à partir de ${seek_formatted}${NOCOLOR}"
    fi
}

# Exécute le pass 1 (analyse) de l'encodage two-pass
# Retourne 0 si succès, 1 si erreur
_run_encoding_pass1() {
    local input_file="$1"
    local ffmpeg_log="$2"
    local base_name="$3"
    local x265_base_params="$4"
    local progress_slot="$5"
    local is_parallel="$6"
    local awk_time_func="$7"

    START_TS="$(date +%s)"
    
    # Construire les paramètres pass 1
    local x265_params_pass1="pass=1:${x265_base_params}"
    if [[ "${X265_PASS1_FAST:-false}" == true ]]; then
        x265_params_pass1="${x265_params_pass1}:no-slow-firstpass=1"
    fi

    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        $SAMPLE_SEEK_PARAMS \
        -hwaccel $HWACCEL \
        -i "$input_file" $SAMPLE_DURATION_PARAMS $VIDEO_FILTER_OPTS -pix_fmt "$OUTPUT_PIX_FMT" \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$VIDEO_BITRATE" -x265-params "$x265_params_pass1" \
        -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
        -an \
        -f null /dev/null \
        -progress pipe:1 -nostats 2> "${ffmpeg_log}.pass1" | \
    awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" \
        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="🔍" -v END_MSG="Analyse OK" \
        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

    local pass1_rc=${PIPESTATUS[0]:-0}
    
    if [[ "$pass1_rc" -ne 0 ]]; then
        # Ne pas afficher les logs si interruption volontaire (Ctrl+C)
        # Code 255 = signal reçu, 130 = SIGINT (128+2), 143 = SIGTERM (128+15)
        if [[ "${_INTERRUPTED:-0}" -ne 1 && "$pass1_rc" -ne 255 && "$pass1_rc" -lt 128 ]]; then
            echo -e "${RED}❌ Erreur lors de l'analyse (pass 1)${NOCOLOR}" >&2
            if [[ -f "${ffmpeg_log}.pass1" ]]; then
                tail -n 40 "${ffmpeg_log}.pass1" >&2 || true
            fi
        fi
        return 1
    fi
    
    return 0
}

# Exécute le pass 2 (encodage final) de l'encodage two-pass
# Retourne 0 si succès, 1 si erreur
_run_encoding_pass2() {
    local input_file="$1"
    local output_file="$2"
    local ffmpeg_log="$3"
    local base_name="$4"
    local x265_base_params="$5"
    local audio_params="$6"
    local stream_mapping="$7"
    local progress_slot="$8"
    local is_parallel="$9"
    local awk_time_func="${10}"

    START_TS="$(date +%s)"
    local x265_params_pass2="pass=2:${x265_base_params}"

    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        $SAMPLE_SEEK_PARAMS \
        -hwaccel $HWACCEL \
        -i "$input_file" $SAMPLE_DURATION_PARAMS $VIDEO_FILTER_OPTS -pix_fmt "$OUTPUT_PIX_FMT" \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$VIDEO_BITRATE" -x265-params "$x265_params_pass2" \
        -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
        $audio_params \
        $stream_mapping -f matroska \
        "$output_file" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log" | \
    awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" \
        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="🎬" -v END_MSG="Terminé ✅" \
        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

    # CRITIQUE : capturer PIPESTATUS immédiatement après le pipeline
    local ffmpeg_rc=${PIPESTATUS[0]:-0}
    local awk_rc=${PIPESTATUS[1]:-0}

    if [[ "$ffmpeg_rc" -eq 0 && "$awk_rc" -eq 0 ]]; then
        return 0
    else
        # Ne pas afficher les logs si interruption volontaire (Ctrl+C)
        # Code 255 = signal reçu, 130 = SIGINT (128+2), 143 = SIGTERM (128+15)
        if [[ "${_INTERRUPTED:-0}" -ne 1 && "$ffmpeg_rc" -ne 255 && "$ffmpeg_rc" -lt 128 ]] && [[ -f "$ffmpeg_log" ]]; then
            echo "--- Dernières lignes du log ffmpeg ($ffmpeg_log) ---" >&2
            tail -n 80 "$ffmpeg_log" >&2 || true
            echo "--- Fin du log ffmpeg ---" >&2
        fi
        return 1
    fi
}

# Exécute l'encodage single-pass avec CRF (pour séries)
# Plus rapide que two-pass, taille variable mais qualité constante
# Retourne 0 si succès, 1 si erreur
_run_encoding_single_pass() {
    local input_file="$1"
    local output_file="$2"
    local ffmpeg_log="$3"
    local base_name="$4"
    local x265_base_params="$5"
    local audio_params="$6"
    local stream_mapping="$7"
    local progress_slot="$8"
    local is_parallel="$9"
    local awk_time_func="${10}"

    START_TS="$(date +%s)"
    
    # Paramètres x265 pour CRF (pas de pass=, pas de bitrate cible)
    local x265_params_crf="${x265_base_params}"

    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        $SAMPLE_SEEK_PARAMS \
        -hwaccel $HWACCEL \
        -i "$input_file" $SAMPLE_DURATION_PARAMS $VIDEO_FILTER_OPTS -pix_fmt "$OUTPUT_PIX_FMT" \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -crf "$CRF_VALUE" -x265-params "$x265_params_crf" \
        $audio_params \
        $stream_mapping -f matroska \
        "$output_file" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log" | \
    awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" \
        -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
        -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="⚡" -v END_MSG="Terminé ✅" \
        "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"

    # CRITIQUE : capturer PIPESTATUS immédiatement après le pipeline
    local ffmpeg_rc=${PIPESTATUS[0]:-0}
    local awk_rc=${PIPESTATUS[1]:-0}

    if [[ "$ffmpeg_rc" -eq 0 && "$awk_rc" -eq 0 ]]; then
        return 0
    else
        # Ne pas afficher les logs si interruption volontaire (Ctrl+C)
        # Code 255 = signal reçu, 130 = SIGINT (128+2), 143 = SIGTERM (128+15)
        if [[ "${_INTERRUPTED:-0}" -ne 1 && "$ffmpeg_rc" -ne 255 && "$ffmpeg_rc" -lt 128 ]] && [[ -f "$ffmpeg_log" ]]; then
            echo "--- Dernières lignes du log ffmpeg ($ffmpeg_log) ---" >&2
            tail -n 80 "$ffmpeg_log" >&2 || true
            echo "--- Fin du log ffmpeg ---" >&2
        fi
        return 1
    fi
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

    # Chronos : début du traitement de ce fichier
    FILE_START_TS="$(date +%s)"
    START_TS="$FILE_START_TS"

    # Préparer les paramètres vidéo (adaptés à la résolution source)
    _setup_video_encoding_params "$tmp_input"
    
    # Préparer les paramètres du mode sample si activé
    _setup_sample_mode_params "$tmp_input" "$duration_secs"

    # Préparer les paramètres audio (copy ou conversion Opus)
    local audio_params
    audio_params=$(_build_audio_params "$tmp_input")

    # Préparer le mapping des streams (filtre sous-titres FR)
    local stream_mapping
    stream_mapping=$(_build_stream_mapping "$tmp_input")

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

    # Paramètres x265 de base (VBV + extra params du mode)
    local x265_base_params="${X265_VBV_STRING}"
    if [[ -n "${X265_EXTRA_PARAMS:-}" ]]; then
        x265_base_params="${x265_base_params}:${X265_EXTRA_PARAMS}"
    fi

    # ==================== CHOIX DU MODE D'ENCODAGE ====================
    if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
        # Mode single-pass CRF (séries uniquement)
        if ! _run_encoding_single_pass "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                       "$x265_base_params" "$audio_params" "$stream_mapping" \
                                       "$progress_slot" "$is_parallel" "$awk_time_func"; then
            if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
                release_progress_slot "$progress_slot"
            fi
            return 1
        fi
    else
        # Mode two-pass classique
        # ==================== PASS 1 : ANALYSE ====================
        if ! _run_encoding_pass1 "$tmp_input" "$ffmpeg_log_temp" "$base_name" \
                                 "$x265_base_params" "$progress_slot" "$is_parallel" "$awk_time_func"; then
            if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
                release_progress_slot "$progress_slot"
            fi
            return 1
        fi

        # ==================== PASS 2 : ENCODAGE ====================
        if ! _run_encoding_pass2 "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$base_name" \
                                 "$x265_base_params" "$audio_params" "$stream_mapping" \
                                 "$progress_slot" "$is_parallel" "$awk_time_func"; then
            # Nettoyer les fichiers de stats x265
            rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
            if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
                release_progress_slot "$progress_slot"
            fi
            return 1
        fi

        # Nettoyage fichiers two-pass
        rm -f "x265_2pass.log" "x265_2pass.log.cutree" 2>/dev/null || true
    fi

    # Libérer le slot de progression
    if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
        release_progress_slot "$progress_slot"
    fi

    return 0
}
