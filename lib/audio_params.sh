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

###########################################################
# HIÉRARCHIE DES CODECS AUDIO (EFFICACITÉ)
###########################################################

# Retourne le "rang" d'efficacité d'un codec audio (plus élevé = plus efficace = plus compact)
# Ce rang détermine si on GARDE le codec source ou si on le CONVERTIT
# Rang 10+ = premium/lossless (passthrough par défaut)
# Usage: get_audio_codec_rank "opus" -> 5
get_audio_codec_rank() {
    local codec="$1"
    # Normaliser le nom du codec (ffprobe peut retourner des variantes)
    # Efficacité = qualité / taille (Opus 128k ≈ AAC 160k >> E-AC3 384k >> AC3 640k)
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
# Opus (5), AAC (4), Vorbis (3) sont efficaces
# E-AC3 (2), AC3 (1), autres (0) sont inefficaces
AUDIO_CODEC_EFFICIENT_THRESHOLD=3

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

# Vérifie si un codec source est "efficace" (rang >= seuil)
# Usage: is_audio_codec_efficient "opus" -> 0 (true)
is_audio_codec_efficient() {
    local codec="$1"
    local rank
    rank=$(get_audio_codec_rank "$codec")
    [[ "$rank" -ge "${AUDIO_CODEC_EFFICIENT_THRESHOLD:-3}" ]]
}

# Vérifie si un codec est lossless (FLAC, TrueHD, DTS-HD MA)
# Usage: is_audio_codec_lossless "flac" -> 0 (true)
is_audio_codec_lossless() {
    local codec="$1"
    case "$codec" in
        flac|truehd|mlp|dts-hd|dtshd|dts_hd) return 0 ;;
        *) return 1 ;;
    esac
}

