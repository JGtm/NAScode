#!/usr/bin/env bats
###########################################################
# RÉGRESSIONS - stdin de ffmpeg et nettoyage après Ctrl+C
#
# Cas réel (saison complète, mode -s) : convert_file héritait de la queue
# (`done < "$QUEUE"`) comme stdin. ffmpeg lisait les chemins comme des touches ;
# un « c » ouvrait son invite « Enter command: » et son fil principal bouclait :
# progression figée, ffmpeg qui ne se termine jamais, insensible à SIGTERM,
# donc orphelin à 100 % CPU après Ctrl+C. Les .in/.out (plusieurs Go) restaient
# dans TMP_DIR.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    export SCRIPT_DIR="$PROJECT_ROOT"
    export EXECUTION_TIMESTAMP="test_$$"
    export NO_PROGRESS=true
    export PARALLEL_JOBS=1
    export LIMIT_FILES=0
    export QUEUE="$TEST_TEMP_DIR/Queue"
    export OUTPUT_DIR="$TEST_TEMP_DIR/out"
    mkdir -p "$OUTPUT_DIR"
}

teardown() {
    [[ -n "${FAKE_PID:-}" ]] && kill -9 "$FAKE_PID" 2>/dev/null || true
    teardown_test_env
}

###########################################################
# 1. convert_file ne doit pas hériter de la queue comme stdin
###########################################################

@test "régression: convert_file ne lit pas la queue sur stdin (mode simple)" {
    # Des noms contenant des « c » et des « h », comme les vrais épisodes
    printf '%s\0' "/s/Série - 1x01 - caméra.mkv" "/s/Série - 1x02 - continue.mkv" \
        "/s/Série - 1x03 - accident.mkv" > "$QUEUE"

    run bash -c '
        source "$1/lib/ui.sh"; source "$1/lib/config.sh"; source "$1/lib/utils.sh"
        source "$1/lib/processing.sh"
        DONE="$2/done"; LEAK="$2/leak"
        check_off_peak_before_processing() { return 0; }
        notify_event() { :; }
        # Simule ffmpeg : lit stdin comme le clavier
        convert_file() {
            local k
            if IFS= read -r -n 1 -t 1 k; then echo "lu:[$k]" >> "$LEAK"; fi
            echo "$1" >> "$DONE"
        }
        _process_queue_simple
        echo "done=$(wc -l < "$DONE" | tr -d " ")"
        [[ -f "$LEAK" ]] && cat "$LEAK"
        exit 0
    ' _ "$PROJECT_ROOT" "$TEST_TEMP_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"done=3"* ]]
    [[ "$output" != *"lu:"* ]]
}

@test "contrat: chaque convert_file lancé en arrière-plan a stdin sur /dev/null" {
    local bad
    bad=$(grep -nE 'convert_file .*&[[:space:]]*$' "$PROJECT_ROOT/lib/processing.sh" | grep -v '< /dev/null' || true)
    [ -z "$bad" ]
    [ "$(grep -cE 'convert_file .*< /dev/null &' "$PROJECT_ROOT/lib/processing.sh")" -ge 2 ]
}

