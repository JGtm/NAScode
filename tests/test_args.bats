#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/args.sh
# Vérifie le parsing des options CLI et l'absence d'effets de bord
# VERSION CONSOLIDÉE pour performance (réduit le nombre de setup)
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal_fast  # Version rapide sans detect.sh (args.sh n'en a pas besoin)
    source "$LIB_DIR/utils.sh"     # nécessaire pour parse_human_size_to_bytes
    source "$LIB_DIR/off_peak.sh"  # Nécessaire pour parse_off_peak_range
    source "$LIB_DIR/args.sh"
}

teardown() {
    teardown_test_env
}

_reset_cli_state() {
    DRYRUN=false
    RANDOM_MODE=false
    LIMIT_FILES=0
    SUFFIX_MODE="ask"
    KEEP_INDEX=false
    REGENERATE_INDEX=false
    VMAF_ENABLED=false
    SAMPLE_MODE=false
    SINGLE_PASS_MODE=true
    NO_PROGRESS=false
    PARALLEL_JOBS=1
    CONVERSION_MODE="serie"
    VIDEO_CODEC="hevc"
    SOURCE="/source"
    OUTPUT_DIR="/output"
    CUSTOM_QUEUE=""
    EXCLUDES=()
    EXCLUDES_REGEX=""
    OFF_PEAK_ENABLED=false
    OFF_PEAK_START="22:00"
    OFF_PEAK_END="06:00"
    SINGLE_FILE=""
    MIN_SIZE_BYTES=0
}

###########################################################
# TEST CONSOLIDÉ : Options de base (-s, -o, -m, -c, -d)
###########################################################

@test "parse_arguments: options de base (source, output, mode, codec, dryrun)" {
    # Test 1: -s/-o/-m configurent les chemins et mode
    _reset_cli_state
    parse_arguments -s "/videos" -o "/out" -m "serie"
    [ "$DRYRUN" = "false" ]
    [ "$SOURCE" = "/videos" ]
    [ "$OUTPUT_DIR" = "/out" ]
    [ "$CONVERSION_MODE" = "serie" ]
    
    # Test 2: --mode film
    _reset_cli_state
    parse_arguments --mode film
    [ "$CONVERSION_MODE" = "film" ]
    
    # Test 3: --codec av1
    _reset_cli_state
    parse_arguments --codec av1
    [ "$VIDEO_CODEC" = "av1" ]
    
    # Test 4: -c hevc
    _reset_cli_state
    parse_arguments -c hevc
    [ "$VIDEO_CODEC" = "hevc" ]
    
    # Test 5: --codec combiné avec --mode
    _reset_cli_state
    parse_arguments -m film -c av1
    [ "$CONVERSION_MODE" = "film" ]
    [ "$VIDEO_CODEC" = "av1" ]
    
    # Test 6: -d active dry-run
    _reset_cli_state
    parse_arguments -d -s "/videos"
    [ "$DRYRUN" = "true" ]
    [ "$SOURCE" = "/videos" ]
    
    # Test 7: --dryrun
    _reset_cli_state
    parse_arguments --dryrun
    [ "$DRYRUN" = "true" ]
}

###########################################################
# TEST CONSOLIDÉ : Options de suffixe (-x, -S, --suffix)
###########################################################

