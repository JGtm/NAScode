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
    # DRYRUN_SUFFIX est readonly dans config.sh, on teste avec la valeur par défaut
    # La valeur par défaut est "-dryrun-sample", donc on vérifie juste que DRYRUN=true l'ajoute
    SOURCE="/videos"
    SUFFIX_STRING="_x265"
    DRYRUN=true
    
    local result
    result=$(_prepare_file_paths "/videos/test.mkv" "/output")
    
    local final_output
    final_output=$(echo "$result" | cut -d'|' -f5)
    
    # Vérifier que le suffix dryrun est présent (valeur par défaut: -dryrun-sample)
    [[ "$final_output" =~ "-dryrun-sample.mkv" ]]
}

###########################################################
# Tests de should_skip_conversion()
###########################################################

@test "should_skip_conversion: skip si pas de codec" {
    run should_skip_conversion "" "5000000" "test.mkv" "/source/test.mkv"
    [ "$status" -eq 0 ]
}

@test "should_skip_conversion: skip si hevc avec bitrate bas" {
    # Utiliser les valeurs par défaut (readonly)
    # Le seuil par défaut est ~2500 kbps, on teste avec un bitrate bien en dessous
    # Bitrate sous le seuil
    run should_skip_conversion "hevc" "2000000" "test.mkv" "/source/test.mkv"
    [ "$status" -eq 0 ]
}

@test "should_skip_conversion: pas de skip si hevc avec bitrate élevé" {
    # Bitrate au-dessus du seuil (5 Mbps >> seuil de ~2.5 Mbps)
    run should_skip_conversion "hevc" "5000000" "test.mkv" "/source/test.mkv"
    [ "$status" -ne 0 ]
}

@test "should_skip_conversion: pas de skip si h264 même avec bitrate bas" {
    # H264 doit toujours être converti (pas de skip basé sur le bitrate)
    run should_skip_conversion "h264" "2000000" "test.mkv" "/source/test.mkv"
    [ "$status" -ne 0 ]
}

###########################################################
# Tests de _get_temp_filename()
###########################################################

@test "_get_temp_filename: génère un chemin dans TMP_DIR" {
    # TMP_DIR est readonly, utiliser sa valeur actuelle
    local result
    result=$(_get_temp_filename "/source/video.mkv" ".in")
    
    [[ "$result" =~ ^"$TMP_DIR"/tmp_ ]]
}

@test "_get_temp_filename: inclut le suffix demandé" {
    local result
    result=$(_get_temp_filename "/source/video.mkv" ".out.mkv")
    
    [[ "$result" =~ ".out.mkv"$ ]]
}

@test "_get_temp_filename: génère des noms différents pour fichiers différents" {
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
    # TMP_DIR et MIN_TMP_FREE_MB sont readonly, utiliser les valeurs par défaut
    run _check_disk_space "/source/test.mkv"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests des paramètres audio (préparation pour réactivation)
###########################################################

@test "config: OPUS_TARGET_BITRATE_KBPS défini à 128" {
    # OPUS_TARGET_BITRATE_KBPS est readonly et déjà chargé par load_base_modules
    [ "$OPUS_TARGET_BITRATE_KBPS" -eq 128 ]
}

###########################################################
# Tests de chemins avec espaces
###########################################################

@test "_prepare_file_paths: gère les espaces dans le nom de fichier" {
    SOURCE="/videos"
    SUFFIX_STRING="_x265"
    DRYRUN=false
    
    local result
    result=$(_prepare_file_paths "/videos/my movie file.mkv" "/output")
    
    local filename
    filename=$(echo "$result" | cut -d'|' -f1)
    
    [ "$filename" = "my movie file.mkv" ]
}

@test "_prepare_file_paths: gère les espaces dans le chemin" {
    SOURCE="/videos"
    SUFFIX_STRING="_x265"
    DRYRUN=false
    
    local result
    result=$(_prepare_file_paths "/videos/season one/episode 01.mkv" "/output")
    
    local final_dir
    final_dir=$(echo "$result" | cut -d'|' -f2)
    
    [[ "$final_dir" =~ "season one" ]]
}
