#!/bin/bash
###########################################################
# MODE ADAPTATIF (FILM-ADAPTIVE)
# Analyse de complexité et export des paramètres adaptatifs
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. L'analyse peut échouer (fallback aux valeurs par défaut)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

# Variables exportées pour les modules d'encodage
# (définies par _convert_run_adaptive_analysis_and_export)
# ADAPTIVE_TARGET_KBPS, ADAPTIVE_MAXRATE_KBPS, ADAPTIVE_BUFSIZE_KBPS

###########################################################
# ANALYSE ET EXPORT
###########################################################

# Lance l'analyse de complexité et exporte les paramètres adaptatifs.
# Usage: _convert_run_adaptive_analysis_and_export <file_to_analyze> [source_video_codec]
# Retourne: adaptive_target_kbps|adaptive_maxrate_kbps|adaptive_bufsize_kbps|complexity_c|complexity_desc|stddev_val|si_avg|ti_avg
# Effets de bord: export ADAPTIVE_*_KBPS, affichage UX
_convert_run_adaptive_analysis_and_export() {
    local file_to_analyze="$1"
    local source_video_codec="${2:-}"

    local adaptive_params
    adaptive_params=$(compute_video_params_adaptive "$file_to_analyze")

    # Format étendu avec SI/TI:
    # pix_fmt|filter_opts|bitrate|maxrate|bufsize|vbv_string|output_height|input_width|input_height|input_pix_fmt|complexity_C|complexity_desc|stddev|target_kbps|si_avg|ti_avg
    local _pix _flt _br _mr _bs _vbv _oh _iw _ih _ipf
    local complexity_c complexity_desc stddev_val adaptive_target_kbps si_avg ti_avg
    IFS='|' read -r _pix _flt _br _mr _bs _vbv _oh _iw _ih _ipf complexity_c complexity_desc stddev_val adaptive_target_kbps si_avg ti_avg <<< "$adaptive_params"

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

    display_complexity_analysis "$file_to_analyze" "$complexity_c" "$complexity_desc" "$stddev_val" "$adaptive_target_kbps" "$si_avg" "$ti_avg" >&2

    # Option B (UX, conditionnelle) : afficher le seuil de skip uniquement quand il
    # a du sens (source déjà dans un codec meilleur/égal au codec cible).
    if [[ "${UI_QUIET:-false}" != true ]]; then
        local show_skip_threshold=false
        if [[ -n "$source_video_codec" ]] && declare -f is_codec_better_or_equal &>/dev/null; then
            if is_codec_better_or_equal "$source_video_codec" "$target_codec"; then
                show_skip_threshold=true
            fi
        fi

        if [[ "$show_skip_threshold" == true ]]; then
            local skip_tolerance_percent="${SKIP_TOLERANCE_PERCENT:-10}"
            if [[ ! "$skip_tolerance_percent" =~ ^[0-9]+$ ]]; then
                skip_tolerance_percent=10
            fi

            local compare_codec="$source_video_codec"
            local compare_maxrate_kbps="$adaptive_maxrate_kbps"
            if [[ "$compare_codec" != "$target_codec" ]] && declare -f translate_bitrate_kbps_between_codecs &>/dev/null; then
                compare_maxrate_kbps=$(translate_bitrate_kbps_between_codecs "$adaptive_maxrate_kbps" "$target_codec" "$compare_codec")
            fi

            if [[ -z "$compare_maxrate_kbps" ]] || ! [[ "$compare_maxrate_kbps" =~ ^[0-9]+$ ]]; then
                compare_maxrate_kbps="$adaptive_maxrate_kbps"
            fi

            local threshold_kbps=$(( compare_maxrate_kbps + (compare_maxrate_kbps * skip_tolerance_percent / 100) ))

            local cmp_display="${compare_codec^^}"
            [[ "$compare_codec" == "hevc" || "$compare_codec" == "h265" ]] && cmp_display="X265"
            [[ "$compare_codec" == "av1" ]] && cmp_display="AV1"

            if [[ "$threshold_kbps" -gt 0 ]]; then
                echo -e "${DIM}     └─ Seuil skip : ${threshold_kbps} kbps (${cmp_display})${NOCOLOR}" >&2
            fi
        fi
    fi

    # Stocker les paramètres adaptatifs dans des variables d'environnement
    export ADAPTIVE_TARGET_KBPS="$adaptive_target_kbps"
    export ADAPTIVE_MAXRATE_KBPS="$adaptive_maxrate_kbps"
    export ADAPTIVE_BUFSIZE_KBPS="$adaptive_bufsize_kbps"

    echo "${adaptive_target_kbps}|${adaptive_maxrate_kbps}|${adaptive_bufsize_kbps}|${complexity_c}|${complexity_desc}|${stddev_val}|${si_avg}|${ti_avg}"
}

###########################################################
# GESTION DU MODE ADAPTATIF
###########################################################

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
    adaptive_info=$(_convert_run_adaptive_analysis_and_export "$tmp_input" "$v_codec")

    local adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps
    local _complexity_c _complexity_desc _stddev_val
    IFS='|' read -r adaptive_target_kbps adaptive_maxrate_kbps adaptive_bufsize_kbps _complexity_c _complexity_desc _stddev_val <<< "$adaptive_info"

    # Vérifier si on peut skip maintenant qu'on a le seuil adaptatif
    if should_skip_conversion_adaptive "$v_codec" "$v_bitrate" "$filename" "$file_original" "$a_codec" "$a_bitrate" "$adaptive_maxrate_kbps"; then
        print_conversion_not_required
        rm -f "$tmp_input" 2>/dev/null || true
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            call_if_exists update_queue || true
        fi
        call_if_exists increment_processed_count || true
        return 1
    fi

    print_conversion_required "$v_codec" "$v_bitrate"

    # Réserver le slot limite après l'analyse (évite les slots "gâchés")
    if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
        local _slot
        _slot=$(call_if_exists increment_converted_count) || _slot="0"
        if [[ "$_slot" =~ ^[0-9]+$ ]] && [[ "$_slot" -gt 0 ]]; then
            # shellcheck disable=SC2034
            LIMIT_DISPLAY_SLOT="$_slot"
        fi
    fi

    # Log de démarrage (sans ré-afficher la ligne déjà imprimée avant l'analyse)
    _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir" false true
    return 0
}
