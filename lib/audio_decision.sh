#!/bin/bash

# Module: audio_decision.sh
# Rôle: logique de décision “smart codec” audio (quoi faire) + helpers.
# Note: la construction des paramètres FFmpeg (comment le faire) reste dans audio_params.sh.

if [[ -n "${_AUDIO_DECISION_SH_LOADED:-}" ]]; then
    return 0
fi
_AUDIO_DECISION_SH_LOADED=1

###########################################################
# HIÉRARCHIE DES CODECS AUDIO (EFFICACITÉ)
###########################################################

# Retourne le "rang" d'efficacité d'un codec audio (plus élevé = plus efficace = plus compact)
# Ce rang détermine si on GARDE le codec source ou si on le CONVERTIT
# Rang 10+ = premium/lossless (passthrough par défaut)
# Usage: get_audio_codec_rank "opus" -> 5
get_audio_codec_rank() {
    local codec="$1"
    case "$codec" in
        opus|libopus)           echo 5 ;;   # Très efficace (128k)
        aac|aac_latm)           echo 4 ;;   # Très efficace (160k)
        eac3|ec-3|dd+)          echo 2 ;;   # Inefficace (384k) → convertir
        ac3|a52)                echo 1 ;;   # Inefficace (640k) → convertir
        flac)                   echo 10 ;;  # Lossless (passthrough)
        truehd|mlp)             echo 11 ;;  # TrueHD lossless (passthrough)
        dts)                    echo 10 ;;  # DTS (passthrough, qualité)
        dts-hd|dtshd|dts_hd)    echo 11 ;;  # DTS-HD MA (passthrough, lossless)
        dca)                    echo 10 ;;  # DTS Core (passthrough)
        pcm*|s16le|s24le)       echo 0 ;;   # PCM non compressé → convertir
        mp3|mp2)                echo 0 ;;   # Anciens codecs → convertir
        vorbis)                 echo 3 ;;   # Vorbis (efficace, proche AAC)
        *)                      echo 0 ;;   # Inconnu → convertir
    esac
}

# Rang minimum pour considérer un codec comme "efficace" (à garder)
AUDIO_CODEC_EFFICIENT_THRESHOLD=3

# Retourne le bitrate cible (kbps) pour un codec audio donné
get_audio_codec_target_bitrate() {
    local codec="$1"
    case "$codec" in
        opus|libopus)           echo "${AUDIO_BITRATE_OPUS_DEFAULT:-128}" ;;
        aac|aac_latm)           echo "${AUDIO_BITRATE_AAC_DEFAULT:-160}" ;;
        eac3|ec-3|dd+)          echo "${AUDIO_BITRATE_EAC3_DEFAULT:-384}" ;;
        ac3|a52)                echo "${AUDIO_BITRATE_AC3_DEFAULT:-640}" ;;
        flac|truehd|mlp)        echo "0" ;;  # Lossless : pas de limite
        dts|dts-hd|dtshd|dca)   echo "${AUDIO_BITRATE_AC3_DEFAULT:-640}" ;;  # Comme AC3
        *)                      echo "0" ;;  # Inconnu : pas de limite
    esac
}

is_audio_codec_efficient() {
    local codec="$1"
    local rank
    rank=$(get_audio_codec_rank "$codec")
    [[ "$rank" -ge "${AUDIO_CODEC_EFFICIENT_THRESHOLD:-3}" ]]
}

is_audio_codec_lossless() {
    local codec="$1"
    case "$codec" in
        flac|truehd|mlp|dts-hd|dtshd|dts_hd) return 0 ;;
        *) return 1 ;;
    esac
}

# Ces codecs sont conservés par défaut sauf --no-lossless
is_audio_codec_premium_passthrough() {
    local codec="$1"
    local rank
    rank=$(get_audio_codec_rank "$codec")
    [[ "$rank" -ge 10 ]]
}

is_audio_codec_better_or_equal() {
    local source_codec="$1"
    local target_codec="$2"

    local source_rank target_rank
    source_rank=$(get_audio_codec_rank "$source_codec")
    target_rank=$(get_audio_codec_rank "$target_codec")

    [[ "$source_rank" -ge "$target_rank" ]]
}

