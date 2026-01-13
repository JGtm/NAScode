#!/bin/bash
###########################################################
# GESTION DE LA FILE D'ATTENTE
# Construction, tri et traitement de la queue de fichiers
# Note: Les fonctions d'index sont dans lib/index.sh
# Note: Les fonctions de compteurs sont dans lib/counters.sh
###########################################################

# Variables pour stocker les options actives (affichage groupé)
_LIMIT_MESSAGE=""
_LIMIT_MODE=""

###########################################################
# VALIDATION DU FICHIER QUEUE
###########################################################

# Valide qu'un fichier queue est bien formé (non vide, format null-separated).
# Utilisé pour les queues personnalisées (-q) et la validation interne.
validate_queue_file() {
    local queue_file="$1"
    
    if [[ ! -f "$queue_file" ]]; then
        print_error "ERREUR : Le fichier queue '$queue_file' n'existe pas."
        return 1
    fi
    
    if [[ ! -s "$queue_file" ]]; then
        print_error "Le fichier queue est vide"
        return 1
    fi
    
    local file_count
    file_count=$(count_null_separated "$queue_file")
    if [[ $file_count -eq 0 ]]; then
        print_error "Format du fichier queue invalide (séparateur NUL attendu)"
        return 1
    fi
    
    local test_read
    test_read=$(head -c 100 "$queue_file" | tr '\0' '\n' | head -1)
    if [[ -z "$test_read" ]] && [[ $file_count -gt 0 ]]; then
        print_info "Le fichier queue semble valide ($file_count fichiers détectés)."
    else
        print_success "Fichier queue validé : $queue_file"
    fi
    
    return 0
}

###########################################################
# CONSTRUCTION DE LA QUEUE À PARTIR DE L'INDEX
###########################################################

_build_queue_from_index() {
    # Construction de la QUEUE à partir de l'INDEX (fichier permanent)
    # Appliquer le mode de tri configuré via SORT_MODE

    # Appliquer un filtre taille (si demandé) AVANT le tri.
    # Cela s'applique aussi quand un index existant est conservé.
    _emit_index_lines() {
        if [[ "${MIN_SIZE_BYTES:-0}" -gt 0 ]]; then
            awk -F'\t' -v min="$MIN_SIZE_BYTES" '$1+0 >= min {print}' "$INDEX"
        else
            cat "$INDEX"
        fi
    }

    case "$SORT_MODE" in
        size_desc)
            # Trier par taille décroissante (par défaut)
            _emit_index_lines | sort -nrk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        size_asc)
            # Trier par taille croissante
            _emit_index_lines | sort -nk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        name_asc)
            # Trier par nom de fichier ascendant (utilise la 2ème colonne : chemin)
            _emit_index_lines | sort -t$'\t' -k2,2 | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        name_desc)
            # Trier par nom de fichier descendant
            _emit_index_lines | sort -t$'\t' -k2,2 -r | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        *)
            # Mode inconnu -> repli sur size_desc
            _emit_index_lines | sort -nrk1,1 | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
    esac
}

###########################################################
# LIMITATIONS ET FILTRES
###########################################################

_apply_queue_limitations() {
    # APPLICATION DE LA LIMITATION (Unifiée, s'applique à la queue prête, peu importe sa source)
    local limit_count=$LIMIT_FILES
    
    if [[ "$limit_count" -eq 0 ]]; then
        return 0
    fi
    
    # Stocker les informations de limitation pour affichage groupé
    if [[ "$RANDOM_MODE" == true ]]; then
        _LIMIT_MESSAGE="Sélection de $limit_count fichier(s) maximum"
        _LIMIT_MODE="random"
    else
        _LIMIT_MESSAGE="$limit_count fichier(s) maximum"
        _LIMIT_MODE="normal"
    fi
    
    local tmp_limit="$QUEUE.limit"
    local queue_content
    
    # Lire la queue (séparée par \0) et la convertir en lignes pour le traitement
    queue_content=$(tr '\0' '\n' < "$QUEUE")
    
    # Appliquer le tri (aléatoire si random) et la limite
    if [[ "$RANDOM_MODE" == true ]]; then
        # Mode RANDOM : Tri aléatoire puis limitation
        echo "$queue_content" | sort -R | head -n "$limit_count" | tr '\n' '\0' > "$tmp_limit"
    else
        # Mode Normal : Limitation du haut de la liste (déjà triée par taille décroissante)
        echo "$queue_content" | head -n "$limit_count" | tr '\n' '\0' > "$tmp_limit"
    fi
    
    mv "$tmp_limit" "$QUEUE"
}

