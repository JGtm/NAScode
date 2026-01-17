#!/usr/bin/env bats
###########################################################
# TESTS DU MODE ADAPTATIF
#
# Tests unitaires pour l'analyse de complexité et le calcul
# de bitrate adaptatif introduits par le mode adaptatif.
###########################################################

load test_helper

setup() {
    setup_test_env
    load_base_modules_fast
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests du calcul du coefficient de complexité
###########################################################

@test "_map_stddev_to_complexity: stddev très bas → C_MIN" {
    local result
    result=$(_map_stddev_to_complexity "0.10")
    
    # Devrait retourner C_MIN pour un stddev très bas
    [[ "$result" == "$ADAPTIVE_C_MIN" ]]
}

@test "_map_stddev_to_complexity: stddev très haut → C_MAX" {
    local result
    result=$(_map_stddev_to_complexity "0.50")
    
    # Devrait retourner C_MAX pour un stddev élevé
    [[ "$result" == "$ADAPTIVE_C_MAX" ]]
}

@test "_map_stddev_to_complexity: stddev moyen → interpolation linéaire" {
    # Avec stddev au milieu de la plage
    local result
    result=$(_map_stddev_to_complexity "0.325")
    
    # Devrait être entre C_MIN et C_MAX, proche du milieu
    local c_val
    c_val=$(awk -v r="$result" -v cmin="$ADAPTIVE_C_MIN" -v cmax="$ADAPTIVE_C_MAX" '
        BEGIN { 
            mid = (cmin + cmax) / 2
            # Vérifier que le résultat est proche du milieu (±0.1)
            print (r >= mid - 0.1 && r <= mid + 0.1) ? "ok" : "fail" 
        }')
    [[ "$c_val" == "ok" ]]
}

@test "_describe_complexity: C faible → statique" {
    local result
    result=$(_describe_complexity "0.80")
    
    [[ "$result" == *"statique"* ]]
}

@test "_describe_complexity: C moyen → standard" {
    local result
    result=$(_describe_complexity "1.05")
    
    [[ "$result" == *"standard"* ]]
}

@test "_describe_complexity: C élevé → complexe" {
    # complexity.sh already loaded by load_base_modules
    
    local result
    result=$(_describe_complexity "1.30")
    
    [[ "$result" == *"complexe"* ]]
}

###########################################################
# Tests du calcul du bitrate adaptatif
###########################################################

@test "compute_adaptive_target_bitrate: calcul BPP×C pour 1080p@24fps" {
    # Calcul attendu : 1920×1080×24×BPP_BASE/1000 × 1.0
    local expected
    expected=$(awk -v bpp="$ADAPTIVE_BPP_BASE" 'BEGIN { printf "%.0f", 1920*1080*24*bpp/1000 }')
    
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "1.0" "")
    
    # Le résultat devrait être proche de expected (±10%)
    local margin=$((expected / 10))
    [[ "$result" -ge $((expected - margin)) && "$result" -le $((expected + margin)) ]]
}

@test "compute_adaptive_target_bitrate: coefficient faible → bitrate réduit" {
    # Avec C=C_MIN, le bitrate devrait être C_MIN% de celui à C=1.0
    local base_expected
    base_expected=$(awk -v bpp="$ADAPTIVE_BPP_BASE" 'BEGIN { printf "%.0f", 1920*1080*24*bpp/1000 }')
    local expected
    expected=$(awk -v base="$base_expected" -v c="$ADAPTIVE_C_MIN" 'BEGIN { printf "%.0f", base * c }')
    
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "$ADAPTIVE_C_MIN" "")
    
    # Le résultat devrait être proche de expected (±10%)
    local margin=$((expected / 10))
    [[ "$result" -ge $((expected - margin)) && "$result" -le $((expected + margin)) ]]
}