# Retourne le nom de l'encodeur FFmpeg pour un codec
get_audio_ffmpeg_encoder() {
    local codec="$1"
    case "$codec" in
        opus|libopus)   echo "libopus" ;;
        aac|aac_latm)   echo "aac" ;;
        eac3|ec-3|dd+)  echo "eac3" ;;
        ac3|a52)        echo "ac3" ;;
        flac)           echo "flac" ;;
        *)              echo "$codec" ;;
    esac
}

###########################################################
# MULTICHANNEL + BITRATES (ANTI-UPSCALE)
###########################################################

# Détermine si la source audio est multicanal (>= 6 canaux, soit 5.1 ou plus)
_is_audio_multichannel() {
    local channels="${1:-2}"
    [[ "$channels" -ge 6 ]]
}

# Calcule le bitrate cible EAC3 avec anti-upscale
_compute_eac3_target_bitrate_kbps() {
    local source_bitrate_kbps="${1:-0}"
    local cap="${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}"

    if [[ "$source_bitrate_kbps" -eq 0 ]]; then
        echo "$cap"
    elif [[ "$source_bitrate_kbps" -lt "$cap" ]]; then
        echo "$source_bitrate_kbps"
    else
        echo "$cap"
    fi
}

_get_multichannel_target_bitrate() {
    local codec="$1"
    case "$codec" in
        opus|libopus)   echo "${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}" ;;
        aac|aac_latm)   echo "${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}" ;;
        eac3|ec-3|dd+)  echo "${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}" ;;
        ac3|a52)        echo "${AUDIO_BITRATE_AC3_DEFAULT:-640}" ;;
        *)              echo "${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}" ;;
    esac
}

# Retourne le bitrate cible pour le codec audio configuré
_get_audio_target_bitrate() {
    local codec="${1:-${AUDIO_CODEC:-copy}}"

    if [[ "${AUDIO_BITRATE_KBPS:-0}" -gt 0 ]]; then
        echo "$AUDIO_BITRATE_KBPS"
        return 0
    fi

    get_audio_codec_target_bitrate "$codec"
}

###########################################################
# ANALYSE AUDIO - LOGIQUE SMART CODEC
###########################################################

