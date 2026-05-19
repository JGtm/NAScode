#!/bin/bash
###########################################################
# AUTO-BOOST — orchestration du mode `adaptatif-vmaf`
#
# Phase C de la roadmap (docs/AV1_OPTIMIZATION_PLAN.md §C.1) :
# variante "lite" en pur Bash + ffmpeg + libvmaf de l'outil
# Auto-Boost-Essential (qui utilise Python + Vapoursynth + SSIMU2).
#
# Pipeline (6 étapes) :
#   1. Découper l'input en segments alignés keyframes (lib/segmenter.sh).
#   2. Encoder chaque segment en "preview rapide" (lib/vmaf_predictive.sh).
#   3. Mesurer VMAF du preview vs source pour chaque segment.
#   4. Calculer un delta CRF par segment selon le VMAF observé.
#   5. Ré-encoder chaque segment avec son CRF ajusté (config qualité).
#   6. Concaténer les segments finaux en un fichier vidéo unique.
#
# La sortie est une vidéo AV1 only (pas d'audio, pas de sous-titres).
# Le mux audio est délégué au caller (typiquement NAScode standard).
#
# Dépendances : lib/segmenter.sh, lib/vmaf_predictive.sh (et lib/vmaf.sh
# qui définit compute_vmaf_score).
#
# NOTE: Pas de `set -euo pipefail` car sourcé.
###########################################################

###########################################################
# CONFIGURATION
###########################################################

# Durée approximative d'un segment, en secondes. Compromis entre
# granularité (court = mieux ciblé) et coût (court = plus de fichiers
# temporaires, plus de concat overhead). 30s est un bon défaut.
AUTO_BOOST_SEGMENT_DURATION="${AUTO_BOOST_SEGMENT_DURATION:-30}"

# Répertoire de travail pour les segments temporaires.
# Si vide, mktemp -d sera utilisé.
AUTO_BOOST_WORK_DIR="${AUTO_BOOST_WORK_DIR:-}"

# CRF de base pour l'encode final (delta sera ajouté/soustrait par segment).
# Aligné sur le défaut adaptatif série (CRF_VALUE=21 dans config.sh).
AUTO_BOOST_BASE_CRF="${AUTO_BOOST_BASE_CRF:-21}"

# Preset SVT-AV1 pour l'encode final (= mainline 5 medium).
AUTO_BOOST_FINAL_PRESET="${AUTO_BOOST_FINAL_PRESET:-5}"

# Params SVT-AV1 perceptuels pour l'encode final. Aligné sur le profil
# adaptatif (sans film-grain qui ralentit, avec variance-boost et lp=6).
AUTO_BOOST_SVTAV1_PARAMS="${AUTO_BOOST_SVTAV1_PARAMS:-tune=0:enable-overlays=0:film-grain=0:variance-boost-strength=3:luminance-qp-bias=15:sharpness=1:enable-qm=1:qm-min=0:ac-bias=0.25:lp=6}"

###########################################################
# ORCHESTRATION PRINCIPALE
###########################################################

# Exécute le pipeline auto-boost-lite sur un fichier d'entrée.
# Produit un fichier de sortie vidéo AV1 only avec un CRF variable
# par segment. Le caller doit muxer l'audio séparément.
#
# Usage : auto_boost_encode <input> <output> [base_crf]
# Retourne : 0 si OK, code != 0 sinon.
auto_boost_encode() {
    local input="$1"
    local output="$2"
    local base_crf="${3:-$AUTO_BOOST_BASE_CRF}"

    if [[ -z "$input" || -z "$output" ]]; then
        echo "ERROR: auto_boost_encode usage: <input> <output> [base_crf]" >&2
        return 2
    fi
    if [[ ! -f "$input" ]]; then
        echo "ERROR: auto_boost_encode: input not found: $input" >&2
        return 2
    fi

    # Vérifier les prérequis de briques (segmenter + vmaf_predictive).
    if ! auto_boost_check_prereqs; then
        return 3
    fi

    # Workspace temporaire. mktemp si pas fourni explicitement.
    local work_dir="${AUTO_BOOST_WORK_DIR}"
    local cleanup_work_dir=false
    if [[ -z "$work_dir" ]]; then
        work_dir=$(mktemp -d -t nascode_autoboost.XXXXXX) || {
            echo "ERROR: auto_boost_encode: cannot create work dir" >&2
            return 4
        }
        cleanup_work_dir=true
    else
        mkdir -p "$work_dir" || return 4
    fi

    local raw_dir="${work_dir}/raw"        # segments source (-c copy)
    local proxy_dir="${work_dir}/proxy"    # encodes rapides pour mesure VMAF
    local final_dir="${work_dir}/final"    # encodes qualité avec CRF ajusté
    mkdir -p "$raw_dir" "$proxy_dir" "$final_dir"

    local ret=0
    _auto_boost_run_pipeline "$input" "$output" "$base_crf" \
        "$raw_dir" "$proxy_dir" "$final_dir"
    ret=$?

    if [[ "$cleanup_work_dir" == true ]]; then
        rm -rf "$work_dir"
    fi
    return "$ret"
}

