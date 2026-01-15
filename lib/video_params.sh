#!/bin/bash
###########################################################
# PARAMÈTRES VIDÉO (pix_fmt, downscale, bitrate)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les fonctions retournent des chaînes vides ou des
#    valeurs par défaut en cas d'entrée invalide
# 3. Les modules sont sourcés, pas exécutés directement
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

    # Profil 480p/SD : réduction plus agressive pour contenus basse résolution
    if [[ "$output_height" -le "${ADAPTIVE_480P_MAX_HEIGHT:-480}" ]]; then
        local scale_percent="${ADAPTIVE_480P_SCALE_PERCENT:-50}"
        if [[ -z "$scale_percent" ]] || ! [[ "$scale_percent" =~ ^[0-9]+$ ]] || [[ "$scale_percent" -le 0 ]]; then
            echo "$base_kbps"
            return 0
        fi
        # Arrondi au plus proche
        echo $(( (base_kbps * scale_percent + 50) / 100 ))
        return 0
    fi

    # Profil 720p : réduction modérée
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
# Format (Option A): _<codec>_<height>p[_<AUDIO>][_sample]
# Usage: _build_effective_suffix_for_dims <width> <height> [input_file] [opt_audio_codec] [opt_audio_bitrate] [source_video_codec]

_suffix_select_video_codec_suffix() {
    local source_video_codec="$1"

    # Suffixe basé sur le codec vidéo
    # Si source_video_codec est fourni et est supérieur ou égal au codec cible,
    # on utilise le codec source (cas video_passthrough)
    local codec_suffix="x265"
    local use_source_codec=false

    if [[ -n "$source_video_codec" ]] && is_codec_better_or_equal "$source_video_codec" "${VIDEO_CODEC:-hevc}"; then
        use_source_codec=true
    fi

    if [[ "$use_source_codec" == true ]]; then
        codec_suffix=$(get_codec_suffix "$source_video_codec")
    else
        codec_suffix=$(get_codec_suffix "${VIDEO_CODEC:-hevc}")
    fi

    echo "$codec_suffix"
}

_suffix_build_quality_part() {
    local output_height="$1"

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
        echo "_crf${effective_crf}"
        return 0
    fi

    local effective_bitrate_kbps
    effective_bitrate_kbps=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
    if [[ -n "$effective_bitrate_kbps" ]] && [[ "$effective_bitrate_kbps" =~ ^[0-9]+$ ]]; then
        echo "_${effective_bitrate_kbps}k"
    else
        echo "_${TARGET_BITRATE_KBPS}k"
    fi
}

_suffix_build_resolution_part() {
    local output_height="$1"

    if [[ -n "$output_height" ]] && [[ "$output_height" =~ ^[0-9]+$ ]]; then
        echo "_${output_height}p"
    else
        echo ""
    fi
}

_suffix_get_audio_codec() {
    local input_file="$1"
    local opt_audio_codec="$2"
    local opt_audio_bitrate="$3"

    if [[ -n "$input_file" && -f "$input_file" ]] && declare -f _get_effective_audio_codec &>/dev/null; then
        _get_effective_audio_codec "$input_file" "$opt_audio_codec" "$opt_audio_bitrate"
    else
        echo "${AUDIO_CODEC:-copy}"
    fi
}

_suffix_build_audio_part() {
    local audio_codec="$1"

    case "$audio_codec" in
        copy|unknown|"")  echo "" ;;
        *)     echo "_${audio_codec^^}" ;;
    esac
}

_suffix_build_sample_part() {
    if [[ "${SAMPLE_MODE:-false}" == true ]]; then
        echo "_sample"
    else
        echo ""
    fi
}

