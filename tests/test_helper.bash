#!/bin/bash
###########################################################
# HELPER POUR LES TESTS BATS
# Charge les modules nécessaires et configure l'environnement
#
# API simplifiée :
#   load_modules "base"     - Charge tous les modules avec détection réelle
#   load_modules "base_fast" - Charge tous les modules avec mocks système
#   load_modules "minimal"   - Charge seulement config/ui avec détection réelle
#   load_modules "minimal_fast" - Charge seulement config/ui avec mocks
#
# Les anciennes fonctions sont conservées pour rétro-compatibilité.
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

###########################################################
# MOCK DES VARIABLES DE DÉTECTION SYSTÈME
###########################################################

# Applique les mocks pour éviter les appels système lents
_apply_detection_mocks() {
    export HAS_MD5SUM=1 HAS_MD5=0 HAS_PYTHON3=1 HAS_DATE_NANO=1 HAS_PERL_HIRES=0
    export HAS_GAWK=1 HAS_SHA256SUM=1 HAS_SHASUM=0 HAS_OPENSSL=1
    export HAS_LIBVMAF=0 FFMPEG_VMAF=""
    export IS_MSYS=0 IS_MACOS=0 IS_LINUX=1
    export HAS_LIBSVTAV1=1 HAS_LIBX265=1 HAS_LIBAOM=0
}

###########################################################
# CHARGEMENT DES MODULES - API UNIFIÉE
###########################################################

# Charge les modules selon le mode spécifié
# Usage: load_modules <mode>
#   mode: "base", "base_fast", "minimal", "minimal_fast"
load_modules() {
    local mode="${1:-base}"
    export SCRIPT_DIR="$PROJECT_ROOT"

    case "$mode" in
        base)
            _load_modules_base false
            ;;
        base_fast)
            _load_modules_base true
            ;;
        minimal)
            _load_modules_minimal false
            ;;
        minimal_fast)
            _load_modules_minimal true
            ;;
        *)
            echo "Mode inconnu: $mode (base, base_fast, minimal, minimal_fast)" >&2
            return 1
            ;;
    esac
}

# Implémentation interne : charge les modules de base
_load_modules_base() {
    local use_mocks="${1:-false}"

    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/ui_options.sh"

    if [[ "$use_mocks" == true ]]; then
        _apply_detection_mocks
    else
        source "$LIB_DIR/detect.sh"
    fi

    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/codec_profiles.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/media_probe.sh"
    source "$LIB_DIR/audio_params.sh"
    source "$LIB_DIR/complexity.sh"
    source "$LIB_DIR/video_params.sh"
    source "$LIB_DIR/stream_mapping.sh"
    source "$LIB_DIR/counters.sh"
    source "$LIB_DIR/skip_decision.sh"
    source "$LIB_DIR/conversion_prep.sh"
    source "$LIB_DIR/adaptive_mode.sh"
}

# Implémentation interne : charge les modules minimaux
_load_modules_minimal() {
    local use_mocks="${1:-false}"

    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/ui_options.sh"

    if [[ "$use_mocks" == true ]]; then
        _apply_detection_mocks
    else
        source "$LIB_DIR/detect.sh"
    fi

    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/codec_profiles.sh"
    source "$LIB_DIR/counters.sh"
    source "$LIB_DIR/skip_decision.sh"
}

###########################################################
# FONCTIONS RÉTRO-COMPATIBLES (conservées)
###########################################################

# Charger les modules de base (sans effets de bord)
load_base_modules() {
    load_modules "base"
}

# Version rapide de load_base_modules qui mocke detect.sh (pour tests sans I/O réel)
load_base_modules_fast() {
    load_modules "base_fast"
}

# Charger uniquement les couleurs et config (pour tests isolés)
load_minimal() {
    load_modules "minimal"
}

# Version rapide de load_minimal qui mocke detect.sh (pour tests sans I/O)
# Utiliser pour les tests qui n'ont pas besoin de vraie détection système
load_minimal_fast() {
    load_modules "minimal_fast"
}

###########################################################
# HELPERS UTILITAIRES
###########################################################

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

###########################################################
# ASSERTIONS (helpers)
###########################################################

# Vérifie qu'au moins un fichier matche un glob.
# Usage: assert_glob_exists "/path/to/pattern_*.log"
assert_glob_exists() {
    local pattern="$1"
    if ! compgen -G "$pattern" > /dev/null; then
        echo "Expected glob to match at least one file: $pattern" >&2
        return 1
    fi
}

# Vérifie qu'aucune ligne ne ressemble à un prompt interactif (ligne commençant par '?').
# Usage: assert_output_has_no_prompt_lines
assert_output_has_no_prompt_lines() {
    # On évite d'encoder ici des textes de questions précis (fragiles).
    # On détecte seulement le marqueur de prompt au début de ligne.
    if printf '%s\n' "$output" | grep -qE '^[[:space:]]*\?[[:space:]]'; then
        echo "Unexpected interactive prompt detected in output" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
}
