#!/bin/bash
###########################################################
# HELPER POUR LES TESTS BATS
# Charge les modules nécessaires et configure l'environnement
###########################################################

# Répertoire du projet (parent de tests/)
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LIB_DIR="$PROJECT_ROOT/lib"
export FIXTURES_DIR="$(dirname "${BASH_SOURCE[0]}")/fixtures"

# Créer un répertoire temporaire pour les tests
setup_test_env() {
    export TEST_TEMP_DIR=$(mktemp -d)
    export LOG_DIR="$TEST_TEMP_DIR/logs"
    export TMP_DIR="$TEST_TEMP_DIR/tmp"
    mkdir -p "$LOG_DIR" "$TMP_DIR"
}

# Nettoyer après les tests
teardown_test_env() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Charger les modules de base (sans effets de bord)
load_base_modules() {
    # Définir SCRIPT_DIR pour config.sh
    export SCRIPT_DIR="$PROJECT_ROOT"
    
    # Charger les couleurs (désactivées pour les tests)
    source "$LIB_DIR/ui.sh"
    
    # Charger la détection système
    source "$LIB_DIR/detect.sh"
    
    # Charger la configuration
    source "$LIB_DIR/config.sh"
    
    # Charger les utilitaires
    source "$LIB_DIR/utils.sh"
}

# Charger uniquement les couleurs et config (pour tests isolés)
load_minimal() {
    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
}

# Helper pour créer un fichier null-separated
create_null_separated_file() {
    local output_file="$1"
    shift
    # Les arguments restants sont les éléments à écrire
    printf '%s\0' "$@" > "$output_file"
}

# Helper pour vérifier qu'une fonction existe
function_exists() {
    declare -f "$1" > /dev/null 2>&1
}
