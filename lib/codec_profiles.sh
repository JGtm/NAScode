#!/bin/bash
###########################################################
# PROFILS DE CODECS ET ENCODEURS
# 
# Architecture modulaire pour supporter plusieurs codecs
# vidéo (HEVC, AV1, etc.) avec leurs encodeurs respectifs.
#
# Note: Utilise des fonctions case au lieu de tableaux associatifs
# pour compatibilité avec Git Bash (subshells).
#
# Usage:
#   get_codec_encoder "$VIDEO_CODEC"     -> encodeur par défaut
#   get_codec_ffmpeg_name "$VIDEO_CODEC" -> nom ffmpeg du codec
#   build_encoder_params ...             -> paramètres encodeur
###########################################################

# ----- Variables globales codec (initialisées par défaut) -----
VIDEO_CODEC="${VIDEO_CODEC:-hevc}"      # Codec cible : hevc, av1
VIDEO_ENCODER=""                         # Encodeur (auto si vide)

# ----- Réglages par défaut AV1 (SVT-AV1) -----
# Ces valeurs ne sont pas "en dur" dans la commande FFmpeg : elles sont configurables
# via variables (lib/config.sh ou export environnement) et utilisées lors de la
# construction des options.
SVTAV1_TUNE_DEFAULT="${SVTAV1_TUNE_DEFAULT:-0}"
SVTAV1_ENABLE_OVERLAYS_DEFAULT="${SVTAV1_ENABLE_OVERLAYS_DEFAULT:-1}"
SVTAV1_PRESET_DEFAULT="${SVTAV1_PRESET_DEFAULT:-8}"
SVTAV1_CRF_DEFAULT="${SVTAV1_CRF_DEFAULT:-32}"

###########################################################
# FONCTIONS D'ACCÈS AUX PROFILS
###########################################################

# Retourne l'encodeur par défaut pour un codec donné
# Usage: get_codec_encoder "hevc" -> "libx265"
get_codec_encoder() {
    local codec="${1:-hevc}"
    case "$codec" in
        hevc)  echo "libx265" ;;
        av1)   echo "libsvtav1" ;;
        *)     echo "libx265" ;;  # Fallback sécurisé
    esac
}

# Retourne le suffixe de fichier pour un codec
# Usage: get_codec_suffix "av1" -> "av1"
get_codec_suffix() {
    local codec="${1:-hevc}"
    case "$codec" in
        hevc)  echo "x265" ;;
        av1)   echo "av1" ;;
        *)     echo "x265" ;;  # Fallback
    esac
}

# Retourne les noms FFmpeg reconnus pour un codec (pour skip)
# Usage: get_codec_ffmpeg_names "hevc" -> "hevc h265"
get_codec_ffmpeg_names() {
    local codec="${1:-hevc}"
    case "$codec" in
        hevc)  echo "hevc h265" ;;
        av1)   echo "av1" ;;
        *)     echo "" ;;
    esac
}

# Vérifie si un codec source correspond au codec cible
# Usage: is_codec_match "hevc" "hevc" -> 0 (true)
#        is_codec_match "h265" "hevc" -> 0 (true)
is_codec_match() {
    local source_codec="$1"
    local target_codec="$2"
    local known_names
    known_names=$(get_codec_ffmpeg_names "$target_codec")
    
    for name in $known_names; do
        if [[ "$source_codec" == "$name" ]]; then
            return 0
        fi
    done
    return 1
}

# Vérifie si un codec est supporté
# Usage: is_codec_supported "av1" -> 0 (true)
is_codec_supported() {
    local codec="$1"
    case "$codec" in
        hevc|av1) return 0 ;;
        *)        return 1 ;;
    esac
}

# Retourne le "rang" d'un codec (plus élevé = plus moderne/meilleur)
# Utilisé pour déterminer si un fichier est déjà dans un codec "meilleur"
# Usage: get_codec_rank "av1" -> 2, get_codec_rank "hevc" -> 1
get_codec_rank() {
    local codec="$1"
    case "$codec" in
        av1)   echo 2 ;;   # Plus moderne, meilleur ratio qualité/taille
        hevc)  echo 1 ;;   # Standard actuel
        h265)  echo 1 ;;   # Alias HEVC
        *)     echo 0 ;;   # Non-supporté (h264, etc.)
    esac
}

