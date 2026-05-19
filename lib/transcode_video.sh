#!/bin/bash
###########################################################
# ENCODAGE VIDÉO
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. L'encodage FFmpeg peut retourner des codes non-zéro
#    dans des cas gérés (interruption propre, etc.)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

# Texte affiché dans la barre de progression FFmpeg
# Pour afficher le nom du fichier : PROGRESS_DISPLAY_TEXT="$base_name"
# Pour afficher un texte fixe : PROGRESS_DISPLAY_TEXT="Traitement en cours"
PROGRESS_DISPLAY_TEXT_USE_FILENAME=false  # true = nom du fichier, false = texte fixe
# Note: PROGRESS_DISPLAY_TEXT_FIXED est défini dynamiquement via _get_progress_display_text_fixed()
# pour respecter le changement de langue via --lang (évalué après le parsing des arguments).

_get_progress_display_text_fixed() {
    echo "$(msg MSG_UI_PROGRESS_PROCESSING)"
}

###########################################################
# SOUS-FONCTIONS ENCODAGE (FORMAT / SCALE)
###########################################################

# Note: les fonctions suivantes sont désormais centralisées dans :
# - lib/video_params.sh : _select_output_pix_fmt, _build_downscale_filter_if_needed,
#   _compute_output_height_for_bitrate, _compute_effective_bitrate_kbps_for_height,
#   _build_effective_suffix_for_dims
# - lib/stream_mapping.sh : _build_stream_mapping

###########################################################
# SOUS-FONCTIONS D'ENCODAGE (PASS 1 / PASS 2)
###########################################################

