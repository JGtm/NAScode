#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/off_peak.sh
# Vérifie les fonctions de gestion des heures creuses
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal
    source "$LIB_DIR/off_peak.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de time_to_minutes()
###########################################################

@test "time_to_minutes: convertit 00:00 en 0" {
    result=$(time_to_minutes "00:00")
    [ "$result" -eq 0 ]
}

@test "time_to_minutes: convertit 01:00 en 60" {
    result=$(time_to_minutes "01:00")
    [ "$result" -eq 60 ]
}

@test "time_to_minutes: convertit 12:30 en 750" {
    result=$(time_to_minutes "12:30")
    [ "$result" -eq 750 ]
}

@test "time_to_minutes: convertit 22:00 en 1320" {
    result=$(time_to_minutes "22:00")
    [ "$result" -eq 1320 ]
}

@test "time_to_minutes: convertit 23:59 en 1439" {
    result=$(time_to_minutes "23:59")
    [ "$result" -eq 1439 ]
}

@test "time_to_minutes: gère les heures avec zéro initial (08:30)" {
    result=$(time_to_minutes "08:30")
    [ "$result" -eq 510 ]
}

@test "time_to_minutes: gère les heures sans zéro initial (6:00)" {
    result=$(time_to_minutes "6:00")
    [ "$result" -eq 360 ]
}

###########################################################
# Tests de parse_off_peak_range()
###########################################################

@test "parse_off_peak_range: accepte format valide 22:00-06:00" {
    parse_off_peak_range "22:00-06:00"
    [ "$OFF_PEAK_START" = "22:00" ]
    [ "$OFF_PEAK_END" = "06:00" ]
}

@test "parse_off_peak_range: accepte format valide 23:30-07:30" {
    parse_off_peak_range "23:30-07:30"
    [ "$OFF_PEAK_START" = "23:30" ]
    [ "$OFF_PEAK_END" = "07:30" ]
}

@test "parse_off_peak_range: accepte format sans zéros initiaux 8:00-18:00" {
    parse_off_peak_range "8:00-18:00"
    [ "$OFF_PEAK_START" = "08:00" ]
    [ "$OFF_PEAK_END" = "18:00" ]
}

@test "parse_off_peak_range: rejette format invalide (sans tiret)" {
    run parse_off_peak_range "22:00"
    [ "$status" -ne 0 ]
}

@test "parse_off_peak_range: rejette format invalide (heure > 23)" {
    run parse_off_peak_range "25:00-06:00"
    [ "$status" -ne 0 ]
}

@test "parse_off_peak_range: rejette format invalide (minutes > 59)" {
    run parse_off_peak_range "22:60-06:00"
    [ "$status" -ne 0 ]
}

@test "parse_off_peak_range: rejette format invalide (texte)" {
    run parse_off_peak_range "invalid"
    [ "$status" -ne 0 ]
}

@test "parse_off_peak_range: rejette format vide" {
    run parse_off_peak_range ""
    [ "$status" -ne 0 ]
}

###########################################################
# Tests de is_off_peak_time()
###########################################################

# Helper pour tester is_off_peak_time avec une heure simulée
_test_is_off_peak() {
    local simulated_time="$1"
    local start="$2"
    local end="$3"
    
    # Remplacer temporairement la commande date
    date() {
        if [[ "$1" == "+%H:%M" ]]; then
            echo "$simulated_time"
        else
            command date "$@"
        fi
    }
    export -f date
    
    OFF_PEAK_START="$start"
    OFF_PEAK_END="$end"
    
    is_off_peak_time
    local result=$?
    
    # Restaurer date
    unset -f date
    
    return $result
}

@test "is_off_peak_time: 23:00 est dans la plage 22:00-06:00" {
    _test_is_off_peak "23:00" "22:00" "06:00"
}

@test "is_off_peak_time: 03:00 est dans la plage 22:00-06:00" {
    _test_is_off_peak "03:00" "22:00" "06:00"
}

@test "is_off_peak_time: 12:00 n'est pas dans la plage 22:00-06:00" {
    run _test_is_off_peak "12:00" "22:00" "06:00"
    [ "$status" -ne 0 ]
}

