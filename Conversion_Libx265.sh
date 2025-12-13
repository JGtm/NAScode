#!/bin/bash

###########################################################
# TO DO
# 1. Erreur à analyser pour le fichier My Dearest Nemesis - 1x12 - Épisode 12 qui echoue a chaque fois
###########################################################

set -euo pipefail

###########################################################
# CONFIGURATION GLOBALE
###########################################################

# Paramètres par défaut
readonly EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
readonly LOCKFILE="/tmp/conversion_video.lock"
readonly STOP_FLAG="/tmp/conversion_stop_flag"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- Aides de compatibilité pour macOS / Homebrew -----
# Si l utilisateur a installé GNU coreutils / gawk via Homebrew, privilégier leur répertoire gnubin
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

# préfixe md5 portable (8 premiers caractères) pour créer les noms temporaires
compute_md5_prefix() {
    local input="$1"
    if [[ "$HAS_MD5SUM" -eq 1 ]]; then
        printf "%s" "$input" | md5sum | awk '{print substr($1,1,8)}'
    elif [[ "$HAS_MD5" -eq 1 ]]; then
        # Sur macOS, md5 n affiche que le digest pour stdin ; gestion robuste
        printf "%s" "$input" | md5 | awk '{print substr($1,1,8)}'
    elif [[ "$HAS_PYTHON3" -eq 1 ]]; then
        # shellcheck disable=SC2259
        printf "%s" "$input" | python3 - <<PY | head -1
import sys,hashlib
print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:8])
PY
    else
        # repli : utiliser un hash shell simple (non cryptographique mais stable)
        printf "%s" "$input" | awk '{s=0; for(i=1;i<=length($0);i++){s=(s*31+and(255, ord=ord(substr($0,i,1))));} printf "%08x", s}' 2>/dev/null || echo "00000000"
    fi
}

# horodatage haute resolution (secondes avec fraction)
now_ts() {
    if [[ "$HAS_DATE_NANO" -eq 1 ]]; then
        date +%s.%N
    elif [[ "$HAS_PYTHON3" -eq 1 ]]; then
        python3 -c 'import time; print(time.time())'
    elif [[ "$HAS_PERL_HIRES" -eq 1 ]]; then
        perl -MTime::HiRes -e 'printf("%.6f\n", Time::HiRes::time)'
    else
        date +%s
    fi
}

# -----------------------------------------------------

# Variables modifiables par arguments
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

# Mode de tri pour la construction de la file d attente (optionnel)
# Options disponibles pour `SORT_MODE` :
#   - size_desc  : Trier par taille décroissante (par défaut, privilégie gros fichiers)
#   - size_asc   : Trier par taille croissante
#   - name_asc   : Trier par nom de fichier (ordre alphabétique ascendant)
#   - name_desc  : Trier par nom de fichier (ordre alphabétique descendant)
SORT_MODE="name_asc"

# Conserver l index existant sans demander confirmation
KEEP_INDEX=false

# Paramètre de nombre de fichiers à sélectionner aléatoirement par défaut
readonly RANDOM_MODE_DEFAULT_LIMIT=10

# Version FFMPEG minimale
readonly FFMPEG_MIN_VERSION=8 

# Suffixe pour les fichiers
readonly DRYRUN_SUFFIX="-dryrun-sample"
SUFFIX_STRING="_x265"  # Suffixe par défaut pour les fichiers de sortie

# Exclusions par défaut
EXCLUDES=("./logs" "./*.sh" "./*.txt" "Converted")

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

# Fonction utilitaire : compter les éléments dans un fichier null-separated
count_null_separated() {
    local file="$1"
    if [[ -f "$file" ]]; then
        tr -cd '\0' < "$file" | wc -c
    else
        echo 0
    fi
}

###########################################################
# COULEURS ANSI
###########################################################

readonly NOCOLOR=$'\033[0m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly RED=$'\033[0;31m'
readonly CYAN=$'\033[0;36m'
readonly BLUE=$'\033[0;34m'
readonly MAGENTA=$'\033[0;35m'
readonly ORANGE=$'\033[1;33m'

###########################################################
# CHEMINS DES LOGS
###########################################################

readonly LOG_DIR="./logs"
readonly LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"
readonly LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"
readonly LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"
readonly SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
readonly LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
readonly INDEX="$LOG_DIR/Index"
readonly INDEX_READABLE="$LOG_DIR/Index_readable_${EXECUTION_TIMESTAMP}.txt"
readonly QUEUE="$LOG_DIR/Queue"
readonly LOG_DRYRUN_COMPARISON="$LOG_DIR/DryRun_Comparison_${EXECUTION_TIMESTAMP}.log"
readonly VMAF_QUEUE_FILE="$LOG_DIR/.vmaf_queue_${EXECUTION_TIMESTAMP}"

###########################################################
# PARAMÈTRES TECHNIQUES
###########################################################

# Système
readonly TMP_DIR="/tmp/video_convert"

readonly MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp


# PARAMETRES DE CONVERSION (encodeur generique - HEVC/x265)
# Two-pass encoding : bitrate cible au lieu de CRF pour taille previsible
# ENCODER_PRESET : Prereglage generique de l encodeur. Pour libx265 utiliser (ultrafast..veryslow),
ENCODER_PRESET=""

# SEUIL DE BITRATE DE CONVERSION (KBPS)
readonly BITRATE_CONVERSION_THRESHOLD_KBPS=2800

# TOLÉRANCE DU BITRATE A SKIP (%)
readonly SKIP_TOLERANCE_PERCENT=10

# CORRECTION IONICE
IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then 
    IO_PRIORITY_CMD="ionice -c2 -n4"
fi

###########################################################
# GESTION DES MODES DE CONVERSION
###########################################################

# Two-pass encoding : bitrate cible pour 1,1 Go/h en 1080p
# Calcul : 1,1 Go = 1,1 * 1024 * 8 Mbits = 9011 Mbits
#          9011 / 3600s = 2503 kbps total
#          Video = ~2300-2400 kbps (audio ~128 kbps)

set_conversion_mode_parameters() {
    case "$CONVERSION_MODE" in
        film)
            # Films : bitrate plus eleve pour meilleure qualite
            TARGET_BITRATE_KBPS=2500
            ENCODER_PRESET="slow"
            MAXRATE_KBPS=4000
            BUFSIZE_KBPS=$(( (MAXRATE_KBPS * 3) / 2 ))
            ;;
        serie)
            # Series : bitrate optimise pour ~1,1 Go/h
            TARGET_BITRATE_KBPS=2300
            ENCODER_PRESET="medium"
            MAXRATE_KBPS=2800
            BUFSIZE_KBPS=$(( (MAXRATE_KBPS * 3) / 2 ))
            ;;
        *)
            echo -e "${RED}ERREUR : Mode de conversion inconnu : $CONVERSION_MODE${NOCOLOR}"
            echo "Modes disponibles : film, serie"
            exit 1
            ;;
    esac
    # Valeurs derivees utilisees par ffmpeg/x265
    TARGET_BITRATE_FFMPEG="${TARGET_BITRATE_KBPS}k"
    MAXRATE_FFMPEG="${MAXRATE_KBPS}k"
    BUFSIZE_FFMPEG="${BUFSIZE_KBPS}k"
    X265_VBV_PARAMS="vbv-maxrate=${MAXRATE_KBPS}:vbv-bufsize=${BUFSIZE_KBPS}"
}

###########################################################
# GESTION DES ARGUMENTS
###########################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source) 
                SOURCE="$2"
                shift 2 
                ;;
            -o|--output-dir) 
                OUTPUT_DIR="$2"
                shift 2 
                ;;
            -e|--exclude) 
                EXCLUDES+=("$2")
                shift 2 
                ;;
            -m|--mode) 
                CONVERSION_MODE="$2"
                shift 2 
                ;;
            -d|--dry-run|--dryrun) 
                DRYRUN=true
                shift 
                ;;
            -x|--no-suffix) 
                FORCE_NO_SUFFIX=true
                shift 
                ;;
            -r|--random)
                RANDOM_MODE=true
                shift
                ;;
            -l|--limit)
                if [[ "${2:-}" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]]; then
                    LIMIT_FILES="$2"
                    shift 2
                else
                    echo -e "${RED}ERREUR : --limit doit être suivi d'un nombre positif.${NOCOLOR}"
                    exit 1
                fi
                ;;
            -q|--queue)
                if [[ -f "$2" ]]; then
                    CUSTOM_QUEUE="$2"
                    shift 2
                else
                    echo -e "${RED}ERREUR : Fichier queue '$2' introuvable.${NOCOLOR}"
                    exit 1
                fi
                ;;
            -n|--no-progress)
                NO_PROGRESS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -k|--keep-index)
                KEEP_INDEX=true
                shift
                ;;
            -v|--vmaf)
                VMAF_ENABLED=true
                shift
                ;;
            -*) 
                # On vérifie si l argument est une option courte groupée
                if [[ "$1" =~ ^-[a-zA-Z]{2,}$ ]]; then
                    local flag_to_process="-${1:1:1}" 
                    # remaining_flags = le reste
                    local remaining_flags="-${1:2}" 
                    # Remplacement des arguments :
                    # 1. Le premier argument devient le premier flag à traiter (-x).
                    # 2. Le reste de l argument groupé est réinséré avant les arguments suivants.
                    set -- "$flag_to_process" "$remaining_flags" "${@:2}"
                    continue # On relance la boucle pour traiter le flag_to_process.
                fi
                # Si ce n est pas une option groupée ou si ce n est pas géré, c est une erreur.
                echo -e "${RED}Option inconnue : $1${NOCOLOR}"
                show_help
                exit 1
                ;;
        esac
    done

    #if [[ "$OUTPUT_DIR" != /* ]]; then
    #    OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
    #fi
    
    # En mode random, appliquer la limite par défaut si aucune limite n a été spécifiée
    if [[ "$RANDOM_MODE" == true ]] && [[ "$LIMIT_FILES" -eq 0 ]]; then
        LIMIT_FILES=$RANDOM_MODE_DEFAULT_LIMIT
    fi
}

show_help() {
    cat << EOF
Usage : ./conversion.sh [OPTIONS]

Options :
    -s, --source DIR             Dossier source (ARG) [défaut : dossier parent]
    -o, --output-dir DIR         Dossier de destination (ARG) [défaut : `Converted` au même niveau que le script]
    -e, --exclude PATTERN        Ajouter un pattern d'exclusion (ARG)
    -m, --mode MODE              Mode de conversion : film, serie (ARG) [défaut : serie]
    -d, --dry-run                Mode simulation sans conversion (FLAG)
    -x, --no-suffix              Désactiver le suffixe _x265 (FLAG)
    -r, --random                 Tri aléatoire : sélectionne des fichiers aléatoires (FLAG) [défaut : 10]
    -l, --limit N                Limiter le traitement à N fichiers (ARG)
    -q, --queue FILE             Utiliser un fichier queue personnalisé (ARG)
    -n, --no-progress            Désactiver l'affichage des indicateurs de progression (FLAG)
    -h, --help                   Afficher cette aide (FLAG)
    -k, --keep-index             Conserver l'index existant sans demande interactive (FLAG)
    -v, --vmaf                   Activer l'évaluation VMAF de la qualité vidéo (FLAG) [désactivé par défaut]

Remarque sur les options courtes groupées :
    - Les options courtes peuvent être groupées lorsque ce sont des flags (sans argument),
        par exemple : -xdrk est équivalent à -x -d -r -k.
    - Les options qui attendent un argument (marquées (ARG) ci-dessus : -s, -o, -e, -m, -l, -q)
        doivent être fournies séparément avec leur valeur, par exemple : -l 5 ou --limit 5.
        par exemple : ./conversion.sh -xdrk -l 5  (groupement de flags puis -l 5 séparé),
                      ./conversion.sh --source /path --limit 10.

Modes de conversion :
  film          : Qualité maximale
  serie         : Bon compromis taille/qualité [défaut]

Exemples :
  ./conversion.sh
  ./conversion.sh -s /media/videos -o /media/converted
  ./conversion.sh --mode film --dry-run
  ./conversion.sh --mode serie --no-progress
  ./conversion.sh -xdrk -l 5      -x (no-suffix) -d (dry-run) -r (random) -k (keep-index) puis -l 5
  ./conversion.sh -dnr            -d (dry-run) -n (no-progress) -r (random)
  ./conversion.sh --vmaf          Activer l'évaluation VMAF après conversion
EOF
}

###########################################################
# GESTION DU VERROUILLAGE
###########################################################

