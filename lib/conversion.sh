#!/bin/bash
###########################################################
# LOGIQUE DE SKIP ET CONVERSION
###########################################################

# Modes de conversion possibles (retournés par _determine_conversion_mode)
# - "skip"             : fichier ignoré (vidéo conforme, audio OK ou mode copy)
# - "video_passthrough": vidéo copiée, seul l'audio est converti
# - "full"             : conversion complète (vidéo + audio)
CONVERSION_ACTION=""

# Variable pour stocker le numéro de fichier courant (pour affichage [X/Y])
CURRENT_FILE_NUMBER=0

# Génère le préfixe [X/Y] pour les messages si le compteur est disponible
# Usage: _get_counter_prefix
# - Avec limite (-l) : affiche [converted/LIMIT] (commence à 0)
# - Sans limite : affiche [X/Y] avec le total réel
# Retourne une chaîne vide si pas de compteur actif
_get_counter_prefix() {
    local current_num="${CURRENT_FILE_NUMBER:-0}"
    local total_num="${TOTAL_FILES_TO_PROCESS:-0}"
    local limit="${LIMIT_FILES:-0}"
    
    # Mode limite : afficher [converted/LIMIT]
    if [[ "$limit" -gt 0 ]]; then
        local converted=0
        if declare -f get_converted_count &>/dev/null; then
            converted=$(get_converted_count)
        fi
        echo "${DIM}[${converted}/${limit}]${NOCOLOR} "
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
    
    # Calcul dynamique du seuil de skip
    # En mode film-adaptive, on utilise le maxrate adaptatif calculé pour ce fichier
    # Sinon on utilise le MAXRATE_KBPS global
    local effective_maxrate_kbps="${MAXRATE_KBPS}"
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]] && [[ -n "$adaptive_maxrate_kbps" ]] && [[ "$adaptive_maxrate_kbps" =~ ^[0-9]+$ ]]; then
        effective_maxrate_kbps="$adaptive_maxrate_kbps"
    fi
    
    local base_threshold_bits=$((effective_maxrate_kbps * 1000))
    local tolerance_bits=$((effective_maxrate_kbps * SKIP_TOLERANCE_PERCENT * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))
    
    # Détecter si le fichier est déjà encodé dans un codec "meilleur ou égal" au codec cible
    local target_codec="${VIDEO_CODEC:-hevc}"
    local is_better_or_equal_codec=false
    
    if is_codec_better_or_equal "$codec" "$target_codec"; then
        is_better_or_equal_codec=true
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
    
    mkdir -p "$final_dir" 2>/dev/null || true
    if [[ "$NO_PROGRESS" != true ]]; then
        echo ""
        local counter_str=$(_get_counter_prefix)
        echo -e "▶️  ${counter_str}Démarrage du fichier : $filename"
    fi
    if [[ -n "$LOG_PROGRESS" ]]; then
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
        echo -e "${CYAN}→ $filename${NOCOLOR}"
    fi

    if ! custom_pv "$file_original" "$tmp_input" "$CYAN"; then
        echo -e "${RED}❌ ERREUR Impossible de déplacer (custom_pv) : $file_original${NOCOLOR}"
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