# Prépare les paramètres vidéo adaptés au fichier source (bitrate, filtres, etc.)
# Retourne via variables globales : VIDEO_BITRATE, VIDEO_MAXRATE, VIDEO_BUFSIZE,
#                                   X265_VBV_STRING, VIDEO_FILTER_OPTS, OUTPUT_PIX_FMT
# En mode adaptatif, utilise les variables ADAPTIVE_TARGET_KBPS, ADAPTIVE_MAXRATE_KBPS,
# ADAPTIVE_BUFSIZE_KBPS si elles sont définies.
_setup_video_encoding_params() {
    local input_file="$1"

    local base_codec="${VIDEO_CODEC:-hevc}"
    local effective_codec="${EFFECTIVE_VIDEO_CODEC:-$base_codec}"

    # Encodeur effectif : peut différer si on encode dans un codec différent de VIDEO_CODEC.
    local encoder="${EFFECTIVE_VIDEO_ENCODER:-${VIDEO_ENCODER:-}}"
    if [[ -z "$encoder" ]] && declare -f get_codec_encoder &>/dev/null; then
        encoder=$(get_codec_encoder "$effective_codec")
    fi
    [[ -z "$encoder" ]] && encoder="libx265"
    
    # Récupérer les propriétés du flux vidéo source
    local input_props
    input_props=$(get_video_stream_props "$input_file")
    local input_width input_height input_pix_fmt
    IFS='|' read -r input_width input_height input_pix_fmt <<< "$input_props"

    # Pixel format de sortie (10-bit si source 10-bit)
    OUTPUT_PIX_FMT=$(_select_output_pix_fmt "$input_pix_fmt")

    # Filtre de downscale si nécessaire
    local downscale_filter
    downscale_filter=$(_build_downscale_filter_if_needed "$input_width" "$input_height")
    
    VIDEO_FILTER_OPTS=""
    if [[ -n "$downscale_filter" ]]; then
        VIDEO_FILTER_OPTS="-vf $downscale_filter"
        if [[ "$NO_PROGRESS" != true ]] && [[ "${VIDEO_PRECONVERSION_VIDEOINFO_SHOWN:-false}" != true ]]; then
            local downscale_msg
            downscale_msg=$(msg MSG_UI_DOWNSCALE "$input_width" "$input_height" "$DOWNSCALE_MAX_WIDTH" "$DOWNSCALE_MAX_HEIGHT")
            if declare -f ui_print_raw &>/dev/null; then
                ui_print_raw "${CYAN}  ⬇️  ${downscale_msg}${NOCOLOR}"
            else
                echo -e "${CYAN}  ⬇️  ${downscale_msg}${NOCOLOR}"
            fi
        fi
    fi
    
    # Affichage 10-bit si applicable
    if [[ "$NO_PROGRESS" != true ]] && [[ -n "$input_pix_fmt" ]] && [[ "${VIDEO_PRECONVERSION_VIDEOINFO_SHOWN:-false}" != true ]]; then
        if [[ "$OUTPUT_PIX_FMT" == "yuv420p10le" ]]; then
            if declare -f ui_print_raw &>/dev/null; then
                ui_print_raw "${CYAN}  🎨 $(msg MSG_UI_10BIT)${NOCOLOR}"
            else
                echo -e "${CYAN}  🎨 $(msg MSG_UI_10BIT)${NOCOLOR}"
            fi
        fi
    fi

    # Calcul du bitrate selon le mode
    local effective_target effective_maxrate effective_bufsize
    
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]] && \
       [[ -n "${ADAPTIVE_TARGET_KBPS:-}" ]] && [[ "${ADAPTIVE_TARGET_KBPS}" =~ ^[0-9]+$ ]]; then
        # Mode adaptatif : utiliser les paramètres calculés par analyse de complexité
        # (Bitrate déjà affiché par display_complexity_analysis)
        effective_target="${ADAPTIVE_TARGET_KBPS}"
        effective_maxrate="${ADAPTIVE_MAXRATE_KBPS}"
        effective_bufsize="${ADAPTIVE_BUFSIZE_KBPS}"

        # Si on encode dans un codec différent (no-downgrade), traduire le budget bitrate.
        if [[ "$effective_codec" != "$base_codec" ]] && declare -f translate_bitrate_kbps_between_codecs &>/dev/null; then
            effective_target=$(translate_bitrate_kbps_between_codecs "$effective_target" "$base_codec" "$effective_codec")
            effective_maxrate=$(translate_bitrate_kbps_between_codecs "$effective_maxrate" "$base_codec" "$effective_codec")
            effective_bufsize=$(translate_bitrate_kbps_between_codecs "$effective_bufsize" "$base_codec" "$effective_codec")
        fi
    else
        # Mode standard : calcul basé sur la résolution de sortie
        local output_height
        output_height=$(_compute_output_height_for_bitrate "$input_width" "$input_height")

        effective_target=$(_compute_effective_bitrate_kbps_for_height "${TARGET_BITRATE_KBPS}" "$output_height")
        effective_maxrate=$(_compute_effective_bitrate_kbps_for_height "${MAXRATE_KBPS}" "$output_height")
        effective_bufsize=$(_compute_effective_bitrate_kbps_for_height "${BUFSIZE_KBPS}" "$output_height")

        # Traduire le budget bitrate vers le codec effectif si nécessaire.
        if [[ "$effective_codec" != "$base_codec" ]] && declare -f translate_bitrate_kbps_between_codecs &>/dev/null; then
            effective_target=$(translate_bitrate_kbps_between_codecs "$effective_target" "$base_codec" "$effective_codec")
            effective_maxrate=$(translate_bitrate_kbps_between_codecs "$effective_maxrate" "$base_codec" "$effective_codec")
            effective_bufsize=$(translate_bitrate_kbps_between_codecs "$effective_bufsize" "$base_codec" "$effective_codec")
        fi
    fi

    # Cap "qualité équivalente" : si la source est dans un codec moins efficace que
    # le codec d'encodage effectif, plafonner le budget pour éviter de gonfler le bitrate.
    # Ne change pas la décision de skip : uniquement les paramètres d'encodage.
    local src_codec="${SOURCE_VIDEO_CODEC:-}"
    local src_bitrate_bits="${SOURCE_VIDEO_BITRATE_BITS:-}"
    if [[ "${VIDEO_EQUIV_QUALITY_CAP:-true}" == true ]] && \
       [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" != true ]] && \
       [[ -n "$src_codec" ]] && [[ "$src_bitrate_bits" =~ ^[0-9]+$ ]] && [[ "$src_bitrate_bits" -gt 0 ]]; then
        if ! is_codec_better_or_equal "$src_codec" "$effective_codec"; then
            local src_kbps=$((src_bitrate_bits / 1000))
            if [[ "$src_kbps" -gt 0 ]] && [[ "$effective_target" =~ ^[0-9]+$ ]] && [[ "$effective_target" -gt 0 ]]; then
                local cap_kbps="$src_kbps"
                if declare -f translate_bitrate_kbps_between_codecs &>/dev/null; then
                    cap_kbps=$(translate_bitrate_kbps_between_codecs "$src_kbps" "$src_codec" "$effective_codec")
                fi

                if [[ "$cap_kbps" =~ ^[0-9]+$ ]] && [[ "$cap_kbps" -gt 0 ]] && [[ "$cap_kbps" -lt "$effective_target" ]]; then
                    local original_target_kbps="$effective_target"
                    effective_target="$cap_kbps"

                    if [[ "$effective_maxrate" =~ ^[0-9]+$ ]] && [[ "$effective_maxrate" -gt 0 ]]; then
                        effective_maxrate=$((effective_maxrate * cap_kbps / original_target_kbps))
                    fi
                    if [[ "$effective_bufsize" =~ ^[0-9]+$ ]] && [[ "$effective_bufsize" -gt 0 ]]; then
                        effective_bufsize=$((effective_bufsize * cap_kbps / original_target_kbps))
                    fi

                    [[ "$effective_maxrate" -lt "$effective_target" ]] && effective_maxrate="$effective_target"
                    [[ "$effective_bufsize" -lt "$effective_maxrate" ]] && effective_bufsize="$effective_maxrate"
                fi
            fi
        fi
    fi

    VIDEO_BITRATE="${effective_target}k"
    VIDEO_MAXRATE="${effective_maxrate}k"
    VIDEO_BUFSIZE="${effective_bufsize}k"
    
    # Construire les paramètres de base pour l'encodeur (VBV + mode extras)
    # Pour x265: "vbv-maxrate=X:vbv-bufsize=Y:amp=0:rect=0:..."
    # Pour svtav1: "tune=0:film-grain=8:..."
    local vbv_params=""
    
    # Paramètres VBV selon l'encodeur
    case "$encoder" in
        libx265)
            vbv_params="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"
            ;;
        libsvtav1|libaom-av1)
            # Ces encodeurs utilisent -maxrate/-bufsize directement via FFmpeg
            vbv_params=""
            ;;
    esac
    
    # Ajouter les paramètres spécifiques au mode (tuning, optimisations)
    local mode_params="${EFFECTIVE_ENCODER_MODE_PARAMS:-${ENCODER_MODE_PARAMS:-}}"
    if [[ -z "$mode_params" ]] && declare -f get_encoder_mode_params &>/dev/null; then
        mode_params=$(get_encoder_mode_params "$encoder" "${ENCODER_MODE_PROFILE:-${CONVERSION_MODE:-serie}}")
    fi
    
    # Combiner VBV + mode params
    ENCODER_BASE_PARAMS="$vbv_params"
    if [[ -n "$mode_params" ]]; then
        if [[ -n "$ENCODER_BASE_PARAMS" ]]; then
            ENCODER_BASE_PARAMS="${ENCODER_BASE_PARAMS}:${mode_params}"
        else
            ENCODER_BASE_PARAMS="$mode_params"
        fi
    fi

    # SVT-AV1: paramètres spécifiques via -svtav1-params
    if [[ "$encoder" == "libsvtav1" ]]; then
        # Keyint (en plus du -g générique) pour cohérence
        if [[ "$ENCODER_BASE_PARAMS" != *"keyint="* ]]; then
            local mode_keyint
            mode_keyint="${FILM_KEYINT:-600}"
            if [[ -n "$mode_keyint" ]]; then
                if [[ -n "$ENCODER_BASE_PARAMS" ]]; then
                    ENCODER_BASE_PARAMS="${ENCODER_BASE_PARAMS}:keyint=${mode_keyint}"
                else
                    ENCODER_BASE_PARAMS="keyint=${mode_keyint}"
                fi
            fi
        fi
        
        # CRF plafonné : SVT-AV1 (via FFmpeg) n'accepte pas forcément les clés
        # "max-bitrate" / "buffer-size" dans -svtav1-params (selon build).
        # En pratique, le couple rc=0 + mbr=<kbps> déclenche bien le mode "capped CRF".
        if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
            if [[ "$ENCODER_BASE_PARAMS" != *"rc="* ]]; then
                if [[ -n "$ENCODER_BASE_PARAMS" ]]; then
                    ENCODER_BASE_PARAMS="${ENCODER_BASE_PARAMS}:rc=0"
                else
                    ENCODER_BASE_PARAMS="rc=0"
                fi
            fi

            if [[ "$ENCODER_BASE_PARAMS" != *"mbr="* ]]; then
                if [[ "$effective_maxrate" =~ ^[0-9]+$ ]] && [[ "$effective_maxrate" -gt 0 ]]; then
                    if [[ -n "$ENCODER_BASE_PARAMS" ]]; then
                        ENCODER_BASE_PARAMS="${ENCODER_BASE_PARAMS}:mbr=${effective_maxrate}"
                    else
                        ENCODER_BASE_PARAMS="mbr=${effective_maxrate}"
                    fi
                fi
            fi
        fi
    fi
    
    # Rétro-compatibilité : garder X265_VBV_STRING pour les tests existants
    # shellcheck disable=SC2034
    X265_VBV_STRING="vbv-maxrate=${effective_maxrate}:vbv-bufsize=${effective_bufsize}"
}

