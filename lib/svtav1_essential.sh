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
# HELPERS UI
###########################################################

# Préfère print_status (cohérence couleur magenta NAScode), fallback echo.
_essential_say() {
    local msg="$1"
    if declare -f print_status >/dev/null 2>&1; then
        print_status "[essential] ${msg}" "${MAGENTA:-}"
    else
        echo "[essential] ${msg}"
    fi
}

_essential_say_err() {
    local msg="$1"
    if declare -f print_error >/dev/null 2>&1; then
        print_error "[essential] ${msg}"
    else
        echo "ERROR: [essential] ${msg}" >&2
    fi
}

###########################################################
# PIPELINE ENCODING (Phase B)
###########################################################

# Convertit une chaîne svtav1-params (style mainline `key=value:key=value`)
# en arguments CLI pour SvtAv1EncApp standalone (`--key value --key value`).
# Échappe les valeurs vides.
#
# Usage : _essential_params_to_cli "tune=0:enable-overlays=1:preset=5"
# Retourne : "--tune 0 --enable-overlays 1 --preset 5"
_essential_params_to_cli() {
    local params="$1"
    [[ -z "$params" ]] && { echo ""; return 0; }
    local out=""
    local IFS=':'
    # shellcheck disable=SC2206
    local -a pairs=($params)
    local pair key val
    for pair in "${pairs[@]}"; do
        [[ -z "$pair" ]] && continue
        key="${pair%%=*}"
        val="${pair#*=}"
        # Si pas de '=' dans la paire, on traite comme flag standalone.
        if [[ "$key" == "$val" ]]; then
            out+=" --${key}"
        else
            out+=" --${key} ${val}"
        fi
    done
    # Trim leading space.
    echo "${out# }"
}

# Encode une vidéo en AV1 via SvtAv1EncApp Essential standalone, en pipe
# YUV4MPEG depuis ffmpeg. Sortie au format IVF (raw AV1 stream).
#
# Architecture :
#   ffmpeg -i <input> [filters] -f yuv4mpegpipe -pix_fmt yuv420p10le -strict -1 pipe:1
#     | SvtAv1EncApp -i - --preset N --crf N <params Essential> -b <output_ivf>
#
# Note `-strict -1` : requis car yuv420p10le n'est pas officiel dans le
# format y4m, mais ffmpeg+SvtAv1EncApp s'entendent quand même.
#
# Usage : _essential_pipe_encode <input> <output_ivf> [mode] [crf] [preset]
# - <input>      : fichier vidéo source (ffmpeg le lit).
# - <output_ivf> : chemin du fichier IVF de sortie (raw AV1).
# - [mode]       : profil NAScode (serie/film/adaptatif). Défaut : adaptatif.
# - [crf]        : CRF cible. Défaut : ${CRF_VALUE:-${SVTAV1_CRF_DEFAULT:-32}}.
# - [preset]     : preset SVT-AV1 [0-13]. Défaut : ${SVTAV1_PRESET_DEFAULT:-8}.
#
# Retourne : 0 si OK, code != 0 sinon. Le binaire est attendu dans
# SVTAV1_ESSENTIAL_BIN (sinon dans le PATH sous le nom SvtAv1EncApp).
_essential_pipe_encode() {
    local input="$1"
    local output_ivf="$2"
    local mode="${3:-adaptatif}"
    local crf="${4:-${CRF_VALUE:-${SVTAV1_CRF_DEFAULT:-32}}}"
    local preset="${5:-${SVTAV1_PRESET_DEFAULT:-8}}"

    if [[ -z "$input" || -z "$output_ivf" ]]; then
        echo "ERROR: _essential_pipe_encode usage: <input> <output_ivf> [mode] [crf] [preset]" >&2
        return 2
    fi
    if [[ ! -f "$input" ]]; then
        echo "ERROR: _essential_pipe_encode: input not found: $input" >&2
        return 2
    fi

    # Binaire Essential : SVTAV1_ESSENTIAL_BIN ou fallback PATH.
    local bin="${SVTAV1_ESSENTIAL_BIN:-SvtAv1EncApp}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "ERROR: _essential_pipe_encode: binaire Essential introuvable ($bin)" >&2
        return 3
    fi

    # Récupérer les params Essential pour le mode demandé.
    local params_essential
    params_essential=$(get_essential_mode_params "$mode")
    local cli_params
    cli_params=$(_essential_params_to_cli "$params_essential")

    _essential_say "Encode pipe via SvtAv1EncApp ${mode} (preset=${preset}, crf=${crf})"

    # Construction du pipe.
    # ffmpeg : input → yuv4mpegpipe 10-bit → stdout.
    # SvtAv1EncApp : stdin (y4m auto-detect) → IVF.
    # On capture stderr de SvtAv1EncApp dans un log temp séparé pour
    # éviter les blocages d'écriture quand le caller (ex. bats `run`)
    # bufferise stderr lentement.
    local svt_log
    svt_log=$(mktemp -t svtav1_essential.XXXXXX.log)
    # shellcheck disable=SC2086 (cli_params expansion volontaire)
    ffmpeg -hide_banner -loglevel error \
            -i "$input" \
            -map 0:v:0 -an -sn \
            -f yuv4mpegpipe -pix_fmt yuv420p10le -strict -1 pipe:1 2>/dev/null \
        | "$bin" -i - \
            --preset "$preset" --crf "$crf" $cli_params \
            -b "$output_ivf" > /dev/null 2>"$svt_log"

    # Vérifier la sortie : IVF non vide = succès, sinon on remonte le log.
    if [[ ! -s "$output_ivf" ]]; then
        echo "ERROR: _essential_pipe_encode: IVF output empty or missing: $output_ivf" >&2
        if [[ -s "$svt_log" ]]; then
            grep -iE 'svt ?\[error\]|error' "$svt_log" | head -5 >&2
        fi
        rm -f "$svt_log"
        return 4
    fi
    rm -f "$svt_log"
    return 0
}

