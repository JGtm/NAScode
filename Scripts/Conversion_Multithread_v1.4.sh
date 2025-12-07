#!/bin/bash

###########################################################
# TO DO
# 1. Assurer la prise en charge des fichiers avec des caractères spéciaux (type accents)
# 2. Exclure de la queue les fichiers qui ne sont pas des vidéos
# 3. S'assurer que les différents fichiers et dossiers générés ou exploités par le script existent ou sont créés
# 4. Contrôler la disponibilité de ffmpeg
###########################################################

###########################################################
# ARGUMENTS & OPTIONS
###########################################################

DRYRUN=false               # Mode simulation
SOURCE="."                  # Dossier par défaut
OUTPUT_DIR="converted"      # Dossier de destination par défaut
REMOVE_ORIGINAL=false      # Faux par défaut
# Liste des exclusions (Inclut les fichiers et dossiers générés par défaut)
EXCLUDES=("./logs" "./Conversion_Multithread.sh" "./*.sh" "./*.txt" "./Queue.txt" "$OUTPUT_DIR")

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -o|--output-dir) # NOUVEAU: Dossier de destination
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
        -r|--remove-original) # NOUVEAU: Option pour supprimer l'original
            REMOVE_ORIGINAL=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./conversion.sh [OPTIONS]"
            echo ""
            echo "Options :"
            echo "  -s, --source <dossier>     Dossier source à analyser (défaut: .)"
            echo "  -o, --output-dir <dossier> Dossier de destination (défaut: converted)"
            echo "  -e, --exclude <dossier>    Dossier à exclure (répétable)"
            echo "  -r, --remove-original      Supprime le fichier original après succès"
            echo "  -d, --dry-run              Mode simulation, aucune conversion"
            echo ""
            exit 0
            ;;
        *)
            echo "Option inconnue : $1"
            exit 1
            ;;
    esac
done

