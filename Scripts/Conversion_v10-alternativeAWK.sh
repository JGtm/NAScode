#!/bin/bash

###########################################################
# CONVERSION VIDÉO V10 - REFACTORISATION MAJEURE
# Architecture : Système d'état distribué (bash pur)
# Remplacement AWK → Agrégateur de progression centralisé
###########################################################

# TO DO
# 1. Assurer la prise en charge des fichiers avec des caractères spéciaux (type accents)
# ====> a priori corrigé, rester vigilant
# 2. Erreur à analyser pour le fichier My Dearest Nemesis - 1x12 - Épisode 12 qui echoue a chaque fois
# V10 NOTES:
# - Suppression du pipeline AWK complexe
# - Implémentation d'un système d'état par job (fichiers temporaires)
# - Agrégateur de progression en boucle centralisée (plus lisible, plus maintenable)
# - Synchronisation robuste avec locks simples

###########################################################
# ACTIVATION STRICT MODE
###########################################################

set -euo pipefail

###########################################################
# CONFIGURATION GLOBALE
###########################################################

readonly EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
readonly LOCKFILE="/tmp/conversion_video.lock"
readonly STOP_FLAG="/tmp/conversion_stop_flag"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRYRUN=false
TEST_MODE=false
TEST_COUNT=10
FILE_LIMIT=0
CUSTOM_QUEUE=""
SOURCE="../"
OUTPUT_DIR="$SCRIPT_DIR/Converted"
REMOVE_ORIGINAL=false
FORCE_NO_SUFFIX=false
PARALLEL_JOBS=3
NO_PROGRESS=false

readonly DRYRUN_TEST_SUFFIX="-dryrun-sample"
SUFFIX_STRING="_x265"

EXCLUDES=("./logs" "./*.sh" "./*.txt" "Converted" "$SCRIPT_DIR")

###########################################################
# COULEURS ANSI
###########################################################

