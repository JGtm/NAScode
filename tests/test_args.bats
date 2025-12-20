#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/args.sh
# Vérifie le parsing des options CLI et l'absence d'effets de bord
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_minimal
    source "$LIB_DIR/args.sh"
}

teardown() {
    teardown_test_env
}

_reset_cli_state() {
    DRYRUN=false
    RANDOM_MODE=false
    LIMIT_FILES=0
    FORCE_NO_SUFFIX=false
    KEEP_INDEX=false
    VMAF_ENABLED=false
    SAMPLE_MODE=false
    NO_PROGRESS=false
    PARALLEL_JOBS=1
    CONVERSION_MODE="serie"
    SOURCE="/source"
    OUTPUT_DIR="/output"
    CUSTOM_QUEUE=""
    EXCLUDES=()
}

@test "parse_arguments: dry-run reste false si option absente" {
    _reset_cli_state

    parse_arguments -s "/videos" -o "/out" -m "serie"

    [ "$DRYRUN" = "false" ]
    [ "$SOURCE" = "/videos" ]
    [ "$OUTPUT_DIR" = "/out" ]
    [ "$CONVERSION_MODE" = "serie" ]
}

@test "parse_arguments: -e/--exclude ajoute un pattern" {
    _reset_cli_state

    [ "${#EXCLUDES[@]}" -eq 0 ]
    parse_arguments -e "\.part$" --exclude "/Converted/"

    [ "${#EXCLUDES[@]}" -eq 2 ]
    [ "${EXCLUDES[0]}" = "\\.part$" ]
    [ "${EXCLUDES[1]}" = "/Converted/" ]
}

@test "parse_arguments: -m/--mode affecte CONVERSION_MODE" {
    _reset_cli_state

    parse_arguments --mode film
    [ "$CONVERSION_MODE" = "film" ]
}

@test "parse_arguments: active dry-run via -d" {
    _reset_cli_state

    parse_arguments -d -s "/videos"

    [ "$DRYRUN" = "true" ]
    [ "$SOURCE" = "/videos" ]
}

@test "parse_arguments: active dry-run via --dryrun" {
    _reset_cli_state

    parse_arguments --dryrun

    [ "$DRYRUN" = "true" ]
}

@test "parse_arguments: options groupées passent correctement (-xdrk)" {
    _reset_cli_state

    parse_arguments -xdrk

    [ "$FORCE_NO_SUFFIX" = "true" ]
    [ "$DRYRUN" = "true" ]
    [ "$RANDOM_MODE" = "true" ]
    [ "$KEEP_INDEX" = "true" ]
    [ "$LIMIT_FILES" -eq "$RANDOM_MODE_DEFAULT_LIMIT" ]
}

@test "parse_arguments: -x active FORCE_NO_SUFFIX" {
    _reset_cli_state

    parse_arguments -x

    [ "$FORCE_NO_SUFFIX" = "true" ]
    [ "$DRYRUN" = "false" ]
}

@test "parse_arguments: -k active KEEP_INDEX" {
    _reset_cli_state

    parse_arguments --keep-index

    [ "$KEEP_INDEX" = "true" ]
}

@test "parse_arguments: -n active NO_PROGRESS" {
    _reset_cli_state

    parse_arguments --no-progress

    [ "$NO_PROGRESS" = "true" ]
}

@test "parse_arguments: -v active VMAF_ENABLED" {
    _reset_cli_state

    parse_arguments --vmaf

    [ "$VMAF_ENABLED" = "true" ]
}

@test "parse_arguments: -t active SAMPLE_MODE" {
    _reset_cli_state

    parse_arguments --sample

    [ "$SAMPLE_MODE" = "true" ]
}

@test "parse_arguments: dry-run désactive VMAF et sample" {
    _reset_cli_state

    parse_arguments -d -v -t

    [ "$DRYRUN" = "true" ]
    [ "$VMAF_ENABLED" = "false" ]
    [ "$SAMPLE_MODE" = "false" ]
}

@test "parse_arguments: -j/--jobs configure PARALLEL_JOBS" {
    _reset_cli_state

    parse_arguments -j 4

    [ "$PARALLEL_JOBS" -eq 4 ]
}

@test "parse_arguments: -r active RANDOM_MODE et limite par défaut" {
    _reset_cli_state

    parse_arguments --random

    [ "$RANDOM_MODE" = "true" ]
    [ "$LIMIT_FILES" -eq "$RANDOM_MODE_DEFAULT_LIMIT" ]
}

@test "parse_arguments: -r + -l conserve la limite explicite" {
    _reset_cli_state

    parse_arguments -r -l 3

    [ "$RANDOM_MODE" = "true" ]
    [ "$LIMIT_FILES" -eq 3 ]
}

@test "parse_arguments: -l ne déclenche pas dry-run" {
    _reset_cli_state

    parse_arguments -l 5

    [ "$LIMIT_FILES" -eq 5 ]
    [ "$DRYRUN" = "false" ]
}

@test "parse_arguments: -q/--queue accepte un fichier existant" {
    _reset_cli_state

    local qfile="$TEST_TEMP_DIR/custom.queue"
    printf '%s\0' "/videos/a.mkv" "/videos/b.mkv" > "$qfile"

    parse_arguments --queue "$qfile"
    [ "$CUSTOM_QUEUE" = "$qfile" ]
}

@test "parse_arguments: --help affiche l'aide et sort 0 (sous-shell)" {
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/colors.sh; source lib/config.sh; source lib/args.sh; parse_arguments --help'
    [ "$status" -eq 0 ]
    [[ "$output" =~ Usage ]] 
}

@test "parse_arguments: --limit invalide échoue (sous-shell)" {
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/colors.sh; source lib/config.sh; source lib/args.sh; parse_arguments --limit 0'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "--limit" ]]
}

@test "parse_arguments: --jobs invalide échoue (sous-shell)" {
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/colors.sh; source lib/config.sh; source lib/args.sh; parse_arguments --jobs 0'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "--jobs" ]]
}

@test "parse_arguments: --queue inexistant échoue (sous-shell)" {
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/colors.sh; source lib/config.sh; source lib/args.sh; parse_arguments --queue "/nonexistent/file.queue"'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "introuvable" ]]
}

@test "parse_arguments: option inconnue échoue (sous-shell)" {
    run bash -lc 'set -euo pipefail; cd "$PROJECT_ROOT"; source lib/colors.sh; source lib/config.sh; source lib/args.sh; parse_arguments --definitivement-pas-une-option'
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Option" ]]
}

@test "config: DRYRUN d'environnement est écrasé à false" {
    run bash -lc 'export DRYRUN=true; cd "$PROJECT_ROOT"; source lib/colors.sh; source lib/config.sh; echo "$DRYRUN"'
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}
