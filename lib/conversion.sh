#!/bin/bash
###########################################################
# LOGIQUE DE SKIP ET CONVERSION
###########################################################

# Modes de conversion possibles (retournés par _determine_conversion_mode)
# - "skip"             : fichier ignoré (vidéo conforme, audio OK ou mode copy)
# - "video_passthrough": vidéo copiée, seul l'audio est converti
# - "full"             : conversion complète (vidéo + audio)
CONVERSION_ACTION=""

# Codec vidéo effectivement utilisé pour l'encodage (peut différer de VIDEO_CODEC
# si la source est dans un codec supérieur et qu'on applique une politique
# "no downgrade" : ré-encodage dans le même codec pour limiter le bitrate).
EFFECTIVE_VIDEO_CODEC=""
EFFECTIVE_VIDEO_ENCODER=""
EFFECTIVE_ENCODER_MODE_PARAMS=""

# Contexte du dernier calcul de seuil (utile pour l'UX).
SKIP_THRESHOLD_CODEC=""                 # codec dans lequel on compare le bitrate
SKIP_THRESHOLD_MAXRATE_KBPS=""           # maxrate (kbps) dans le codec de comparaison
SKIP_THRESHOLD_MAX_TOLERATED_BITS=""     # seuil final (bits) après tolérance
SKIP_THRESHOLD_TOLERANCE_PERCENT=""      # tolérance appliquée

# Variable pour stocker le numéro de fichier courant (pour affichage [X/Y])
CURRENT_FILE_NUMBER=0

# En mode limite (-l), afficher un compteur “slot en cours” 1-based pour l'UX.
# Le slot est réservé de façon atomique (mutex) uniquement quand on sait
# qu'on ne va PAS skip le fichier (y compris après analyse adaptative).
# Il reste stable pendant tout le traitement du fichier.
LIMIT_DISPLAY_SLOT=0

