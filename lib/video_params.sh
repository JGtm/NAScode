#!/bin/bash
###########################################################
# PARAMÈTRES VIDÉO (pix_fmt, downscale, bitrate)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
###########################################################

###########################################################
# PIXEL FORMAT
###########################################################

# Détermine le pixel format de sortie.
# - Si la source est 10-bit (Main10 etc.), on garde du 10-bit (yuv420p10le)
# - Sinon on reste en 8-bit (yuv420p)
# Usage: select_output_pix_fmt <input_pix_fmt>
# Retourne: yuv420p ou yuv420p10le
select_output_pix_fmt() {
    local input_pix_fmt="$1"
    local out_pix_fmt="yuv420p"

    # Heuristique simple et robuste : les pix_fmt 10-bit contiennent généralement "10".
    # Ex: yuv420p10le, yuv422p10le, yuv444p10le
    if [[ "$input_pix_fmt" == *"10"* ]]; then
        out_pix_fmt="yuv420p10le"
    fi

    echo "$out_pix_fmt"
}

###########################################################
# DOWNSCALE
###########################################################

# Construit le filtre vidéo (optionnel) pour limiter la résolution à 1080p.
# Usage: build_downscale_filter <width> <height>
# Retourne: chaîne vide si pas de downscale, sinon le filtre scale=...
build_downscale_filter() {
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
# CALCUL HAUTEUR DE SORTIE
###########################################################

# Estime la hauteur de sortie après application éventuelle du downscale 1080p.
# Usage: compute_output_height <src_width> <src_height>
# Retourne: hauteur estimée (vide si entrées invalides)
compute_output_height() {
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

###########################################################
# ADAPTATION BITRATE PAR RÉSOLUTION
###########################################################

# Calcule un bitrate effectif (kbps) selon la hauteur de sortie estimée.
# Usage: compute_effective_bitrate <base_kbps> <output_height>
# Retourne: bitrate adapté en kbps
compute_effective_bitrate() {
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
    output_pix_fmt=$(select_output_pix_fmt "$input_pix_fmt")

    # Filtre de downscale si nécessaire
    local downscale_filter filter_opts=""
    downscale_filter=$(build_downscale_filter "$input_width" "$input_height")
    if [[ -n "$downscale_filter" ]]; then
        filter_opts="-vf $downscale_filter"
    fi

    # Calcul du bitrate adapté à la résolution de sortie
    local output_height
    output_height=$(compute_output_height "$input_width" "$input_height")

    local effective_target effective_maxrate effective_bufsize
    effective_target=$(compute_effective_bitrate "${TARGET_BITRATE_KBPS}" "$output_height")
    effective_maxrate=$(compute_effective_bitrate "${MAXRATE_KBPS}" "$output_height")
    effective_bufsize=$(compute_effective_bitrate "${BUFSIZE_KBPS}" "$output_height")

    local video_bitrate="${effective_target}k"
    local video_maxrate="${effective_maxrate}k"
    local video_bufsize="${effective_bufsize}k"
    local vbv_string="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"

    # Retourner toutes les valeurs séparées par |
    echo "${output_pix_fmt}|${filter_opts}|${video_bitrate}|${video_maxrate}|${video_bufsize}|${vbv_string}|${output_height}|${input_width}|${input_height}|${input_pix_fmt}"
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
        echo -e "${CYAN}  ⬇️  Downscale activé : ${input_width}x${input_height} → max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
    fi
    
    if [[ -n "$input_pix_fmt" ]] && [[ "$output_pix_fmt" == "yuv420p10le" ]]; then
        echo -e "${CYAN}  🎨 Sortie 10-bit activée (source: $input_pix_fmt)${NOCOLOR}"
    fi
}
