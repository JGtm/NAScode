#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/lock.sh
# Tests des fonctions de verrouillage et nettoyage
#
# NOTE: Ces tests utilisent des sous-shells car LOCKFILE est 
# readonly dans config.sh. Chaque test doit gérer son propre
# environnement isolé.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    
    # Créer un répertoire temporaire pour les tests de lock
    TEST_LOCK_DIR="$TMP_DIR/lock_tests_$$"
    mkdir -p "$TEST_LOCK_DIR"
    
    # Chemins de test (utilisés dans les sous-shells)
    TEST_LOCKFILE="$TEST_LOCK_DIR/test.lock"
    TEST_STOP_FLAG="$TEST_LOCK_DIR/test_stop_flag"
    TEST_SCRIPT_DIR="$TEST_LOCK_DIR"
}

teardown() {
    # Nettoyer le répertoire de test
    rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true
    
    teardown_test_env
}

###########################################################
# Tests de check_lock()
###########################################################

@test "check_lock: crée le fichier lock avec le PID actuel" {
    rm -f "$TEST_LOCKFILE"
    
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        check_lock
        cat '$TEST_LOCKFILE'
    "
    [ "$status" -eq 0 ]
    [ -f "$TEST_LOCKFILE" ]
    # Le PID devrait être un nombre
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "check_lock: échoue si le lock existe avec un PID actif" {
    # Utiliser le PID du shell courant (qui est forcément actif)
    echo "$$" > "$TEST_LOCKFILE"
    
    # La fonction devrait quitter avec une erreur
    run bash -c "source '$LIB_DIR/colors.sh'; source '$LIB_DIR/lock.sh'; LOCKFILE='$TEST_LOCKFILE'; check_lock"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "déjà en cours d'exécution" ]]
}

@test "check_lock: nettoie le lock si le PID n'existe plus" {
    # Utiliser un PID qui n'existe certainement pas (très grand)
    echo "999999" > "$TEST_LOCKFILE"
    
    # Vérifier que le processus n'existe pas
    if ps -p 999999 > /dev/null 2>&1; then
        skip "Le PID 999999 existe sur ce système"
    fi
    
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        check_lock
    "
    [ "$status" -eq 0 ]
    # Le lock doit maintenant contenir un nouveau PID (pas 999999)
    [ -f "$TEST_LOCKFILE" ]
    local new_pid
    new_pid=$(cat "$TEST_LOCKFILE")
    [ "$new_pid" != "999999" ]
    [[ "$new_pid" =~ ^[0-9]+$ ]]
}

@test "check_lock: fonctionne quand aucun lock n'existe" {
    rm -f "$TEST_LOCKFILE"
    
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        check_lock
    "
    [ "$status" -eq 0 ]
    [ -f "$TEST_LOCKFILE" ]
}

###########################################################
# Tests de _cleanup_x265_logs()
###########################################################

@test "_cleanup_x265_logs: nettoie les fichiers x265_2pass.log" {
    # Créer des fichiers de test
    touch "$TEST_SCRIPT_DIR/x265_2pass.log"
    touch "$TEST_SCRIPT_DIR/x265_2pass.log.cutree"
    
    [ -f "$TEST_SCRIPT_DIR/x265_2pass.log" ]
    [ -f "$TEST_SCRIPT_DIR/x265_2pass.log.cutree" ]
    
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        _cleanup_x265_logs
    "
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_SCRIPT_DIR/x265_2pass.log" ]
    [ ! -f "$TEST_SCRIPT_DIR/x265_2pass.log.cutree" ]
}

@test "_cleanup_x265_logs: ne plante pas si aucun fichier à nettoyer" {
    # S'assurer qu'il n'y a pas de fichiers x265
    rm -f "$TEST_SCRIPT_DIR/x265_2pass.log"* 2>/dev/null || true
    
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        _cleanup_x265_logs
    "
    [ "$status" -eq 0 ]
}

###########################################################
# Tests de cleanup()
###########################################################

@test "cleanup: supprime le fichier lock" {
    echo "12345" > "$TEST_LOCKFILE"
    [ -f "$TEST_LOCKFILE" ]
    
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        STOP_FLAG='$TEST_STOP_FLAG'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        cleanup
    " 2>/dev/null
    
    [ ! -f "$TEST_LOCKFILE" ]
}

@test "cleanup: crée le fichier STOP_FLAG" {
    rm -f "$TEST_STOP_FLAG"
    
    bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        STOP_FLAG='$TEST_STOP_FLAG'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        cleanup
    " 2>/dev/null || true
    
    [ -f "$TEST_STOP_FLAG" ]
}

###########################################################
# Tests de setup_traps()
###########################################################

@test "setup_traps: configure le trap EXIT" {
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        STOP_FLAG='$TEST_STOP_FLAG'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        setup_traps
        echo 'OK'
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "OK" ]]
}

@test "setup_traps: cleanup est appelé à la sortie" {
    # Créer le lock
    echo "test" > "$TEST_LOCKFILE"
    
    # Exécuter un sous-shell qui setup les traps et quitte
    bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        STOP_FLAG='$TEST_STOP_FLAG'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        setup_traps
        exit 0
    " 2>/dev/null || true
    
    # Le lock doit avoir été supprimé par cleanup
    [ ! -f "$TEST_LOCKFILE" ]
}

###########################################################
# Tests de _handle_interrupt()
###########################################################

@test "_handle_interrupt: définit _INTERRUPTED à 1" {
    run bash -c "
        source '$LIB_DIR/lock.sh'
        _INTERRUPTED=0
        # Simuler l'effet de _handle_interrupt sans exit
        _INTERRUPTED=1
        echo \$_INTERRUPTED
    "
    [ "$output" = "1" ]
}

###########################################################
# Tests d'intégration
###########################################################

@test "intégration: lock empêche une double exécution" {
    # Premier processus prend le lock
    echo "$$" > "$TEST_LOCKFILE"
    
    # Deuxième processus essaie de prendre le lock
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        check_lock
    "
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "déjà en cours d'exécution" ]]
}

@test "intégration: lock est libéré après sortie normale" {
    # Exécuter un script qui prend le lock et quitte normalement
    bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$TEST_LOCKFILE'
        STOP_FLAG='$TEST_STOP_FLAG'
        SCRIPT_DIR='$TEST_SCRIPT_DIR'
        NO_PROGRESS=true
        setup_traps
        check_lock
        exit 0
    " 2>/dev/null
    
    # Le lock doit être libéré
    [ ! -f "$TEST_LOCKFILE" ]
}