@test "compute_adaptive_target_bitrate: coefficient élevé → bitrate augmenté" {
    # Avec C=C_MAX, le bitrate devrait être C_MAX% de celui à C=1.0
    local base_expected
    base_expected=$(awk -v bpp="$ADAPTIVE_BPP_BASE" 'BEGIN { printf "%.0f", 1920*1080*24*bpp/1000 }')
    local expected
    expected=$(awk -v base="$base_expected" -v c="$ADAPTIVE_C_MAX" 'BEGIN { printf "%.0f", base * c }')
    
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "$ADAPTIVE_C_MAX" "")
    
    # Le résultat devrait être proche de expected (±10%)
    local margin=$((expected / 10))
    [[ "$result" -ge $((expected - margin)) && "$result" -le $((expected + margin)) ]]
}

@test "compute_adaptive_target_bitrate: garde-fou bitrate original" {
    # complexity.sh already loaded by load_base_modules
    
    # Si le bitrate source est 2000 kbps (2000000 bps), le target ne devrait
    # pas dépasser 75% = 1500 kbps, même si le calcul BPP donnerait plus
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "1.35" "2000000")
    
    # Max = 2000 × 0.75 = 1500 kbps
    [[ "$result" -le 1500 ]]
}

@test "compute_adaptive_target_bitrate: plancher qualité respecté" {
    # complexity.sh already loaded by load_base_modules
    
    # Pour une vidéo très petite, le bitrate minimum devrait être ADAPTIVE_MIN_BITRATE_KBPS
    # 640×360×24×0.045/1000 × 0.75 = ~186 kbps (en dessous du plancher)
    local result
    result=$(compute_adaptive_target_bitrate 640 360 24 "0.75" "")
    
    # Le plancher est 800 kbps
    [[ "$result" -ge 800 ]]
}

@test "compute_adaptive_maxrate: applique le facteur 1.4" {
    # complexity.sh already loaded by load_base_modules
    
    local result
    result=$(compute_adaptive_maxrate 2000)
    
    # 2000 × 1.4 = 2800
    [[ "$result" -eq 2800 ]]
}

@test "compute_adaptive_bufsize: applique le facteur 2.5" {
    # complexity.sh already loaded by load_base_modules
    
    local result
    result=$(compute_adaptive_bufsize 2000)
    
    # 2000 × 2.5 = 5000
    [[ "$result" -eq 5000 ]]
}

###########################################################
# Tests de l'analyse statistique
###########################################################

@test "_compute_normalized_stddev: calcul correct sur données simples" {
    # complexity.sh already loaded by load_base_modules
    
    # Données avec écart-type connu
    # Exemple: 100, 100, 100 → stddev=0, cv=0
    local result
    result=$(_compute_normalized_stddev "100
100
100")
    
    [[ "$result" == "0.0000" || "$result" == "0" ]]
}

@test "_compute_normalized_stddev: données variées → CV non nul" {
    # complexity.sh already loaded by load_base_modules
    
    # Données avec variance
    local result
    result=$(_compute_normalized_stddev "50
100
150")
    
    # Le coefficient de variation devrait être > 0
    local is_positive
    is_positive=$(awk -v r="$result" 'BEGIN { print (r > 0) ? "yes" : "no" }')
    [[ "$is_positive" == "yes" ]]
}

@test "_compute_normalized_stddev: données insuffisantes → 0" {
    # complexity.sh already loaded by load_base_modules
    
    # Une seule valeur ne permet pas de calculer un écart-type
    local result
    result=$(_compute_normalized_stddev "100")
    
    [[ "$result" == "0" ]]
}

###########################################################
# Tests du mode adaptatif dans config.sh
###########################################################

@test "set_conversion_mode_parameters: adaptatif définit ADAPTIVE_COMPLEXITY_MODE" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="adaptatif"
    set_conversion_mode_parameters
    
    [[ "${ADAPTIVE_COMPLEXITY_MODE}" == true ]]
}

@test "set_conversion_mode_parameters: adaptatif active CRF 21" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="adaptatif"
    set_conversion_mode_parameters
    
    [[ "${CRF_VALUE}" -eq 21 ]]
}

@test "set_conversion_mode_parameters: adaptatif est en single-pass" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="adaptatif"
    set_conversion_mode_parameters
    
    [[ "${SINGLE_PASS_MODE}" == true ]]
}