# Vérifie si un codec source est "meilleur ou égal" au codec cible
# Un fichier AV1 ne devrait pas être ré-encodé en HEVC
# Usage: is_codec_better_or_equal "av1" "hevc" -> 0 (true, AV1 >= HEVC)
#        is_codec_better_or_equal "hevc" "av1" -> 1 (false, HEVC < AV1)
is_codec_better_or_equal() {
    local source_codec="$1"
    local target_codec="$2"
    
    local source_rank target_rank
    source_rank=$(get_codec_rank "$source_codec")
    target_rank=$(get_codec_rank "$target_codec")
    
    [[ "$source_rank" -ge "$target_rank" ]]
}

# Liste les codecs supportés
# Usage: list_supported_codecs -> "hevc av1"
list_supported_codecs() {
    echo "hevc av1"
}

###########################################################
# PARAMÈTRES ENCODEUR PAR MODE (serie/film)
###########################################################

# Retourne les paramètres encodeur spécifiques au mode
# Usage: get_encoder_mode_params "libx265" "serie"
get_encoder_mode_params() {
    local encoder="$1"
    local mode="${2:-serie}"
    
    case "$encoder" in
        libx265)
            case "$mode" in
                # Séries : optimisations vitesse/qualité pour contenu série
                serie) echo "amp=0:rect=0:sao=0:strong-intra-smoothing=0:limit-refs=3:subme=2" ;;
                # Films : défauts x265 (qualité max)
                film)  echo "" ;;
                *)     echo "" ;;
            esac
            ;;
        libsvtav1)
            case "$mode" in
                # Séries : preset rapide, grain synthétique désactivé
                serie) echo "tune=${SVTAV1_TUNE_DEFAULT}:enable-overlays=${SVTAV1_ENABLE_OVERLAYS_DEFAULT}" ;;
                # Films : qualité max, film grain preservation
                film)  echo "tune=${SVTAV1_TUNE_DEFAULT}:enable-overlays=${SVTAV1_ENABLE_OVERLAYS_DEFAULT}:film-grain=8:film-grain-denoise=0" ;;
                *)     echo "" ;;
            esac
            ;;
        libaom-av1)
            echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

# Retourne le préfixe pour les paramètres encodeur (-x265-params, etc.)
# Usage: get_encoder_params_flag "libx265" -> "-x265-params"
get_encoder_params_flag() {
    local encoder="$1"
    case "$encoder" in
        libx265)    echo "-x265-params" ;;
        libsvtav1)  echo "-svtav1-params" ;;
        libaom-av1) echo "" ;;  # libaom utilise des options directes
        *)          echo "" ;;
    esac
}

# Construit la chaîne complète des paramètres encodeur
# Usage: build_encoder_params "libx265" "serie" "vbv-maxrate=2520:vbv-bufsize=3780"
# Retourne: "vbv-maxrate=2520:vbv-bufsize=3780:amp=0:rect=0:..."
build_encoder_params() {
    local encoder="$1"
    local mode="$2"
    local base_params="$3"  # VBV params, etc.
    
    local mode_params
    mode_params=$(get_encoder_mode_params "$encoder" "$mode")
    
    local result="$base_params"
    if [[ -n "$mode_params" ]]; then
        if [[ -n "$result" ]]; then
            result="${result}:${mode_params}"
        else
            result="$mode_params"
        fi
    fi
    
    echo "$result"
}

# Construit l'option -tune pour FFmpeg (si applicable)
# Usage: build_tune_option "libx265" "serie" -> "-tune fastdecode"
build_tune_option() {
    local encoder="$1"
    local mode="$2"
    
    # Seul x265 utilise -tune fastdecode en mode option
    if [[ "$encoder" == "libx265" ]]; then
        case "$mode" in
            serie) echo "-tune fastdecode" ;;
            film)  echo "" ;;
            *)     echo "" ;;
        esac
    else
        echo ""
    fi
}

