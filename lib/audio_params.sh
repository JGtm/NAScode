#!/bin/bash
###########################################################
# PARAMÈTRES AUDIO (AAC, AC3, E-AC3, Opus, FLAC, DTS)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
#
# Logique "Smart Codec" (optimisation taille) :
#   - Opus et AAC sont très efficaces → on les garde si bitrate OK
#   - E-AC3 et AC3 sont inefficaces → on convertit vers cible
#   - DTS/DTS-HD/TrueHD/FLAC (premium) → passthrough si possible
#   - Options --force-audio pour forcer la conversion
#   - Option --no-lossless pour forcer conversion des codecs premium
#
# Règles Multi-channel (5.1+) :
#   - Layout cible toujours 5.1 (downmix si >5.1)
#   - Codec par défaut multichannel = EAC3 384k
#   - AAC multichannel uniquement si -a aac + --force-audio
#   - Opus multichannel : 224k
#   - Anti-upscale : ne pas convertir si source < 256k
###########################################################

# Charger la logique de décision audio (smart codec) depuis un module dédié.
# Ce fichier conserve uniquement la construction des paramètres FFmpeg et les helpers de layout.
if [[ -z "${_AUDIO_DECISION_SH_LOADED:-}" ]]; then
    _AUDIO_PARAMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    source "${_AUDIO_PARAMS_DIR}/audio_decision.sh"
fi

###########################################################
# GESTION DES LAYOUTS AUDIO (CANAUX)
###########################################################

# Retourne le layout audio cible selon les canaux source.
# Usage: _get_target_audio_layout <channels>
# Retourne: "stereo" ou "5.1"
# Règle : multichannel (>=6ch) → toujours 5.1 (downmix si 7.1)
_get_target_audio_layout() {
    local channels="${1:-2}"

    if [[ "${AUDIO_FORCE_STEREO:-false}" == true ]]; then
        echo "stereo"
        return 0
    fi
    
    if _is_audio_multichannel "$channels"; then
        echo "5.1"
    else
        echo "stereo"
    fi
}

# Construit le filtre aformat pour normaliser le layout audio.
# Usage: _build_audio_layout_filter <channels>
# Retourne: "-af aformat=channel_layouts=..." ou "" si pas nécessaire
_build_audio_layout_filter() {
    local channels="${1:-2}"
    
    local target_layout
    target_layout=$(_get_target_audio_layout "$channels")
    
    echo "-af aformat=channel_layouts=${target_layout}"
}

###########################################################
# CONSTRUCTION PARAMÈTRES FFMPEG
###########################################################

# Construit les paramètres audio FFmpeg selon la logique smart codec
# Usage: _build_audio_params <input_file> [opt_source_codec] [opt_source_bitrate_kbps] [opt_channels]
# Retourne: les paramètres FFmpeg pour l'audio (-c:a ... -b:a ...)
_build_audio_params() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"
    local opt_channels="${4:-}"
    
    # Récupérer les infos audio complètes si non fournies
    local channels="$opt_channels"
    if [[ -z "$channels" ]]; then
        if declare -f _probe_audio_full &>/dev/null; then
            local audio_full
            audio_full=$(_probe_audio_full "$input_file")
            local probe_codec probe_bitrate probe_channels
            IFS='|' read -r probe_codec probe_bitrate probe_channels _ <<< "$audio_full"
            [[ -z "$opt_source_codec" ]] && opt_source_codec="$probe_codec"
            [[ -z "$opt_source_bitrate_kbps" ]] && opt_source_bitrate_kbps="$probe_bitrate"
            channels="$probe_channels"
        elif declare -f _probe_audio_channels &>/dev/null; then
            local channel_info
            channel_info=$(_probe_audio_channels "$input_file")
            channels=$(echo "$channel_info" | cut -d'|' -f1)
        fi
    fi
    [[ -z "$channels" || "$channels" == "N/A" ]] && channels="2"
    
    local decision action effective_codec target_bitrate _reason
    decision=$(_get_smart_audio_decision "$input_file" "$opt_source_codec" "$opt_source_bitrate_kbps" "$channels")
    IFS='|' read -r action effective_codec target_bitrate _reason <<< "$decision"
    
    case "$action" in
        "copy")
            # Mode copy : on garde l'audio tel quel (priorité au copy)
            echo "-c:a copy"
            ;;
        "convert"|"downscale")
            # Déterminer le layout cible (toujours 5.1 si multichannel)
            local layout_filter
            layout_filter=$(_build_audio_layout_filter "$channels")
            
            case "$effective_codec" in
                opus|libopus)
                    # Opus avec normalisation des layouts audio
                    echo "-c:a libopus -b:a ${target_bitrate}k ${layout_filter}"
                    ;;
                aac|aac_latm)
                    # AAC avec normalisation des layouts audio
                    echo "-c:a aac -b:a ${target_bitrate}k ${layout_filter}"
                    ;;
                eac3|ec-3|dd+)
                    # E-AC3 (Dolby Digital Plus) avec normalisation
                    echo "-c:a eac3 -b:a ${target_bitrate}k ${layout_filter}"
                    ;;
                ac3|a52)
                    # AC3 (Dolby Digital) avec normalisation
                    echo "-c:a ac3 -b:a ${target_bitrate}k ${layout_filter}"
                    ;;
                flac)
                    # FLAC lossless (pas de bitrate, compression level)
                    echo "-c:a flac -compression_level 8 ${layout_filter}"
                    ;;
                *)
                    # Fallback vers EAC3 pour multichannel, codec cible sinon
                    local fallback_codec fallback_encoder fallback_bitrate
                    if _is_audio_multichannel "$channels"; then
                        fallback_codec="eac3"
                        fallback_bitrate="${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}"
                    else
                        fallback_codec="${AUDIO_CODEC:-aac}"
                        fallback_bitrate=$(_get_audio_target_bitrate "$fallback_codec")
                    fi
                    fallback_encoder=$(get_audio_ffmpeg_encoder "$fallback_codec")
                    echo "-c:a ${fallback_encoder} -b:a ${fallback_bitrate}k ${layout_filter}"
                    ;;
            esac
            ;;
        *)
            # Fallback sécurisé
            echo "-c:a copy"
            ;;
    esac
}

###########################################################
# INFORMATIONS POUR LE SUFFIXE
###########################################################

# Retourne le codec audio effectif qui sera utilisé (pour le suffixe)
# Usage: _get_effective_audio_codec <input_file> [opt_source_codec] [opt_source_bitrate_kbps]
# Retourne: le nom du codec (opus, aac, ac3, eac3, flac, copy)
_get_effective_audio_codec() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"
    
    local decision action effective_codec
    decision=$(_get_smart_audio_decision "$input_file" "$opt_source_codec" "$opt_source_bitrate_kbps")
    IFS='|' read -r action effective_codec _ _ <<< "$decision"

    local normalized
    normalized=$(_normalize_audio_codec "$effective_codec")
    
    if [[ "$action" == "copy" && "$effective_codec" != "copy" && "$effective_codec" != "unknown" ]]; then
        echo "$normalized"
    elif [[ "$action" == "convert" || "$action" == "downscale" ]]; then
        echo "$normalized"
    else
        echo "copy"
    fi
}
