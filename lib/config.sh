#!/bin/bash
###########################################################
# CONFIGURATION GLOBALE
# Paramètres par défaut et constantes du script
###########################################################

# ----- Horodatage et chemins de base -----
# Note: SCRIPT_DIR est défini dans le script principal avant le chargement des modules
readonly EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
readonly LOCKFILE="/tmp/conversion_video.lock"
readonly STOP_FLAG="/tmp/conversion_stop_flag"
# SCRIPT_DIR est déjà défini par le script principal

# ----- Aides de compatibilité pour macOS / Homebrew -----
# Si l'utilisateur a installé GNU coreutils / gawk via Homebrew, privilégier leur répertoire gnubin
if command -v brew >/dev/null 2>&1; then
    core_gnubin="$(brew --prefix coreutils 2>/dev/null)/libexec/gnubin"
    if [[ -d "$core_gnubin" ]]; then
        PATH="$core_gnubin:$PATH"
    fi
    gawk_bin="$(brew --prefix gawk 2>/dev/null)/bin"
    if [[ -d "$gawk_bin" ]]; then
        PATH="$gawk_bin:$PATH"
    fi
    bash_bin="$(brew --prefix bash 2>/dev/null)/bin"
    if [[ -d "$bash_bin" ]]; then
        PATH="$bash_bin:$PATH"
    fi
fi

# ----- Détection unique des outils disponibles -----
# Ces variables sont évaluées une seule fois au démarrage pour éviter
# des appels répétitifs à `command -v` dans les fonctions utilitaires.
HAS_MD5SUM=$(command -v md5sum >/dev/null 2>&1 && echo 1 || echo 0)
HAS_MD5=$(command -v md5 >/dev/null 2>&1 && echo 1 || echo 0)
HAS_PYTHON3=$(command -v python3 >/dev/null 2>&1 && echo 1 || echo 0)
HAS_DATE_NANO=$(date +%s.%N >/dev/null 2>&1 && echo 1 || echo 0)
HAS_PERL_HIRES=$(perl -MTime::HiRes -e '1' 2>/dev/null && echo 1 || echo 0)
# Détecter si awk supporte systime() (GNU awk)
HAS_GAWK=$(awk 'BEGIN { print systime() }' 2>/dev/null | grep -qE '^[0-9]+$' && echo 1 || echo 0)
# Outils pour calcul SHA256 (vérification intégrité transfert)
HAS_SHA256SUM=$(command -v sha256sum >/dev/null 2>&1 && echo 1 || echo 0)
HAS_SHASUM=$(command -v shasum >/dev/null 2>&1 && echo 1 || echo 0)
HAS_OPENSSL=$(command -v openssl >/dev/null 2>&1 && echo 1 || echo 0)
# Détection de libvmaf dans FFmpeg (pour évaluation qualité vidéo)
HAS_LIBVMAF=$(ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf && echo 1 || echo 0)

# ----- Détection de l'environnement MSYS/MinGW/Git Bash sur Windows -----
IS_MSYS=0
if [[ -n "${MSYSTEM:-}" ]] || [[ "$(uname -s)" =~ ^MINGW|^MSYS|^CYGWIN ]]; then
    IS_MSYS=1
fi