# Retourne le keyint (GOP) pour le mode courant
# Usage: get_mode_keyint "film" -> 240
get_mode_keyint() {
    local mode="${1:-serie}"
    case "$mode" in
        serie) echo "600" ;;   # ~25s @ 24fps (compression optimale)
        film)  echo "240" ;;   # ~10s @ 24fps (seeking rapide)
        *)     echo "600" ;;
    esac
}

# Indique si pass 1 doit être rapide
# Usage: is_pass1_fast "serie" -> true
is_pass1_fast() {
    local mode="${1:-serie}"
    case "$mode" in
        serie) echo "true" ;;
        film)  echo "false" ;;
        *)     echo "true" ;;
    esac
}

###########################################################
# PARAMÈTRES VBV PAR CODEC
###########################################################

# Construit les paramètres VBV selon l'encodeur
# Usage: build_vbv_params "libx265" 2520 3780 -> "vbv-maxrate=2520:vbv-bufsize=3780"
build_vbv_params() {
    local encoder="$1"
    local maxrate_kbps="$2"
    local bufsize_kbps="$3"
    
    case "$encoder" in
        libx265)
            echo "vbv-maxrate=${maxrate_kbps}:vbv-bufsize=${bufsize_kbps}"
            ;;
        libsvtav1|libaom-av1)
            # Ces encodeurs utilisent les options FFmpeg directement
            echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

###########################################################
# PRESETS PAR ENCODEUR
###########################################################

# Convertit un preset x265 en preset équivalent pour un autre encodeur
# Usage: convert_preset "medium" "libsvtav1" -> "5"
convert_preset() {
    local x265_preset="$1"
    local target_encoder="$2"
    
    if [[ "$target_encoder" == "libx265" ]]; then
        echo "$x265_preset"
        return
    fi
    
    # Mapping x265 -> SVT-AV1 (approximatif)
    if [[ "$target_encoder" == "libsvtav1" ]]; then
        case "$x265_preset" in
            ultrafast) echo "12" ;;
            superfast) echo "10" ;;
            veryfast)  echo "8" ;;
            faster)    echo "7" ;;
            fast)      echo "6" ;;
            medium)    echo "5" ;;
            slow)      echo "4" ;;
            slower)    echo "3" ;;
            veryslow)  echo "2" ;;
            placebo)   echo "1" ;;
            *)         echo "5" ;;
        esac
        return
    fi
    
    # Mapping x265 -> libaom (cpu-used)
    if [[ "$target_encoder" == "libaom-av1" ]]; then
        case "$x265_preset" in
            ultrafast|superfast) echo "8" ;;
            veryfast|faster)     echo "6" ;;
            fast|medium)         echo "4" ;;
            slow|slower)         echo "2" ;;
            veryslow|placebo)    echo "1" ;;
            *)                   echo "4" ;;
        esac
        return
    fi
    
    # Fallback
    echo "$x265_preset"
}

###########################################################
# VALIDATION
###########################################################

# Valide et initialise le codec/encodeur
# Usage: validate_codec_config
# Retourne: 0 si OK, 1 si erreur
validate_codec_config() {
    # Vérifier que le codec est supporté
    if ! is_codec_supported "$VIDEO_CODEC"; then
        echo "Codec non supporté: $VIDEO_CODEC" >&2
        echo "Codecs disponibles: $(list_supported_codecs)" >&2
        return 1
    fi
    
    # Si pas d'encodeur spécifié, utiliser le défaut
    if [[ -z "$VIDEO_ENCODER" ]]; then
        VIDEO_ENCODER=$(get_codec_encoder "$VIDEO_CODEC")
    fi
    
    # Vérifier que l'encodeur est disponible dans FFmpeg
    if ! ffmpeg -encoders 2>/dev/null | grep -q "^ V.*${VIDEO_ENCODER}"; then
        echo "Encodeur non disponible dans FFmpeg: $VIDEO_ENCODER" >&2
        return 1
    fi
    
    return 0
}
