#!/bin/bash
###########################################################
# SVT-AV1-Essential (fork nekotrix) — détection et mapping
#
# Phase B de la roadmap docs/AV1_OPTIMIZATION_PLAN.md :
# permet à NAScode d'utiliser le binaire standalone Essential
# `SvtAv1EncApp.exe` quand il est présent dans le PATH, avec
# un fallback transparent sur le mainline `-c:v libsvtav1`.
#
# **État actuel (2026-05) : SCAFFOLDING uniquement.**
# - Détection runtime : OK
# - Mapping params mainline ↔ Essential : OK
# - Refactor pipeline pipe-based : NON IMPLÉMENTÉ (TODO).
# Tant que le refactor pipe n'est pas fait, NAScode continue
# d'utiliser `-c:v libsvtav1` (mainline) même si Essential est
# détecté. La détection sert juste à logger l'info et préparer
# le terrain.
#
# NOTE: Pas de `set -euo pipefail` car sourcé.
###########################################################

###########################################################
# VARIABLES — détection et override
###########################################################

# Chemin du binaire Essential (auto-détecté ou fourni via env).
# Si vide après detect_svtav1_essential, le binaire n'est pas dispo.
SVTAV1_ESSENTIAL_BIN="${SVTAV1_ESSENTIAL_BIN:-}"

# true si le binaire détecté est bien le fork Essential (vs mainline).
SVTAV1_HAS_ESSENTIAL="${SVTAV1_HAS_ESSENTIAL:-false}"

# true si NAScode doit utiliser Essential. Défaut = HAS_ESSENTIAL,
# overridable via flag CLI --essential / --no-essential ou env.
SVTAV1_USE_ESSENTIAL="${SVTAV1_USE_ESSENTIAL:-}"

###########################################################
# DÉTECTION
###########################################################

# Vérifie si SvtAv1EncApp est dans le PATH et si c'est le fork Essential.
# Side effects : exporte SVTAV1_ESSENTIAL_BIN et SVTAV1_HAS_ESSENTIAL.
# Retourne 0 si Essential détecté, 1 sinon.
# Usage : detect_svtav1_essential
detect_svtav1_essential() {
    local bin="${SVTAV1_ESSENTIAL_BIN:-SvtAv1EncApp}"

    if ! command -v "$bin" >/dev/null 2>&1; then
        SVTAV1_ESSENTIAL_BIN=""
        SVTAV1_HAS_ESSENTIAL=false
        return 1
    fi

    # Capture les 3 premières lignes de --version (le tag "Essential"
    # apparaît dans la version string du fork nekotrix).
    local ver
    ver=$("$bin" --version 2>&1 | head -3)

    if [[ "$ver" =~ [Ee]ssential ]]; then
        SVTAV1_ESSENTIAL_BIN=$(command -v "$bin")
        SVTAV1_HAS_ESSENTIAL=true
        return 0
    fi

    # Binaire présent mais pas Essential (ex. mainline standalone).
    SVTAV1_ESSENTIAL_BIN=""
    SVTAV1_HAS_ESSENTIAL=false
    return 1
}

# Retourne true si Essential doit être utilisé.
# Logique : SVTAV1_USE_ESSENTIAL si défini explicitement, sinon HAS_ESSENTIAL.
should_use_svtav1_essential() {
    if [[ -n "${SVTAV1_USE_ESSENTIAL:-}" ]]; then
        [[ "$SVTAV1_USE_ESSENTIAL" == "true" ]]
        return $?
    fi
    [[ "${SVTAV1_HAS_ESSENTIAL:-false}" == "true" ]]
}

###########################################################
# MAPPING PARAMS mainline → Essential
###########################################################

# Retourne les params SVT-AV1 spécifiques au fork Essential pour un mode donné.
# Diffère de get_encoder_mode_params (mainline) sur ces points :
# - `film-grain=N` → `photon-noise=N` (synthèse de grain plus réaliste)
# - Ajoute `enable-tf=3` (temporal filter sur toutes frames)
# - Ajoute `enable-alt-cdef=1` et `enable-alt-dlf=1` (deblocking/CDEF améliorés)
# - Le mode `adaptatif` garde `enable-tf=2` (moins agressif) pour limiter coût RAM.
#
# Usage : get_essential_mode_params "serie"
# Retourne une chaîne `key=value:key=value:...` (vide si mode inconnu).
get_essential_mode_params() {
    local mode="${1:-serie}"
    local lp_suffix="${SVTAV1_LP_DEFAULT:+:lp=${SVTAV1_LP_DEFAULT}}"
    local av1_base_qm="enable-qm=1:qm-min=0:ac-bias=0.25"
    local av1_essential_extra="enable-tf=3:enable-alt-cdef=1:enable-alt-dlf=1"

    case "$mode" in
        # Séries : pas de photon-noise (slowdown attendu similaire à mainline film-grain).
        # Bisection confirmera quand le pipeline pipe sera en place.
        serie)
            echo "tune=${SVTAV1_TUNE_DEFAULT}:enable-overlays=${SVTAV1_ENABLE_OVERLAYS_DEFAULT}:variance-boost-strength=3:luminance-qp-bias=20:sharpness=1:${av1_base_qm}:${av1_essential_extra}${lp_suffix}"
            ;;
        # Films : photon-noise=20 remplace film-grain=8 (échelle ~ISO, 20 = grain modéré).
        film)
            echo "tune=${SVTAV1_TUNE_DEFAULT}:enable-overlays=${SVTAV1_ENABLE_OVERLAYS_DEFAULT}:photon-noise=20:photon-noise-chroma=1:variance-boost-strength=2:luminance-qp-bias=15:sharpness=1:${av1_base_qm}:${av1_essential_extra}${lp_suffix}"
            ;;
        # Adaptatif : enable-tf=2 (pas 3) pour limiter RAM. Pas de photon-noise pour cause
        # historique de crash HWACCEL (à re-tester sur Essential, peut-être OK).
        adaptatif)
            echo "tune=${SVTAV1_TUNE_DEFAULT}:enable-overlays=0:variance-boost-strength=3:luminance-qp-bias=15:sharpness=1:${av1_base_qm}:enable-tf=2:enable-alt-cdef=1:enable-alt-dlf=1${lp_suffix}"
            ;;
        *)
            echo ""
            ;;
    esac
}

###########################################################
# PIPELINE ENCODING — STUB
###########################################################

# Encode via le binaire standalone SvtAv1EncApp Essential, en pipe avec FFmpeg.
# Architecture cible (NON IMPLÉMENTÉE) :
#   ffmpeg -i <in> [filters] -f yuv4mpegpipe -pix_fmt yuv420p10le -
#     | SvtAv1EncApp -i stdin --params... -b stdout
#     | ffmpeg -i pipe:0 [audio passthrough/transcode] -c:v copy <out>
#
# Cf. docs/AV1_OPTIMIZATION_PLAN.md §B.2 pour la spécification complète.
# Tant que cette fonction est stubée, NAScode utilise le pipeline standard
# via `-c:v libsvtav1` (mainline), même si Essential est détecté.
#
# Usage : _essential_pipe_encode <input> <output> <mode> [extras...]
_essential_pipe_encode() {
    echo "ERROR: _essential_pipe_encode is not yet implemented." >&2
    echo "       Falling back to mainline libsvtav1 pipeline." >&2
    echo "       Cf. docs/AV1_OPTIMIZATION_PLAN.md §B.2 (Phase B refactor pipe)." >&2
    return 99  # Code spécial signalant le stub
}