_validate_queue_not_empty() {										   
    if ! [[ -s "$QUEUE" ]]; then
        echo "Aucun fichier à traiter trouvé (vérifiez les filtres ou la source)."
        exit 0
    fi

    local file_count
    file_count=$(count_null_separated "$QUEUE")
    if [[ "$file_count" -eq 0 ]]; then
        print_error "Format du fichier queue invalide (séparateur NUL attendu)"
        exit 1
    fi
}

_display_random_mode_selection() {													
    if [[ "$RANDOM_MODE" != true ]] || [[ "$NO_PROGRESS" == true ]]; then
        return 0
    fi

    echo -e "\n  ${CYAN}📋 Fichiers sélectionnés aléatoirement${NOCOLOR}"
    echo -e "  ${DIM}─────────────────────────────────────────────${NOCOLOR}"
    tr '\0' '\n' < "$QUEUE" | sed 's|.*/||' | nl -w2 -s'. ' | sed 's/^/  /'
    echo ""
}

_create_readable_queue_copy() {																							  
    tr '\0' '\n' < "$QUEUE" > "$LOG_DIR/Queue_readable_${EXECUTION_TIMESTAMP}.txt"
}

###########################################################
# AFFICHAGE DES OPTIONS ACTIVES (GROUPÉ)
###########################################################

# Affiche toutes les options actives dans un encadré après les questions interactives
_show_active_options() {
    [[ "$NO_PROGRESS" == true ]] && return 0
    
    local options=()
    
    # Chemins source et destination (toujours affichés)
    options+=("$(format_option_source "$SOURCE")")
    options+=("$(format_option_dest "$OUTPUT_DIR")")
    
    # Nombre de fichiers à traiter (seulement sans limite, car compteur actif)
    if [[ "${LIMIT_FILES:-0}" -eq 0 ]] && [[ -f "$QUEUE" ]]; then
        local file_count
        file_count=$(count_null_separated "$QUEUE")
        if [[ "$file_count" -gt 0 ]]; then
            options+=("$(format_option_file_count "$file_count")")
        fi
    fi
    
    # Option Dry-run (en premier car très important)
    if [[ "$DRYRUN" == true ]]; then
        options+=("$(format_option_dryrun)")
    fi
    
    # Codec vidéo (toujours affiché)
    options+=("$(format_option_video)")
    
    # Option VMAF
    if [[ "$VMAF_ENABLED" == true && "$HAS_LIBVMAF" -eq 1 ]]; then
        options+=("$(format_option_vmaf)")
    fi
    
    # Option Mode échantillon
    if [[ "$SAMPLE_MODE" == true ]]; then
        options+=("$(format_option_sample)")
    fi
    
    # Option Codec Audio (si différent de copy)
    if [[ "${AUDIO_CODEC:-copy}" != "copy" ]]; then
        options+=("$(format_option_audio)")
    fi

    # Ordre de tri de la queue
    options+=("$(format_option_sort_mode)")

    # Option Mode aléatoire
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        options+=("$(format_option_random_mode)")
    fi
    
    # Option Limitation
    if [[ -n "$_LIMIT_MESSAGE" ]]; then
        options+=("$(format_option_limit "$_LIMIT_MESSAGE" "$_LIMIT_MODE")")
    fi
    
    # Afficher seulement si au moins une option est active
    if [[ ${#options[@]} -gt 0 ]]; then
        print_active_options "${options[@]}"
    fi
}

###########################################################
# FONCTION PRINCIPALE DE CONSTRUCTION DE LA QUEUE
###########################################################

build_queue() {
    # Étape 1 : Gestion de l'INDEX (source de vérité)
    # Note: fonctions _handle_custom_queue, _handle_existing_index, _generate_index
    # sont définies dans lib/index.sh
    
    # Priorité 1 : Utiliser une queue personnalisée (crée INDEX)
    if _handle_custom_queue; then
        :
    # Priorité 2 : Réutiliser l'INDEX existant (avec demande à l'utilisateur)
    elif _handle_existing_index; then
        # L'INDEX existant a été accepté, rien à faire
        :
    # Priorité 3 : Générer un nouvel INDEX
    else
        _generate_index
    fi
    
    # Étape 2 : Construire la QUEUE à partir de l'INDEX (tri par taille décroissante)
    _build_queue_from_index
    
    # Sauvegarder la queue complète avant limitation (pour alimentation dynamique)
    cp -f "$QUEUE" "$QUEUE.full" 2>/dev/null || true
    
    # Étape 3 : Appliquer les limitations (limit, random)
    _apply_queue_limitations
    
    # Étape 4 : Afficher les options actives (après les questions interactives)
    _show_active_options
    
    # Étape 5 : Finalisation et validation
    _validate_queue_not_empty
    _display_random_mode_selection
    _create_readable_queue_copy
}
