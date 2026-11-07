#!/usr/bin/env bats
###########################################################
# RÉGRESSIONS - portabilité macOS et grosses bibliothèques
#
# Cas ratés en conditions réelles (NAS Synology monté en SMB sur macOS) :
#   1. `-l N` sur une grosse queue : `printf | head` recevait SIGPIPE et
#      pipefail + errexit tuaient le script sans message (exit 141).
#   2. find BSD sans -printf : repli `stat` par fichier, deux explorations
#      de la source (comptage + indexation), donc très lent sur un partage.
#   3. `stat -c` (GNU) sur l'index existant : fatal avec le stat BSD.
#
# Chaque scénario tourne dans un bash séparé en `set -euo pipefail`,
# comme le point d'entrée nascode, pour reproduire les arrêts silencieux.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    WORK="$TEST_TEMP_DIR/work"
    mkdir -p "$WORK/src/Show S01" "$WORK/logs"
    printf 'a' > "$WORK/src/Show S01/ep1.mkv"
    printf 'bbb' > "$WORK/src/Show S01/ep2.mkv"
    printf 'ccccc' > "$WORK/src/movie.mp4"
    echo "notes" > "$WORK/src/notes.txt"
}

teardown() {
    teardown_test_env
}

# Lance un scénario dans un bash strict avec les modules de queue chargés.
# Usage: run_strict '<code bash>'
run_strict() {
    run bash -c '
        set -euo pipefail
        export SCRIPT_DIR="$1" NASCODE_TMP_DIR="$2/tmp"
        source "$1/lib/ui.sh"; source "$1/lib/ui_options.sh"; source "$1/lib/config.sh"
        source "$1/lib/utils.sh"; source "$1/lib/index.sh"; source "$1/lib/counters.sh"
        source "$1/lib/queue.sh"
        mkdir -p "$TMP_DIR"
        SOURCE="$2/src"; OUTPUT_DIR="$2/out"; LOG_DIR="$2/logs"
        INDEX="$LOG_DIR/Index"; INDEX_READABLE="$LOG_DIR/Index_readable.txt"
        INDEX_META="$LOG_DIR/Index.meta"; QUEUE="$LOG_DIR/Queue"
        EXCLUDES=(); EXCLUDES_REGEX=""; NO_PROGRESS=true; MIN_SIZE_BYTES=0
        LIMIT_FILES=0; RANDOM_MODE=false; KEEP_INDEX=false
        eval "$3"
    ' _ "$PROJECT_ROOT" "$WORK" "$1"
}

# Queue d'environ 1 Mo (bien au-delà du tampon d'un tube, 16 à 64 Ko).
make_big_queue() {
    seq 1 15000 | awk '{printf "/Volumes/Séries/Une Série/Une Série - 1x%05d - Un titre d épisode assez long.mkv\n", $1}' \
        | tr '\n' '\0' > "$WORK/logs/Queue"
}

###########################################################
# 1. Limitation -l sur une grosse queue (SIGPIPE)
###########################################################

@test "régression: -l 1 sur une grosse queue ne tue pas le script (SIGPIPE)" {
    make_big_queue
    run_strict '
        LIMIT_FILES=1
        _apply_queue_limitations
        echo "survived"
        tr "\0" "\n" < "$QUEUE"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "survived" ]
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[1]}" == *"1x00001"* ]]
}

@test "régression: -r -l 3 sur une grosse queue ne tue pas le script (SIGPIPE)" {
    make_big_queue
    run_strict '
        LIMIT_FILES=3; RANDOM_MODE=true
        _apply_queue_limitations
        echo "survived"
        tr "\0" "\n" < "$QUEUE" | wc -l | tr -d " "
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "survived" ]
    [ "${lines[1]}" -eq 3 ]
}

@test "régression: la limitation ne laisse pas de fichier temporaire" {
    make_big_queue
    run_strict 'LIMIT_FILES=2; _apply_queue_limitations; ls -A "$LOG_DIR"'
    [ "$status" -eq 0 ]
    [ "$output" = "Queue" ]
}