###########################################################
# ENCODAGE UNIFIÉ
###########################################################

# Note: get_encoder_params_flag() est définie dans codec_profiles.sh et exportée.
# Ne pas dupliquer ici.

# Retire/désactive les options SVT-AV1 incompatibles avec un encodage multi-pass.
# Usage: _nascode_strip_svtav1_multipass_incompat "tune=0:enable-overlays=1:film-grain=8:keyint=240"
# SVT-AV1 refuse explicitement enable-overlays=1 et film-grain=N (>0) en multi-pass
# ("The overlay frames feature is currently not supported with multi-pass encoding").
# On force enable-overlays=0 et on supprime film-grain/film-grain-denoise plutôt que
# de planter l'encodage avant la pass1.
_nascode_strip_svtav1_multipass_incompat() {
    local params="${1:-}"
    [[ -z "$params" ]] && { echo ""; return 0; }
    params=$(printf '%s' "$params" | sed -E \
        -e 's/(^|:)enable-overlays=[^:]*/\1enable-overlays=0/g' \
        -e 's/(^|:)film-grain=[^:]*//g' \
        -e 's/(^|:)film-grain-denoise=[^:]*//g' \
        -e 's/::+/:/g' \
        -e 's/^://' \
        -e 's/:$//')
    echo "$params"
}

