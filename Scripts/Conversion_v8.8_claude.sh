#!/bin/bash

###########################################################
# TO DO
# 1. Assurer la prise en charge des fichiers avec des caractères spéciaux (type accents)
# ====> a priori corrigé, rester vigilant
# 2. Erreur à analyser pour le fichier My Dearest Nemesis - 1x12 - Épisode 12 qui echoue a chaque fois
###########################################################

set -euo pipefail

###########################################################
# CONFIGURATION GLOBALE
###########################################################

# Paramètres par défaut
readonly EXECUTION_TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
readonly LOCKFILE="/tmp/conversion_video.lock"

# Variables modifiables par arguments
DRYRUN=false
TEST_MODE=false
TEST_COUNT=10
SOURCE="./"
OUTPUT_DIR="converted"
REMOVE_ORIGINAL=false
FORCE_NO_SUFFIX=false
PARALLEL_JOBS=3

# Suffixe pour les fichiers
readonly DRYRUN_TEST_SUFFIX="-dryrun-sample"
SUFFIX_STRING="_x265"

# Exclusions par défaut
EXCLUDES=("./logs" "./*.sh" "./*.txt" "converted")

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
readonly LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
readonly QUEUE="$LOG_DIR/Queue"
readonly LOG_DRYRUN_COMPARISON="$LOG_DIR/DryRun_Comparison_${EXECUTION_TIMESTAMP}.log"

###########################################################
# PARAMÈTRES TECHNIQUES
###########################################################

# Système
readonly TMP_DIR="/tmp/video_convert"

readonly MIN_TMP_FREE_MB=2048  # Espace libre requis en MB dans /tmp

# PARAMÈTRES DE CONVERSION NVENC (HEVC/x265)
# NVENC_PRESET: Vitesse de l'encodage. p5 (Bon équilibre), p7 (Max qualité), p3 (Plus rapide)
readonly NVENC_PRESET="p5"

# CRF (-cq): Facteur de qualité constante. Plus haut = plus de compression / moins bonne qualité.
readonly CRF=28 # 28 est un bon compromis taille/qualité pour H.265

# MAXRATE: Débit binaire maximal (en kilobits/seconde). Ex: 3000k (1080p standard)
readonly MAXRATE="3000k"

# BUFSIZE: Taille du tampon VBV. Généralement 1.5x MAXRATE (Ex: 4500k si MAXRATE=3000k).
readonly BUFSIZE="4500k"

# SEUIL DE BITRATE DE CONVERSION (KBPS)
readonly BITRATE_CONVERSION_THRESHOLD_KBPS=2300

# TOLÉRANCE DU BITRATE A SKIP (%)
readonly SKIP_TOLERANCE_PERCENT=10

# PRE-ANALYSE DES IMAGES ET SURFACES DE MEMOIRES TAMPONS
readonly RC_LOOKAHEAD=20 # Une valeur de 20 est un bon équilibre entre la qualité. Les valeurs plus élevées consomment plus de mémoire GPU.
readonly SURFACES=16 # 16 est une valeur sûre, plus que suffisante pour le rc-lookahead 20 et la plupart des tâches d'encodage 1080p ou 4K.