###########################################################
# 2. find sans -printf (macOS) et exploration unique
###########################################################

# Crée de faux binaires find/gfind dans un dossier placé en tête du PATH.
#   $1 : `find -printf` accepté           (ok|ko)
#   $2 : `gfind -printf` accepté          (ok|ko)
# Un gfind "ko" masque aussi un éventuel vrai gfind installé sur la machine.
make_fake_finds() {
    local fake="$WORK/fakebin" name mode
    local ok='#!/bin/sh\nexit 0\n'
    local ko='#!/bin/sh\nfor a in "$@"; do [ "$a" = "-printf" ] && exit 1; done\nexit 0\n'
    mkdir -p "$fake"
    for name in find gfind; do
        if [[ "$name" == find ]]; then mode="$1"; else mode="$2"; fi
        if [[ "$mode" == ko ]]; then printf "$ko" > "$fake/$name"; else printf "$ok" > "$fake/$name"; fi
        chmod +x "$fake/$name"
    done
    echo "$fake"
}

@test "find: le find natif est gardé s'il connaît -printf (Linux, Git Bash)" {
    local fake; fake=$(make_fake_finds ok ok)
    run_strict "PATH=\"$fake:\$PATH\"; _detect_find_printf; echo \"\$_NASCODE_FIND_BIN \$_NASCODE_FIND_PRINTF\""
    [ "$status" -eq 0 ]
    [ "$output" = "find 1" ]
}

@test "find: gfind est retenu quand find ne connaît pas -printf (macOS)" {
    local fake; fake=$(make_fake_finds ko ok)
    run_strict "PATH=\"$fake:\$PATH\"; _detect_find_printf; echo \"\$_NASCODE_FIND_BIN \$_NASCODE_FIND_PRINTF\""
    [ "$status" -eq 0 ]
    [ "$output" = "gfind 1" ]
}

@test "find: repli stat quand aucun find ne connaît -printf (macOS sans findutils)" {
    local fake; fake=$(make_fake_finds ko ko)
    run_strict "PATH=\"$fake:\$PATH\"; _detect_find_printf; echo \"\$_NASCODE_FIND_BIN \$_NASCODE_FIND_PRINTF\""
    [ "$status" -eq 0 ]
    [ "$output" = "find 0" ]
}

@test "index: le repli stat donne les mêmes tailles que find -printf" {
    run_strict '
        _NASCODE_FIND_PRINTF=0 _NASCODE_FIND_BIN=find
        _generate_index
        sort -k2 "$INDEX"
    '
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ "${lines[0]}" == 1$'\t'*"/Show S01/ep1.mkv" ]]
    [[ "${lines[1]}" == 3$'\t'*"/Show S01/ep2.mkv" ]]
    [[ "${lines[2]}" == 5$'\t'*"/movie.mp4" ]]
}

@test "index: la source n'est explorée qu'une seule fois" {
    run_strict '
        eval "$(declare -f _list_video_candidates | sed "1s/_list_video_candidates/_orig_list_video_candidates/")"
        _list_video_candidates() { echo x >> "$LOG_DIR/.calls"; _orig_list_video_candidates "$@"; }
        _generate_index
        echo "calls=$(wc -l < "$LOG_DIR/.calls" | tr -d " ") indexed=$(wc -l < "$INDEX" | tr -d " ")"
        ls -A "$TMP_DIR"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "calls=1 indexed=3" ]
    # Le fichier temporaire des candidates est supprimé
    [ "${#lines[@]}" -eq 1 ]
}

###########################################################
# 3. Index existant avec un stat BSD (sans GNU coreutils)
###########################################################

@test "régression: -k avec un stat BSD ne tue pas le script" {
    run_strict '
        _generate_index
        # Simule le stat de macOS : pas de -c, format via -f/-t
        stat() { [[ "$1" == "-c" ]] && return 1; echo "2026-11-07 12:12:09"; }
        KEEP_INDEX=true
        _handle_existing_index
        echo "kept rc=$?"
    '
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "kept rc=0" ]
}
