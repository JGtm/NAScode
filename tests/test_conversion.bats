#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/conversion.sh
# Tests des fonctions de conversion et préparation
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/conversion.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _prepare_file_paths()
###########################################################

@test "_prepare_file_paths: extrait correctement le nom de fichier" {
    local result
    result=$(_prepare_file_paths "/source/videos/test.mkv" "/output")
    
    local filename
    filename=$(echo "$result" | cut -d'|' -f1)
    
    [ "$filename" = "test.mkv" ]
}

@test "_prepare_file_paths: calcule correctement le base_name" {
    local result
    result=$(_prepare_file_paths "/source/video.test.mkv" "/output")
    
    local base_name
    base_name=$(echo "$result" | cut -d'|' -f3)
    
    [ "$base_name" = "video.test" ]
}

@test "_prepare_file_paths: gère les fichiers à la racine" {
    SOURCE="/videos"
    local result
    result=$(_prepare_file_paths "/videos/movie.mkv" "/output")
    
    local final_dir
    final_dir=$(echo "$result" | cut -d'|' -f2)
    
    [ "$final_dir" = "/output" ]
}

@test "_prepare_file_paths: préserve les sous-dossiers relatifs" {
    SOURCE="/videos"
    local result
    result=$(_prepare_file_paths "/videos/season1/episode01.mkv" "/output")
    
    local final_dir
    final_dir=$(echo "$result" | cut -d'|' -f2)
    
    [ "$final_dir" = "/output/season1" ]
}

@test "_prepare_file_paths: inclut le suffix dans final_output" {
    SOURCE="/videos"
    SUFFIX_STRING="_x265"
    DRYRUN=false
    
    local result
    result=$(_prepare_file_paths "/videos/test.mkv" "/output")
    
    local final_output
    final_output=$(echo "$result" | cut -d'|' -f5)
    
    [[ "$final_output" =~ "_x265.mkv" ]]
}

@test "_prepare_file_paths: ajoute le suffix dryrun si activé" {
    SOURCE="/videos"
    SUFFIX_STRING="_x265"
    DRYRUN=true
    DRYRUN_SUFFIX="_DRYRUN"
    
    local result
    result=$(_prepare_file_paths "/videos/test.mkv" "/output")
    
    local final_output
    final_output=$(echo "$result" | cut -d'|' -f5)
    
    [[ "$final_output" =~ "_x265_DRYRUN.mkv" ]]
}

###########################################################
# Tests de should_skip_conversion()
###########################################################

@test "should_skip_conversion: skip si pas de codec" {
    run should_skip_conversion "" "5000000" "test.mkv" "/source/test.mkv"
    [ "$status" -eq 0 ]
}

@test "should_skip_conversion: skip si hevc avec bitrate bas" {
    # Configurer le seuil
    BITRATE_CONVERSION_THRESHOLD_KBPS=2500
    SKIP_TOLERANCE_PERCENT=5
    
    # Bitrate sous le seuil (2.5 Mbps * 1.05 = 2.625 Mbps = 2625000 bps)
    run should_skip_conversion "hevc" "2000000" "test.mkv" "/source/test.mkv"
    [ "$status" -eq 0 ]
}

@test "should_skip_conversion: pas de skip si hevc avec bitrate élevé" {
    BITRATE_CONVERSION_THRESHOLD_KBPS=2500
    SKIP_TOLERANCE_PERCENT=5
    
    # Bitrate au-dessus du seuil
    run should_skip_conversion "hevc" "5000000" "test.mkv" "/source/test.mkv"
    [ "$status" -ne 0 ]
}

@test "should_skip_conversion: pas de skip si h264 même avec bitrate bas" {
    BITRATE_CONVERSION_THRESHOLD_KBPS=2500
    SKIP_TOLERANCE_PERCENT=5
    
    run should_skip_conversion "h264" "2000000" "test.mkv" "/source/test.mkv"
    [ "$status" -ne 0 ]
}

###########################################################
# Tests de _get_temp_filename()
###########################################################

@test "_get_temp_filename: génère un chemin dans TMP_DIR" {
    TMP_DIR="$TEST_TEMP_DIR/tmp"
    
    local result
    result=$(_get_temp_filename "/source/video.mkv" ".in")
    
    [[ "$result" =~ ^"$TMP_DIR"/tmp_ ]]
}

@test "_get_temp_filename: inclut le suffix demandé" {
    TMP_DIR="$TEST_TEMP_DIR/tmp"
    
    local result
    result=$(_get_temp_filename "/source/video.mkv" ".out.mkv")
    
    [[ "$result" =~ ".out.mkv"$ ]]
}

@test "_get_temp_filename: génère des noms différents pour fichiers différents" {
    TMP_DIR="$TEST_TEMP_DIR/tmp"
    
    local result1
    local result2
    result1=$(_get_temp_filename "/source/video1.mkv" ".in")
    result2=$(_get_temp_filename "/source/video2.mkv" ".in")
    
    [ "$result1" != "$result2" ]
}

###########################################################
# Tests de _check_disk_space()
###########################################################

@test "_check_disk_space: retourne 0 si assez d'espace" {
    TMP_DIR="$TEST_TEMP_DIR/tmp"
    MIN_TMP_FREE_MB=1  # 1 MB minimum
    
    run _check_disk_space "/source/test.mkv"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests des paramètres audio (préparation pour réactivation)
###########################################################

@test "config: AUDIO_OPUS_TARGET_KBPS défini à 128" {
    # Vérifier que la constante commentée est bien préparée à 128
    local opus_target
    opus_target=$(grep -oP 'AUDIO_OPUS_TARGET_KBPS=\K[0-9]+' "$LIB_DIR/conversion.sh" 2>/dev/null | head -1) || opus_target=""
    
    # Soit la variable existe (non commentée), soit on vérifie dans le code commenté
    if [[ -n "$opus_target" ]]; then
        [ "$opus_target" -eq 128 ]
    else
        # Vérifier que c'est présent dans le code commenté
        grep -q "AUDIO_OPUS_TARGET_KBPS=128" "$LIB_DIR/conversion.sh"
    fi
}