@test "contrat: tous les appels ffmpeg de lib/ passent -nostdin" {
    # detect.sh n'interroge que les capacités (-filters, -version) au démarrage.
    local bad
    bad=$(grep -rnE '(^|[[:space:](])ffmpeg -' "$PROJECT_ROOT/lib" \
        | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' \
        | grep -v 'lib/detect.sh' \
        | grep -v -- '-nostdin' || true)
    if [[ -n "$bad" ]]; then echo "$bad"; fi
    [ -z "$bad" ]
}

###########################################################
# 2. Arrêt forcé des encodeurs qui ignorent SIGTERM
###########################################################

@test "cleanup: un encodeur descendant qui ignore SIGTERM est tué (SIGKILL après grâce)" {
    # Faux encodeur au nom unique qui ignore SIGTERM. Lien symbolique vers sleep :
    # macOS tue une copie de /bin/sleep (signature invalide) et nomme un script
    # « /bin/bash » ; le lien garde son propre nom dans `ps -o comm`.
    local fake="$TEST_TEMP_DIR/nasfakeenc"
    ln -s "$(command -v sleep)" "$fake"
    bash -c 'trap "" TERM; exec "$1" 30' _ "$fake" &
    FAKE_PID=$!
    sleep 0.3
    kill -0 "$FAKE_PID"

    source "$LIB_DIR/lock.sh"
    _CLEANUP_KILL_NAMES="nasfakeenc"
    local -a found=()
    mapfile -t found < <(_cleanup_descendant_encoders "$$")
    [ "${#found[@]}" -eq 1 ]
    [ "${found[0]}" = "$FAKE_PID" ]

    _cleanup_kill_survivors 2 "${found[@]}"
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$FAKE_PID" 2>/dev/null || break; sleep 0.1; done
    ! kill -0 "$FAKE_PID" 2>/dev/null
}

@test "cleanup: un encodeur qui n'est pas un descendant n'est jamais visé" {
    local fake="$TEST_TEMP_DIR/nasfakeenc"
    ln -s "$(command -v sleep)" "$fake"
    # Double fork : le faux encodeur est rattaché à PID 1, hors de notre arbre
    ( "$fake" 30 & echo $! > "$TEST_TEMP_DIR/pid" )
    FAKE_PID=$(cat "$TEST_TEMP_DIR/pid")
    sleep 0.3
    kill -0 "$FAKE_PID"

    source "$LIB_DIR/lock.sh"
    _CLEANUP_KILL_NAMES="nasfakeenc"
    run _cleanup_descendant_encoders "$$"
    [ -z "$output" ]
}

@test "cleanup: sans encodeur, _cleanup_kill_survivors rend la main tout de suite" {
    source "$LIB_DIR/lock.sh"
    local t0=$SECONDS
    _cleanup_kill_survivors 10
    [ $(( SECONDS - t0 )) -lt 1 ]
}

###########################################################
# 3. Temporaires d'une conversion interrompue
###########################################################

@test "temporaires: _get_temp_filename et _get_temp_workdir enregistrent leurs chemins" {
    run bash -c '
        export TMP_DIR="$2" EXECUTION_TIMESTAMP=reg
        source "$1/lib/ui.sh"; source "$1/lib/utils.sh"; source "$1/lib/conversion_prep.sh"
        a=$(_get_temp_filename "/s/ep.mkv" ".in")
        b=$(_get_temp_workdir "/s/ep.mkv")
        reg=$(_tmp_registry_path)
        grep -qxF "$a" "$reg" && grep -qxF "$b" "$reg" && echo OK
    ' _ "$PROJECT_ROOT" "$TMP_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "temporaires: après interruption, les fichiers du run sont supprimés (et rien hors TMP_DIR)" {
    local outside="$TEST_TEMP_DIR/hors_tmp.mkv"
    echo keep > "$outside"
    run bash -c '
        export TMP_DIR="$2" EXECUTION_TIMESTAMP=intr
        source "$1/lib/ui.sh"; source "$1/lib/utils.sh"; source "$1/lib/conversion_prep.sh"
        source "$1/lib/lock.sh"
        in=$(_get_temp_filename "/s/ep.mkv" ".in"); echo x > "$in"
        log=$(_get_temp_filename "/s/ep.mkv" "_err.log"); echo x > "$log"; echo x > "$log.pass1"
        wd=$(_get_temp_workdir "/s/ep.mkv"); mkdir -p "$wd"; echo x > "$wd/seg"
        _register_temp_path "$3"
        _cleanup_run_temp_files
        ls -A "$TMP_DIR"
    ' _ "$PROJECT_ROOT" "$TMP_DIR" "$outside"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -f "$outside" ]
}

@test "temporaires: en fin normale, seuls les dossiers de travail vides sont retirés" {
    run bash -c '
        export TMP_DIR="$2" EXECUTION_TIMESTAMP=norm
        source "$1/lib/ui.sh"; source "$1/lib/utils.sh"; source "$1/lib/conversion_prep.sh"
        source "$1/lib/lock.sh"
        out=$(_get_temp_filename "/s/ep.mkv" ".out.mkv"); echo x > "$out"
        wd=$(_get_temp_workdir "/s/ep.mkv"); mkdir -p "$wd"
        _cleanup_run_empty_workdirs
        ls -A "$TMP_DIR"
    ' _ "$PROJECT_ROOT" "$TMP_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == tmp_*".out.mkv" ]]
}