_build_effective_suffix_for_dims() {
    local src_width="$1"
    local src_height="$2"
    local input_file="${3:-}"
    local opt_audio_codec="${4:-}"
    local opt_audio_bitrate="${5:-}"
    local source_video_codec="${6:-}"

    local codec_suffix
    codec_suffix=$(_suffix_select_video_codec_suffix "$source_video_codec")

    local suffix="_${codec_suffix}"

    # Résolution de sortie estimée (après downscale éventuel)
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$src_width" "$src_height")

    suffix="${suffix}$(_suffix_build_resolution_part "$output_height")"

    local audio_codec
    audio_codec=$(_suffix_get_audio_codec "$input_file" "$opt_audio_codec" "$opt_audio_bitrate")
    suffix="${suffix}$(_suffix_build_audio_part "$audio_codec")"
    suffix="${suffix}$(_suffix_build_sample_part)"

    echo "$suffix"
}

###########################################################
# GESTION HFR (High Frame Rate)
###########################################################

# Récupère le FPS d'un fichier vidéo.
# Usage: _get_video_fps <input_file>
# Retourne: FPS en décimal (ex: 23.976, 29.97, 59.94)
_get_video_fps() {
    local input_file="$1"
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
    
    echo "$fps"
}

# Vérifie si un FPS est considéré comme HFR (High Frame Rate).
# Usage: _is_hfr <fps>
# Retourne: 0 (true) si HFR, 1 (false) sinon
_is_hfr() {
    local fps="$1"
    local threshold="${HFR_THRESHOLD_FPS:-30}"
    
    awk -v fps="$fps" -v t="$threshold" 'BEGIN { exit (fps > t ? 0 : 1) }'
}

# Calcule le facteur de majoration bitrate pour HFR.
# Usage: _compute_hfr_bitrate_factor <fps>
# Retourne: facteur (ex: 1.0, 1.5, 2.0)
_compute_hfr_bitrate_factor() {
    local fps="$1"
    local ref="${HFR_REFERENCE_FPS:-30}"
    
    # Si FPS <= seuil, pas de majoration
    if ! _is_hfr "$fps"; then
        echo "1.0"
        return 0
    fi
    
    # Facteur = fps / référence
    awk -v fps="$fps" -v ref="$ref" 'BEGIN { printf "%.2f", fps / ref }'
}

# Applique la majoration HFR à un bitrate.
# Usage: _apply_hfr_bitrate_adjustment <base_kbps> <fps>
# Retourne: bitrate ajusté (kbps)
_apply_hfr_bitrate_adjustment() {
    local base_kbps="$1"
    local fps="$2"
    
    local factor
    factor=$(_compute_hfr_bitrate_factor "$fps")
    
    awk -v base="$base_kbps" -v f="$factor" 'BEGIN { printf "%.0f", base * f }'
}

