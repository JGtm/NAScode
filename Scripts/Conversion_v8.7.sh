#!/bin/bash

###########################################################
# TO DO
# 1. Assurer la prise en charge des fichiers avec des caractères spéciaux (type accents)
# ====> a priori corrigé, rester vigilant
# 2. Erreur à analyser pour le fichier My Dearest Nemesis - 1x12 - Épisode 12 qui echoue a chaque fois
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
FORCE_NO_SUFFIX=false

# Liste des exclusions
EXCLUDES=("./logs" "./*.sh" "./*.txt" "converted")

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source) SOURCE="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -e|--exclude) EXCLUDES+=("$2"); shift 2 ;;
        -d|--dry-run|--dryrun) DRYRUN=true; shift ;;
        -r|--remove-original) REMOVE_ORIGINAL=true; shift ;;
		-n|--no-suffix) FORCE_NO_SUFFIX=true; shift ;;
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

# Définition du chemin absolu/relatif pour OUTPUT_DIR
if [[ "$SOURCE" != "." && "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$SOURCE/$OUTPUT_DIR"
fi

############################################
# CONFIGURATION
############################################

# COULEURS ANSI pour le terminal
NOCOLOR='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
ORANGE='\033[1;33m'

# Date/heure pour l'archivage des logs
EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')

# CHEMINS
LOG_DIR="./logs"
LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"
LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"
LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"
SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
QUEUE="$LOG_DIR/Queue"

PARALLEL_JOBS=3
TMP_DIR="/tmp/video_convert"
MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp

# PROTECTION MULTI-INSTANCE
LOCKFILE="/tmp/conversion_video.lock"

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

# PRE-ANALYSE DES IMAGES ET SURFACES DE MEMOIRES TAMPONS
RC_LOOKAHEAD=20 # Une valeur de 20 est un bon équilibre entre la qualité. Les valeurs plus élevées consomment plus de mémoire GPU.
SURFACES=16 # 16 est une valeur sûre, plus que suffisante pour le rc-lookahead 20 et la plupart des tâches d'encodage 1080p ou 4K.

# GESTION DU SUFFIXE
SUFFIX_STRING="_x265"
USE_SUFFIX=true # Variable globale pour déterminer l'usage du _x265 ou non

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
        echo -e "${RED}⛔ Le script est déjà en cours d'exécution (PID $pid).${NOCOLOR}"
        exit 1
    else
        echo -e "${YELLOW}⚠️ Fichier lock trouvé mais processus absent. Nettoyage...${NOCOLOR}"
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

echo -e "${GREEN}Environnement validé.${NOCOLOR}"

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

#----------------------------------------------------
# GESTION PLEXIGNORE
#----------------------------------------------------

check_plexignore() {
    local source_abs
    source_abs=$(readlink -f "$SOURCE")
    local output_abs
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
export -f check_plexignore

#----------------------------------------------------
# VÉRIFICATION DU SUFFIXE
#----------------------------------------------------

check_output_suffix() {
    local source_abs
    source_abs=$(readlink -f "$SOURCE")
    local output_abs
    output_abs=$(readlink -f "$OUTPUT_DIR")
    local is_same_dir=false

    if [[ "$source_abs" == "$output_abs" ]]; then
        is_same_dir=true
    fi

    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        echo -e "${ORANGE}ℹ️  Option --no-suffix activée. Le suffixe est désactivé par commande.${NOCOLOR}"
    else
        # 1. Demande interactive (uniquement si l'option force n'est PAS utilisée)
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
        # ALERTE : Pas de suffixe ET même répertoire = RISQUE D'ÉCRASMENT
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
        echo -e "${YELLOW}Si vous ne supprimez pas les originaux (-r), assurez-vous que Plex gère correctement les doublons.${NOCOLOR}"
    fi
}

export -f check_output_suffix
export SUFFIX_STRING FORCE_NO_SUFFIX
export USE_SUFFIX

check_plexignore

check_output_suffix

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
    
    local base_name="${filename%.*}"
	 
    # LOGIQUE SUFFIXE
    # POSSIBLEMENT DOUBLON AVEC LIGNE 547
    local final_output
    if [[ "$USE_SUFFIX" == true ]]; then
        final_output="$final_dir/${base_name}${SUFFIX_STRING}.mkv" 
    else
        final_output="$final_dir/${base_name}.mkv" 
    fi
	
	# VÉRIFICATION DE L'EXISTENCE DU FICHIER DE SORTIE
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        echo -e "   ${BLUE}⏭️ SKIPPED (Fichier de sortie existe déjà) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi

    # Fichiers temporaires (PID based)
    local TMP_BASE_NAME="$$" 
    local tmp_input="$TMP_DIR/${TMP_BASE_NAME}.in" 
    local tmp_output="$TMP_DIR/${TMP_BASE_NAME}.out.mkv"
    local ffmpeg_log_temp="$TMP_DIR/${TMP_BASE_NAME}_err.log"
    
    # --- DRY RUN (SIMPLIFIÉ) ---
    if [[ "$DRYRUN" == true ]]; then
        # La comparaison des noms est désormais faite dans la fonction dry_run_compare_names
        echo "[DRY RUN] 📁 Création structure : $final_dir"
        echo "[DRY RUN] 📄 Fichier cible : $(basename "$final_output")"
        mkdir -p "$final_dir"
        touch "$final_output"
        return 0
    fi

    mkdir -p "$final_dir"
    echo -e "${YELLOW}▶️ Démarrage du fichier : $filename${NOCOLOR}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS"

    # --- VÉRIFICATION ESPACE DISQUE ---
    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}')
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    # ----------------------------------------------------
    # LECTURE FFPROBE (Bitrate, Codec, Durée)
    # ----------------------------------------------------
    
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

    # ----------------------------------------------------
    # CONDITIONS SKIP (Tolérance variable)
    # ----------------------------------------------------
    
    # --- Validation fichier vidéo ---
    if [[ -z "$codec" ]]; then
        echo -e "   ${BLUE}⏭️ SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi
    
    # Calcul de la tolérance en bits
    local base_threshold_bits=$(($BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$(($BITRATE_CONVERSION_THRESHOLD_KBPS * $SKIP_TOLERANCE_PERCENT * 10)) 
    local max_tolerated_bits=$(($base_threshold_bits + $tolerance_bits)) 
    
    # Validation du format x265 et du bitrate
    if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
        if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le "$max_tolerated_bits" ]]; then
            echo -e "   ${BLUE}⏭️ SKIPPED (Déjà x265 & bitrate optimisé) : $filename${NOCOLOR}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Déjà x265 et bitrate optimisé) | $file_original" >> "$LOG_SKIPPED"
            return 0
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage X265) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS"
    fi
    
    # ----------------------------------------------------
    # COPIE LOCALE
    # ----------------------------------------------------
    
    echo -e "  ${CYAN}→ Transfert de [$filename] vers dossier temporaire...${NOCOLOR}"
    if ! pv -f "$file_original" > "$tmp_input"; then
		echo -e "   ${RED}❌ ERROR Impossible de déplacer : $file_original${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR PV copy failed | $file_original" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null; return 1
    fi

    # ----------------------------------------------------
    # CONVERSION GPU NVENC AVEC AFFICHAGE STABLE (PARALLEL)
    # ----------------------------------------------------
    echo "  → Encodage NVENC..."
    
    if $IO_PRIORITY_CMD ffmpeg -y -loglevel warning \
        -hwaccel cuda -hwaccel_output_format cuda \
        -i "$tmp_input" \
        -c:v hevc_nvenc -preset "$NVENC_PRESET" \
        -maxrate "$MAXRATE" -bufsize "$BUFSIZE" -rc vbr -cq "$CRF" \
        -rc-lookahead "$RC_LOOKAHEAD" -surfaces "$SURFACES" \
        -c:a copy \
        -map 0 -f matroska \
        "$tmp_output" \
        -progress pipe:1 -nostats 2> "$ffmpeg_log_temp" | \
    awk -v DURATION="$duration_secs" -v CURRENT_FILE_NAME="$base_name" '
        BEGIN {
            duration = DURATION;
            last_printed = -10;
            if (duration < 1) { exit; }
        }
        /out_time_us=/ {
            gsub(/out_time_us=/, "");
            current_time = $0 / 1000000;
            p = (current_time / duration) * 100;
            if (p > 100) p = 100;
            
            # Affichage nouvelle ligne tous les 5% pour lisibilité en parallèle
            if (p - last_printed >= 5 || (p >= 99 && last_printed < 95)) {
				printf "    ... [%-60.60s] Progression : %.0f%%\n", CURRENT_FILE_NAME, p;
                fflush();
                last_printed = p;
            }
        }
        /progress=end/ {
			printf "    ... [%-60.60s] Progression : 100%%\n", CURRENT_FILE_NAME;
            fflush();
        }
    ' ; then 
        echo -e "  ${GREEN}✅ Fichier converti : $filename${NOCOLOR}"
        echo ""

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
        echo ""; 
		echo -e "  ${RED}❌ Échec de la conversion : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR"
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR"
        cat "$ffmpeg_log_temp" >> "$LOG_ERROR"
        echo "-------------------------------" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
    fi
}

