#!/usr/bin/env bats
###########################################################
# TESTS HFR (High Frame Rate)
#
# Tests unitaires pour la gestion du contenu HFR :
# - Détection HFR
# - Limitation FPS
# - Majoration bitrate
###########################################################

load test_helper

setup() {
    setup_test_env
    load_base_modules_fast
    
    # Valeurs par défaut pour les tests
    export HFR_THRESHOLD_FPS=30
    export LIMIT_FPS_TARGET=29.97
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de détection HFR (_is_hfr)
###########################################################

@test "_is_hfr: 24 fps → non HFR" {
    run _is_hfr "24"
    [[ "$status" -eq 1 ]]
}

@test "_is_hfr: 25 fps → non HFR" {
    run _is_hfr "25"
    [[ "$status" -eq 1 ]]
}

@test "_is_hfr: 29.97 fps → non HFR" {
    run _is_hfr "29.97"
    [[ "$status" -eq 1 ]]
}

@test "_is_hfr: 30 fps → non HFR (seuil exact)" {
    run _is_hfr "30"
    [[ "$status" -eq 1 ]]
}

@test "_is_hfr: 50 fps → HFR" {
    run _is_hfr "50"
    [[ "$status" -eq 0 ]]
}

@test "_is_hfr: 59.94 fps → HFR" {
    run _is_hfr "59.94"
    [[ "$status" -eq 0 ]]
}

@test "_is_hfr: 60 fps → HFR" {
    run _is_hfr "60"
    [[ "$status" -eq 0 ]]
}

@test "_is_hfr: 120 fps → HFR" {
    run _is_hfr "120"
    [[ "$status" -eq 0 ]]
}

###########################################################
# Tests du facteur de majoration (_compute_hfr_bitrate_factor)
###########################################################

@test "_compute_hfr_bitrate_factor: 24 fps → 1.0" {
    local result
    result=$(_compute_hfr_bitrate_factor "24")
    [[ "$result" == "1.0" ]] || [[ "$result" == "1.00" ]]
}

@test "_compute_hfr_bitrate_factor: 30 fps → 1.0" {
    local result
    result=$(_compute_hfr_bitrate_factor "30")
    [[ "$result" == "1.0" ]] || [[ "$result" == "1.00" ]]
}

@test "_compute_hfr_bitrate_factor: 60 fps → 2.0" {
    local result
    result=$(_compute_hfr_bitrate_factor "60")
    [[ "$result" == "2.00" ]]
}

@test "_compute_hfr_bitrate_factor: 50 fps → ~1.67" {
    local result
    result=$(_compute_hfr_bitrate_factor "50")
    # 50/30 = 1.666...
    local expected
    expected=$(awk 'BEGIN { printf "%.2f", 50/30 }')
    [[ "$result" == "$expected" ]]
}

@test "_compute_hfr_bitrate_factor: 120 fps → 4.0" {
    local result
    result=$(_compute_hfr_bitrate_factor "120")
    [[ "$result" == "4.00" ]]
}

###########################################################
# Tests de l'ajustement bitrate (_apply_hfr_bitrate_adjustment)
###########################################################

@test "_apply_hfr_bitrate_adjustment: 2070 kbps @ 24 fps → inchangé" {
    local result
    result=$(_apply_hfr_bitrate_adjustment "2070" "24")
    [[ "$result" -eq 2070 ]]
}

@test "_apply_hfr_bitrate_adjustment: 2070 kbps @ 60 fps → 4140 kbps" {
    local result
    result=$(_apply_hfr_bitrate_adjustment "2070" "60")
    [[ "$result" -eq 4140 ]]
}

@test "_apply_hfr_bitrate_adjustment: 2000 kbps @ 50 fps → majore" {
    local result
    result=$(_apply_hfr_bitrate_adjustment "2000" "50")
    # 2000 * (50/30) = 3333.33...
    # Vérifier que le résultat est dans la plage attendue [3330, 3340]
    [[ "$result" -ge 3330 ]] && [[ "$result" -le 3340 ]]
}

###########################################################
# Tests du filtre FPS (_build_fps_limit_filter)
###########################################################

@test "_build_fps_limit_filter: LIMIT_FPS=false → vide" {
    export LIMIT_FPS=false
    local result
    result=$(_build_fps_limit_filter "60")
    [[ -z "$result" ]]
}

@test "_build_fps_limit_filter: LIMIT_FPS=true, 24 fps → vide (pas HFR)" {
    export LIMIT_FPS=true
    local result
    result=$(_build_fps_limit_filter "24")
    [[ -z "$result" ]]
}

@test "_build_fps_limit_filter: LIMIT_FPS=true, 60 fps → fps=29.97" {
    export LIMIT_FPS=true
    local result
    result=$(_build_fps_limit_filter "60")
    [[ "$result" == "fps=29.97" ]]
}

@test "_build_fps_limit_filter: LIMIT_FPS=true, 50 fps → fps=29.97" {
    export LIMIT_FPS=true
    local result
    result=$(_build_fps_limit_filter "50")
    [[ "$result" == "fps=29.97" ]]
}

@test "_build_fps_limit_filter: LIMIT_FPS_TARGET personnalisé → fps=25" {
    export LIMIT_FPS=true
    export LIMIT_FPS_TARGET=25
    local result
    result=$(_build_fps_limit_filter "60")
    [[ "$result" == "fps=25" ]]
}

###########################################################
# Tests de configuration par mode
###########################################################

@test "mode serie: LIMIT_FPS=true par défaut" {
    unset LIMIT_FPS
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    [[ "$LIMIT_FPS" == true ]]
}

@test "mode film: LIMIT_FPS=false par défaut" {
    unset LIMIT_FPS
    CONVERSION_MODE="film"
    set_conversion_mode_parameters
    [[ "$LIMIT_FPS" == false ]]
}

@test "mode adaptatif: LIMIT_FPS=false par défaut" {
    unset LIMIT_FPS
    CONVERSION_MODE="adaptatif"
    set_conversion_mode_parameters
    [[ "$LIMIT_FPS" == false ]]
}

@test "mode serie + --no-limit-fps: LIMIT_FPS=false" {
    export LIMIT_FPS=false
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    # L'override CLI doit être préservé
    [[ "$LIMIT_FPS" == false ]]
}

@test "mode film + --limit-fps: LIMIT_FPS=true" {
    export LIMIT_FPS=true
    CONVERSION_MODE="film"
    set_conversion_mode_parameters
    # L'override CLI doit être préservé
    [[ "$LIMIT_FPS" == true ]]
}