@test "is_off_peak_time: 06:00 n'est pas dans la plage 22:00-06:00 (fin exclusive)" {
    run _test_is_off_peak "06:00" "22:00" "06:00"
    [ "$status" -ne 0 ]
}

@test "is_off_peak_time: 22:00 est dans la plage 22:00-06:00 (début inclusif)" {
    _test_is_off_peak "22:00" "22:00" "06:00"
}

@test "is_off_peak_time: plage normale 08:00-18:00, 10:00 est dedans" {
    _test_is_off_peak "10:00" "08:00" "18:00"
}

@test "is_off_peak_time: plage normale 08:00-18:00, 20:00 n'est pas dedans" {
    run _test_is_off_peak "20:00" "08:00" "18:00"
    [ "$status" -ne 0 ]
}

@test "is_off_peak_time: plage normale 08:00-18:00, 08:00 est dedans (début inclusif)" {
    _test_is_off_peak "08:00" "08:00" "18:00"
}

@test "is_off_peak_time: plage normale 08:00-18:00, 18:00 n'est pas dedans (fin exclusive)" {
    run _test_is_off_peak "18:00" "08:00" "18:00"
    [ "$status" -ne 0 ]
}

###########################################################
# Tests de format_wait_time()
###########################################################

@test "format_wait_time: 0 secondes" {
    result=$(format_wait_time 0)
    [ "$result" = "0s" ]
}

@test "format_wait_time: 45 secondes" {
    result=$(format_wait_time 45)
    [ "$result" = "45s" ]
}

@test "format_wait_time: 90 secondes = 1min 30s" {
    result=$(format_wait_time 90)
    [ "$result" = "1min 30s" ]
}

@test "format_wait_time: 3600 secondes = 1h" {
    result=$(format_wait_time 3600)
    [ "$result" = "1h" ]
}

@test "format_wait_time: 3661 secondes = 1h 1min 1s" {
    result=$(format_wait_time 3661)
    [ "$result" = "1h 1min 1s" ]
}

@test "format_wait_time: 7200 secondes = 2h" {
    result=$(format_wait_time 7200)
    [ "$result" = "2h" ]
}

@test "format_wait_time: 5400 secondes = 1h 30min" {
    result=$(format_wait_time 5400)
    [ "$result" = "1h 30min" ]
}

###########################################################
# Tests de seconds_until_off_peak()
###########################################################

# Helper pour tester seconds_until_off_peak avec une heure simulée
_test_seconds_until() {
    local simulated_time="$1"
    local start="$2"
    
    # Remplacer temporairement la commande date
    date() {
        if [[ "$1" == "+%H:%M" ]]; then
            echo "$simulated_time"
        else
            command date "$@"
        fi
    }
    export -f date
    
    OFF_PEAK_START="$start"
    
    seconds_until_off_peak
    local result=$?
    
    # Restaurer date
    unset -f date
}

@test "seconds_until_off_peak: de 12:00 à 22:00 = 10h = 36000s" {
    result=$(_test_seconds_until "12:00" "22:00")
    [ "$result" -eq 36000 ]
}

@test "seconds_until_off_peak: de 21:00 à 22:00 = 1h = 3600s" {
    result=$(_test_seconds_until "21:00" "22:00")
    [ "$result" -eq 3600 ]
}

@test "seconds_until_off_peak: de 23:00 à 22:00 = 23h = 82800s (jour suivant)" {
    result=$(_test_seconds_until "23:00" "22:00")
    [ "$result" -eq 82800 ]
}

###########################################################
# Tests de check_off_peak_before_processing()
###########################################################

@test "check_off_peak_before_processing: retourne 0 si OFF_PEAK_ENABLED=false" {
    OFF_PEAK_ENABLED=false
    check_off_peak_before_processing
}

###########################################################
# Tests d'intégration des variables par défaut
###########################################################

@test "off_peak: valeurs par défaut correctes" {
    # Recharger pour avoir les valeurs par défaut
    source "$LIB_DIR/off_peak.sh"
    
    [ "$OFF_PEAK_ENABLED" = "false" ]
    [ "$OFF_PEAK_START" = "22:00" ]
    [ "$OFF_PEAK_END" = "06:00" ]
    [ "$OFF_PEAK_CHECK_INTERVAL" -eq 60 ]
}