# Normalisation des chemins pour éviter les problèmes de formats mixtes
# Convertit les chemins MSYS (/c/, /d/, etc.) en format Windows (C:/, D:/, etc.)
# et nettoie les doubles slashes, ./ inutiles, etc.
normalize_path() {
    local path="$1"
    [[ -z "$path" ]] && return 0

    # Sur environnement MSYS/MinGW/Git Bash, convertir /lettre/ en Lettre:/
    if [[ "$IS_MSYS" -eq 1 ]]; then
        # Convertir /c/... en C:/... (lettres de lecteur)
        if [[ "$path" =~ ^/([a-zA-Z])(/|$) ]]; then
            local drive="${BASH_REMATCH[1]}"
            drive="${drive^^}"  # Convertir en majuscule
            path="${drive}:${path:2}"
        fi
    fi

    # Nettoyer les chemins : supprimer les ./ au milieu et les doubles slashes
    # Remplacer /./ par /
    while [[ "$path" =~ /\./ ]]; do
        path="${path//\/.\//\/}"
    done
    # Supprimer les doubles slashes (sauf au début pour les chemins UNC)
    path=$(echo "$path" | sed 's#\([^:]\)//\+#\1/#g')
    # Supprimer le slash final sauf pour la racine
    [[ "$path" != "/" && "$path" != *":" ]] && path="${path%/}"

    echo "$path"
}

# ----- Variables modifiables par arguments -----
DRYRUN=false
RANDOM_MODE=false
LIMIT_FILES=0
CUSTOM_QUEUE=""
SOURCE="../"
OUTPUT_DIR="$SCRIPT_DIR/Converted"
FORCE_NO_SUFFIX=false
PARALLEL_JOBS=1
NO_PROGRESS=false
CONVERSION_MODE="serie"
VMAF_ENABLED=false  # Évaluation VMAF désactivée par défaut

# Mode de tri pour la construction de la file d'attente (optionnel)
# Options disponibles pour `SORT_MODE` :
#   - size_desc  : Trier par taille décroissante (par défaut, privilégie gros fichiers)
#   - size_asc   : Trier par taille croissante
#   - name_asc   : Trier par nom de fichier (ordre alphabétique ascendant)
#   - name_desc  : Trier par nom de fichier (ordre alphabétique descendant)
SORT_MODE="name_asc"

# Conserver l'index existant sans demander confirmation
KEEP_INDEX=false

# ----- Constantes de configuration -----
# Paramètre de nombre de fichiers à sélectionner aléatoirement par défaut
readonly RANDOM_MODE_DEFAULT_LIMIT=10

# Version FFMPEG minimale
readonly FFMPEG_MIN_VERSION=8 

# Suffixe pour les fichiers
readonly DRYRUN_SUFFIX="-dryrun-sample"
SUFFIX_STRING="_x265"  # Suffixe par défaut (sera mis à jour par build_dynamic_suffix)

# Exclusions par défaut
EXCLUDES=("./logs" "./*.sh" "./*.txt" "Converted")

# ----- Paramètres système -----
readonly TMP_DIR="/tmp/video_convert"
readonly MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp

# ----- Paramètres de conversion -----
# SEUIL DE BITRATE DE CONVERSION (KBPS)
# Fichiers avec bitrate inférieur à ce seuil ne seront pas reconvertis
readonly BITRATE_CONVERSION_THRESHOLD_KBPS=2520

# TOLÉRANCE DU BITRATE A SKIP (%)
readonly SKIP_TOLERANCE_PERCENT=10

# CORRECTION IONICE
IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then 
    IO_PRIORITY_CMD="ionice -c2 -n4"
fi

# ----- Variables d'encodage (initialisées par set_conversion_mode_parameters) -----
ENCODER_PRESET=""
TARGET_BITRATE_KBPS=0
MAXRATE_KBPS=0
BUFSIZE_KBPS=0
TARGET_BITRATE_FFMPEG=""
MAXRATE_FFMPEG=""
BUFSIZE_FFMPEG=""
X265_VBV_PARAMS=""
HWACCEL=""

###########################################################
# GESTION DES MODES DE CONVERSION
###########################################################

# Two-pass encoding : bitrate cible pour 1,1 Go/h en 1080p
# Calcul : 1,1 Go = 1,1 * 1024 * 8 Mbits = 9011 Mbits
#          9011 / 3600s = 2503 kbps total
#          Video = ~2300-2400 kbps (audio ~128 kbps)

# Paramètres x265 additionnels par mode (optimisations vitesse/qualité)
X265_EXTRA_PARAMS=""