@test "parse_arguments: options de suffixe (-x, -S, --suffix)" {
    # Test 1: SUFFIX_MODE par défaut est ask
    _reset_cli_state
    [ "$SUFFIX_MODE" = "ask" ]
    
    # Test 2: -x active SUFFIX_MODE=off
    _reset_cli_state
    parse_arguments -x
    [ "$SUFFIX_MODE" = "off" ]
    [ "$DRYRUN" = "false" ]
    
    # Test 3: --suffix avec valeur
    _reset_cli_state
    parse_arguments --suffix "_custom"
    [ "$SUFFIX_MODE" = "custom:_custom" ]
    
    # Test 4: --suffix sans argument
    _reset_cli_state
    parse_arguments --suffix
    [ "$SUFFIX_MODE" = "on" ]
    
    # Test 5: --suffix suivi d'une option
    _reset_cli_state
    parse_arguments --suffix -v
    [ "$SUFFIX_MODE" = "on" ]
    [ "$VMAF_ENABLED" = "true" ]
    
    # Test 6: -S avec valeur
    _reset_cli_state
    parse_arguments -S "_mon_suffixe"
    [ "$SUFFIX_MODE" = "custom:_mon_suffixe" ]
    
    # Test 7: -S sans argument
    _reset_cli_state
    parse_arguments -S
    [ "$SUFFIX_MODE" = "on" ]
    
    # Test 8: -S suivi de -d
    _reset_cli_state
    parse_arguments -S -d
    [ "$SUFFIX_MODE" = "on" ]
    [ "$DRYRUN" = "true" ]
}

###########################################################
# TEST CONSOLIDÉ : Options de flags booléens
###########################################################

@test "parse_arguments: flags booléens (-k, -R, -n, -v, -t, -2)" {
    # Test 1: -k active KEEP_INDEX
    _reset_cli_state
    parse_arguments --keep-index
    [ "$KEEP_INDEX" = "true" ]
    
    # Test 2: -R active REGENERATE_INDEX
    _reset_cli_state
    parse_arguments -R
    [ "$REGENERATE_INDEX" = "true" ]
    
    # Test 3: --regenerate-index
    _reset_cli_state
    parse_arguments --regenerate-index
    [ "$REGENERATE_INDEX" = "true" ]
    
    # Test 4: -n active NO_PROGRESS
    _reset_cli_state
    parse_arguments --no-progress
    [ "$NO_PROGRESS" = "true" ]
    
    # Test 5: -v active VMAF_ENABLED
    _reset_cli_state
    parse_arguments --vmaf
    [ "$VMAF_ENABLED" = "true" ]
    
    # Test 6: -t active SAMPLE_MODE
    _reset_cli_state
    parse_arguments --sample
    [ "$SAMPLE_MODE" = "true" ]
    
    # Test 7: -2/--two-pass désactive SINGLE_PASS_MODE
    _reset_cli_state
    parse_arguments --two-pass
    [ "$SINGLE_PASS_MODE" = "false" ]
    
    # Test 8: -2 forme courte
    _reset_cli_state
    parse_arguments -2
    [ "$SINGLE_PASS_MODE" = "false" ]
}

###########################################################
# TEST CONSOLIDÉ : Single-pass et mode film
###########################################################

@test "parse_arguments: single-pass et interactions avec mode" {
    # Test 1: single-pass désactivé automatiquement pour mode film
    _reset_cli_state
    parse_arguments --mode film
    [ "$SINGLE_PASS_MODE" = "true" ]

    # La désactivation se fait dans set_conversion_mode_parameters (appelé après parse_arguments)
    set_conversion_mode_parameters
    [ "$SINGLE_PASS_MODE" = "false" ]
    
    # Test 2: single-pass reste actif pour mode serie
    _reset_cli_state
    parse_arguments --mode serie
    [ "$SINGLE_PASS_MODE" = "true" ]

    set_conversion_mode_parameters
    [ "$SINGLE_PASS_MODE" = "true" ]
    
    # Test 3: dry-run désactive VMAF et sample
    _reset_cli_state
    parse_arguments -d -v -t
    [ "$DRYRUN" = "true" ]
    [ "$VMAF_ENABLED" = "false" ]
    [ "$SAMPLE_MODE" = "false" ]
}

###########################################################
# TEST CONSOLIDÉ : Options avec valeurs (-j, -l, -r, -e, --min-size)
###########################################################

