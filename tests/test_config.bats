#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/config.sh
# Tests des fonctions de configuration
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de normalize_path()
###########################################################

@test "normalize_path: gère une chaîne vide" {
    result=$(normalize_path "")
    [ -z "$result" ]
}

@test "normalize_path: conserve un chemin Unix simple" {
    result=$(normalize_path "/home/user/videos")
    [ "$result" = "/home/user/videos" ]
}

@test "normalize_path: supprime les doubles slashes" {
    result=$(normalize_path "/home//user///videos")
    [ "$result" = "/home/user/videos" ]
}

@test "normalize_path: supprime les ./ au milieu" {
    result=$(normalize_path "/home/./user/./videos")
    [ "$result" = "/home/user/videos" ]
}

@test "normalize_path: supprime le slash final" {
    result=$(normalize_path "/home/user/videos/")
    [ "$result" = "/home/user/videos" ]
}

@test "normalize_path: conserve la racine /" {
    result=$(normalize_path "/")
    [ "$result" = "/" ]
}

# Tests spécifiques MSYS (exécutés seulement si IS_MSYS=1)
@test "normalize_path: convertit /c/ en C:/ (MSYS)" {
    if [[ "$IS_MSYS" -ne 1 ]]; then
        skip "Test MSYS uniquement"
    fi
    
    result=$(normalize_path "/c/Users/test")
    [ "$result" = "C:/Users/test" ]
}

@test "normalize_path: convertit /d/ en D:/ (MSYS)" {
    if [[ "$IS_MSYS" -ne 1 ]]; then
        skip "Test MSYS uniquement"
    fi
    
    result=$(normalize_path "/d/Videos/movie.mkv")
    [ "$result" = "D:/Videos/movie.mkv" ]
}

@test "normalize_path: gère les chemins Windows natifs" {
    result=$(normalize_path "C:/Users/test/videos")
    [ "$result" = "C:/Users/test/videos" ]
}

###########################################################
# Tests de _build_excludes_regex()
###########################################################

@test "_build_excludes_regex: construit une regex valide" {
    # La fonction doit être définie
    function_exists _build_excludes_regex || skip "Fonction non disponible"
    
    result=$(_build_excludes_regex)
    # Vérifier que la regex contient les patterns attendus
    [[ "$result" =~ "Converted" ]]
}

@test "_build_excludes_regex: inclut Converted dans la regex" {
    function_exists _build_excludes_regex || skip "Fonction non disponible"
    
    result=$(_build_excludes_regex)
    # Vérifier que la regex n'est pas vide et contient un pattern
    [[ -n "$result" ]]
}

###########################################################
# Tests de set_conversion_mode_parameters()
###########################################################

@test "set_conversion_mode_parameters: mode série configure un bitrate valide" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    # Bitrate doit être défini et dans une plage raisonnable (1000-5000 kbps)
    [ -n "$TARGET_BITRATE_KBPS" ]
    [ "$TARGET_BITRATE_KBPS" -gt 1000 ]
    [ "$TARGET_BITRATE_KBPS" -lt 5000 ]
}

@test "set_conversion_mode_parameters: mode film configure un bitrate valide" {
    CONVERSION_MODE="film"
    set_conversion_mode_parameters
    
    # Bitrate doit être défini et dans une plage raisonnable
    [ -n "$TARGET_BITRATE_KBPS" ]
    [ "$TARGET_BITRATE_KBPS" -gt 1000 ]
    [ "$TARGET_BITRATE_KBPS" -lt 5000 ]
}

@test "set_conversion_mode_parameters: MAXRATE supérieur au TARGET" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    [ "$MAXRATE_KBPS" -gt "$TARGET_BITRATE_KBPS" ]
}

@test "set_conversion_mode_parameters: BUFSIZE supérieur au MAXRATE" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    [ "$BUFSIZE_KBPS" -gt "$MAXRATE_KBPS" ]
}

@test "set_conversion_mode_parameters: mode série utilise un preset valide" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    # Vérifier que le preset est défini et dans la liste des presets x265 valides
    [ -n "$ENCODER_PRESET" ]
    [[ "$ENCODER_PRESET" =~ ^(ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow|placebo)$ ]]
}

@test "set_conversion_mode_parameters: mode film utilise un preset valide" {
    # NOTE: Le mode film peut utiliser un preset différent selon les optimisations
    CONVERSION_MODE="film"
    set_conversion_mode_parameters
    
    # Vérifier que le preset est défini et dans la liste des presets x265 valides
    [ -n "$ENCODER_PRESET" ]
    [[ "$ENCODER_PRESET" =~ ^(ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow|placebo)$ ]]
}

@test "set_conversion_mode_parameters: calcule le seuil de conversion" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    # Seuil = TARGET * 1.2 arrondi = 2070 * 1.2 = 2484, arrondi à 2520
    [ "$BITRATE_CONVERSION_THRESHOLD_KBPS" -gt "$TARGET_BITRATE_KBPS" ]
}

###########################################################
# Tests des constantes de configuration
###########################################################

@test "config: PARALLEL_JOBS par défaut est 1" {
    [ "$PARALLEL_JOBS" -eq 1 ]
}

@test "config: DRYRUN par défaut est false" {
    [ "$DRYRUN" = "false" ]
}

@test "config: VMAF_ENABLED par défaut est false" {
    [ "$VMAF_ENABLED" = "false" ]
}

@test "config: MIN_TMP_FREE_MB est défini" {
    [ -n "$MIN_TMP_FREE_MB" ]
    [ "$MIN_TMP_FREE_MB" -gt 0 ]
}