# Retourne: action|codec_effectif|bitrate_cible|raison
_get_smart_audio_decision() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"
    local opt_channels="${4:-}"

    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|copy|0|mode_copy"
        return 0
    fi

    local source_codec source_bitrate_kbps channels

    if [[ -n "$opt_source_codec" ]]; then
        source_codec="$opt_source_codec"
        source_bitrate_kbps="${opt_source_bitrate_kbps:-0}"
        channels="${opt_channels:-2}"
    else
        if declare -f _probe_audio_full &>/dev/null; then
            local audio_full
            audio_full=$(_probe_audio_full "$input_file")
            IFS='|' read -r source_codec source_bitrate_kbps channels _ <<< "$audio_full"
        else
            local audio_probe
            audio_probe=$(_probe_audio_info "$input_file")
            IFS='|' read -r source_codec source_bitrate_kbps <<< "$audio_probe"
            channels="2"
        fi
    fi

    [[ -z "$channels" || "$channels" == "N/A" ]] && channels="2"
    [[ -z "$source_bitrate_kbps" ]] && source_bitrate_kbps="0"

    local is_multichannel=false
    _is_audio_multichannel "$channels" && is_multichannel=true

    local target_codec="${AUDIO_CODEC:-aac}"
    local target_bitrate

    local effective_target_codec="$target_codec"
    if [[ "$is_multichannel" == true ]]; then
        if [[ "$target_codec" == "opus" ]]; then
            effective_target_codec="opus"
        elif [[ "$target_codec" == "aac" && "${FORCE_AUDIO_CODEC:-false}" == true ]]; then
            effective_target_codec="aac"
        else
            effective_target_codec="eac3"
        fi
        target_bitrate=$(_get_multichannel_target_bitrate "$effective_target_codec")
    else
        target_bitrate=$(_get_audio_target_bitrate "$target_codec")
    fi

    if [[ "${NO_LOSSLESS:-false}" == true ]]; then
        if is_audio_codec_premium_passthrough "$source_codec"; then
            if [[ "$is_multichannel" == true ]]; then
                local eac3_bitrate
                eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                echo "convert|eac3|${eac3_bitrate}|no_lossless_multichannel"
            else
                echo "convert|${target_codec}|${target_bitrate}|no_lossless_stereo"
            fi
            return 0
        fi
    fi

    if [[ "${FORCE_AUDIO_CODEC:-false}" == true ]]; then
        if [[ "$source_codec" == "$effective_target_codec" ]] || \
           [[ "$source_codec" == "libopus" && "$effective_target_codec" == "opus" ]] || \
           [[ "$source_codec" == "aac_latm" && "$effective_target_codec" == "aac" ]]; then
            if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -gt "$target_bitrate" ]]; then
                echo "downscale|${effective_target_codec}|${target_bitrate}|force_downscale"
            else
                echo "copy|${source_codec}|0|force_same_codec_ok"
            fi
        else
            echo "convert|${effective_target_codec}|${target_bitrate}|force_convert"
        fi
        return 0
    fi

    if [[ -z "$source_codec" ]]; then
        echo "convert|${effective_target_codec}|${target_bitrate}|unknown_codec"
        return 0
    fi

    if is_audio_codec_premium_passthrough "$source_codec"; then
        if [[ "$channels" -gt 6 ]]; then
            local eac3_bitrate
            eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
            echo "convert|eac3|${eac3_bitrate}|premium_downmix_required"
            return 0
        fi
        echo "copy|${source_codec}|0|premium_passthrough"
        return 0
    fi

    if [[ "$is_multichannel" == true ]]; then
        local anti_upscale_threshold="${AUDIO_ANTI_UPSCALE_THRESHOLD_KBPS:-256}"

        if [[ "$source_codec" == "eac3" || "$source_codec" == "ec-3" || "$source_codec" == "dd+" ]]; then
            if [[ "$channels" -gt 6 ]]; then
                local eac3_bitrate
                eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                echo "convert|eac3|${eac3_bitrate}|eac3_downmix_required"
            elif [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -gt "${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}" ]]; then
                echo "downscale|eac3|${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}|eac3_multichannel_downscale"
            else
                echo "copy|${source_codec}|0|eac3_multichannel_ok"
            fi
            return 0
        fi

        if [[ "$source_codec" == "ac3" || "$source_codec" == "a52" ]]; then
            if [[ "$effective_target_codec" == "opus" ]]; then
                echo "convert|opus|${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}|ac3_to_opus_multichannel"
            else
                local eac3_bitrate
                eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                echo "convert|eac3|${eac3_bitrate}|ac3_to_eac3_multichannel"
            fi
            return 0
        fi

        if [[ "$source_codec" == "aac" || "$source_codec" == "aac_latm" ]]; then
            if [[ "$effective_target_codec" == "aac" ]]; then
                if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -gt "${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}" ]]; then
                    echo "downscale|aac|${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}|aac_multichannel_downscale"
                elif [[ "$channels" -gt 6 ]]; then
                    echo "convert|aac|${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}|aac_downmix_required"
                else
                    echo "copy|${source_codec}|0|aac_multichannel_ok"
                fi
            else
                if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -lt "$anti_upscale_threshold" ]]; then
                    echo "copy|${source_codec}|0|aac_multichannel_anti_upscale"
                else
                    local eac3_bitrate
                    eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                    echo "convert|eac3|${eac3_bitrate}|aac_to_eac3_multichannel"
                fi
            fi
            return 0
        fi

        if [[ "$source_codec" == "opus" || "$source_codec" == "libopus" ]]; then
            if [[ "$effective_target_codec" == "opus" ]]; then
                if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -gt "${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}" ]]; then
                    echo "downscale|opus|${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}|opus_multichannel_downscale"
                elif [[ "$channels" -gt 6 ]]; then
                    echo "convert|opus|${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}|opus_downmix_required"
                else
                    echo "copy|${source_codec}|0|opus_multichannel_ok"
                fi
            else
                if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -le "${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}" ]]; then
                    if [[ "$channels" -le 6 ]]; then
                        echo "copy|${source_codec}|0|opus_multichannel_efficient"
                    else
                        echo "convert|opus|${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}|opus_downmix_required"
                    fi
                else
                    echo "downscale|opus|${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}|opus_multichannel_downscale"
                fi
            fi
            return 0
        fi

        if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -lt "$anti_upscale_threshold" ]]; then
            echo "copy|${source_codec}|0|multichannel_anti_upscale"
        else
            local eac3_bitrate
            eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
            echo "convert|eac3|${eac3_bitrate}|multichannel_to_eac3"
        fi
        return 0
    fi

    if [[ "$source_codec" == "$target_codec" ]] || \
       [[ "$source_codec" == "libopus" && "$target_codec" == "opus" ]] || \
       [[ "$source_codec" == "aac_latm" && "$target_codec" == "aac" ]]; then
        if [[ "$source_bitrate_kbps" -eq 0 ]]; then
            echo "copy|${source_codec}|0|same_codec_unknown_bitrate"
        elif [[ "$source_bitrate_kbps" -le "$target_bitrate" ]]; then
            echo "copy|${source_codec}|0|same_codec_bitrate_ok"
        elif [[ "$source_bitrate_kbps" -gt $((target_bitrate * 110 / 100)) ]]; then
            echo "downscale|${source_codec}|${target_bitrate}|same_codec_downscale"
        else
            echo "copy|${source_codec}|0|same_codec_margin_ok"
        fi
        return 0
    fi

    if is_audio_codec_efficient "$source_codec"; then
        local source_limit
        source_limit=$(get_audio_codec_target_bitrate "$source_codec")

        if [[ "$source_limit" -eq 0 ]]; then
            echo "copy|${source_codec}|0|efficient_codec_no_limit"
        elif [[ "$source_bitrate_kbps" -eq 0 ]]; then
            echo "copy|${source_codec}|0|efficient_codec_unknown_bitrate"
        elif [[ "$source_bitrate_kbps" -le "$source_limit" ]]; then
            echo "copy|${source_codec}|0|efficient_codec_bitrate_ok"
        elif [[ "$source_bitrate_kbps" -gt $((source_limit * 110 / 100)) ]]; then
            echo "downscale|${source_codec}|${source_limit}|efficient_codec_downscale"
        else
            echo "copy|${source_codec}|0|efficient_codec_margin_ok"
        fi
        return 0
    fi

    echo "convert|${target_codec}|${target_bitrate}|inefficient_codec_convert"
}

