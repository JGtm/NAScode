#!/usr/bin/env bats
###########################################################
# TESTS DU MODE FILM-ADAPTIVE
#
# Tests unitaires pour l'analyse de complexité et le calcul
# de bitrate adaptatif introduits par le mode film-adaptive.
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
# Tests du mode film-adaptive dans config.sh
###########################################################

@test "set_conversion_mode_parameters: film-adaptive définit ADAPTIVE_COMPLEXITY_MODE" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="film-adaptive"
    set_conversion_mode_parameters
    
    [[ "${ADAPTIVE_COMPLEXITY_MODE}" == true ]]
}

@test "set_conversion_mode_parameters: film-adaptive active CRF 21" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="film-adaptive"
    set_conversion_mode_parameters
    
    [[ "${CRF_VALUE}" -eq 21 ]]
}

@test "set_conversion_mode_parameters: film-adaptive est en single-pass" {
    # complexity.sh already loaded by load_base_modules
    
    CONVERSION_MODE="film-adaptive"
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
