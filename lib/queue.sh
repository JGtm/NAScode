#!/bin/bash
###########################################################
# GESTION DE LA FILE D'ATTENTE
# Construction, tri et traitement de la queue de fichiers
###########################################################

###########################################################
# SOUS-FONCTIONS DE CONSTRUCTION DE LA FILE D'ATTENTE
###########################################################

_handle_custom_queue() {
    # Gestion du fichier queue personnalisé (Option -q)
    # Crée un INDEX à partir de la CUSTOM_QUEUE fournie
    if [[ -n "$CUSTOM_QUEUE" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo ""
            echo -e "${CYAN}📄 Utilisation du fichier queue personnalisé : $CUSTOM_QUEUE${NOCOLOR}"
        fi
        
        if ! validate_queue_file "$CUSTOM_QUEUE"; then
            exit 1
        fi
        
        # Convertir la CUSTOM_QUEUE (null-separated) en INDEX (taille\tchemin)
        # Calculer la taille pour chaque fichier
        tr '\0' '\n' < "$CUSTOM_QUEUE" | while read -r f; do
            echo -e "$(stat -c%s "$f")\t$f"
        done > "$INDEX"
        
        # Créer INDEX_READABLE
        cut -f2- "$INDEX" > "$INDEX_READABLE"
        
        return 0
    fi
    return 1
}

_handle_existing_index() {
    # Gestion de l'INDEX existant (demande à l'utilisateur si on doit le conserver)
    if [[ ! -f "$INDEX" ]]; then
        return 1
    fi
    
    local index_date=$(stat -c '%y' "$INDEX" | cut -d'.' -f1)
    # Si l'utilisateur a demandé de conserver l'index, on l'accepte sans demander
    if [[ "$KEEP_INDEX" == true ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${YELLOW}Utilisation forcée de l'index existant (--keep-index activé).${NOCOLOR}"
        fi
        # Vérifier que l'index n'est pas vide
        if ! [[ -s "$INDEX" ]]; then 
            echo "Index vide, régénération nécessaire..."
            rm -f "$INDEX" "$INDEX_READABLE"
            return 1
        fi
        return 0
    fi
    if [[ "$NO_PROGRESS" != true ]]; then
        echo ""
        echo -e "${CYAN}  Un fichier index existant a été trouvé.${NOCOLOR}"
        echo -e "${CYAN}  Date de création : $index_date${NOCOLOR}"
        echo ""
    fi
    
    # Lire la réponse depuis le terminal pour éviter de consommer l'entrée de xargs/cat
    read -r -p "Souhaitez-vous conserver ce fichier index ? (O/n) " response < /dev/tty
    
    case "$response" in
        [nN])
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "${YELLOW}Régénération d'un nouvel index...${NOCOLOR}"
            fi
            rm -f "$INDEX" "$INDEX_READABLE"
            return 1
            ;;
        *)
            if [[ "$NO_PROGRESS" != true ]]; then
                echo -e "${YELLOW}Utilisation de l'index existant.${NOCOLOR}"
            fi
            
            # Vérifier que l'index n'est pas vide
            if ! [[ -s "$INDEX" ]]; then 
                echo "Index vide, régénération nécessaire..."
                rm -f "$INDEX" "$INDEX_READABLE"
                return 1
            fi
            
            return 0
            ;;
    esac
}

_count_total_video_files() {
    local exclude_dir_name="$1"
    
    # Calcul du nombre total de fichiers candidats (lent, mais nécessaire pour l'affichage de progression)
    find "$SOURCE" \
        -wholename "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 2>/dev/null | \
    tr -cd '\0' | wc -c
}

_index_video_files() {
    local exclude_dir_name="$1"
    local total_files="$2"
    local queue_tmp="$3"
    local count_file="$4"
    
    # Deuxième passe : indexer les fichiers avec leur taille
    find "$SOURCE" \
        -wholename "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 | \
    while IFS= read -r -d $'\0' f; do
        if is_excluded "$f"; then continue; fi
        if [[ "$f" =~ \.(sh|txt)$ ]]; then continue; fi
        
        local count=$(($(cat "$count_file") + 1))
        echo "$count" > "$count_file"
        
        # Affichage de progression
        if [[ "$NO_PROGRESS" != true ]]; then
            printf "\rIndexation en cours... [%-${#total_files}d/${count}]" "$count" >&2
        fi
        
        # Stockage de la taille et du chemin (séparé par tab)
        echo -e "$(stat -c%s "$f")\t$f"
    done > "$queue_tmp"
}

_generate_index() {
    # Génération de l'INDEX (fichier permanent contenant tous les fichiers indexés avec tailles)
    local exclude_dir_name=$OUTPUT_DIR

    if [[ "$NO_PROGRESS" != true ]]; then 
        echo "Indexation fichiers..." >&2
    fi
    
    # Première passe : compter le nombre total de fichiers vidéo candidats
    local total_files=$(_count_total_video_files "$exclude_dir_name")

    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${BLUE}📊 Total de fichiers vidéo trouvés : ${total_files}${NOCOLOR}"
    fi

    # Initialiser le compteur
    local count_file="$TMP_DIR/.index_count_$$"
    echo "0" > "$count_file"
    
    # Deuxième passe : indexer les fichiers (stockage taille + chemin)
    local index_tmp="$INDEX.tmp"
    _index_video_files "$exclude_dir_name" "$total_files" "$index_tmp" "$count_file"
    
    local final_count=$(cat "$count_file")
    rm -f "$count_file"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "\n${GREEN}✅ Indexation terminée [${final_count} fichiers répertoriés]${NOCOLOR}" >&2
    fi
    
    # Sauvegarder l'INDEX (fichier permanent, non trié, format taille\tchemin)
    mv "$index_tmp" "$INDEX" 
    cut -f2- "$INDEX" > "$INDEX_READABLE"
}

_build_queue_from_index() {
    # Construction de la QUEUE à partir de l'INDEX (fichier permanent)
    # Appliquer le mode de tri configuré via SORT_MODE
    case "$SORT_MODE" in
        size_desc)
            # Trier par taille décroissante (par défaut)
            sort -nrk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        size_asc)
            # Trier par taille croissante
            sort -nk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        name_asc)
            # Trier par nom de fichier ascendant (utilise la 2ème colonne : chemin)
            sort -t$'\t' -k2,2 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        name_desc)
            # Trier par nom de fichier descendant
            sort -t$'\t' -k2,2 -r "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
        *)
            # Mode inconnu -> repli sur size_desc
            sort -nrk1,1 "$INDEX" | cut -f2- | tr '\n' '\0' > "$QUEUE"
            ;;
    esac
}


