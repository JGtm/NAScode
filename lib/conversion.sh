#!/bin/bash
###########################################################
# ORCHESTRATION DE LA CONVERSION
# Point d'entrée principal : convert_file()
# 
# Modules associés (chargés avant) :
# - skip_decision.sh : logique skip/passthrough/full
# - conversion_prep.sh : préparation chemins, fichiers temp
# - adaptive_mode.sh : mode adaptatif
# - ui.sh : messages (print_skip_message, print_conversion_info, etc.)
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. convert_file() gère ses propres codes retour pour
#    signaler skip/succès/échec sans interrompre le batch
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

# Métadonnées source (par fichier) utiles au calcul des paramètres d'encodage.
# (ex: cap « qualité équivalente » quand le codec source est moins efficace)
SOURCE_VIDEO_CODEC=""
SOURCE_VIDEO_BITRATE_BITS=""

# Flag pour savoir si on a déjà affiché des infos vidéo (downscale/10-bit)
VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=false

###########################################################
# RÉCUPÉRATION DES MÉTADONNÉES
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

###########################################################
# FONCTION DE CONVERSION PRINCIPALE
###########################################################

convert_file() {
    set -o pipefail

    local file_original="$1"
    # Windows/Git Bash : normaliser les CRLF
    file_original="${file_original//$'\r'/}"
    local output_dir="$2"

    local _processed_marked=false
    _mark_processed_once() {
        if [[ "$_processed_marked" == true ]]; then
            return 0
        fi
        _processed_marked=true
        call_if_exists increment_processed_count || true
    }

    # Protection : entrée vide ou fichier absent -> ne doit jamais bloquer le FIFO.
    if [[ -z "$file_original" ]]; then
        print_warning "$(msg MSG_CONV_EMPTY_ENTRY)"
        [[ "${LIMIT_FILES:-0}" -gt 0 ]] && call_if_exists update_queue || true
        _mark_processed_once
        return 0
    fi
    if [[ ! -f "$file_original" ]]; then
        print_warning "$(msg MSG_CONV_FILE_NOT_FOUND "$file_original")"
        [[ "${LIMIT_FILES:-0}" -gt 0 ]] && call_if_exists update_queue || true
        _mark_processed_once
        return 0
    fi
    
    # Compteurs initiaux (variables définies dans counters.sh)
    # shellcheck disable=SC2034
    CURRENT_FILE_NUMBER=$(call_if_exists increment_starting_counter) || CURRENT_FILE_NUMBER=0
    # shellcheck disable=SC2034
    LIMIT_DISPLAY_SLOT=0
    # shellcheck disable=SC2034
    VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=false
    
    # 1. Récupérer TOUTES les métadonnées en un seul appel
    local full_metadata
    if ! full_metadata=$(_convert_get_full_metadata "$file_original"); then
        print_warning "$(msg MSG_CONV_METADATA_ERROR "$file_original")"
        [[ "${LIMIT_FILES:-0}" -gt 0 ]] && call_if_exists update_queue || true
        _mark_processed_once
        return 0
    fi
    
    local v_bitrate v_codec duration_secs v_width v_height v_pix_fmt a_codec a_bitrate
    IFS='|' read -r v_bitrate v_codec duration_secs v_width v_height v_pix_fmt a_codec a_bitrate <<< "$full_metadata"

    # Exposer les métadonnées source pour les modules d'encodage.
    # shellcheck disable=SC2034
    SOURCE_VIDEO_CODEC="$v_codec"
    # shellcheck disable=SC2034
    SOURCE_VIDEO_BITRATE_BITS="$v_bitrate"
    
    # 2. Préparation des chemins (fonction dans conversion_prep.sh)
    local path_info
    if ! path_info=$(_prepare_file_paths "$file_original" "$output_dir" "$v_width" "$v_height" "$a_codec" "$a_bitrate" "$v_codec"); then
        print_error "$(msg MSG_CONV_PREP_FAILED "$file_original")"
        _mark_processed_once
        return 1
    fi
    
    IFS='|' read -r filename final_dir base_name _effective_suffix final_output <<< "$path_info"
    
    # 3. Vérifications standard (skip rapide) - fonctions dans conversion_prep.sh
    if _check_output_exists "$file_original" "$filename" "$final_output"; then
        _mark_processed_once
        return 0
    fi
    
    if _handle_dryrun_mode "$final_dir" "$final_output"; then
        _mark_processed_once
        return 0
    fi
    
    local tmp_input
    tmp_input=$(_get_temp_filename "$file_original" ".in")
    local tmp_output
    tmp_output=$(_get_temp_filename "$file_original" ".out.mkv")
    local ffmpeg_log_temp
    ffmpeg_log_temp=$(_get_temp_filename "$file_original" "_err.log")

    # Isoler l'exécution FFmpeg (two-pass logs) dans un workdir dédié par fichier.
    local job_workdir=""
    if declare -f _get_temp_workdir &>/dev/null; then
        job_workdir=$(_get_temp_workdir "$file_original")
        if [[ -n "$job_workdir" ]]; then
            mkdir -p "$job_workdir" 2>/dev/null || true
            export NASCODE_WORKDIR="$job_workdir"
        fi
    fi
    
    # 4. Décision de conversion
    if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" != true ]]; then
        # Mode standard : skip possible ici (fonctions dans skip_decision.sh)
        if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" ""; then
            [[ "$LIMIT_FILES" -gt 0 ]] && call_if_exists update_queue || true
            _mark_processed_once
            return 0
        fi
        # Réserver le slot limite
        if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
            local _slot
            _slot=$(call_if_exists increment_converted_count) || _slot="0"
            if [[ "$_slot" =~ ^[0-9]+$ && "$_slot" -gt 0 ]]; then
                # shellcheck disable=SC2034
                LIMIT_DISPLAY_SLOT="$_slot"
            fi
        fi
        _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    else
        # Mode adaptatif : analyse AVANT transfert (fonctions dans adaptive_mode.sh)
        mkdir -p "$final_dir" 2>/dev/null || true

        local adaptive_info
        adaptive_info=$(_convert_run_adaptive_analysis_and_export "$file_original" "$v_codec")

        local adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps
        local _complexity_c _complexity_desc _stddev_val
        IFS='|' read -r adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps _complexity_c _complexity_desc _stddev_val <<< "$adaptive_info"

        # IMPORTANT (bash) : l'appel via "$(...)" exécute la fonction dans un subshell,
        # donc les exports faits dans _convert_run_adaptive_analysis_and_export ne remontent pas.
        # On exporte ici dans le shell parent pour que l'encodage (transcode_video.sh)
        # utilise bien les budgets adaptatifs (AV1 comme HEVC/x265).
        if [[ "$adaptive_target_kbps" =~ ^[0-9]+$ ]] && [[ "$adaptive_maxrate_kbps" =~ ^[0-9]+$ ]] && [[ "$adaptive_bufsize_kbps" =~ ^[0-9]+$ ]]; then
            export ADAPTIVE_TARGET_KBPS="$adaptive_target_kbps"
            export ADAPTIVE_MAXRATE_KBPS="$adaptive_maxrate_kbps"
            export ADAPTIVE_BUFSIZE_KBPS="$adaptive_bufsize_kbps"
        else
            unset ADAPTIVE_TARGET_KBPS ADAPTIVE_MAXRATE_KBPS ADAPTIVE_BUFSIZE_KBPS
        fi

        # Skip avec seuil adaptatif (avant transfert)
        if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" "$adaptive_maxrate_kbps"; then
            print_conversion_not_required
            [[ "$LIMIT_FILES" -gt 0 ]] && call_if_exists update_queue || true
            _mark_processed_once
            return 0
        fi

        print_conversion_required "$v_codec" "$v_bitrate"

        # Réserver le slot limite après l'analyse (évite les slots "gâchés")
        if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
            local _slot
            _slot=$(call_if_exists increment_converted_count) || _slot="0"
            if [[ "$_slot" =~ ^[0-9]+$ && "$_slot" -gt 0 ]]; then
                # shellcheck disable=SC2034
                LIMIT_DISPLAY_SLOT="$_slot"
            fi
        fi

        # Maintenant qu'on sait qu'on ne skip pas : démarrage + log START
        _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    fi

    if ! _check_disk_space "$file_original"; then
        _mark_processed_once
        return 1
    fi
    
    local size_before_mb
    size_before_mb=$(du -m "$file_original" | awk '{print $1}')
    
    # 5. Téléchargement vers stockage temporaire (fonction dans conversion_prep.sh)
    if ! _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp"; then
        _mark_processed_once
        return 1
    fi
    
    # 6. Messages informatifs (fonction dans ui.sh)
    print_conversion_info "$v_codec" "$tmp_input" "$v_width" "$v_height" "$v_pix_fmt" "$a_codec" "$a_bitrate"
    
    # 7. Exécution de la conversion (fonctions dans transcode_video.sh / ffmpeg_pipeline.sh)
    local conversion_success=false
    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        _execute_video_passthrough "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name" && conversion_success=true
    else
        _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name" && conversion_success=true
    fi
    
    # 8. Finalisation (fonctions dans finalize.sh)
    if [[ "$conversion_success" == true ]]; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$size_before_mb"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi

    # Nettoyer le workdir dédié (best-effort)
    if [[ -n "${NASCODE_WORKDIR:-}" ]] && [[ -n "$job_workdir" ]] && [[ "$job_workdir" == "$NASCODE_WORKDIR" ]]; then
        rm -rf -- "$job_workdir" 2>/dev/null || true
        unset NASCODE_WORKDIR
    fi
    
    _mark_processed_once
}