# S'assurer que le dossier de sortie est relatif à la source si la source n'est pas le répertoire courant
if [[ "$SOURCE" != "." && "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$SOURCE/$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR" # Créer le dossier de sortie

###########################################################
# FONCTION : Vérification exclusion
###########################################################
is_excluded() {
    local f="$1"
    for ex in "${EXCLUDES[@]}"; do
        # Vérifie si le chemin commence par l'exclusion ou correspond à un pattern
        if [[ "$f" == "$ex"* ]]; then
            return 0
        fi
    done
    return 1
}

############################################
# CONFIG
############################################

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

LOG_SUCCESS="$LOG_DIR/Success.log"
LOG_SKIPPED="$LOG_DIR/Skipped.log"
LOG_ERROR="$LOG_DIR/Error.log"
SUMMARY_FILE="$LOG_DIR/Summary.log"
LOG_PROGRESS="$LOG_DIR/Progress.log"
QUEUE="$LOG_DIR/Queue.txt"


touch "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$QUEUE"


PARALLEL_JOBS=3
TMP_DIR="/tmp/video_convert"
mkdir -p "$TMP_DIR"

NVENC_PRESET="p5"
CRF=25

# CORRECTION IONICE: Définition de la commande ionice si elle est disponible
IO_PRIORITY_CMD=""
if command -v ionice &> /dev/null; then
    IO_PRIORITY_CMD="ionice -c2 -n4"
fi

############################################
# FONCTION DE CONVERSION GPU AVEC BUFFER LOCAL
############################################

convert_file() {
    local file_original="$1"
    local output_dir="$2"
    local remove_original="$3"

    # 1. Obtenir le nom de base brut.
    local filename_raw=$(basename "$file_original")

    # 2. Correction ultra-robuste : Suppression des retours chariot, sauts de ligne, et autres caractères de contrôle/insécables.
    local filename=$(echo "$filename_raw" | sed 's/[\r\n]//g' | tr -d '[:cntrl:]\u00A0')
    
    # Si le nettoyage séquentiel ne marche pas (selon le système), utiliser une commande unique plus agressive :
    # local filename=$(echo "$filename_raw" | tr -d '\r\n\t\u0000-\u001F\u007F-\u009F\u00A0')

    if [[ "$DRYRUN" == true ]]; then
        echo "[DRY RUN] → $file_original"
        return 0
    fi

    # Déterminer les chemins d'entrée/sortie
    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")

    local final_dir="$output_dir/$relative_dir"
    mkdir -p "$final_dir"

    # Utilise le nom de fichier NETTOYÉ pour le chemin temporaire
    local tmp_input="$TMP_DIR/$filename" 
    local tmp_output="$TMP_DIR/${filename%.*}_x265.mkv"
    local final_output="$final_dir/${filename%.*}_x265.mkv"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS"

    ############################################
    # LECTURE FFPROBE (Version robuste)
    ############################################
    local info_video=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name,height,bit_rate \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    local ffprobe_status=$?

    if [ "$ffprobe_status" -ne 0 ] || [ -z "$info_video" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo/corrompu) | $file" >> "$LOG_SKIPPED"
        return 0
    fi
    
    local codec=$(echo "$info_video" | sed -n '1p')
    local bitrate=$(echo "$info_video" | sed -n '3p')
    local sizeBeforeMB=$(du -m "$file" | awk '{print $1}')

    ############################################
    # CONDITIONS SKIP
    ############################################
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (déjà x265) | $file" >> "$LOG_SKIPPED"
        return 0
    fi

    if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le 2300000 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED bitrate ${bitrate}bps | $file" >> "$LOG_SKIPPED"
        return 0
    fi

    ############################################
    # COPIE LOCALE
    ############################################
    cp "$file_original" "$tmp_input"

    if [[ ! -f "$tmp_input" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR copy to local tmp | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    ############################################
    # CONVERSION
    ############################################
    if $IO_PRIORITY_CMD ffmpeg -y \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" -rc vbr -cq "$CRF" \
        -c:a copy \
        "$tmp_output"; then

        # Déplacement vers la destination finale
        mv "$tmp_output" "$final_output"
        rm "$tmp_input" # Suppression du fichier temporaire

        # Suppression conditionnelle du fichier original
        if [[ "$remove_original" == true ]]; then
            rm "$file"
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS + REMOVED | $file → $final_output | ${sizeBeforeMB}MB" >> "$LOG_SUCCESS"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file → $final_output | ${sizeBeforeMB}MB" >> "$LOG_SUCCESS"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output"
    fi
}

# Export de toutes les variables et fonctions nécessaires à xargs
export -f convert_file
export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE

############################################
# CONSTRUCTION FILE (tri par taille)
############################################
echo "Indexation fichiers..." >&2

# Utilisation de find pour lister les fichiers vidéo et exclure les fichiers non-vidéo
find "$SOURCE" -type f -print0 \
    \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) \
    -not -iname "*.txt" \
    -not -iname "*.sh" \
| \
while IFS= read -r -d $'\0' f; do
    # Exclusions
    if is_excluded "$f"; then
        continue
    fi
    # Format: Taille(octets)\tChemin
    echo -e "$(stat -c%s "$f")\t$f"
done | sort -nrk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE" 

# Vérification
if ! [[ -s "$QUEUE" ]]; then
    echo "Aucun fichier à traiter trouvé dans '$SOURCE' ou tous les fichiers correspondent aux critères d'exclusion."
    rm "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" 2>/dev/null
    exit 0
fi

echo "Démarrage du traitement parallèle ($PARALLEL_JOBS jobs)..."

############################################
# TRAITEMENT PARALLÈLE
############################################

# xargs appelle la fonction convert_file en lui passant le chemin du fichier,
# le dossier de destination et l'option de suppression.
cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL"

############################################
# SUMMARY
############################################
# ... (le résumé reste le même)
success_count=$(wc -l < "$LOG_SUCCESS")
skipped_count=$(wc -l < "$LOG_SKIPPED")
error_count=$(wc -l < "$LOG_ERROR")

echo "---- Résumé ----" > "$SUMMARY_FILE"
echo "Succès  : $success_count" >> "$SUMMARY_FILE"
echo "Skip    : $skipped_count" >> "$SUMMARY_FILE"
echo "Erreurs : $error_count" >> "$SUMMARY_FILE"
echo "Terminé à : $(date)" >> "$SUMMARY_FILE"

echo "Traitement terminé. Résumé disponible dans $SUMMARY_FILE"