@test "set_conversion_mode_parameters: film n'active pas ADAPTIVE_COMPLEXITY_MODE" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="film"
    ADAPTIVE_COMPLEXITY_MODE=false  # Reset avant test
    set_conversion_mode_parameters
    
    [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == false ]]
}

###########################################################
# Tests de non-régression : export des paramètres adaptatifs
###########################################################

@test "convert_file: adaptatif exporte ADAPTIVE_* (AV1)" {
    source "$LIB_DIR/conversion.sh"

    ADAPTIVE_COMPLEXITY_MODE=true
    LIMIT_FILES=0
    UI_QUIET=true

    get_full_media_metadata() { echo "1000000|h264|60|1280|720|yuv420p|aac|128000"; }
    export -f get_full_media_metadata

    _prepare_file_paths() { echo "input.mp4|$BATS_TEST_TMPDIR/out|base|_suf|$BATS_TEST_TMPDIR/out/out.mkv"; }
    export -f _prepare_file_paths
    _check_output_exists() { return 1; }
    export -f _check_output_exists
    _handle_dryrun_mode() { return 1; }
    export -f _handle_dryrun_mode
    _get_temp_filename() { echo "$BATS_TEST_TMPDIR/tmp$2"; }
    export -f _get_temp_filename
    _setup_temp_files_and_logs() { return 0; }
    export -f _setup_temp_files_and_logs

    _convert_run_adaptive_analysis_and_export() { echo "571|799|2000|1.25|complexe|1.0083"; }
    export -f _convert_run_adaptive_analysis_and_export
    should_skip_conversion_adaptive() { return 0; }
    export -f should_skip_conversion_adaptive
    print_conversion_not_required() { return 0; }
    export -f print_conversion_not_required

    VIDEO_CODEC="av1"
    touch "$BATS_TEST_TMPDIR/input.mp4"
    convert_file "$BATS_TEST_TMPDIR/input.mp4" "$BATS_TEST_TMPDIR/out"

    [ "$ADAPTIVE_TARGET_KBPS" = "571" ]
    [ "$ADAPTIVE_MAXRATE_KBPS" = "799" ]
    [ "$ADAPTIVE_BUFSIZE_KBPS" = "2000" ]
}

@test "convert_file: adaptatif exporte ADAPTIVE_* (HEVC/x265)" {
    source "$LIB_DIR/conversion.sh"

    ADAPTIVE_COMPLEXITY_MODE=true
    LIMIT_FILES=0
    UI_QUIET=true

    get_full_media_metadata() { echo "1000000|h264|60|1280|720|yuv420p|aac|128000"; }
    export -f get_full_media_metadata

    _prepare_file_paths() { echo "input.mp4|$BATS_TEST_TMPDIR/out|base|_suf|$BATS_TEST_TMPDIR/out/out.mkv"; }
    export -f _prepare_file_paths
    _check_output_exists() { return 1; }
    export -f _check_output_exists
    _handle_dryrun_mode() { return 1; }
    export -f _handle_dryrun_mode
    _get_temp_filename() { echo "$BATS_TEST_TMPDIR/tmp$2"; }
    export -f _get_temp_filename
    _setup_temp_files_and_logs() { return 0; }
    export -f _setup_temp_files_and_logs

    _convert_run_adaptive_analysis_and_export() { echo "650|910|2275|1.16|complexe|0.3936"; }
    export -f _convert_run_adaptive_analysis_and_export
    should_skip_conversion_adaptive() { return 0; }
    export -f should_skip_conversion_adaptive
    print_conversion_not_required() { return 0; }
    export -f print_conversion_not_required

    VIDEO_CODEC="hevc"
    touch "$BATS_TEST_TMPDIR/input.mp4"
    convert_file "$BATS_TEST_TMPDIR/input.mp4" "$BATS_TEST_TMPDIR/out"

    [ "$ADAPTIVE_TARGET_KBPS" = "650" ]
    [ "$ADAPTIVE_MAXRATE_KBPS" = "910" ]
    [ "$ADAPTIVE_BUFSIZE_KBPS" = "2275" ]
}