# Pipeline interne — séparé pour faciliter la gestion du cleanup.
_auto_boost_run_pipeline() {
    local input="$1"
    local output="$2"
    local base_crf="$3"
    local raw_dir="$4"
    local proxy_dir="$5"
    local final_dir="$6"

    # Étape 1 : segmentation.
    if ! _segment_video "$input" "$AUTO_BOOST_SEGMENT_DURATION" "$raw_dir"; then
        echo "ERROR: auto_boost: segmentation failed" >&2
        return 10
    fi

    # Liste des segments raw (ordre lexicographique = ordre chronologique
    # grâce au pattern seg_%03d).
    local raw_segments=("$raw_dir"/seg_*)
    if [[ ${#raw_segments[@]} -eq 0 ]] || [[ ! -f "${raw_segments[0]}" ]]; then
        echo "ERROR: auto_boost: no segments produced" >&2
        return 11
    fi

    local final_list="${final_dir}/concat.list"
    : > "$final_list"

    # Étape 2-5 : pour chaque segment, proxy → VMAF → delta → encode final.
    local idx=0
    local seg seg_basename proxy_path final_path vmaf delta final_crf
    for seg in "${raw_segments[@]}"; do
        seg_basename=$(basename "$seg")
        proxy_path="${proxy_dir}/${seg_basename}"
        final_path="${final_dir}/${seg_basename}"

        # 2. Proxy rapide
        if ! _quick_encode_segment "$seg" "$proxy_path"; then
            echo "ERROR: auto_boost: proxy encode failed for $seg_basename" >&2
            return 20
        fi

        # 3. Mesure VMAF
        vmaf=$(_measure_vmaf_segment "$proxy_path" "$seg")

        # 4. Delta CRF
        delta=$(_compute_crf_adjustment "$vmaf")

        # CRF final = base + delta, borné à [10, 50] pour rester sain.
        final_crf=$((base_crf + delta))
        if [[ $final_crf -lt 10 ]]; then final_crf=10; fi
        if [[ $final_crf -gt 50 ]]; then final_crf=50; fi

        echo "[auto_boost] seg ${idx}: vmaf=${vmaf} delta=${delta} crf=${final_crf}"

        # 5. Encode qualité final
        if ! _auto_boost_quality_encode "$seg" "$final_path" "$final_crf"; then
            echo "ERROR: auto_boost: quality encode failed for $seg_basename" >&2
            return 30
        fi

        # Ajout à la concat list. Path *relatif* (basename seulement) :
        # robuste face aux conversions /tmp ↔ C:/tmp côté ffmpeg.exe sous
        # MSYS2/Windows. ffmpeg résout les paths relativement au dossier
        # contenant le concat list — ici final_dir, qui contient le segment.
        printf "file '%s'\n" "$(_auto_boost_concat_escape "$(basename "$final_path")")" >> "$final_list"
        idx=$((idx + 1))
    done

    # Étape 6 : concat.
    if ! _concat_segments "$final_list" "$output"; then
        echo "ERROR: auto_boost: final concat failed" >&2
        return 40
    fi

    echo "[auto_boost] OK — ${idx} segments encodés, sortie: $output"
    return 0
}

# Encode "qualité" d'un segment avec les params perceptuels finaux.
# Usage : _auto_boost_quality_encode <input_seg> <out_seg> <crf>
_auto_boost_quality_encode() {
    local input_seg="$1"
    local out_seg="$2"
    local crf="$3"

    ffmpeg -hide_banner -loglevel error -y \
        -i "$input_seg" \
        -c:v libsvtav1 \
        -crf "$crf" \
        -preset "$AUTO_BOOST_FINAL_PRESET" \
        -svtav1-params "$AUTO_BOOST_SVTAV1_PARAMS" \
        -pix_fmt yuv420p10le \
        -an -sn \
        "$out_seg" 2>&1
}

# Échappe les apostrophes dans un chemin pour le format `ffmpeg -f concat`.
# Le format concat veut: file 'path/with''quote.mkv' (apostrophe doublée).
_auto_boost_concat_escape() {
    printf "%s" "${1//\'/\'\\\'\'}"
}

###########################################################
# UTILITAIRES
###########################################################

# Vérifie que toutes les dépendances Phase C sont prêtes (briques
# définies, outils dispo).
#
# Usage : auto_boost_check_prereqs
# Retourne : 0 si tout est prêt, !=0 avec message d'erreur sinon.
auto_boost_check_prereqs() {
    local missing=()
    for fn in _segment_video _concat_segments _quick_encode_segment \
              _measure_vmaf_segment _compute_crf_adjustment compute_vmaf_score; do
        if ! declare -f "$fn" >/dev/null; then
            missing+=("$fn")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: auto_boost: missing functions: ${missing[*]}" >&2
        echo "       Make sure lib/segmenter.sh, lib/vmaf_predictive.sh," >&2
        echo "       and lib/vmaf.sh are all sourced." >&2
        return 1
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "ERROR: auto_boost: ffmpeg not in PATH" >&2
        return 2
    fi

    return 0
}
