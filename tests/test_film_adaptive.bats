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
    load_base_modules
    # Charger complexity.sh (déjà chargé par load_base_modules via test_helper)
    # Les constantes utilisent ${VAR:-default} donc pas de problème de re-source
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests du calcul du coefficient de complexité
###########################################################

@test "_map_stddev_to_complexity: stddev très bas → C_MIN (0.85)" {
    local result
    result=$(_map_stddev_to_complexity "0.10")
    
    # Devrait retourner C_MIN (0.85) pour un stddev très bas
    [[ "$result" == "0.85" ]]
}

@test "_map_stddev_to_complexity: stddev très haut → C_MAX (1.25)" {
    local result
    result=$(_map_stddev_to_complexity "0.50")
    
    # Devrait retourner C_MAX (1.25) pour un stddev élevé
    [[ "$result" == "1.25" ]]
}

@test "_map_stddev_to_complexity: stddev moyen → interpolation linéaire" {
    # Avec stddev au milieu de la plage (0.325 = milieu entre 0.20 et 0.45)
    local result
    result=$(_map_stddev_to_complexity "0.325")
    
    # Devrait être autour de 1.05 (milieu entre 0.85 et 1.25)
    # Vérifions qu'il est dans la plage attendue
    local c_val
    c_val=$(awk -v r="$result" 'BEGIN { print (r >= 1.0 && r <= 1.1) ? "ok" : "fail" }')
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
    # complexity.sh already loaded by load_base_modules
    
    # 1920×1080×24×0.032/1000 × 1.0 = ~1592 kbps
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "1.0" "")
    
    # Le résultat devrait être autour de 1592 kbps (±150)
    [[ "$result" -ge 1450 && "$result" -le 1750 ]]
}

@test "compute_adaptive_target_bitrate: coefficient faible → bitrate réduit" {
    # complexity.sh already loaded by load_base_modules
    
    # Avec C=0.85, le bitrate devrait être ~85% de celui à C=1.0
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "0.85" "")
    
    # ~1592 × 0.85 = ~1353 kbps
    [[ "$result" -ge 1200 && "$result" -le 1500 ]]
}

@test "compute_adaptive_target_bitrate: coefficient élevé → bitrate augmenté" {
    # complexity.sh already loaded by load_base_modules
    
    # Avec C=1.25, le bitrate devrait être ~125% de celui à C=1.0
    local result
    result=$(compute_adaptive_target_bitrate 1920 1080 24 "1.25" "")
    
    # ~1592 × 1.25 = ~1990 kbps
    [[ "$result" -ge 1850 && "$result" -le 2150 ]]
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
