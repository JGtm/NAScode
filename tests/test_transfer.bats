#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/transfer.sh
# Tests du système de transferts asynchrones
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    
    export SCRIPT_DIR="$PROJECT_ROOT"
    export EXECUTION_TIMESTAMP="test_$$"
    export NO_PROGRESS=true
    
    # Charger les modules requis
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/transfer.sh"
}

teardown() {
    # Nettoyer les processus de test
    if [[ -n "${TRANSFER_PIDS_FILE:-}" ]] && [[ -f "$TRANSFER_PIDS_FILE" ]]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$TRANSFER_PIDS_FILE"
        rm -f "$TRANSFER_PIDS_FILE"
    fi
    teardown_test_env
}

###########################################################
# Tests de init_async_transfers()
###########################################################

@test "init_async_transfers: crée le fichier de PIDs" {
    init_async_transfers
    
    [ -n "$TRANSFER_PIDS_FILE" ]
    [ -f "$TRANSFER_PIDS_FILE" ]
}

@test "init_async_transfers: fichier de PIDs initialement vide" {
    init_async_transfers
    
    local size
    size=$(wc -c < "$TRANSFER_PIDS_FILE")
    [ "$size" -eq 0 ]
}

###########################################################
# Tests de _add_transfer_pid()
###########################################################

@test "_add_transfer_pid: ajoute un PID au fichier" {
    init_async_transfers
    
    _add_transfer_pid "12345"
    
    grep -q "12345" "$TRANSFER_PIDS_FILE"
}

@test "_add_transfer_pid: ajoute plusieurs PIDs" {
    init_async_transfers
    
    _add_transfer_pid "111"
    _add_transfer_pid "222"
    _add_transfer_pid "333"
    
    local count
    count=$(wc -l < "$TRANSFER_PIDS_FILE")
    [ "$count" -eq 3 ]
}

###########################################################
# Tests de _cleanup_finished_transfers()
###########################################################

@test "_cleanup_finished_transfers: supprime les PIDs terminés" {
    init_async_transfers
    
    # Ajouter un PID qui n'existe pas (processus terminé)
    _add_transfer_pid "999999"
    
    _cleanup_finished_transfers
    
    # Le PID doit avoir été supprimé
    local count
    count=$(grep -c '[0-9]' "$TRANSFER_PIDS_FILE" 2>/dev/null) || count=0
    [ "$count" -eq 0 ]
}

@test "_cleanup_finished_transfers: garde les PIDs actifs" {
    init_async_transfers
    
    # Lancer un processus en arrière-plan
    sleep 10 &
    local bg_pid=$!
    
    _add_transfer_pid "$bg_pid"
    _cleanup_finished_transfers
    
    # Le PID doit toujours être présent
    grep -q "$bg_pid" "$TRANSFER_PIDS_FILE"
    
    # Nettoyer
    kill "$bg_pid" 2>/dev/null || true
}

###########################################################
# Tests de _count_active_transfers()
###########################################################

@test "_count_active_transfers: retourne 0 sans transferts" {
    init_async_transfers
    
    local count
    count=$(_count_active_transfers)
    
    [ "$count" -eq 0 ]
}

@test "_count_active_transfers: compte correctement les transferts actifs" {
    init_async_transfers
    
    # Lancer 2 processus en arrière-plan
    sleep 10 &
    local pid1=$!
    sleep 10 &
    local pid2=$!
    
    _add_transfer_pid "$pid1"
    _add_transfer_pid "$pid2"
    
    local count
    count=$(_count_active_transfers)
    
    [ "$count" -eq 2 ]
    
    # Nettoyer
    kill "$pid1" "$pid2" 2>/dev/null || true
}

@test "_count_active_transfers: exclut les transferts terminés" {
    init_async_transfers
    
    # Lancer un processus qui se termine vite
    sleep 0.1 &
    local pid1=$!
    # Lancer un processus long
    sleep 10 &
    local pid2=$!
    
    _add_transfer_pid "$pid1"
    _add_transfer_pid "$pid2"
    
    # Attendre que le premier se termine
    sleep 0.3
    
    local count
    count=$(_count_active_transfers)
    
    [ "$count" -eq 1 ]
    
    # Nettoyer
    kill "$pid2" 2>/dev/null || true
}

###########################################################
# Tests de wait_for_transfer_slot()
###########################################################

@test "wait_for_transfer_slot: retourne immédiatement si slots disponibles" {
    init_async_transfers
    
    # Pas de transfert en cours
    run wait_for_transfer_slot
    [ "$status" -eq 0 ]
}

@test "wait_for_transfer_slot: attend si max atteint" {
    init_async_transfers
    
    # Simuler MAX_CONCURRENT_TRANSFERS processus actifs
    local pids=()
    for i in $(seq 1 $MAX_CONCURRENT_TRANSFERS); do
        sleep 10 &
        pids+=($!)
        _add_transfer_pid "${pids[-1]}"
    done
    
    # Vérifier que le count est au max
    local count
    count=$(_count_active_transfers)
    [ "$count" -eq "$MAX_CONCURRENT_TRANSFERS" ]
    
    # Terminer un processus
    kill "${pids[0]}" 2>/dev/null || true
    wait "${pids[0]}" 2>/dev/null || true
    
    # Maintenant wait_for_transfer_slot doit retourner
    run wait_for_transfer_slot
    [ "$status" -eq 0 ]
    
    # Nettoyer les autres
    for pid in "${pids[@]:1}"; do
        kill "$pid" 2>/dev/null || true
    done
}

###########################################################
# Tests de wait_all_transfers()
###########################################################

@test "wait_all_transfers: retourne immédiatement sans transferts" {
    init_async_transfers
    
    run wait_all_transfers
    [ "$status" -eq 0 ]
}

@test "wait_all_transfers: attend tous les transferts actifs" {
    init_async_transfers
    
    # Lancer des processus courts
    sleep 0.2 &
    local pid1=$!
    sleep 0.2 &
    local pid2=$!
    
    _add_transfer_pid "$pid1"
    _add_transfer_pid "$pid2"
    
    # wait_all_transfers doit attendre
    wait_all_transfers
    
    # Les deux processus doivent être terminés
    ! kill -0 "$pid1" 2>/dev/null
    ! kill -0 "$pid2" 2>/dev/null
}

###########################################################
# Tests de cleanup_transfers()
###########################################################

@test "cleanup_transfers: supprime le fichier de PIDs" {
    init_async_transfers
    
    local pids_file="$TRANSFER_PIDS_FILE"
    [ -f "$pids_file" ]
    
    cleanup_transfers
    
    [ ! -f "$pids_file" ]
}

###########################################################
# Tests d'intégration
###########################################################

@test "transfer: workflow complet init → add → count → cleanup" {
    # Init
    init_async_transfers
    [ -f "$TRANSFER_PIDS_FILE" ]
    
    # Ajouter des processus
    sleep 10 &
    local pid1=$!
    _add_transfer_pid "$pid1"
    
    # Compter
    local count
    count=$(_count_active_transfers)
    [ "$count" -eq 1 ]
    
    # Terminer le processus
    kill "$pid1" 2>/dev/null || true
    wait "$pid1" 2>/dev/null || true
    
    # Cleanup
    cleanup_transfers
    [ ! -f "$TRANSFER_PIDS_FILE" ]
}
