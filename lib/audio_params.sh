#!/bin/bash
###########################################################
# PARAMÈTRES AUDIO (AAC, AC3, E-AC3, Opus, FLAC)
# 
# Fonctions pures qui retournent des valeurs via echo,
# sans muter de variables globales.
#
# Logique "Smart Codec" :
#   - Si la source a un codec "meilleur" que la cible, on le garde
#   - Mais on applique la limite de bitrate définie pour ce codec source
#   - Options --force-audio pour bypasser cette logique
###########################################################

###########################################################
# HIÉRARCHIE DES CODECS AUDIO
###########################################################

# Retourne le "rang" d'efficacité d'un codec audio (plus élevé = meilleur)
# Basé sur l'efficacité de compression à qualité perceptuelle équivalente
# Usage: get_audio_codec_rank "opus" -> 5
get_audio_codec_rank() {
    local codec="$1"
    # Normaliser le nom du codec (ffprobe peut retourner des variantes)
    case "$codec" in
        opus|libopus)           echo 5 ;;   # Le plus efficace
        aac|aac_latm)           echo 4 ;;   # Très bon, polyvalent
        eac3|ec-3|dd+)          echo 3 ;;   # E-AC3 (Dolby Digital Plus)
        ac3|a52|dca)            echo 2 ;;   # AC3/DTS (rétro-compatibilité)
        flac)                   echo 6 ;;   # Lossless (rang spécial, toujours garder)
        truehd|mlp)             echo 7 ;;   # TrueHD (lossless Atmos)
        dts|dts-hd|dtshd)       echo 2 ;;   # DTS classique (comme AC3)
        pcm*|s16le|s24le)       echo 1 ;;   # PCM non compressé (à convertir)
        mp3|mp2)                echo 1 ;;   # Anciens codecs (à convertir)
        vorbis)                 echo 3 ;;   # Vorbis (similaire E-AC3)
        *)                      echo 0 ;;   # Inconnu
    esac
}

# Retourne le bitrate cible (kbps) pour un codec audio donné
# Usage: get_audio_codec_target_bitrate "opus" -> 128
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

# Vérifie si un codec source est "meilleur ou égal" au codec cible
# Usage: is_audio_codec_better_or_equal "opus" "aac" -> 0 (true)
is_audio_codec_better_or_equal() {
    local source_codec="$1"
    local target_codec="$2"
    
    local source_rank target_rank
    source_rank=$(get_audio_codec_rank "$source_codec")
    target_rank=$(get_audio_codec_rank "$target_codec")
    
    [[ "$source_rank" -ge "$target_rank" ]]
}

# Retourne le nom de l'encodeur FFmpeg pour un codec
# Usage: get_audio_ffmpeg_encoder "opus" -> "libopus"
get_audio_ffmpeg_encoder() {
    local codec="$1"
    case "$codec" in
        opus|libopus)   echo "libopus" ;;
        aac|aac_latm)   echo "aac" ;;
        eac3|ec-3|dd+)  echo "eac3" ;;
        ac3|a52)        echo "ac3" ;;
        flac)           echo "flac" ;;
        *)              echo "$codec" ;;  # Fallback
    esac
}

###########################################################
# BITRATE CIBLE
###########################################################

# Retourne le bitrate cible pour le codec audio configuré
# Usage: _get_audio_target_bitrate [codec_override]
# Retourne: bitrate en kbps
_get_audio_target_bitrate() {
    local codec="${1:-${AUDIO_CODEC:-copy}}"
    
    # Si un bitrate custom est défini, l'utiliser
    if [[ "${AUDIO_BITRATE_KBPS:-0}" -gt 0 ]]; then
        echo "$AUDIO_BITRATE_KBPS"
        return 0
    fi
    
    # Sinon utiliser le défaut selon le codec
    get_audio_codec_target_bitrate "$codec"
}

###########################################################
# ANALYSE AUDIO - LOGIQUE SMART CODEC
###########################################################