# Génère le préfixe [X/Y] pour les messages si le compteur est disponible
# Usage: _get_counter_prefix
# - Avec limite (-l) : affiche [slot/LIMIT] (commence à 1)
# - Sans limite : affiche [X/Y] avec le total réel
# Retourne une chaîne vide si pas de compteur actif
_get_counter_prefix() {
    local current_num="${CURRENT_FILE_NUMBER:-0}"
    local total_num="${TOTAL_FILES_TO_PROCESS:-0}"
    local limit="${LIMIT_FILES:-0}"

    # Mode random : le "total" est déjà la sélection (ex: 10 fichiers).
    # UX attendue : compteur de position [X/Y], pas une logique de slot/limite.
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        if [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
            echo "${DIM}[${current_num}/${total_num}]${NOCOLOR} "
        fi
        return
    fi
    
    # Mode limite : afficher [slot/LIMIT] uniquement si un slot a été réservé.
    if [[ "$limit" -gt 0 ]]; then
        local slot="${LIMIT_DISPLAY_SLOT:-0}"
        if [[ "$slot" =~ ^[0-9]+$ ]] && [[ "$slot" -gt 0 ]]; then
            echo "${DIM}[${slot}/${limit}]${NOCOLOR} "
        elif [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
            # Fallback (ex: film-adaptive) : le slot est réservé après l'analyse,
            # mais on veut un compteur visible dès le démarrage.
            echo "${DIM}[${current_num}/${total_num}]${NOCOLOR} "
        fi
        return
    fi
    
    # Mode normal : afficher [current/total]
    if [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
        echo "${DIM}[${current_num}/${total_num}]${NOCOLOR} "
    fi
}

# Détermine le mode de conversion à appliquer pour un fichier.
# Usage: _determine_conversion_mode <codec> <bitrate> <filename> <file_original> [opt_audio_codec] [opt_audio_bitrate] [adaptive_maxrate_kbps]
# Définit CONVERSION_ACTION et retourne 0 si une action est nécessaire, 1 si skip total
# Note: adaptive_maxrate_kbps est utilisé en mode film-adaptive pour le seuil de skip
_determine_conversion_mode() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    local opt_audio_codec="${5:-}"
    local opt_audio_bitrate="${6:-}"
    local adaptive_maxrate_kbps="${7:-}"
    
    CONVERSION_ACTION=""
    
    # --- Validation fichier vidéo ---
    if [[ -z "$codec" ]]; then
        CONVERSION_ACTION="skip"
        return 1
    fi
    
    # Reset (pour éviter d'exposer des infos obsolètes)
    EFFECTIVE_VIDEO_CODEC=""
    EFFECTIVE_VIDEO_ENCODER=""
    EFFECTIVE_ENCODER_MODE_PARAMS=""
    SKIP_THRESHOLD_CODEC=""
    SKIP_THRESHOLD_MAXRATE_KBPS=""
    SKIP_THRESHOLD_MAX_TOLERATED_BITS=""
    SKIP_THRESHOLD_TOLERANCE_PERCENT=""

    # Calcul dynamique du seuil de skip
    # En mode film-adaptive, on utilise le maxrate adaptatif calculé pour ce fichier
    # Sinon on utilise le MAXRATE_KBPS global
    local effective_maxrate_kbps="${MAXRATE_KBPS:-0}"
    local skip_tolerance_percent="${SKIP_TOLERANCE_PERCENT:-10}"

    # Robustesse: si un module a modifié ces valeurs de façon inattendue
    if [[ ! "$effective_maxrate_kbps" =~ ^[0-9]+$ ]]; then
        effective_maxrate_kbps=0
    fi
    if [[ ! "$skip_tolerance_percent" =~ ^[0-9]+$ ]]; then
        skip_tolerance_percent=10
    fi
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]] && [[ -n "$adaptive_maxrate_kbps" ]] && [[ "$adaptive_maxrate_kbps" =~ ^[0-9]+$ ]]; then
        effective_maxrate_kbps="$adaptive_maxrate_kbps"
    fi

    # Codec cible (config) et comparaison codec-aware
    local target_codec="${VIDEO_CODEC:-hevc}"
    local compare_codec="$target_codec"

    # Détecter si le fichier est déjà encodé dans un codec "meilleur ou égal" au codec cible
    local is_better_or_equal_codec=false
    if is_codec_better_or_equal "$codec" "$target_codec"; then
        is_better_or_equal_codec=true
        compare_codec="$codec"
    fi

    # Si la source est dans un codec supérieur/égal, traduire le seuil dans l'espace
    # du codec source (ex: seuil HEVC -> seuil AV1) pour comparer "à qualité équivalente".
    # C'est plus conservateur (on skip moins souvent) quand la source est plus efficace.
    local compare_maxrate_kbps="$effective_maxrate_kbps"
    if [[ "$is_better_or_equal_codec" == true ]] && [[ -n "$compare_codec" ]] && [[ "$compare_codec" != "$target_codec" ]]; then
        if declare -f translate_bitrate_kbps_between_codecs &>/dev/null; then
            compare_maxrate_kbps=$(translate_bitrate_kbps_between_codecs "$effective_maxrate_kbps" "$target_codec" "$compare_codec")
        fi
    fi

    if [[ -z "$compare_maxrate_kbps" ]] || ! [[ "$compare_maxrate_kbps" =~ ^[0-9]+$ ]]; then
        compare_maxrate_kbps="$effective_maxrate_kbps"
    fi

    local base_threshold_bits=$((compare_maxrate_kbps * 1000))
    local tolerance_bits=$((compare_maxrate_kbps * skip_tolerance_percent * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))

    # Exposer le contexte du seuil pour l'UX
    SKIP_THRESHOLD_CODEC="$compare_codec"
    SKIP_THRESHOLD_MAXRATE_KBPS="$compare_maxrate_kbps"
    SKIP_THRESHOLD_MAX_TOLERATED_BITS="$max_tolerated_bits"
    SKIP_THRESHOLD_TOLERANCE_PERCENT="$skip_tolerance_percent"

    # Option --force-video : bypass smart (ne pas skip la vidéo)
    if [[ "${FORCE_VIDEO_CODEC:-false}" == true ]]; then
        is_better_or_equal_codec=false
    fi
    
    # Vidéo conforme (bon codec + bitrate optimisé) ?
    local video_is_ok=false
    if [[ "$is_better_or_equal_codec" == true ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            video_is_ok=true
        fi
    fi
    
    if [[ "$video_is_ok" == true ]]; then
        # Vidéo OK - vérifier si l'audio peut être optimisé
        # On passe les métadonnées audio si disponibles pour éviter un nouveau probe
        if declare -f _should_convert_audio &>/dev/null && _should_convert_audio "$file_original" "$opt_audio_codec" "$opt_audio_bitrate"; then
            # Audio à optimiser → mode passthrough vidéo
            CONVERSION_ACTION="video_passthrough"
            return 0
        else
            # Audio OK aussi → skip complet
            CONVERSION_ACTION="skip"
            return 1
        fi
    fi
    
    # Vidéo non conforme → conversion complète
    CONVERSION_ACTION="full"

    # Politique no-downgrade : si la source est dans un codec supérieur, on ré-encode
    # dans le même codec pour plafonner le bitrate (sauf --force-video).
    EFFECTIVE_VIDEO_CODEC="$target_codec"
    if [[ "${FORCE_VIDEO_CODEC:-false}" != true ]]; then
        local source_rank target_rank
        source_rank=$(get_codec_rank "$codec")
        target_rank=$(get_codec_rank "$target_codec")
        if [[ -n "$source_rank" && -n "$target_rank" ]] && [[ "$source_rank" =~ ^[0-9]+$ ]] && [[ "$target_rank" =~ ^[0-9]+$ ]]; then
            if [[ "$source_rank" -gt "$target_rank" ]]; then
                EFFECTIVE_VIDEO_CODEC="$codec"
            fi
        fi
    fi

    if [[ -n "$EFFECTIVE_VIDEO_CODEC" ]] && declare -f get_codec_encoder &>/dev/null; then
        EFFECTIVE_VIDEO_ENCODER=$(get_codec_encoder "$EFFECTIVE_VIDEO_CODEC")
        if declare -f get_encoder_mode_params &>/dev/null; then
            EFFECTIVE_ENCODER_MODE_PARAMS=$(get_encoder_mode_params "$EFFECTIVE_VIDEO_ENCODER" "${ENCODER_MODE_PROFILE:-${CONVERSION_MODE:-serie}}")
        fi
    fi
    return 0
}

should_skip_conversion() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    local opt_audio_codec="${5:-}"
    local opt_audio_bitrate="${6:-}"
    
    # Déterminer le mode de conversion (sans seuil adaptatif)
    _determine_conversion_mode "$codec" "$bitrate" "$filename" "$file_original" "$opt_audio_codec" "$opt_audio_bitrate" ""
    
    # Affichage et logging selon le mode
    _display_skip_decision "$codec" "$filename" "$file_original"
    
    # Retourner 0 si skip, 1 sinon (sémantique shell : 0=succès=skip)
    [[ "$CONVERSION_ACTION" == "skip" ]] && return 0 || return 1
}

# Version avec support du seuil adaptatif pour le mode film-adaptive
# Usage: should_skip_conversion_adaptive <codec> <bitrate> <filename> <file_original> [audio_codec] [audio_bitrate] [adaptive_maxrate_kbps]
should_skip_conversion_adaptive() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    local opt_audio_codec="${5:-}"
    local opt_audio_bitrate="${6:-}"
    local adaptive_maxrate_kbps="${7:-}"
    
    # Déterminer le mode de conversion avec le seuil adaptatif si fourni
    _determine_conversion_mode "$codec" "$bitrate" "$filename" "$file_original" "$opt_audio_codec" "$opt_audio_bitrate" "$adaptive_maxrate_kbps"
    
    # Affichage et logging selon le mode
    _display_skip_decision "$codec" "$filename" "$file_original"
    
    # Retourner 0 si skip, 1 sinon (sémantique shell : 0=succès=skip)
    [[ "$CONVERSION_ACTION" == "skip" ]] && return 0 || return 1
}

