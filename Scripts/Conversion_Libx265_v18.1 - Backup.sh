#!/bin/bash

###########################################################
# TO DO
# 1. Erreur à analyser pour le fichier My Dearest Nemesis - 1x12 - Épisode 12 qui echoue a chaque fois
# 2. Proposer une alternative à AWK pour gérer l affichage de barre de progression dynamique 
#    de la conversion sur plusieurs lignes pour les traitements en parallèle 
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

# ----- Compatibility helpers for macOS / Homebrew -----
# If the user installed GNU coreutils / gawk via Homebrew, prefer their gnubin
if command -v brew >/dev/null 2>&1; then
    core_gnubin="$(brew --prefix coreutils 2>/dev/null)/libexec/gnubin"
    if [[ -d "$core_gnubin" ]]; then
        PATH="$core_gnubin:$PATH"
    fi
    gawk_bin="$(brew --prefix gawk 2>/dev/null)/bin"
    if [[ -d "$gawk_bin" ]]; then
        PATH="$gawk_bin:$PATH"
    fi
fi

# portable md5 prefix (first 8 chars) for creating tmp names
compute_md5_prefix() {
    local input="$1"
    if command -v md5sum >/dev/null 2>&1; then
        printf "%s" "$input" | md5sum | awk '{print substr($1,1,8)}'
    elif command -v md5 >/dev/null 2>&1; then
        # macOS md5 prints only the digest for stdin; handle robustly
        printf "%s" "$input" | md5 | awk '{print substr($1,1,8)}'
    elif command -v python3 >/dev/null 2>&1; then
        printf "%s" "$input" | python3 - <<PY | head -1
import sys,hashlib
print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:8])
PY
    else
        # fallback: use a simple shell hash (not cryptographic but stable)
        printf "%s" "$input" | awk '{s=0; for(i=1;i<=length($0);i++){s=(s*31+and(255, ord=ord(substr($0,i,1))));} printf "%08x", s}' 2>/dev/null || echo "00000000"
    fi
}

# nproc compatibility
nproc_compat() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi
    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null && return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null && return
    fi
    echo 1
}