@test "parse_arguments: options avec valeurs (-j, -l, -r, -e, --min-size)" {
    # Test 1: -j configure PARALLEL_JOBS
    _reset_cli_state
    parse_arguments -j 4
    [ "$PARALLEL_JOBS" -eq 4 ]
    
    # Test 2: -r active RANDOM_MODE avec limite par défaut
    _reset_cli_state
    parse_arguments --random
    [ "$RANDOM_MODE" = "true" ]
    [ "$LIMIT_FILES" -eq "$RANDOM_MODE_DEFAULT_LIMIT" ]
    
    # Test 3: -r + -l conserve la limite explicite
    _reset_cli_state
    parse_arguments -r -l 3
    [ "$RANDOM_MODE" = "true" ]
    [ "$LIMIT_FILES" -eq 3 ]
    
    # Test 4: -l ne déclenche pas dry-run
    _reset_cli_state
    parse_arguments -l 5
    [ "$LIMIT_FILES" -eq 5 ]
    [ "$DRYRUN" = "false" ]
    
    # Test 5: -e ajoute des patterns d'exclusion
    _reset_cli_state
    [ "${#EXCLUDES[@]}" -eq 0 ]
    parse_arguments -e "\.part$" --exclude "/Converted/"
    [ "${#EXCLUDES[@]}" -eq 2 ]
    [ "${EXCLUDES[0]}" = "\\.part$" ]
    [ "${EXCLUDES[1]}" = "/Converted/" ]
    [[ -n "$EXCLUDES_REGEX" ]]
    
    # Test 6: --min-size affecte MIN_SIZE_BYTES
    _reset_cli_state
    parse_arguments --min-size 700M
    [ "$MIN_SIZE_BYTES" -eq 734003200 ]
}

###########################################################
# TEST CONSOLIDÉ : Options groupées
###########################################################

@test "parse_arguments: options groupées (-xdrk)" {
    _reset_cli_state
    parse_arguments -xdrk
    [ "$SUFFIX_MODE" = "off" ]
    [ "$DRYRUN" = "true" ]
    [ "$RANDOM_MODE" = "true" ]
    [ "$KEEP_INDEX" = "true" ]
    [ "$LIMIT_FILES" -eq "$RANDOM_MODE_DEFAULT_LIMIT" ]
}

###########################################################
# TEST CONSOLIDÉ : Option -q/--queue
###########################################################

@test "parse_arguments: -q/--queue accepte un fichier existant" {
    _reset_cli_state
    local qfile="$TEST_TEMP_DIR/custom.queue"
    printf '%s\0' "/videos/a.mkv" "/videos/b.mkv" > "$qfile"
    parse_arguments --queue "$qfile"
    [ "$CUSTOM_QUEUE" = "$qfile" ]
}

###########################################################
# TEST CONSOLIDÉ : Options --off-peak / -p
###########################################################

@test "parse_arguments: heures creuses (-p, --off-peak)" {
    # Test 1: -p active OFF_PEAK avec valeurs par défaut
    _reset_cli_state
    parse_arguments -p
    [ "$OFF_PEAK_ENABLED" = "true" ]
    [ "$OFF_PEAK_START" = "22:00" ]
    [ "$OFF_PEAK_END" = "06:00" ]
    
    # Test 2: --off-peak
    _reset_cli_state
    parse_arguments --off-peak
    [ "$OFF_PEAK_ENABLED" = "true" ]
    [ "$OFF_PEAK_START" = "22:00" ]
    [ "$OFF_PEAK_END" = "06:00" ]
    
    # Test 3: --off-peak=23:00-07:00
    _reset_cli_state
    parse_arguments --off-peak=23:00-07:00
    [ "$OFF_PEAK_ENABLED" = "true" ]
    [ "$OFF_PEAK_START" = "23:00" ]
    [ "$OFF_PEAK_END" = "07:00" ]
    
    # Test 4: -p 21:30-05:30
    _reset_cli_state
    parse_arguments -p 21:30-05:30
    [ "$OFF_PEAK_ENABLED" = "true" ]
    [ "$OFF_PEAK_START" = "21:30" ]
    [ "$OFF_PEAK_END" = "05:30" ]
    
    # Test 5: plage diurne
    _reset_cli_state
    parse_arguments --off-peak=08:00-18:00
    [ "$OFF_PEAK_ENABLED" = "true" ]
    [ "$OFF_PEAK_START" = "08:00" ]
    [ "$OFF_PEAK_END" = "18:00" ]
    
    # Test 6: -p combinable avec -d
    _reset_cli_state
    parse_arguments -dp
    [ "$DRYRUN" = "true" ]
    [ "$OFF_PEAK_ENABLED" = "true" ]
}