# Décision intelligente pour l'audio : garde le codec meilleur, applique limite bitrate
# Retourne: action|codec_effectif|bitrate_cible|raison
# Actions: copy (garder tel quel), convert (vers codec cible), downscale (même codec, bitrate réduit)
_get_smart_audio_decision() {
    local input_file="$1"
    
    # Si mode copy explicite, toujours copier
    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|copy|0|mode_copy"
        return 0
    fi
    
    # Récupérer les infos audio du premier flux audio
    local audio_info
    audio_info=$(ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$input_file" 2>/dev/null || true)
    
    local source_codec source_bitrate source_bitrate_tag
    source_codec=$(echo "$audio_info" | awk -F= '/^codec_name=/{print $2; exit}')
    source_bitrate=$(echo "$audio_info" | awk -F= '/^bit_rate=/{print $2; exit}')
    source_bitrate_tag=$(echo "$audio_info" | awk -F= '/^TAG:BPS=/{print $2; exit}')
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$source_bitrate" || "$source_bitrate" == "N/A" ]]; then
        source_bitrate="$source_bitrate_tag"
    fi
    
    # Convertir en kbps
    if declare -f clean_number &>/dev/null; then
        source_bitrate=$(clean_number "$source_bitrate")
    fi
    local source_bitrate_kbps=0
    if [[ -n "$source_bitrate" && "$source_bitrate" =~ ^[0-9]+$ ]]; then
        source_bitrate_kbps=$((source_bitrate / 1000))
    fi
    
    local target_codec="${AUDIO_CODEC:-aac}"
    local target_bitrate
    target_bitrate=$(_get_audio_target_bitrate "$target_codec")
    
    # --- Mode FORCE : ignorer la logique smart ---
    if [[ "${FORCE_AUDIO_CODEC:-false}" == true ]]; then
        if [[ "$source_codec" == "$target_codec" ]]; then
            # Même codec mais force → downscale si bitrate > cible
            if [[ "$source_bitrate_kbps" -gt "$target_bitrate" ]]; then
                echo "downscale|${target_codec}|${target_bitrate}|force_downscale"
            else
                echo "copy|${source_codec}|0|force_same_codec_ok"
            fi
        else
            echo "convert|${target_codec}|${target_bitrate}|force_convert"
        fi
        return 0
    fi
    
    # --- Logique Smart Codec ---
    
    # Cas 1 : Codec source inconnu → sécurité, on copie
    if [[ -z "$source_codec" ]]; then
        echo "copy|unknown|0|unknown_codec"
        return 0
    fi
    
    # Cas 2 : Codec lossless (FLAC, TrueHD) → toujours garder
    local source_rank
    source_rank=$(get_audio_codec_rank "$source_codec")
    if [[ "$source_rank" -ge 6 ]]; then
        echo "copy|${source_codec}|0|lossless_keep"
        return 0
    fi
    
    # Cas 3 : Source = même codec que cible
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
    
    # Cas 4 : Codec source MEILLEUR que cible → garder source, mais appliquer sa limite
    if is_audio_codec_better_or_equal "$source_codec" "$target_codec"; then
        local source_limit
        source_limit=$(get_audio_codec_target_bitrate "$source_codec")
        
        if [[ "$source_limit" -eq 0 ]]; then
            # Pas de limite pour ce codec (rare pour lossy)
            echo "copy|${source_codec}|0|better_codec_no_limit"
        elif [[ "$source_bitrate_kbps" -eq 0 ]]; then
            echo "copy|${source_codec}|0|better_codec_unknown_bitrate"
        elif [[ "$source_bitrate_kbps" -le "$source_limit" ]]; then
            echo "copy|${source_codec}|0|better_codec_bitrate_ok"
        elif [[ "$source_bitrate_kbps" -gt $((source_limit * 110 / 100)) ]]; then
            # Downscale dans le même codec (meilleur)
            echo "downscale|${source_codec}|${source_limit}|better_codec_downscale"
        else
            echo "copy|${source_codec}|0|better_codec_margin_ok"
        fi
        return 0
    fi
    
    # Cas 5 : Codec source MOINS BON que cible → convertir vers cible
    if [[ "$source_bitrate_kbps" -eq 0 ]]; then
        # Bitrate inconnu, on convertit par sécurité
        echo "convert|${target_codec}|${target_bitrate}|worse_codec_convert"
    elif [[ "$source_bitrate_kbps" -le "$target_bitrate" ]]; then
        # Anti-upscaling : source déjà petit, on copie
        echo "copy|${source_codec}|0|worse_codec_anti_upscale"
    elif [[ "$source_bitrate_kbps" -gt $((target_bitrate * 110 / 100)) ]]; then
        # Gain significatif → convertir
        echo "convert|${target_codec}|${target_bitrate}|worse_codec_convert_gain"
    else
        # Marge de 10% → copier
        echo "copy|${source_codec}|0|worse_codec_margin_ok"
    fi
}

# Analyse l'audio d'un fichier et détermine si la conversion est avantageuse.
# RÉTRO-COMPATIBILITÉ : retourne le format original source_codec|source_bitrate_kbps|should_convert
# Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert)
_get_audio_conversion_info() {
    local input_file="$1"
    
    # Si mode copy, toujours copier (format original)
    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|0|0"
        return 0
    fi
    
    # Récupérer les infos audio du premier flux audio (pour le bitrate source)
    local audio_info
    audio_info=$(ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,bit_rate:stream_tags=BPS \
        -of default=noprint_wrappers=1 \
        "$input_file" 2>/dev/null || true)
    
    local source_codec source_bitrate source_bitrate_tag
    source_codec=$(echo "$audio_info" | awk -F= '/^codec_name=/{print $2; exit}')
    source_bitrate=$(echo "$audio_info" | awk -F= '/^bit_rate=/{print $2; exit}')
    source_bitrate_tag=$(echo "$audio_info" | awk -F= '/^TAG:BPS=/{print $2; exit}')
    
    # Utiliser le tag BPS si bitrate direct non disponible
    if [[ -z "$source_bitrate" || "$source_bitrate" == "N/A" ]]; then
        source_bitrate="$source_bitrate_tag"
    fi
    
    # Convertir en kbps
    if declare -f clean_number &>/dev/null; then
        source_bitrate=$(clean_number "$source_bitrate")
    fi
    local source_bitrate_kbps=0
    if [[ -n "$source_bitrate" && "$source_bitrate" =~ ^[0-9]+$ ]]; then
        source_bitrate_kbps=$((source_bitrate / 1000))
    fi
    
    # Utiliser la décision smart pour déterminer should_convert
    local decision action
    decision=$(_get_smart_audio_decision "$input_file")
    action=$(echo "$decision" | cut -d'|' -f1)
    
    # Déterminer should_convert
    local should_convert=0
    if [[ "$action" == "convert" || "$action" == "downscale" ]]; then
        should_convert=1
    fi
    
    # Retourner le format original : source_codec|source_bitrate_kbps|should_convert
    echo "${source_codec}|${source_bitrate_kbps}|${should_convert}"
}

# Détermine si l'audio d'un fichier doit être converti.
# Wrapper simple pour _get_smart_audio_decision.
# Usage: _should_convert_audio <input_file>
# Retourne: 0 si l'audio doit être converti/downscalé, 1 sinon
_should_convert_audio() {
    local input_file="$1"
    
    local decision action
    decision=$(_get_smart_audio_decision "$input_file")
    action=$(echo "$decision" | cut -d'|' -f1)
    
    if [[ "$action" == "convert" || "$action" == "downscale" ]]; then
        return 0  # Doit être traité
    fi
    return 1  # Pas besoin de conversion
}

###########################################################
# CONSTRUCTION PARAMÈTRES FFMPEG
###########################################################

# Construit les paramètres audio FFmpeg selon la logique smart codec
# Usage: _build_audio_params <input_file>
# Retourne: les paramètres FFmpeg pour l'audio (-c:a ... -b:a ...)
_build_audio_params() {
    local input_file="$1"
    
    local decision action effective_codec target_bitrate reason
    decision=$(_get_smart_audio_decision "$input_file")
    IFS='|' read -r action effective_codec target_bitrate reason <<< "$decision"
    
    case "$action" in
        "copy")
            echo "-c:a copy"
            ;;
        "convert"|"downscale")
            local encoder
            encoder=$(get_audio_ffmpeg_encoder "$effective_codec")
            
            case "$effective_codec" in
                opus|libopus)
                    # Opus avec normalisation des layouts audio (évite les erreurs VLC)
                    echo "-c:a libopus -b:a ${target_bitrate}k -af aformat=channel_layouts=7.1|5.1|stereo|mono"
                    ;;
                aac|aac_latm)
                    # AAC standard
                    echo "-c:a aac -b:a ${target_bitrate}k"
                    ;;
                eac3|ec-3|dd+)
                    # E-AC3 (Dolby Digital Plus)
                    echo "-c:a eac3 -b:a ${target_bitrate}k"
                    ;;
                ac3|a52)
                    # AC3 (Dolby Digital)
                    echo "-c:a ac3 -b:a ${target_bitrate}k"
                    ;;
                flac)
                    # FLAC lossless (pas de bitrate, compression level)
                    echo "-c:a flac -compression_level 8"
                    ;;
                *)
                    # Fallback vers le codec cible configuré
                    local fallback_encoder
                    fallback_encoder=$(get_audio_ffmpeg_encoder "${AUDIO_CODEC:-aac}")
                    local fallback_bitrate
                    fallback_bitrate=$(_get_audio_target_bitrate "${AUDIO_CODEC:-aac}")
                    echo "-c:a ${fallback_encoder} -b:a ${fallback_bitrate}k"
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
# Usage: _get_effective_audio_codec <input_file>
# Retourne: le nom du codec (opus, aac, ac3, eac3, flac, copy)
_get_effective_audio_codec() {
    local input_file="$1"
    
    local decision action effective_codec
    decision=$(_get_smart_audio_decision "$input_file")
    IFS='|' read -r action effective_codec _ _ <<< "$decision"
    
    if [[ "$action" == "copy" && "$effective_codec" != "copy" && "$effective_codec" != "unknown" ]]; then
        # On garde le codec source tel quel
        # Normaliser le nom pour le suffixe
        case "$effective_codec" in
            libopus)  echo "opus" ;;
            aac_latm) echo "aac" ;;
            ec-3|dd+) echo "eac3" ;;
            a52)      echo "ac3" ;;
            *)        echo "$effective_codec" ;;
        esac
    elif [[ "$action" == "convert" || "$action" == "downscale" ]]; then
        # On va encoder vers ce codec
        case "$effective_codec" in
            libopus)  echo "opus" ;;
            aac_latm) echo "aac" ;;
            ec-3|dd+) echo "eac3" ;;
            a52)      echo "ac3" ;;
            *)        echo "$effective_codec" ;;
        esac
    else
        echo "copy"
    fi
}
