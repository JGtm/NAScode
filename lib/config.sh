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
SUFFIX_ENABLED=false      # -S sans argument : activer le suffixe sans question
CUSTOM_SUFFIX_STRING=""   # Suffixe personnalisé via -S/--suffix
REGENERATE_INDEX=false    # Régénérer l'index via -R/--regenerate-index
PARALLEL_JOBS=1
NO_PROGRESS=false
CONVERSION_MODE="serie"
VMAF_ENABLED=false  # Évaluation VMAF désactivée par défaut
SINGLE_FILE=""       # Chemin vers un fichier unique à convertir (bypass index/queue)

# ----- Codec audio -----
# Options : aac (défaut), copy, ac3, opus
# - aac  : AAC 160k, très compatible, bon compromis qualité/taille (défaut)
# - copy : garde l'audio original (pas de réencodage)
# - ac3  : Dolby Digital, compatible TV/receivers
# - opus : Meilleure compression, moins compatible
# Note : la conversion n'a lieu que si on y gagne (anti-upscaling intelligent)
AUDIO_CODEC="aac"
AUDIO_BITRATE_KBPS=0  # 0 = utiliser le défaut selon le codec

# ----- Codec vidéo -----
# Codec cible pour l'encodage (hevc, av1)
# L'encodeur est choisi automatiquement selon le codec (modifiable dans codec_profiles.sh)
VIDEO_CODEC="hevc"
VIDEO_ENCODER=""     # Vide = auto-détection selon VIDEO_CODEC

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
SUFFIX_STRING=""  # Suffixe par défaut (sera mis à jour par build_dynamic_suffix selon le codec)

# Exclusions par défaut
EXCLUDES=("./logs" "./*.sh" "./*.txt" "./Converted" "./tests" "../ConversionPy")

# ----- Paramètres système -----
readonly TMP_DIR="/tmp/video_convert"
readonly MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp

# ----- Paramètres de conversion -----
# Le seuil de skip est maintenant dynamique : MAXRATE_KBPS * (1 + SKIP_TOLERANCE_PERCENT%)
# Il s'adapte automatiquement au mode (film/série) et au codec (HEVC/AV1)

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

# ----- Paramètres audio par codec -----
# Bitrates cibles (kbps) pour chaque codec audio
# Ces valeurs sont utilisées si AUDIO_BITRATE_KBPS=0 (auto)
# Hiérarchie qualité/efficacité (du meilleur au moins bon) :
#   Opus > AAC > E-AC3 > AC3 > FLAC (lossless, cas spécial)
readonly AUDIO_BITRATE_OPUS_DEFAULT=128     # Opus : 128k excellent (plus efficace)
readonly AUDIO_BITRATE_AAC_DEFAULT=160      # AAC : 160k pour 5.1 (polyvalent)
readonly AUDIO_BITRATE_EAC3_DEFAULT=384     # E-AC3 (DD+) : 384k pour séries HD/Atmos
readonly AUDIO_BITRATE_AC3_DEFAULT=640      # AC3 (Dolby) : 640k rétro-compatibilité
readonly AUDIO_BITRATE_FLAC_DEFAULT=0       # FLAC : variable (lossless, pas de limite)

# Seuil de conversion : ne convertir l'audio que si le bitrate source dépasse ce seuil
# Cela évite de "gonfler" un audio déjà compressé à bas débit
readonly AUDIO_CONVERSION_THRESHOLD_KBPS=160

# ----- Mode FORCE (bypasse la logique smart codec) -----
# Si activé, force la conversion vers le codec cible même si la source est "meilleure"
FORCE_AUDIO_CODEC=false   # --force-audio : force le codec audio cible
FORCE_VIDEO_CODEC=false   # --force-video : force le réencodage vidéo

###########################################################
# GESTION DES MODES DE CONVERSION
###########################################################

# Bitrates de RÉFÉRENCE (équivalent HEVC)
# Ces valeurs sont ajustées automatiquement selon l'efficacité du codec cible.
# Calcul : 1,1 Go/h en 1080p → 2503 kbps total → ~2400 kbps vidéo
#
# L'efficacité des codecs (définie dans codec_profiles.sh) :
#   H.264 = 100% (référence), HEVC = 70%, AV1 = 50%, VVC = 35%
# Formule : TARGET_KBPS = BASE_TARGET * (efficiency_codec / efficiency_hevc)
#         = BASE_TARGET * (efficiency_codec / 70)

# Paramètres x265 additionnels par mode (optimisations vitesse/qualité)
X265_EXTRA_PARAMS=""
# Pass 1 rapide (no-slow-firstpass) - désactivé par défaut pour qualité max
X265_PASS1_FAST=false