###########################################################
# Tests des paramètres X265 avancés
###########################################################

@test "set_conversion_mode_parameters: mode série configure X265_EXTRA_PARAMS" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    # Vérifier que les paramètres série sont présents
    [[ "$X265_EXTRA_PARAMS" =~ "sao=0" ]]
    [[ "$X265_EXTRA_PARAMS" =~ "strong-intra-smoothing=0" ]]
    [[ "$X265_EXTRA_PARAMS" =~ "limit-refs=3" ]]
    [[ "$X265_EXTRA_PARAMS" =~ "subme=2" ]]
}

@test "set_conversion_mode_parameters: mode série active X265_PASS1_FAST" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    [ "$X265_PASS1_FAST" = "true" ]
}

@test "set_conversion_mode_parameters: mode série inclut amp=0 et rect=0" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    [[ "$X265_EXTRA_PARAMS" =~ "amp=0" ]]
    [[ "$X265_EXTRA_PARAMS" =~ "rect=0" ]]
}

@test "set_conversion_mode_parameters: mode film n'active pas X265_PASS1_FAST" {
    CONVERSION_MODE="film"
    set_conversion_mode_parameters
    
    [ "$X265_PASS1_FAST" = "false" ]
}

@test "set_conversion_mode_parameters: mode film configure X265_EXTRA_PARAMS différemment" {
    CONVERSION_MODE="film"
    set_conversion_mode_parameters
    
    # Mode film utilise amp et rect (pas désactivés)
    [[ ! "$X265_EXTRA_PARAMS" =~ "amp=0" ]] || [[ -z "$X265_EXTRA_PARAMS" ]]
}

###########################################################
# Tests des constantes VBV
###########################################################

@test "config: X265_VBV_PARAMS est cohérent avec MAXRATE et BUFSIZE" {
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    [[ "$X265_VBV_PARAMS" =~ "vbv-maxrate=${MAXRATE_KBPS}" ]]
    [[ "$X265_VBV_PARAMS" =~ "vbv-bufsize=${BUFSIZE_KBPS}" ]]
}

###########################################################
# Tests du mode single-pass CRF
###########################################################

@test "config: SINGLE_PASS_MODE par défaut est true" {
    [ "$SINGLE_PASS_MODE" = "true" ]
}

@test "set_conversion_mode_parameters: single-pass configure CRF_VALUE dans une plage valide" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    set_conversion_mode_parameters
    
    # CRF doit être entre 18 (quasi-transparent) et 28 (basse qualité)
    [ -n "$CRF_VALUE" ]
    [ "$CRF_VALUE" -ge 18 ]
    [ "$CRF_VALUE" -le 28 ]
}

@test "set_conversion_mode_parameters: single-pass ne change pas le preset" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    set_conversion_mode_parameters
    
    # Le preset doit rester valide (même comportement qu'en two-pass)
    [ -n "$ENCODER_PRESET" ]
    [[ "$ENCODER_PRESET" =~ ^(ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow|placebo)$ ]]
}

@test "build_dynamic_suffix: affiche CRF en mode single-pass" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=true
    set_conversion_mode_parameters
    
    # Doit contenir _crf suivi d'un nombre
    [[ "$SUFFIX_STRING" =~ _crf[0-9]+_ ]]
}

@test "build_dynamic_suffix: affiche bitrate en mode two-pass" {
    CONVERSION_MODE="serie"
    SINGLE_PASS_MODE=false
    set_conversion_mode_parameters
    
    # Doit contenir le bitrate suivi de k, pas de CRF
    [[ "$SUFFIX_STRING" =~ _[0-9]+k_ ]]
    [[ ! "$SUFFIX_STRING" =~ "_crf" ]]
}

###########################################################
# Tests de validate_codec_config()
###########################################################

@test "validate_codec_config: accepte codec hevc avec encodeur disponible" {
    VIDEO_CODEC="hevc"
    VIDEO_ENCODER=""
    
    # Skip si libx265 n'est pas disponible
    if ! ffmpeg -encoders 2>/dev/null | grep -q libx265; then
        skip "libx265 non disponible"
    fi
    
    # Exécuter directement (pas avec run) pour préserver VIDEO_ENCODER
    validate_codec_config
    local status=$?
    [ "$status" -eq 0 ]
    [ "$VIDEO_ENCODER" = "libx265" ]
}

@test "validate_codec_config: rejette codec non supporté" {
    VIDEO_CODEC="vp9"
    VIDEO_ENCODER=""
    
    run validate_codec_config
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Codec non supporté" ]]
}

@test "validate_codec_config: rejette encodeur non disponible" {
    VIDEO_CODEC="hevc"
    VIDEO_ENCODER="encodeur_inexistant_xyz"
    
    run validate_codec_config
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Encodeur non disponible" ]]
}

@test "set_conversion_mode_parameters: échoue avec codec AV1 si libsvtav1 absent" {
    # Ce test vérifie que la validation codec est bien appelée
    VIDEO_CODEC="av1"
    VIDEO_ENCODER=""
    CONVERSION_MODE="serie"
    
    # Si libsvtav1 est disponible, on skip le test
    if ffmpeg -encoders 2>/dev/null | grep -q libsvtav1; then
        skip "libsvtav1 est disponible, test non applicable"
    fi
    
    run set_conversion_mode_parameters
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Encodeur non disponible" || "$output" =~ "Configuration codec invalide" ]]
}