cleanup() {
    local exit_code=$?
    # Afficher le message d interruption seulement si terminaison par signal (INT/TERM)
    # et pas déjà signalé par STOP_FLAG
    # Note: On utilise une variable pour détecter les signaux plutôt que le code de sortie
    if [[ "${_INTERRUPTED:-}" == "1" ]] && [[ ! -f "$STOP_FLAG" ]]; then
        echo -e "\n${YELLOW}⚠️ Interruption détectée, arrêt en cours...${NOCOLOR}"
    fi
    touch "$STOP_FLAG"
    # Attendre brièvement que les processus en arrière-plan détectent le STOP_FLAG
    sleep 0.3
    kill $(jobs -p) 2>/dev/null || true
    # Attendre que les jobs se terminent pour éviter les messages après le prompt
    wait 2>/dev/null || true
    rm -f "$LOCKFILE"
    # Nettoyage des artefacts de queue dynamique
    if [[ -n "${WORKFIFO:-}" ]]; then
        rm -f "${WORKFIFO}" 2>/dev/null || true
    fi
    # Suppression des artefacts du writer FIFO si présents
    if [[ -n "${FIFO_WRITER_PID:-}" ]]; then
        rm -f "${FIFO_WRITER_PID}" "${FIFO_WRITER_READY:-}" 2>/dev/null || true
    fi
    # Nettoyage des slots de progression parallèle
    cleanup_progress_slots
}

# Variable pour détecter une vraie interruption (Ctrl+C ou kill)
_INTERRUPTED=0
_handle_interrupt() {
    _INTERRUPTED=1
    exit 130
}

trap cleanup EXIT
trap _handle_interrupt INT TERM

check_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE")
        
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${RED}⛔ Le script est déjà en cours d'exécution (PID $pid).${NOCOLOR}"
            exit 1
        else
            echo -e "${YELLOW}⚠️ Fichier lock trouvé mais processus absent. Nettoyage...${NOCOLOR}"
            rm -f "$LOCKFILE"
        fi
    fi
    
    echo $$ > "$LOCKFILE"
}

# Helpers portables pour verrou (lock) / déverrouillage (unlock)
# Utilisation : lock <chemin> [timeout_seconds]
# Si `flock` est disponible il est privilégié, sinon on utilise un verrou par répertoire (mkdir).
lock() {
    local file="$1"
    local timeout="${2:-10}"

    if [[ -z "$file" ]]; then
        return 1
    fi

    if command -v flock >/dev/null 2>&1; then
        # Utilise un descripteur de fichier dédié pour maintenir le flock
        exec 200>"$file" || return 1
        local elapsed=0
        while ! flock -n 200; do
            sleep 1
            elapsed=$((elapsed+1))
            if (( elapsed >= timeout )); then
                return 2
            fi
        done
        return 0
    else
        # Repli : créer un répertoire de verrou (opération atomique sur les systèmes POSIX)
        local lockdir="${file}.lock"
        local elapsed_ms=0
        while ! mkdir "$lockdir" 2>/dev/null; do
            sleep 0.1
            elapsed_ms=$((elapsed_ms+1))
            if (( elapsed_ms >= timeout * 10 )); then
                return 2
            fi
        done
        printf "%s\n" "$$" > "$lockdir/pid" 2>/dev/null || true
        return 0
    fi
}

# Utilisation : unlock <chemin>
unlock() {
    local file="$1"
    if [[ -z "$file" ]]; then
        return 1
    fi

    if command -v flock >/dev/null 2>&1; then
        # Ferme le descripteur 200 si ouvert
        exec 200>&- 2>/dev/null || true
        return 0
    else
        local lockdir="${file}.lock"
        rm -rf "$lockdir" 2>/dev/null || true
        return 0
    fi
}

###########################################################
# VÉRIFICATIONS SYSTÈME
###########################################################

check_dependencies() {
    echo -e "${BLUE}Vérification de l'environnement...${NOCOLOR}"

    local missing_deps=()

    for cmd in ffmpeg ffprobe; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}ERREUR : Dépendances manquantes : ${missing_deps[*]}${NOCOLOR}"
        exit 1
    fi

    # Vérification de la version de ffmpeg (si disponible)
    local ffmpeg_version
    ffmpeg_version=$(ffmpeg -version 2>/dev/null | head -n1 | grep -oE 'version [0-9]+' | cut -d ' ' -f2 || true)

    if [[ -z "$ffmpeg_version" ]]; then
        echo -e "${YELLOW}⚠️  Impossible de déterminer la version de ffmpeg.${NOCOLOR}"
    else
        if [[ "$ffmpeg_version" =~ ^[0-9]+$ ]]; then
            if (( ffmpeg_version < FFMPEG_MIN_VERSION )); then
                 echo -e "${YELLOW}⚠️ ALERTE : Version FFMPEG ($ffmpeg_version) < Recommandee ($FFMPEG_MIN_VERSION).${NOCOLOR}"
            else
                 echo -e "   - FFMPEG Version : ${GREEN}$ffmpeg_version${NOCOLOR} (OK)"
            fi
        else
            echo -e "${YELLOW}⚠️  Version ffmpeg détectée : $ffmpeg_version${NOCOLOR}"
        fi
    fi

    if [[ ! -d "$SOURCE" ]]; then
        echo -e "${RED}ERREUR : Source '$SOURCE' introuvable.${NOCOLOR}"
        exit 1
    fi

    echo -e "   - Mode conversion : ${CYAN}$CONVERSION_MODE${NOCOLOR} (bitrate=${TARGET_BITRATE_KBPS}k, two-pass)"
    echo -e "${GREEN}Environnement validé.${NOCOLOR}"
}

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

