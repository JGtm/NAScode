#!/bin/bash

###########################################################
# TO DO
# 1. Assurer la prise en charge des fichiers avec caracteres speciaux
# 2. Gestion des erreurs FFMPEG et NVENC
###########################################################

set -uo pipefail

###########################################################
# CONFIGURATION GLOBALE
###########################################################

readonly EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
readonly LOCKFILE="/tmp/conversion_video.lock"

# Variables modifiables par arguments
DRYRUN=false
TEST_MODE=false
TEST_COUNT=10
SOURCE=".."                 # Par defaut : Dossier Parent
OUTPUT_DIR="./Converted"    # Par defaut : Sous-dossier Converted
REMOVE_ORIGINAL=false
FORCE_NO_SUFFIX=false
PARALLEL_JOBS=3
SHOW_PROGRESS=true
LIMIT_FILES=0
MANUAL_QUEUE_FILE=""
NO_PROGRESS=false            # Potentiellement doublon
QUEUE_FILE=""                # Potentiellement doublon
USE_EXISTING_QUEUE=false     # Potentiellement doublon
PROCESS_LIMIT=0              # Potentiellement doublon

# Version FFMPEG minimale
readonly FFMPEG_MIN_VERSION=6 

readonly DRYRUN_TEST_SUFFIX="-dryrun-sample"
SUFFIX_STRING="_x265"

# Exclusions
EXCLUDES=("./logs" "./*.sh" "./*.txt" "Converted" "Conversion")

# Variable pour l arret propre par Ctrl+C
XARGS_PID=""

###########################################################
# COULEURS ANSI (Format corrige)
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
readonly QUEUE="$LOG_DIR/Queue"
readonly LOG_DRYRUN_COMPARISON="$LOG_DIR/DryRun_Comparison_${EXECUTION_TIMESTAMP}.log"

###########################################################
# PARAMETRES TECHNIQUES
###########################################################

# readonly TMP_DIR="/tmp/video_convert"
# Cette approche force l'utilisation du dossier Temp de Windows (ex: C:\Users\User\AppData\Local\Temp).
readonly TMP_DIR="/tmp/video_convert_tmp"
readonly STATUS_DIR="$TMP_DIR/status"
readonly MIN_TMP_FREE_MB=2048 

# NVENC SETTINGS
readonly NVENC_PRESET="p5"
readonly CRF=28 
readonly MAXRATE="3000k"
readonly BUFSIZE="4500k"
readonly BITRATE_CONVERSION_THRESHOLD_KBPS=2300
readonly SKIP_TOLERANCE_PERCENT=10
readonly RC_LOOKAHEAD=20 
readonly SURFACES=16 

IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then IO_PRIORITY_CMD="ionice -c2 -n4"; fi

###########################################################
# GESTION DES ARGUMENTS
###########################################################

show_help() {
    cat << EOF
Usage: ./conversion.sh [OPTIONS]
Options:
  -s, --source DIR          Dossier source (defaut: ..)
  -o, --output-dir DIR      Dossier de destination (defaut: ./Converted)
  -q, --queue FILE          Utiliser un fichier Queue existant
  -l, --limit N             Traiter seulement les N premiers fichiers
  -e, --exclude PATTERN     Ajouter un pattern d exclusion
  -d, --dry-run             Mode simulation
  -r, --remove-original     Supprimer les fichiers originaux
  -n, --no-suffix           Desactiver le suffixe _x265
  --no-progress             Desactiver l affichage dynamique
  -t, --test [N]            Mode test (defaut: 10 fichiers)
  -h, --help                Aide
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source) SOURCE="$2"; shift 2 ;;
            -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
            -q|--queue) MANUAL_QUEUE_FILE="$2"; shift 2 ;;
            -l|--limit) 
                if [[ "$2" =~ ^[0-9]+$ ]]; then LIMIT_FILES="$2"; shift 2; else echo -e "${RED}Erreur: Limit invalide${NOCOLOR}"; exit 1; fi 
                ;;
            -e|--exclude) EXCLUDES+=("$2"); shift 2 ;;
            -d|--dry-run|--dryrun) DRYRUN=true; shift ;;
            -r|--remove-original) REMOVE_ORIGINAL=true; shift ;;
            -n|--no-suffix) FORCE_NO_SUFFIX=true; shift ;;
            --no-progress) SHOW_PROGRESS=false; shift ;;
            -t|--test)
                TEST_MODE=true
                if [[ "${2:-}" =~ ^[0-9]+$ ]]; then TEST_COUNT="$2"; shift 2; else shift 1; fi
                ;;
            -h|--help) show_help; exit 0 ;;
            *) echo -e "${RED}Option inconnue : $1${NOCOLOR}"; show_help; exit 1 ;;
        esac
    done
}