# RÉTRO-COMPATIBILITÉ : retourne source_codec|source_bitrate_kbps|should_convert
_get_audio_conversion_info() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"

    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|0|0"
        return 0
    fi

    local source_codec source_bitrate_kbps

    if [[ -n "$opt_source_codec" ]]; then
        source_codec="$opt_source_codec"
        source_bitrate_kbps="${opt_source_bitrate_kbps:-0}"
    else
        local audio_probe
        audio_probe=$(_probe_audio_info "$input_file")
        IFS='|' read -r source_codec source_bitrate_kbps <<< "$audio_probe"
    fi

    local decision action
    decision=$(_get_smart_audio_decision "$input_file" "$source_codec" "$source_bitrate_kbps")
    action=$(echo "$decision" | cut -d'|' -f1)

    local should_convert=0
    if [[ "$action" == "convert" || "$action" == "downscale" ]]; then
        should_convert=1
    fi

    echo "${source_codec}|${source_bitrate_kbps}|${should_convert}"
}

_should_convert_audio() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"

    local decision action
    decision=$(_get_smart_audio_decision "$input_file" "$opt_source_codec" "$opt_source_bitrate_kbps")
    action=$(echo "$decision" | cut -d'|' -f1)

    if [[ "$action" == "convert" || "$action" == "downscale" ]]; then
        return 0
    fi
    return 1
}
