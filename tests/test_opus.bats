#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Conversion audio Opus (--opus)
# Tests des fonctions de conversion audio expérimentales
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    # Charger les modules une seule fois (pas via load_base_modules pour éviter readonly conflicts)
    if [[ -z "${_OPUS_TEST_LOADED:-}" ]]; then
        export SCRIPT_DIR="$PROJECT_ROOT"
        source "$LIB_DIR/ui.sh"
        source "$LIB_DIR/config.sh"
        source "$LIB_DIR/utils.sh"
        source "$LIB_DIR/transcode_video.sh"
        # Initialiser le mode conversion (définit TARGET_BITRATE_KBPS, etc.)
        set_conversion_mode_parameters "series"
        _OPUS_TEST_LOADED=1
    fi
    
    # Variables modifiables uniquement
    OPUS_ENABLED=false
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _get_audio_conversion_info()
###########################################################

@test "_get_audio_conversion_info: retourne copy si Opus désactivé" {
    OPUS_ENABLED=false
    
    local result
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    
    [[ "$result" == "copy|0|0" ]]
}

@test "_get_audio_conversion_info: should_convert=0 quand Opus désactivé" {
    OPUS_ENABLED=false
    
    local result should_convert
    result=$(_get_audio_conversion_info "/fake/file.mkv")
    should_convert=$(echo "$result" | cut -d'|' -f3)
    
    [ "$should_convert" -eq 0 ]
}

###########################################################
# Tests de _build_audio_params()
###########################################################

@test "_build_audio_params: retourne '-c:a copy' si Opus désactivé" {
    OPUS_ENABLED=false
    
    local result
    result=$(_build_audio_params "/fake/file.mkv")
    
    [[ "$result" == "-c:a copy" ]]
}

@test "_build_audio_params: inclut le bitrate Opus quand activé" {
    # Note: Ce test nécessiterait un vrai fichier audio ou un mock de ffprobe
    # On teste juste que la fonction ne plante pas
    OPUS_ENABLED=true
    
    run _build_audio_params "/fake/file.mkv"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests d'intégration avec args.sh
###########################################################

@test "args: --opus active OPUS_ENABLED" {
    source "$LIB_DIR/args.sh"
    
    OPUS_ENABLED=false
    parse_arguments --opus
    
    [ "$OPUS_ENABLED" = true ]
}

@test "args: --opus apparaît dans l'aide" {
    source "$LIB_DIR/args.sh"
    
    run show_help
    [[ "$output" =~ "--opus" ]]
    [[ "$output" =~ "Opus" ]] || [[ "$output" =~ "audio" ]]
}

###########################################################
# Tests du suffixe avec Opus
###########################################################

@test "_build_effective_suffix_for_dims: inclut _opus si activé" {
    OPUS_ENABLED=true
    # ADAPTIVE_BITRATE_BY_RESOLUTION est readonly=true, utiliser la valeur par défaut
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ "$result" =~ "_opus" ]]
}

@test "_build_effective_suffix_for_dims: n'inclut pas _opus si désactivé" {
    OPUS_ENABLED=false
    # ADAPTIVE_BITRATE_BY_RESOLUTION est readonly=true, utiliser la valeur par défaut
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims 1920 1080)
    
    [[ ! "$result" =~ "_opus" ]]
}

###########################################################
# Tests de config.sh avec Opus
###########################################################

@test "config: build_dynamic_suffix inclut _opus si activé" {
    # config.sh est déjà chargé par load_base_modules
    OPUS_ENABLED=true
    FORCE_NO_SUFFIX=false
    SAMPLE_MODE=false
    
    build_dynamic_suffix
    
    [[ "$SUFFIX_STRING" =~ "_opus" ]]
}

@test "config: OPUS_TARGET_BITRATE_KBPS est défini et valide" {
    # Variable readonly déjà chargée
    [ -n "$OPUS_TARGET_BITRATE_KBPS" ]
    [ "$OPUS_TARGET_BITRATE_KBPS" -gt 0 ]
    [ "$OPUS_TARGET_BITRATE_KBPS" -lt 512 ]
}

@test "config: OPUS_CONVERSION_THRESHOLD_KBPS supérieur au target" {
    # Le seuil de conversion doit être supérieur au bitrate cible
    [ -n "$OPUS_CONVERSION_THRESHOLD_KBPS" ]
    [ "$OPUS_CONVERSION_THRESHOLD_KBPS" -gt "$OPUS_TARGET_BITRATE_KBPS" ]
}