# Indique si l'on doit ajouter les options FFmpeg de premier niveau
# `-maxrate <X> -bufsize <Y>` pour ce couple (encodeur, mode).
# Usage: _should_emit_maxrate_flag "libsvtav1" "pass1" -> retourne 1 (non)
# SVT-AV1 rejette -maxrate hors mode CRF ("Max Bitrate only supported with CRF mode") :
# en two-pass on est en ABR avec -b:v, le couple est incompatible.
# x265 et libaom acceptent -maxrate en multi-pass, on garde le comportement.
_should_emit_maxrate_flag() {
    local encoder="${1:-libx265}"
    local mode="${2:-crf}"
    if [[ "$encoder" == "libsvtav1" && "$mode" != "crf" ]]; then
        return 1
    fi
    return 0
}

# Construit les paramètres internes de l'encodeur
# Usage: _build_encoder_params_internal "libx265" "pass1" "vbv-maxrate=2520:vbv-bufsize=3780"
_build_encoder_params_internal() {
    local encoder="${1:-libx265}"
    local mode="$2"           # pass1, pass2, crf
    local base_params="$3"    # VBV params et extras

    local full_params=""

    case "$encoder" in
        libx265)
            # x265 : paramètres classiques avec pass=N pour two-pass
            case "$mode" in
                "pass1")
                    full_params="pass=1:${base_params}"
                    if [[ "${X265_PASS1_FAST:-false}" == true ]]; then
                        full_params="${full_params}:no-slow-firstpass=1"
                    fi
                    ;;
                "pass2")
                    full_params="pass=2:${base_params}"
                    ;;
                "crf")
                    full_params="${base_params}"
                    ;;
            esac
            ;;

        libsvtav1)
            # SVT-AV1 : paramètres via -svtav1-params.
            # IMPORTANT : le multi-pass entre invocations ffmpeg séparées N'EST PAS
            # supporté par le wrapper libsvtav1 (RC stats gardées en mémoire ; les
            # clés `stats=`, `passes=` sont rejetées ; `pass=` n'écrit rien).
            # → `_execute_conversion` force le mode "crf" pour cet encodeur ;
            #   les branches pass1/pass2 ci-dessous sont conservées en garde-fou
            #   défensif au cas où l'appelant outrepasserait la décision.
            case "$mode" in
                "pass1"|"pass2")
                    local pass_num="${mode#pass}"
                    local sanitized
                    sanitized=$(_nascode_strip_svtav1_multipass_incompat "$base_params")
                    full_params="pass=${pass_num}"
                    [[ -n "$sanitized" ]] && full_params="${full_params}:${sanitized}"
                    ;;
                "crf")
                    full_params="${base_params}"
                    ;;
            esac
            ;;
            
        libaom-av1)
            # libaom-av1 : pas de params flag, utilise -pass directement
            # Les paramètres seront gérés différemment
            full_params=""
            ;;
            
        *)
            full_params="${base_params}"
            ;;
    esac
    
    echo "$full_params"
}