# CORRECTION IONICE
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
            -n|--no-suffix) 
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

    # Définition du chemin absolu/relatif pour OUTPUT_DIR
    if [[ "$SOURCE" != "." && "$OUTPUT_DIR" != /* ]]; then
        OUTPUT_DIR="$SOURCE/$OUTPUT_DIR"
    fi
}

show_help() {
    cat << EOF
Usage: ./conversion.sh [OPTIONS]

Options:
  -s, --source DIR          Dossier source (défaut: .)
  -o, --output-dir DIR      Dossier de destination (défaut: converted)
  -e, --exclude PATTERN     Ajouter un pattern d'exclusion
  -d, --dry-run             Mode simulation sans conversion
  -r, --remove-original     Supprimer les fichiers originaux après conversion
  -n, --no-suffix           Désactiver le suffixe _x265
  -t, --test [N]            Mode test avec N fichiers aléatoires (défaut: 10)
  -h, --help                Afficher cette aide

Exemples:
  ./conversion.sh -s /media/videos -o /media/converted
  ./conversion.sh --dry-run --test 5
  ./conversion.sh -r --no-suffix
EOF
}

###########################################################
# GESTION DU VERROUILLAGE
###########################################################

cleanup() {
    rm -f "$LOCKFILE"
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
    
    if [[ ! -d "$SOURCE" ]]; then
        echo -e "${RED}ERREUR: Source '$SOURCE' introuvable.${NOCOLOR}"
        exit 1
    fi
    
    echo -e "${GREEN}Environnement validé.${NOCOLOR}"
}

initialize_directories() {
    mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR"
    
    # Créer les fichiers de log
    for log_file in "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS" "$LOG_DRYRUN_COMPARISON"; do
        touch "$log_file"
    done
    
    # Réinitialisation Queue
    > "$QUEUE"
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
# GESTION PLEXIGNORE
###########################################################

check_plexignore() {
    local source_abs output_abs
    source_abs=$(readlink -f "$SOURCE")
    output_abs=$(readlink -f "$OUTPUT_DIR")
    local plexignore_file="$OUTPUT_DIR/.plexignore"

    # Vérifier si OUTPUT_DIR est un sous-dossier de SOURCE
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
# VALIDATION DE LA CONVERSION
###########################################################

should_skip_conversion() {
    local codec="$1"
    local bitrate="$2"
    local filename="$3"
    local file_original="$4"
    
    # --- Validation fichier vidéo ---
    if [[ -z "$codec" ]]; then
        echo -e "   ${BLUE}⏭️ SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi
    
    # Calcul de la tolérance en bits
    local base_threshold_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * 1000))
    local tolerance_bits=$((BITRATE_CONVERSION_THRESHOLD_KBPS * SKIP_TOLERANCE_PERCENT * 10))
    local max_tolerated_bits=$((base_threshold_bits + tolerance_bits))
    
    # Validation du format x265 et du bitrate
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
    set -o pipefail # Important pour capter l'erreur ffmpeg

    local file_original="$1"
    local output_dir="$2"
    local remove_original="$3"
    
    # Nettoyage du nom de fichier
    local filename_raw=$(basename "$file_original")
    local filename=$(echo "$filename_raw" | tr -d '\r\n')
    
    if [[ -z "$filename" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR filename empty | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    # Construction des chemins
    local relative_path="${file_original#$SOURCE}"
    relative_path="${relative_path#/}"
    local relative_dir=$(dirname "$relative_path")
    local final_dir="$output_dir/$relative_dir"
    local base_name="${filename%.*}"
	 
    # Détermination du suffixe effectif
    local effective_suffix="$SUFFIX_STRING"
    if [[ "$DRYRUN" == true ]]; then
        effective_suffix="${effective_suffix}${DRYRUN_TEST_SUFFIX}"
    fi

    local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
	
    # VÉRIFICATION DE L'EXISTENCE DU FICHIER DE SORTIE
    if [[ "$DRYRUN" != true ]] && [[ -f "$final_output" ]]; then
        echo -e "   ${BLUE}⏭️ SKIPPED (Fichier de sortie existe déjà) : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (Fichier de sortie existe déjà) | $file_original" >> "$LOG_SKIPPED"
        return 0
    fi

    # --- DRY RUN (SIMPLIFIÉ) ---
    if [[ "$DRYRUN" == true ]]; then
        echo "[DRY RUN] 📄 Fichier cible : $(basename "$final_output")"
        mkdir -p "$final_dir"
        touch "$final_output"
        return 0
    fi

    # Fichiers temporaires (PID based)
    local TMP_BASE_NAME="$$"
    local tmp_input="$TMP_DIR/${TMP_BASE_NAME}.in"
    local tmp_output="$TMP_DIR/${TMP_BASE_NAME}.out.mkv"
    local ffmpeg_log_temp="$TMP_DIR/${TMP_BASE_NAME}_err.log"

    mkdir -p "$final_dir"
    echo -e "${YELLOW}▶️ Démarrage du fichier : $filename${NOCOLOR}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | START | $file_original" >> "$LOG_PROGRESS"

    # --- VÉRIFICATION ESPACE DISQUE ---
    local free_space_mb=$(df -m "$TMP_DIR" | awk 'NR==2 {print $4}')
    if [[ "$free_space_mb" -lt "$MIN_TMP_FREE_MB" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR Espace disque insuffisant dans $TMP_DIR ($free_space_mb MB libres) | $file_original" >> "$LOG_ERROR"
        return 1
    fi

    # --- LECTURE METADATA ---
    local metadata
    metadata=$(get_video_metadata "$file_original")
    IFS='|' read -r bitrate codec duration_secs <<< "$metadata"
    
    local sizeBeforeMB=$(du -m "$file_original" | awk '{print $1}')

    # --- VÉRIFICATION SI SKIP NÉCESSAIRE ---
    if should_skip_conversion "$codec" "$bitrate" "$filename" "$file_original"; then
        return 0
    fi
    
    # --- COPIE LOCALE ---
    echo -e "  ${CYAN}→ Transfert de [$filename] vers dossier temporaire...${NOCOLOR}"
    if ! pv -f "$file_original" > "$tmp_input"; then
        echo -e "   ${RED}❌ ERROR Impossible de déplacer : $file_original${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR PV copy failed | $file_original" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null
        return 1
    fi

    # --- CONVERSION GPU NVENC AVEC AFFICHAGE STABLE (PARALLEL) ---
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
            duration = DURATION + 0;
            if (duration < 1) exit;

            start = systime();
            last_update = 0;
            refresh_interval = 15;    # <<< rafraîchissement 15 sec
        }

        /out_time_us=/ {
            gsub(/out_time_us=/, "");
            current_time = $0 / 1000000;

            percent = (current_time / duration) * 100;
            if (percent > 100) percent = 100;

            # Temps écoulé
            elapsed = systime() - start;

            # Vitesse dencodage
            speed = (elapsed > 0 ? current_time / elapsed : 1);

            # ETA
            remaining = duration - current_time;
            eta = (speed > 0 ? remaining / speed : 0);

            h = int(eta / 3600);
            m = int((eta % 3600) / 60);
            s = int(eta % 60);

            eta_str = sprintf("%02d:%02d:%02d", h, m, s);

            # Rafraîchir toutes les X secondes
            now = systime() + (strftime("%S") % 1);  # précision décimale
            if (now - last_update >= refresh_interval || percent >= 99) {
                printf "    ... [%-30.30s] %.1f%% | ETA: %s | Speed: %.2fx\n",
                       CURRENT_FILE_NAME, percent, eta_str, speed;
                fflush();
                last_update = now;
            }
        }

        /progress=end/ {
            printf "    ... [%-30.30s] 100%% | ETA: 00:00:00 | Speed: %.2fx\n",
                CURRENT_FILE_NAME, speed;
            fflush();
        }
    '; then 
        echo -e "  ${GREEN}✅ Fichier converti : $filename${NOCOLOR}"
        echo ""

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
    else
        echo ""
        echo -e "  ${RED}❌ Échec de la conversion : $filename${NOCOLOR}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR"
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR"
        cat "$ffmpeg_log_temp" >> "$LOG_ERROR"
        echo "-------------------------------" >> "$LOG_ERROR"
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
    fi
}

###########################################################
# CONSTRUCTION DE LA FILE D'ATTENTE
###########################################################

build_queue() {
    echo "Indexation fichiers..." >&2
    local exclude_dir_name=$(basename "$OUTPUT_DIR")

    find "$SOURCE" \
        -name "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 | \
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
        # Mode normal : tri par taille décroissante
        sort -nrk1,1 "$QUEUE.tmp" | cut -f2- | tr '\n' '\0' > "$QUEUE"
    fi
    
    rm "$QUEUE.tmp"

    # Créer une version lisible pour consultation
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

                # --- PRÉPARATION POUR LA VÉRIFICATION D'ANOMALIE ---
                local generated_base_name="${final_output_basename%.mkv}"
                
                # 1. RETRAIT DU SUFFIXE DRY RUN (toujours en premier car il est le dernier ajouté)
                if [[ "$DRYRUN" == true ]]; then
                    generated_base_name="${generated_base_name%"$DRYRUN_TEST_SUFFIX"}"
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
                    printf "  %-10s : %s\n" "ORIGINAL" "$filename"
                    printf "  %-10s : %s\n" "GÉNÉRÉ" "$final_output_basename"
                    
                    # Affichage des noms en couleur dans le terminal
                    printf "  ${ORANGE}%-10s${NOCOLOR} : %s\n" "ORIGINAL" "$filename" > $TTY_DEV
                    printf "  ${GREEN}%-10s${NOCOLOR} : %s\n" "GÉNÉRÉ" "$final_output_basename" > $TTY_DEV
                    
                    echo ""
                
                } | tee -a "$LOG_FILE"
                
            done < "$QUEUE"
            
            # AFFICHAGE ET LOG DU RÉSUMÉ DES ANOMALIES
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
            
            # Affichage en couleur dans le terminal (pour le résumé final)
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
    export -f convert_file get_video_metadata should_skip_conversion clean_number
    export DRYRUN LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE 
    export TMP_DIR NVENC_PRESET CRF IO_PRIORITY_CMD SOURCE OUTPUT_DIR REMOVE_ORIGINAL 
    export MAXRATE BUFSIZE BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT 
    export MIN_TMP_FREE_MB RC_LOOKAHEAD SURFACES 
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE 
    export DRYRUN_TEST_SUFFIX SUFFIX_STRING
}

###########################################################
# FONCTION PRINCIPALE
###########################################################

main() {
    # Parse des arguments
    parse_arguments "$@"
    
    # Vérifications système
    check_lock
    check_dependencies
    initialize_directories
    
    # Configuration interactive
    check_plexignore
    check_output_suffix
    
    # Construction de la file d'attente
    build_queue
    
    # Export pour parallel
    export_for_parallel
    
    # Traitement des fichiers
    local nb_files=$(tr -cd '\0' < "$QUEUE" | wc -c)
    echo -e "${CYAN}Démarrage du traitement ($nb_files fichiers)...${NOCOLOR}"
    
    cat "$QUEUE" | xargs -0 -I{} -P "$PARALLEL_JOBS" bash -c 'convert_file "$@"' _ {} "$OUTPUT_DIR" "$REMOVE_ORIGINAL"
    
    # Comparaison en mode dry-run
    dry_run_compare_names
    
    # Affichage du résumé
    show_summary
}

###########################################################
# POINT D'ENTRÉE
###########################################################

main "$@"