export -f convert_file
export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR REMOVE_ORIGINAL MAXRATE BUFSIZE BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT MIN_TMP_FREE_MB RC_LOOKAHEAD SURFACES NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE

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

# Créer une version lisible pour consultation
tr '\0' '\n' < "$QUEUE" > "$LOG_DIR/Queue_readable_${EXECUTION_TIMESTAMP}.txt"


if ! [[ -s "$QUEUE" ]]; then
    echo "Aucun fichier à traiter trouvé."
    exit 0
fi

############################################
# DRY RUN AVANCÉ (VERIFICATION DU RESULTAT)
############################################

dry_run_compare_names() {
    if [[ "$DRYRUN" != true ]]; then return 0; fi

    echo ""
    read -r -p "Souhaitez-vous afficher la comparaison entre les noms de fichiers originaux et générés ? (O/n) " response
    
    case "$response" in
        [oO]|[yY]|'')
            echo -e "\n-------------------------------------------"
            echo "      SIMULATION DES NOMS DE FICHIERS"
            echo "-------------------------------------------"
            local total_files=$(tr -cd '\0' < "$QUEUE" | wc -c)
            local count=0
            
            while IFS= read -r -d $'\0' file_original; do
                local filename_raw=$(basename "$file_original")
                local filename=$(echo "$filename_raw" | tr -d '\r\n')
                local base_name="${filename%.*}"
                local final_output
                
                # Le chemin complet n'est pas utilisé pour l'affichage, mais nécessaire pour calculer final_output
                local relative_path="${file_original#$SOURCE}"
                relative_path="${relative_path#/}"
                local relative_dir=$(dirname "$relative_path")
                local final_dir="$OUTPUT_DIR/$relative_dir"
                
                # Détermination du nom de sortie (avec ou sans suffixe)
                if [[ "$USE_SUFFIX" == true ]]; then
                    final_output="$final_dir/${base_name}${SUFFIX_STRING}.mkv" 
                else
                    final_output="$final_dir/${base_name}.mkv" 
                fi
                
                # Extraction du nom de fichier généré pour l'affichage
                local final_output_basename=$(basename "$final_output")

                count=$((count + 1))
                echo "[ $count / $total_files ]"
                echo "  ORIGINAL : $filename"
                echo "  GÉNÉRÉ   : $final_output_basename"
                echo ""
            done < "$QUEUE"
            echo "-------------------------------------------"
            ;;
        [nN]|*)
            echo "Comparaison des noms ignorée."
            ;;
    esac
}

export -f dry_run_compare_names

############################################
# TRAITEMENT
############################################

NB_FILES=$(tr -cd '\0' < "$QUEUE" | wc -c)
echo -e "${CYAN}Démarrage du traitement ($NB_FILES fichiers)...${NOCOLOR}"

cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL"

dry_run_compare_names

############################################
# RÉSUMÉ
############################################

succ=$(wc -l < "$LOG_SUCCESS")
skip=$(wc -l < "$LOG_SKIPPED")

# Compte le nombre de lignes qui commencent par un timestamp et contiennent 'ERROR ffmpeg'
err=$(grep -c ' | ERROR ffmpeg | ' "$LOG_ERROR" 2>/dev/null || echo "0")
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