#!/bin/bash
###########################################################
# GESTION DE LA FILE D'ATTENTE
# Construction, tri et traitement de la queue de fichiers
###########################################################

###########################################################
# VALIDATION DU FICHIER QUEUE
###########################################################

# Valide qu'un fichier queue est bien formé (non vide, format null-separated).
# Utilisé pour les queues personnalisées (-q) et la validation interne.
validate_queue_file() {
    local queue_file="$1"
    
    if [[ ! -f "$queue_file" ]]; then
        echo -e "${RED}ERREUR : Le fichier queue '$queue_file' n'existe pas.${NOCOLOR}"
        return 1
    fi
    
    if [[ ! -s "$queue_file" ]]; then
        echo -e "${RED}ERREUR : Le fichier queue '$queue_file' est vide.${NOCOLOR}"
        return 1
    fi
    
    local file_count=$(count_null_separated "$queue_file")
    if [[ $file_count -eq 0 ]]; then
        echo -e "${RED}ERREUR : Le fichier queue n'a pas le format attendu (fichiers séparés par null).${NOCOLOR}"
        return 1
    fi
    
    local test_read=$(head -c 100 "$queue_file" | tr '\0' '\n' | head -1)
    if [[ -z "$test_read" ]] && [[ $file_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Le fichier queue semble valide ($file_count fichiers détectés).${NOCOLOR}"
    else
        echo -e "${GREEN}✅ Fichier queue validé ($file_count fichiers détectés).${NOCOLOR}"
    fi
    
    return 0
}

###########################################################
# VALIDATION DE LA SOURCE DE L'INDEX
###########################################################

# Normalise un chemin source pour comparaison (chemin absolu canonique)
_normalize_source_path() {
    local path="$1"
    # Utiliser normalize_path si disponible (pour MSYS/Windows)
    if declare -f normalize_path &>/dev/null; then
        path=$(normalize_path "$path")
    fi
    # Convertir en chemin absolu si relatif
    if [[ ! "$path" = /* ]] && [[ ! "$path" =~ ^[A-Z]: ]]; then
        path="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
    # Supprimer le slash final pour uniformité
    path="${path%/}"
    echo "$path"
}

# Vérifie si l'index existant correspond à la source actuelle
# Retourne 0 si valide, 1 si régénération nécessaire
_validate_index_source() {
    # Si pas de fichier de métadonnées, on ne peut pas valider → régénérer
    if [[ ! -f "$INDEX_META" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${YELLOW}⚠️  Pas de métadonnées pour l'index existant, régénération...${NOCOLOR}"
        fi
        rm -f "$INDEX" "$INDEX_READABLE"
        return 1
    fi
    
    # Lire la source stockée dans les métadonnées
    local stored_source=""
    stored_source=$(grep '^SOURCE=' "$INDEX_META" 2>/dev/null | cut -d'=' -f2-)
    
    if [[ -z "$stored_source" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${YELLOW}⚠️  Source non trouvée dans les métadonnées, régénération...${NOCOLOR}"
        fi
        rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
        return 1
    fi
    
    # Normaliser les deux chemins pour comparaison
    local current_source_normalized=$(_normalize_source_path "$SOURCE")
    local stored_source_normalized=$(_normalize_source_path "$stored_source")
    
    if [[ "$current_source_normalized" != "$stored_source_normalized" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${YELLOW}⚠️  La source a changé :${NOCOLOR}"
            echo -e "${YELLOW}    Index créé pour : $stored_source${NOCOLOR}"
            echo -e "${YELLOW}    Source actuelle : $SOURCE${NOCOLOR}"
            echo -e "${YELLOW}    Régénération automatique de l'index...${NOCOLOR}"
        fi
        rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
        return 1
    fi
    
    return 0
}

# Sauvegarde les métadonnées de l'index (source utilisée, date, etc.)
_save_index_metadata() {
    {
        echo "SOURCE=$SOURCE"
        echo "CREATED=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "OUTPUT_DIR=$OUTPUT_DIR"
    } > "$INDEX_META"
}

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
        
        # Créer INDEX_READABLE et sauvegarder les métadonnées
        cut -f2- "$INDEX" > "$INDEX_READABLE"
        _save_index_metadata
        
        return 0
    fi
    return 1
}

_handle_existing_index() {
    # Gestion de l'INDEX existant (demande à l'utilisateur si on doit le conserver)
    if [[ ! -f "$INDEX" ]]; then
        return 1
    fi
    
    # Vérifier que l'index n'est pas vide
    if ! [[ -s "$INDEX" ]]; then 
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "${YELLOW}Index vide, régénération nécessaire...${NOCOLOR}"
        fi
        rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
        return 1
    fi
    
    # Vérifier si l'index correspond à la source actuelle
    if ! _validate_index_source; then
        return 1
    fi
    
    local index_date=$(stat -c '%y' "$INDEX" | cut -d'.' -f1)
    # Si l'utilisateur a demandé de conserver l'index, on l'accepte sans demander
    if [[ "$KEEP_INDEX" == true ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            print_info "Utilisation forcée de l'index existant (--keep-index)"
        fi
        return 0
    fi
    if [[ "$NO_PROGRESS" != true ]]; then
        print_info_box "Index existant trouvé" "Date de création : $index_date"
    fi
    
    # Lire la réponse depuis le terminal pour éviter de consommer l'entrée de xargs/cat
    ask_question "Conserver ce fichier index ?"
    read -r response < /dev/tty
    
    case "$response" in
        [nN])
            if [[ "$NO_PROGRESS" != true ]]; then
                print_status "Régénération d'un nouvel index..."
            fi
            rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
            return 1
            ;;
        *)
            if [[ "$NO_PROGRESS" != true ]]; then
                print_success "Index existant conservé"
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
        
        # Affichage de progression (icône + compteur)
        if [[ "$NO_PROGRESS" != true ]]; then
            printf "\r${BLUE}📊 Indexation en cours... [%d/%d]${NOCOLOR}" "$count" "$total_files" >&2
        fi
        
        # Stockage de la taille et du chemin (séparé par tab)
        echo -e "$(stat -c%s "$f")\t$f"
    done > "$queue_tmp"
}

_generate_index() {
    # Génération de l'INDEX (fichier permanent contenant tous les fichiers indexés avec tailles)
    local exclude_dir_name=$OUTPUT_DIR
    
    # Première passe : compter le nombre total de fichiers vidéo candidats
    local total_files=$(_count_total_video_files "$exclude_dir_name")

    # Initialiser le compteur
    local count_file="$TMP_DIR/.index_count_$$"
    echo "0" > "$count_file"
    
    # Deuxième passe : indexer les fichiers (stockage taille + chemin)
    local index_tmp="$INDEX.tmp"
    _index_video_files "$exclude_dir_name" "$total_files" "$index_tmp" "$count_file"
    
    local final_count=$(cat "$count_file")
    rm -f "$count_file"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "\n${GREEN}✅ ${final_count} fichiers indexés${NOCOLOR}" >&2
    fi
    
    # Sauvegarder l'INDEX (fichier permanent, non trié, format taille\tchemin)
    mv "$index_tmp" "$INDEX" 
    cut -f2- "$INDEX" > "$INDEX_READABLE"
    
    # Sauvegarder les métadonnées de l'index (source, date, etc.)
    _save_index_metadata
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
            print_limitation "Sélection aléatoire de $limit_count fichiers maximum" "random"
        else
            print_limitation "Traitement de $limit_count fichiers maximum"
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
