#!/bin/bash
###########################################################
# VÉRIFICATION DES DÉPENDANCES
###########################################################

check_dependencies() {
    print_section "Vérification de l'environnement"

    local missing_deps=()

    for cmd in ffmpeg ffprobe; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Dépendances manquantes : ${missing_deps[*]}"
        exit 1
    fi

    # Vérification de la version de ffmpeg (si disponible)
    local ffmpeg_version
    ffmpeg_version=$(ffmpeg -version 2>/dev/null | head -n1 | grep -oE 'version [0-9]+' | cut -d ' ' -f2 || true)

    if [[ -z "$ffmpeg_version" ]]; then
        print_warning "Impossible de déterminer la version de ffmpeg."
    else
        if [[ "$ffmpeg_version" =~ ^[0-9]+$ ]]; then
            if (( ffmpeg_version < FFMPEG_MIN_VERSION )); then
                print_warning "Version FFMPEG ($ffmpeg_version) < Recommandée ($FFMPEG_MIN_VERSION)"
            else
                print_item "FFmpeg" "v$ffmpeg_version" "$GREEN"
            fi
        else
            print_warning "Version ffmpeg détectée : $ffmpeg_version"
        fi
    fi

    if [[ ! -d "$SOURCE" ]]; then
        print_error "Source '$SOURCE' introuvable."
        exit 1
    fi

    # Affichage adapté selon le mode d'encodage
    if [[ "${SINGLE_PASS_MODE:-false}" == true ]]; then
        print_item "Mode conversion" "$CONVERSION_MODE (CRF=$CRF_VALUE, single-pass)" "$CYAN"
    else
        print_item "Mode conversion" "$CONVERSION_MODE (bitrate=${TARGET_BITRATE_KBPS}k, two-pass)" "$CYAN"
    fi
    print_success "Environnement validé"
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
            print_info "Fichier .plexignore déjà présent dans '$OUTPUT_DIR'"
            return 0
        fi

        ask_question "Créer un fichier .plexignore dans '$OUTPUT_DIR' pour éviter les doublons Plex ?"
        read -r response

        case "$response" in
            [oO]|[yY]|'')
                echo "*" > "$plexignore_file"
                print_success "Fichier .plexignore créé dans '$OUTPUT_DIR'"
                ;;
            [nN]|*)
                print_info "Création de .plexignore ignorée"
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
        print_info "Option --no-suffix activée. Le suffixe est désactivé par commande."
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
            ask_question "Utiliser le suffixe de sortie ? Ex: $hint_1080 / $hint_720"
        else
            ask_question "Utiliser le suffixe de sortie ? Ex: $hint_1080"
        fi
        read -r response
        
        case "$response" in
            [nN])
                SUFFIX_STRING=""
                print_warning "Suffixe de sortie désactivé"
                ;;
            *)
                # Ne pas afficher le suffixe complet car la résolution (1080p/720p) 
                # dépend de chaque fichier source et peut prêter à confusion
                print_success "Suffixe de sortie activé"
                ;;
        esac
    fi

    # 2. Vérification de sécurité critique
    if [[ -z "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
        # ALERTE : Pas de suffixe ET même répertoire = RISQUE D'ÉCRASMENT
        print_critical_alert "RISQUE D'ÉCRASEMENT" \
            "Source et sortie IDENTIQUES: $source_abs" \
            "L'absence de suffixe ÉCRASERA les originaux !"
        
        if [[ "$DRYRUN" == true ]]; then
            print_info "(MODE DRY RUN) : Visualisez les fichiers qui seront écrasés"
        fi
        
        ask_question "Continuer SANS suffixe dans le même répertoire ?"
        read -r final_confirm
        
        case "$final_confirm" in
            [oO]|[yY]|'')
                print_warning "Continuation SANS suffixe. Vérifiez le Dry Run ou les logs."
                ;;
            *)
                print_error "Opération annulée. Modifiez le suffixe ou le dossier de sortie."
                exit 1
                ;;
        esac
    
    # 3. Vérification de sécurité douce
    elif [[ -n "$SUFFIX_STRING" ]] && [[ "$is_same_dir" == true ]]; then
        # ATTENTION : Suffixe utilisé, mais toujours dans le même répertoire
        print_warning_box "Coexistence de fichiers" \
            "Les fichiers originaux et convertis coexisteront dans le même répertoire."
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
        print_info "Évaluation VMAF activée"
    else
        print_error "VMAF demandé mais libvmaf non disponible dans FFmpeg"
        VMAF_ENABLED=false
    fi
}
