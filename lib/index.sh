#!/bin/bash
###########################################################
# GESTION DE L'INDEX
# Construction et validation de l'index des fichiers vidéo
# Extrait de queue.sh pour modularité
###########################################################

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
    # Si régénération forcée demandée
    if [[ "${REGENERATE_INDEX:-false}" == true ]]; then
        print_warning "Régénération forcée de l'index demandée."
        rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
        return 1
    fi

    # Si pas de fichier de métadonnées, on ne peut pas valider → régénérer
    if [[ ! -f "$INDEX_META" ]]; then
        print_warning "Pas de métadonnées pour l'index existant, régénération..."
        rm -f "$INDEX" "$INDEX_READABLE"
        return 1
    fi
    
    # Lire la source stockée dans les métadonnées
    local stored_source=""
    stored_source=$(grep '^SOURCE=' "$INDEX_META" 2>/dev/null | cut -d'=' -f2-)
    
    if [[ -z "$stored_source" ]]; then
        print_warning "Source non trouvée dans les métadonnées, régénération..."
        rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
        return 1
    fi
    
    # Normaliser les deux chemins pour comparaison
    local current_source_normalized
    current_source_normalized=$(_normalize_source_path "$SOURCE")
    local stored_source_normalized
    stored_source_normalized=$(_normalize_source_path "$stored_source")
    
    if [[ "$current_source_normalized" != "$stored_source_normalized" ]]; then
        if [[ "${UI_QUIET:-false}" == true ]]; then
            print_warning "La source a changé, régénération automatique de l'index."
        else
            print_warning "La source a changé :"
            print_item "Index créé pour" "$stored_source" "$YELLOW"
            print_item "Source actuelle" "$SOURCE" "$YELLOW"
            print_warning "Régénération automatique de l'index..."
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
# SOUS-FONCTIONS DE CONSTRUCTION DE L'INDEX
###########################################################

_handle_custom_queue() {
    # Gestion du fichier queue personnalisé (Option -q)
    # Crée un INDEX à partir de la CUSTOM_QUEUE fournie
    if [[ -n "$CUSTOM_QUEUE" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo ""
                print_info "Utilisation du fichier queue personnalisé : $CUSTOM_QUEUE"
        fi
        
        if ! validate_queue_file "$CUSTOM_QUEUE"; then
            exit 1
        fi
        
        # Convertir la CUSTOM_QUEUE (null-separated) en INDEX (taille\tchemin)
        # Calculer la taille pour chaque fichier, et appliquer le filtre --min-size si actif.
        tr '\0' '\n' < "$CUSTOM_QUEUE" | while read -r f; do
            [[ -z "$f" ]] && continue
            local size
            size=$(get_file_size_bytes "$f")
            if [[ "${MIN_SIZE_BYTES:-0}" -gt 0 ]] && [[ "$size" -lt "$MIN_SIZE_BYTES" ]]; then
                continue
            fi
            echo -e "${size}\t$f"
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
        print_warning "Index vide, régénération nécessaire..."
        rm -f "$INDEX" "$INDEX_READABLE" "$INDEX_META"
        return 1
    fi
    
    # Vérifier si l'index correspond à la source actuelle
    if ! _validate_index_source; then
        return 1
    fi
    
    local index_date
    index_date=$(stat -c '%y' "$INDEX" | cut -d'.' -f1)
    # Si l'utilisateur a demandé de conserver l'index, on l'accepte sans demander
    if [[ "$KEEP_INDEX" == true ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            print_index_kept "Utilisation forcée de l'index existant"
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
                print_index_kept "Index existant conservé"
            fi
            return 0
            ;;
    esac
}

_count_total_video_files() {
    local exclude_dir_name="$1"
    local count=0
    
    # Calcul du nombre total de fichiers candidats (applique les mêmes exclusions que l'indexation)
    while IFS= read -r -d $'\0' f; do
        # Appliquer les mêmes exclusions que _index_video_files
        if is_excluded "$f"; then continue; fi
        if [[ "$f" =~ \.(sh|txt)$ ]]; then continue; fi

        # Si filtre taille activé, ne compter que les fichiers >= seuil
        if [[ "${MIN_SIZE_BYTES:-0}" -gt 0 ]]; then
            local size
            size=$(get_file_size_bytes "$f")
            if [[ "$size" -lt "$MIN_SIZE_BYTES" ]]; then
                continue
            fi
        fi
        ((count++))
    done < <(find "$SOURCE" \
        -wholename "$exclude_dir_name" -prune \
        -o \
        -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" \) -print0 2>/dev/null)
    
    echo "$count"
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
        
        # Stockage de la taille et du chemin (séparé par tab)
        local size
        size=$(get_file_size_bytes "$f")

        # Filtre taille (index/queue) : ne garder que les fichiers >= seuil
        if [[ "${MIN_SIZE_BYTES:-0}" -gt 0 ]] && [[ "$size" -lt "$MIN_SIZE_BYTES" ]]; then
            continue
        fi

        # Incrémenter le compteur APRÈS le filtre (sinon progression incorrecte)
        local count
        count=$(($(cat "$count_file") + 1))
        echo "$count" > "$count_file"
        
        # Affichage de progression
        if [[ "$NO_PROGRESS" != true ]]; then
            print_indexing_progress "$count" "$total_files"
        fi

        echo -e "${size}\t$f"
    done > "$queue_tmp"
}

_generate_index() {
    # Génération de l'INDEX (fichier permanent contenant tous les fichiers indexés avec tailles)
    local exclude_dir_name=$OUTPUT_DIR
    
    # Première passe : compter le nombre total de fichiers vidéo candidats
    local total_files
    total_files=$(_count_total_video_files "$exclude_dir_name")

    # Afficher l'en-tête du bloc d'indexation
    if [[ "$NO_PROGRESS" != true ]]; then
        print_indexing_start >&2
    fi

    # Initialiser le compteur
    local count_file="$TMP_DIR/.index_count_$$"
    echo "0" > "$count_file"
    
    # Deuxième passe : indexer les fichiers (stockage taille + chemin)
    local index_tmp="$INDEX.tmp"
    _index_video_files "$exclude_dir_name" "$total_files" "$index_tmp" "$count_file"
    
    local final_count
    final_count=$(cat "$count_file")
    rm -f "$count_file"
    
    # Afficher la fin du bloc d'indexation
    if [[ "$NO_PROGRESS" != true ]]; then
        print_indexing_end "$final_count"
    fi
    
    # Sauvegarder l'INDEX (fichier permanent, non trié, format taille\tchemin)
    mv "$index_tmp" "$INDEX" 
    cut -f2- "$INDEX" > "$INDEX_READABLE"
    
    # Sauvegarder les métadonnées de l'index (source, date, etc.)
    _save_index_metadata
}