validate_queue_file() {
    local queue_file="$1"
    
    if [[ ! -f "$queue_file" ]]; then
        echo -e "${RED}ERREUR : Le fichier queue '$queue_file' n'existe pas.${NOCOLOR}"
        return 1
    fi
    
    if [[ ! -s "$queue_file" ]]; then
        echo -e "${RED}ERREUR : Le fichier queue '$queue_file' est vide.${NOCOLOR}"
        return 1
    fi
    
    local file_count=$(count_null_separated "$queue_file")
    if [[ $file_count -eq 0 ]]; then
        echo -e "${RED}ERREUR : Le fichier queue n'a pas le format attendu (fichiers séparés par null).${NOCOLOR}"
        return 1
    fi
    
    local test_read=$(head -c 100 "$queue_file" | tr '\0' '\n' | head -1)
    if [[ -z "$test_read" ]] && [[ $file_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Le fichier queue semble valide ($file_count fichiers détectés).${NOCOLOR}"
    else
        echo -e "${GREEN}✅ Fichier queue validé ($file_count fichiers détectés).${NOCOLOR}"
    fi
    
    return 0
}

initialize_directories() {
    mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR"
    
    rm -f "$STOP_FLAG"
    
    # Créer les fichiers de log
    for log_file in "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS"; do
        touch "$log_file"
    done
    # Le log de comparaison dry-run n est créé que si on est en mode dry-run
    if [[ "$DRYRUN" == true ]]; then
        touch "$LOG_DRYRUN_COMPARISON"
    fi
}

###########################################################
# FONCTIONS UTILITAIRES
###########################################################

is_excluded() {
    local f="$1"
    # Utilise la regex pré-compilée pour une vérification O(1) au lieu de O(n)
    if [[ -n "$EXCLUDES_REGEX" ]] && [[ "$f" =~ $EXCLUDES_REGEX ]]; then
        return 0
    fi
    return 1
}

# Pure Bash - évite un fork vers sed
clean_number() {
    local val="${1//[!0-9]/}"
    echo "${val:-0}"
}

# custom_pv : remplacement simple et sûr pour les binaires de `pv` utilisant `dd` + interrogation
# de la taille de destination.
# Utilisation : custom_pv <src> <dst> [couleur]
# Remarques : utilise `dd` et `stat` ; affiche la progression sur `stderr` (colorée) et termine
# à 100% à la fin.

# Script AWK partagé pour l affichage de progression (évite la duplication)
# Arguments attendus: copied, total, start, now, width, color, nocolor, newline (0 ou 1)
readonly AWK_PROGRESS_SCRIPT='
function hr(bytes,   units,i,div,val){
    units[0]="B"; units[1]="KiB"; units[2]="MiB"; units[3]="GiB"; units[4]="TiB";
    val=bytes+0;
    for(i=4;i>=0;i--){ div = 2^(10*i); if(val>=div){ return sprintf("%.2f%s", val/div, units[i]) } }
    return sprintf("%dB", bytes);
}
function hms(secs,   s,h,m){ s=int(secs+0.5); h=int(s/3600); m=int((s%3600)/60); s=s%60; return sprintf("%d:%02d:%02d", h, m, s); }
BEGIN{
    elapsed = (now - start) + 0.0;
    if(elapsed <= 0) elapsed = 0.000001;
    speed = (copied / elapsed);
    pct = (total>0 ? int( (copied*100)/total ) : (newline ? 100 : 0));
    if(pct>100) pct=100;
    filled = int(pct * width / 100);
    bar="";
    for(i=0;i<filled;i++) bar=bar"=";
    if(filled<width) bar=bar">"; for(i=filled+1;i<width;i++) bar=bar" ";
    line = sprintf("%s [%5.2fGiB/s] [%s] %3d%% %s/%s", hms(elapsed), (speed/(1024*1024*1024)), bar, pct, sprintf("%6s", hr(copied)), sprintf("%6s", hr(total)));
    if (newline) {
        printf("\r\033[K%s%s%s\n", color, line, nocolor);
    } else {
        printf("\r\033[K%s%s%s", color, line, nocolor);
    }
    fflush();
}
'

custom_pv() {
    local src="$1"
    local dst="$2"
    local color="${3:-$CYAN}"

    if [[ ! -f "$src" ]]; then
        return 1
    fi

    local total copied start_ts current_ts dd_pid
    total=$(stat -c%s -- "$src" 2>/dev/null) || total=0
    if [[ $total -le 0 ]]; then
        # repli : copie simple
        dd if="$src" of="$dst" bs=4M status=none 2>/dev/null
        return $?
    fi

    rm -f -- "$dst" 2>/dev/null || true

    # Démarrer dd en arrière-plan
    dd if="$src" of="$dst" bs=4M status=none &
    dd_pid=$!

    start_ts=$(now_ts)

    # Interroger la progression pendant l exécution de dd
    while kill -0 "$dd_pid" 2>/dev/null; do
        copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
        current_ts=$(now_ts)

        # Afficher la progression (sans saut de ligne)
        awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" \
            -v width=40 -v color="$color" -v nocolor="$NOCOLOR" -v newline=0 \
            "$AWK_PROGRESS_SCRIPT" >&2

        sleep 0.5
    done

    wait "$dd_pid" 2>/dev/null || true

    # valeur finale (avec saut de ligne)
    copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
    current_ts=$(now_ts)
    awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" \
        -v width=40 -v color="$color" -v nocolor="$NOCOLOR" -v newline=1 \
        "$AWK_PROGRESS_SCRIPT" >&2

    return 0
}

###########################################################
# SYSTÈME DE SLOTS POUR PROGRESSION PARALLÈLE
###########################################################

# Répertoire pour les fichiers de verrouillage des slots
readonly SLOTS_DIR="/tmp/video_convert_slots_${EXECUTION_TIMESTAMP}"

# Acquerir un slot libre pour affichage de progression
# Usage: acquire_progress_slot
# Retourne le numero de slot (1 a PARALLEL_JOBS) sur stdout
acquire_progress_slot() {
    mkdir -p "$SLOTS_DIR" 2>/dev/null || true
    local max_slots=${PARALLEL_JOBS:-1}
    local slot=1
    while [[ $slot -le $max_slots ]]; do
        local slot_file="$SLOTS_DIR/slot_$slot"
        if mkdir "$slot_file" 2>/dev/null; then
            echo "$$" > "$slot_file/pid"
            echo "$slot"
            return 0
        fi
        ((slot++))
    done
    # Aucun slot libre, retourner 0 (mode dégradé)
    echo "0"
}

# Libérer un slot de progression
# Usage: release_progress_slot <slot_number>
release_progress_slot() {
    local slot="$1"
    if [[ -n "$slot" && "$slot" -gt 0 ]]; then
        rm -rf "$SLOTS_DIR/slot_$slot" 2>/dev/null || true
    fi
}

# Nettoyer tous les slots (appelé en fin de script)
cleanup_progress_slots() {
    rm -rf "$SLOTS_DIR" 2>/dev/null || true
}

# Preparer espace affichage pour les workers paralleles
# Usage: setup_progress_display
setup_progress_display() {
    local max_slots=${PARALLEL_JOBS:-1}
    if [[ "$max_slots" -gt 1 && "$NO_PROGRESS" != true ]]; then
        # Réserver des lignes vides pour chaque slot
        for ((i=1; i<=max_slots; i++)); do
            echo ""
        done
        # Ligne séparatrice
        echo -e "${CYAN}─────────────────────────────────────────────────────────────────────────${NOCOLOR}"
    fi
}

###########################################################
# GESTION PLEXIGNORE
###########################################################

check_plexignore() {
    local source_abs output_abs
    source_abs=$(readlink -f "$SOURCE")
    output_abs=$(readlink -f "$OUTPUT_DIR")
    local plexignore_file="$OUTPUT_DIR/.plexignore"

    # Vérifier si OUTPUT_DIR est un sous-dossier de SOURCE
    if [[ "$output_abs"/ != "$source_abs"/ ]] && [[ "$output_abs" = "$source_abs"/* ]]; then
        if [[ -f "$plexignore_file" ]]; then
            echo -e "${GREEN}\nℹ️  Fichier .plexignore déjà présent dans '$OUTPUT_DIR'. Aucune action requise.${NOCOLOR}"
            return 0
        fi

        echo ""
        read -r -p "Souhaitez-vous créer un fichier .plexignore dans '$OUTPUT_DIR' pour éviter les doublons sur Plex ? (O/n) " response

        case "$response" in
            [oO]|[yY]|'')
                echo "*" > "$plexignore_file"
                echo -e "${GREEN}✅ Fichier .plexignore créé dans '$OUTPUT_DIR' pour masquer les doublons.${NOCOLOR}"
                ;;
            [nN]|*)
                echo -e "${CYAN}⏭️  Création de .plexignore ignorée.${NOCOLOR}"
                ;;
        esac
    fi
}

###########################################################
# VÉRIFICATION DU SUFFIXE
###########################################################

check_output_suffix() {
    local source_abs output_abs is_same_dir=false
    source_abs=$(readlink -f "$SOURCE")
    output_abs=$(readlink -f "$OUTPUT_DIR")

    if [[ "$source_abs" == "$output_abs" ]]; then
        is_same_dir=true
    fi

    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        echo -e "${YELLOW}ℹ️  Option --no-suffix activée. Le suffixe est désactivé par commande.${NOCOLOR}"
    else
        # 1. Demande interactive (uniquement si l option force n est PAS utilisée)
        read -r -p "Voulez-vous utiliser le suffixe de sortie ('$SUFFIX_STRING') ? (O/n) " response
        
        case "$response" in
            [nN])
                SUFFIX_STRING=""
                echo -e "${YELLOW}⚠️  Le suffixe de sortie est désactivé.${NOCOLOR}"
                ;;
            *)
                echo -e "${GREEN}✅ Le suffixe de sortie ('${SUFFIX_STRING}') sera utilisé.${NOCOLOR}"
                ;;
        esac
    fi

    # 2. Vérification de sécurité critique
    if [[ -z "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
        # ALERTE : Pas de suffixe ET même répertoire = RISQUE D ÉCRASMENT
        echo -e "${MAGENTA}\n🚨 🚨 🚨 ALERTE CRITIQUE : RISQUE D'ÉCRASMENT 🚨 🚨 🚨${NOCOLOR}"
        echo -e "${MAGENTA}Votre dossier source et votre dossier de sortie sont IDENTIQUES ($source_abs).${NOCOLOR}"
        echo -e "${MAGENTA}L'absence de suffixe ENTRAÎNERA L'ÉCRASEMENT des fichiers originaux !${NOCOLOR}"
        
        if [[ "$DRYRUN" == true ]]; then
            echo -e "\n⚠️  (MODE DRY RUN) : Cette configuration vous permet de voir les noms de fichiers qui SERONT écrasés."
        fi
        
        read -r -p "Êtes-vous ABSOLUMENT sûr de vouloir continuer SANS suffixe dans le même répertoire ? (O/n) " final_confirm
        
        case "$final_confirm" in
            [oO]|[yY]|'')
                echo "Continuation SANS suffixe. Veuillez vérifier attentivement le Dry Run ou les logs."
                ;;
            *)
                echo "Opération annulée par l'utilisateur. Veuillez relancer en modifiant le suffixe ou le dossier de sortie."
                exit 1
                ;;
        esac
    
    # 3. Vérification de sécurité douce
    elif [[ -n "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
        # ATTENTION : Suffixe utilisé, mais toujours dans le même répertoire
        echo -e "${YELLOW}⚠️  ATTENTION : Les fichiers originaux et convertis vont COEXISTER dans le même répertoire.${NOCOLOR}"
        echo -e "${YELLOW}Si vous ne supprimez pas les originaux, assurez-vous que Plex gère correctement les doublons.${NOCOLOR}"
    fi
}

###########################################################
# VÉRIFICATION LIBRAIRIE VMAF
###########################################################

check_vmaf() {
    if [[ "$VMAF_ENABLED" != true ]]; then
        return 0
    fi
    
    if [[ "$HAS_LIBVMAF" -eq 1 ]]; then
        echo -e "${YELLOW}📊 Évaluation VMAF activée${NOCOLOR}"
    else
        echo -e "${RED}⚠️ Évaluation VMAF demandée mais libvmaf non disponible dans FFmpeg${NOCOLOR}"
        VMAF_ENABLED=false
    fi
}

###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
###########################################################

get_video_metadata() {
    local file="$1"
    local metadata_output
    
    # Récupération de toutes les métadonnées en une seule commande pour optimisation
    metadata_output=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS:format=bit_rate,duration \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null)
    
    # Parsing des résultats
    local bitrate_stream=$(echo "$metadata_output" | grep '^bit_rate=' | head -1 | cut -d'=' -f2)
    local bitrate_bps=$(echo "$metadata_output" | grep '^TAG:BPS=' | cut -d'=' -f2)
    local bitrate_container=$(echo "$metadata_output" | grep '^\[FORMAT\]' -A 10 | grep '^bit_rate=' | cut -d'=' -f2)
    local codec=$(echo "$metadata_output" | grep '^codec_name=' | cut -d'=' -f2)
    local duration=$(echo "$metadata_output" | grep '^duration=' | cut -d'=' -f2)
    
    # Nettoyage des valeurs
    bitrate_stream=$(clean_number "$bitrate_stream")
    bitrate_bps=$(clean_number "$bitrate_bps")
    bitrate_container=$(clean_number "$bitrate_container")
    
    # Détermination du bitrate prioritaire
    local bitrate=0
    if [[ -n "$bitrate_stream" ]]; then 
        bitrate="$bitrate_stream"
    elif [[ -n "$bitrate_bps" ]]; then 
        bitrate="$bitrate_bps"
    elif [[ -n "$bitrate_container" ]]; then 
        bitrate="$bitrate_container"
    fi
    
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then 
        bitrate=0
    fi
    
    if [[ -z "$duration" ]] || ! [[ "$duration" =~ ^[0-9.]+$ ]]; then 
        duration=1
    fi
    
    # Retour des valeurs séparées par des pipes
    echo "${bitrate}|${codec}|${duration}"
}

###########################################################
# LOGIQUE DE SKIP
###########################################################

should_skip_conversion() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    
    # --- Validation fichier vidéo ---
    if [[ -z "$codec" ]]; then
        echo -e "${BLUE}⏭️  SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
        return 0
    fi
    
    # Calcul de la tolérance en bits
    local base_threshold_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * SKIP_TOLERANCE_PERCENT * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))
    
    # Validation du format x265 et du bitrate
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            echo -e "${BLUE}⏭️  SKIPPED (Déjà x265 & bitrate optimisé) : $filename${NOCOLOR}" >&2
            if [[ -n "$LOG_SKIPPED" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà x265 et bitrate optimisé) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
            fi
            return 0
        fi
        if [[ -n "$LOG_PROGRESS" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage X265) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
        fi
    fi
    
    return 1
}

###########################################################
# SOUS-FONCTIONS DE CONSTRUCTION DE LA FILE D ATTENTE
###########################################################

_handle_custom_queue() {
    # Gestion du fichier queue personnalisé (Option -q)
    # Crée un INDEX à partir de la CUSTOM_QUEUE fournie
    if [[ -n "$CUSTOM_QUEUE" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo ""
            echo -e "${CYAN}📄 Utilisation du fichier queue personnalisé : $CUSTOM_QUEUE${NOCOLOR}"
        fi
        
        if ! validate_queue_file "$CUSTOM_QUEUE"; then
            exit 1
        fi
        
        # Convertir la CUSTOM_QUEUE (null-separated) en INDEX (taille\tchemin)
        # Calculer la taille pour chaque fichier
        tr '\0' '\n' < "$CUSTOM_QUEUE" | while read -r f; do
            echo -e "$(stat -c%s "$f")\t$f"
        done > "$INDEX"
        
        # Créer INDEX_READABLE
        cut -f2- "$INDEX" > "$INDEX_READABLE"
        
        return 0
    fi
    return 1
}

_handle_existing_index() {
    # Gestion de l INDEX existant (demande à l utilisateur si on doit le conserver)
    if [[ ! -f "$INDEX" ]]; then
        return 1
    fi
    
    local index_date=$(stat -c '%y' "$INDEX" | cut -d'.' -f1)
    # Si l utilisateur a demandé de conserver l index, on l accepte sans demander
    if [[ "$KEEP_INDEX" == true ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${YELLOW}Utilisation forcée de l'index existant (--keep-index activé).${NOCOLOR}"
        fi
        # Vérifier que l index n est pas vide
        if ! [[ -s "$INDEX" ]]; then 
            echo "Index vide, régénération nécessaire..."
            rm -f "$INDEX" "$INDEX_READABLE"
            return 1
        fi
        return 0
    fi
    if [[ "$NO_PROGRESS" != true ]]; then
        echo ""
        echo -e "${CYAN}  Un fichier index existant a été trouvé.${NOCOLOR}"
        echo -e "${CYAN}  Date de création : $index_date${NOCOLOR}"
        echo ""
    fi
    
    # Lire la réponse depuis le terminal pour éviter de consommer l entrée de xargs/cat
    read -r -p "Souhaitez-vous conserver ce fichier index ? (O/n) " response < /dev/tty
    
    case "$response" in
        [nN])
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "${YELLOW}Régénération d'un nouvel index...${NOCOLOR}"
            fi
            rm -f "$INDEX" "$INDEX_READABLE"
            return 1
            ;;
        *)
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "${YELLOW}Utilisation de l'index existant.${NOCOLOR}"
            fi
            
            # Vérifier que l index n est pas vide
            if ! [[ -s "$INDEX" ]]; then 
                echo "Index vide, régénération nécessaire..."
                rm -f "$INDEX" "$INDEX_READABLE"
                return 1
            fi
            
            return 0
            ;;
    esac
}

_count_total_video_files() {
    local exclude_dir_name="$1"
    
    # Calcul du nombre total de fichiers candidats (lent, mais nécessaire pour l affichage de progression)
    find "$SOURCE" \
        -wholename "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 2>/dev/null | \
    tr -cd '\0' | wc -c
}

_index_video_files() {
    local exclude_dir_name="$1"
    local total_files="$2"
    local queue_tmp="$3"
    local count_file="$4"
    
    # Deuxième passe : indexer les fichiers avec leur taille
    find "$SOURCE" \
        -wholename "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 | \
    while IFS= read -r -d $'\0' f; do
        if is_excluded "$f"; then continue; fi
        if [[ "$f" =~ \.(sh|txt)$ ]]; then continue; fi
        
        local count=$(($(cat "$count_file") + 1))
        echo "$count" > "$count_file"
        
        # Affichage de progression
        if [[ "$NO_PROGRESS" != true ]]; then
            printf "\rIndexation en cours... [%-${#total_files}d/${count}]" "$count" >&2
        fi
        
        # Stockage de la taille et du chemin (séparé par tab)
        echo -e "$(stat -c%s "$f")\t$f"
    done > "$queue_tmp"
}

_generate_index() {
    # Génération de l INDEX (fichier permanent contenant tous les fichiers indexés avec tailles)
    local exclude_dir_name=$OUTPUT_DIR

    if [[ "$NO_PROGRESS" != true ]]; then 
        echo "Indexation fichiers..." >&2
    fi
    
    # Première passe : compter le nombre total de fichiers vidéo candidats
    local total_files=$(_count_total_video_files "$exclude_dir_name")

    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${BLUE}📊 Total de fichiers vidéo trouvés : ${total_files}${NOCOLOR}"
    fi

    # Initialiser le compteur
    local count_file="$TMP_DIR/.index_count_$$"
    echo "0" > "$count_file"
    
    # Deuxième passe : indexer les fichiers (stockage taille + chemin)
    local index_tmp="$INDEX.tmp"
    _index_video_files "$exclude_dir_name" "$total_files" "$index_tmp" "$count_file"
    
    local final_count=$(cat "$count_file")
    rm -f "$count_file"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "\n${GREEN}✅ Indexation terminée [${final_count} fichiers répertoriés]${NOCOLOR}" >&2
    fi
    
    # Sauvegarder l INDEX (fichier permanent, non trié, format taille\tchemin)
    mv "$index_tmp" "$INDEX" 
    cut -f2- "$INDEX" > "$INDEX_READABLE"
}

_build_queue_from_index() {
    # Construction de la QUEUE à partir de l INDEX (fichier permanent)
    # Appliquer le mode de tri configuré via SORT_MODE
    case "$SORT_MODE" in
        size_desc)
            # Trier par taille décroissante (par défaut)
            sort -nrk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        size_asc)
            # Trier par taille croissante
            sort -nk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        name_asc)
            # Trier par nom de fichier ascendant (utilise la 2ème colonne : chemin)
            sort -t$'\t' -k2,2 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        name_desc)
            # Trier par nom de fichier descendant
            sort -t$'\t' -k2,2 -r "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        *)
            # Mode inconnu -> repli sur size_desc
            sort -nrk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
    esac
}


_apply_queue_limitations() {
    # APPLICATION DE LA LIMITATION (Unifiée, s applique à la queue prête, peu importe sa source)
    local limit_count=$LIMIT_FILES
    
    if [[ "$limit_count" -eq 0 ]]; then
        return 0
    fi
    
    # Affichage du message de limitation
    if [[ "$NO_PROGRESS" != true ]]; then
        if [[ "$RANDOM_MODE" == true ]]; then
            echo -e "${MAGENTA}LIMITATION (RANDOM) : Sélection aléatoire de $limit_count fichiers maximum.${NOCOLOR}"
        else
            echo -e "${MAGENTA}LIMITATION : Traitement de $limit_count fichiers maximum.${NOCOLOR}"
        fi
    fi
    
    local tmp_limit="$QUEUE.limit"
    local queue_content
    
    # Lire la queue (séparée par \0) et la convertir en lignes pour le traitement
    queue_content=$(tr '\0' '\n' < "$QUEUE")
    
    # Appliquer le tri (aléatoire si random) et la limite
    if [[ "$RANDOM_MODE" == true ]]; then
        # Mode RANDOM : Tri aléatoire puis limitation
        echo "$queue_content" | sort -R | head -n "$limit_count" | tr '\n' '\0' > "$tmp_limit"
    else
        # Mode Normal : Limitation du haut de la liste (déjà triée par taille décroissante)
        echo "$queue_content" | head -n "$limit_count" | tr '\n' '\0' > "$tmp_limit"
    fi
    
    mv "$tmp_limit" "$QUEUE"
}

_validate_queue_not_empty() {										   
    if ! [[ -s "$QUEUE" ]]; then
        echo "Aucun fichier à traiter trouvé (vérifiez les filtres ou la source)."
        exit 0
    fi
}

_display_random_mode_selection() {													
    if [[ "$RANDOM_MODE" != true ]] || [[ "$NO_PROGRESS" == true ]]; then
        return 0
    fi
    
    echo -e "\n${CYAN}📋 Fichiers sélectionnés aléatoirement : ${NOCOLOR}"
    tr '\0' '\n' < "$QUEUE" | nl -w2 -s'. '
    echo ""
}

_create_readable_queue_copy() {																							  
    tr '\0' '\n' < "$QUEUE" > "$LOG_DIR/Queue_readable_${EXECUTION_TIMESTAMP}.txt"
}

# Incrémenter le compteur de fichiers traités (thread-safe via lock)
# Incrémenter le compteur de fichiers traités (utilisé seulement en mode FIFO avec limite)
increment_processed_count() {
    # Ne rien faire si pas en mode FIFO (pas de limite)
    if [[ -z "${PROCESSED_COUNT_FILE:-}" ]] || [[ ! -f "${PROCESSED_COUNT_FILE:-}" ]]; then
        return 0
    fi
    
    local lockdir="$LOG_DIR/processed_count.lock"
    # Mutex simple via mkdir
    local attempts=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.05
        attempts=$((attempts + 1))
        if [[ $attempts -gt 100 ]]; then break; fi  # timeout 5s
    done
    
    local current=0
    if [[ -f "$PROCESSED_COUNT_FILE" ]]; then
        current=$(cat "$PROCESSED_COUNT_FILE" 2>/dev/null || echo 0)
    fi
    echo $((current + 1)) > "$PROCESSED_COUNT_FILE"
    
    rmdir "$lockdir" 2>/dev/null || true
}

# Quand un fichier est skip, ajouter le prochain candidat de la queue complète
# pour maintenir le nombre de fichiers demandés par --limit
update_queue() {
    # Ne rien faire si pas de limitation
    if [[ "$LIMIT_FILES" -le 0 ]]; then
        return 0
    fi
    
    # Vérifier que la FIFO existe
    if [[ -z "${WORKFIFO:-}" ]] || [[ ! -p "$WORKFIFO" ]]; then
        return 0
    fi

    local lockdir="$LOG_DIR/update_queue.lock"
    # Mutex simple via mkdir
    while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.01; done

    local nextpos=0
    if [[ -f "$NEXT_QUEUE_POS_FILE" ]]; then
        nextpos=$(cat "$NEXT_QUEUE_POS_FILE" 2>/dev/null) || nextpos=0
    fi
    local total=0
    if [[ -f "$TOTAL_QUEUE_FILE" ]]; then
        total=$(cat "$TOTAL_QUEUE_FILE" 2>/dev/null) || total=0
    fi

    if [[ $nextpos -lt $total ]]; then
        # Récupérer l élément suivant
        local candidate
        candidate=$(tr '\0' '\n' < "$QUEUE_FULL" | sed -n "$((nextpos+1))p") || candidate=""
        if [[ -n "$candidate" ]]; then
            # Incrémenter aussi target_count pour que le writer attende ce fichier supplémentaire
            local current_target=0
            if [[ -f "$TARGET_COUNT_FILE" ]]; then
                current_target=$(cat "$TARGET_COUNT_FILE" 2>/dev/null || echo 0)
            fi
            echo $((current_target + 1)) > "$TARGET_COUNT_FILE"
            
            # Ecrire le nouveau fichier dans la FIFO
            printf '%s\0' "$candidate" > "$WORKFIFO" || true
        fi
        echo $((nextpos + 1)) > "$NEXT_QUEUE_POS_FILE"
    fi

    rmdir "$lockdir" 2>/dev/null || true
}

###########################################################
# SOUS-FONCTIONS DE PRE-CONVERSION
###########################################################

_prepare_file_paths() {
    local file_original="$1"
    local output_dir="$2"
    
    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        return 1
    fi

    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")
    local final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"
    
    local effective_suffix="$SUFFIX_STRING"
    if [[ "$DRYRUN" == true ]]; then
        effective_suffix="${effective_suffix}${DRYRUN_SUFFIX}"
    fi

    local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
    
    echo "$filename|$final_dir|$base_name|$effective_suffix|$final_output"
}

_check_output_exists() {
    local file_original="$1"
    local filename="$2"
    local final_output="$3"
    
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        echo -e "${BLUE}⏭️  SKIPPED (Fichier de sortie existe déjà) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
        # Alimenter la queue avec le prochain candidat si limite active
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue || true
        fi
        return 0
    fi
    return 1
}

_handle_dryrun_mode() {
    local final_dir="$1"
    local final_output="$2"
    
    if [[ "$DRYRUN" == true ]]; then
        mkdir -p "$final_dir"
        touch "$final_output"
        return 0
    fi
    return 1
}

_get_temp_filename() {
    local file_original="$1"
    local suffix="$2"
    local md5p
    md5p=$(compute_md5_prefix "$file_original")
    echo "$TMP_DIR/tmp_${md5p}_${RANDOM}${suffix}"
}

# Calculer le checksum SHA256 d un fichier en utilisant les outils disponibles (portable)
compute_sha256() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo ""
        return 0
    fi

    if [[ "$HAS_SHA256SUM" -eq 1 ]]; then
        sha256sum -- "$file" | awk '{print $1}'
    elif [[ "$HAS_SHASUM" -eq 1 ]]; then
        shasum -a 256 -- "$file" | awk '{print $1}'
    elif [[ "$HAS_OPENSSL" -eq 1 ]]; then
        openssl dgst -sha256 -- "$file" | awk '{print $NF}'
    elif [[ "$HAS_PYTHON3" -eq 1 ]]; then
        python3 - <<PY "$file"
import sys,hashlib
with open(sys.argv[1],'rb') as fh:
    print(hashlib.sha256(fh.read()).hexdigest())
PY
    else
        # fallback: vide si aucun outil n est disponible
        echo ""
    fi
}

_setup_temp_files_and_logs() {
    local filename="$1"
    local file_original="$2"
    local final_dir="$3"
    
    mkdir -p "$final_dir" 2>/dev/null || true
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "▶️  Démarrage du fichier : $filename"
    fi
    if [[ -n "$LOG_PROGRESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
    fi
}

_check_disk_space() {
    local file_original="$1"
    
    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}' 2>/dev/null) || return 0
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERREUR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        return 1
    fi
    return 0
}

_analyze_video() {
    local file_original="$1"
    local filename="$2"
    
    local metadata
    metadata=$(get_video_metadata "$file_original")
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata"
    
    if should_skip_conversion "$codec" "$bitrate" "$filename" "$file_original"; then
        return 1
    fi
    
    echo "$bitrate|$codec|$duration_secs"
    return 0
}

_copy_to_temp_storage() {
    local file_original="$1"
    local filename="$2"
    local tmp_input="$3"
    local ffmpeg_log_temp="$4"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}→ Transfert de [$filename] vers dossier temporaire...${NOCOLOR}"
    else
        echo -e "${CYAN}→ $filename${NOCOLOR}"
    fi

    if ! custom_pv "$file_original" "$tmp_input" "$CYAN"; then
        echo -e "${RED}❌ ERREUR Impossible de déplacer (custom_pv) : $file_original${NOCOLOR}"
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR custom_pv copy failed | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null
        return 1
    fi

    return 0
}

###########################################################
# CONVERSION
###########################################################

_execute_conversion() {
    local tmp_input="$1"
    local tmp_output="$2"
    local ffmpeg_log_temp="$3"
    local duration_secs="$4"
    local base_name="$5"

    # Options de l encodage (principales) :
    #  -g 600               : taille GOP (nombre d images entre I-frames)
    #  -keyint_min 600      : intervalle minimum entre keyframes (force des I-frames régulières)
    #  -c:v libx265         : encodeur logiciel x265 (HEVC)
    #  -preset slow         : préréglage qualité/temps (lent = meilleure compression)
    #  -tune fastdecode     : optimiser l encodeur pour un décodage plus rapide
    #  -pix_fmt yuv420p10le : format de pixels YUV 4:2:0 en 10 bits

    # timestamp de depart portable
    START_TS="$(date +%s)"

    # Two-pass encoding : analyse puis encodage
    # Pass 1 : analyse rapide pour generer les statistiques
    # Pass 2 : encodage final avec repartition optimale du bitrate

    # Preparer les parametres
    local ff_bitrate="${TARGET_BITRATE_FFMPEG:-${TARGET_BITRATE_KBPS}k}"
    local ff_maxrate="${MAXRATE_FFMPEG:-${MAXRATE_KBPS}k}"
    local ff_bufsize="${BUFSIZE_FFMPEG:-${BUFSIZE_KBPS}k}"
    local x265_vbv="${X265_VBV_PARAMS:-vbv-maxrate=${MAXRATE_KBPS}:vbv-bufsize=${BUFSIZE_KBPS}}"
    
    # Fichier de stats pour two-pass (dans logs/2pass/)
    # Nom unique : hash du fichier + PID + RANDOM pour eviter conflits en parallele
    local stats_dir="${LOG_DIR}/2pass"
    mkdir -p "$stats_dir" 2>/dev/null || true
    local file_hash
    file_hash=$(compute_md5_prefix "$base_name")
    local stats_file_posix="${stats_dir}/x265_2pass_${file_hash}_${$}_${RANDOM}"

    # Script AWK adapte selon la disponibilite de systime() (gawk vs awk BSD)
    local awk_time_func
    if [[ "$HAS_GAWK" -eq 1 ]]; then
        awk_time_func='function get_time() { return systime() }'
    else
        awk_time_func='function get_time() { cmd="date +%s"; cmd | getline t; close(cmd); return t }'
    fi

    # Acquerir un slot pour affichage de progression en mode parallele
    local progress_slot=0
    local is_parallel=0
    if [[ "${PARALLEL_JOBS:-1}" -gt 1 ]]; then
        is_parallel=1
        progress_slot=$(acquire_progress_slot)
    fi

    # ==================== PASS 1 : ANALYSE ====================
    # Utiliser -passlogfile de ffmpeg (gere les chemins Windows correctement)
    local x265_params_pass1="pass=1:${x265_vbv}"
    
    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -hwaccel $HWACCEL \
        -i "$tmp_input" -pix_fmt yuv420p10le \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$ff_bitrate" -x265-params "$x265_params_pass1" \
        -passlogfile "$stats_file_posix" \
        -maxrate "$ff_maxrate" -bufsize "$ff_bufsize" \
        -an \
        -f null /dev/null \
        -progress pipe:1 -nostats 2> "${ffmpeg_log_temp}.pass1" | \
    awk -v DURATION="$duration_secs" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" -v MAX_SLOTS="${PARALLEL_JOBS:-1}" -v PASS_LABEL="Analyse" "
        $awk_time_func
        BEGIN {
            duration = DURATION + 0;
            if (duration < 1) exit;
            start = START + 0;
            last_update = 0;
            refresh_interval = 2;
            speed = 1;
            slot = SLOT + 0;
            is_parallel = PARALLEL + 0;
            max_slots = MAX_SLOTS + 0;
        }

        /out_time_us=/ {
            if (match(\$0, /[0-9]+/)) {
                current_time = substr(\$0, RSTART, RLENGTH) / 1000000;
            } else {
                current_time = 0;
            }

            percent = (current_time / duration) * 100;
            if (percent > 100) percent = 100;

            now = get_time();
            elapsed = now - start;
            speed = (elapsed > 0 ? current_time / elapsed : 1);
            remaining = duration - current_time;
            eta = (speed > 0 ? remaining / speed : 0);

            h = int(eta / 3600);
            m = int((eta % 3600) / 60);
            s = int(eta % 60);
            eta_str = sprintf(\"%02d:%02d:%02d\", h, m, s);

            bar_width = 20;
            filled = int(percent * bar_width / 100);
            bar = \"\";
            for (i = 0; i < filled; i++) bar = bar \"━\";
            for (i = filled; i < bar_width; i++) bar = bar \"┄\";

            if (NOPROG != \"true\" && (now - last_update >= refresh_interval || percent >= 99)) {
                if (is_parallel && slot > 0) {
                    lines_up = max_slots - slot + 2;
                    printf \"\\033[%dA\\r\\033[K  🔍 [%d] %-25.25s [%s] %5.1f%% | ETA: %s | x%.2f\\033[%dB\\r\",
                           lines_up, slot, CURRENT_FILE_NAME, bar, percent, eta_str, speed, lines_up > \"/dev/stderr\";
                } else {
                    printf \"\\r\\033[K  🔍 %-30.30s [%s] %5.1f%% | ETA: %s | x%.2f\",
                           CURRENT_FILE_NAME, bar, percent, eta_str, speed > \"/dev/stderr\";
                }
                fflush(\"/dev/stderr\");
                last_update = now;
            }
        }

        /progress=end/ {
            if (NOPROG != \"true\") {
                bar_complete = \"\";
                for (i = 0; i < 20; i++) bar_complete = bar_complete \"━\";
                if (is_parallel && slot > 0) {
                    lines_up = max_slots - slot + 2;
                    printf \"\\033[%dA\\r\\033[K  🔍 [%d] %-25.25s [%s] 100.0%% | Analyse OK\\033[%dB\\r\",
                           lines_up, slot, CURRENT_FILE_NAME, bar_complete, lines_up > \"/dev/stderr\";
                } else {
                    printf \"\\r\\033[K  🔍 %-30.30s [%s] 100.0%% | Analyse OK\\n\",
                           CURRENT_FILE_NAME, bar_complete > \"/dev/stderr\";
                }
                fflush(\"/dev/stderr\");
            }
        }
    "

    # Verifier le succes du pass 1
    local pass1_rc=${PIPESTATUS[0]:-0}
    if [[ "$pass1_rc" -ne 0 ]]; then
        echo -e "${RED}❌ Erreur lors de l'analyse (pass 1)${NOCOLOR}" >&2
        if [[ -f "${ffmpeg_log_temp}.pass1" ]]; then
            tail -n 40 "${ffmpeg_log_temp}.pass1" >&2 || true
        fi
        rm -f "$stats_file_posix" "${stats_file_posix}.cutree" "${ffmpeg_log_temp}.pass1" 2>/dev/null || true
        if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
            release_progress_slot "$progress_slot"
        fi
        return 1
    fi

    # ==================== PASS 2 : ENCODAGE ====================
    START_TS="$(date +%s)"
    local x265_params_pass2="pass=2:${x265_vbv}"

    $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -hwaccel $HWACCEL \
        -i "$tmp_input" -pix_fmt yuv420p10le \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -b:v "$ff_bitrate" -x265-params "$x265_params_pass2" \
        -passlogfile "$stats_file_posix" \
        -maxrate "$ff_maxrate" -bufsize "$ff_bufsize" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
    awk -v DURATION="$duration_secs" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" -v START="$START_TS" -v SLOT="$progress_slot" -v PARALLEL="$is_parallel" -v MAX_SLOTS="${PARALLEL_JOBS:-1}" "
        $awk_time_func
        BEGIN {
            duration = DURATION + 0;
            if (duration < 1) exit;
            start = START + 0;
            last_update = 0;
            refresh_interval = 2;
            speed = 1;
            slot = SLOT + 0;
            is_parallel = PARALLEL + 0;
            max_slots = MAX_SLOTS + 0;
        }

        /out_time_us=/ {
            if (match(\$0, /[0-9]+/)) {
                current_time = substr(\$0, RSTART, RLENGTH) / 1000000;
            } else {
                current_time = 0;
            }

            percent = (current_time / duration) * 100;
            if (percent > 100) percent = 100;

            now = get_time();
            elapsed = now - start;
            speed = (elapsed > 0 ? current_time / elapsed : 1);
            remaining = duration - current_time;
            eta = (speed > 0 ? remaining / speed : 0);

            h = int(eta / 3600);
            m = int((eta % 3600) / 60);
            s = int(eta % 60);
            eta_str = sprintf(\"%02d:%02d:%02d\", h, m, s);

            bar_width = 20;
            filled = int(percent * bar_width / 100);
            bar = \"\";
            for (i = 0; i < filled; i++) bar = bar \"█\";
            for (i = filled; i < bar_width; i++) bar = bar \"░\";

            if (NOPROG != \"true\" && (now - last_update >= refresh_interval || percent >= 99)) {
                if (is_parallel && slot > 0) {
                    lines_up = max_slots - slot + 2;
                    printf \"\\033[%dA\\r\\033[K  🎬 [%d] %-25.25s [%s] %5.1f%% | ETA: %s | x%.2f\\033[%dB\\r\",
                           lines_up, slot, CURRENT_FILE_NAME, bar, percent, eta_str, speed, lines_up > \"/dev/stderr\";
                } else {
                    printf \"\\r\\033[K  🎬 %-30.30s [%s] %5.1f%% | ETA: %s | x%.2f\",
                           CURRENT_FILE_NAME, bar, percent, eta_str, speed > \"/dev/stderr\";
                }
                fflush(\"/dev/stderr\");
                last_update = now;
            }
        }

        /progress=end/ {
            if (NOPROG != \"true\") {
                bar_complete = \"\";
                for (i = 0; i < 20; i++) bar_complete = bar_complete \"█\";
                if (is_parallel && slot > 0) {
                    lines_up = max_slots - slot + 2;
                    printf \"\\033[%dA\\r\\033[K  🎬 [%d] %-25.25s [%s] 100.0%% | Termine\\033[%dB\\r\",
                           lines_up, slot, CURRENT_FILE_NAME, bar_complete, lines_up > \"/dev/stderr\";
                } else {
                    printf \"\\r\\033[K  ✅ %-30.30s [%s] 100.0%% | Termine\\n\",
                           CURRENT_FILE_NAME, bar_complete > \"/dev/stderr\";
                }
                fflush(\"/dev/stderr\");
            }
        }
    "

    # Nettoyer les fichiers de stats
    rm -f "$stats_file_posix" "${stats_file_posix}.cutree" "${ffmpeg_log_temp}.pass1" 2>/dev/null || true

    # Liberer le slot de progression
    if [[ "$is_parallel" -eq 1 && "$progress_slot" -gt 0 ]]; then
        release_progress_slot "$progress_slot"
    fi

    # Recupere les codes de sortie du pipeline (0 = succes).
    local ffmpeg_rc=0
    local awk_rc=0
    if [[ ${#PIPESTATUS[@]} -ge 1 ]]; then
        ffmpeg_rc=${PIPESTATUS[0]:-0}
        awk_rc=${PIPESTATUS[1]:-0}
    fi

    if [[ "$ffmpeg_rc" -eq 0 && "$awk_rc" -eq 0 ]]; then
        return 0
    else
        if [[ -f "$ffmpeg_log_temp" ]]; then
            echo "--- Dernieres lignes du log ffmpeg ($ffmpeg_log_temp) ---" >&2
            tail -n 80 "$ffmpeg_log_temp" >&2 || true
            echo "--- Fin du log ffmpeg ---" >&2
        else
            echo "(Aucun fichier de log ffmpeg trouve: $ffmpeg_log_temp)" >&2
        fi
        return 1
    fi
}

###########################################################
# TRAITEMENT DE LA FILE d ATTENTE
###########################################################

# Préparer une queue dynamique (FIFO) pour le traitement parallèle
# Traitement simple sans FIFO (quand pas de limite)
_process_queue_simple() {
    local nb_files=0
    if [[ -f "$QUEUE" ]]; then
        nb_files=$(count_null_separated "$QUEUE")
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}Démarrage du traitement ($nb_files fichiers)...${NOCOLOR}"
        # Reserver espace affichage pour les workers paralleles
        setup_progress_display
    fi
    
    # Lire la queue et traiter en parallele
    local file
    local -a _pids=()
    while IFS= read -r -d '' file; do
        convert_file "$file" "$OUTPUT_DIR" &
        _pids+=("$!")
        if [[ "${#_pids[@]}" -ge "$PARALLEL_JOBS" ]]; then
            if ! wait -n 2>/dev/null; then
                wait "${_pids[0]}" 2>/dev/null || true
            fi
            local -a _still=()
            for p in "${_pids[@]}"; do
                if kill -0 "$p" 2>/dev/null; then
                    _still+=("$p")
                fi
            done
            _pids=("${_still[@]}")
        fi
    done < "$QUEUE"
    
    # Attendre tous les jobs restants
    for p in "${_pids[@]}"; do
        wait "$p" || true
    done
    
    wait 2>/dev/null || true
    sleep 1
}

# Traitement avec FIFO (quand limite active - permet le remplacement dynamique)
_process_queue_with_fifo() {
    WORKFIFO="$LOG_DIR/queue_fifo_${EXECUTION_TIMESTAMP}"
    FIFO_WRITER_PID="$LOG_DIR/fifo_writer_pid_${EXECUTION_TIMESTAMP}"
    FIFO_WRITER_READY="$LOG_DIR/fifo_writer.ready_${EXECUTION_TIMESTAMP}"
    
    # Fichier compteur : nombre de fichiers traités (succès + erreur + skip)
    PROCESSED_COUNT_FILE="$LOG_DIR/processed_count_${EXECUTION_TIMESTAMP}"
    echo "0" > "$PROCESSED_COUNT_FILE"
    export PROCESSED_COUNT_FILE
    
    # Queue complète et position pour alimentation dynamique
    QUEUE_FULL="$QUEUE.full"
    NEXT_QUEUE_POS_FILE="$LOG_DIR/next_queue_pos_${EXECUTION_TIMESTAMP}"
    TOTAL_QUEUE_FILE="$LOG_DIR/total_queue_${EXECUTION_TIMESTAMP}"
    
    # Calculer le total de la queue complète
    local total_full=0
    if [[ -f "$QUEUE_FULL" ]]; then
        total_full=$(count_null_separated "$QUEUE_FULL")
    fi
    echo "$total_full" > "$TOTAL_QUEUE_FILE"
    
    # Nombre de fichiers à traiter (queue limitée)
    local target_count=0
    if [[ -f "$QUEUE" ]]; then
        target_count=$(count_null_separated "$QUEUE")
    fi
    # Position initiale = nombre de fichiers déjà dans la queue limitée
    echo "$target_count" > "$NEXT_QUEUE_POS_FILE"
    
    # Fichier cible pour le writer
    TARGET_COUNT_FILE="$LOG_DIR/target_count_${EXECUTION_TIMESTAMP}"
    echo "$target_count" > "$TARGET_COUNT_FILE"
    export TARGET_COUNT_FILE QUEUE_FULL NEXT_QUEUE_POS_FILE TOTAL_QUEUE_FILE WORKFIFO

    # Créer le FIFO et lancer un writer de fond
    rm -f "$WORKFIFO" 2>/dev/null || true
    mkfifo "$WORKFIFO"
    
    # Writer : écrit la queue initiale puis attend que tous les fichiers soient traités
    (
        exec 3<> "$WORKFIFO"
        # Écrire le contenu initial (NUL séparés)
        if [[ -f "$QUEUE" ]]; then
            cat "$QUEUE" >&3
        fi
        # Signaler prêt
        touch "$FIFO_WRITER_READY" 2>/dev/null || true
        
        # Attendre que le nombre de fichiers traités atteigne la cible
        while [[ ! -f "$STOP_FLAG" ]]; do
            local processed=0
            if [[ -f "$PROCESSED_COUNT_FILE" ]]; then
                processed=$(cat "$PROCESSED_COUNT_FILE" 2>/dev/null || echo 0)
            fi
            local target=$target_count
            if [[ -f "$TARGET_COUNT_FILE" ]]; then
                target=$(cat "$TARGET_COUNT_FILE" 2>/dev/null || echo "$target_count")
            fi
            
            if [[ "$processed" -ge "$target" ]]; then
                break
            fi
            sleep 0.5
        done
        exec 3>&-
    ) &
    printf "%d" "$!" > "$FIFO_WRITER_PID" 2>/dev/null || true
    
    # Traitement des fichiers
    local nb_files=$target_count
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}Démarrage du traitement ($nb_files fichiers)...${NOCOLOR}"
        # Reserver espace affichage pour les workers paralleles
        setup_progress_display
    fi
    
    # Consumer : lire les noms de fichiers separes par NUL et lancer les conversions en parallele
    _consumer_run() {
        local file
        local -a _pids=()
        while IFS= read -r -d '' file; do
            convert_file "$file" "$OUTPUT_DIR" &
            _pids+=("$!")
            if [[ "${#_pids[@]}" -ge "$PARALLEL_JOBS" ]]; then
                if ! wait -n 2>/dev/null; then
                    wait "${_pids[0]}" 2>/dev/null || true
                fi
                local -a _still=()
                for p in "${_pids[@]}"; do
                    if kill -0 "$p" 2>/dev/null; then
                        _still+=("$p")
                    fi
                done
                _pids=("${_still[@]}")
            fi
        done < "$WORKFIFO"
        for p in "${_pids[@]}"; do
            wait "$p" || true
        done
    }
    _consumer_run &
    local consumer_pid=$!

    # Attendre que le consumer termine
    wait "$consumer_pid" 2>/dev/null || true
    
    # Signaler au writer FIFO qu il doit se terminer
    touch "$STOP_FLAG" 2>/dev/null || true
    
    # Si un writer a enregistré son PID, demander son arrêt proprement
    if [[ -n "${FIFO_WRITER_PID:-}" ]] && [[ -f "${FIFO_WRITER_PID}" ]]; then
        local _writer_pid
        _writer_pid=$(cat "$FIFO_WRITER_PID" 2>/dev/null || echo "")
        if [[ -n "$_writer_pid" ]] && [[ "$_writer_pid" != "" ]]; then
            kill "$_writer_pid" 2>/dev/null || true
            wait "$_writer_pid" 2>/dev/null || true
        fi
    fi

    # Nettoyer les artefacts FIFO
    rm -f "$WORKFIFO" "$FIFO_WRITER_PID" "$FIFO_WRITER_READY" 2>/dev/null || true
    rm -f "$PROCESSED_COUNT_FILE" "$TARGET_COUNT_FILE" 2>/dev/null || true
    rm -f "$NEXT_QUEUE_POS_FILE" "$TOTAL_QUEUE_FILE" 2>/dev/null || true
    
    # Tentative de terminaison des processus enfants éventuels restants
    _reap_children() {
        local children=""
        if command -v pgrep >/dev/null 2>&1; then
            children=$(pgrep -P $$ 2>/dev/null || true)
        elif ps -o pid=,ppid= >/dev/null 2>&1; then
            children=$(ps -o pid=,ppid= | awk -v p=$$ '$2==p {print $1}' || true)
        fi
        for c in $children; do
            if [[ -n "$c" ]] && [[ "$c" != "$$" ]]; then
                kill "$c" 2>/dev/null || true
                wait "$c" 2>/dev/null || true
            fi
        done
    }
    _reap_children 2>/dev/null || true

    wait 2>/dev/null || true
    sleep 1
}

# Point d entrée : choisit le mode de traitement selon la présence d une limite
prepare_dynamic_queue() {
    if [[ "$LIMIT_FILES" -gt 0 ]]; then
        # Mode FIFO : permet le remplacement dynamique des fichiers skippés
        _process_queue_with_fifo
    else
        # Mode simple : traitement direct sans overhead FIFO
        _process_queue_simple
    fi
}

###########################################################
# CONSTRUCTION DE LA FILE D ATTENTE
###########################################################

build_queue() {
    # Étape 1 : Gestion de l INDEX (source de vérité)
    # Priorité 1 : Utiliser une queue personnalisée (crée INDEX)
    if _handle_custom_queue; then
        :
    # Priorité 2 : Réutiliser l INDEX existant (avec demande à l utilisateur)
    elif _handle_existing_index; then
        # L INDEX existant a été accepté, rien à faire
        :
    # Priorité 3 : Générer un nouvel INDEX
    else
        _generate_index
    fi
    
    # Étape 2 : Construire la QUEUE à partir de l INDEX (tri par taille décroissante)
    _build_queue_from_index
    
    # Sauvegarder la queue complète avant limitation (pour alimentation dynamique)
    cp -f "$QUEUE" "$QUEUE.full" 2>/dev/null || true
    
    # Étape 3 : Appliquer les limitations (limit, random)
    _apply_queue_limitations
    
    # Étape 4 : Finalisation et validation
    _validate_queue_not_empty
    _display_random_mode_selection
    _create_readable_queue_copy
}

###########################################################
# FONCTION DE CONVERSION PRINCIPALE
###########################################################

convert_file() {
    set -o pipefail

    local file_original="$1"
    local output_dir="$2"
    
    local path_info
    path_info=$(_prepare_file_paths "$file_original" "$output_dir") || return 1
    
    IFS='|' read -r filename final_dir base_name effective_suffix final_output <<< "$path_info"
    
    if _check_output_exists "$file_original" "$filename" "$final_output"; then
        increment_processed_count || true
        return 0
    fi
    
    if _handle_dryrun_mode "$final_dir" "$final_output"; then
        increment_processed_count || true
        return 0
    fi
    
    local tmp_input=$(_get_temp_filename "$file_original" ".in")
    local tmp_output=$(_get_temp_filename "$file_original" ".out.mkv")
    local ffmpeg_log_temp=$(_get_temp_filename "$file_original" "_err.log")
    
    _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    
    _check_disk_space "$file_original" || return 1
    
    local metadata_info
    if ! metadata_info=$(_analyze_video "$file_original" "$filename"); then
        # Analyse a indiqué qu on doit skip ce fichier
        increment_processed_count || true
        return 0
    fi
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata_info"
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')
    
    _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp" || return 1
    
    if _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$sizeBeforeMB"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
    fi
    
    # Incrémenter le compteur de fichiers traités (signal pour le FIFO writer)
    increment_processed_count || true
}

###########################################################
# ANALYSE VMAF
###########################################################

# Calcul du score VMAF (qualité vidéo perceptuelle)
# Usage : compute_vmaf_score <fichier_original> <fichier_converti> [filename_display]
# Retourne le score VMAF moyen (0-100) ou "NA" si indisponible
compute_vmaf_score() {
    local original="$1"
    local converted="$2"
    local filename_display="${3:-}"
    
    # Vérifier que libvmaf est disponible
    if [[ "$HAS_LIBVMAF" -ne 1 ]]; then
        echo "NA"
        return 0
    fi
    
    # Vérifier que les deux fichiers existent
    if [[ ! -f "$original" ]] || [[ ! -f "$converted" ]]; then
        echo "NA"
        return 0
    fi
    
    # Fichiers temporaires dans logs/vmaf/
    local vmaf_dir="${LOG_DIR}/vmaf"
    mkdir -p "$vmaf_dir" 2>/dev/null || true
    local file_hash
    file_hash=$(compute_md5_prefix "$filename_display")
    local vmaf_log_file="${vmaf_dir}/vmaf_${file_hash}_${$}_${RANDOM}.json"
    local progress_file="${vmaf_dir}/vmaf_progress_$$.txt"
    
    # Obtenir la durée totale de la vidéo en microsecondes pour la progression
    local duration_us=0
    local duration_str
    duration_str=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$converted" 2>/dev/null)
    if [[ -n "$duration_str" ]]; then
        # Convertir en microsecondes (durée est en secondes avec décimales)
        duration_us=$(awk "BEGIN {printf \"%.0f\", $duration_str * 1000000}")
    fi
    
    # Calculer le score VMAF avec subsampling (1 frame sur 5 pour accélérer)
    # n_subsample=5 : analyse seulement 20% des frames (5x plus rapide)
    if [[ "$NO_PROGRESS" != true ]] && [[ "$duration_us" -gt 0 ]] && [[ -n "$filename_display" ]]; then
        # Lancer ffmpeg en arrière-plan avec progression vers fichier
        ffmpeg -hide_banner -nostdin -i "$converted" -i "$original" \
            -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=$vmaf_log_file:n_subsample=5" \
            -progress "$progress_file" \
            -f null - >/dev/null 2>&1 &
        local ffmpeg_pid=$!
        
        local last_percent=-1
        # Afficher la progression en lisant le fichier (écrire sur /dev/tty pour éviter capture)
        while kill -0 "$ffmpeg_pid" 2>/dev/null; do
            if [[ -f "$progress_file" ]]; then
                local out_time_us
                out_time_us=$(grep -o 'out_time_us=[0-9]*' "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2)
                if [[ -n "$out_time_us" ]] && [[ "$out_time_us" =~ ^[0-9]+$ ]] && [[ "$out_time_us" -gt 0 ]]; then
                    local percent=$((out_time_us * 100 / duration_us))
                    [[ $percent -gt 100 ]] && percent=100
                    # Afficher seulement si le pourcentage a changé
                    if [[ "$percent" -ne "$last_percent" ]]; then
                        last_percent=$percent
                        # Barre de progression
                        local filled=$((percent / 5))
                        local empty=$((20 - filled))
                        local bar=""
                        for ((i=0; i<filled; i++)); do bar+="█"; done
                        for ((i=0; i<empty; i++)); do bar+="░"; done
                        # Tronquer le titre a 30 caracteres max
                        local short_name="$filename_display"
                        if [[ ${#short_name} -gt 30 ]]; then
                            short_name="${short_name:0:27}..."
                        fi
                        # Ecrire sur stderr (fd 2) pour eviter capture par $()
                        printf "\r    %-30s \033[0;36mVMAF\033[0m [%s] %3d%%" "$short_name" "$bar" "$percent" >&2
                    fi
                fi
            fi
            sleep 0.2
        done
        wait "$ffmpeg_pid" 2>/dev/null
        printf "\r%100s\r" "" >&2  # Effacer la ligne de progression
    else
        # Sans barre de progression
        ffmpeg -hide_banner -nostdin -i "$converted" -i "$original" \
            -lavfi "[0:v][1:v]libvmaf=log_fmt=json:log_path=$vmaf_log_file:n_subsample=5" \
            -f null - >/dev/null 2>&1
    fi
    
    # Nettoyer le fichier de progression
    rm -f "$progress_file" 2>/dev/null || true
    
    # Extraire le score VMAF depuis le fichier JSON
    local vmaf_score=""
    if [[ -f "$vmaf_log_file" ]] && [[ -s "$vmaf_log_file" ]]; then
        vmaf_score=$(grep -o '"mean"[[:space:]]*:[[:space:]]*[0-9.]*' "$vmaf_log_file" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Nettoyer le fichier temporaire
    rm -f "$vmaf_log_file" 2>/dev/null || true
    
    if [[ -n "$vmaf_score" ]]; then
        # Arrondir à 2 décimales
        printf "%.2f" "$vmaf_score"
    else
        echo "NA"
    fi
}

# Enregistrer une paire de fichiers pour analyse VMAF ultérieure
# Usage : _queue_vmaf_analysis <fichier_original> <fichier_converti>
# Les analyses seront effectuées à la fin de toutes les conversions
_queue_vmaf_analysis() {
    local file_original="$1"
    local final_actual="$2"
    
    # Verifier que evaluation VMAF est activee
    if [[ "$VMAF_ENABLED" != true ]]; then
        return 0
    fi
    
    # Vérifier que libvmaf est disponible
    if [[ "$HAS_LIBVMAF" -ne 1 ]]; then
        return 0
    fi
    
    # Vérifier que les deux fichiers existent
    if [[ ! -f "$file_original" ]] || [[ ! -f "$final_actual" ]]; then
        return 0
    fi
    
    # Enregistrer la paire dans le fichier de queue (format: original|converti)
    echo "${file_original}|${final_actual}" >> "$VMAF_QUEUE_FILE" 2>/dev/null || true
}

# Traiter toutes les analyses VMAF en attente
# Appelé à la fin de toutes les conversions, avant le résumé
process_vmaf_queue() {
    if [[ ! -f "$VMAF_QUEUE_FILE" ]] || [[ ! -s "$VMAF_QUEUE_FILE" ]]; then
        return 0
    fi
    
    local vmaf_count
    vmaf_count=$(wc -l < "$VMAF_QUEUE_FILE" 2>/dev/null | tr -d ' ') || vmaf_count=0
    
    if [[ "$vmaf_count" -eq 0 ]]; then
        return 0
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo ""
        echo -e "${MAGENTA}📊 Analyse VMAF de $vmaf_count fichier(s)...${NOCOLOR}"
    fi
    
    local current=0
    while IFS='|' read -r file_original final_actual; do
        ((current++)) || true
        
        # Vérifier que les fichiers existent toujours
        if [[ ! -f "$file_original" ]] || [[ ! -f "$final_actual" ]]; then
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "  ${YELLOW}⚠${NOCOLOR} [$current/$vmaf_count] Fichier(s) introuvable(s), ignoré"
            fi
            continue
        fi
        
        local filename
        filename=$(basename "$final_actual")
        
        # Calculer le score VMAF (avec barre de progression intégrée)
        local vmaf_score
        vmaf_score=$(compute_vmaf_score "$file_original" "$final_actual" "$filename")
        
        # Interpréter le score VMAF
        local vmaf_quality=""
        if [[ "$vmaf_score" != "NA" ]]; then
            local vmaf_int=${vmaf_score%.*}
            if [[ "$vmaf_int" -ge 90 ]]; then
                vmaf_quality="EXCELLENT"
            elif [[ "$vmaf_int" -ge 80 ]]; then
                vmaf_quality="TRES_BON"
            elif [[ "$vmaf_int" -ge 70 ]]; then
                vmaf_quality="BON"
            else
                vmaf_quality="DEGRADE"
            fi
        fi
        
        # Logger le score VMAF
        if [[ -n "$LOG_SUCCESS" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | VMAF | $file_original → $final_actual | score:${vmaf_score} | quality:${vmaf_quality:-NA}" >> "$LOG_SUCCESS" 2>/dev/null || true
        fi
        
        if [[ "$NO_PROGRESS" != true ]]; then
            local status_icon="${GREEN}✓${NOCOLOR}"
            if [[ "$vmaf_score" == "NA" ]]; then
                status_icon="${YELLOW}?${NOCOLOR}"
            elif [[ "$vmaf_quality" == "DEGRADE" ]]; then
                status_icon="${RED}✗${NOCOLOR}"
            fi
            # Tronquer le nom de fichier a 30 caracteres pour aligner
            local short_fn="$filename"
            if [[ ${#short_fn} -gt 30 ]]; then
                short_fn="${short_fn:0:27}..."
            fi
            printf "\r  %s [%d/%d] %-30s : %s (%s)%20s\n" "$status_icon" "$current" "$vmaf_count" "$short_fn" "$vmaf_score" "${vmaf_quality:-NA}" "" >&2
        fi
        
    done < "$VMAF_QUEUE_FILE"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${GREEN}✅ Analyses VMAF terminées${NOCOLOR}"
    fi
    
    # Nettoyer le fichier de queue
    rm -f "$VMAF_QUEUE_FILE" 2>/dev/null || true
}

###########################################################
# RESULTATS ET FINALISATION
###########################################################

# Essayer de déplacer le fichier produit vers la destination finale.
# Renvoie le chemin réel utilisé pour le fichier final sur stdout.
# Usage : _finalize_try_move <tmp_output> <final_output> <file_original>
_finalize_try_move() {
    local tmp_output="$1"
    local final_output="$2"
    local file_original="$3"

    local max_try=3
    local try=0

    # Tentative mv (3 essais)
    while [[ $try -lt $max_try ]]; do
        if mv "$tmp_output" "$final_output" 2>/dev/null; then
            printf "%s" "$final_output"
            return 0
        fi
        try=$((try+1))
        sleep 2
    done

    # Essayer cp + rm (3 essais)
    try=0
    while [[ $try -lt $max_try ]]; do
        if cp "$tmp_output" "$final_output" 2>/dev/null; then
            rm -f "$tmp_output" 2>/dev/null || true
            printf "%s" "$final_output"
            return 0
        fi
        try=$((try+1))
        sleep 2
    done

    # Repli local : dossier fallback
    local local_fallback_dir="${FALLBACK_DIR:-$HOME/Conversion_failed_uploads}"
    mkdir -p "$local_fallback_dir" 2>/dev/null || true
    if mv "$tmp_output" "$local_fallback_dir/" 2>/dev/null; then
        printf "%s" "$local_fallback_dir/$(basename "$final_output")"
        return 0
    fi
    if cp "$tmp_output" "$local_fallback_dir/" 2>/dev/null; then
        rm -f "$tmp_output" 2>/dev/null || true
        printf "%s" "$local_fallback_dir/$(basename "$final_output")"
        return 0
    fi

    # Ultime repli : laisser le temporaire et l utiliser
    printf "%s" "$tmp_output"
    return 2
}

# Nettoyage local des artefacts temporaires et calculs de taille/checksum.
# Usage : _finalize_log_and_verify <file_original> <final_actual> <tmp_input> <ffmpeg_log_temp> <checksum_before> <sizeBeforeMB> <sizeBeforeBytes>
_finalize_log_and_verify() {
    local file_original="$1"
    local final_actual="$2"
    local tmp_input="$3"
    local ffmpeg_log_temp="$4"
    local checksum_before="$5"
    local sizeBeforeMB="$6"
    local sizeBeforeBytes="${7:-0}"

    # Nettoyer les artefacts temporaires liés à l entrée et au log ffmpeg
    rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null || true

    # Taille après (en MB et en octets)
    local sizeAfterMB=0 sizeAfterBytes=0
    if [[ -e "$final_actual" ]]; then
        sizeAfterMB=$(du -m "$final_actual" 2>/dev/null | awk '{print $1}') || sizeAfterMB=0
        # Taille exacte en octets (stat -c%s sur Linux, stat -f%z sur macOS)
        sizeAfterBytes=$(stat -c%s "$final_actual" 2>/dev/null || stat -f%z "$final_actual" 2>/dev/null || echo 0)
    fi

    local size_comparison="${sizeBeforeMB}MB → ${sizeAfterMB}MB"

    if [[ "$sizeAfterMB" -ge "$sizeBeforeMB" ]]; then
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: FICHIER PLUS LOURD ($size_comparison). | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
    fi

    # Log success
    if [[ -n "$LOG_SUCCESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file_original → $final_actual | $size_comparison" >> "$LOG_SUCCESS" 2>/dev/null || true
    fi

    # Vérification d intégrité : d abord comparer la taille exacte (rapide), puis checksum si nécessaire
    local verify_status="OK"
    local checksum_after=""
    
    if [[ "$sizeBeforeBytes" -gt 0 && "$sizeAfterBytes" -gt 0 && "$sizeBeforeBytes" -ne "$sizeAfterBytes" ]]; then
        # Taille différente = transfert incomplet ou corrompu
        verify_status="SIZE_MISMATCH"
    elif [[ -n "$checksum_before" ]]; then
        # Taille identique, vérifier le checksum
        checksum_after=$(compute_sha256 "$final_actual" 2>/dev/null || echo "")
        if [[ -z "$checksum_after" ]]; then
            verify_status="NO_CHECKSUM"
        elif [[ "$checksum_before" != "$checksum_after" ]]; then
            verify_status="MISMATCH"
        fi
    elif [[ -z "$checksum_before" ]]; then
        verify_status="SKIPPED"
    fi

    # Écrire uniquement dans les logs : VERIFY
    if [[ -n "$LOG_SUCCESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | VERIFY | $file_original → $final_actual | size:${sizeBeforeBytes}B->${sizeAfterBytes}B | checksum:${checksum_before:-NA}/${checksum_after:-NA} | status:${verify_status}" >> "$LOG_SUCCESS" 2>/dev/null || true
    fi

    # Enregistrer pour analyse VMAF ultérieure (sera traité après toutes les conversions)
    _queue_vmaf_analysis "$file_original" "$final_actual"

    # En cas de problème, journaliser dans le log d erreur
    if [[ "$verify_status" == "MISMATCH" || "$verify_status" == "SIZE_MISMATCH" ]]; then
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ${verify_status} | $file_original -> $final_actual | size:${sizeBeforeBytes}B->${sizeAfterBytes}B | checksum:${checksum_before:-NA}/${checksum_after:-NA}" >> "$LOG_ERROR" 2>/dev/null || true
        fi
    fi
}

# Fonction principale de finalisation (regroupe l affichage, le déplacement, le logging)
_finalize_conversion_success() {
    local filename="$1"
    local file_original="$2"
    local tmp_input="$3"
    local tmp_output="$4"
    local final_output="$5"
    local ffmpeg_log_temp="$6"
    local sizeBeforeMB="$7"

    # Si un marqueur d arrêt global existe, ne pas finaliser (message déjà affiché par cleanup)
    if [[ -f "$STOP_FLAG" ]]; then
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null || true
        return 1
    fi

    if [[ "$NO_PROGRESS" != true ]]; then
        # Calculer la durée écoulée depuis le début de la conversion (START_TS défini avant l appel à ffmpeg)
        local elapsed_str="N/A"
        if [[ -n "${START_TS:-}" ]]; then
            local end_ts
            end_ts=$(date +%s)
            local elapsed=$((end_ts - START_TS))
            local eh=$((elapsed / 3600))
            local em=$(((elapsed % 3600) / 60))
            local es=$((elapsed % 60))
            elapsed_str=$(printf "%02d:%02d:%02d" "$eh" "$em" "$es")
        fi

        echo -e "  ${GREEN}✅ Fichier converti : $filename (durée: ${elapsed_str})${NOCOLOR}"
    fi

    # checksum et taille exacte avant déplacement (pour vérification intégrité)
    local checksum_before sizeBeforeBytes
    checksum_before=$(compute_sha256 "$tmp_output" 2>/dev/null || echo "")
    sizeBeforeBytes=$(stat -c%s "$tmp_output" 2>/dev/null || stat -f%z "$tmp_output" 2>/dev/null || echo 0)

    # Déplacer / copier / fallback et récupérer le chemin réel
    local final_actual
    final_actual=$(_finalize_try_move "$tmp_output" "$final_output" "$file_original") || true

    # Nettoyage, logs et vérifications
    _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "$checksum_before" "$sizeBeforeMB" "$sizeBeforeBytes"
}

_finalize_conversion_error() {
    local filename="$1"
    local file_original="$2"
    local tmp_input="$3"
    local tmp_output="$4"
    local ffmpeg_log_temp="$5"
    
    if [[ ! -f "$STOP_FLAG" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "  ${RED}❌ Échec de la conversion : $filename${NOCOLOR}"
        fi
    fi
    if [[ -n "$LOG_ERROR" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR" 2>/dev/null || true
        if [[ -n "$ffmpeg_log_temp" ]] && [[ -f "$ffmpeg_log_temp" ]] && [[ -s "$ffmpeg_log_temp" ]]; then
            cat "$ffmpeg_log_temp" >> "$LOG_ERROR" 2>/dev/null || true
        else
            echo "(Log d'erreur : ffmpeg_log_temp='$ffmpeg_log_temp' exists=$([ -f "$ffmpeg_log_temp" ] && echo 'OUI' || echo 'NON'))" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        echo "-------------------------------" >> "$LOG_ERROR" 2>/dev/null || true
    fi
    rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
}


###########################################################
# DRY RUN AVANCÉ (Comparaison et Anomalies de nommage)
###########################################################

dry_run_compare_names() {
    local TTY_DEV="/dev/tty"
    local LOG_FILE="$LOG_DRYRUN_COMPARISON"

    echo ""
    read -r -p "Souhaitez-vous afficher la comparaison entre les noms de fichiers originaux et générés ? (O/n) " response
    
    case "$response" in
        [oO]|[yY]|'')
            {
                echo ""
                echo "-------------------------------------------"
                echo "      SIMULATION DES NOMS DE FICHIERS"
                echo "-------------------------------------------"
            } | tee -a "$LOG_FILE"
            
            local total_files=$(count_null_separated "$QUEUE")
            local count=0
            local anomaly_count=0
            
            while IFS= read -r -d $'\0' file_original; do
                local filename_raw=$(basename "$file_original")
                local filename=$(echo "$filename_raw" | tr -d '\r\n')
                local base_name="${filename%.*}"
                
                local relative_path="${file_original#$SOURCE}"
                relative_path="${relative_path#/}"
                local relative_dir=$(dirname "$relative_path")
                local final_dir="$OUTPUT_DIR/$relative_dir"
                
                local effective_suffix="$SUFFIX_STRING"
                if [[ "$DRYRUN" == true ]]; then
                    effective_suffix="${effective_suffix}${DRYRUN_SUFFIX}"
                fi

                local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
                local final_output_basename=$(basename "$final_output")

                # --- PRÉPARATION POUR LA VÉRIFICATION D ANOMALIE ---
                local generated_base_name="${final_output_basename%.mkv}"
                
                # 1. RETRAIT DU SUFFIXE DRY RUN (toujours en premier car il est le dernier ajouté)
                if [[ "$DRYRUN" == true ]]; then
                    generated_base_name="${generated_base_name%"$DRYRUN_SUFFIX"}"
                fi
                
                # 2. RETRAIT DU SUFFIXE D ORIGINE ($SUFFIX_STRING)
                if [[ -n "$SUFFIX_STRING" ]]; then
                    generated_base_name="${generated_base_name%"$SUFFIX_STRING"}"
                fi

                count=$((count + 1))
                
                {
                    echo -e "[ $count / $total_files ]"
                    
                    local anomaly_message=""
                    
                    # --- VÉRIFICATION D ANOMALIE ---
                    if [[ "$base_name" != "$generated_base_name" ]]; then
                        anomaly_count=$((anomaly_count + 1))
                        anomaly_message="🚨 ANOMALIE DÉTECTÉE : Le nom de base original diffère du nom généré sans suffixe !"
                    fi
                    
                    if [[ -n "$anomaly_message" ]]; then
                        echo "$anomaly_message"
                        echo -e "${RED}  $anomaly_message${NOCOLOR}" > $TTY_DEV
                    fi
                    
                    # Affichage des noms
                    printf "  ${ORANGE}%-10s${NOCOLOR} : %s\n" "ORIGINAL" "$filename"
                    printf "  ${GREEN}%-10s${NOCOLOR}    : %s\n" "GÉNÉRÉ" "$final_output_basename"
                    
                    echo ""
                
                } | tee -a "$LOG_FILE"
                
            done < "$QUEUE"
            
            # AFFICHAGE ET LOG DU RÉSUMÉ DES ANOMALIES
            {
                echo "-------------------------------------------"
                if [[ "$anomaly_count" -gt 0 ]]; then
                    printf "  $anomaly_count ANOMALIE(S) de nommage trouvée(s)."
                    printf "  Veuillez vérifier les caractères spéciaux ou les problèmes d'encodage pour ces fichiers."
                else
                    printf " ${GREEN}Aucune anomalie de nommage détectée.${NOCOLOR}"
                fi
				echo ""
                echo "-------------------------------------------"
            } | tee -a "$LOG_FILE"         
            ;;
        [nN]|*)
            echo "Comparaison des noms ignorée."
            ;;
    esac
}

###########################################################
# AFFICHAGE DU RÉSUMÉ FINAL
###########################################################

show_summary() {
    # Traiter toutes les analyses VMAF en attente
    process_vmaf_queue
    
    local succ=0
    if [[ -f "$LOG_SUCCESS" && -s "$LOG_SUCCESS" ]]; then
        succ=$(grep -c ' | SUCCESS' "$LOG_SUCCESS" 2>/dev/null || echo 0)
    fi

    local skip=0
    if [[ -f "$LOG_SKIPPED" && -s "$LOG_SKIPPED" ]]; then
        skip=$(grep -c ' | SKIPPED' "$LOG_SKIPPED" 2>/dev/null || echo 0)
    fi

    local err=0
    if [[ -f "$LOG_ERROR" && -s "$LOG_ERROR" ]]; then
        err=$(grep -c ' | ERROR ffmpeg | ' "$LOG_ERROR" 2>/dev/null || echo 0)
    fi

    # Anomalies : fichiers plus lourds après conversion
    local size_anomalies=0
    if [[ -f "$LOG_SKIPPED" && -s "$LOG_SKIPPED" ]]; then
        size_anomalies=$(grep -c 'WARNING: FICHIER PLUS LOURD' "$LOG_SKIPPED" 2>/dev/null | tr -d '\r\n') || size_anomalies=0
    fi

    # Anomalies : erreurs de vérification checksum/taille lors du transfert
    local checksum_anomalies=0
    if [[ -f "$LOG_ERROR" && -s "$LOG_ERROR" ]]; then
        checksum_anomalies=$(grep -cE ' ERROR (MISMATCH|SIZE_MISMATCH|NO_CHECKSUM) ' "$LOG_ERROR" 2>/dev/null | tr -d '\r\n') || checksum_anomalies=0
    fi

    # Anomalies VMAF : fichiers avec qualité dégradée (score < 70)
    local vmaf_anomalies=0
    if [[ -f "$LOG_SUCCESS" && -s "$LOG_SUCCESS" ]]; then
        vmaf_anomalies=$(grep -c ' | VMAF | .* | quality:DEGRADE' "$LOG_SUCCESS" 2>/dev/null | tr -d '\r\n') || vmaf_anomalies=0
    fi
    
    {
        echo ""
        echo "-------------------------------------------"
        echo "           RÉSUMÉ DE CONVERSION            "
        echo "-------------------------------------------"
        echo "Date fin  : $(date +"%Y-%m-%d %H:%M:%S")"
        echo "Succès    : $succ"
        echo "Ignorés   : $skip"
        echo "Erreurs   : $err"
        echo "-------------------------------------------"
        echo "           ANOMALIES DÉTECTÉES             "
        echo "-------------------------------------------"
        echo "Taille    : $size_anomalies"
        echo "Intégrité : $checksum_anomalies"
        echo "VMAF      : $vmaf_anomalies"
        echo "-------------------------------------------"
    } | tee "$SUMMARY_FILE"
}

###########################################################
# EXPORT DES FONCTIONS ET VARIABLES
###########################################################

export_variables() {
    # --- Fonctions de conversion ---
    export -f convert_file get_video_metadata should_skip_conversion clean_number custom_pv
    
    # --- Fonctions de préparation fichiers ---
    export -f _prepare_file_paths _check_output_exists _handle_dryrun_mode
    export -f _setup_temp_files_and_logs _check_disk_space _get_temp_filename
    
    # --- Fonctions d analyse et copie ---
    export -f _analyze_video _copy_to_temp_storage _execute_conversion
    
    # --- Fonctions de finalisation ---
    export -f _finalize_conversion_success _finalize_try_move
    export -f _finalize_log_and_verify _finalize_conversion_error
    
    # --- Fonctions de gestion de queue ---
    export -f _handle_custom_queue _handle_existing_index
    export -f _count_total_video_files _index_video_files _generate_index
    export -f _build_queue_from_index _apply_queue_limitations _validate_queue_not_empty
    export -f _display_random_mode_selection _create_readable_queue_copy
    export -f build_queue validate_queue_file
    
    # --- Fonctions de traitement parallèle ---
    export -f prepare_dynamic_queue _process_queue_simple _process_queue_with_fifo
    export -f increment_processed_count update_queue
    
    # --- Fonctions utilitaires ---
    export -f is_excluded count_null_separated compute_md5_prefix now_ts
    
    # --- Fonctions VMAF (qualité vidéo) ---
    export -f compute_vmaf_score _queue_vmaf_analysis process_vmaf_queue check_vmaf
    
    # --- Variables de configuration ---
    export DRYRUN CONVERSION_MODE KEEP_INDEX SORT_MODE
    export ENCODER_PRESET TARGET_BITRATE_KBPS TARGET_BITRATE_FFMPEG HWACCEL
    export MAXRATE_KBPS BUFSIZE_KBPS MAXRATE_FFMPEG BUFSIZE_FFMPEG X265_VBV_PARAMS
    export BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT
    export MIN_TMP_FREE_MB PARALLEL_JOBS FFMPEG_MIN_VERSION
    
    # --- Variables de chemins ---
    export SOURCE OUTPUT_DIR TMP_DIR SCRIPT_DIR
    export LOG_DIR LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE
    export QUEUE INDEX INDEX_READABLE
    
    # --- Variables de queue dynamique (mode FIFO) ---
    export WORKFIFO QUEUE_FULL NEXT_QUEUE_POS_FILE TOTAL_QUEUE_FILE
    export FIFO_WRITER_PID FIFO_WRITER_READY
    export PROCESSED_COUNT_FILE TARGET_COUNT_FILE
    
    # --- Variables d options ---
    export DRYRUN_SUFFIX SUFFIX_STRING NO_PROGRESS STOP_FLAG
    export RANDOM_MODE RANDOM_MODE_DEFAULT_LIMIT LIMIT_FILES CUSTOM_QUEUE
    export EXECUTION_TIMESTAMP EXCLUDES_REGEX VMAF_ENABLED
    
    # --- Variables de couleurs et affichage ---
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE
    export AWK_PROGRESS_SCRIPT IO_PRIORITY_CMD
    
    # --- Fonctions et variables de progression parallèle ---
    export -f acquire_progress_slot release_progress_slot cleanup_progress_slots setup_progress_display
    export SLOTS_DIR
    
    # --- Variables de detection d outils ---
    export HAS_MD5SUM HAS_MD5 HAS_PYTHON3
    export HAS_DATE_NANO HAS_PERL_HIRES HAS_GAWK
    export HAS_SHA256SUM HAS_SHASUM HAS_OPENSSL
    export HAS_LIBVMAF VMAF_QUEUE_FILE
    
    # --- Export du tableau EXCLUDES ---
    ( IFS=:; export EXCLUDES="${EXCLUDES[*]}" )
}

###########################################################
# FONCTION PRINCIPALE
###########################################################

main() {
    parse_arguments "$@"
    
    set_conversion_mode_parameters
    
    # Convertir SOURCE en chemin absolu pour éviter les problèmes de répertoire courant
    SOURCE=$(cd "$SOURCE" && pwd)
    
    check_lock
    check_dependencies
    initialize_directories
    
    check_plexignore
    check_output_suffix
    
    # Détecter le hwaccel avant d indexer / construire la queue
    detect_hwaccel

    # Vérifier si VMAF est activé et disponible
    check_vmaf

    build_queue
    
    export_variables

    # Préparer la queue dynamique, lancer le traitement et attendre la fin
    prepare_dynamic_queue

    # Afficher le résumé final
    if [[ "$DRYRUN" == true ]]; then
        echo -e "${GREEN}Dry run terminé${NOCOLOR}"
        dry_run_compare_names
    else
        show_summary
    fi
}

###########################################################
# POINT D ENTRÉE
###########################################################

main "$@"