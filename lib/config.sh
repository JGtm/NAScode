#!/bin/bash
###########################################################
# CONFIGURATION GLOBALE
###########################################################

# ----- Horodatage et chemins de base -----
# Note: SCRIPT_DIR est défini dans le script principal avant le chargement des modules
readonly EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
readonly LOCKFILE="/tmp/conversion_video.lock"
readonly STOP_FLAG="/tmp/conversion_stop_flag"
# SCRIPT_DIR est déjà défini par le script principal

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
OPUS_ENABLED=false  # Conversion audio Opus (expérimental, problèmes VLC)
SINGLE_FILE=""       # Chemin vers un fichier unique à convertir (bypass index/queue)

# Mode sample : encoder uniquement un segment de test (30s par défaut)
SAMPLE_MODE=false
SAMPLE_DURATION=30      # Durée du segment en secondes
SAMPLE_MARGIN_START=180 # Marge début (éviter générique) en secondes
SAMPLE_MARGIN_END=120   # Marge fin (éviter générique) en secondes
SAMPLE_KEYFRAME_POS=""  # Position exacte du keyframe utilisé (décimal, pour VMAF)

# Mode single-pass CRF pour séries (plus rapide, taille variable)
# Activé par défaut pour le mode "serie", désactivé automatiquement pour "film"
SINGLE_PASS_MODE=true

# Mode de tri pour la construction de la file d'attente (optionnel)
# Options disponibles pour `SORT_MODE` :
#   - size_desc  : Trier par taille décroissante (par défaut, privilégie gros fichiers)
#   - size_asc   : Trier par taille croissante
#   - name_asc   : Trier par nom de fichier (ordre alphabétique ascendant)
#   - name_desc  : Trier par nom de fichier (ordre alphabétique descendant)
SORT_MODE="size_desc"

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

# ----- Limitation de résolution (downscale automatique) -----
# Objectif : éviter de compresser du 1440p/2160p avec un bitrate prévu pour du 1080p.
# Règle : si la source dépasse 1080p, on redimensionne pour tenir dans 1920x1080
# en conservant le ratio d'aspect.
readonly DOWNSCALE_MAX_WIDTH=1920
readonly DOWNSCALE_MAX_HEIGHT=1080

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

# ----- Adaptation du bitrate par résolution (par fichier) -----
# Objectif : garder une taille prévisible en two-pass en ajustant le budget quand la
# sortie est nettement plus petite qu'un 1080p (ex: 720p).
#
# Remarque : ces valeurs s'appliquent uniquement à l'encodage (FFmpeg/x265) et ne
# changent pas le mode global (film/serie) affiché dans le résumé.
readonly ADAPTIVE_BITRATE_BY_RESOLUTION=true

# Profil 720p (déclenché si la hauteur de sortie estimée <= 720)
readonly ADAPTIVE_720P_MAX_HEIGHT=720

# Facteur appliqué aux bitrates base (TARGET/MAXRATE/BUFSIZE) quand profil 720p.
# Exemple : 70 => 2070k (1080p) devient ~1449k (720p)
readonly ADAPTIVE_720P_SCALE_PERCENT=70

# ----- Paramètres audio Opus (expérimental) -----
# Note : la conversion Opus peut causer des problèmes avec VLC pour le surround.
# Utiliser --opus pour activer cette fonctionnalité.
readonly OPUS_TARGET_BITRATE_KBPS=128
readonly OPUS_CONVERSION_THRESHOLD_KBPS=160

###########################################################
# GESTION DES MODES DE CONVERSION
###########################################################

# Two-pass encoding : bitrate cible pour 1,1 Go/h en 1080p
# Calcul : 1,1 Go = 1,1 * 1024 * 8 Mbits = 9011 Mbits
#          9011 / 3600s = 2503 kbps total
#          Video = ~2300-2400 kbps (audio ~128 kbps)

# Paramètres x265 additionnels par mode (optimisations vitesse/qualité)
X265_EXTRA_PARAMS=""
# Pass 1 rapide (no-slow-firstpass) - désactivé par défaut pour qualité max
X265_PASS1_FAST=false