# Vérifie si un codec est "premium passthrough" (lossless + DTS)
# Ces codecs sont conservés par défaut sauf --no-lossless
# Usage: is_audio_codec_premium_passthrough "dts" -> 0 (true)
is_audio_codec_premium_passthrough() {
    local codec="$1"
    local rank
    rank=$(get_audio_codec_rank "$codec")
    [[ "$rank" -ge 10 ]]
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
# GESTION DES LAYOUTS AUDIO (CANAUX)
###########################################################

# Détermine si la source audio est multicanal (>= 6 canaux, soit 5.1 ou plus)
# Usage: _is_audio_multichannel <channels>
# Retourne: 0 (true) si >= 6 canaux, 1 (false) sinon
_is_audio_multichannel() {
    local channels="${1:-2}"
    [[ "$channels" -ge 6 ]]
}

# Retourne le layout audio cible selon les canaux source.
# Usage: _get_target_audio_layout <channels>
# Retourne: "stereo" ou "5.1"
# Règle : multichannel (>=6ch) → toujours 5.1 (downmix si 7.1)
_get_target_audio_layout() {
    local channels="${1:-2}"
    
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
# BITRATE CIBLE (ANTI-UPSCALE)
###########################################################

# Calcule le bitrate cible EAC3 avec anti-upscale
# Usage: _compute_eac3_target_bitrate_kbps <source_bitrate_kbps>
# Retourne: bitrate cible (jamais au-dessus de la source, plafond 384)
_compute_eac3_target_bitrate_kbps() {
    local source_bitrate_kbps="${1:-0}"
    local cap="${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}"
    
    if [[ "$source_bitrate_kbps" -eq 0 ]]; then
        # Bitrate inconnu → utiliser le plafond
        echo "$cap"
    elif [[ "$source_bitrate_kbps" -lt "$cap" ]]; then
        # Source < plafond → utiliser la source (pas d'upscale)
        echo "$source_bitrate_kbps"
    else
        # Source >= plafond → utiliser le plafond
        echo "$cap"
    fi
}

# Retourne le bitrate cible multichannel pour un codec
# Usage: _get_multichannel_target_bitrate <codec>
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

# Décision intelligente pour l'audio avec support multichannel et DTS passthrough
# Retourne: action|codec_effectif|bitrate_cible|raison
# Actions: copy (garder tel quel), convert (vers codec cible), downscale (même codec, bitrate réduit)
# Usage: _get_smart_audio_decision <input_file> [opt_source_codec] [opt_source_bitrate_kbps] [opt_channels]
_get_smart_audio_decision() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"
    local opt_channels="${4:-}"
    
    # Si mode copy explicite, toujours copier
    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|copy|0|mode_copy"
        return 0
    fi
    
    local source_codec source_bitrate_kbps channels
    
    if [[ -n "$opt_source_codec" ]]; then
        # Utilisation des métadonnées fournies (optimisation)
        source_codec="$opt_source_codec"
        source_bitrate_kbps="${opt_source_bitrate_kbps:-0}"
        channels="${opt_channels:-2}"
    else
        # Utiliser _probe_audio_full pour tout récupérer d'un coup
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
    
    # Valeurs par défaut
    [[ -z "$channels" || "$channels" == "N/A" ]] && channels="2"
    [[ -z "$source_bitrate_kbps" ]] && source_bitrate_kbps="0"
    
    local is_multichannel=false
    _is_audio_multichannel "$channels" && is_multichannel=true
    
    local target_codec="${AUDIO_CODEC:-aac}"
    local target_bitrate
    
    # Déterminer le codec cible effectif selon multichannel
    local effective_target_codec="$target_codec"
    if [[ "$is_multichannel" == true ]]; then
        # Multichannel : EAC3 par défaut, sauf si -a opus ou (-a aac + --force-audio)
        if [[ "$target_codec" == "opus" ]]; then
            effective_target_codec="opus"
        elif [[ "$target_codec" == "aac" && "${FORCE_AUDIO_CODEC:-false}" == true ]]; then
            effective_target_codec="aac"
        else
            # Codec par défaut multichannel = EAC3
            effective_target_codec="eac3"
        fi
        target_bitrate=$(_get_multichannel_target_bitrate "$effective_target_codec")
    else
        target_bitrate=$(_get_audio_target_bitrate "$target_codec")
    fi
    
    # ===== Traitement --no-lossless =====
    # Force la conversion des codecs premium (DTS/DTS-HD/TrueHD/FLAC)
    if [[ "${NO_LOSSLESS:-false}" == true ]]; then
        if is_audio_codec_premium_passthrough "$source_codec"; then
            if [[ "$is_multichannel" == true ]]; then
                # Multichannel + --no-lossless → EAC3 384k 5.1
                local eac3_bitrate
                eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                echo "convert|eac3|${eac3_bitrate}|no_lossless_multichannel"
            else
                # Stéréo + --no-lossless → codec cible stéréo
                echo "convert|${target_codec}|${target_bitrate}|no_lossless_stereo"
            fi
            return 0
        fi
    fi
    
    # ===== Mode FORCE : ignorer la logique smart =====
    if [[ "${FORCE_AUDIO_CODEC:-false}" == true ]]; then
        if [[ "$source_codec" == "$effective_target_codec" ]] || \
           [[ "$source_codec" == "libopus" && "$effective_target_codec" == "opus" ]] || \
           [[ "$source_codec" == "aac_latm" && "$effective_target_codec" == "aac" ]]; then
            # Même codec mais force → downscale si bitrate > cible
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
    
    # ===== Codec source inconnu → convertir par sécurité =====
    if [[ -z "$source_codec" ]]; then
        echo "convert|${effective_target_codec}|${target_bitrate}|unknown_codec"
        return 0
    fi
    
    # ===== Codecs premium passthrough (DTS/DTS-HD/TrueHD/FLAC) =====
    if is_audio_codec_premium_passthrough "$source_codec"; then
        # Vérifier si downmix requis (>5.1 → 5.1)
        if [[ "$channels" -gt 6 ]]; then
            # Source > 5.1 (ex: 7.1) → conversion obligatoire pour downmix
            local eac3_bitrate
            eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
            echo "convert|eac3|${eac3_bitrate}|premium_downmix_required"
            return 0
        fi
        # Source déjà 5.1 ou moins → passthrough OK
        echo "copy|${source_codec}|0|premium_passthrough"
        return 0
    fi
    
    # ===== Traitement multichannel spécifique =====
    if [[ "$is_multichannel" == true ]]; then
        # Anti-upscale : ne pas convertir si source < seuil (sauf si downmix requis)
        local anti_upscale_threshold="${AUDIO_ANTI_UPSCALE_THRESHOLD_KBPS:-256}"
        
        # EAC3 source
        if [[ "$source_codec" == "eac3" || "$source_codec" == "ec-3" || "$source_codec" == "dd+" ]]; then
            # Priorité 1: vérifier si downmix requis (>5.1)
            if [[ "$channels" -gt 6 ]]; then
                # EAC3 mais >5.1 → re-encode pour downmix vers 5.1
                local eac3_bitrate
                eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                echo "convert|eac3|${eac3_bitrate}|eac3_downmix_required"
            elif [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -gt "${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}" ]]; then
                # EAC3 > 384 et déjà 5.1 → downscale vers 384
                echo "downscale|eac3|${AUDIO_BITRATE_EAC3_MULTICHANNEL:-384}|eac3_multichannel_downscale"
            else
                # EAC3 <= 384 et déjà 5.1 → copy
                echo "copy|${source_codec}|0|eac3_multichannel_ok"
            fi
            return 0
        fi
        
        # AC3 source → convertir vers codec cible multichannel
        if [[ "$source_codec" == "ac3" || "$source_codec" == "a52" ]]; then
            if [[ "$effective_target_codec" == "opus" ]]; then
                # -a opus → Opus multichannel
                echo "convert|opus|${AUDIO_BITRATE_OPUS_MULTICHANNEL:-224}|ac3_to_opus_multichannel"
            else
                # Default → EAC3 multichannel
                local eac3_bitrate
                eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
                echo "convert|eac3|${eac3_bitrate}|ac3_to_eac3_multichannel"
            fi
            return 0
        fi
        
        # AAC multichannel (option B : downscale si > 320 et -a aac + --force-audio)
        if [[ "$source_codec" == "aac" || "$source_codec" == "aac_latm" ]]; then
            if [[ "$effective_target_codec" == "aac" ]]; then
                # -a aac + --force-audio (déjà traité ci-dessus si force)
                # Sans force : on garde AAC si bitrate OK
                if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -gt "${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}" ]]; then
                    echo "downscale|aac|${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}|aac_multichannel_downscale"
                elif [[ "$channels" -gt 6 ]]; then
                    echo "convert|aac|${AUDIO_BITRATE_AAC_MULTICHANNEL:-320}|aac_downmix_required"
                else
                    echo "copy|${source_codec}|0|aac_multichannel_ok"
                fi
            else
                # Cible pas AAC en multichannel → convertir vers EAC3 (défaut multichannel)
                # Sauf si source bitrate < anti-upscale threshold
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
        
        # Opus multichannel
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
                # Garder Opus si bitrate OK (efficace)
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
        
        # Autres codecs multichannel → convertir vers EAC3 (avec anti-upscale)
        if [[ "$source_bitrate_kbps" -gt 0 && "$source_bitrate_kbps" -lt "$anti_upscale_threshold" ]]; then
            echo "copy|${source_codec}|0|multichannel_anti_upscale"
        else
            local eac3_bitrate
            eac3_bitrate=$(_compute_eac3_target_bitrate_kbps "$source_bitrate_kbps")
            echo "convert|eac3|${eac3_bitrate}|multichannel_to_eac3"
        fi
        return 0
    fi
    
    # ===== Logique stéréo classique =====
    
    # Source = même codec que cible (variantes incluses)
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
    
    # Codec source EFFICACE (Opus, AAC, Vorbis) → garder si bitrate OK
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
    
    # Codec source INEFFICACE (E-AC3, AC3, MP3, etc.) → convertir vers cible
    echo "convert|${target_codec}|${target_bitrate}|inefficient_codec_convert"
}

