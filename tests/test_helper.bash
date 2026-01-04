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
    
    # Charger les profils de codecs
    source "$LIB_DIR/codec_profiles.sh"
    
    # Charger les utilitaires
    source "$LIB_DIR/utils.sh"
    
    # Charger les fonctions de probe média (doit être avant audio_params)
    source "$LIB_DIR/media_probe.sh"
    
    # Charger les paramètres audio
    source "$LIB_DIR/audio_params.sh"

    # Charger l'analyse de complexité (mode film-adaptive)
    source "$LIB_DIR/complexity.sh"

    # Charger les paramètres vidéo et le mapping streams
    source "$LIB_DIR/video_params.sh"
    source "$LIB_DIR/stream_mapping.sh"
}

# Version rapide de load_base_modules qui mocke detect.sh (pour tests sans I/O réel)
load_base_modules_fast() {
    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    # Mock des variables de détection (évite les appels système lents)
    export HAS_MD5SUM=1 HAS_MD5=0 HAS_PYTHON3=1 HAS_DATE_NANO=1 HAS_PERL_HIRES=0
    export HAS_GAWK=1 HAS_SHA256SUM=1 HAS_SHASUM=0 HAS_OPENSSL=1
    export HAS_LIBVMAF=0 FFMPEG_VMAF=""
    export IS_MSYS=0 IS_MACOS=0 IS_LINUX=1
    export HAS_LIBSVTAV1=1 HAS_LIBX265=1 HAS_LIBAOM=0
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/codec_profiles.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/media_probe.sh"
    source "$LIB_DIR/audio_params.sh"
    source "$LIB_DIR/complexity.sh"
    source "$LIB_DIR/video_params.sh"
    source "$LIB_DIR/stream_mapping.sh"
}

# Charger uniquement les couleurs et config (pour tests isolés)
load_minimal() {
    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/codec_profiles.sh"
}

# Version rapide de load_minimal qui mocke detect.sh (pour tests sans I/O)
# Utiliser pour les tests qui n'ont pas besoin de vraie détection système
load_minimal_fast() {
    export SCRIPT_DIR="$PROJECT_ROOT"
    source "$LIB_DIR/ui.sh"
    # Mock des variables de détection (évite les appels système lents)
    export HAS_MD5SUM=1
    export HAS_MD5=0
    export HAS_PYTHON3=1
    export HAS_DATE_NANO=1
    export HAS_PERL_HIRES=0
    export HAS_GAWK=1
    export HAS_SHA256SUM=1
    export HAS_SHASUM=0
    export HAS_OPENSSL=1
    export HAS_LIBVMAF=0
    export FFMPEG_VMAF=""
    export IS_MSYS=0
    export IS_MACOS=0
    export IS_LINUX=1
    export HAS_LIBSVTAV1=1
    export HAS_LIBX265=1
    export HAS_LIBAOM=0
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/codec_profiles.sh"
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
