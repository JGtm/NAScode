#!/bin/bash
###########################################################
# GESTION DES COMPTEURS
# Compteurs persistants pour le mode FIFO et les limitations
# Extrait de queue.sh pour modularité
###########################################################

###########################################################
# VARIABLES DE COMPTAGE (AFFICHAGE)
###########################################################

# Variable pour stocker le numéro de fichier courant (pour affichage [X/Y])
CURRENT_FILE_NUMBER=0

# En mode limite (-l), afficher un compteur "slot en cours" 1-based pour l'UX.
# Le slot est réservé de façon atomique (mutex) uniquement quand on sait
# qu'on ne va PAS skip le fichier (y compris après analyse adaptative).
# Il reste stable pendant tout le traitement du fichier.
LIMIT_DISPLAY_SLOT=0

###########################################################
# COMPTEURS DE FICHIERS TRAITÉS/CONVERTIS
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

# Incrémente le compteur de fichiers réellement convertis (pas les skips)
# Utilisé pour l'affichage "X/LIMIT" en mode limite
increment_converted_count() {
    # Ne rien faire si pas en mode limite
    if [[ -z "${CONVERTED_COUNT_FILE:-}" ]] || [[ ! -f "${CONVERTED_COUNT_FILE:-}" ]]; then
        return 0
    fi
    
    local lockdir="$LOG_DIR/converted_count.lock"
    # Mutex simple via mkdir
    local attempts=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.05
        attempts=$((attempts + 1))
        if [[ $attempts -gt 100 ]]; then break; fi  # timeout 5s
    done
    
    local current=0
    if [[ -f "$CONVERTED_COUNT_FILE" ]]; then
        current=$(cat "$CONVERTED_COUNT_FILE" 2>/dev/null || echo 0)
    fi
    local new_value=$((current + 1))
    echo "$new_value" > "$CONVERTED_COUNT_FILE"
    
    rmdir "$lockdir" 2>/dev/null || true
    
    echo "$new_value"
}

# Lit le compteur de fichiers convertis (pour affichage final)
get_converted_count() {
    if [[ -z "${CONVERTED_COUNT_FILE:-}" ]] || [[ ! -f "${CONVERTED_COUNT_FILE:-}" ]]; then
        echo "0"
        return 0
    fi
    cat "$CONVERTED_COUNT_FILE" 2>/dev/null || echo "0"
}

# Incrémente le compteur de fichier au DÉBUT du traitement et retourne la nouvelle valeur
# Utilisé pour l'affichage "Fichier X/Y"
increment_starting_counter() {
    # Ne rien faire si pas de fichier compteur
    if [[ -z "${STARTING_FILE_COUNTER_FILE:-}" ]] || [[ ! -f "${STARTING_FILE_COUNTER_FILE:-}" ]]; then
        echo "0"
        return 0
    fi
    
    local lockdir="$LOG_DIR/starting_counter.lock"
    # Mutex simple via mkdir
    local attempts=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.05
        attempts=$((attempts + 1))
        if [[ $attempts -gt 100 ]]; then break; fi  # timeout 5s
    done
    
    local current=0
    if [[ -f "$STARTING_FILE_COUNTER_FILE" ]]; then
        current=$(cat "$STARTING_FILE_COUNTER_FILE" 2>/dev/null || echo 0)
    fi
    local new_value=$((current + 1))
    echo "$new_value" > "$STARTING_FILE_COUNTER_FILE"
    
    rmdir "$lockdir" 2>/dev/null || true
    
    echo "$new_value"
}

###########################################################
# MISE À JOUR DYNAMIQUE DE LA QUEUE (MODE FIFO)
###########################################################

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