# Wrapper d'intégration pour le pipeline NAScode. Analogue à
# `_execute_auto_boost_conversion` mais avec encode SvtAv1EncApp Essential
# au lieu d'auto-boost. Sortie : mkv complet avec audio smart codec
# (réutilise `_build_audio_params` de lib/audio_params.sh).
#
# Usage : _execute_essential_conversion <tmp_input> <tmp_output> <log> <duration> <base_name>
_execute_essential_conversion() {
    local tmp_input="$1"
    local tmp_output="$2"
    local ffmpeg_log="$3"
    local duration="$4"
    local base_name="$5"

    if [[ -z "$tmp_input" || -z "$tmp_output" ]]; then
        echo "ERROR: _execute_essential_conversion usage: <in> <out> <log> <duration> <base_name>" >&2
        return 1
    fi
    if [[ ! -f "$tmp_input" ]]; then
        echo "ERROR: _execute_essential_conversion: input not found: $tmp_input" >&2
        return 1
    fi

    # Étape 1 : encode vidéo en IVF via pipe.
    local out_ivf="${tmp_output%.*}.essential.ivf"
    local mode="${CONVERSION_MODE:-adaptatif}"
    # `adaptatif-vmaf` partage le profil `adaptatif` côté params.
    [[ "$mode" == "adaptatif-vmaf" ]] && mode="adaptatif"

    _essential_say "Démarrage encode SVT-AV1-Essential (mode ${mode})"
    if ! _essential_pipe_encode "$tmp_input" "$out_ivf" "$mode" 2>>"$ffmpeg_log"; then
        _essential_say_err "pipe encode failed"
        echo "ERROR: _execute_essential_conversion: pipe encode failed" >>"$ffmpeg_log"
        rm -f "$out_ivf"
        return 1
    fi
    _essential_say "Mux final (audio smart codec + sous-titres + metadata)"

    # Étape 2 : audio smart codec (fallback copy si module pas chargé).
    local audio_opts_str="-c:a copy"
    if declare -f _build_audio_params >/dev/null; then
        audio_opts_str=$(_build_audio_params "$tmp_input" 2>/dev/null) || audio_opts_str="-c:a copy"
        [[ -z "$audio_opts_str" ]] && audio_opts_str="-c:a copy"
    fi
    local -a audio_opts
    # shellcheck disable=SC2206
    audio_opts=( $audio_opts_str )

    # Étape 3 : mux final IVF + audio/subs/metadata source.
    if ! ffmpeg -hide_banner -loglevel error -y \
            -i "$out_ivf" -i "$tmp_input" \
            -map 0:v:0 -map 1:a? -map 1:s? \
            -c:v copy "${audio_opts[@]}" -c:s copy \
            -map_metadata 1 -map_chapters 1 \
            "$tmp_output" 2>>"$ffmpeg_log"; then
        echo "ERROR: _execute_essential_conversion: final mux failed" >>"$ffmpeg_log"
        rm -f "$out_ivf"
        return 1
    fi

    rm -f "$out_ivf"
    return 0
}