###########################################################
# TEST CONSOLIDÉ : Option -f/--file
###########################################################

@test "parse_arguments: fichier unique (-f, --file)" {
    # Test 1: -f avec fichier existant
    _reset_cli_state
    local test_file="$TEST_TEMP_DIR/video.mkv"
    touch "$test_file"
    parse_arguments -f "$test_file"
    [ "$SINGLE_FILE" = "$test_file" ]
    
    # Test 2: --file avec fichier existant
    _reset_cli_state
    test_file="$TEST_TEMP_DIR/movie.mp4"
    touch "$test_file"
    parse_arguments --file "$test_file"
    [ "$SINGLE_FILE" = "$test_file" ]
    
    # Test 3: -f combinable avec -m et -t
    _reset_cli_state
    test_file="$TEST_TEMP_DIR/test.mkv"
    touch "$test_file"
    parse_arguments -f "$test_file" -m film -t
    [ "$SINGLE_FILE" = "$test_file" ]
    [ "$CONVERSION_MODE" = "film" ]
    [ "$SAMPLE_MODE" = "true" ]
}

###########################################################
# TESTS EN SOUS-SHELL (erreurs qui font exit)
###########################################################

@test "parse_arguments: erreurs attendues (sous-shell)" {
    # Test 1: --min-size invalide
    run parse_arguments --min-size 10Z
    [ "$status" -ne 0 ]
    [[ "$output" =~ "min-size" ]] || [[ "$output" =~ "Taille" ]]
    
    # Test 2: codec invalide
    run parse_arguments --codec xyz
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalide" ]] || [[ "$output" =~ "Invalid" ]]
    
    # Test 3: -f avec fichier inexistant
    run parse_arguments -f "/chemin/inexistant/video.mkv"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "introuvable" ]]
}

@test "parse_arguments: --help affiche l'aide et sort 0" {
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --help'
    [ "$status" -eq 0 ]
    [[ "$output" =~ Usage ]] 
}

@test "parse_arguments: validations d'options (sous-shell)" {
    # Test 1: --limit invalide
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --limit 0'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "--limit" ]]
    
    # Test 2: --jobs invalide
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --jobs 0'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "--jobs" ]]
    
    # Test 3: --queue inexistant
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --queue "/nonexistent/file.queue"'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "introuvable" ]]
    
    # Test 4: option inconnue
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --definitivement-pas-une-option'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Option" ]]
    
    # Test 5: argument positionnel inattendu
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments -d l 3'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Argument inattendu" ]]

    # Test 6: option nécessitant une valeur (source)
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --source'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "source" ]] || [[ "$output" =~ "valeur" ]]

    # Test 7: option nécessitant une valeur (output-dir)
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/args.sh; parse_arguments --output-dir'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "output" ]] || [[ "$output" =~ "valeur" ]]
}

@test "parse_arguments: off-peak invalide (sous-shell)" {
    # Test 1: heure invalide
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/off_peak.sh; source lib/args.sh; parse_arguments --off-peak=25:00-06:00'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Format invalide" ]]
    
    # Test 2: format incomplet
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; source lib/off_peak.sh; source lib/args.sh; parse_arguments --off-peak=22:00'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Format invalide" ]]
}

@test "config: DRYRUN d'environnement est écrasé à false" {
    run bash -lc 'export DRYRUN=true; cd "$PROJECT_ROOT"; source lib/ui.sh; source lib/config.sh; echo "$DRYRUN"'
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}