_apply_queue_limitations() {
    # APPLICATION DE LA LIMITATION (Unifiée, s'applique à la queue prête, peu importe sa source)
    local limit_count=$LIMIT_FILES
    
    if [[ "$limit_count" -eq 0 ]]; then
        return 0
    fi
    
    # Affichage du message de limitation
    if [[ "$NO_PROGRESS" != true ]]; then
        if [[ "$RANDOM_MODE" == true ]]; then
            echo -e "${MAGENTA}LIMITATION (RANDOM) : Sélection aléatoire de $limit_count fichiers maximum.${NOCOLOR}"
        else
            echo -e "${MAGENTA}LIMITATION : Traitement de $limit_count fichiers maximum.${NOCOLOR}"
        fi
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
}

_display_random_mode_selection() {													
    if [[ "$RANDOM_MODE" != true ]] || [[ "$NO_PROGRESS" == true ]]; then
        return 0
    fi
    
    echo -e "\n${CYAN}📋 Fichiers sélectionnés aléatoirement : ${NOCOLOR}"
    tr '\0' '\n' < "$QUEUE" | nl -w2 -s'. '
    echo ""
}

_create_readable_queue_copy() {																							  
    tr '\0' '\n' < "$QUEUE" > "$LOG_DIR/Queue_readable_${EXECUTION_TIMESTAMP}.txt"
}

###########################################################
# GESTION DES COMPTEURS (MODE FIFO)
###########################################################

# Incrémenter le compteur de fichiers traités (utilisé seulement en mode FIFO avec limite)
increment_processed_count() {
    # Ne rien faire si pas en mode FIFO (pas de limite)
    if [[ -z "${PROCESSED_COUNT_FILE:-}" ]] || [[ ! -f "${PROCESSED_COUNT_FILE:-}" ]]; then
        return 0
    fi
    
    local lockdir="$LOG_DIR/processed_count.lock"
    # Mutex simple via mkdir
    local attempts=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.05
        attempts=$((attempts + 1))
        if [[ $attempts -gt 100 ]]; then break; fi  # timeout 5s
    done
    
    local current=0
    if [[ -f "$PROCESSED_COUNT_FILE" ]]; then
        current=$(cat "$PROCESSED_COUNT_FILE" 2>/dev/null || echo 0)
    fi
    echo $((current + 1)) > "$PROCESSED_COUNT_FILE"
    
    rmdir "$lockdir" 2>/dev/null || true
}

# Quand un fichier est skip, ajouter le prochain candidat de la queue complète
# pour maintenir le nombre de fichiers demandés par --limit
update_queue() {
    # Ne rien faire si pas de limitation
    if [[ "$LIMIT_FILES" -le 0 ]]; then
        return 0
    fi
    
    # Vérifier que la FIFO existe
    if [[ -z "${WORKFIFO:-}" ]] || [[ ! -p "$WORKFIFO" ]]; then
        return 0
    fi

    local lockdir="$LOG_DIR/update_queue.lock"
    # Mutex simple via mkdir
    while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.01; done

    local nextpos=0
    if [[ -f "$NEXT_QUEUE_POS_FILE" ]]; then
        nextpos=$(cat "$NEXT_QUEUE_POS_FILE" 2>/dev/null) || nextpos=0
    fi
    local total=0
    if [[ -f "$TOTAL_QUEUE_FILE" ]]; then
        total=$(cat "$TOTAL_QUEUE_FILE" 2>/dev/null) || total=0
    fi

    if [[ $nextpos -lt $total ]]; then
        # Récupérer l'élément suivant
        local candidate
        candidate=$(tr '\0' '\n' < "$QUEUE_FULL" | sed -n "$((nextpos+1))p") || candidate=""
        if [[ -n "$candidate" ]]; then
            # Incrémenter aussi target_count pour que le writer attende ce fichier supplémentaire
            local current_target=0
            if [[ -f "$TARGET_COUNT_FILE" ]]; then
                current_target=$(cat "$TARGET_COUNT_FILE" 2>/dev/null || echo 0)
            fi
            echo $((current_target + 1)) > "$TARGET_COUNT_FILE"
            
            # Ecrire le nouveau fichier dans la FIFO
            printf '%s\0' "$candidate" > "$WORKFIFO" || true
        fi
        echo $((nextpos + 1)) > "$NEXT_QUEUE_POS_FILE"
    fi

    rmdir "$lockdir" 2>/dev/null || true
}

###########################################################
# FONCTION PRINCIPALE DE CONSTRUCTION DE LA QUEUE
###########################################################

build_queue() {
    # Étape 1 : Gestion de l'INDEX (source de vérité)
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
    
    # Étape 4 : Finalisation et validation
    _validate_queue_not_empty
    _display_random_mode_selection
    _create_readable_queue_copy
}