###########################################################
# GESTION DU VERROUILLAGE ET ARRET PROPRE
###########################################################

# Fonction appelee uniquement lors d'un CTRL+C (SIGINT) ou SIGTERM
handle_interrupt() {
    if [[ -n "$XARGS_PID" ]]; then
        echo -e "\n${YELLOW}SIGINT recu. Arret des jobs en cours...${NOCOLOR}" > /dev/tty
        
        # Envoie SIGTERM a Xargs et tous ses descendants
        if ! kill -TERM -- "-$XARGS_PID" 2>/dev/null; then
             kill -TERM "$XARGS_PID" 2>/dev/null
        fi
    fi
    exit 1 # Quitte pour declencher le cleanup final
}

# Fonction appelee a la fin du script (Succes ou Erreur)
cleanup() {
    rm -f "$LOCKFILE"
    rm -rf "$STATUS_DIR" 2>/dev/null
}

# On separe les traps :
# INT/TERM declenchent l'interruption (kill xargs)
trap handle_interrupt INT TERM
# EXIT declenche uniquement le nettoyage (rm lockfile)
trap cleanup EXIT

check_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid=$(cat "$LOCKFILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${RED}⛔ Le script est deja en cours d execution (PID $pid).${NOCOLOR}"
            exit 1
        else
            echo -e "${YELLOW}⚠️ Fichier lock trouve mais processus absent. Nettoyage...${NOCOLOR}"
            rm -f "$LOCKFILE"
        fi
    fi
    echo $$ > "$LOCKFILE"
}

###########################################################
# VERIFICATIONS SYSTEME
###########################################################

check_dependencies() {
    echo "Verification de l environnement..."
    local missing_deps=()
    for cmd in ffmpeg ffprobe pv bc; do
        if ! command -v "$cmd" &> /dev/null; then missing_deps+=("$cmd"); fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}ERREUR: Dependances manquantes: ${missing_deps[*]}${NOCOLOR}"
        exit 1
    fi

    local ffmpeg_version_raw
    ffmpeg_version_raw=$(ffmpeg -version | head -n1 | grep -oE 'version [0-9]+' | cut -d ' ' -f2)
    
    if [[ "$ffmpeg_version_raw" =~ ^[0-9]+$ ]]; then
        if (( ffmpeg_version_raw < FFMPEG_MIN_VERSION )); then
             echo -e "${YELLOW}⚠️ ALERTE: Version FFMPEG ($ffmpeg_version_raw) < Recommandee ($FFMPEG_MIN_VERSION).${NOCOLOR}"
        else
             echo -e "   - FFMPEG Version : ${GREEN}$ffmpeg_version_raw${NOCOLOR} (OK)"
        fi
    fi
    
    if [[ ! -d "$SOURCE" ]]; then
        echo -e "${RED}ERREUR: Source '$SOURCE' introuvable.${NOCOLOR}"
        exit 1
    fi
    echo -e "${GREEN}Environnement valide.${NOCOLOR}"
}

initialize_directories() {
    mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR" "$STATUS_DIR"
    for log_file in "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$LOG_DRYRUN_COMPARISON"; do
        touch "$log_file"
    done
}

