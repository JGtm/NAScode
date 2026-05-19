#!/usr/bin/env bats
###########################################################
# TESTS DE STRUCTURE - Phase C scaffolding
#
# Vérifient que les modules de Phase C (auto-boost-lite Bash)
# sont sourçables et exposent les bonnes signatures de fonctions.
# Les tests d'intégration viendront quand les briques seront
# réellement implémentées (cf. AV1_OPTIMIZATION_PLAN.md §C).
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal_fast
    source "$LIB_DIR/segmenter.sh"
    source "$LIB_DIR/vmaf_predictive.sh"
    source "$LIB_DIR/auto_boost.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests segmenter.sh
###########################################################

@test "segmenter: _segment_video est définie" {
    declare -f _segment_video >/dev/null
}

@test "segmenter: _concat_segments est définie" {
    declare -f _concat_segments >/dev/null
}

@test "segmenter: _list_keyframes est définie" {
    declare -f _list_keyframes >/dev/null
}

@test "segmenter: _segment_video stub retourne 99" {
    run _segment_video "/in" 30 "/out"
    [ "$status" -eq 99 ]
}

@test "segmenter: _concat_segments stub retourne 99" {
    run _concat_segments "/list" "/out"
    [ "$status" -eq 99 ]
}

###########################################################
# Tests vmaf_predictive.sh
###########################################################

@test "vmaf_predictive: _quick_encode_segment est définie" {
    declare -f _quick_encode_segment >/dev/null
}

@test "vmaf_predictive: _measure_vmaf_segment est définie" {
    declare -f _measure_vmaf_segment >/dev/null
}

@test "vmaf_predictive: _compute_crf_adjustment est définie" {
    declare -f _compute_crf_adjustment >/dev/null
}

@test "vmaf_predictive: VMAF_PREDICTIVE_PROBE_CRF défini par défaut" {
    [ -n "${VMAF_PREDICTIVE_PROBE_CRF:-}" ]
}

@test "vmaf_predictive: VMAF_PREDICTIVE_BOOST_TABLE défini par défaut" {
    [ -n "${VMAF_PREDICTIVE_BOOST_TABLE:-}" ]
}

###########################################################
# Tests auto_boost.sh
###########################################################

@test "auto_boost: auto_boost_encode est définie" {
    declare -f auto_boost_encode >/dev/null
}

@test "auto_boost: auto_boost_check_prereqs est définie" {
    declare -f auto_boost_check_prereqs >/dev/null
}

@test "auto_boost: auto_boost_encode stub retourne 99" {
    run auto_boost_encode "/in" "/out"
    [ "$status" -eq 99 ]
}

@test "auto_boost: auto_boost_check_prereqs valide la présence des briques" {
    # Toutes les fonctions briques sont sourcées dans setup → check doit passer.
    run auto_boost_check_prereqs
    [ "$status" -eq 0 ]
}

@test "auto_boost: AUTO_BOOST_SEGMENT_DURATION défini par défaut" {
    [ -n "${AUTO_BOOST_SEGMENT_DURATION:-}" ]
}