# Affichage et logging de la décision de skip (factorisation)
_display_skip_decision() {
    local codec="$1"
    local filename="$2"
    local file_original="$3"
    
    local counter_prefix=$(_get_counter_prefix)
    case "$CONVERSION_ACTION" in
        "skip")
            if [[ -z "$codec" ]]; then
                echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}" >&2
                if [[ -n "$LOG_SESSION" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
                fi
            else
                local codec_display="${codec^^}"
                [[ "$codec" == "hevc" || "$codec" == "h265" ]] && codec_display="X265"
                local skip_msg="Déjà ${codec_display} & bitrate optimisé"
                # En mode adaptatif, préciser que c'est par rapport au seuil adaptatif
                if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]]; then
                    skip_msg="Déjà ${codec_display} & bitrate ≤ seuil adaptatif"
                fi
                echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (${skip_msg}) : $filename${NOCOLOR}" >&2
                if [[ -n "$LOG_SESSION" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (${skip_msg}) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
                fi
            fi
            ;;
        "video_passthrough")
            # Log discret - le message visible sera affiché après le transfert
            if [[ -n "$LOG_PROGRESS" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | VIDEO_PASSTHROUGH | Audio à optimiser | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
            fi
            ;;
        "full")
            # Détecter si le fichier est dans un codec meilleur/égal mais avec bitrate trop élevé
            local target_codec="${VIDEO_CODEC:-hevc}"
            local is_better_or_equal=false
            is_codec_better_or_equal "$codec" "$target_codec" && is_better_or_equal=true
            
            if [[ "$is_better_or_equal" == true && -n "$LOG_PROGRESS" ]]; then
                local codec_display="${codec^^}"
                [[ "$codec" == "hevc" || "$codec" == "h265" ]] && codec_display="X265"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage ${codec_display}) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
            fi
            ;;
    esac
}

