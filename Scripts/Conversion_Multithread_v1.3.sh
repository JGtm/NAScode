#!/bin/bash

###########################################################
# TO DO
# 1. Exclure de la queue les fichiers qui ne sont pas des vidéos
# 2. S'assurer que les différents fichiers et dossiers générés ou exploités par le script existent ou sont créés
# 3. Contrôler la disponibilité de ffmpeg
###########################################################

###########################################################
# ARGUMENTS & OPTIONS
###########################################################

DRYRUN=false               # Mode simulation
SOURCE="."                  # Dossier par défaut

# Liste des exclusions (Ajout des logs et du script par défaut pour éviter les faux positifs)
EXCLUDES=("./logs" "./Conversion_Multithread.sh" "./*.sh" "./*.txt" "./Queue.txt")

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source)
            SOURCE="$2"
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
        -h|--help)
            echo "Usage: ./conversion.sh [OPTIONS]"
            echo ""
            echo "Options :"
            echo "  -s, --source <dossier>   Dossier source à analyser"
            echo "  -e, --exclude <dossier>  Dossier à exclure (répétable)"
            echo "  -d, --dry-run            Mode simulation, aucune conversion"
            echo ""
            exit 0
            ;;
        *)
            echo "Option inconnue : $1"
            exit 1
            ;;
    esac
done

###########################################################
# FONCTION : Vérification exclusion
###########################################################

is_excluded() {
    local f="$1"
    for ex in "${EXCLUDES[@]}"; do
        # Vérifie si le chemin commence par l'exclusion ou correspond à un pattern de fichier/extension
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


PARALLEL_JOBS=3   # NAS-friendly (évite la saturation réseau)
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
    local file="$1" # Le chemin d'origine, complet et correctement transmis par xargs -0
    
    # 1. Obtenir le nom de base brut.
    local filename_raw=$(basename "$file")

    # 2. Nettoyer (sanitiser) le nom de fichier :
    # tr -d '[:cntrl:]' retire tous les caractères de contrôle (dont les retours chariot).
    # tr -d '\u00A0' retire spécifiquement l'espace insécable (si votre environnement le supporte).
    local filename=$(echo "$filename_raw" | tr -d '[:cntrl:]' | tr -d '\u00A0')
    
    # Si le nettoyage ci-dessus pose problème (selon le système), utiliser une alternative plus simple :
    # local filename=$(echo "$filename_raw" | tr -d '[:cntrl:]')
    
    if [[ "$DRYRUN" == true ]]; then
        echo "[DRY RUN] → $file"
        return 0
    fi

    local tmp_input="$TMP_DIR/$filename" # Utilise le nom de fichier NETTOYÉ pour l'entrée temporaire
    local tmp_output="$TMP_DIR/${filename%.*}_x265.mkv"
    local final_output="${file%.*}_x265.mkv" # Utilise le chemin d'origine pour la destination finale

    echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file" >> "$LOG_PROGRESS"

    ############################################
    # LECTURE FFPROBE (1 seule fois) - Version robuste
    ############################################

    # Appel ffprobe pour obtenir le codec, la hauteur et le bitrate du PREMIER flux vidéo (v:0)
    # Remplacer tout le bloc FFPROBE par cette version simplifiée et robuste
    local info_video=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name,height,bit_rate \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    local ffprobe_status=$?

    # Vérification du code de sortie ($?): 0 = Succès (flux vidéo trouvé), >0 = Erreur (pas de flux vidéo ou corrompu)
    if [ "$ffprobe_status" -ne 0 ] || [ -z "$info_video" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo/corrompu) | $file" >> "$LOG_SKIPPED"
        return 0
    fi
    
    # Extraction des valeurs à partir de la sortie réussie
    local codec=$(echo "$info_video" | sed -n '1p')
    local height=$(echo "$info_video" | sed -n '2p')
    local bitrate=$(echo "$info_video" | sed -n '3p')

    # Vérification additionnelle : si le codec est vide, c'est un échec de lecture
    if [[ -z "$codec" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (flux vidéo vide) | $file" >> "$LOG_SKIPPED"
        return 0
    fi
    
    local sizeBeforeMB=$(du -m "$file" | awk '{print $1}')

    ############################################
    # CONDITIONS SKIP
    ############################################
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (déjà x265) | $file" >> "$LOG_SKIPPED"
        return 0
    fi

    ## if [[ "$height" -le 1080 ]]; then
    ##     echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED resolution ${height}px | $file" >> "$LOG_SKIPPED"
    ##     return 0
    ## fi

    if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le 2300000 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED bitrate ${bitrate}bps | $file" >> "$LOG_SKIPPED"
        return 0
    fi

    ############################################
    # COPIE LOCALE (optimisation NAS)
    ############################################
    cp "$file" "$tmp_input"

    if [[ ! -f "$tmp_input" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR copy to local tmp | $file" >> "$LOG_ERROR"
        return 1
    fi

    ############################################
    # CONVERSION GPU NVENC VIA BUFFER LOCAL
    ############################################
    # CORRECTION IONICE: Utilisation de la variable (vide si ionice non disponible)
    if $IO_PRIORITY_CMD ffmpeg -y \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" -rc vbr -cq "$CRF" \
        -c:a copy \
        "$tmp_output"; then

        mv "$tmp_output" "$final_output"
        rm "$file" "$tmp_input"

        echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file → $final_output | ${sizeBeforeMB}MB" >> "$LOG_SUCCESS"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output"
    fi
}

# Mise à jour de l'exportation pour inclure la variable ionice
export -f convert_file
export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD

############################################
# CONSTRUCTION FILE (tri par taille)
############################################
echo "Indexation fichiers..." >&2

# Utilisation de find pour lister les fichiers se terminant par \0
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

# Vérification (à conserver)
if ! [[ -s "$QUEUE" ]]; then
    echo "Aucun fichier à traiter trouvé dans '$SOURCE' ou tous les fichiers correspondent aux critères d'exclusion."
    # Suppression des fichiers log vides créés précédemment
    rm "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" 2>/dev/null
    exit 0
fi

echo "Démarrage du traitement parallèle ($PARALLEL_JOBS jobs). Premiers chemins dans la file (séparés par \0)..."
head -c 512 "$QUEUE" | sed 's/\x0/\n/g' # Affichage des 512 premiers octets, remplaçant \0 par \n pour la lisibilité

############################################
# TRAITEMENT PARALLÈLE
############################################

echo "Démarrage du traitement parallèle ($PARALLEL_JOBS jobs)..."

# L'option -0 permet à xargs de lire les entrées séparées par \0, 
# ce qui neutralise le traitement des apostrophes.
cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {}

############################################
# SUMMARY
############################################

success_count=$(wc -l < "$LOG_SUCCESS")
skipped_count=$(wc -l < "$LOG_SKIPPED")
error_count=$(wc -l < "$LOG_ERROR")

echo "---- Résumé ----" > "$SUMMARY_FILE"
echo "Succès  : $success_count" >> "$SUMMARY_FILE"
echo "Skip    : $skipped_count" >> "$SUMMARY_FILE"
echo "Erreurs : $error_count" >> "$SUMMARY_FILE"
echo "Terminé à : $(date)" >> "$SUMMARY_FILE"

echo "Traitement terminé. Résumé disponible dans $SUMMARY_FILE"