# high-resolution timestamp (seconds with fraction)
now_ts() {
    if date +%s.%N >/dev/null 2>&1; then
        date +%s.%N
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(time.time())'
    else
        perl -MTime::HiRes -e 'printf("%.6f\n", Time::HiRes::time)'
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

# Conserver l index existant sans demander confirmation
KEEP_INDEX=false

# Paramètre de nombre de fichiers à sélectionner aléatoirement par défaut
readonly RANDOM_MODE_DEFAULT_LIMIT=10

# Version FFMPEG minimale
readonly FFMPEG_MIN_VERSION=8 

# Suffixe pour les fichiers
readonly DRYRUN_SUFFIX="-dryrun-sample"
SUFFIX_STRING="_x265"  # Default suffix for output files

# Exclusions par défaut
EXCLUDES=("./logs" "./*.sh" "./*.txt" "Converted" "$SCRIPT_DIR")

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

###########################################################
# PARAMÈTRES TECHNIQUES
###########################################################

# Système
readonly TMP_DIR="/tmp/video_convert"

readonly MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp


# PARAMÈTRES DE CONVERSION (encodeur générique - HEVC/x265)
# CRF (-cq) : Facteur de qualité constante. Plus bas = meilleure qualité / plus de taille.
# ENCODER_PRESET : Préréglage générique de l encodeur. Pour libx265 utiliser (ultrafast..veryslow),
ENCODER_PRESET=""

# SEUIL DE BITRATE DE CONVERSION (KBPS)
readonly BITRATE_CONVERSION_THRESHOLD_KBPS=2300

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

set_conversion_mode_parameters() {
    case "$CONVERSION_MODE" in
        film)
            CRF=20.6
            ENCODER_PRESET="slow"
            ;;
        serie)
            CRF=20.7
            ENCODER_PRESET="slow"
            ;;
        *)
            echo -e "${RED}ERREUR : Mode de conversion inconnu : $CONVERSION_MODE${NOCOLOR}"
            echo "Modes disponibles : film, serie"
            exit 1
            ;;
    esac
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

    if [[ "$OUTPUT_DIR" != /* ]]; then
        OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
    fi
    
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
EOF
}

###########################################################
# GESTION DU VERROUILLAGE
###########################################################

cleanup() {
    touch "$STOP_FLAG"
    rm -f "$LOCKFILE"
    kill $(jobs -p) 2>/dev/null || true
    # Nettoyage des artefacts de queue dynamique
    if [[ -n "${WORKFIFO:-}" ]]; then
        rm -f "${WORKFIFO}" 2>/dev/null || true
    fi
    if [[ -n "${NEXT_MASTER_POS_FILE:-}" ]]; then
        rm -f "${NEXT_MASTER_POS_FILE}" "${TOTAL_MASTER_FILE:-}" 2>/dev/null || true
    fi
    # Remove FIFO writer artifacts if present
    if [[ -n "${FIFO_WRITER_PID:-}" ]]; then
        rm -f "${FIFO_WRITER_PID}" "${FIFO_WRITER_READY:-}" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

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

    echo -e "   - Mode conversion : ${CYAN}$CONVERSION_MODE${NOCOLOR} (CRF=$CRF)"
    echo -e "${GREEN}Environnement validé.${NOCOLOR}"
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
    
    local file_count=$(tr -cd '\0' < "$queue_file" | wc -c)
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
    for log_file in "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$LOG_DRYRUN_COMPARISON"; do
        touch "$log_file"
    done
    # Log pour update_queue
    touch "$LOG_DIR/update_queue.log"
}

###########################################################
# FONCTIONS UTILITAIRES
###########################################################

is_excluded() {
    local f="$1"
    for ex in "${EXCLUDES[@]}"; do
        if [[ "$f" == "$ex"* ]]; then 
            return 0
        fi
    done
    return 1
}

clean_number() {
    echo "$1" | sed 's/[^0-9]//g'
}

# custom_pv : remplacement simple et sûr pour les binaires de `pv` utilisant `dd` + interrogation
# de la taille de destination.
# Utilisation : custom_pv <src> <dst> [couleur]
# Remarques : utilise `dd` et `stat` ; affiche la progression sur `stderr` (colorée) et termine
# à 100% à la fin.
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

    # Interroger la progression pendant l'exécution de dd
    while kill -0 "$dd_pid" 2>/dev/null; do
        copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
        current_ts=$(now_ts)

        # Calculer et afficher une ligne de progression lisible via awk (avec colorisation)
        awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" -v width=40 -v color="$color" -v nocolor="$NOCOLOR" '
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
            pct = (total>0 ? int( (copied*100)/total ) : 0);
            if(pct>100) pct=100;
            filled = int(pct * width / 100);
            bar="";
            for(i=0;i<filled;i++) bar=bar"=";
            if(filled<width) bar=bar">"; for(i=filled+1;i<width;i++) bar=bar" ";
            printf("\r\033[K%s%s%s", color, sprintf("%s [%5.2fGiB/s] [%s] %3d%% %s/%s", hms(elapsed), (speed/(1024*1024*1024)), bar, pct, sprintf("%6s", hr(copied)), sprintf("%6s", hr(total))), nocolor);
            
            fflush();
        }
        ' >&2

        sleep 0.5
    done

    wait "$dd_pid" 2>/dev/null || true

    # valeur finale
    copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
    current_ts=$(now_ts)
    awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" -v width=40 -v color="$color" -v nocolor="$NOCOLOR" '
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
        pct = (total>0 ? int( (copied*100)/total ) : 100);
        if(pct>100) pct=100;
        filled = int(pct * width / 100);
        bar="";
        for(i=0;i<filled;i++) bar=bar"=";
        if(filled<width) bar=bar">"; for(i=filled+1;i<width;i++) bar=bar" ";
        printf("\r\033[K%s%s%s\n", color, sprintf("%s [%5.2fGiB/s] [%s] %3d%% %s/%s", hms(elapsed), (speed/(1024*1024*1024)), bar, pct, sprintf("%6s", hr(copied)), sprintf("%6s", hr(total))), nocolor);
    }
    ' >&2

    return 0
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
        echo -e "${BLUE}⏭️ SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}" >&2
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
            echo -e "${BLUE}⏭️ SKIPPED (Déjà x265 & bitrate optimisé) : $filename${NOCOLOR}" >&2
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
    
    local index_date=$(stat -c '%y' "$INDEX" | cut -d' ' -f1-2)
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
        -name "$exclude_dir_name" -prune \
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
        -name "$exclude_dir_name" -prune \
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
    local exclude_dir_name=$(basename "$OUTPUT_DIR")

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
    
    # Créer INDEX_READABLE pour consultation
    cut -f2- "$INDEX" > "$INDEX_READABLE"
}

_build_queue_from_index() {
    # Construction de la QUEUE à partir de l INDEX (fichier permanent)
    # Trier par taille décroissante et supprimer la colonne taille
    sort -nrk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
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
    # Vérification que la queue n est pas vide
    if ! [[ -s "$QUEUE" ]]; then
        echo "Aucun fichier à traiter trouvé (vérifiez les filtres ou la source)."
        exit 0
    fi
}

_display_random_mode_selection() {
    # Afficher les fichiers sélectionnés en aléatoire
    if [[ "$RANDOM_MODE" != true ]] || [[ "$NO_PROGRESS" == true ]]; then
        return 0
    fi
    
    echo -e "\n${CYAN}📋 Fichiers sélectionnés aléatoirement : ${NOCOLOR}"
    tr '\0' '\n' < "$QUEUE" | nl -w2 -s'. '
    echo ""
}

_create_readable_queue_copy() {
    # Créer une version lisible de la queue pour consultation (inclut toutes les limitations)
    tr '\0' '\n' < "$QUEUE" > "$LOG_DIR/Queue_readable_${EXECUTION_TIMESTAMP}.txt"
}

# update_queue: lorsque un fichier est SKIPPÉ, ajouter le prochain candidat depuis la queue complète
# pour maintenir le nombre de fichiers demandés par --limit
update_queue() {
    local reason="${1:-}"

    # Ne rien faire si pas de limitation ou si pas de queue master
    if [[ "$LIMIT_FILES" -le 0 ]]; then
        if [[ -w "$LOG_DIR/update_queue.log" ]]; then
            printf "%s | update_queue: skip (no limit)\n" "$(date +'%Y-%m-%d %H:%M:%S')" >> "$LOG_DIR/update_queue.log" 2>/dev/null || true
        fi
        return 0
    fi

    if [[ -z "${WORKFIFO:-}" ]] || [[ ! -p "$WORKFIFO" ]]; then
        if [[ -w "$LOG_DIR/update_queue.log" ]]; then
            printf "%s | update_queue: skip (no WORKFIFO or not a pipe) WORKFIFO=%s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "${WORKFIFO:-}" >> "$LOG_DIR/update_queue.log" 2>/dev/null || true
        fi
        return 0
    fi

    local lockdir="$LOG_DIR/update_queue.lock"
    # simple mutex par création de dossier
    while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.01; done

    local nextpos=0
    if [[ -f "$NEXT_MASTER_POS_FILE" ]]; then
        nextpos=$(cat "$NEXT_MASTER_POS_FILE") || nextpos=0
    fi
    local total=0
    if [[ -f "$TOTAL_MASTER_FILE" ]]; then
        total=$(cat "$TOTAL_MASTER_FILE") || total=0
    fi

    if [[ $nextpos -lt $total ]]; then
        # Récupérer l'élément suivant (convertir la master queue en lignes pour sed)
        local candidate
        candidate=$(tr '\0' '\n' < "$MASTER_QUEUE" | sed -n "$((nextpos+1))p") || candidate=""
        if [[ -n "$candidate" ]]; then
            # Écrire atomiquement dans le FIFO (en arrière-plan pour ne pas bloquer l'appelant)
            printf '%s\0' "$candidate" > "$WORKFIFO" &
        fi
        echo $((nextpos+1)) > "$NEXT_MASTER_POS_FILE"
    fi

    rmdir "$lockdir" 2>/dev/null || true
}

###########################################################
# SOUS-FONCTIONS DE CONVERSION
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
        echo -e "${BLUE}⏭️ SKIPPED (Fichier de sortie existe déjà) : $filename${NOCOLOR}" >&2
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
        # Si une limite est en place, alimenter la queue avec le prochain candidat
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue "skip" || true
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

_setup_temp_files_and_logs() {
    local filename="$1"
    local file_original="$2"
    local final_dir="$3"
    
    mkdir -p "$final_dir" 2>/dev/null || true
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${YELLOW}▶️ Démarrage du fichier : $filename${NOCOLOR}"
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

_execute_conversion() {
    local tmp_input="$1"
    local tmp_output="$2"
    local ffmpeg_log_temp="$3"
    local duration_secs="$4"
    local base_name="$5"

    # Calcul du nombre de threads à allouer par job
    local cores
    cores=$(nproc_compat)
    local threads_per_job=$(( cores / PARALLEL_JOBS ))
    if [[ "$threads_per_job" -lt 1 ]]; then
        threads_per_job=1
    fi
       
    # Options :
    #  -g 600               : GOP size (nombre d images entre I-frames)
    #  -keyint_min 600      : intervalle minimum entre keyframes (force I-frame régulière)
    #  -c:v libx265         : encodeur logiciel x265 (HEVC)
    #  -preset slow         : préréglage qualité/temps (lent = meilleure compression)
    #  -tune fastdecode     : optimiser pour un décodage rapide
    #  -pix_fmt yuv420p10le : FFormat de pixel YUV 4:2:0 avec 10 bits de profondeur de couleur maximum

    if $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -i "$tmp_input" -pix_fmt yuv420p10le \
        -g 600 -keyint_min 600 \
        -c:v libx265 -preset "$ENCODER_PRESET" \
        -tune fastdecode -crf "$CRF" -x265-params "pools=${threads_per_job}" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
    awk -v DURATION="$duration_secs" -v CURRENT_FILE_NAME="$base_name" -v NOPROG="$NO_PROGRESS" '
        BEGIN {
            duration = DURATION + 0;
            if (duration < 1) exit;

            start = systime();
            last_update = 0;
            refresh_interval = 10;
        }

        /out_time_us=/ {
            gsub(/out_time_us=/, "");
            current_time = $0 / 1000000;

            percent = (current_time / duration) * 100;
            if (percent > 100) percent = 100;

            elapsed = systime() - start;

            speed = (elapsed > 0 ? current_time / elapsed : 1);

            remaining = duration - current_time;
            eta = (speed > 0 ? remaining / speed : 0);

            h = int(eta / 3600);
            m = int((eta % 3600) / 60);
            s = int(eta % 60);

            eta_str = sprintf("%02d:%02d:%02d", h, m, s);

            now = systime() + (strftime("%S") % 1);
            if (NOPROG != "true" && (now - last_update >= refresh_interval || percent >= 99)) {
                printf "  ... [%-40.40s] %5.1f%% | ETA: %s | Speed: %.2fx\n",
                       CURRENT_FILE_NAME, percent, eta_str, speed;
                fflush();
                last_update = now;
            }
        }

        /progress=end/ {
            if (NOPROG != "true") {
                printf "  ... [%-40.40s] 100%% | ETA: 00:00:00 | Speed: %.2fx\n",
                    CURRENT_FILE_NAME, speed;
                fflush();
            }
        }
    '; then
        return 0
    else
        return 1
    fi
}

_finalize_conversion_success() {
    local filename="$1"
    local file_original="$2"
    local tmp_input="$3"
    local tmp_output="$4"
    local final_output="$5"
    local ffmpeg_log_temp="$6"
    local sizeBeforeMB="$7"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "  ${GREEN}✅ Fichier converti : $filename${NOCOLOR}"
    fi
    mv "$tmp_output" "$final_output" 2>/dev/null || return 1
    rm "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null || true

    local sizeAfterMB=$(du -m "$final_output" 2>/dev/null | awk '{print $1}') || sizeAfterMB=0
    local size_comparison="${sizeBeforeMB}MB → ${sizeAfterMB}MB"

    if [[ "$sizeAfterMB" -ge "$sizeBeforeMB" ]]; then
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: FICHIER PLUS LOURD ($size_comparison). | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
    fi
    
    if [[ -n "$LOG_SUCCESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file_original → $final_output | $size_comparison" >> "$LOG_SUCCESS" 2>/dev/null || true
    fi
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
    # Sauvegarder la queue complète (avant application de la limitation) pour alimentation dynamique
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
        return 0
    fi
    
    if _handle_dryrun_mode "$final_dir" "$final_output"; then
        return 0
    fi
    
    local tmp_input=$(_get_temp_filename "$file_original" ".in")
    local tmp_output=$(_get_temp_filename "$file_original" ".out.mkv")
    local ffmpeg_log_temp=$(_get_temp_filename "$file_original" "_err.log")
    
    _setup_temp_files_and_logs "$filename" "$file_original" "$final_dir"
    
    _check_disk_space "$file_original" || return 1
    
    local metadata_info
    if ! metadata_info=$(_analyze_video "$file_original" "$filename"); then
        # analyse a indiqué qu'on doit skip ce fichier -> alimenter la queue si nécessaire
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue "skip" || true
        fi
        return 0
    fi
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata_info"
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')
    
    _copy_to_temp_storage "$file_original" "$filename" "$tmp_input" "$ffmpeg_log_temp" || return 1
    
    if _execute_conversion "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" "$duration_secs" "$base_name"; then
        _finalize_conversion_success "$filename" "$file_original" "$tmp_input" "$tmp_output" "$final_output" "$ffmpeg_log_temp" "$sizeBeforeMB"
    else
        _finalize_conversion_error "$filename" "$file_original" "$tmp_input" "$tmp_output" "$ffmpeg_log_temp"
        # En cas d'erreur de conversion, si on a une limite, alimenter la queue pour compenser
        if [[ "$LIMIT_FILES" -gt 0 ]]; then
            update_queue "skip" || true
        fi
    fi
}

###########################################################
# DRY RUN AVANCÉ (Comparaison et Anomalies de nommage)
###########################################################

dry_run_compare_names() {
    if [[ "$DRYRUN" != true ]]; then return 0; fi

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
            
            local total_files=$(tr -cd '\0' < "$QUEUE" | wc -c)
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

                # --- PRÉPARATION POUR LA VÉRIFICATION D'ANOMALIE ---
                local generated_base_name="${final_output_basename%.mkv}"
                
                # 1. RETRAIT DU SUFFIXE DRY RUN (toujours en premier car il est le dernier ajouté)
                if [[ "$DRYRUN" == true ]]; then
                    generated_base_name="${generated_base_name%"$DRYRUN_SUFFIX"}"
                fi
                
                # 2. RETRAIT DU SUFFIXE D'ORIGINE ($SUFFIX_STRING)
                if [[ -n "$SUFFIX_STRING" ]]; then
                    generated_base_name="${generated_base_name%"$SUFFIX_STRING"}"
                fi

                count=$((count + 1))
                
                {
                    echo -e "[ $count / $total_files ]"
                    
                    local anomaly_message=""
                    
                    # --- VÉRIFICATION D'ANOMALIE ---
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
    
    {
        echo ""
        echo "-------------------------------------------"
        echo "           RÉSUMÉ DE CONVERSION            "
        echo "-------------------------------------------"
        echo "Date fin : $(date +"%Y-%m-%d %H:%M:%S")"
        echo "Succès   : $succ"
        echo "Ignorés  : $skip"
        echo "Erreurs  : $err"
        echo "-------------------------------------------"
    } | tee "$SUMMARY_FILE"
}

###########################################################
# EXPORT DES FONCTIONS ET VARIABLES POUR PARALLEL
###########################################################

export_for_parallel() {
    export -f convert_file get_video_metadata should_skip_conversion clean_number \
        _prepare_file_paths _check_output_exists _handle_dryrun_mode _setup_temp_files_and_logs \
        _check_disk_space _analyze_video _copy_to_temp_storage _execute_conversion custom_pv \
        _finalize_conversion_success _finalize_conversion_error is_excluded _get_temp_filename \
        _handle_custom_queue _handle_existing_index _count_total_video_files _index_video_files \
        _generate_index _build_queue_from_index _apply_queue_limitations _validate_queue_not_empty \
        _display_random_mode_selection build_queue validate_queue_file _create_readable_queue_copy update_queue
    export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE LOG_DIR
    export TMP_DIR ENCODER_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR FFMPEG_MIN_VERSION
    export BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT
    export MIN_TMP_FREE_MB PARALLEL_JOBS
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE 
    export DRYRUN_SUFFIX SUFFIX_STRING NO_PROGRESS STOP_FLAG SCRIPT_DIR
    export RANDOM_MODE RANDOM_MODE_DEFAULT_LIMIT LIMIT_FILES CUSTOM_QUEUE EXECUTION_TIMESTAMP QUEUE INDEX INDEX_READABLE
    export MASTER_QUEUE WORKFIFO NEXT_MASTER_POS_FILE TOTAL_MASTER_FILE
    export FIFO_WRITER_PID FIFO_WRITER_READY
    export CONVERSION_MODE KEEP_INDEX
    declare -gx EXCLUDES="${EXCLUDES[@]}"
}

###########################################################
# FONCTION PRINCIPALE
###########################################################

main() {
    # Parse des arguments
    parse_arguments "$@"
    
    # Configuration des paramètres selon le mode
    set_conversion_mode_parameters
    
    # Convertir SOURCE en chemin absolu pour éviter les problèmes de répertoire courant
    SOURCE=$(cd "$SOURCE" && pwd)
    
    # Vérifications système
    check_lock
    check_dependencies
    initialize_directories
    
    # Configuration interactive
    check_plexignore
    check_output_suffix
    
    # Construction de la file d attente
    build_queue
    
    # Export pour parallel
    export_for_parallel
    # Préparer une queue dynamique (FIFO) pour permettre l'ajout de candidats lorsque des fichiers sont skip
    MASTER_QUEUE="$QUEUE.full"
    NEXT_MASTER_POS_FILE="$LOG_DIR/next_master_pos_${EXECUTION_TIMESTAMP}"
    TOTAL_MASTER_FILE="$LOG_DIR/total_master_${EXECUTION_TIMESTAMP}"
    WORKFIFO="$LOG_DIR/queue_fifo_${EXECUTION_TIMESTAMP}"
    FIFO_WRITER_PID="$LOG_DIR/fifo_writer_pid_${EXECUTION_TIMESTAMP}"
    FIFO_WRITER_READY="$LOG_DIR/fifo_writer.ready_${EXECUTION_TIMESTAMP}"

    # Total d'éléments dans la master queue
    local total_master=0
    if [[ -f "$MASTER_QUEUE" ]]; then
        total_master=$(tr -cd '\0' < "$MASTER_QUEUE" | wc -c) || total_master=0
    fi
    echo "$total_master" > "$TOTAL_MASTER_FILE"
    # Debug log: total master written
    if [[ -w "$LOG_DIR/update_queue.log" ]]; then
        printf "%s | main: TOTAL_MASTER_FILE='%s' value=%d\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$TOTAL_MASTER_FILE" "$total_master" >> "$LOG_DIR/update_queue.log" 2>/dev/null || true
    fi

    # Position initiale (nombre d'éléments déjà présents dans la queue limitée)
    local initial_in_queue=0
    if [[ -f "$QUEUE" ]]; then
        initial_in_queue=$(tr -cd '\0' < "$QUEUE" | wc -c) || initial_in_queue=0
    fi
    echo "$initial_in_queue" > "$NEXT_MASTER_POS_FILE"
    # Debug log: initial next pos
    if [[ -w "$LOG_DIR/update_queue.log" ]]; then
        printf "%s | main: NEXT_MASTER_POS_FILE='%s' value=%d\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$NEXT_MASTER_POS_FILE" "$initial_in_queue" >> "$LOG_DIR/update_queue.log" 2>/dev/null || true
    fi

    # Créer le FIFO et lancer un writer de fond qui garde la FIFO ouverte
    rm -f "$WORKFIFO" 2>/dev/null || true
    mkfifo "$WORKFIFO"
    # Writer persistant : ouvre la FIFO en écriture, injecte la queue initiale,
    # puis garde la FD ouverte jusqu'à l'arrêt du script (évite EOF prématuré)
    (
        # Open FIFO read-write to avoid blocking when no reader is present
        exec 3<> "$WORKFIFO"
        # write writer pid & mark ready so update_queue can detect writer availability
        if [[ -n "${FIFO_WRITER_PID:-}" ]]; then
            printf "%d" "$$" > "$FIFO_WRITER_PID" 2>/dev/null || true
        fi
        # écrire le contenu initial (NUL séparés)
        if [[ -f "$QUEUE" ]]; then
            cat "$QUEUE" >&3
        fi
        # En mode dry-run, fermer l'écrivain (writer FIFO) après avoir injecté la file initiale
        # afin que le consommateur reçoive EOF et puisse se terminer normalement. En mode normal,
        # on garde l'écrivain ouvert pour permettre l'alimentation dynamique via update_queue.
        if [[ "$DRYRUN" == true ]]; then
            if [[ -n "${FIFO_WRITER_READY:-}" ]]; then
                touch "$FIFO_WRITER_READY" 2>/dev/null || true
            fi
            if [[ -w "$LOG_DIR/update_queue.log" ]]; then
                printf "%s | main: FIFO writer wrote initial queue and exiting (dry-run)\n" "$(date +'%Y-%m-%d %H:%M:%S')" >> "$LOG_DIR/update_queue.log" 2>/dev/null || true
            fi
            exec 3>&-
            exit 0
        fi
        # signal ready
        if [[ -n "${FIFO_WRITER_READY:-}" ]]; then
            touch "$FIFO_WRITER_READY" 2>/dev/null || true
        fi
        # log writer start
        if [[ -w "$LOG_DIR/update_queue.log" ]]; then
            printf "%s | main: FIFO writer started (WORKFIFO=%s) pid=%s ready=%s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$WORKFIFO" "$(cat ${FIFO_WRITER_PID} 2>/dev/null || echo '')" "$FIFO_WRITER_READY" >> "$LOG_DIR/update_queue.log" 2>/dev/null || true
        fi
        # garder la FD ouverte tant que le script tourne (permet update_queue d'écrire sans bloquer)
        while [[ ! -f "$STOP_FLAG" ]]; do
            sleep 0.5
        done
        exec 3>&-
    ) &
    # Exporter les variables de queue dynamique pour les workers
    export MASTER_QUEUE WORKFIFO NEXT_MASTER_POS_FILE TOTAL_MASTER_FILE
    
    # Traitement des fichiers
    local nb_files=0
    if [[ -f "${QUEUE:-}" ]]; then
        nb_files=$(tr -cd '\0' < "$QUEUE" | wc -c) || nb_files=0
    fi

    if [[ "$DRYRUN" == true ]]; then
        echo -e "${MAGENTA}ℹ️  MODE DRY RUN activé : simulation uniquement — aucun encodage réel effectué.${NOCOLOR}"
    fi

    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}Démarrage du traitement ($nb_files fichiers)...${NOCOLOR}"
    fi
    
    # Consumer: read NUL-delimited filenames and run conversions with concurrency
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
                for file in "${_pids[@]}"; do
                    if kill -0 "$file" 2>/dev/null; then
                        _still+=("$file")
                    fi
                done
                _pids=("${_still[@]}")
            fi
        done < "$WORKFIFO"
        for file in "${_pids[@]}"; do
            wait "$file" || true
        done
    }
    _consumer_run &

    wait
    sleep 1

    if [[ "$DRYRUN" == true ]]; then
        echo -e "${GREEN}Traitement terminé${NOCOLOR}"
    fi
    
    dry_run_compare_names

    if [[ "$DRYRUN" != true ]]; then
        show_summary
    fi
}

###########################################################
# POINT D ENTRÉE
###########################################################

main "$@"