set_conversion_mode_parameters() {
    case "$CONVERSION_MODE" in
        film)
            # Films : two-pass ABR, qualité maximale
            TARGET_BITRATE_KBPS=2035
            ENCODER_PRESET="medium"
            # ABR avec maxrate/bufsize souples pour qualité constante
            MAXRATE_KBPS=3200
            BUFSIZE_KBPS=4800
            # Films : pas de paramètres x265 spéciaux (défauts optimaux)
            X265_EXTRA_PARAMS=""
            # Pass 1 complète pour une analyse approfondie (qualité max)
            X265_PASS1_FAST=false
            # Films : forcer two-pass pour qualité maximale
            SINGLE_PASS_MODE=false
            # GOP court pour meilleur seeking (240 frames ~10s @ 24fps)
            FILM_KEYINT=240
            # Pas de tune fastdecode pour qualité max
            FILM_TUNE_FASTDECODE=false
            ;;
        serie)
            # Séries : bitrate optimisé pour ~1 Go/h (two-pass) ou CRF 21 (single-pass)
            TARGET_BITRATE_KBPS=2070
            ENCODER_PRESET="medium"
            MAXRATE_KBPS=2520
            BUFSIZE_KBPS=$(( (MAXRATE_KBPS * 3) / 2 ))
            # Séries : optimisations vitesse/qualité adaptées au contenu série
            # - amp=0, rect=0 : désactive AMP/RECT (gain vitesse ~10%, perte qualité négligeable)
            # - sao=0 : désactive Sample Adaptive Offset (gain ~5%, perte minime sur séries)
            # - strong-intra-smoothing=0 : préserve les détails fins et edges nettes
            # - limit-refs=3 : limite les références motion (bon compromis)
            # - subme=2 : précision sub-pixel réduite (gain vitesse significatif)
            X265_EXTRA_PARAMS="amp=0:rect=0:sao=0:strong-intra-smoothing=0:limit-refs=3:subme=2"
            # Pass 1 rapide : analyse moins approfondie mais gain temps ~15%
            X265_PASS1_FAST=true
            # En mode single-pass, on utilise CRF au lieu du bitrate cible
            # CRF : 0=lossless, 18=quasi-transparent, 23=défaut x265, 28+=basse qualité
            if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
                CRF_VALUE=21
            fi
            # GOP long pour meilleure compression (600 frames ~25s @ 24fps)
            FILM_KEYINT=600
            # Tune fastdecode pour décodage fluide sur appareils variés
            FILM_TUNE_FASTDECODE=true
            ;;
        *)
            print_error "Mode de conversion inconnu : $CONVERSION_MODE"
            echo "  Modes disponibles : film, serie"
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

# Construit un suffixe de fichier reflétant les paramètres de conversion.
# IMPORTANT : le suffixe final est désormais calculé par fichier (bitrate effectif + résolution)
# dans lib/transcode_video.sh. SUFFIX_STRING sert ici surtout de "preview" et d'interrupteur
# (vide = suffixe désactivé).
#
# Format effectif: _x265_<bitrate>k_<height>p_<preset>[_tuned][_sample]
# Exemples: _x265_1449k_720p_medium_tuned
#           _x265_2070k_1080p_medium_tuned
build_dynamic_suffix() {
    # Ne pas écraser si l'utilisateur a forcé --no-suffix
    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        return
    fi
    
    local suffix="_x265"
    
    # Mode single-pass CRF ou two-pass bitrate
    if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
        suffix="${suffix}_crf${CRF_VALUE}"
    else
        # Bitrate cible (two-pass)
        suffix="${suffix}_${TARGET_BITRATE_KBPS}k"
    fi

    # Résolution (preview) : la valeur réelle est déterminée par fichier.
    suffix="${suffix}_1080p"
    
    # Preset d'encodage
    suffix="${suffix}_${ENCODER_PRESET}"
    
    # Indicateur si paramètres x265 spéciaux (tuned)
    if [[ -n "$X265_EXTRA_PARAMS" ]]; then
        suffix="${suffix}_tuned"
    fi
    
    # Indicateur conversion audio Opus
    if [[ "${OPUS_ENABLED:-false}" == true ]]; then
        suffix="${suffix}_opus"
    fi
    
    # Indicateur mode sample (segment de test)
    if [[ "$SAMPLE_MODE" == true ]]; then
        suffix="${suffix}_sample"
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
