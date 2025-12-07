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
        -t|--test)
            TEST_MODE=true
            # Si le prochain argument est un nombre, on l'utilise comme compteur
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                TEST_COUNT="$2"
                shift 2
            else
                shift 1
            fi
            ;;
        -h|--help)
            echo "Usage: ./conversion.sh [OPTIONS]"
            echo ""
            echo "Options :"
            echo "  -s, --source <dossier>     Dossier source"
            echo "  -o, --output-dir <dossier> Dossier de destination"
            echo "  -t, --test [N]             Mode TEST: Traite N fichiers aléatoires (défaut 10)"
            echo "  -r, --remove-original      Supprime l'original après succès"
            echo "  -d, --dry-run              Simulation sans conversion (crée des fichiers vides)"
            echo ""
            exit 0
            ;;
        *)
            echo "Option inconnue : $1"
            exit 1
            ;;
    esac
done

# Définition du chemin absolu/relatif pour l'OUTPUT_DIR
if [[ "$SOURCE" != "." && "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$SOURCE/$OUTPUT_DIR"
fi

############################################
# CONFIG
############################################

# Date/heure pour l'archivage des logs
EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')

# DÉFINITION DES CHEMINS DES LOGS
LOG_DIR="./logs"
LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"
LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"
LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"
SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
QUEUE="$LOG_DIR/Queue.txt"

PARALLEL_JOBS=1
TMP_DIR="/tmp/video_convert"

# PARAMÈTRES DE CONVERSION NVENC (HEVC/x265)
# NVENC_PRESET: Vitesse de l'encodage. p5 (Bon équilibre), p7 (Max qualité), p3 (Plus rapide)
NVENC_PRESET="p5"

# CRF (-cq): Facteur de qualité constante. Plus haut = plus de compression / moins bonne qualité.
CRF=28 # 28 est un bon compromis taille/qualité pour H.265

# MAXRATE: Débit binaire maximal (en kilobits/seconde). Ex: 3000k (1080p standard)
MAXRATE="3000k"

# BUFSIZE: Taille du tampon VBV. Généralement 1.5x MAXRATE (Ex: 4500k si MAXRATE=3000k).
BUFSIZE="4500k"

# SEUIL DE BITRATE DE CONVERSION (KBPS)
BITRATE_CONVERSION_THRESHOLD_KBPS=2300

# TOLÉRANCE DU BITRATE A SKIP (%)
SKIP_TOLERANCE_PERCENT=10

# CORRECTION IONICE
IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then
    IO_PRIORITY_CMD="ionice -c2 -n4"
fi

############################################
# VÉRIFICATIONS PRÉALABLES
############################################

echo "Vérification de l'environnement..."

if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "ERREUR: ffmpeg et/ou ffprobe sont introuvables."
    exit 1
fi
if ! command -v pv &> /dev/null; then
    echo "ERREUR: pv est introuvable."
    exit 1
fi
if [ ! -d "$SOURCE" ]; then
    echo "ERREUR: Le dossier source '$SOURCE' n'existe pas."
    exit 1
fi

mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR"
touch "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$QUEUE"

# RÉINITIALISATION QUEUE SEULEMENT (Les logs sont datés donc uniques)
echo "Réinitialisation du fichier de queue..."
> "$QUEUE"

echo "Environnement validé."

############################################
# FONCTIONS UTILITAIRES
############################################

is_excluded() {
    local f="$1"
    for ex in "${EXCLUDES[@]}"; do
        if [[ "$f" == "$ex"* ]]; then
            return 0
        fi
    done
    return 1
}

# Nettoyage du bitrate
clean_number() {
    echo "$1" | sed 's/[^0-9]//g'
}
export -f clean_number

############################################
# FONCTION DE CONVERSION
############################################

convert_file() {
    # 1. IMPORTANT : Si ffmpeg échoue, le pipe entier échoue.
    # Cela évite que le script tente de faire un 'mv' sur un fichier qui n'a pas été créé.
    set -o pipefail

    local file_original="$1"
    local output_dir="$2"
    local remove_original="$3"
    
    local filename_raw=$(basename "$file_original")
    # Nettoyage : Retrait des \r et \n
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    # --- DEFINITION DES CHEMINS ---
    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")
    local final_dir="$output_dir/$relative_dir"
    
    # Nom final
    local final_output="$final_dir/${filename%.*}_x265.mkv" 

    # Noms temporaires (basés sur le PID pour garantir des caractères ASCII uniquement)
    local TMP_BASE_NAME="$$" 
    local tmp_input="$TMP_DIR/${TMP_BASE_NAME}.in" 
    local tmp_output="$TMP_DIR/${TMP_BASE_NAME}.out.mkv"
    local ffmpeg_log_temp="$TMP_DIR/${TMP_BASE_NAME}_err.log" # Log temporaire pour capturer l'erreur
    
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

    ############################################
    # LECTURE FFPROBE (Bitrate, Codec, Durée)
    ############################################
    
    local bitrate_stream=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    local bitrate_bps=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=BPS -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    local bitrate_container=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    local codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')
    local sizeBeforeBytes=$(stat -c%s "$file_original")
    
    # Extraction de la durée pour la barre de progression
    local duration_secs=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_original" 2>/dev/null)
    if [[ -z "$duration_secs" ]]; then
        duration_secs=1 
    fi

    bitrate_stream=$(clean_number "$bitrate_stream")
    bitrate_bps=$(clean_number "$bitrate_bps")
    bitrate_container=$(clean_number "$bitrate_container")
    
    local bitrate=0
    # Priorité pour déterminer le bitrate
    if [[ -n "$bitrate_stream" ]]; then bitrate="$bitrate_stream"; elif [[ -n "$bitrate_bps" ]]; then bitrate="$bitrate_bps"; elif [[ -n "$bitrate_container" ]]; then bitrate="$bitrate_container"; fi
    
    # Sécurité pour éviter erreur arithmétique si vide
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then bitrate=0; fi

    # CONDITIONS SKIP
    if [[ -z "$codec" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi

    # ----------------------------------------------------
    # LOGIQUE PERSONNALISÉE (Tolérance variable)
    # ----------------------------------------------------
    
    # Calcul de la tolérance en bits
    local base_threshold_bits=$(($BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$(($BITRATE_CONVERSION_THRESHOLD_KBPS * $SKIP_TOLERANCE_PERCENT * 10)) 
    local max_tolerated_bits=$(($base_threshold_bits + $tolerance_bits)) 
    
    # 1. Vérification du codec
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        
        # 2. Vérification du bitrate (uniquement pour les X265)
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            # SKIP : Déjà X265 ET bitrate optimisé
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà x265 et bitrate optimisé (${bitrate}bps <= ${max_tolerated_bits}bps)) | $file_original" >> "$LOG_SKIPPED"
            return 0
        fi
        
        # CONTINUER LA CONVERSION : Fichier X265 mais Bitrate TROP ÉLEVÉ
        echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage X265) | Bitrate trop élevé (${bitrate}bps) | $file_original" >> "$LOG_PROGRESS"
    fi
    
    # Si le codec est X264/autre : On continue la conversion

    ############################################
    # COPIE LOCALE
    ############################################
    echo "  → Transfert vers dossier temporaire..."
    
    # PV sans barre de progression interne pour éviter les conflits
    if ! pv -f "$file_original" > "$tmp_input"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR PV copy failed | $file_original" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null; return 1
    fi

    ############################################
    # CONVERSION GPU NVENC
    ############################################
    echo "  → Encodage NVENC"
    
    # 2. Redirection '2> $ffmpeg_log_temp' pour capturer l'erreur si ffmpeg plante
    # 3. stats_period 1 (plus rapide que 10) pour nourrir awk régulièrement
    if $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" \
        -maxrate "$MAXRATE" -bufsize "$BUFSIZE" -rc vbr -cq "$CRF" \
        -c:a copy \
        -map 0 \
        -f matroska \
        "$tmp_output" \
        -stats_period 1 \
        -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
    awk -v DURATION="$duration_secs" '
        BEGIN {
            duration = DURATION;
            last_printed = -10; # Valeur initiale pour forcer l''affichage à 0%
            if (duration < 1) { exit; }
        }
        /out_time_ms/ {
            current_time = $3 / 1000000;
            p = current_time / duration * 100;
            
            # Logique : On affiche une nouvelle ligne seulement si on a avancé de 5%
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
        echo ""
        echo "  ❌ Échec de la conversion."
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR"
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR"
        cat "$ffmpeg_log_temp" >> "$LOG_ERROR"
        echo "-------------------------------" >> "$LOG_ERROR"
        
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
    fi
}

export -f convert_file
export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR REMOVE_ORIGINAL MAXRATE BUFSIZE BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT

############################################
# CONSTRUCTION FILE
############################################
echo "Indexation fichiers..." >&2

EXCLUDE_DIR_NAME=$(basename "$OUTPUT_DIR")

# Construction de la liste complète
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
    # Mode normal : Tout trier par taille (du plus grand au plus petit)
    sort -nrk1,1 "$QUEUE.tmp" | cut -f2- | tr '\n' '\0' > "$QUEUE"
fi
rm "$QUEUE.tmp"

if ! [[ -s "$QUEUE" ]]; then
    echo "Aucun fichier à traiter trouvé."
    rm "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$QUEUE" 2>/dev/null
    exit 0
fi

############################################
# TRAITEMENT SÉQUENTIEL
############################################
NB_FILES=$(tr -cd '\0' < "$QUEUE" | wc -c)
echo "Démarrage du traitement ($NB_FILES fichiers)..."

cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL"

############################################
# SUMMARY ET FIN (Affichage dans le terminal)
############################################

success_count=$(wc -l < "$LOG_SUCCESS")
skipped_count=$(wc -l < "$LOG_SKIPPED")
error_count=$(wc -l < "$LOG_ERROR")

# Écriture du résumé
echo "-------------------------------------------" > "$SUMMARY_FILE"
echo "           RÉSUMÉ DE CONVERSION            " >> "$SUMMARY_FILE"
echo "-------------------------------------------" >> "$SUMMARY_FILE"
echo "Date fin : $(date)" >> "$SUMMARY_FILE"
echo "Succès   : $success_count" >> "$SUMMARY_FILE"
echo "Ignorés  : $skipped_count" >> "$SUMMARY_FILE"
echo "Erreurs  : $error_count" >> "$SUMMARY_FILE"
echo "-------------------------------------------" >> "$SUMMARY_FILE"

# Affichage du résumé dans le terminal
cat "$SUMMARY_FILE"