# Construit les paramètres spécifiques à l'encodeur pour FFmpeg

# Retourne l'option -tune appropriée pour l'encodeur
# Usage: _get_tune_option <encoder>
_get_tune_option() {
    local encoder="${1:-libx265}"
    
    # Seul x265 supporte -tune fastdecode comme option directe.
    # Désactivé par défaut : x265 4.x active dhdr10-info avec cette option,
    # provoquant un segfault si aucune donnée HDR10+ n'est présente.
    if [[ "$encoder" == "libx265" ]]; then
        if [[ "${FILM_TUNE_FASTDECODE:-false}" == true ]]; then
            echo "-tune fastdecode"
            return
        fi
    fi
    # Les autres encodeurs gèrent le tune via leurs params internes
    echo ""
}

# Retourne l'option preset appropriée pour l'encodeur
# Usage: _get_preset_option <encoder> <preset>
_get_preset_option() {
    local encoder="${1:-libx265}"
    local preset="${2:-medium}"
    
    case "$encoder" in
        libx265)
            echo "-preset $preset"
            ;;
        libsvtav1)
            # SVT-AV1 utilise -preset avec des valeurs numériques 0-13
            local svt_preset
            if [[ -n "${SVTAV1_PRESET:-}" ]]; then
                svt_preset="$SVTAV1_PRESET"
            elif [[ -n "${SVTAV1_PRESET_DEFAULT:-}" ]]; then
                svt_preset="$SVTAV1_PRESET_DEFAULT"
            else
                svt_preset=$(convert_preset "$preset" "libsvtav1")
            fi
            echo "-preset $svt_preset"
            ;;
        libaom-av1)
            # libaom utilise -cpu-used au lieu de -preset (géré séparément)
            echo ""
            ;;
        *)
            echo "-preset $preset"
            ;;
    esac
}

# Retourne l'option bitrate/CRF appropriée pour l'encodeur et le mode
# Usage: _get_bitrate_option <encoder> <mode>
_get_bitrate_option() {
    local encoder="${1:-libx265}"
    local mode="$2"  # crf ou autre
    
    if [[ "$mode" == "crf" ]]; then
        case "$encoder" in
            libx265)
                echo "-crf $CRF_VALUE"
                ;;
            libsvtav1)
                # SVT-AV1 utilise -crf aussi (0-63, défaut ~35)
                # Valeur configurable (commande type: -crf 32)
                local svt_crf=""
                if [[ -n "${SVTAV1_CRF:-}" ]]; then
                    svt_crf="$SVTAV1_CRF"
                elif [[ -n "${SVTAV1_CRF_DEFAULT:-}" ]]; then
                    svt_crf="$SVTAV1_CRF_DEFAULT"
                else
                    # Mapping approximatif : CRF x265 21 ≈ CRF SVT-AV1 30
                    svt_crf=$(( CRF_VALUE + 9 ))
                fi
                [[ $svt_crf -gt 63 ]] && svt_crf=63
                echo "-crf $svt_crf"
                ;;
            libaom-av1)
                # libaom utilise -crf aussi (0-63)
                local aom_crf=$(( CRF_VALUE + 9 ))
                [[ $aom_crf -gt 63 ]] && aom_crf=63
                echo "-crf $aom_crf"
                ;;
            *)
                echo "-crf $CRF_VALUE"
                ;;
        esac
    else
        echo "-b:v $VIDEO_BITRATE"
    fi
}

