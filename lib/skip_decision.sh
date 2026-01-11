#!/bin/bash
###########################################################
# LOGIQUE DE DÉCISION SKIP / PASSTHROUGH / FULL
# Détermine si un fichier doit être converti ou ignoré
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

###########################################################
# FONCTION PRINCIPALE DE DÉCISION
###########################################################

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

###########################################################
# WRAPPERS PUBLICS
###########################################################

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
    print_skip_message "$codec" "$filename" "$file_original"
    
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
    print_skip_message "$codec" "$filename" "$file_original"
    
    # Retourner 0 si skip, 1 sinon (sémantique shell : 0=succès=skip)
    [[ "$CONVERSION_ACTION" == "skip" ]] && return 0 || return 1
}