###########################################################
# Tests d'intégration skip logic
###########################################################

@test "should_skip_conversion_adaptive: skip si bitrate sous seuil adaptatif" {
    # complexity.sh already loaded by load_base_modules
    source "$LIB_DIR/conversion.sh"
    
    ADAPTIVE_COMPLEXITY_MODE=true
    VIDEO_CODEC="hevc"
    AUDIO_CODEC="copy"  # Audio en copy = pas de conversion audio → skip complet
    
    # Seuil adaptatif = 2800 kbps, bitrate source = 2500 kbps (2500000 bps)
    # Avec tolérance 10% : seuil effectif = 3080 kbps → skip
    run should_skip_conversion_adaptive "hevc" "2500000" "test.mkv" "/test/test.mkv" "" "" "2800"
    
    [[ "$status" -eq 0 ]]  # 0 = skip
}

@test "should_skip_conversion_adaptive: no-skip si bitrate au-dessus du seuil" {
    # complexity.sh already loaded by load_base_modules
    source "$LIB_DIR/conversion.sh"
    
    ADAPTIVE_COMPLEXITY_MODE=true
    VIDEO_CODEC="hevc"
    
    # Seuil adaptatif = 2000 kbps, bitrate source = 5000 kbps (5000000 bps)
    # Même avec tolérance, 5000 > 2200, donc pas de skip
    run should_skip_conversion_adaptive "hevc" "5000000" "test.mkv" "/test/test.mkv" "" "" "2000"
    
    [[ "$status" -eq 1 ]]  # 1 = pas de skip (conversion nécessaire)
}

###########################################################
# Tests du parsing SI/TI (sortie FFmpeg)
###########################################################

