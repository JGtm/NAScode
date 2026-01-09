#!/bin/bash
###########################################################
# PARAMÈTRES VIDÉO (pix_fmt, downscale, bitrate)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
###########################################################

###########################################################
# API INTERNE (compat exports/tests)
#
# Ces fonctions (préfixées par _) étaient historiquement dans
# lib/transcode_video.sh et sont exportées via lib/exports.sh.
# On les centralise ici pour éviter les duplications.
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
# Format two-pass: _<codec>_<bitrate>k_<height>p_<preset>[_<audio_codec>][_sample]
# Format single-pass: _<codec>_crf<value>_<height>p_<preset>[_<audio_codec>][_sample]
# Usage: _build_effective_suffix_for_dims <width> <height> [input_file] [opt_audio_codec] [opt_audio_bitrate] [source_video_codec]
_build_effective_suffix_for_dims() {
    local src_width="$1"
    local src_height="$2"
    local input_file="${3:-}"
    local opt_audio_codec="${4:-}"
    local opt_audio_bitrate="${5:-}"
    local source_video_codec="${6:-}"

    # Suffixe basé sur le codec vidéo
    # Si source_video_codec est fourni et est supérieur ou égal au codec cible,
    # on utilise le codec source (cas video_passthrough)
    local codec_suffix="x265"
    local use_source_codec=false
    
    if [[ -n "$source_video_codec" ]] && is_codec_better_or_equal "$source_video_codec" "${VIDEO_CODEC:-hevc}"; then
        use_source_codec=true
    fi
    
    if [[ "$use_source_codec" == true ]]; then
        # Utiliser le codec source pour le suffixe
        codec_suffix=$(get_codec_suffix "$source_video_codec")
    else
        codec_suffix=$(get_codec_suffix "${VIDEO_CODEC:-hevc}")
    fi

    local suffix="_${codec_suffix}"

    # Résolution de sortie estimée (après downscale éventuel)
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$src_width" "$src_height")

    # Mode single-pass CRF ou two-pass bitrate
    if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
        # Calculer le CRF effectif selon l'encodeur
        local effective_crf="$CRF_VALUE"
        case "${VIDEO_ENCODER:-libx265}" in
            libsvtav1)
                if [[ -n "${SVTAV1_CRF:-}" ]]; then
                    effective_crf="$SVTAV1_CRF"
                elif [[ -n "${SVTAV1_CRF_DEFAULT:-}" ]]; then
                    effective_crf="$SVTAV1_CRF_DEFAULT"
                else
                    effective_crf=$(( CRF_VALUE + 9 ))
                fi
                [[ $effective_crf -gt 63 ]] && effective_crf=63
                ;;
            libaom-av1)
                effective_crf=$(( CRF_VALUE + 9 ))
                [[ $effective_crf -gt 63 ]] && effective_crf=63
                ;;
        esac
        suffix="${suffix}_crf${effective_crf}"
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

    # Indicateur du codec audio effectif (smart codec logic)
    local audio_suffix=""
    if [[ -n "$input_file" && -f "$input_file" ]] && declare -f _get_effective_audio_codec &>/dev/null; then
        audio_suffix=$(_get_effective_audio_codec "$input_file" "$opt_audio_codec" "$opt_audio_bitrate")
    else
        audio_suffix="${AUDIO_CODEC:-copy}"
    fi

    case "$audio_suffix" in
        copy|unknown|"")  ;;
        aac)   suffix="${suffix}_aac" ;;
        ac3)   suffix="${suffix}_ac3" ;;
        eac3)  suffix="${suffix}_eac3" ;;
        opus)  suffix="${suffix}_opus" ;;
        flac)  suffix="${suffix}_flac" ;;
        *)     suffix="${suffix}_${audio_suffix}" ;;
    esac

    if [[ "${SAMPLE_MODE:-false}" == true ]]; then
        suffix="${suffix}_sample"
    fi

    echo "$suffix"
}

###########################################################
# PIXEL FORMAT
###########################################################

# Détermine le pixel format de sortie.
# - Si la source est 10-bit (Main10 etc.), on garde du 10-bit (yuv420p10le)
# - Sinon on reste en 8-bit (yuv420p)
# Usage: select_output_pix_fmt <input_pix_fmt>
# Retourne: yuv420p ou yuv420p10le
select_output_pix_fmt() {
    _select_output_pix_fmt "$@"
}

###########################################################
# DOWNSCALE
###########################################################

# Construit le filtre vidéo (optionnel) pour limiter la résolution à 1080p.
# Usage: build_downscale_filter <width> <height>
# Retourne: chaîne vide si pas de downscale, sinon le filtre scale=...
build_downscale_filter() {
    _build_downscale_filter_if_needed "$@"
}

###########################################################
# CALCUL COMPLET DES PARAMÈTRES VIDÉO
###########################################################

