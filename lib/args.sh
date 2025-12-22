#!/bin/bash
###########################################################
# PARSING DES ARGUMENTS
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
            -t|--sample|--test)
                SAMPLE_MODE=true
                shift
                ;;
            --opus)
                OPUS_ENABLED=true
                shift
                ;;
            -2|--two-pass)
                SINGLE_PASS_MODE=false
                shift
                ;;
            -j|--jobs)
                if [[ "${2:-}" =~ ^[0-9]+$ ]] && [[ "$2" -ge 1 ]]; then
                    PARALLEL_JOBS="$2"
                    shift 2
                else
                    echo -e "${RED}ERREUR : --jobs doit être suivi d'un nombre >= 1.${NOCOLOR}"
                    exit 1
                fi
                ;;
            -*) 
                # On vérifie si l'argument est une option courte groupée
                if [[ "$1" =~ ^-[a-zA-Z]{2,}$ ]]; then
                    local flag_to_process="-${1:1:1}" 
                    # remaining_flags = le reste
                    local remaining_flags="-${1:2}" 
                    # Remplacement des arguments :
                    # 1. Le premier argument devient le premier flag à traiter (-x).
                    # 2. Le reste de l'argument groupé est réinséré avant les arguments suivants.
                    set -- "$flag_to_process" "$remaining_flags" "${@:2}"
                    continue # On relance la boucle pour traiter le flag_to_process.
                fi
                # Si ce n'est pas une option groupée ou si ce n'est pas géré, c'est une erreur.
                echo -e "${RED}Option inconnue : $1${NOCOLOR}"
                show_help
                exit 1
                ;;
        esac
    done

    #if [[ "$OUTPUT_DIR" != /* ]]; then
    #    OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
    #fi
    
    # En mode random, appliquer la limite par défaut si aucune limite n'a été spécifiée
    if [[ "$RANDOM_MODE" == true ]] && [[ "$LIMIT_FILES" -eq 0 ]]; then
        LIMIT_FILES=$RANDOM_MODE_DEFAULT_LIMIT
    fi
    
    # Avertissements d'incompatibilités
    if [[ "$DRYRUN" == true ]]; then
        if [[ "$VMAF_ENABLED" == true ]]; then
            echo -e "${YELLOW}⚠️  VMAF désactivé en mode dry-run (pas de fichier converti à analyser)${NOCOLOR}"
            VMAF_ENABLED=false
        fi
        if [[ "$SAMPLE_MODE" == true ]]; then
            echo -e "${YELLOW}⚠️  Mode sample ignoré en mode dry-run (simulation uniquement)${NOCOLOR}"
            SAMPLE_MODE=false
        fi
    fi
    
    # Single-pass désactivé automatiquement pour les films (two-pass pour qualité max)
    if [[ "${SINGLE_PASS_MODE:-true}" == true ]] && [[ "$CONVERSION_MODE" == "film" ]]; then
        SINGLE_PASS_MODE=false
    fi
}

###########################################################
# AFFICHAGE DE L'AIDE
###########################################################

show_help() {
    cat << EOF
Usage : ./conversion.sh [OPTIONS]

Options :
    -s, --source DIR             Dossier source (ARG) [défaut : dossier parent]
    -o, --output-dir DIR         Dossier de destination (ARG) [défaut : \`Converted\` au même niveau que le script]
    -e, --exclude PATTERN        Ajouter un pattern d'exclusion (ARG)
    -m, --mode MODE              Mode de conversion : film, serie (ARG) [défaut : serie]
    -d, --dry-run                Mode simulation sans conversion (FLAG)
    -x, --no-suffix              Désactiver le suffixe _x265 (FLAG)
    -r, --random                 Tri aléatoire : sélectionne des fichiers aléatoires (FLAG) [défaut : 10]
    -l, --limit N                Limiter le traitement à N fichiers (ARG)
    -j, --jobs N                 Nombre de conversions parallèles (ARG) [défaut : 1]
    -q, --queue FILE             Utiliser un fichier queue personnalisé (ARG)
    -n, --no-progress            Désactiver l'affichage des indicateurs de progression (FLAG)
    -h, --help                   Afficher cette aide (FLAG)
    -k, --keep-index             Conserver l'index existant sans demande interactive (FLAG)
    -v, --vmaf                   Activer l'évaluation VMAF de la qualité vidéo (FLAG) [désactivé par défaut]
    -t, --sample                 Mode test : encoder seulement 30s à une position aléatoire (FLAG)
    --opus                       Convertir l'audio en Opus 128kbps (expérimental, problèmes VLC surround)
    -2, --two-pass               Forcer le mode two-pass (défaut : single-pass CRF 23 pour séries)

Remarque sur les options courtes groupées :
    - Les options courtes peuvent être groupées lorsque ce sont des flags (sans argument),
        par exemple : -xdrk est équivalent à -x -d -r -k.
    - Les options qui attendent un argument (marquées (ARG) ci-dessus : -s, -o, -e, -m, -l, -j, -q)
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
