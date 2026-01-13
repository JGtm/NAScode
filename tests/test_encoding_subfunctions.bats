#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Sous-fonctions d'encodage refactorisées
# Tests pour _setup_video_encoding_params, _setup_sample_mode_params, etc.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/ffmpeg_pipeline.sh"
    source "$LIB_DIR/transcode_video.sh"
    
    # Initialiser le mode conversion (définit TARGET_BITRATE_KBPS, etc.)
    set_conversion_mode_parameters "series"
    
    # Les variables readonly sont déjà définies par config.sh
    # On utilise leurs valeurs par défaut
    NO_PROGRESS=true
    SAMPLE_MODE=false
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _setup_video_encoding_params() - variables globales
###########################################################

@test "_setup_video_encoding_params: définit VIDEO_BITRATE pour 1080p" {
    # Simuler get_video_stream_props
    get_video_stream_props() { echo "1920|1080|yuv420p"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    # VIDEO_BITRATE doit être défini
    [ -n "$VIDEO_BITRATE" ]
    [[ "$VIDEO_BITRATE" =~ ^[0-9]+k$ ]]
}

@test "_setup_video_encoding_params: réduit le bitrate pour 720p" {
    get_video_stream_props() { echo "1280|720|yuv420p"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    # Le bitrate doit être ~70% de 2070k = ~1449k
    local bitrate_num=${VIDEO_BITRATE%k}
    [ "$bitrate_num" -lt 2070 ]
    [ "$bitrate_num" -gt 1400 ]
}

@test "_setup_video_encoding_params: cap qualité équivalente si codec source moins efficace" {
    # Source: H.264 à 1000 kbps ; cible: HEVC.
    # Avec efficacités par défaut (H264=100, HEVC=70), le cap attendu est 700 kbps.
    CONVERSION_MODE="serie"
    VIDEO_CODEC="hevc"
    VIDEO_ENCODER="libx265"
    set_conversion_mode_parameters

    get_video_stream_props() { echo "1920|1080|yuv420p"; }
    export -f get_video_stream_props

    SOURCE_VIDEO_CODEC="h264"
    SOURCE_VIDEO_BITRATE_BITS=1000000

    _setup_video_encoding_params "/fake/file.mkv"

    [ "$VIDEO_BITRATE" = "700k" ]
    [ "$VIDEO_MAXRATE" = "852k" ]
    [ "$VIDEO_BUFSIZE" = "1278k" ]
}

@test "_setup_video_encoding_params: définit OUTPUT_PIX_FMT" {
    get_video_stream_props() { echo "1920|1080|yuv420p10le"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    [ "$OUTPUT_PIX_FMT" = "yuv420p10le" ]
}

@test "_setup_video_encoding_params: définit X265_VBV_STRING" {
    get_video_stream_props() { echo "1920|1080|yuv420p"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    [[ "$X265_VBV_STRING" =~ "vbv-maxrate=" ]]
    [[ "$X265_VBV_STRING" =~ "vbv-bufsize=" ]]
}

@test "_setup_video_encoding_params: film-adaptive applique ADAPTIVE_* en HEVC/x265" {
    # Simuler une source 720p
    get_video_stream_props() { echo "1280|720|yuv420p"; }
    export -f get_video_stream_props

    CONVERSION_MODE="film-adaptive"
    VIDEO_CODEC="hevc"
    VIDEO_ENCODER="libx265"
    set_conversion_mode_parameters

    # Forcer les paramètres adaptatifs (ceux-ci doivent prendre le dessus)
    ADAPTIVE_COMPLEXITY_MODE=true
    ADAPTIVE_TARGET_KBPS=571
    ADAPTIVE_MAXRATE_KBPS=799
    ADAPTIVE_BUFSIZE_KBPS=1998

    _setup_video_encoding_params "/fake/file.mkv"

    [ "$VIDEO_BITRATE" = "571k" ]
    [ "$VIDEO_MAXRATE" = "799k" ]
    [ "$VIDEO_BUFSIZE" = "1998k" ]
    [ "$X265_VBV_STRING" = "vbv-maxrate=799:vbv-bufsize=1998" ]
}

@test "_setup_video_encoding_params: SVT-AV1 ajoute keyint dans ENCODER_BASE_PARAMS" {
    # Skip si libsvtav1 n'est pas disponible dans FFmpeg
    if ! ffmpeg -encoders 2>/dev/null | grep -q libsvtav1; then
        skip "libsvtav1 non disponible dans FFmpeg"
    fi
    
    VIDEO_CODEC="av1"
    VIDEO_ENCODER="libsvtav1"
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    get_video_stream_props() { echo "1920|1080|yuv420p10le"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    # Vérifier que keyint est présent dans les params SVT-AV1
    [[ "$ENCODER_BASE_PARAMS" =~ "keyint=" ]]
}

@test "_setup_video_encoding_params: SVT-AV1 inclut tune et enable-overlays" {
    # Skip si libsvtav1 n'est pas disponible dans FFmpeg
    if ! ffmpeg -encoders 2>/dev/null | grep -q libsvtav1; then
        skip "libsvtav1 non disponible dans FFmpeg"
    fi
    
    VIDEO_CODEC="av1"
    VIDEO_ENCODER="libsvtav1"
    CONVERSION_MODE="serie"
    set_conversion_mode_parameters
    
    get_video_stream_props() { echo "1920|1080|yuv420p10le"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    [[ "$ENCODER_BASE_PARAMS" =~ "tune=" ]]
    [[ "$ENCODER_BASE_PARAMS" =~ "enable-overlays=" ]]
}

###########################################################
# Tests de _setup_sample_mode_params()
###########################################################

@test "_setup_sample_mode_params: ne fait rien si SAMPLE_MODE=false" {
    SAMPLE_MODE=false
    
    _setup_sample_mode_params "/fake/file.mkv" "3600"
    
    [ -z "$SAMPLE_SEEK_PARAMS" ]
    [ -z "$SAMPLE_DURATION_PARAMS" ]
    [ "$EFFECTIVE_DURATION" = "3600" ]
}

@test "_setup_sample_mode_params: définit les paramètres si SAMPLE_MODE=true" {
    SAMPLE_MODE=true
    SAMPLE_DURATION=30
    SAMPLE_MARGIN_START=180
    SAMPLE_MARGIN_END=120
    
    # Mock ffprobe pour éviter l'appel réel
    ffprobe() { echo "200.0"; }
    export -f ffprobe
    
    _setup_sample_mode_params "/fake/file.mkv" "3600"
    
    # Vérifier que les paramètres sont définis
    [[ "$SAMPLE_SEEK_PARAMS" =~ "-ss" ]]
    [[ "$SAMPLE_DURATION_PARAMS" == "-t 30" ]]
    [ "$EFFECTIVE_DURATION" = "30" ]
}

###########################################################
# Tests de _build_audio_params()
###########################################################

@test "_build_audio_params: retourne copy par défaut" {
    AUDIO_CODEC="copy"
    
    local result
    result=$(_build_audio_params "/fake/file.mkv")
    
    [ "$result" = "-c:a copy" ]
}

###########################################################
# Tests de cohérence des noms de variables
###########################################################

@test "nomenclature: VIDEO_BITRATE est bien nommé (pas ff_bitrate)" {
    get_video_stream_props() { echo "1920|1080|yuv420p"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    # VIDEO_BITRATE doit exister
    [ -n "$VIDEO_BITRATE" ]
    # L'ancienne variable ne doit pas être définie par cette fonction
    [ -z "${ff_bitrate:-}" ]
}

@test "nomenclature: OUTPUT_PIX_FMT est bien nommé (pas output_pix_fmt local)" {
    get_video_stream_props() { echo "1920|1080|yuv420p"; }
    export -f get_video_stream_props
    
    _setup_video_encoding_params "/fake/file.mkv"
    
    # La variable globale doit être définie
    [ -n "$OUTPUT_PIX_FMT" ]
}

###########################################################
# Tests de _compute_output_height_for_bitrate avec variables explicites
###########################################################

@test "_compute_output_height_for_bitrate: utilise src_width/src_height (pas width/height)" {
    # Vérifier que la fonction fonctionne avec les nouveaux noms de paramètres
    local result
    result=$(_compute_output_height_for_bitrate "1280" "720")
    
    [ "$result" = "720" ]
}

@test "_compute_output_height_for_bitrate: calcule computed_height correctement" {
    # Test avec downscale nécessaire (4K → 1080p)
    local result
    result=$(_compute_output_height_for_bitrate "3840" "2160")
    
    # La hauteur doit être <= 1080 et paire
    [ "$result" -le 1080 ]
    [ $((result % 2)) -eq 0 ]
}

###########################################################
# Tests de _compute_effective_bitrate_kbps_for_height avec variables explicites
###########################################################

@test "_compute_effective_bitrate_kbps_for_height: utilise output_height (pas out_height)" {
    local result
    result=$(_compute_effective_bitrate_kbps_for_height "2070" "720")
    
    # Doit retourner ~70% de 2070 = ~1449
    [ "$result" -gt 1400 ]
    [ "$result" -lt 1500 ]
}

@test "_compute_effective_bitrate_kbps_for_height: utilise scale_percent (pas pct)" {
    # Note: ADAPTIVE_720P_SCALE_PERCENT est readonly (70 par défaut)
    # On teste avec la valeur par défaut
    
    local result
    result=$(_compute_effective_bitrate_kbps_for_height "2000" "720")
    
    # Avec 70%, on attend 1400
    [ "$result" -eq 1400 ]
}

###########################################################
# Tests de _build_effective_suffix_for_dims avec variables explicites
###########################################################

@test "_build_effective_suffix_for_dims: utilise src_width/src_height" {
    # Les variables readonly sont définies par config.sh
    AUDIO_CODEC="copy"
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims "1920" "1080")
    
    [[ "$result" =~ "_x265_" ]]
    [[ "$result" =~ "_1080p" ]]
}

@test "_build_effective_suffix_for_dims: utilise effective_bitrate_kbps" {
    # Les variables readonly sont définies par config.sh
    # TARGET_BITRATE_KBPS=2070, ADAPTIVE_720P_SCALE_PERCENT=70
    # Forcer two-pass pour tester le bitrate adapté
    SINGLE_PASS_MODE=false
    AUDIO_CODEC="copy"
    SAMPLE_MODE=false
    
    local result
    result=$(_build_effective_suffix_for_dims "1280" "720")
    
    # Le bitrate dans le suffixe doit être réduit (~1449k pour 2070*70%)
    [[ "$result" =~ "_1449k_" ]] || [[ "$result" =~ "_14[0-9][0-9]k_" ]]
}
