#!/bin/bash
###########################################################
# VÉRIFICATION DES DÉPENDANCES
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

    echo -e "   - Mode conversion : ${CYAN}$CONVERSION_MODE${NOCOLOR} (bitrate=${TARGET_BITRATE_KBPS}k, two-pass)"
    echo -e "${GREEN}Environnement validé.${NOCOLOR}"
}

###########################################################
# GESTION PLEXIGNORE
###########################################################

check_plexignore() {
    local source_abs output_abs
    source_abs=$(cd "$SOURCE" && pwd)
    output_abs=$(cd "$OUTPUT_DIR" && pwd)
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
# VÉRIFICATION DU SUFFIXE DE SORTIE
###########################################################

check_output_suffix() {
    local source_abs output_abs is_same_dir=false
    source_abs=$(cd "$SOURCE" && pwd)
    output_abs=$(cd "$OUTPUT_DIR" && pwd)

    if [[ "$source_abs" == "$output_abs" ]]; then
        is_same_dir=true
    fi

    if [[ "$FORCE_NO_SUFFIX" == true ]]; then
        SUFFIX_STRING=""
        echo -e "${YELLOW}ℹ️  Option --no-suffix activée. Le suffixe est désactivé par commande.${NOCOLOR}"
    else
        # 1. Demande interactive (uniquement si l'option force n'est PAS utilisée)
        local suffix_example_1080 suffix_example_720
        suffix_example_1080="${SUFFIX_STRING}"
        suffix_example_720=""
        if declare -f _build_effective_suffix_for_dims &>/dev/null; then
            suffix_example_1080=$(_build_effective_suffix_for_dims 1920 1080)
            suffix_example_720=$(_build_effective_suffix_for_dims 1280 720)
        fi

        # Affichage succinct : garder seulement "<bitrate>_<height>" (ex: 2070k_1080p)
        local hint_1080 hint_720
        hint_1080="$suffix_example_1080"
        hint_720="$suffix_example_720"
        if [[ "$hint_1080" == _x265_* ]]; then
            local _rest _br _res
            _rest="${hint_1080#_x265_}"
            IFS='_' read -r _br _res _ <<< "$_rest"
            if [[ -n "$_br" && -n "$_res" ]]; then
                hint_1080="${_br}_${_res}"
            fi
        fi
        if [[ "$hint_720" == _x265_* ]]; then
            local _rest2 _br2 _res2
            _rest2="${hint_720#_x265_}"
            IFS='_' read -r _br2 _res2 _ <<< "$_rest2"
            if [[ -n "$_br2" && -n "$_res2" ]]; then
                hint_720="${_br2}_${_res2}"
            fi
        fi

        if [[ -n "$suffix_example_720" ]] && [[ "$suffix_example_720" != "$suffix_example_1080" ]]; then
            read -r -p "Utiliser le suffixe de sortie ? Ex: $hint_1080 / $hint_720 (O/n) " response
        else
            read -r -p "Utiliser le suffixe de sortie ? Ex: $hint_1080 (O/n) " response
        fi
        
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
        echo -e "${YELLOW}Si vous ne supprimez pas les originaux, assurez-vous que Plex gère correctement les doublons.${NOCOLOR}"
    fi
}

###########################################################
# VÉRIFICATION LIBRAIRIE VMAF
###########################################################

check_vmaf() {
    if [[ "$VMAF_ENABLED" != true ]]; then
        return 0
    fi
    
    if [[ "$HAS_LIBVMAF" -eq 1 ]]; then
        echo -e "${YELLOW}📊 Évaluation VMAF activée${NOCOLOR}"
    else
        echo -e "${RED}⚠️ Évaluation VMAF demandée mais libvmaf non disponible dans FFmpeg${NOCOLOR}"
        VMAF_ENABLED=false
    fi
}