set_conversion_mode_parameters() {
    case "$CONVERSION_MODE" in
        film)
            # Films : bitrate plus élevé pour meilleure qualité
            TARGET_BITRATE_KBPS=2250
            ENCODER_PRESET="slow"
            MAXRATE_KBPS=3600
            BUFSIZE_KBPS=$(( (MAXRATE_KBPS * 3) / 2 ))
            # Films : garder toutes les optimisations x265 pour qualité max
            X265_EXTRA_PARAMS=""
            ;;
        serie)
            # Séries : bitrate optimisé pour ~1 Go/h
            TARGET_BITRATE_KBPS=2070
            ENCODER_PRESET="medium"
            MAXRATE_KBPS=2520
            BUFSIZE_KBPS=$(( (MAXRATE_KBPS * 3) / 2 ))
            # Séries : optimisations vitesse (amp=0, rect=0 accélèrent l'encodage
            # avec impact minime sur la qualité pour du contenu série)
            X265_EXTRA_PARAMS="amp=0:rect=0"
            ;;
        *)
            echo -e "${RED}ERREUR : Mode de conversion inconnu : $CONVERSION_MODE${NOCOLOR}"
            echo "Modes disponibles : film, serie"
            exit 1
            ;;
    esac
    # Valeurs dérivées utilisées par ffmpeg/x265
    TARGET_BITRATE_FFMPEG="${TARGET_BITRATE_KBPS}k"
    MAXRATE_FFMPEG="${MAXRATE_KBPS}k"
    BUFSIZE_FFMPEG="${BUFSIZE_KBPS}k"
    X265_VBV_PARAMS="vbv-maxrate=${MAXRATE_KBPS}:vbv-bufsize=${BUFSIZE_KBPS}"
    
    # Construire le suffixe dynamique basé sur les paramètres
    build_dynamic_suffix
}

###########################################################
# GÉNÉRATION DU SUFFIXE DYNAMIQUE
###########################################################

# Construit un suffixe de fichier reflétant les paramètres de conversion
# Format: _x265_<mode>_<bitrate>k_<preset>[_tuned]
# Exemples: _x265_serie_2070k_medium_tuned
#           _x265_film_2250k_slow
build_dynamic_suffix() {
    # Ne pas écraser si l'utilisateur a forcé --no-suffix
    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        return
    fi
    
    local suffix="_x265"
    
    # Bitrate cible
    suffix="${suffix}_${TARGET_BITRATE_KBPS}k"
    
    # Preset d'encodage
    suffix="${suffix}_${ENCODER_PRESET}"
    
    # Indicateur si paramètres x265 spéciaux (tuned)
    if [[ -n "$X265_EXTRA_PARAMS" ]]; then
        suffix="${suffix}_tuned"
    fi
    
    SUFFIX_STRING="$suffix"
}

# Regex pré-compilée des exclusions (construite au démarrage pour optimiser is_excluded)
_build_excludes_regex() {
    local regex=""
    for ex in "${EXCLUDES[@]}"; do
        # Échapper les caractères spéciaux regex et convertir * en .*
        local escaped
        escaped=$(printf '%s' "$ex" | sed 's/[][\/.^$]/\\&/g; s/\*/\.\*/g')
        if [[ -n "$regex" ]]; then
            regex="${regex}|^${escaped}"
        else
            regex="^${escaped}"
        fi
    done
    echo "$regex"
}
EXCLUDES_REGEX="$(_build_excludes_regex)"

###########################################################
# DÉTECTION HARDWARE ACCELERATION
###########################################################

# Détecte et définit la variable HWACCEL utilisée pour le décodage matériel
detect_hwaccel() {
    HWACCEL=""

    # macOS -> videotoolbox
    if [[ "$(uname -s)" == "Darwin" ]]; then
        HWACCEL="videotoolbox"
    else
        HWACCEL="cuda"
    fi
}