set_conversion_mode_parameters() {
    # Bitrates de référence HEVC (seront ajustés selon le codec)
    local base_target_kbps base_maxrate_kbps base_bufsize_kbps
    
    case "$CONVERSION_MODE" in
        film)
            # Films : two-pass ABR, qualité maximale
            # Bitrates de référence (HEVC)
            base_target_kbps=2035
            base_maxrate_kbps=3200
            base_bufsize_kbps=4800
            ENCODER_PRESET="medium"
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
            # Bitrates de référence (HEVC)
            base_target_kbps=2070
            base_maxrate_kbps=2520
            base_bufsize_kbps=$(( (base_maxrate_kbps * 3) / 2 ))
            ENCODER_PRESET="medium"
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
    
    # Appliquer le facteur d'efficacité du codec cible
    # Les bitrates de référence sont pour HEVC (efficacité=70)
    # Formule : bitrate_codec = bitrate_hevc * (efficacité_codec / 70)
    local codec_efficiency=70  # HEVC par défaut
    if declare -f get_codec_efficiency &>/dev/null; then
        codec_efficiency=$(get_codec_efficiency "${VIDEO_CODEC:-hevc}")
    fi
    
    # Calculer les bitrates ajustés
    # Exemples : HEVC → *70/70=*1, AV1 → *50/70≈*0.71, VVC → *35/70=*0.5
    TARGET_BITRATE_KBPS=$(( base_target_kbps * codec_efficiency / 70 ))
    MAXRATE_KBPS=$(( base_maxrate_kbps * codec_efficiency / 70 ))
    BUFSIZE_KBPS=$(( base_bufsize_kbps * codec_efficiency / 70 ))
    
    # Valeurs dérivées utilisées par ffmpeg/x265
    TARGET_BITRATE_FFMPEG="${TARGET_BITRATE_KBPS}k"
    MAXRATE_FFMPEG="${MAXRATE_KBPS}k"
    BUFSIZE_FFMPEG="${BUFSIZE_KBPS}k"
    X265_VBV_PARAMS="vbv-maxrate=${MAXRATE_KBPS}:vbv-bufsize=${BUFSIZE_KBPS}"
    
    # Initialiser l'encodeur selon le codec (si pas déjà spécifié)
    if [[ -z "$VIDEO_ENCODER" ]] && declare -f get_codec_encoder &>/dev/null; then
        VIDEO_ENCODER=$(get_codec_encoder "$VIDEO_CODEC")
    elif [[ -z "$VIDEO_ENCODER" ]]; then
        # Fallback si codec_profiles.sh pas encore chargé
        case "$VIDEO_CODEC" in
            hevc) VIDEO_ENCODER="libx265" ;;
            av1)  VIDEO_ENCODER="libsvtav1" ;;
            *)    VIDEO_ENCODER="libx265" ;;
        esac
    fi
    
    # Valider que le codec/encodeur est disponible dans FFmpeg
    if declare -f validate_codec_config &>/dev/null; then
        if ! validate_codec_config; then
            print_error "Configuration codec invalide. Vérifiez que FFmpeg supporte l'encodeur $VIDEO_ENCODER."
            exit 1
        fi
    fi
    
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
# Format effectif: _<codec>_<bitrate>k_<height>p_<preset>[_tuned][_sample]
# Exemples: _x265_1449k_720p_medium_tuned
#           _av1_2070k_1080p_medium
build_dynamic_suffix() {
    # Ne pas écraser si l'utilisateur a forcé --no-suffix
    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        return
    fi
    
    # Suffixe basé sur le codec (x265, av1, etc.)
    local codec_suffix="x265"
    if declare -f get_codec_suffix &>/dev/null; then
        codec_suffix=$(get_codec_suffix "$VIDEO_CODEC")
    elif [[ "$VIDEO_CODEC" == "av1" ]]; then
        codec_suffix="av1"
    fi
    
    local suffix="_${codec_suffix}"
    
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
    
    # Indicateur du codec audio (si différent de copy)
    case "${AUDIO_CODEC:-copy}" in
        aac)  suffix="${suffix}_aac" ;;
        ac3)  suffix="${suffix}_ac3" ;;
        opus) suffix="${suffix}_opus" ;;
    esac
    
    # Indicateur mode sample (segment de test)
    if [[ "$SAMPLE_MODE" == true ]]; then
        suffix="${suffix}_sample"
    fi
    
    SUFFIX_STRING="$suffix"
}

# Regex pré-compilée des exclusions (construite au démarrage pour optimiser is_excluded)
_build_excludes_regex() {
    local regex=""
    local ex ex_norm escaped pat

    for ex in "${EXCLUDES[@]}"; do
        # Normalisation: slashes + suppression de ./ et du / final
        ex_norm="${ex//\\//}"
        ex_norm="${ex_norm#./}"
        ex_norm="${ex_norm%/}"
        [[ -z "$ex_norm" ]] && continue

        # Échapper les caractères spéciaux regex (en gardant * pour le glob)
        escaped=$(printf '%s' "$ex_norm" | sed 's/[][\/.^$+?(){}|]/\\&/g')
        # Conversion glob: * => .*
        escaped="${escaped//\*/.*}"

        # Si le pattern ressemble à un nom de dossier simple (sans / ni *)
        # on le fait matcher comme segment de chemin (ex: /tests/ partout).
        if [[ "$ex_norm" != *"/"* ]] && [[ "$ex_norm" != *"*"* ]]; then
            pat="(^|/)${escaped}(/|$)"
        else
            # Sinon on matche sur le chemin complet (substring)
            pat="$escaped"
        fi

        if [[ -n "$regex" ]]; then
            regex="${regex}|${pat}"
        else
            regex="$pat"
        fi
    done

    echo "$regex"
}
EXCLUDES_REGEX="$(_build_excludes_regex)"