###########################################################
# Debug optionnel : capture SVT-AV1 "capped CRF" sans spam terminal
###########################################################

_nascode_is_truthy() {
    local v="${1:-}"
    [[ "$v" == "1" || "$v" == "true" || "$v" == "TRUE" || "$v" == "yes" || "$v" == "YES" ]]
}

_nascode_get_ffmpeg_loglevel_for_encoder() {
    local enc="${1:-}"

    # Par défaut, on garde un niveau bas pour ne pas noyer l'utilisateur.
    # NB: la sortie FFmpeg est redirigée vers un fichier, donc même 'info' ne spamme pas le terminal.
    if _nascode_is_truthy "${NASCODE_LOG_SVT_CONFIG:-0}" && [[ "$enc" == "libsvtav1" ]]; then
        echo "info"
        return 0
    fi

    echo "warning"
}

_nascode_maybe_write_svt_config_log() {
    local enc="${1:-}"
    local ffmpeg_stderr_log="${2:-}"
    local base="${3:-}"
    local input="${4:-}"
    local output="${5:-}"
    local encoder_specific="${6:-}"

    if ! _nascode_is_truthy "${NASCODE_LOG_SVT_CONFIG:-0}"; then
        return 0
    fi
    if [[ "$enc" != "libsvtav1" ]]; then
        return 0
    fi
    if [[ -z "$ffmpeg_stderr_log" || ! -f "$ffmpeg_stderr_log" ]]; then
        return 0
    fi

    local safe_name
    safe_name=$(printf "%s" "$base" | tr -c 'A-Za-z0-9._-' '_')
    safe_name=${safe_name:0:80}

    local log_dir="${LOG_DIR:-./logs}"
    mkdir -p "$log_dir" 2>/dev/null || true

    local out_log="$log_dir/SVT_${EXECUTION_TIMESTAMP}_${safe_name}.log"

    {
        echo "# NAScode - SVT-AV1 config extract"
        echo "# date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# input: $input"
        echo "# output: $output"
        echo "# encoder_specific_opts: ${encoder_specific:-<empty>}"
        echo
        grep -E 'Svt\[info\]: SVT \[config\]|capped CRF|max bitrate|BRC mode' "$ffmpeg_stderr_log" 2>/dev/null || true
    } > "$out_log" 2>/dev/null || true

    if [[ ! -s "$out_log" ]] || ! grep -qE 'Svt\[info\]: SVT \[config\]|capped CRF|max bitrate|BRC mode' "$out_log" 2>/dev/null; then
        rm -f "$out_log" 2>/dev/null || true
        return 0
    fi

    if [[ -n "${LOG_SESSION:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SVT_CONFIG_LOG | $out_log" >> "$LOG_SESSION" 2>/dev/null || true
    fi
}

# Exécute un encodage ffmpeg avec le mode spécifié.
# Usage: _run_ffmpeg_encode <mode> <input_file> <output_file> <ffmpeg_log> <base_name> 
#                           <encoder_base_params> <audio_params> <stream_mapping>
#                           <progress_slot> <is_parallel> <awk_time_func>
# Modes: "pass1" (analyse), "pass2" (encodage two-pass), "crf" (single-pass)
# Retourne: 0 si succès, 1 si erreur
_run_ffmpeg_encode() {
    local mode="$1"
    local input_file="$2"
    local output_file="$3"
    local ffmpeg_log="$4"
    local base_name="$5"
    local encoder_base_params="$6"
    local audio_params="$7"
    local stream_mapping="$8"
    local progress_slot="$9"
    local is_parallel="${10}"
    local awk_time_func="${11}"

    START_TS="$(date +%s)"
    
    # Encodeur à utiliser (défaut: libx265 pour rétro-compatibilité)
    local encoder="${EFFECTIVE_VIDEO_ENCODER:-${VIDEO_ENCODER:-libx265}}"
    
    # Construire les options hwaccel (vide si non disponible = fallback software)
    local hwaccel_opts=""
    if [[ -n "${HWACCEL:-}" && "${HWACCEL}" != "none" ]]; then
        hwaccel_opts="-hwaccel $HWACCEL"
    fi

    # Configuration selon le mode
    local audio_opt stream_opt log_suffix emoji end_msg
    
    case "$mode" in
        "pass1")
            audio_opt="-an"
            stream_opt=""
            log_suffix=".pass1"
            emoji="🔍"
            end_msg="$(msg MSG_PROGRESS_ANALYSIS_OK)"
            ;;
        "pass2")
            audio_opt="$audio_params"
            stream_opt="$stream_mapping -f matroska"
            log_suffix=""
            emoji="🎬"
            end_msg="$(msg MSG_PROGRESS_DONE)"
            ;;
        "crf")
            audio_opt="$audio_params"
            stream_opt="$stream_mapping -f matroska"
            log_suffix=""
            emoji="⚡"
            end_msg="$(msg MSG_PROGRESS_DONE)"
            ;;
        *)
            log_error "$(msg MSG_TRANSCODE_UNKNOWN_MODE "$mode")"
            return 1
            ;;
    esac

    # Paramètres GOP selon le mode (film: 240, série: 600)
    local keyint_value="${FILM_KEYINT:-600}"
    
    # Texte à afficher dans la barre de progression
    local progress_display_text
    if [[ "$PROGRESS_DISPLAY_TEXT_USE_FILENAME" == true ]]; then
        progress_display_text="$base_name"
    else
        progress_display_text="$(_get_progress_display_text_fixed)"
    fi
    
    # Options spécifiques à l'encodeur
    local tune_opt preset_opt bitrate_opt
    tune_opt=$(_get_tune_option "$encoder")
    preset_opt=$(_get_preset_option "$encoder" "$ENCODER_PRESET")
    bitrate_opt=$(_get_bitrate_option "$encoder" "$mode")

    
    # Construire les paramètres encodeur spécifiques
    local encoder_params_flag encoder_full_params
    encoder_params_flag=$(get_encoder_params_flag "$encoder")
    encoder_full_params=$(_build_encoder_params_internal "$encoder" "$mode" "$encoder_base_params")

    # Construire les options encodeur spécifiques (vide si non applicable)
    local encoder_specific_opts=""
    if [[ -n "$encoder_params_flag" && -n "$encoder_full_params" ]]; then
        encoder_specific_opts="$encoder_params_flag $encoder_full_params"
    fi

    # Exécution FFmpeg unifiée
    local -a cmd
    cmd=()

    # Préfixe (ionice) si disponible
    if [[ -n "${IO_PRIORITY_CMD:-}" ]]; then
        _cmd_append_words cmd "$IO_PRIORITY_CMD"
    fi

    local ffmpeg_loglevel
    ffmpeg_loglevel=$(_nascode_get_ffmpeg_loglevel_for_encoder "$encoder")
    cmd+=(ffmpeg -y -loglevel "$ffmpeg_loglevel")

    # Augmenter probesize/analyzeduration pour les remux Blu-ray avec de nombreux streams
    # (sous-titres PGS, plusieurs pistes audio) dont les paramètres nécessitent plus de données.
    # Valeur configurable via FFMPEG_PROBESIZE (défaut : 100M).
    cmd+=(-probesize "${FFMPEG_PROBESIZE:-100M}" -analyzeduration "${FFMPEG_ANALYZEDURATION:-100M}")

    # Ces variables sont historiquement des strings contenant plusieurs options.
    # On les split volontairement en mots (contrôlé en interne) pour éviter les expansions non-quotées.
    _cmd_append_words cmd "${SAMPLE_SEEK_PARAMS:-}"
    _cmd_append_words cmd "$hwaccel_opts"

    cmd+=(-i "$input_file")

    _cmd_append_words cmd "${SAMPLE_DURATION_PARAMS:-}"
    _cmd_append_words cmd "$VIDEO_FILTER_OPTS"

    # Conservation des métadonnées (titres, tags, chapitres) du fichier source.
    # On n'applique pas en pass1 car la sortie est /dev/null (analyse seule).
    if [[ "${KEEP_METADATA:-false}" == true ]] && [[ "$mode" != "pass1" ]]; then
        cmd+=(-map_metadata 0 -map_chapters 0)
    fi

    cmd+=(-pix_fmt "$OUTPUT_PIX_FMT")
    cmd+=(-g "$keyint_value" -keyint_min "$keyint_value")
    cmd+=(-c:v "$encoder")

    _cmd_append_words cmd "$preset_opt"
    _cmd_append_words cmd "$tune_opt"
    _cmd_append_words cmd "$bitrate_opt"
    _cmd_append_words cmd "$encoder_specific_opts"

    if _should_emit_maxrate_flag "$encoder" "$mode"; then
        cmd+=(-maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE")
    fi

    _cmd_append_words cmd "$audio_opt"
    _cmd_append_words cmd "$stream_opt"

    case "$mode" in
        "pass1")
            cmd+=(-f null /dev/null)
            ;;
        *)
            cmd+=("$output_file")
            ;;
    esac

    # Garder l'ordre historique (output puis progress) pour minimiser le risque de régression.
    cmd+=(-progress pipe:1 -nostats)

    if [[ -n "${NASCODE_WORKDIR:-}" ]] && [[ -d "${NASCODE_WORKDIR}" ]]; then
        (cd "${NASCODE_WORKDIR}" && "${cmd[@]}" 2> "${ffmpeg_log}${log_suffix}") | \
            awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
                -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
                -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="$emoji" -v END_MSG="$end_msg" \
                -v PROGRESS_MARKER_FILE="${PROGRESS_MARKER_FILE:-}" -v PROGRESS_MARKER_DELAY="${PROGRESS_MARKER_DELAY:-15}" \
                "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
    else
        "${cmd[@]}" 2> "${ffmpeg_log}${log_suffix}" | \
            awk -v DURATION="$EFFECTIVE_DURATION" -v CURRENT_FILE_NAME="$progress_display_text" -v NOPROG="$NO_PROGRESS" \
                -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" \
                -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v EMOJI="$emoji" -v END_MSG="$end_msg" \
                -v PROGRESS_MARKER_FILE="${PROGRESS_MARKER_FILE:-}" -v PROGRESS_MARKER_DELAY="${PROGRESS_MARKER_DELAY:-15}" \
                "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
    fi

    # CRITIQUE : capturer PIPESTATUS immédiatement après le pipeline
    local ffmpeg_rc=${PIPESTATUS[0]:-0}
    local awk_rc=${PIPESTATUS[1]:-0}

    if [[ "$ffmpeg_rc" -eq 0 && "$awk_rc" -eq 0 ]]; then
        # Option debug: extraire la config SVT-AV1 sans spammer le terminal.
        # NB: si NASCODE_LOG_SVT_CONFIG=1, on a utilisé -loglevel info pour rendre ces lignes disponibles.
        _nascode_maybe_write_svt_config_log "$encoder" "${ffmpeg_log}${log_suffix}" "$base_name" "$input_file" "${output_file:-}" "$encoder_specific_opts"
        return 0
    fi
    
    # Gestion d'erreur - ne pas afficher les logs si interruption volontaire
    # Code 255 = signal reçu, 130 = SIGINT (128+2), 143 = SIGTERM (128+15)
    if [[ "${_INTERRUPTED:-0}" -ne 1 && "$ffmpeg_rc" -ne 255 && "$ffmpeg_rc" -lt 128 ]]; then
        local log_file="${ffmpeg_log}${log_suffix}"
        if [[ "$mode" == "pass1" ]]; then
            log_error "$(msg MSG_TRANSCODE_PASS1_ERROR)"
        fi
        if [[ -f "$log_file" ]]; then
            echo "--- $(msg MSG_TRANSCODE_FFMPEG_LOG "$log_file") ---" >&2
            tail -n 40 "$log_file" >&2 || true
            echo "--- End ffmpeg log ---" >&2
        fi
    fi
    return 1
}

# Note: Les fonctions _ffmpeg_pipeline_*, _setup_sample_mode_params, _execute_ffmpeg_pipeline,
# _execute_video_passthrough et _execute_conversion sont maintenant dans lib/ffmpeg_pipeline.sh