# Construit le filtre FPS si limitation activée.
# Usage: _build_fps_limit_filter <fps>
# Retourne: filtre "fps=29.97" ou chaîne vide
_build_fps_limit_filter() {
    local fps="$1"
    local target="${LIMIT_FPS_TARGET:-29.97}"
    
    # Si limitation désactivée ou FPS <= seuil, pas de filtre
    if [[ "${LIMIT_FPS:-false}" != true ]]; then
        echo ""
        return 0
    fi
    
    if ! _is_hfr "$fps"; then
        echo ""
        return 0
    fi
    
    echo "fps=${target}"
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
# Retourne: pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height|input_width|input_height|input_pix_fmt|source_fps|output_fps
#
# Exemple: yuv420p10le|-vf scale=...|1449k|1764k|2646k|vbv-maxrate=1764:vbv-bufsize=2646|720|1920|1080|yuv420p|59.94|29.97
compute_video_params() {
    local input_file="$1"
    
    # Récupérer les propriétés du flux vidéo source
    local input_props
    input_props=$(get_video_stream_props "$input_file")
    local input_width input_height input_pix_fmt
    IFS='|' read -r input_width input_height input_pix_fmt <<< "$input_props"

    # Récupérer le FPS source
    local source_fps
    source_fps=$(_get_video_fps "$input_file")
    local output_fps="$source_fps"

    # Pixel format de sortie
    local output_pix_fmt
    output_pix_fmt=$(_select_output_pix_fmt "$input_pix_fmt")

    # Construire les filtres vidéo
    local filters=()
    
    # Filtre de downscale si nécessaire
    local downscale_filter
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")
    if [[ -n "$downscale_filter" ]]; then
        filters+=("$downscale_filter")
    fi
    
    # Filtre de limitation FPS si activé et HFR détecté
    local fps_filter
    fps_filter=$(_build_fps_limit_filter "$source_fps")
    if [[ -n "$fps_filter" ]]; then
        filters+=("$fps_filter")
        output_fps="${LIMIT_FPS_TARGET:-29.97}"
        # Marquer que le FPS a été limité (pour UI et VMAF)
        export FPS_WAS_LIMITED=true
        export FPS_ORIGINAL="$source_fps"
    fi
    
    # Construire l'option -vf si des filtres sont présents
    local filter_opts=""
    if [[ ${#filters[@]} -gt 0 ]]; then
        local IFS=','
        filter_opts="-vf ${filters[*]}"
    fi

    # Calcul du bitrate adapté à la résolution de sortie
    local output_height
    output_height=$(_compute_output_height_for_bitrate "$input_width" "$input_height")

    local effective_target effective_maxrate effective_bufsize
    effective_target=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
    effective_maxrate=$(_compute_effective_bitrate_kbps_for_height "${MAXRATE_KBPS}" "$output_height")
    effective_bufsize=$(_compute_effective_bitrate_kbps_for_height "${BUFSIZE_KBPS}" "$output_height")
    
    # Si HFR et pas de limitation FPS → majorer le bitrate
    if [[ "${LIMIT_FPS:-false}" != true ]] && _is_hfr "$source_fps"; then
        effective_target=$(_apply_hfr_bitrate_adjustment "$effective_target" "$source_fps")
        effective_maxrate=$(_apply_hfr_bitrate_adjustment "$effective_maxrate" "$source_fps")
        effective_bufsize=$(_apply_hfr_bitrate_adjustment "$effective_bufsize" "$source_fps")
        # Marquer pour l'UI
        export HFR_BITRATE_ADJUSTED=true
        export HFR_FACTOR=$(_compute_hfr_bitrate_factor "$source_fps")
    fi

    local video_bitrate="${effective_target}k"
    local video_maxrate="${effective_maxrate}k"
    local video_bufsize="${effective_bufsize}k"
    local vbv_string="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"

    # Retourner toutes les valeurs séparées par |
    echo "${output_pix_fmt}|${filter_opts}|${video_bitrate}|${video_maxrate}|${video_bufsize}|${vbv_string}|${output_height}|${input_width}|${input_height}|${input_pix_fmt}|${source_fps}|${output_fps}"
}

###########################################################
# CALCUL ADAPTATIF (MODE ADAPTATIF)
###########################################################

# Calcule les paramètres vidéo avec analyse de complexité.
# Usage: compute_video_params_adaptive <input_file>
# Retourne: pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height|input_width|input_height|input_pix_fmt|complexity_C|complexity_desc
#
# Cette fonction étend compute_video_params pour le mode adaptatif :
# - Analyse la complexité du fichier (multi-échantillonnage)
# - Calcule un bitrate adapté au contenu
# - Applique les garde-fous (min/max, % du bitrate original)
compute_video_params_adaptive() {
    local input_file="$1"
    
    # Récupérer les métadonnées complètes
    local metadata
    metadata=$(get_full_media_metadata "$input_file")
    
    local video_bitrate_bps _video_codec duration input_width input_height input_pix_fmt audio_codec _audio_bitrate
    IFS='|' read -r video_bitrate_bps _video_codec duration input_width input_height input_pix_fmt audio_codec _audio_bitrate <<< "$metadata"
    
    # Récupérer le FPS source (utiliser le helper)
    local source_fps
    source_fps=$(_get_video_fps "$input_file")
    local output_fps="$source_fps"
    
    # Pixel format de sortie
    local output_pix_fmt
    output_pix_fmt=$(_select_output_pix_fmt "$input_pix_fmt")

    # Construire les filtres vidéo
    local filters=()
    
    # Filtre de downscale si nécessaire
    local downscale_filter
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")
    if [[ -n "$downscale_filter" ]]; then
        filters+=("$downscale_filter")
    fi
    
    # Filtre de limitation FPS si activé explicitement (rare en mode adaptatif)
    local fps_filter
    fps_filter=$(_build_fps_limit_filter "$source_fps")
    if [[ -n "$fps_filter" ]]; then
        filters+=("$fps_filter")
        output_fps="${LIMIT_FPS_TARGET:-29.97}"
        export FPS_WAS_LIMITED=true
        export FPS_ORIGINAL="$source_fps"
    fi
    
    # Construire l'option -vf si des filtres sont présents
    local filter_opts=""
    if [[ ${#filters[@]} -gt 0 ]]; then
        local IFS=','
        filter_opts="-vf ${filters[*]}"
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

    # Analyser la complexité (multi-échantillonnage avec progression)
    # Retourne: stddev|SI|TI
    local analysis_result stddev si_avg ti_avg
    analysis_result=$(analyze_video_complexity "$input_file" "$duration" true)
    IFS='|' read -r stddev si_avg ti_avg <<< "$analysis_result"
    
    # Calculer le coefficient C avec les 3 métriques
    local complexity_c complexity_desc
    complexity_c=$(_map_metrics_to_complexity "$stddev" "$si_avg" "$ti_avg")
    complexity_desc=$(_describe_complexity "$complexity_c")

    # Calculer le bitrate adaptatif avec la formule BPP × C
    # Utiliser output_fps (après limitation éventuelle) pour le calcul
    local effective_target effective_maxrate effective_bufsize
    effective_target=$(compute_adaptive_target_bitrate "$output_width" "$output_height" "$output_fps" "$complexity_c" "$video_bitrate_bps")
    effective_maxrate=$(compute_adaptive_maxrate "$effective_target")
    effective_bufsize=$(compute_adaptive_bufsize "$effective_target")

    local video_bitrate="${effective_target}k"
    local video_maxrate="${effective_maxrate}k"
    local video_bufsize="${effective_bufsize}k"
    local vbv_string="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"

    # Retourner toutes les valeurs séparées par | (format étendu avec SI/TI)
    echo "${output_pix_fmt}|${filter_opts}|${video_bitrate}|${video_maxrate}|${video_bufsize}|${vbv_string}|${output_height}|${input_width}|${input_height}|${input_pix_fmt}|${complexity_c}|${complexity_desc}|${stddev}|${effective_target}|${si_avg}|${ti_avg}"
}

###########################################################
# AFFICHAGE DES PARAMÈTRES (effet de bord volontaire)
###########################################################

# Affiche les informations de downscale/10-bit/HFR si applicable.
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
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "${CYAN}  ⬇️  Downscale activé : ${input_width}x${input_height} → Max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
        else
            echo -e "${CYAN}  ⬇️  Downscale activé : ${input_width}x${input_height} → Max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
        fi
    fi
    
    if [[ -n "$input_pix_fmt" ]] && [[ "$output_pix_fmt" == "yuv420p10le" ]]; then
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "${CYAN}  🎨 Sortie 10-bit activée${NOCOLOR}"
        else
            echo -e "${CYAN}  🎨 Sortie 10-bit activée${NOCOLOR}"
        fi
    fi
    
    # Afficher info HFR : limitation FPS ou majoration bitrate
    if [[ "${FPS_WAS_LIMITED:-false}" == true ]]; then
        local msg="${CYAN}  📽️  FPS limité (${FPS_ORIGINAL} → ${LIMIT_FPS_TARGET:-29.97} fps)${NOCOLOR}"
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "$msg"
        else
            echo -e "$msg"
        fi
    elif [[ "${HFR_BITRATE_ADJUSTED:-false}" == true ]]; then
        local msg="${CYAN}  📽️  HFR détecté (${FPS_ORIGINAL:-?} fps) → bitrate ajusté ×${HFR_FACTOR:-?}${NOCOLOR}"
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "$msg"
        else
            echo -e "$msg"
        fi
    fi
}
