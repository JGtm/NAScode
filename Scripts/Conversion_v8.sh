#!/bin/bash

###########################################################
# TO DO
# 1. Assurer la prise en charge des fichiers avec des caractères spéciaux (type accents)
# 2. Corriger le remplissage des logs et du fichier queue illisible
###########################################################

###########################################################
# ARGUMENTS & OPTIONS
###########################################################

DRYRUN=false               # Mode simulation
TEST_MODE=false            # Mode test aléatoire
TEST_COUNT=10              # Nombre de fichiers pour le test (défaut 10)
SOURCE="."                  # Dossier par défaut
OUTPUT_DIR="converted"      # Dossier de destination par défaut
REMOVE_ORIGINAL=false      # Faux par défaut

# Liste des exclusions
EXCLUDES=("./logs" "./*.sh" "./*.txt" "converted")

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source) SOURCE="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -e|--exclude) EXCLUDES+=("$2"); shift 2 ;;
        -d|--dry-run|--dryrun) DRYRUN=true; shift ;;
        -r|--remove-original) REMOVE_ORIGINAL=true; shift ;;
        -t|--test)
            TEST_MODE=true
            if [[ "$2" =~ ^[0-9]+$ ]]; then TEST_COUNT="$2"; shift 2; else shift 1; fi
            ;;
        -h|--help)
            echo "Usage: ./conversion.sh [OPTIONS]"
            exit 0
            ;;
        *) echo "Option inconnue : $1"; exit 1 ;;
    esac
done