readonly NOCOLOR='\033[0m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly ORANGE='\033[1;33m'

###########################################################
# CHEMINS DES LOGS
###########################################################

readonly LOG_DIR="./logs"
readonly LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"
readonly LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"
readonly LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"
readonly SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
readonly QUEUE="$LOG_DIR/Queue"
readonly LOG_DRYRUN_COMPARISON="$LOG_DIR/DryRun_Comparison_${EXECUTION_TIMESTAMP}.log"

###########################################################
# PARAMÈTRES TECHNIQUES
###########################################################

readonly TMP_DIR="/tmp/video_convert"
readonly JOBS_STATE_DIR="$TMP_DIR/jobs.state"
readonly PROGRESS_LOCK="$TMP_DIR/progress.lock"
readonly MIN_TMP_FREE_MB=2048

readonly NVENC_PRESET="p5"
readonly CRF=28
readonly MAXRATE="3000k"
readonly BUFSIZE="4500k"
readonly BITRATE_CONVERSION_THRESHOLD_KBPS=2300
readonly SKIP_TOLERANCE_PERCENT=10
readonly RC_LOOKAHEAD=20
readonly SURFACES=16

IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then 
    IO_PRIORITY_CMD="ionice -c2 -n4"
fi

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
            -d|--dry-run|--dryrun) 
                DRYRUN=true
                shift 
                ;;
            -r|--remove-original) 
                REMOVE_ORIGINAL=true
                shift 
                ;;
            -x|--no-suffix) 
                FORCE_NO_SUFFIX=true
                shift 
                ;;
            -t|--test)
                TEST_MODE=true
                if [[ "${2:-}" =~ ^[0-9]+$ ]]; then 
                    TEST_COUNT="$2"
                    shift 2
                else 
                    shift 1
                fi
                ;;
            -l|--limit)
                if [[ "${2:-}" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]]; then
                    FILE_LIMIT="$2"
                    shift 2
                else
                    echo -e "${RED}ERREUR: --limit doit être suivi d'un nombre positif.${NOCOLOR}"
                    exit 1
                fi
                ;;
            -q|--queue)
                if [[ -f "$2" ]]; then
                    CUSTOM_QUEUE="$2"
                    shift 2
                else
                    echo -e "${RED}ERREUR: Fichier queue '$2' introuvable.${NOCOLOR}"
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
            *) 
                echo -e "${RED}Option inconnue : $1${NOCOLOR}"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ "$OUTPUT_DIR" != /* ]]; then
        OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
    fi
}

show_help() {
    cat << EOF
Usage: ./conversion.sh [OPTIONS]

Options:
  -s, --source DIR          Dossier source (défaut: dossier parent)
  -o, --output-dir DIR      Dossier de destination (défaut: converted au même niveau que le script)
  -e, --exclude PATTERN     Ajouter un pattern d'exclusion
  -d, --dry-run             Mode simulation sans conversion
  -r, --remove-original     Supprimer les fichiers originaux après conversion
  -x, --no-suffix           Désactiver le suffixe _x265
  -t, --test N              Mode test avec N fichiers aléatoires (défaut: 10)
  -l, --limit N             Limiter le traitement à N fichiers
  -q, --queue FILE          Utiliser un fichier queue personnalisé
  -n, --no-progress         Désactiver l'affichage des barres de progression (mode silencieux)
  -h, --help                Afficher cette aide

Exemples:
  ./conversion.sh
  ./conversion.sh -s /media/videos -o /media/converted
  ./conversion.sh --dry-run --test 5
  ./conversion.sh --no-progress
EOF
}

###########################################################
# GESTION DU VERROUILLAGE
###########################################################

cleanup() {
    touch "$STOP_FLAG"
    rm -f "$LOCKFILE"
    rm -rf "$JOBS_STATE_DIR"
    kill $(jobs -p) 2>/dev/null || true
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

check_ffmpeg_version() {
    local ffmpeg_version
    ffmpeg_version=$(ffmpeg -version 2>/dev/null | head -n 1 | grep -oP 'ffmpeg version \K[0-9]+' | head -c 1)
    
    if [[ -z "$ffmpeg_version" ]]; then
        echo -e "${YELLOW}⚠️  Impossible de déterminer la version de ffmpeg.${NOCOLOR}"
        return 0
    fi
    
    if [[ "$ffmpeg_version" -lt 8 ]]; then
        echo -e "${RED}⚠️  ALERTE: ffmpeg version $ffmpeg_version détectée. Version 8 ou supérieure recommandée.${NOCOLOR}"
    fi
}

check_dependencies() {
    echo "Vérification de l'environnement..."
    
    local missing_deps=()
    
    for cmd in ffmpeg ffprobe pv; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}ERREUR: Dépendances manquantes: ${missing_deps[*]}${NOCOLOR}"
        exit 1
    fi
    
    check_ffmpeg_version
    
    if [[ ! -d "$SOURCE" ]]; then
        echo -e "${RED}ERREUR: Source '$SOURCE' introuvable.${NOCOLOR}"
        exit 1
    fi
    
    echo -e "${GREEN}Environnement validé.${NOCOLOR}"
}

validate_queue_file() {
    local queue_file="$1"
    
    if [[ ! -f "$queue_file" ]]; then
        echo -e "${RED}ERREUR: Le fichier queue '$queue_file' n'existe pas.${NOCOLOR}"
        return 1
    fi
    
    if [[ ! -s "$queue_file" ]]; then
        echo -e "${RED}ERREUR: Le fichier queue '$queue_file' est vide.${NOCOLOR}"
        return 1
    fi
    
    local file_count=$(tr -cd '\0' < "$queue_file" | wc -c)
    if [[ $file_count -eq 0 ]]; then
        echo -e "${RED}ERREUR: Le fichier queue n'a pas le format attendu (fichiers séparés par null).${NOCOLOR}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Fichier queue validé ($file_count fichiers détectés).${NOCOLOR}"
    return 0
}

initialize_directories() {
    mkdir -p "$LOG_DIR" "$TMP_DIR" "$JOBS_STATE_DIR" "$OUTPUT_DIR"
    
    rm -f "$STOP_FLAG"
    
    for log_file in "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_DRYRUN_COMPARISON"; do
        touch "$log_file"
    done
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

###########################################################
# SYSTÈME DE GESTION D'ÉTAT (V10 - NOUVEAU)
###########################################################

update_progress() {
    local job_id="$1"
    local progress="$2"
    local speed="$3"
    local eta="$4"
    local filename="$5"
    local status="$6"
    
    local state_file="$JOBS_STATE_DIR/${job_id}.state"
    
    echo "${progress}|${speed}|${eta}|${filename}|${status}" > "$state_file" 2>/dev/null || true
}

get_job_state() {
    local job_id="$1"
    local state_file="$JOBS_STATE_DIR/${job_id}.state"
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file" 2>/dev/null || true
    fi
}

aggregate_and_display_progress() {
    local total_jobs="$1"
    
    if [[ "$NO_PROGRESS" == true ]]; then
        return 0
    fi
    
    local last_display_time=$(date +%s)
    local refresh_interval=1
    local no_activity_count=0
    local max_no_activity=10
    
    while true; do
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_display_time))
        
        if [[ $time_diff -lt $refresh_interval ]]; then
            sleep 0.2
            continue
        fi
        
        local completed_jobs=0
        local active_jobs=0
        local error_jobs=0
        local line_num=1
        local active_states=""
        
        for state_file in "$JOBS_STATE_DIR"/*.state; do
            [[ ! -f "$state_file" ]] && continue
            
            local state=$(cat "$state_file" 2>/dev/null)
            [[ -z "$state" ]] && continue
            
            IFS='|' read -r progress speed eta filename status <<< "$state"
            
            case "$status" in
                completed) ((completed_jobs++)) ;;
                error) ((error_jobs++)) ;;
                active|skipped)
                    ((active_jobs++))
                    active_states+="$(printf "%2d|%s|%s|%s|%s\n" "$line_num" "$filename" "$progress" "$speed" "$eta")"$'\n'
                    ((line_num++))
                    ;;
            esac
        done
        
        printf '\033[2J\033[H'
        
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        echo -e "${CYAN}📊 Conversion en cours ${NOCOLOR}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        
        while IFS='|' read -r line_num filename progress speed eta; do
            [[ -z "$line_num" ]] && continue
            display_job_line "$line_num" "$filename" "$progress" "$speed" "$eta"
        done <<< "$active_states"
        
        echo ""
        display_progress_footer "$completed_jobs" "$total_jobs" "$active_jobs" "$error_jobs"
        
        last_display_time=$current_time
        
        if [[ $active_jobs -eq 0 ]]; then
            ((no_activity_count++))
            if [[ $no_activity_count -gt $max_no_activity ]]; then
                break
            fi
        else
            no_activity_count=0
        fi
    done
}

display_job_line() {
    local line_num="$1"
    local filename="$2"
    local progress="$3"
    local speed="$4"
    local eta="$5"
    
    local progress_int=${progress%.*}
    [[ -z "$progress_int" ]] && progress_int=0
    
    local bar_length=25
    local filled=$((progress_int * bar_length / 100))
    local empty=$((bar_length - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    local filename_short=$(basename "$filename" | cut -c1-35)
    
    printf "%2d) [${GREEN}%-${bar_length}s${NOCOLOR}] %3d%% | %5sx | ETA:%s | %s\n" \
        "$line_num" "$bar" "$progress_int" "$speed" "$eta" "$filename_short"
}

display_progress_footer() {
    local completed="$1"
    local total="$2"
    local active="$3"
    local errors="$4"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
    
    if [[ "$errors" -gt 0 ]]; then
        echo -e "✅ ${GREEN}${completed}${NOCOLOR} | 🔄 ${YELLOW}${active}${NOCOLOR} | ❌ ${RED}${errors}${NOCOLOR} | 📋 Total: ${total}"
    else
        echo -e "✅ ${GREEN}${completed}${NOCOLOR} | 🔄 ${YELLOW}${active}${NOCOLOR} | 📋 Total: ${total}"
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
}

###########################################################
# GESTION PLEXIGNORE
###########################################################

check_plexignore() {
    local source_abs output_abs
    source_abs=$(readlink -f "$SOURCE")
    output_abs=$(readlink -f "$OUTPUT_DIR")
    local plexignore_file="$OUTPUT_DIR/.plexignore"

    if [[ "$output_abs"/ != "$source_abs"/ ]] && [[ "$output_abs" = "$source_abs"/* ]]; then
        if [[ "$REMOVE_ORIGINAL" == false ]]; then
            
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
        echo -e "${ORANGE}ℹ️  Option --no-suffix activée. Le suffixe est désactivé par commande.${NOCOLOR}"
    else
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

    if [[ -z "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
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
    
    elif [[ -n "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
        echo -e "${YELLOW}⚠️  ATTENTION : Les fichiers originaux et convertis vont COEXISTER dans le même répertoire.${NOCOLOR}"
        echo -e "${YELLOW}Si vous ne supprimez pas les originaux (-r), assurez-vous que Plex gère correctement les doublons.${NOCOLOR}"
    fi
}

###########################################################
# ANALYSE DES MÉTADONNÉES VIDÉO
###########################################################

get_video_metadata() {
    local file="$1"
    local metadata_output
    
    metadata_output=$(ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate,codec_name:stream_tags=BPS:format=bit_rate,duration \
        -of default=noprint_wrappers=1 \
        "$file" 2>/dev/null)
    
    local bitrate_stream=$(echo "$metadata_output" | grep '^bit_rate=' | head -1 | cut -d'=' -f2)
    local bitrate_bps=$(echo "$metadata_output" | grep '^TAG:BPS=' | cut -d'=' -f2)
    local bitrate_container=$(echo "$metadata_output" | grep '^\[FORMAT\]' -A 10 | grep '^bit_rate=' | cut -d'=' -f2)
    local codec=$(echo "$metadata_output" | grep '^codec_name=' | cut -d'=' -f2)
    local duration=$(echo "$metadata_output" | grep '^duration=' | cut -d'=' -f2)
    
    bitrate_stream=$(clean_number "$bitrate_stream")
    bitrate_bps=$(clean_number "$bitrate_bps")
    bitrate_container=$(clean_number "$bitrate_container")
    
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
    
    echo "${bitrate}|${codec}|${duration}"
}

###########################################################
# VALIDATION DE LA CONVERSION
###########################################################

should_skip_conversion() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    
    if [[ -z "$codec" ]]; then
        echo -e "   ${BLUE}⏭️ SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi
    
    local base_threshold_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * SKIP_TOLERANCE_PERCENT * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))
    
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            echo -e "   ${BLUE}⏭️ SKIPPED (Déjà x265 & bitrate optimisé) : $filename${NOCOLOR}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà x265 et bitrate optimisé) | $file_original" >> "$LOG_SKIPPED"
            return 0
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage X265) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS"
    fi
    
    return 1
}

###########################################################
# FONCTION DE CONVERSION PRINCIPALE
###########################################################

convert_file() {
    set -o pipefail

    local file_original="$1"
    local output_dir="$2"
    local remove_original="$3"
    local job_id="$$"
    
    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")
    local final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"
	 
    local effective_suffix="$SUFFIX_STRING"
    if [[ "$DRYRUN" == true ]]; then
        effective_suffix="${effective_suffix}${DRYRUN_TEST_SUFFIX}"
    fi

    local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
	
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        echo -e "   ${BLUE}⏭️ SKIPPED (Fichier de sortie existe déjà) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi

    if [[ "$DRYRUN" == true ]]; then
        echo "[DRY RUN] 📄 Fichier cible : $(basename "$final_output")"
        mkdir -p "$final_dir"
        touch "$final_output"
        return 0
    fi

    local TMP_BASE_NAME="$$"
    local tmp_input="$TMP_DIR/${TMP_BASE_NAME}.in"
    local tmp_output="$TMP_DIR/${TMP_BASE_NAME}.out.mkv"
    local ffmpeg_log_temp="$TMP_DIR/${TMP_BASE_NAME}_err.log"

    mkdir -p "$final_dir"
    
    update_progress "$job_id" "0" "0.00x" "00:00:00" "$filename" "active"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "  ${YELLOW}▶️ Démarrage du fichier : $filename${NOCOLOR}"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS"

    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}')
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_ERROR"
        update_progress "$job_id" "0" "0.00x" "00:00:00" "$filename" "error"
        return 1
    fi

    local metadata
    metadata=$(get_video_metadata "$file_original")
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata"
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')

    if should_skip_conversion "$codec" "$bitrate" "$filename" "$file_original"; then
        update_progress "$job_id" "100" "1.00x" "00:00:00" "$filename" "skipped"
        return 0
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "  ${CYAN}→ Transfert de [$filename] vers dossier temporaire...${NOCOLOR}"
    else
        echo -e "  ${CYAN}→ $filename${NOCOLOR}"
    fi
    
    if ! pv -f "$file_original" > "$tmp_input"; then
        echo -e "   ${RED}❌ ERROR Impossible de déplacer : $file_original${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR PV copy failed | $file_original" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null
        update_progress "$job_id" "0" "0.00x" "00:00:00" "$filename" "error"
        return 1
    fi

    if [[ "$NO_PROGRESS" != true ]]; then
        echo "  → Encodage NVENC..."
    fi
    
    local start_time=$(date +%s)
    
    if $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" \
        -maxrate "$MAXRATE" -bufsize "$BUFSIZE" -rc vbr -cq "$CRF" \
        -rc-lookahead "$RC_LOOKAHEAD" -surfaces "$SURFACES" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | awk \
        -v JOB_ID="$job_id" \
        -v FILENAME="$filename" \
        -v DURATION="$duration_secs" \
        -v START_TIME="$start_time" \
        -v STATE_DIR="$JOBS_STATE_DIR" '
        BEGIN {
            duration = DURATION + 0
            if (duration < 1) exit
            last_update = 0
            refresh_interval = 0.5
        }
        
        /out_time_us=/ {
            gsub(/out_time_us=/, "")
            current_time_us = $0 + 0
            current_time = current_time_us / 1000000
            
            percent = (current_time / duration) * 100
            if (percent > 100) percent = 100
            
            elapsed = systime() - START_TIME
            if (elapsed > 0)
                speed = current_time / elapsed
            else
                speed = 1
            
            remaining = duration - current_time
            if (speed > 0)
                eta_sec = remaining / speed
            else
                eta_sec = 0
            
            if (eta_sec < 0) eta_sec = 0
            
            eta_h = int(eta_sec / 3600)
            eta_m = int((eta_sec % 3600) / 60)
            eta_s = int(eta_sec % 60)
            
            eta_str = sprintf("%02d:%02d:%02d", eta_h, eta_m, eta_s)
            speed_str = sprintf("%.2f", speed)
            percent_str = sprintf("%.1f", percent)
            
            now = systime()
            if (now - last_update >= refresh_interval) {
                state_file = STATE_DIR "/" JOB_ID ".state"
                printf "%s|%s|%s|%s|active\n", percent_str, speed_str, eta_str, FILENAME > state_file
                close(state_file)
                last_update = now
            }
        }
        
        /progress=end/ {
            percent_str = "100.0"
            speed_str = sprintf("%.2f", speed)
            state_file = STATE_DIR "/" JOB_ID ".state"
            printf "%s|%s|00:00:00|%s|active\n", percent_str, speed_str, FILENAME > state_file
            close(state_file)
        }
    '; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "  ${GREEN}✅ Fichier converti : $filename${NOCOLOR}"
            echo ""
        fi
        mv "$tmp_output" "$final_output"
        rm "$tmp_input" "$ffmpeg_log_temp"

        local sizeAfterMB=$(du -m "$final_output" | awk '{print $1}')
        local size_comparison="${sizeBeforeMB}MB → ${sizeAfterMB}MB"

        if [[ "$sizeAfterMB" -ge "$sizeBeforeMB" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: FICHIER PLUS LOURD ($size_comparison). | $file_original" >> "$LOG_SKIPPED"
        fi
        
        if [[ "$remove_original" == true ]]; then
            rm "$file_original"
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS + REMOVED | $file_original → $final_output | $size_comparison" >> "$LOG_SUCCESS"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file_original → $final_output | $size_comparison" >> "$LOG_SUCCESS"
        fi
        
        update_progress "$job_id" "100" "${speed}x" "00:00:00" "$filename" "completed"
    else
        if [[ ! -f "$STOP_FLAG" ]]; then
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "  ${RED}❌ Échec de la conversion : $filename${NOCOLOR}"
            fi
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR"
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR"
        cat "$ffmpeg_log_temp" >> "$LOG_ERROR"
        echo "-------------------------------" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
        update_progress "$job_id" "0" "0.00x" "00:00:00" "$filename" "error"
    fi
}

###########################################################
# CONSTRUCTION DE LA FILE D'ATTENTE
###########################################################

build_queue() {
    if [[ -n "$CUSTOM_QUEUE" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo ""
            echo -e "${CYAN}📄 Utilisation du fichier queue personnalisé : $CUSTOM_QUEUE${NOCOLOR}"
        fi
        
        if ! validate_queue_file "$CUSTOM_QUEUE"; then
            exit 1
        fi
        
        cp "$CUSTOM_QUEUE" "$QUEUE"
        
        if ! [[ -s "$QUEUE" ]]; then
            echo "Aucun fichier à traiter trouvé."
            exit 0
        fi
        return 0
    fi
    
    if [[ -f "$QUEUE" ]]; then
        local queue_date=$(stat -c '%y' "$QUEUE" | cut -d' ' -f1-2)
        if [[ "$NO_PROGRESS" != true ]]; then
            echo ""
            echo -e "${CYAN}📁 Un fichier queue existant a été trouvé.${NOCOLOR}"
            echo -e "${CYAN}   Date de création : $queue_date${NOCOLOR}"
            echo ""
        fi
        
        read -r -p "Souhaitez-vous conserver ce fichier queue ? (O/n) " response
        
        case "$response" in
            [nN])
                if [[ "$NO_PROGRESS" != true ]]; then
                    echo -e "${YELLOW}Régénération d'une nouvelle file d'attente...${NOCOLOR}"
                fi
                rm -f "$QUEUE"
                ;;
            *)
                if [[ "$NO_PROGRESS" != true ]]; then
                    echo -e "${GREEN}Utilisation de la file d'attente existante.${NOCOLOR}"
                fi
                
                if ! [[ -s "$QUEUE" ]]; then
                    echo "Aucun fichier à traiter trouvé."
                    exit 0
                fi
                return 0
                ;;
        esac
    fi
    
    local exclude_dir_name=$(basename "$OUTPUT_DIR")

    if [[ "$NO_PROGRESS" != true ]]; then
        echo "Indexation fichiers..." >&2
    fi
    local total_files=$(find "$SOURCE" \
        -name "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 2>/dev/null | \
    tr -cd '\0' | wc -c)

    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}📊 Total de fichiers vidéo trouvés : ${total_files}${NOCOLOR}"
    fi
    
    local count_file="$TMP_DIR/.index_count_$$"
    echo "0" > "$count_file"
    
    find "$SOURCE" \
        -name "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 | \
    while IFS= read -r -d $'\0' f; do
        if is_excluded "$f"; then continue; fi
        if [[ "$f" =~ \.(sh|txt)$ ]]; then continue; fi
        
        local count=$(($(cat "$count_file") + 1))
        echo "$count" > "$count_file"
        if [[ "$NO_PROGRESS" != true ]]; then
            printf "\rIndexation en cours... [%-${#total_files}d/${total_files}]" "$count" >&2
        fi
        
        echo -e "$(stat -c%s "$f")\t$f"
    done > "$QUEUE.tmp"
    
    local final_count=$(cat "$count_file")
    rm -f "$count_file"
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "\n${GREEN}✅ Indexation terminée [${final_count}/${total_files} fichiers répertoriés]${NOCOLOR}" >&2
    fi
    
    local limit_count=""
    if [[ "$TEST_MODE" == true ]]; then
        limit_count=$TEST_COUNT
        if [[ "$NO_PROGRESS" != true ]]; then
            echo "🎲 MODE TEST ACTIVÉ : Sélection aléatoire de $limit_count fichiers..."
        fi
        sort -R "$QUEUE.tmp" | head -n "$limit_count" | sort -nrk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE"
    elif [[ "$FILE_LIMIT" -gt 0 ]]; then
        limit_count=$FILE_LIMIT
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${ORANGE}📋 LIMITE ACTIVÉE : Traitement de $FILE_LIMIT fichiers maximum.${NOCOLOR}"
        fi
        sort -nrk1,1 "$QUEUE.tmp" | head -n "$limit_count" | cut -f2- | tr '\n' '\0' > "$QUEUE"
    else
        sort -nrk1,1 "$QUEUE.tmp" | cut -f2- | tr '\n' '\0' > "$QUEUE"
    fi
    
    rm "$QUEUE.tmp"

    tr '\0' '\n' < "$QUEUE" > "$LOG_DIR/Queue_readable_${EXECUTION_TIMESTAMP}.txt"

    if ! [[ -s "$QUEUE" ]]; then
        echo "Aucun fichier à traiter trouvé."
        exit 0
    fi
}

###########################################################
# DRY RUN AVANCÉ (Comparaison et Anomalies)
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
                    effective_suffix="${effective_suffix}${DRYRUN_TEST_SUFFIX}"
                fi

                local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
                local final_output_basename=$(basename "$final_output")

                local generated_base_name="${final_output_basename%.mkv}"
                
                if [[ "$DRYRUN" == true ]]; then
                    generated_base_name="${generated_base_name%"$DRYRUN_TEST_SUFFIX"}"
                fi
                
                if [[ -n "$SUFFIX_STRING" ]]; then
                    generated_base_name="${generated_base_name%"$SUFFIX_STRING"}"
                fi

                count=$((count + 1))
                
                {
                    echo -e "[ $count / $total_files ]"
                    
                    local anomaly_message=""
                    
                    if [[ "$base_name" != "$generated_base_name" ]]; then
                        anomaly_count=$((anomaly_count + 1))
                        anomaly_message="🚨 ANOMALIE DÉTECTÉE : Le nom de base original diffère du nom généré sans suffixe !"
                    fi
                    
                    if [[ -n "$anomaly_message" ]]; then
                        echo "$anomaly_message"
                        echo -e "${RED}  $anomaly_message${NOCOLOR}" > $TTY_DEV
                    fi
                    
                    printf "  %-10s : %s\n" "ORIGINAL" "$filename"
                    printf "  %-10s : %s\n" "GÉNÉRÉ" "$final_output_basename"
                    
                    printf "  ${ORANGE}%-10s${NOCOLOR} : %s\n" "ORIGINAL" "$filename" > $TTY_DEV
                    printf "  ${GREEN}%-10s${NOCOLOR} : %s\n" "GÉNÉRÉ" "$final_output_basename" > $TTY_DEV
                    
                    echo ""
                
                } | tee -a "$LOG_FILE"
                
            done < "$QUEUE"
            
            {
                echo "-------------------------------------------"
                if [[ "$anomaly_count" -gt 0 ]]; then
                    echo "❌ $anomaly_count ANOMALIE(S) de nommage trouvée(s)."
                    echo "   Veuillez vérifier les caractères spéciaux ou les problèmes d'encodage pour ces fichiers."
                else
                    echo "✅ Aucune anomalie de nommage détectée."
                fi
                echo "-------------------------------------------"
            } | tee -a "$LOG_FILE"
            
            if [[ "$anomaly_count" -gt 0 ]]; then
                echo -e "${RED}❌ $anomaly_count ANOMALIE(S) de nommage trouvée(s).${NOCOLOR}" > $TTY_DEV
            else
                echo -e "${GREEN}✅ Aucune anomalie de nommage détectée.${NOCOLOR}" > $TTY_DEV
            fi
            
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
    local succ=$(wc -l < "$LOG_SUCCESS")
    local skip=$(wc -l < "$LOG_SKIPPED")
    local err=$(grep -c ' | ERROR ffmpeg | ' "$LOG_ERROR" 2>/dev/null || echo "0")
    
    {
        echo ""
        echo "-------------------------------------------"
        echo "           RÉSUMÉ DE CONVERSION            "
        echo "-------------------------------------------"
        echo "Date fin : $(date)"
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
    export -f convert_file get_video_metadata should_skip_conversion clean_number update_progress
    export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE 
    export TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR REMOVE_ORIGINAL 
    export MAXRATE BUFSIZE BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT 
    export MIN_TMP_FREE_MB RC_LOOKAHEAD SURFACES JOBS_STATE_DIR PROGRESS_LOCK
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE 
    export DRYRUN_TEST_SUFFIX SUFFIX_STRING NO_PROGRESS
}

###########################################################
# FONCTION PRINCIPALE
###########################################################

main() {
    parse_arguments "$@"
    
    SOURCE=$(cd "$SOURCE" && pwd)
    
    check_lock
    check_dependencies
    initialize_directories
    
    check_plexignore
    check_output_suffix
    
    build_queue
    
    export_for_parallel
    
    local nb_files=$(tr -cd '\0' < "$QUEUE" | wc -c)
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${CYAN}Démarrage du traitement ($nb_files fichiers)...${NOCOLOR}"
    fi
    
    aggregate_and_display_progress "$nb_files" &
    local display_pid=$!
    
    cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL"
    
    wait "$display_pid" 2>/dev/null || true
    
    dry_run_compare_names
    
    show_summary
}

###########################################################
# POINT D'ENTRÉE
###########################################################

main "$@"
