#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/svtav1_essential.sh
#
# Phase B de la roadmap : tests de détection et mapping de
# params pour le fork SVT-AV1-Essential. Les tests qui requièrent
# un binaire Essential réel sont skippés en son absence.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal_fast
    source "$LIB_DIR/codec_profiles.sh"
    source "$LIB_DIR/svtav1_essential.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de structure (toujours exécutés)
###########################################################

@test "svtav1_essential: detect_svtav1_essential est définie" {
    declare -f detect_svtav1_essential >/dev/null
}

@test "svtav1_essential: should_use_svtav1_essential est définie" {
    declare -f should_use_svtav1_essential >/dev/null
}

@test "svtav1_essential: get_essential_mode_params est définie" {
    declare -f get_essential_mode_params >/dev/null
}

@test "svtav1_essential: _essential_pipe_encode est définie (stub)" {
    declare -f _essential_pipe_encode >/dev/null
}

###########################################################
# Tests detect_svtav1_essential() — comportement par défaut
###########################################################

@test "detect_svtav1_essential: ne crashe pas si binaire absent" {
    # Force un nom de binaire fictif pour garantir l'absence.
    SVTAV1_ESSENTIAL_BIN="svtav1_inexistant_$$"
    run detect_svtav1_essential
    # Code de sortie 1 attendu (pas Essential), mais pas de crash.
    [ "$status" -eq 1 ]
    [ "${SVTAV1_HAS_ESSENTIAL:-}" = "false" ]
}

@test "should_use_svtav1_essential: false par défaut (Essential absent)" {
    SVTAV1_HAS_ESSENTIAL=false
    unset SVTAV1_USE_ESSENTIAL
    run should_use_svtav1_essential
    [ "$status" -eq 1 ]
}

@test "should_use_svtav1_essential: true si SVTAV1_USE_ESSENTIAL=true (override)" {
    SVTAV1_HAS_ESSENTIAL=false
    SVTAV1_USE_ESSENTIAL=true
    run should_use_svtav1_essential
    [ "$status" -eq 0 ]
}

@test "should_use_svtav1_essential: false si SVTAV1_USE_ESSENTIAL=false (override)" {
    SVTAV1_HAS_ESSENTIAL=true
    SVTAV1_USE_ESSENTIAL=false
    run should_use_svtav1_essential
    [ "$status" -eq 1 ]
}

###########################################################
# Tests get_essential_mode_params() — mapping params
###########################################################

@test "get_essential_mode_params: serie utilise photon-noise pas film-grain" {
    result=$(get_essential_mode_params "serie")
    [[ ! "$result" =~ "film-grain" ]]
}

@test "get_essential_mode_params: serie active enable-tf=3" {
    result=$(get_essential_mode_params "serie")
    [[ "$result" =~ "enable-tf=3" ]]
}

@test "get_essential_mode_params: film active photon-noise=20" {
    result=$(get_essential_mode_params "film")
    [[ "$result" =~ "photon-noise=20" ]]
}

@test "get_essential_mode_params: film n'a pas film-grain (remplacé par photon-noise)" {
    result=$(get_essential_mode_params "film")
    [[ ! "$result" =~ "film-grain" ]]
}

@test "get_essential_mode_params: film active enable-alt-cdef=1 et enable-alt-dlf=1" {
    result=$(get_essential_mode_params "film")
    [[ "$result" =~ "enable-alt-cdef=1" ]]
    [[ "$result" =~ "enable-alt-dlf=1" ]]
}

@test "get_essential_mode_params: adaptatif utilise enable-tf=2 (moins agressif)" {
    result=$(get_essential_mode_params "adaptatif")
    [[ "$result" =~ "enable-tf=2" ]]
    [[ ! "$result" =~ "enable-tf=3" ]]
}

@test "get_essential_mode_params: adaptatif garde enable-overlays=0" {
    result=$(get_essential_mode_params "adaptatif")
    [[ "$result" =~ "enable-overlays=0" ]]
}

@test "get_essential_mode_params: mode inconnu retourne vide" {
    result=$(get_essential_mode_params "inexistant")
    [ -z "$result" ]
}

###########################################################
# Tests _essential_pipe_encode() — stub
###########################################################

@test "_essential_pipe_encode: stub retourne code 99 (non implémenté)" {
    run _essential_pipe_encode "/in" "/out" "serie"
    [ "$status" -eq 99 ]
}

###########################################################
# Tests conditionnels — requièrent un binaire Essential réel
###########################################################

@test "detect_svtav1_essential: vrai binaire Essential dans le PATH" {
    if ! command -v SvtAv1EncApp >/dev/null 2>&1; then
        skip "SvtAv1EncApp non installé dans le PATH"
    fi
    if ! SvtAv1EncApp --version 2>&1 | head -3 | grep -qi essential; then
        skip "SvtAv1EncApp détecté mais pas le fork Essential"
    fi
    run detect_svtav1_essential
    [ "$status" -eq 0 ]
    [ "${SVTAV1_HAS_ESSENTIAL:-}" = "true" ]
    [ -n "${SVTAV1_ESSENTIAL_BIN:-}" ]
}
