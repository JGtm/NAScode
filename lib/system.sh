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
    echo ""
}

###########################################################
# GESTION PLEXIGNORE
###########################################################

check_plexignore() {
    local source_abs output_abs
    source_abs=$(cd "$SOURCE" && pwd)
    output_abs=$(cd "$OUTPUT_DIR" && pwd)
    local plexignore_file="$OUTPUT_DIR/.plexignore"

    # Ne pas proposer .plexignore si source et destination sont identiques
    if [[ "$source_abs" == "$output_abs" ]]; then
        return 0
    fi

    # Vérifier si OUTPUT_DIR est un sous-dossier de SOURCE
    if [[ "$output_abs" = "$source_abs"/* ]]; then
        if [[ -f "$plexignore_file" ]]; then
            print_info_compact "Fichier .plexignore déjà présent dans le répertoire de destination"
            return 0
        fi

        ask_question "Créer un fichier .plexignore dans le répertoire de destination pour éviter les doublons dans Plex ?" "O/n"
        read -r response

        case "$response" in
            [oO]|[yY]|'')
                echo "*" > "$plexignore_file"
                print_success "Fichier .plexignore créé dans le répertoire de destination"
                echo ""
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

    # Gestion du suffixe selon SUFFIX_MODE : off, on, custom:xxx, ask (défaut)
    case "${SUFFIX_MODE:-ask}" in
        off)
            # -x / --no-suffix : désactiver le suffixe
            SUFFIX_STRING=""
            print_info "Option --no-suffix activée. Le suffixe est désactivé par commande."
            ;;
        custom:*)
            # -S "valeur" : suffixe personnalisé
            SUFFIX_STRING="${SUFFIX_MODE#custom:}"
            print_warning "Utilisation forcée du suffixe de sortie : ${SUFFIX_STRING}"
            ;;
        on)
            # -S sans argument : activer le suffixe dynamique sans question
            # SUFFIX_STRING garde sa valeur par défaut (suffixe dynamique)
            print_success "Suffixe de sortie activé"
            ;;
        ask|*)
            # Mode interactif par défaut
            local suffix_example_1080 suffix_example_720
            suffix_example_1080="${SUFFIX_STRING}"
            suffix_example_720=""
            if declare -f _build_effective_suffix_for_dims &>/dev/null; then
                suffix_example_1080=$(_build_effective_suffix_for_dims 1920 1080)
                suffix_example_720=$(_build_effective_suffix_for_dims 1280 720)
            fi

            # Affichage succinct : garder seulement la partie après le codec (ex: 1080p / 720p)
            # Helper pour extraire un hint depuis le suffixe complet
            _extract_suffix_hint() {
                local suffix="$1"
                if [[ "$suffix" == _x265_* || "$suffix" == _av1_* ]]; then
                    local rest
                    rest="${suffix#_*_}"  # Enlève _x265_ ou _av1_
                    [[ -n "$rest" ]] && echo "$rest" || echo "$suffix"
                else
                    echo "$suffix"
                fi
            }
            
            local hint_1080 hint_720
            hint_1080=$(_extract_suffix_hint "$suffix_example_1080")
            hint_720=$(_extract_suffix_hint "$suffix_example_720")

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
            ;;
    esac

    # Vérifications de sécurité (Écrasement / Coexistence)
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
        
    # Vérification de sécurité douce
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
        # Si on utilise un FFmpeg alternatif pour VMAF, afficher une info
        if [[ -n "${FFMPEG_VMAF:-}" ]] && [[ "$FFMPEG_VMAF" != "ffmpeg" ]]; then
            print_info "VMAF via FFmpeg alternatif (libvmaf détecté)"
        fi
        # L'affichage sera groupé avec les autres options dans show_active_options
        return 0
    else
        print_error "VMAF demandé mais libvmaf non disponible dans FFmpeg"
        VMAF_ENABLED=false
    fi
}