convert_file() {
    set -o pipefail

    local file_original="$1"
    local output_dir="$2"
    
    # Incrémenter le compteur de fichiers au tout début (pour affichage [X/Y])
    # Cette variable sera utilisée par tous les messages (skips inclus)
    CURRENT_FILE_NUMBER=0
    if declare -f increment_starting_counter &>/dev/null; then
        CURRENT_FILE_NUMBER=$(increment_starting_counter)
    fi
    
    # 1. Optimisation : Récupérer TOUTES les métadonnées en un seul appel
    # Format: video_bitrate|video_codec|duration|width|height|pix_fmt|audio_codec|audio_bitrate
    local full_metadata
    if declare -f get_full_media_metadata &>/dev/null; then
        full_metadata=$(get_full_media_metadata "$file_original")
    else
        # Fallback (pour tests ou si fonction manquante)
        local v_meta=$(get_video_metadata "$file_original")
        local v_props=$(get_video_stream_props "$file_original")
        local v_bitrate v_codec duration_secs
        IFS='|' read -r v_bitrate v_codec duration_secs <<< "$v_meta"
        local v_width v_height v_pix_fmt
        IFS='|' read -r v_width v_height v_pix_fmt <<< "$v_props"
        # Audio probe séparé
        local a_info=$(_get_audio_conversion_info "$file_original")
        local a_codec a_bitrate _
        IFS='|' read -r a_codec a_bitrate _ <<< "$a_info"
        full_metadata="${v_bitrate}|${v_codec}|${duration_secs}|${v_width}|${v_height}|${v_pix_fmt}|${a_codec}|${a_bitrate}"
    fi
    
    local v_bitrate v_codec duration_secs v_width v_height v_pix_fmt a_codec a_bitrate
    IFS='|' read -r v_bitrate v_codec duration_secs v_width v_height v_pix_fmt a_codec a_bitrate <<< "$full_metadata"
    
    # 2. Préparation des chemins (avec métadonnées pour suffixe)
    local path_info
    path_info=$(_prepare_file_paths "$file_original" "$output_dir" "$v_width" "$v_height" "$a_codec" "$a_bitrate" "$v_codec") || return 1
    
    IFS='|' read -r filename final_dir base_name effective_suffix final_output <<< "$path_info"
    
    # 3. Vérifications standard
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
    
    # 4. Analyse adaptative (mode film-adaptive uniquement)
    # Variables pour stocker les paramètres adaptatifs calculés
    local adaptive_target_kbps="" adaptive_maxrate_kbps="" adaptive_bufsize_kbps=""
    local complexity_c="" complexity_desc="" stddev_val=""
    
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]]; then
        # Calculer les paramètres adaptatifs pour ce fichier
        local adaptive_params
        adaptive_params=$(compute_video_params_adaptive "$file_original")
        
        # Format: pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height|input_width|input_height|input_pix_fmt|complexity_C|complexity_desc|stddev|target_kbps
        local _pix _flt _br _mr _bs _vbv _oh _iw _ih _ipf
        IFS='|' read -r _pix _flt _br _mr _bs _vbv _oh _iw _ih _ipf complexity_c complexity_desc stddev_val adaptive_target_kbps <<< "$adaptive_params"
        
        # Extraire le maxrate adaptatif (enlever le 'k' si présent)
        adaptive_maxrate_kbps="${_mr%k}"
        adaptive_bufsize_kbps="${_bs%k}"
        
        # Afficher l'analyse de complexité (avant la décision de skip)
        if [[ "$NO_PROGRESS" != true ]]; then
            display_complexity_analysis "$file_original" "$complexity_c" "$complexity_desc" "$stddev_val" "$adaptive_target_kbps"
        fi
        
        # Stocker les paramètres adaptatifs dans des variables d'environnement
        # pour qu'ils soient utilisés par _execute_conversion
        export ADAPTIVE_TARGET_KBPS="$adaptive_target_kbps"
        export ADAPTIVE_MAXRATE_KBPS="$adaptive_maxrate_kbps"
        export ADAPTIVE_BUFSIZE_KBPS="$adaptive_bufsize_kbps"
    fi
    
    # 5. Décision de conversion (avec métadonnées et seuil adaptatif si applicable)
    if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" "$adaptive_maxrate_kbps"; then
        # Alimenter la queue avec le prochain candidat si limite active
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue || true
        fi
        increment_processed_count || true
        return 0
    fi
    
    local size_before_mb=$(du -m "$file_original" | awk '{print $1}')
    
    # Incrémenter le compteur de fichiers réellement convertis (UX mode limite)
    # Ce compteur n'est incrémenté que si on va vraiment convertir (pas sur skip)
    if declare -f increment_converted_count &>/dev/null; then
        increment_converted_count >/dev/null
    fi
    
    _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp" || return 1
    
    # Afficher les messages informatifs après le transfert, avant la conversion
    if [[ "$NO_PROGRESS" != true ]]; then
        local codec_display="${v_codec^^}"
        [[ "$v_codec" == "hevc" || "$v_codec" == "h265" ]] && codec_display="X265"
        [[ "$v_codec" == "av1" ]] && codec_display="AV1"
        
        if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
            # Mode passthrough : vidéo conservée, seul l'audio sera converti
            echo -e "${CYAN}  📋 Codec vidéo déjà optimisé → conversion audio seule${NOCOLOR}"
        else
            # Mode full : vérifier si le codec source est meilleur/égal à la cible
            local target_codec="${VIDEO_CODEC:-hevc}"
            if is_codec_better_or_equal "$v_codec" "$target_codec"; then
                # Le codec source est efficace mais le bitrate est trop élevé
                local target_display="${target_codec^^}"
                [[ "$target_codec" == "hevc" || "$target_codec" == "h265" ]] && target_display="X265"
                echo -e "${CYAN}  🎯 Codec ${codec_display} optimal → limitation du bitrate${NOCOLOR}"
            fi
        fi
    fi
    
    # Choix du mode de conversion selon CONVERSION_ACTION (défini par should_skip_conversion)
    local conversion_success=false
    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        # Mode passthrough : vidéo copiée, seul l'audio est converti
        if _execute_video_passthrough "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
            conversion_success=true
        fi
    else
        # Mode standard : conversion complète (vidéo + audio)
        if _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
            conversion_success=true
        fi
    fi
    
    if [[ "$conversion_success" == true ]]; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$size_before_mb"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi
    
    # Incrémenter le compteur de fichiers traités (signal pour le FIFO writer)
    increment_processed_count || true
}