# Définition du chemin absolu/relatif pour l'OUTPUT_DIR
if [[ "$SOURCE" != "." && "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$SOURCE/$OUTPUT_DIR"
fi

############################################
# CONFIGURATION
############################################

# Date/heure pour l'archivage des logs
EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')

# CHEMINS
LOG_DIR="./logs"
LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"
LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"
LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"
SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
QUEUE="$LOG_DIR/Queue.txt"

PARALLEL_JOBS=3
TMP_DIR="/tmp/video_convert"
MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp

# PROTECTION MULTI-INSTANCE
LOCKFILE="/tmp/conversion_video.lock"

# PARAMÈTRES DE CONVERSION NVENC
NVENC_PRESET="p5"
CRF=28 
MAXRATE="3000k"
BUFSIZE="4500k"

# PRE-ANALYSE DES IMAGES ET SURFACES DE MEMOIRES TAMPONS
RC_LOOKAHEAD=20 
SURFACES=16

# LOGIQUE DE SKIP
BITRATE_CONVERSION_THRESHOLD_KBPS=2300
SKIP_TOLERANCE_PERCENT=10

# CORRECTION IONICE
IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then IO_PRIORITY_CMD="ionice -c2 -n4"; fi

############################################
# GESTION DU VERROUILLAGE (TRAP)
############################################

# Fonction de nettoyage appelée à la sortie du script (ou CTRL+C)
cleanup() {
    rm -f "$LOCKFILE"
}
trap cleanup EXIT

# Vérification du verrou
if [[ -f "$LOCKFILE" ]]; then
    # Vérifie si le processus est toujours actif
    pid=$(cat "$LOCKFILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "⛔ Le script est déjà en cours d'exécution (PID $pid)."
        exit 1
    else
        echo "⚠️ Fichier lock trouvé mais processus absent. Nettoyage..."
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"

############################################
# VÉRIFICATIONS PRÉALABLES
############################################

echo "Vérification de l'environnement..."

for cmd in ffmpeg ffprobe pv; do
    if ! command -v $cmd &> /dev/null; then echo "ERREUR: $cmd introuvable."; exit 1; fi
done

if [ ! -d "$SOURCE" ]; then echo "ERREUR: Source '$SOURCE' introuvable."; exit 1; fi

mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR"
touch "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$QUEUE"

# Réinitialisation Queue
> "$QUEUE"

echo "Environnement validé."

############################################
# FONCTIONS UTILITAIRES
############################################

is_excluded() {
    local f="$1"
    for ex in "${EXCLUDES[@]}"; do
        if [[ "$f" == "$ex"* ]]; then return 0; fi
    done
    return 1
}

clean_number() { echo "$1" | sed 's/[^0-9]//g'; }
export -f clean_number

############################################
# FONCTION DE CONVERSION
############################################

convert_file() {
    set -o pipefail # Important pour capter l'erreur ffmpeg

    local file_original="$1"
    local output_dir="$2"
    local remove_original="$3"
    
    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n') # Nettoyage
    
    if [[ -z "$filename" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    # Chemins
    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")
    local final_dir="$output_dir/$relative_dir"
    local final_output="$final_dir/${filename%.*}_x265.mkv" 

    # Fichiers temporaires (PID based)
    local TMP_BASE_NAME="$$" 
    local tmp_input="$TMP_DIR/${TMP_BASE_NAME}.in" 
    local tmp_output="$TMP_DIR/${TMP_BASE_NAME}.out.mkv"
    local ffmpeg_log_temp="$TMP_DIR/${TMP_BASE_NAME}_err.log"
    
    # --- DRY RUN ---
    if [[ "$DRYRUN" == true ]]; then
        echo "[DRY RUN] 📁 Création structure : $final_dir"
        echo "[DRY RUN] 📄 Création fichier vide : $(basename "$final_output")"
        mkdir -p "$final_dir"
        touch "$final_output" 
        return 0
    fi

    mkdir -p "$final_dir"
    echo "▶️ Démarrage du fichier : $filename"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS"

    # --- VÉRIFICATION ESPACE DISQUE ---
    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}')
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    # --- LECTURE METADATA ---
    local bitrate_stream=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    local bitrate_bps=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=BPS -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    local bitrate_container=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    local codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')
    
    # Durée pour progression
    local duration_secs=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    if [[ -z "$duration_secs" ]]; then duration_secs=1; fi

    bitrate_stream=$(clean_number "$bitrate_stream")
    bitrate_bps=$(clean_number "$bitrate_bps")
    bitrate_container=$(clean_number "$bitrate_container")
    
    local bitrate=0
    if [[ -n "$bitrate_stream" ]]; then bitrate="$bitrate_stream"; elif [[ -n "$bitrate_bps" ]]; then bitrate="$bitrate_bps"; elif [[ -n "$bitrate_container" ]]; then bitrate="$bitrate_container"; fi
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then bitrate=0; fi

    # --- CONDITIONS SKIP ---
    if [[ -z "$codec" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi

    # Logique de Tolérance
    local base_threshold_bits=$(($BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$(($BITRATE_CONVERSION_THRESHOLD_KBPS * $SKIP_TOLERANCE_PERCENT * 10)) 
    local max_tolerated_bits=$(($base_threshold_bits + $tolerance_bits)) 
    
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà x265 et bitrate optimisé) | $file_original" >> "$LOG_SKIPPED"
            return 0
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage X265) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS"
    fi
    
    # --- COPIE LOCALE ---
    echo "  → Transfert vers dossier temporaire..."
    if ! pv -f "$file_original" > "$tmp_input"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR PV copy failed | $file_original" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null; return 1
    fi

    # --- CONVERSION ---
    echo "  → Encodage NVENC"
    
    if $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" \
        -maxrate "$MAXRATE" -bufsize "$BUFSIZE" -rc vbr -cq "$CRF" \
        -rc-lookahead "$RC_LOOKAHEAD" -surfaces "$SURFACES" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -stats_period 1 -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
    awk -v DURATION="$duration_secs" '
        BEGIN {
            duration = DURATION;
            last_printed = -10;
            if (duration < 1) { exit; }
        }
        /out_time_ms/ {
            current_time = $3 / 1000000;
            p = current_time / duration * 100;
            if (p - last_printed >= 5) {
                printf "    ... Progression : %.0f%%\n", p;
                fflush();
                last_printed = p;
            }
        }
    ' ; then 
        echo "    ... Progression : 100%"
        echo "  ✅ Fichier converti."
        
        mv "$tmp_output" "$final_output"
        rm "$tmp_input" "$ffmpeg_log_temp"

        local sizeAfterMB=$(du -m "$final_output" | awk '{print $1}')
        local size_comparison="${sizeBeforeMB}MB → ${sizeAfterMB}MB"

        if [ "$sizeAfterMB" -ge "$sizeBeforeMB" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: FICHIER PLUS LOURD ($size_comparison). | $LOG_SKIPPED"
        fi
        
        if [[ "$remove_original" == true ]]; then
            rm "$file_original"
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS + REMOVED | $file_original → $final_output | $size_comparison" >> "$LOG_SUCCESS"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file_original → $final_output | $size_comparison" >> "$LOG_SUCCESS"
        fi
    else
        echo ""; echo "  ❌ Échec de la conversion."
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR"
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR"
        cat "$ffmpeg_log_temp" >> "$LOG_ERROR"
        echo "-------------------------------" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
    fi
}

export -f convert_file
export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR REMOVE_ORIGINAL MAXRATE BUFSIZE BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT MIN_TMP_FREE_MB RC_LOOKAHEAD SURFACES

############################################
# CONSTRUCTION FILE
############################################
echo "Indexation fichiers..." >&2
EXCLUDE_DIR_NAME=$(basename "$OUTPUT_DIR")

find "$SOURCE" \
    -name "$EXCLUDE_DIR_NAME" -prune \
    -o \
    -type f -print0 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) \
| \
while IFS= read -r -d $'\0' f; do
    if is_excluded "$f"; then continue; fi
    if [[ "$f" =~ \.(sh|txt)$ ]]; then continue; fi
    echo -e "$(stat -c%s "$f")\t$f"
done > "$QUEUE.tmp"

# GESTION DU MODE TEST OU NORMAL
if [[ "$TEST_MODE" == true ]]; then
    echo "🎲 MODE TEST ACTIVÉ : Sélection aléatoire de $TEST_COUNT fichiers..."
    sort -R "$QUEUE.tmp" | head -n "$TEST_COUNT" | sort -nrk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE"
else
    # Mode normal
    sort -nrk1,1 "$QUEUE.tmp" | cut -f2- | tr '\n' '\0' > "$QUEUE"
fi
rm "$QUEUE.tmp"

if ! [[ -s "$QUEUE" ]]; then
    echo "Aucun fichier à traiter trouvé."
    exit 0
fi

############################################
# TRAITEMENT
############################################
NB_FILES=$(tr -cd '\0' < "$QUEUE" | wc -c)
echo "Démarrage du traitement ($NB_FILES fichiers)..."

cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL"

############################################
# RÉSUMÉ
############################################
succ=$(wc -l < "$LOG_SUCCESS")
skip=$(wc -l < "$LOG_SKIPPED")
err=$(wc -l < "$LOG_ERROR")
{
  echo "-------------------------------------------"
  echo "           RÉSUMÉ DE CONVERSION            "
  echo "-------------------------------------------"
  echo "Date fin : $(date)"
  echo "Succès   : $succ"
  echo "Ignorés  : $skip"
  echo "Erreurs  : $err"
  echo "-------------------------------------------"
} | tee "$SUMMARY_FILE"