###########################################################
# FONCTIONS UTILITAIRES
###########################################################

is_excluded() {
  local f="$1"
  for ex in "${EXCLUDES[@]}"; do
    case "$f" in
      "$ex"*) return 0 ;;
    esac
  done
  return 1
}

clean_number() { echo "$1" | sed 's/[^0-9]//g'; }

cleanup_output_area() {
    local message="$1"
    local TTY_DEV="/dev/tty"
    
    # Affiche le message, efface la fin de la ligne, et fait UN SEUL saut de ligne.
    printf "\r%s\033[K\n" "$message" > "$TTY_DEV"
}

###########################################################
# GESTION PLEXIGNORE & SUFFIXE
###########################################################

check_plexignore() {
    local source_abs=$(readlink -f "$SOURCE")
    local output_abs=$(readlink -f "$OUTPUT_DIR")
    local plexignore_file="$OUTPUT_DIR/.plexignore"

    if [[ "$output_abs"/ != "$source_abs"/ ]] && [[ "$output_abs" = "$source_abs"/* ]]; then
        if [[ "$REMOVE_ORIGINAL" == false ]]; then
            if [[ -f "$plexignore_file" ]]; then
                echo -e "${GREEN}\nℹ️ Fichier .plexignore present.${NOCOLOR}"
                return 0
            fi
            echo ""
            read -r -p "Creer .plexignore dans '$OUTPUT_DIR' ? (O/n) " response < /dev/tty
            case "$response" in
                [oO]|[yY]|'') echo "*" > "$plexignore_file"; echo -e "${GREEN}✅ .plexignore cree.${NOCOLOR}" ;;
                *) echo -e "${CYAN}⏭️ Ignore.${NOCOLOR}" ;;
            esac
        fi
    fi
}

check_output_suffix() {
    local source_abs=$(readlink -f "$SOURCE")
    local output_abs=$(readlink -f "$OUTPUT_DIR")
    local is_same_dir=false
    [[ "$source_abs" == "$output_abs" ]] && is_same_dir=true

    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        echo -e "${ORANGE}ℹ️ Option --no-suffix : Suffixe desactive.${NOCOLOR}"
    else
        read -r -p "Utiliser le suffixe ('$SUFFIX_STRING') ? (O/n) " response < /dev/tty
        case "$response" in
            [nN]) SUFFIX_STRING=""; echo -e "${YELLOW}⚠️ Suffixe desactive.${NOCOLOR}" ;;
            *) echo -e "${GREEN}✅ Suffixe utilise.${NOCOLOR}" ;;
        esac
    fi

    if [[ -z "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
        echo -e "${MAGENTA}\n🚨 ALERTE CRITIQUE : RISQUE D ECRASMENT (Meme dossier, sans suffixe) 🚨${NOCOLOR}"
        read -r -p "Continuer ? (O/n) " final_confirm < /dev/tty
        case "$final_confirm" in
            [oO]|[yY]|'') echo "Continuation..." ;;
            *) exit 1 ;;
        esac
    fi
}

###########################################################
# CONVERSION
###########################################################

get_video_metadata() {
    local file="$1"
    local output
    output=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate,codec_name:stream_tags=BPS:format=bit_rate,duration -of default=noprint_wrappers=1 "$file" 2>/dev/null)
    local br_st=$(echo "$output" | grep '^bit_rate=' | head -1 | cut -d= -f2)
    local br_bps=$(echo "$output" | grep '^TAG:BPS=' | cut -d= -f2)
    local br_fmt=$(echo "$output" | grep '^\[FORMAT\]' -A10 | grep '^bit_rate=' | cut -d= -f2)
    local codec=$(echo "$output" | grep '^codec_name=' | cut -d= -f2)
    local dur=$(echo "$output" | grep '^duration=' | cut -d= -f2)
    
    br_st=$(clean_number "$br_st"); br_bps=$(clean_number "$br_bps"); br_fmt=$(clean_number "$br_fmt")
    local br=0
    [[ -n "$br_st" ]] && br=$br_st || { [[ -n "$br_bps" ]] && br=$br_bps || { [[ -n "$br_fmt" ]] && br=$br_fmt; }; }
    [[ ! "$br" =~ ^[0-9]+$ ]] && br=0
    [[ -z "$dur" ]] && dur=1
    echo "${br}|${codec}|${dur}"
}

convert_file() {
    set -o pipefail
    local file_original="$1"
    local output_dir="$2"
    local remove_original="$3"
    local TTY_DEV="/dev/tty"

    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    [[ -z "$filename" ]] && return 1

    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local final_dir="$output_dir/$(dirname "$relative_path")"
    local base_name="${filename%.*}"
    
    local effective_suffix="$SUFFIX_STRING"
    [[ "$DRYRUN" == true ]] && effective_suffix="${effective_suffix}${DRYRUN_TEST_SUFFIX}"
    local final_output="$final_dir/${base_name}${effective_suffix}.mkv"

    # Fichiers temporaires
    # Fichiers temporaires
    local pid_unique="${BASHPID:-$$}"
    local tmp_input="$TMP_DIR/${pid_unique}.in"
    local tmp_output="$TMP_DIR/${pid_unique}.out.mkv"
    local log_err="$TMP_DIR/${pid_unique}_err.log"
    local status_file="$STATUS_DIR/${pid_unique}.status"
    local progress_tmp_file="$TMP_DIR/${pid_unique}.progress"

    # Verification existence
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        cleanup_output_area "${BLUE}⏭️ SKIPPED (Existe deja) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Exists) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi

    if [[ "$DRYRUN" == true ]]; then
        echo -e "${CYAN}[DRY RUN] 📄 Cible : $(basename "$final_output")${NOCOLOR}" > "$TTY_DEV"
        mkdir -p "$final_dir"
        touch "$final_output"
        return 0
    fi

    mkdir -p "$final_dir"
    
    # Init du fichier statut (printf utilise)
    printf "STARTING|0|%s\n" "$filename" > "$status_file"
    printf "%s | START | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$file_original" >> "$LOG_PROGRESS"

    # Metadata
    local metadata
    metadata=$(get_video_metadata "$file_original")
    IFS='|' read -r bitrate codec duration <<< "$metadata"
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')

    # SKIP LOGIC
    local skip=false
    local skip_reason=""
    if [[ -z "$codec" ]]; then skip=true; skip_reason="Pas de flux video"; fi
    
    if [[ "$skip" == false && ("$codec" == "hevc" || "$codec" == "h265") ]]; then
        local limit=$(( (BITRATE_CONVERSION_THRESHOLD_KBPS * 1000) + (BITRATE_CONVERSION_THRESHOLD_KBPS * SKIP_TOLERANCE_PERCENT * 10) ))
        if [[ "$bitrate" -le "$limit" ]]; then skip=true; skip_reason="Deja x265 & optimise"; fi
    fi

    if [[ "$skip" == true ]]; then
        cleanup_output_area "${BLUE}⏭️ SKIPPED ($skip_reason) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED ($skip_reason) | $file_original" >> "$LOG_SKIPPED"
        rm -f "$status_file"
        return 0
    fi
    
    # 1. Copie du fichier dans le repertoire temporaire
    # AFFICHAGE DE LA BARRE DE PROGRESSION AVEC PV
    echo -e "${CYAN}→ Transfert de [$filename]...${NOCOLOR}" > "$TTY_DEV"
    
    # pv affiche la barre sur stderr. On redirige stderr vers /dev/tty (le terminal) pour l'afficher.
    if ! pv "$file_original" --progress --timer --rate --eta 2> "$TTY_DEV" > "$tmp_input"; then
        cleanup_output_area "${RED}❌ ERROR Copie : $filename${NOCOLOR}"
        printf "%s | ERROR Copy | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$file_original" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$log_err" "$status_file"; return 1
    fi
    
    # Ligne vide pour séparer la progression PV de la progression dynamique FFMPEG
    # echo "" > "$TTY_DEV" 

    echo "→ Encodage NVENC : $filename" > "$TTY_DEV"

    # 2. Démarrage du lecteur de progression en arriere-plan
    # Utilisation de 'tail -f' pour simuler la lecture d'un pipe sur le fichier temporaire
    (
        # tail -f -n 0 commence a lire a partir de la fin du fichier, et attend les nouvelles donnees
        # L'utilisation de 'tail -f' est le moyen le plus robuste de lire la progression d'un fichier
        # écrit par une application Windows dans un environnement Bash.
        tail -f -n 0 "$progress_tmp_file" 2>/dev/null | while read -r line; do
            if [[ "$line" == out_time_us=* ]]; then
                current_us=${line#out_time_us=}
                # CALCUL DE PROGRESSION SECURISE (AWK)
                pct=$(awk "BEGIN {
                    duration=0; 
                    if (\"$duration\" ~ /^[0-9]+(\.[0-9]+)?$/) { duration=\"$duration\" + 0; }
                    current_us=\"$current_us\" + 0;
                    if (duration > 0) {
                        pct = (current_us / 1000000) / duration * 100;
                        if (pct > 100) { pct = 100; }
                        printf \"%.0f\", pct;
                    } else { print 0; }
                }")
                # Mise a jour du fichier de statut
                printf "RUNNING|%s|%s\n" "$pct" "$filename" > "$status_file"
            elif [[ "$line" == "progress=end" ]]; then
                printf "DONE|100|%s\n" "$filename" > "$status_file"
            fi
        done
    ) &
    local READER_PID=$! # Capture du PID du sous-processus de lecture

    # 3. Execution de FFmpeg (ecriture directement dans le fichier temporaire)
    $IO_PRIORITY_CMD ffmpeg -y -loglevel error \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" \
        -maxrate "$MAXRATE" -bufsize "$BUFSIZE" -rc vbr -cq "$CRF" \
        -rc-lookahead "$RC_LOOKAHEAD" -surfaces "$SURFACES" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -progress "$progress_tmp_file" -nostats 2> "$log_err" 
        
    local FFMPEG_EXIT_CODE=$?

    # 4. Nettoyage du lecteur et du fichier temporaire de progression
    kill "$READER_PID" 2>/dev/null # Arrêt du processus tail -f
    rm -f "$progress_tmp_file" 

    if [ "$FFMPEG_EXIT_CODE" -eq 0 ]; then
        # SUCCES
        cleanup_output_area "${GREEN}✅ Fichier converti : $filename${NOCOLOR}"
        mv "$tmp_output" "$final_output"
        rm -f "$tmp_input" "$log_err" "$status_file"

        local sizeAfterMB=$(du -m "$final_output" | awk '{print $1}')
        printf "%s | SUCCESS | %s -> %s | %sMB->%sMB\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$file_original" "$final_output" "$sizeBeforeMB" "$sizeAfterMB" >> "$LOG_SUCCESS"
        if [[ "$remove_original" == true ]]; then rm "$file_original"; fi
    else
        # ECHEC
        cleanup_output_area "${RED}❌ Echec : $filename (Code $FFMPEG_EXIT_CODE)${NOCOLOR}"
        
        printf "%s | ERROR ffmpeg | %s | Exit Code: %d\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$file_original" "$FFMPEG_EXIT_CODE" >> "$LOG_ERROR"
        cat "$log_err" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output" "$log_err" "$status_file" 2>/dev/null
    fi
}

###########################################################
# CONSTRUCTION DE LA FILE D ATTENTE (QUEUE)
###########################################################

build_queue() {
    local absolute_output_dir="$1"

    if [[ -n "$MANUAL_QUEUE_FILE" ]]; then
        echo -e "${MAGENTA}Mode Queue Manuelle active : $MANUAL_QUEUE_FILE${NOCOLOR}"
        if [[ ! -f "$MANUAL_QUEUE_FILE" ]]; then echo -e "${RED}Fichier introuvable.${NOCOLOR}"; exit 1; fi
        cp "$MANUAL_QUEUE_FILE" "$QUEUE"
        # Continue pour appliquer la limite si elle est fixee.
    elif [[ -s "$QUEUE" ]]; then
        local count_existing=$(wc -l < "$QUEUE")
        echo -e "${YELLOW}Une file d attente existante contient $count_existing fichiers.${NOCOLOR}"
        read -r -p "Voulez-vous conserver ce fichier (C) ou le regenerer (R) ? (C/r) " resp < /dev/tty
        case "$resp" in
            [rR]) echo "Regeneration..." ;;
            *) 
                # Si pas de limite fixee, on peut retourner immediatement.
                if [[ "$LIMIT_FILES" -eq 0 ]]; then
                    echo "Reprise de la file existante sans limite."
                    return
                fi
                echo "Reprise de la file existante pour appliquer la limite."
                ;;
        esac
    fi

    # Generation de la queue si elle n'est pas encore prete (i.e. si R, ou pas de fichier existant, ou MANUEL_QUEUE_FILE non defini)
    if [[ ! -s "$QUEUE" ]] || [[ "$resp" == [rR] ]]; then
        echo "Indexation fichiers en cours..." >&2

        find "$SOURCE" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 | \
            while IFS= read -r -d $'\0' f; do
                # EXCLUSION ROBUSTE DU DOSSIER DE SORTIE
                if [[ "$f" == "$absolute_output_dir"* ]]; then continue; fi
                
                if is_excluded "$f"; then continue; fi
                if [[ "$f" =~ \.(sh|txt)$ ]]; then continue; fi
                echo -e "$(stat -c%s "$f")\t$f"
            done | pv -l -N "Fichiers trouves" > "$QUEUE.tmp"

        if [[ "$TEST_MODE" == true ]]; then
            echo "🎲 MODE TEST : $TEST_COUNT fichiers"
            sort -R "$QUEUE.tmp" | head -n "$TEST_COUNT" | sort -nrk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE"
        else
            sort -nrk1,1 "$QUEUE.tmp" | cut -f2- | tr '\n' '\0' > "$QUEUE"
        fi
        rm "$QUEUE.tmp"
    fi

    # Application de la LIMITATION (S'applique a la queue prete, peu importe sa source)
    if [[ "$LIMIT_FILES" -gt 0 ]]; then
        if ! [[ -s "$QUEUE" ]]; then echo "Aucun fichier a traiter pour appliquer la limite."; exit 0; fi

        echo -e "${ORANGE}Limitation activee : Traitement des $LIMIT_FILES premiers fichiers.${NOCOLOR}"
        local tmp_limit="$QUEUE.limit"
        
        # Le fichier QUEUE est separe par \0.
        # On le convertit en lignes, on prend la tete, et on reconvertit en \0.
        tr '\0' '\n' < "$QUEUE" | head -n "$LIMIT_FILES" | tr '\n' '\0' > "$tmp_limit"
        mv "$tmp_limit" "$QUEUE"
    fi

    if ! [[ -s "$QUEUE" ]]; then echo "Aucun fichier a traiter."; exit 0; fi
}

###########################################################
# FONCTION DRY RUN
###########################################################
dry_run_compare_names() {
    if [[ "$DRYRUN" != true ]]; then return 0; fi

    local TTY_DEV="/dev/tty"
    local LOG_FILE="$LOG_DRYRUN_COMPARISON"

    echo "" > $TTY_DEV
    read -r -p "Souhaitez-vous afficher la comparaison entre les noms de fichiers originaux et generes ? (O/n) " response < $TTY_DEV
    
    case "$response" in
        [oO]|[yY]|'')
            echo -e "\n-------------------------------------------" > $TTY_DEV
            echo -e "${MAGENTA}      SIMULATION DES NOMS DE FICHIERS${NOCOLOR}" > $TTY_DEV
            echo -e "-------------------------------------------" > $TTY_DEV
            echo "Statut|Fichier Original|Fichier Genere" > "$LOG_FILE"
            
            local total_files=$(tr -cd '\0' < "$QUEUE" | wc -c)
            local count=0
            local anomaly_count=0 
            
            while IFS= read -r -d $'\0' file_original; do
                local filename_raw=$(basename "$file_original")
                local filename=$(echo "$filename_raw" | tr -d '\r\n')
                local base_name="${filename%.*}"

                local effective_suffix="$SUFFIX_STRING"
                if [[ "$DRYRUN" == true ]]; then effective_suffix="${effective_suffix}${DRYRUN_TEST_SUFFIX}"; fi

                local final_output="$OUTPUT_DIR/${base_name}${effective_suffix}.mkv" 
                local final_output_basename=$(basename "$final_output")

                local generated_base_name="${final_output_basename%.mkv}"
                if [[ "$DRYRUN" == true ]]; then generated_base_name="${generated_base_name%"$DRYRUN_TEST_SUFFIX"}"; fi
                if [[ -n "$SUFFIX_STRING" ]]; then generated_base_name="${generated_base_name%"$SUFFIX_STRING"}"; fi

                count=$((count + 1))
                echo -e "${CYAN}[ $count / $total_files ]${NOCOLOR}" > $TTY_DEV
                
                if [[ "$base_name" != "$generated_base_name" ]]; then
                    anomaly_count=$((anomaly_count + 1))
                    printf "ANOMALIE|%s|%s\n" "${filename}" "${final_output_basename}" >> "$LOG_FILE"
                    echo -e "  ${RED}🚨 ANOMALIE DETECTEE : Le nom de base original differe du nom genere sans suffixe !${NOCOLOR}" > $TTY_DEV
                fi
                
                printf "  ${ORANGE}%-10s${NOCOLOR} : %s\n" "ORIGINAL" "$filename" > $TTY_DEV
                printf "  ${GREEN}%-10s${NOCOLOR} : %s\n" "GENERE" "$final_output_basename" > $TTY_DEV
                echo "" > $TTY_DEV
            done < "$QUEUE"
            
            echo "-------------------------------------------" >> "$LOG_FILE"
            echo "RESUME FINAL" >> "$LOG_FILE"
            echo "ANOMALIES DE NOMMAGE TROUVEES : $anomaly_count" >> "$LOG_FILE"
            echo "-------------------------------------------" >> "$LOG_FILE"
            
            echo "-------------------------------------------" > $TTY_DEV
            if [[ "$anomaly_count" -gt 0 ]]; then
                echo -e "${RED}❌ $anomaly_count ANOMALIE(S) de nommage trouvee(s).${NOCOLOR}" > $TTY_DEV
            else
                echo -e "${GREEN}✅ Aucune anomalie de nommage detectee.${NOCOLOR}" > $TTY_DEV
            fi
            echo "-------------------------------------------" > $TTY_DEV
            ;;
        [nN]|*) echo "Comparaison des noms ignoree." > $TTY_DEV ;;
    esac
}

###########################################################
# EXPORT
###########################################################

export_for_parallel() {
    export -f convert_file get_video_metadata clean_number cleanup_output_area
    export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE STATUS_DIR
    export TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR REMOVE_ORIGINAL 
    export MAXRATE BUFSIZE BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT 
    export MIN_TMP_FREE_MB RC_LOOKAHEAD SURFACES FFMPEG_MIN_VERSION
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE 
    export DRYRUN_TEST_SUFFIX SUFFIX_STRING
}

###########################################################
# MAIN
###########################################################

main() {
    parse_arguments "$@"
    check_lock
    check_dependencies
    initialize_directories

    local ABSOLUTE_OUTPUT_DIR
    ABSOLUTE_OUTPUT_DIR=$(readlink -f "$OUTPUT_DIR")

    check_plexignore
    check_output_suffix
    build_queue "$ABSOLUTE_OUTPUT_DIR"
    export_for_parallel
    
    local nb_files=0; while IFS= read -r -d $'\0' _; do nb_files=$((nb_files+1)); done < "$QUEUE"
    echo -e "${CYAN}Demarrage du traitement ($nb_files fichiers) - Jobs: $PARALLEL_JOBS${NOCOLOR}"

    # Lancement de Xargs en arriere plan
    cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL" &
    XARGS_PID=$! # Assignation a la variable globale pour le trap

    # BOUCLE DE MONITORING (Affichage Multiligne Propre)
    if [[ "$SHOW_PROGRESS" == true && "$DRYRUN" == false ]]; then
        local TTY_DEV="/dev/tty"
        echo -e "${MAGENTA}\n--- Progression Encours (Max $PARALLEL_JOBS jobs) ---${NOCOLOR}" > "$TTY_DEV"
        
        local last_line_count=0

        while kill -0 $XARGS_PID 2>/dev/null; do
            local status_files
            status_files=$(find "$STATUS_DIR" -maxdepth 1 -type f -name "*.status" | sort)
            
            local active_lines=()
            while IFS= read -r sfile; do
                if [[ -s "$sfile" ]]; then
                    IFS='|' read -r state pct name <<< "$(cat "$sfile")"
                    if [[ "$state" == "RUNNING" ]]; then
                        active_lines+=("${GREEN}[ ${pct}% ]${NOCOLOR} ${CYAN}${name}${NOCOLOR}")
                    fi
                fi
            done <<< "$status_files"
            
            local current_count=${#active_lines[@]}

            # 1. Remonter le curseur pour effacer l'affichage precedent
            if [[ "$last_line_count" -gt 0 ]]; then
                # Remonte le curseur de 'last_line_count' lignes (sequence ANSI fiable)
                printf "\033[%dA" "$last_line_count" > "$TTY_DEV" 2>/dev/null || true 
            fi

            # 2. Afficher les lignes actives et les effacer correctement
            for line in "${active_lines[@]}"; do
                # \r deplace au debut de ligne, \033[K efface le reste de la ligne, \n passe a la suivante
                printf "\r%s\033[K\n" "$line" > "$TTY_DEV"
            done
            
            # 3. Effacer les lignes excédentaires (celles du cycle precedent qui ne sont plus utilisees)
            local lines_to_clear=$((last_line_count - current_count))
            if [[ "$lines_to_clear" -gt 0 ]]; then
                for ((i=1; i<=lines_to_clear; i++)); do
                     # Efface la ligne courante et passe a la suivante
                     echo -e "\r\033[K" > "$TTY_DEV"
                done
                # Remonter le curseur pour le positionner apres la derniere ligne affichee (au debut de la ligne vide)
                printf "\033[%dA" "$lines_to_clear" > "$TTY_DEV" 2>/dev/null || true
            fi

            # Mise a jour du compteur pour le prochain tour
            last_line_count=$current_count
            
            sleep 2
        done
        
        # S'assurer qu'apres l'arret des jobs, l'affichage est propre
        if [[ "$last_line_count" -gt 0 ]]; then
            printf "\033[%dA" "$last_line_count" > "$TTY_DEV" 2>/dev/null || true
            for ((i=1; i<=last_line_count; i++)); do
                 echo -e "\r\033[K" > "$TTY_DEV" 
            done
        fi
        echo "" > "$TTY_DEV"
    else
        wait $XARGS_PID
    fi
    
    dry_run_compare_names
    
    # RESUME (Correction du double '0' et utilisation de la meilleure methode de grep)
    local succ=$(wc -l < "$LOG_SUCCESS")
    local skip=$(wc -l < "$LOG_SKIPPED")
    local err=$(grep -c ' | ERROR ffmpeg | ' "$LOG_ERROR" 2>/dev/null || true)
    
    echo "Succes: $succ | Ignores: $skip | Erreurs: ${err:-0}" | tee "$SUMMARY_FILE"
}

main "$@"