###########################################################
# SOUS-FONCTIONS DE PRE-CONVERSION
###########################################################

_prepare_file_paths() {
    local file_original="$1"
    local output_dir="$2"
    local opt_width="${3:-}"
    local opt_height="${4:-}"
    local opt_audio_codec="${5:-}"
    local opt_audio_bitrate="${6:-}"
    local source_video_codec="${7:-}"
    
    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
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

    # Suffixe effectif (par fichier) : inclut bitrate adapté + résolution + codec audio effectif.
    # Fallback : si les fonctions ne sont pas chargées (tests/unitaires), on garde SUFFIX_STRING.
    local effective_suffix="$SUFFIX_STRING"
    
    # Si un suffixe personnalisé est forcé via -S "valeur", on l'utilise tel quel
    if [[ "${SUFFIX_MODE:-ask}" == custom:* ]]; then
        effective_suffix="${SUFFIX_MODE#custom:}"
    elif [[ -n "$SUFFIX_STRING" ]] && declare -f _build_effective_suffix_for_dims &>/dev/null; then
        local input_width="$opt_width"
        local input_height="$opt_height"
        
        # Si pas de dimensions fournies, on probe (fallback)
        if [[ -z "$input_width" || -z "$input_height" ]] && declare -f get_video_stream_props &>/dev/null; then
            local stream_props
            stream_props=$(get_video_stream_props "$file_original")
            local _pix_fmt
            IFS='|' read -r input_width input_height _pix_fmt <<< "$stream_props"
        fi
        
        # Passer le fichier original pour déterminer le codec audio effectif (smart codec)
        # Passer aussi le codec vidéo source pour utiliser le bon suffixe en cas de passthrough
        effective_suffix=$(_build_effective_suffix_for_dims "$input_width" "$input_height" "$file_original" "$opt_audio_codec" "$opt_audio_bitrate" "$source_video_codec")
    fi

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
        local counter_prefix=$(_get_counter_prefix)
        echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (Fichier de sortie déjà existant) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
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
    local print_start="${4:-true}"
    local log_start="${5:-true}"
    
    mkdir -p "$final_dir" 2>/dev/null || true
    if [[ "$print_start" == true ]] && [[ "$NO_PROGRESS" != true ]] && [[ "${UI_QUIET:-false}" != true ]]; then
        echo ""
        local counter_str=$(_get_counter_prefix)
        echo -e "${counter_str}▶️ Démarrage du fichier : $filename"
    fi
    if [[ "$log_start" == true ]] && [[ -n "$LOG_PROGRESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
    fi
}

_check_disk_space() {
    local file_original="$1"
    
    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}' 2>/dev/null) || return 0
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
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
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_transfer_item "$filename"
    else
        if [[ "${UI_QUIET:-false}" != true ]]; then
            echo -e "${CYAN}→ $filename${NOCOLOR}"
        fi
    fi

    if ! custom_pv "$file_original" "$tmp_input" "$CYAN"; then
        print_error "ERREUR Impossible de déplacer (custom_pv) : $file_original"
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR custom_pv copy failed | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null
        return 1
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_transfer_item_end
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

_convert_get_full_metadata() {
    local file_original="$1"

    # Format attendu:
    # video_bitrate|video_codec|duration|width|height|pix_fmt|audio_codec|audio_bitrate
    if declare -f get_full_media_metadata &>/dev/null; then
        get_full_media_metadata "$file_original"
        return 0
    fi

    # Fallback (pour tests ou si fonction manquante)
    local v_meta
    v_meta=$(get_video_metadata "$file_original")
    local v_props
    v_props=$(get_video_stream_props "$file_original")

    local v_bitrate v_codec duration_secs
    IFS='|' read -r v_bitrate v_codec duration_secs <<< "$v_meta"

    local v_width v_height v_pix_fmt
    IFS='|' read -r v_width v_height v_pix_fmt <<< "$v_props"

    # Audio probe séparé
    local a_info
    a_info=$(_get_audio_conversion_info "$file_original")
    local a_codec a_bitrate _
    IFS='|' read -r a_codec a_bitrate _ <<< "$a_info"

    echo "${v_bitrate}|${v_codec}|${duration_secs}|${v_width}|${v_height}|${v_pix_fmt}|${a_codec}|${a_bitrate}"
}

_convert_run_adaptive_analysis_and_export() {
    local file_to_analyze="$1"

    local adaptive_params
    adaptive_params=$(compute_video_params_adaptive "$file_to_analyze")

    # Format:
    # pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height|input_width|input_height|input_pix_fmt|complexity_C|complexity_desc|stddev|target_kbps
    local _pix _flt _br _mr _bs _vbv _oh _iw _ih _ipf
    local complexity_c complexity_desc stddev_val adaptive_target_kbps
    IFS='|' read -r _pix _flt _br _mr _bs _vbv _oh _iw _ih _ipf complexity_c complexity_desc stddev_val adaptive_target_kbps <<< "$adaptive_params"

    local adaptive_maxrate_kbps adaptive_bufsize_kbps
    adaptive_maxrate_kbps="${_mr%k}"
    adaptive_bufsize_kbps="${_bs%k}"

    # Traduire les bitrates "référence HEVC" vers le codec cible actif.
    # Cela rend film-adaptive cohérent quand VIDEO_CODEC != hevc.
    local target_codec="${VIDEO_CODEC:-hevc}"
    if [[ "$target_codec" != "hevc" ]] && declare -f translate_bitrate_kbps_between_codecs &>/dev/null; then
        adaptive_target_kbps=$(translate_bitrate_kbps_between_codecs "$adaptive_target_kbps" "hevc" "$target_codec")
        adaptive_maxrate_kbps=$(translate_bitrate_kbps_between_codecs "$adaptive_maxrate_kbps" "hevc" "$target_codec")
        adaptive_bufsize_kbps=$(translate_bitrate_kbps_between_codecs "$adaptive_bufsize_kbps" "hevc" "$target_codec")
    fi

    # Afficher l'analyse de complexité
    # Note: appelé dans des $(...) ; on force l'affichage sur stderr.
    # Note UX: expliquer pourquoi on analyse.
    if [[ "${UI_QUIET:-false}" != true ]]; then
        echo -e "${DIM}  🔎 Mode film-adaptive : analyse de complexité pour déterminer le bitrate/seuil${NOCOLOR}" >&2
    fi

    display_complexity_analysis "$file_to_analyze" "$complexity_c" "$complexity_desc" "$stddev_val" "$adaptive_target_kbps" >&2

    # Stocker les paramètres adaptatifs dans des variables d'environnement
    export ADAPTIVE_TARGET_KBPS="$adaptive_target_kbps"
    export ADAPTIVE_MAXRATE_KBPS="$adaptive_maxrate_kbps"
    export ADAPTIVE_BUFSIZE_KBPS="$adaptive_bufsize_kbps"

    echo "${adaptive_target_kbps}|${adaptive_maxrate_kbps}|${adaptive_bufsize_kbps}|${complexity_c}|${complexity_desc}|${stddev_val}"
}

_convert_display_adaptive_decision_required() {
    local v_codec="$1"
    local v_bitrate_bits="$2"

    [[ "${UI_QUIET:-false}" == true ]] && return 0
    [[ "${NO_PROGRESS:-false}" == true ]] && return 0

    local counter_prefix=$(_get_counter_prefix)

    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        echo -e "${counter_prefix}${CYAN}✅ Conversion requise : audio à optimiser (vidéo conservée)${NOCOLOR}" >&2
        return 0
    fi

    if [[ ! "$v_bitrate_bits" =~ ^[0-9]+$ ]] || [[ "$v_bitrate_bits" -le 0 ]]; then
        echo -e "${counter_prefix}${CYAN}✅ Conversion requise${NOCOLOR}" >&2
        return 0
    fi

    local src_kbps=$(( v_bitrate_bits / 1000 ))
    local threshold_bits="${SKIP_THRESHOLD_MAX_TOLERATED_BITS:-0}"
    local threshold_kbps=0
    if [[ "$threshold_bits" =~ ^[0-9]+$ ]] && [[ "$threshold_bits" -gt 0 ]]; then
        threshold_kbps=$(( threshold_bits / 1000 ))
    fi

    local cmp_codec="${SKIP_THRESHOLD_CODEC:-$v_codec}"
    local cmp_display="${cmp_codec^^}"
    [[ "$cmp_codec" == "hevc" || "$cmp_codec" == "h265" ]] && cmp_display="X265"

    local effective_codec="${EFFECTIVE_VIDEO_CODEC:-${VIDEO_CODEC:-hevc}}"
    local target_codec="${VIDEO_CODEC:-hevc}"

    if [[ -n "$threshold_kbps" && "$threshold_kbps" -gt 0 ]]; then
        if [[ "$effective_codec" != "$target_codec" ]]; then
            echo -e "${counter_prefix}${CYAN}✅ Conversion requise : ${src_kbps}k > seuil ${threshold_kbps}k (${cmp_display}) → pas de downgrade (encodage ${effective_codec^^})${NOCOLOR}" >&2
        else
            echo -e "${counter_prefix}${CYAN}✅ Conversion requise : ${src_kbps}k > seuil ${threshold_kbps}k (${cmp_display})${NOCOLOR}" >&2
        fi
    else
        echo -e "${counter_prefix}${CYAN}✅ Conversion requise${NOCOLOR}" >&2
    fi
}

# Gère le mode adaptatif : analyse, skip post-analyse, réservation slot.
# Usage: _convert_handle_adaptive_mode <tmp_input> <v_codec> <v_bitrate> <filename> <file_original> <a_codec> <a_bitrate> <final_dir>
# Retourne: 0 si on continue, 1 si skip (fichier temporaire nettoyé)
# Effets de bord: définit LIMIT_DISPLAY_SLOT, exporte ADAPTIVE_*_KBPS
_convert_handle_adaptive_mode() {
    local tmp_input="$1"
    local v_codec="$2"
    local v_bitrate="$3"
    local filename="$4"
    local file_original="$5"
    local a_codec="$6"
    local a_bitrate="$7"
    local final_dir="$8"

    # Note UX: en mode adaptatif, le "Démarrage" est affiché avant le transfert
    # (aligné avec les autres modes). Ici, on évite d'imprimer une 2e fois.

    local adaptive_info
    adaptive_info=$(_convert_run_adaptive_analysis_and_export "$tmp_input")

    local adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps
    local complexity_c complexity_desc stddev_val
    IFS='|' read -r adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps complexity_c complexity_desc stddev_val <<< "$adaptive_info"

    # Vérifier si on peut skip maintenant qu'on a le seuil adaptatif
    if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" "$adaptive_maxrate_kbps"; then
        rm -f "$tmp_input" 2>/dev/null || true
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            call_if_exists update_queue || true
        fi
        call_if_exists increment_processed_count || true
        return 1
    fi

    _convert_display_adaptive_decision_required "$v_codec" "$v_bitrate"

    # Réserver le slot limite après l'analyse (évite les slots "gâchés")
    if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
        local _slot
        _slot=$(call_if_exists increment_converted_count) || _slot="0"
        if [[ "$_slot" =~ ^[0-9]+$ ]] && [[ "$_slot" -gt 0 ]]; then
            LIMIT_DISPLAY_SLOT="$_slot"
        fi
    fi

    # Log de démarrage (sans ré-afficher la ligne déjà imprimée avant l'analyse)
    _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir" false true
    return 0
}

# Affiche les messages informatifs avant la conversion (codec, bitrate, downscale/10-bit, audio).
# Usage: _convert_display_info_messages <v_codec> <tmp_input> <v_width> <v_height> <v_pix_fmt> <a_codec> <a_bitrate>
# Effets de bord: echo vers stdout
_convert_display_info_messages() {
    local v_codec="$1"
    local tmp_input="$2"
    local v_width="${3:-}"
    local v_height="${4:-}"
    local v_pix_fmt="${5:-}"
    local a_codec="${6:-}"
    local a_bitrate="${7:-}"

    [[ "$NO_PROGRESS" == true ]] && return 0

    local codec_display="${v_codec^^}"
    [[ "$v_codec" == "hevc" || "$v_codec" == "h265" ]] && codec_display="X265"
    [[ "$v_codec" == "av1" ]] && codec_display="AV1"

    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        echo -e "${CYAN}  📋 Codec vidéo déjà optimisé → Conversion audio seule${NOCOLOR}"
    else
        local target_codec="${VIDEO_CODEC:-hevc}"
        if is_codec_better_or_equal "$v_codec" "$target_codec"; then
            echo -e "${CYAN}  🎯 Codec ${codec_display} optimal → Limitation du bitrate${NOCOLOR}"
        fi
    fi

    # Option B : afficher downscale + 10-bit AVANT lancement FFmpeg (centralisé ici)
    # (Uniquement si on encode la vidéo ; pas en passthrough vidéo)
    if [[ "${CONVERSION_ACTION:-full}" != "video_passthrough" ]]; then
        if declare -f _build_downscale_filter_if_needed &>/dev/null; then
            local downscale_filter
            downscale_filter=$(_build_downscale_filter_if_needed "$v_width" "$v_height")
            if [[ -n "$downscale_filter" ]]; then
                echo -e "${CYAN}  ⬇️  Downscale activé : ${v_width}x${v_height} → Max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
                VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=true
            fi
        fi

        if declare -f _select_output_pix_fmt &>/dev/null; then
            local output_pix_fmt
            output_pix_fmt=$(_select_output_pix_fmt "$v_pix_fmt")
            if [[ -n "$v_pix_fmt" && "$output_pix_fmt" == "yuv420p10le" ]]; then
                echo -e "${CYAN}  🎨 Sortie 10-bit activée${NOCOLOR}"
                VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=true
            fi
        fi
    fi

    # Probe canaux audio (une fois) sur le fichier local
    local channels=""
    if declare -f _probe_audio_channels &>/dev/null; then
        local channel_info
        channel_info=$(_probe_audio_channels "$tmp_input")
        channels=$(echo "$channel_info" | cut -d'|' -f1)
    fi

    # Info audio multicanal : afficher en série ET en film, avec wording cohérent.
    if [[ -n "$channels" && "$channels" =~ ^[0-9]+$ ]] && declare -f _is_audio_multichannel &>/dev/null; then
        if _is_audio_multichannel "$channels"; then
            if [[ "${AUDIO_FORCE_STEREO:-false}" == true ]]; then
                echo -e "${CYAN}  🔊 Audio multicanal (${channels}ch) → Downmix stéréo${NOCOLOR}"
            else
                if [[ "$channels" -gt 6 ]]; then
                    echo -e "${CYAN}  🔊 Audio multicanal (${channels}ch) → Downmix 7.1 → 5.1${NOCOLOR}"
                else
                    echo -e "${CYAN}  🔊 Audio multicanal 5.1 (${channels}ch) → Layout conservé (pas de downmix stéréo)${NOCOLOR}"
                fi
            fi
        fi
    fi

    # Option 2A : résumé audio effectif (uniquement si utile)
    if declare -f _get_smart_audio_decision &>/dev/null && [[ -n "$channels" && "$channels" =~ ^[0-9]+$ ]]; then
        local audio_decision action effective_codec target_bitrate reason
        audio_decision=$(_get_smart_audio_decision "$tmp_input" "$a_codec" "$a_bitrate" "$channels")
        IFS='|' read -r action effective_codec target_bitrate reason <<< "$audio_decision"

        local show_audio_summary=false
        if [[ "$action" != "copy" ]]; then
            show_audio_summary=true
        elif [[ "${AUDIO_FORCE_STEREO:-false}" == true && "$channels" -ge 6 ]]; then
            show_audio_summary=true
        fi

        if [[ "$show_audio_summary" == true ]]; then
            local layout=""
            if declare -f _get_target_audio_layout &>/dev/null; then
                layout=$(_get_target_audio_layout "$channels")
            else
                if [[ "${AUDIO_FORCE_STEREO:-false}" == true ]]; then
                    layout="stereo"
                else
                    layout=$([[ "$channels" -ge 6 ]] && echo "5.1" || echo "stereo")
                fi
            fi

            local codec_label="${effective_codec^^}"
            [[ "$effective_codec" == "eac3" ]] && codec_label="EAC3"
            [[ "$effective_codec" == "aac" ]] && codec_label="AAC"
            [[ "$effective_codec" == "opus" ]] && codec_label="OPUS"

            if [[ -n "$target_bitrate" && "$target_bitrate" =~ ^[0-9]+$ ]] && [[ "$target_bitrate" -gt 0 ]]; then
                echo -e "${CYAN}  🎧 Conversion audio vers ${codec_label} ${target_bitrate}k (${layout})${NOCOLOR}"
            else
                echo -e "${CYAN}  🎧 Conversion audio vers ${codec_label} (${layout})${NOCOLOR}"
            fi
        fi
    fi
}

convert_file() {
    set -o pipefail

    local file_original="$1"
    # Windows/Git Bash : normaliser les CRLF
    file_original="${file_original//$'\r'/}"
    local output_dir="$2"
    
    # Compteurs initiaux
    CURRENT_FILE_NUMBER=$(call_if_exists increment_starting_counter) || CURRENT_FILE_NUMBER=0
    LIMIT_DISPLAY_SLOT=0
    VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=false
    
    # 1. Récupérer TOUTES les métadonnées en un seul appel
    local full_metadata
    full_metadata=$(_convert_get_full_metadata "$file_original")
    
    local v_bitrate v_codec duration_secs v_width v_height v_pix_fmt a_codec a_bitrate
    IFS='|' read -r v_bitrate v_codec duration_secs v_width v_height v_pix_fmt a_codec a_bitrate <<< "$full_metadata"
    
    # 2. Préparation des chemins
    local path_info
    path_info=$(_prepare_file_paths "$file_original" "$output_dir" "$v_width" "$v_height" "$a_codec" "$a_bitrate" "$v_codec") || return 1
    
    IFS='|' read -r filename final_dir base_name effective_suffix final_output <<< "$path_info"
    
    # 3. Vérifications standard (skip rapide)
    if _check_output_exists "$file_original" "$filename" "$final_output"; then
        call_if_exists increment_processed_count || true
        return 0
    fi
    
    if _handle_dryrun_mode "$final_dir" "$final_output"; then
        call_if_exists increment_processed_count || true
        return 0
    fi
    
    local tmp_input=$(_get_temp_filename "$file_original" ".in")
    local tmp_output=$(_get_temp_filename "$file_original" ".out.mkv")
    local ffmpeg_log_temp=$(_get_temp_filename "$file_original" "_err.log")
    
    # 4. Décision de conversion (mode non-adaptatif : skip possible ici)
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" != true ]]; then
        if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" ""; then
            [[ "$LIMIT_FILES" -gt 0 ]] && call_if_exists update_queue || true
            call_if_exists increment_processed_count || true
            return 0
        fi
        # Réserver le slot limite
        if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
            local _slot
            _slot=$(call_if_exists increment_converted_count) || _slot="0"
            [[ "$_slot" =~ ^[0-9]+$ && "$_slot" -gt 0 ]] && LIMIT_DISPLAY_SLOT="$_slot"
        fi
        _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    else
        # Mode adaptatif : analyse AVANT transfert pour calculer le seuil adaptatif
        # et décider du skip sans télécharger inutilement.
        mkdir -p "$final_dir" 2>/dev/null || true

        local adaptive_info
        adaptive_info=$(_convert_run_adaptive_analysis_and_export "$file_original")

        local adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps
        local complexity_c complexity_desc stddev_val
        IFS='|' read -r adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps complexity_c complexity_desc stddev_val <<< "$adaptive_info"

        # Skip avec seuil adaptatif (avant transfert)
        if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" "$adaptive_maxrate_kbps"; then
            [[ "$LIMIT_FILES" -gt 0 ]] && call_if_exists update_queue || true
            call_if_exists increment_processed_count || true
            return 0
        fi

        _convert_display_adaptive_decision_required "$v_codec" "$v_bitrate"

        # Réserver le slot limite après l'analyse (évite les slots "gâchés")
        if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
            local _slot
            _slot=$(call_if_exists increment_converted_count) || _slot="0"
            [[ "$_slot" =~ ^[0-9]+$ && "$_slot" -gt 0 ]] && LIMIT_DISPLAY_SLOT="$_slot"
        fi

        # Maintenant qu'on sait qu'on ne skip pas : démarrage + log START (comme les autres modes)
        _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    fi

    _check_disk_space "$file_original" || return 1
    
    local size_before_mb=$(du -m "$file_original" | awk '{print $1}')
    
    # 5. Téléchargement vers stockage temporaire
    _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp" || return 1
    
    # 6. Mode adaptatif : analyse/skip/slot déjà traités avant transfert.
    
    # 7. Messages informatifs
    _convert_display_info_messages "$v_codec" "$tmp_input" "$v_width" "$v_height" "$v_pix_fmt" "$a_codec" "$a_bitrate"
    
    # 8. Exécution de la conversion
    local conversion_success=false
    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        _execute_video_passthrough "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name" && conversion_success=true
    else
        _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name" && conversion_success=true
    fi
    
    # 9. Finalisation
    if [[ "$conversion_success" == true ]]; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$size_before_mb"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi
    
    call_if_exists increment_processed_count || true
}