# Analyse l'audio d'un fichier et détermine si la conversion est avantageuse.
# RÉTRO-COMPATIBILITÉ : retourne le format original source_codec|source_bitrate_kbps|should_convert
# Retourne: codec|bitrate_kbps|should_convert (0=copy, 1=convert)
# Usage: _get_audio_conversion_info <input_file> [opt_source_codec] [opt_source_bitrate_kbps]
_get_audio_conversion_info() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"
    
    # Si mode copy, toujours copier (format original)
    if [[ "${AUDIO_CODEC:-copy}" == "copy" ]]; then
        echo "copy|0|0"
        return 0
    fi
    
    local source_codec source_bitrate_kbps
    
    if [[ -n "$opt_source_codec" ]]; then
        source_codec="$opt_source_codec"
        source_bitrate_kbps="${opt_source_bitrate_kbps:-0}"
    else
        # Utiliser la fonction centralisée dans media_probe.sh
        local audio_probe
        audio_probe=$(_probe_audio_info "$input_file")
        IFS='|' read -r source_codec source_bitrate_kbps <<< "$audio_probe"
    fi
    
    # Utiliser la décision smart pour déterminer should_convert
    local decision action
    decision=$(_get_smart_audio_decision "$input_file" "$source_codec" "$source_bitrate_kbps")
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
# Usage: _should_convert_audio <input_file> [opt_source_codec] [opt_source_bitrate_kbps]
# Retourne: 0 si l'audio doit être converti/downscalé, 1 sinon
_should_convert_audio() {
    local input_file="$1"
    local opt_source_codec="${2:-}"
    local opt_source_bitrate_kbps="${3:-}"
    
    local decision action
    decision=$(_get_smart_audio_decision "$input_file" "$opt_source_codec" "$opt_source_bitrate_kbps")
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
    
    local decision action effective_codec target_bitrate reason
    decision=$(_get_smart_audio_decision "$input_file" "$opt_source_codec" "$opt_source_bitrate_kbps" "$channels")
    IFS='|' read -r action effective_codec target_bitrate reason <<< "$decision"
    
    case "$action" in
        "copy")
            # Mode copy : on garde l'audio tel quel (priorité au copy)
            echo "-c:a copy"
            ;;
        "convert"|"downscale")
            local encoder
            encoder=$(get_audio_ffmpeg_encoder "$effective_codec")
            
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