# Calcule tous les paramètres vidéo pour un fichier donné.
# Usage: compute_video_params <input_file>
# Retourne: pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height
#
# Exemple: yuv420p10le|-vf scale=...|1449k|1764k|2646k|vbv-maxrate=1764:vbv-bufsize=2646|720
compute_video_params() {
    local input_file="$1"
    
    # Récupérer les propriétés du flux vidéo source
    local input_props
    input_props=$(get_video_stream_props "$input_file")
    local input_width input_height input_pix_fmt
    IFS='|' read -r input_width input_height input_pix_fmt <<< "$input_props"

    # Pixel format de sortie
    local output_pix_fmt
    output_pix_fmt=$(_select_output_pix_fmt "$input_pix_fmt")

    # Filtre de downscale si nécessaire
    local downscale_filter filter_opts=""
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")
    if [[ -n "$downscale_filter" ]]; then
        filter_opts="-vf $downscale_filter"
    fi

    # Calcul du bitrate adapté à la résolution de sortie
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$input_width" "$input_height")

    local effective_target effective_maxrate effective_bufsize
    effective_target=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
    effective_maxrate=$(_compute_effective_bitrate_kbps_for_height "${MAXRATE_KBPS}" "$output_height")
    effective_bufsize=$(_compute_effective_bitrate_kbps_for_height "${BUFSIZE_KBPS}" "$output_height")

    local video_bitrate="${effective_target}k"
    local video_maxrate="${effective_maxrate}k"
    local video_bufsize="${effective_bufsize}k"
    local vbv_string="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"

    # Retourner toutes les valeurs séparées par |
    echo "${output_pix_fmt}|${filter_opts}|${video_bitrate}|${video_maxrate}|${video_bufsize}|${vbv_string}|${output_height}|${input_width}|${input_height}|${input_pix_fmt}"
}

###########################################################
# CALCUL ADAPTATIF (MODE FILM-ADAPTIVE)
###########################################################

# Calcule les paramètres vidéo avec analyse de complexité.
# Usage: compute_video_params_adaptive <input_file>
# Retourne: pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height|input_width|input_height|input_pix_fmt|complexity_C|complexity_desc
#
# Cette fonction étend compute_video_params pour le mode film-adaptive :
# - Analyse la complexité du fichier (multi-échantillonnage)
# - Calcule un bitrate adapté au contenu
# - Applique les garde-fous (min/max, % du bitrate original)
compute_video_params_adaptive() {
    local input_file="$1"
    
    # Récupérer les métadonnées complètes
    local metadata
    metadata=$(get_full_media_metadata "$input_file")
    
    local video_bitrate_bps video_codec duration input_width input_height input_pix_fmt audio_codec audio_bitrate
    IFS='|' read -r video_bitrate_bps video_codec duration input_width input_height input_pix_fmt audio_codec audio_bitrate <<< "$metadata"
    
    # Pixel format de sortie
    local output_pix_fmt
    output_pix_fmt=$(_select_output_pix_fmt "$input_pix_fmt")

    # Filtre de downscale si nécessaire
    local downscale_filter filter_opts=""
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")
    if [[ -n "$downscale_filter" ]]; then
        filter_opts="-vf $downscale_filter"
    fi

    # Calcul de la hauteur de sortie (après downscale éventuel)
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$input_width" "$input_height")
    
    # Largeur de sortie estimée (pour le calcul BPP)
    local output_width="$input_width"
    if [[ -n "$downscale_filter" ]] && [[ -n "$output_height" ]]; then
        # Estimer la largeur proportionnellement
        if [[ "$input_height" -gt 0 ]]; then
            output_width=$(( input_width * output_height / input_height ))
            # Arrondir au multiple de 2
            output_width=$(( (output_width / 2) * 2 ))
        fi
    fi

    # Récupérer le FPS
    local fps
    fps=$(ffprobe_safe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$input_file" 2>/dev/null | head -1)
    
    # Convertir le FPS (format "24000/1001" ou "24")
    if [[ "$fps" == *"/"* ]]; then
        fps=$(awk -F/ '{if($2>0) printf "%.3f", $1/$2; else print $1}' <<< "$fps")
    fi
    [[ -z "$fps" ]] && fps="24"

    # Analyser la complexité (multi-échantillonnage avec progression)
    local stddev complexity_c complexity_desc
    stddev=$(analyze_video_complexity "$input_file" "$duration" true)
    complexity_c=$(_map_stddev_to_complexity "$stddev")
    complexity_desc=$(_describe_complexity "$complexity_c")

    # Calculer le bitrate adaptatif avec la formule BPP × C
    local effective_target effective_maxrate effective_bufsize
    effective_target=$(compute_adaptive_target_bitrate "$output_width" "$output_height" "$fps" "$complexity_c" "$video_bitrate_bps")
    effective_maxrate=$(compute_adaptive_maxrate "$effective_target")
    effective_bufsize=$(compute_adaptive_bufsize "$effective_target")

    local video_bitrate="${effective_target}k"
    local video_maxrate="${effective_maxrate}k"
    local video_bufsize="${effective_bufsize}k"
    local vbv_string="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"

    # Retourner toutes les valeurs séparées par | (format étendu)
    echo "${output_pix_fmt}|${filter_opts}|${video_bitrate}|${video_maxrate}|${video_bufsize}|${vbv_string}|${output_height}|${input_width}|${input_height}|${input_pix_fmt}|${complexity_c}|${complexity_desc}|${stddev}|${effective_target}"
}

###########################################################
# AFFICHAGE DES PARAMÈTRES (effet de bord volontaire)
###########################################################

# Affiche les informations de downscale/10-bit si applicable.
# Cette fonction a un effet de bord (echo vers stderr) mais c'est voulu pour l'UI.
# Usage: display_video_params_info <filter_opts> <output_pix_fmt> <input_pix_fmt> <input_width> <input_height>
display_video_params_info() {
    local filter_opts="$1"
    local output_pix_fmt="$2"
    local input_pix_fmt="$3"
    local input_width="$4"
    local input_height="$5"
    
    if [[ "$NO_PROGRESS" == true ]]; then
        return 0
    fi
    
    if [[ -n "$filter_opts" ]]; then
        echo -e "${CYAN}  ⬇️  Downscale activé : ${input_width}x${input_height} → Max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
    fi
    
    if [[ -n "$input_pix_fmt" ]] && [[ "$output_pix_fmt" == "yuv420p10le" ]]; then
        echo -e "${CYAN}  🎨 Sortie 10-bit activée${NOCOLOR}"
    fi
}