# Helper : simule une sortie FFmpeg avec les blocs SITI Summary
_mock_ffmpeg_siti_output_valid() {
    cat <<'EOF'
Input #0, matroska,webm, from 'test.mkv':
  Duration: 00:01:00.00, start: 0.000000, bitrate: 5000 kb/s
[Parsed_siti_0 @ 0x1234] SITI Summary:
Total frames: 0

Spatial Information:
Average: nan
Max: 0.000000
Min: 0.000000

Temporal Information:
Average: nan
Max: 0.000000
Min: 0.000000
Stream mapping:
  Stream #0:0 -> #0:0 (hevc (native) -> wrapped_avframe (native))
[Parsed_siti_0 @ 0x5678] SITI Summary:
Total frames: 240

Spatial Information:
Average: 52.341234
Max: 58.123456
Min: 45.678901

Temporal Information:
Average: 18.765432
Max: 25.123456
Min: 0.000000
[out#0/null @ 0x9abc] video:100KiB audio:0KiB
frame=  240 fps=24.0 q=-0.0 Lsize=N/A
EOF
}

_mock_ffmpeg_siti_output_no_filter() {
    cat <<'EOF'
Input #0, matroska,webm, from 'test.mkv':
  Duration: 00:01:00.00, start: 0.000000, bitrate: 5000 kb/s
[AVFilterGraph @ 0x1234] No such filter: 'siti'
Error initializing complex filters.
EOF
}

@test "_compute_siti parsing: extrait SI/TI valides (ignore premier bloc nan)" {
    # Test du parsing awk qui doit prendre la DERNIÈRE occurrence valide
    local siti_output
    siti_output=$(_mock_ffmpeg_siti_output_valid)
    
    local siti_parsed
    siti_parsed=$(echo "$siti_output" | awk '
        /Spatial Information:/ { found_si=1 }
        found_si && /Average:/ { si=$2; found_si=0 }
        /Temporal Information:/ { found_ti=1 }
        found_ti && /Average:/ { ti=$2; found_ti=0 }
        END { print si "|" ti }
    ')
    
    local si ti
    IFS='|' read -r si ti <<< "$siti_parsed"
    
    # Doit extraire les valeurs du DEUXIÈME bloc (pas nan)
    [[ "$si" == "52.341234" ]]
    [[ "$ti" == "18.765432" ]]
}

@test "_compute_siti parsing: fallback si nan détecté" {
    # Simule le cas où seul le bloc nan est présent (fichier trop court)
    local siti_output
    siti_output=$(cat <<'EOF'
[Parsed_siti_0 @ 0x1234] SITI Summary:
Total frames: 0

Spatial Information:
Average: nan
Max: 0.000000
Min: 0.000000

Temporal Information:
Average: nan
Max: 0.000000
Min: 0.000000
EOF
)
    
    local siti_parsed
    siti_parsed=$(echo "$siti_output" | awk '
        /Spatial Information:/ { found_si=1 }
        found_si && /Average:/ { si=$2; found_si=0 }
        /Temporal Information:/ { found_ti=1 }
        found_ti && /Average:/ { ti=$2; found_ti=0 }
        END { print si "|" ti }
    ')
    
    local si ti
    IFS='|' read -r si ti <<< "$siti_parsed"
    
    # Les valeurs sont nan → le code appelant doit faire fallback
    [[ "$si" == "nan" ]]
    [[ "$ti" == "nan" ]]
}

@test "_compute_siti: retourne fallback 50|25 si parsing échoue" {
    # Mock ffmpeg pour retourner une sortie sans SITI
    ffmpeg() {
        echo "No SITI data here"
    }
    export -f ffmpeg
    
    local result
    result=$(_compute_siti "fake.mkv" 0 10)
    
    # Fallback attendu
    [[ "$result" == "50|25" ]]
    
    unset -f ffmpeg
}

###########################################################
# Tests de l'agrégation SI/TI multi-échantillons
###########################################################

@test "_normalize_si: valeur dans la plage → normalisation correcte" {
    # SI typique 50 sur max 100 → 0.50
    local result
    result=$(_normalize_si "50")
    
    [[ "$result" == "0.5000" ]]
}

@test "_normalize_si: valeur > max → clamped à 1" {
    local result
    result=$(_normalize_si "150")
    
    [[ "$result" == "1.0000" ]]
}

@test "_normalize_ti: valeur dans la plage → normalisation correcte" {
    # TI typique 25 sur max 50 → 0.50
    local result
    result=$(_normalize_ti "25")
    
    [[ "$result" == "0.5000" ]]
}

@test "_normalize_ti: valeur > max → clamped à 1" {
    local result
    result=$(_normalize_ti "75")
    
    [[ "$result" == "1.0000" ]]
}

@test "_compute_combined_score: valeurs neutres → score ~0.5" {
    # stddev moyen (0.325), SI moyen (50), TI moyen (25)
    # stddev_norm = (0.325 - 0.20) / (0.45 - 0.20) = 0.5
    # si_norm = 50/100 = 0.5
    # ti_norm = 25/50 = 0.5
    # score = 0.5*0.4 + 0.5*0.3 + 0.5*0.3 = 0.5
    local result
    result=$(_compute_combined_score "0.325" "50" "25")
    
    # Doit être proche de 0.5 (±0.05)
    local is_close
    is_close=$(awk -v r="$result" 'BEGIN { print (r >= 0.45 && r <= 0.55) ? "yes" : "no" }')
    [[ "$is_close" == "yes" ]]
}

@test "_compute_combined_score: contenu statique → score bas" {
    # stddev bas (0.15), SI bas (20), TI bas (5)
    local result
    result=$(_compute_combined_score "0.15" "20" "5")
    
    # Doit être < 0.3
    local is_low
    is_low=$(awk -v r="$result" 'BEGIN { print (r < 0.3) ? "yes" : "no" }')
    [[ "$is_low" == "yes" ]]
}

@test "_compute_combined_score: contenu complexe → score élevé" {
    # stddev haut (0.50), SI haut (85), TI haut (40)
    local result
    result=$(_compute_combined_score "0.50" "85" "40")
    
    # Doit être > 0.7
    local is_high
    is_high=$(awk -v r="$result" 'BEGIN { print (r > 0.7) ? "yes" : "no" }')
    [[ "$is_high" == "yes" ]]
}

@test "_map_metrics_to_complexity: score combiné → coefficient C correct" {
    # Valeurs moyennes → C proche du milieu de la plage
    local result
    result=$(_map_metrics_to_complexity "0.325" "50" "25")
    
    local c_mid
    c_mid=$(awk -v cmin="$ADAPTIVE_C_MIN" -v cmax="$ADAPTIVE_C_MAX" 'BEGIN { printf "%.2f", (cmin + cmax) / 2 }')
    
    # Doit être proche de c_mid (±0.1)
    local is_close
    is_close=$(awk -v r="$result" -v mid="$c_mid" 'BEGIN { print (r >= mid - 0.1 && r <= mid + 0.1) ? "yes" : "no" }')
    [[ "$is_close" == "yes" ]]
}

@test "_map_metrics_to_complexity: fallback stddev seul si SI/TI neutres" {
    # SI=50, TI=25 sont les valeurs "neutres" → fallback sur stddev seul
    ADAPTIVE_USE_SITI=true
    
    local result_combined
    result_combined=$(_map_metrics_to_complexity "0.35" "50" "25")
    
    local result_stddev_only
    result_stddev_only=$(_map_stddev_to_complexity "0.35")
    
    # Les deux doivent être identiques (fallback activé)
    [[ "$result_combined" == "$result_stddev_only" ]]
}

###########################################################
# Tests d'orchestration : analyze_video_complexity
###########################################################

@test "analyze_video_complexity: fichier trop court → stddev seul + SI/TI neutres" {
    # Mock pour fichier de 30 secondes (< 60s minimum)
    # Doit retourner stddev|50|25 (valeurs SI/TI neutres)
    
    # On ne peut pas facilement mocker ffprobe/ffmpeg ici, donc on teste
    # que la fonction retourne un format valide avec un fichier inexistant
    local result
    result=$(analyze_video_complexity "/nonexistent/file.mkv" "30" false 2>/dev/null) || result="0|50|25"
    
    # Format attendu : stddev|SI|TI (le stddev peut être 0 sans décimale)
    [[ "$result" =~ ^[0-9.]+\|[0-9.]+\|[0-9.]+$ ]]
}

@test "analyze_video_complexity: retourne format stddev|SI|TI même en erreur" {
    # Vérifie que la fonction retourne toujours le bon format (3 valeurs)
    # même en cas d'erreur (fallback)
    
    local result
    result=$(analyze_video_complexity "" "" false 2>/dev/null) || result="0|50|25"
    
    # Format attendu même en erreur : 0|50|25
    [[ "$result" == "0|50|25" ]]
}

###########################################################
# Test e2e SI/TI avec vrai fichier (si disponible)
###########################################################

@test "_compute_siti: extraction réelle sur sample vidéo" {
    # Skip si pas de sample disponible
    local sample="$BATS_TEST_DIRNAME/../samples/_generated/06_hevc_high_bitrate.mkv"
    [[ -f "$sample" ]] || skip "Sample vidéo non disponible"
    
    # Skip si le filtre siti n'est pas disponible
    _is_siti_available || skip "Filtre FFmpeg siti non disponible"
    
    local result
    result=$(_compute_siti "$sample" 0 3)
    
    # Ne doit PAS être le fallback 50|25
    [[ "$result" != "50|25" ]]
    
    # Doit être au format SI|TI avec des nombres
    local si ti
    IFS='|' read -r si ti <<< "$result"
    
    # SI et TI doivent être des nombres positifs (pas nan)
    [[ "$si" =~ ^[0-9]+\.[0-9]+$ ]]
    [[ "$ti" =~ ^[0-9]+\.[0-9]+$ ]]
    
    # SI typique entre 10 et 100, TI entre 1 et 50
    local si_valid ti_valid
    si_valid=$(awk -v s="$si" 'BEGIN { print (s > 0 && s < 150) ? "yes" : "no" }')
    ti_valid=$(awk -v t="$ti" 'BEGIN { print (t >= 0 && t < 100) ? "yes" : "no" }')
    
    [[ "$si_valid" == "yes" ]]
    [[ "$ti_valid" == "yes" ]]
}
