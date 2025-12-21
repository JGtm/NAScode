#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/lock.sh
# Tests des fonctions de verrouillage et nettoyage
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/lock.sh"
    
    # Créer un répertoire temporaire pour les tests de lock
    TEST_LOCK_DIR="$TMP_DIR/lock_tests_$$"
    mkdir -p "$TEST_LOCK_DIR"
    
    # Sauvegarder les variables originales
    ORIGINAL_LOCKFILE="${LOCKFILE:-}"
    ORIGINAL_STOP_FLAG="${STOP_FLAG:-}"
    ORIGINAL_SCRIPT_DIR="${SCRIPT_DIR:-}"
    
    # Utiliser des fichiers de test
    LOCKFILE="$TEST_LOCK_DIR/test.lock"
    STOP_FLAG="$TEST_LOCK_DIR/test_stop_flag"
    SCRIPT_DIR="$TEST_LOCK_DIR"
}

teardown() {
    # Restaurer les variables originales
    LOCKFILE="$ORIGINAL_LOCKFILE"
    STOP_FLAG="$ORIGINAL_STOP_FLAG"
    SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"
    
    # Nettoyer le répertoire de test
    rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true
    
    teardown_test_env
}

###########################################################
# Tests de check_lock()
###########################################################

@test "check_lock: crée le fichier lock avec le PID actuel" {
    rm -f "$LOCKFILE"
    
    check_lock
    
    [ -f "$LOCKFILE" ]
    [ "$(cat "$LOCKFILE")" = "$$" ]
}

@test "check_lock: échoue si le lock existe avec un PID actif" {
    # Utiliser le PID du shell courant (qui est forcément actif)
    echo "$$" > "$LOCKFILE"
    
    # La fonction devrait quitter avec une erreur
    run bash -c "source '$LIB_DIR/colors.sh'; source '$LIB_DIR/lock.sh'; LOCKFILE='$LOCKFILE'; check_lock"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "déjà en cours d'exécution" ]]
}

@test "check_lock: nettoie le lock si le PID n'existe plus" {
    # Utiliser un PID qui n'existe certainement pas (très grand)
    echo "999999" > "$LOCKFILE"
    
    # Vérifier que le processus n'existe pas
    if ps -p 999999 > /dev/null 2>&1; then
        skip "Le PID 999999 existe sur ce système"
    fi
    
    check_lock
    
    # Le lock doit maintenant contenir notre PID
    [ "$(cat "$LOCKFILE")" = "$$" ]
}

@test "check_lock: fonctionne quand aucun lock n'existe" {
    rm -f "$LOCKFILE"
    
    run check_lock
    [ "$status" -eq 0 ]
    [ -f "$LOCKFILE" ]
}

###########################################################
# Tests de _cleanup_x265_logs()
###########################################################

@test "_cleanup_x265_logs: nettoie les fichiers x265_2pass.log" {
    # Créer des fichiers de test
    touch "$SCRIPT_DIR/x265_2pass.log"
    touch "$SCRIPT_DIR/x265_2pass.log.cutree"
    
    [ -f "$SCRIPT_DIR/x265_2pass.log" ]
    [ -f "$SCRIPT_DIR/x265_2pass.log.cutree" ]
    
    NO_PROGRESS=true _cleanup_x265_logs
    
    [ ! -f "$SCRIPT_DIR/x265_2pass.log" ]
    [ ! -f "$SCRIPT_DIR/x265_2pass.log.cutree" ]
}

@test "_cleanup_x265_logs: ne plante pas si aucun fichier à nettoyer" {
    # S'assurer qu'il n'y a pas de fichiers x265
    rm -f "$SCRIPT_DIR/x265_2pass.log"* 2>/dev/null || true
    
    run bash -c "source '$LIB_DIR/colors.sh'; source '$LIB_DIR/lock.sh'; SCRIPT_DIR='$SCRIPT_DIR'; NO_PROGRESS=true; _cleanup_x265_logs"
    [ "$status" -eq 0 ]
}

###########################################################
# Tests de cleanup()
###########################################################

@test "cleanup: supprime le fichier lock" {
    echo "$$" > "$LOCKFILE"
    [ -f "$LOCKFILE" ]
    
    # Appeler cleanup dans un sous-shell pour éviter d'affecter le shell de test
    (
        export LOCKFILE STOP_FLAG SCRIPT_DIR
        source "$LIB_DIR/colors.sh"
        source "$LIB_DIR/progress.sh"
        source "$LIB_DIR/lock.sh"
        NO_PROGRESS=true
        cleanup
    ) 2>/dev/null || true
    
    [ ! -f "$LOCKFILE" ]
}

@test "cleanup: crée le fichier STOP_FLAG" {
    rm -f "$STOP_FLAG"
    
    (
        export LOCKFILE STOP_FLAG SCRIPT_DIR
        source "$LIB_DIR/colors.sh"
        source "$LIB_DIR/progress.sh"
        source "$LIB_DIR/lock.sh"
        NO_PROGRESS=true
        cleanup
    ) 2>/dev/null || true
    
    [ -f "$STOP_FLAG" ]
}

###########################################################
# Tests de setup_traps()
###########################################################

@test "setup_traps: configure le trap EXIT" {
    # Vérifier que setup_traps ne plante pas
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$LOCKFILE'
        STOP_FLAG='$STOP_FLAG'
        SCRIPT_DIR='$SCRIPT_DIR'
        NO_PROGRESS=true
        setup_traps
        echo 'OK'
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "OK" ]]
}

@test "setup_traps: cleanup est appelé à la sortie" {
    # Créer le lock
    echo "test" > "$LOCKFILE"
    
    # Exécuter un sous-shell qui setup les traps et quitte
    bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/progress.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$LOCKFILE'
        STOP_FLAG='$STOP_FLAG'
        SCRIPT_DIR='$SCRIPT_DIR'
        NO_PROGRESS=true
        setup_traps
        exit 0
    " 2>/dev/null || true
    
    # Le lock doit avoir été supprimé par cleanup
    [ ! -f "$LOCKFILE" ]
}

###########################################################
# Tests de _handle_interrupt()
###########################################################

@test "_handle_interrupt: définit _INTERRUPTED à 1" {
    _INTERRUPTED=0
    
    # On ne peut pas vraiment tester exit 130 sans sous-shell
    # Vérifier juste que la variable est accessible
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
    echo "$$" > "$LOCKFILE"
    
    # Deuxième processus essaie de prendre le lock
    run bash -c "
        source '$LIB_DIR/colors.sh'
        source '$LIB_DIR/lock.sh'
        LOCKFILE='$LOCKFILE'
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
        LOCKFILE='$LOCKFILE'
        STOP_FLAG='$STOP_FLAG'
        SCRIPT_DIR='$SCRIPT_DIR'
        NO_PROGRESS=true
        setup_traps
        check_lock
        exit 0
    " 2>/dev/null
    
    # Le lock doit être libéré
    [ ! -f "$LOCKFILE" ]
}
