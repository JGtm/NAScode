#!/bin/bash
###########################################################
# GESTION DES TRANSFERTS ASYNCHRONES
# Transfert des fichiers convertis en arrière-plan
###########################################################

###########################################################
# CONFIGURATION DES TRANSFERTS
###########################################################

# Nombre maximum de transferts simultanés
# Au-delà, on attend qu'un transfert se termine avant d'en lancer un nouveau
readonly MAX_CONCURRENT_TRANSFERS=2

# Fichier pour stocker les PIDs des transferts en cours
# Format: un PID par ligne
TRANSFER_PIDS_FILE=""

###########################################################
# INITIALISATION
###########################################################

# Initialiser le système de transferts asynchrones
# Appelé une fois au démarrage du script
init_async_transfers() {
    TRANSFER_PIDS_FILE="$LOG_DIR/.transfer_pids_${EXECUTION_TIMESTAMP}"
    # Créer le fichier vide
    : > "$TRANSFER_PIDS_FILE"
    export TRANSFER_PIDS_FILE
}

###########################################################
# GESTION DES PIDs DE TRANSFERT
###########################################################

# Ajouter un PID de transfert à la liste
# Usage: _add_transfer_pid <pid>
_add_transfer_pid() {
    local pid="$1"
    if [[ -n "$TRANSFER_PIDS_FILE" ]]; then
        echo "$pid" >> "$TRANSFER_PIDS_FILE"
    fi
}

# Nettoyer les PIDs de transferts terminés de la liste
# Met à jour le fichier en ne gardant que les processus encore actifs
_cleanup_finished_transfers() {
    if [[ -z "$TRANSFER_PIDS_FILE" ]] || [[ ! -f "$TRANSFER_PIDS_FILE" ]]; then
        return 0
    fi
    
    local tmp_file="${TRANSFER_PIDS_FILE}.tmp"
    : > "$tmp_file"
    
    while read -r pid; do
        # Vérifier si le processus est encore actif
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid" >> "$tmp_file"
        fi
    done < "$TRANSFER_PIDS_FILE"
    
    mv "$tmp_file" "$TRANSFER_PIDS_FILE"
}

# Compter le nombre de transferts actuellement en cours
# Retourne le nombre sur stdout
_count_active_transfers() {
    _cleanup_finished_transfers
    
    if [[ -z "$TRANSFER_PIDS_FILE" ]] || [[ ! -f "$TRANSFER_PIDS_FILE" ]]; then
        echo "0"
        return
    fi
    
    # Compter les lignes non vides (wc -l plus fiable que grep -c)
    local count
    count=$(grep -c '[0-9]' "$TRANSFER_PIDS_FILE" 2>/dev/null) || count=0
    # Nettoyer les espaces et retours à la ligne
    count=$(echo "$count" | tr -d '[:space:]')
    [[ -z "$count" ]] && count=0
    echo "$count"
}

###########################################################
# ATTENTE DE TRANSFERTS
###########################################################

# Attendre qu'un slot de transfert soit disponible
# Si le nombre max est atteint, affiche un message et attend
wait_for_transfer_slot() {
    local active_count
    active_count=$(_count_active_transfers)
    
    # Si on n'a pas atteint la limite, on peut continuer
    if [[ "$active_count" -lt "$MAX_CONCURRENT_TRANSFERS" ]]; then
        return 0
    fi
    
    # Afficher le message d'attente
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "  ${YELLOW}⏳ Attente fin de transfert... ($active_count transferts en cours)${NOCOLOR}"
    fi
    
    # Attendre qu'au moins un transfert se termine
    while [[ "$active_count" -ge "$MAX_CONCURRENT_TRANSFERS" ]]; do
        sleep 0.5
        active_count=$(_count_active_transfers)
    done
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "  ${GREEN}✓ Slot de transfert disponible${NOCOLOR}"
    fi
}

# Attendre que TOUS les transferts en cours soient terminés
# Appelé avant le résumé final et l'analyse VMAF
wait_all_transfers() {
    local active_count
    active_count=$(_count_active_transfers)
    
    if [[ "$active_count" -eq 0 ]]; then
        return 0
    fi
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo ""
        echo -e "${CYAN}⏳ Attente de la fin des transferts en cours ($active_count restants)...${NOCOLOR}"
    fi
    
    # Attendre tous les transferts
    while [[ "$active_count" -gt 0 ]]; do
        sleep 0.5
        local new_count
        new_count=$(_count_active_transfers)
        
        # Afficher la progression si le nombre a changé
        if [[ "$new_count" -ne "$active_count" ]] && [[ "$NO_PROGRESS" != true ]]; then
            if [[ "$new_count" -gt 0 ]]; then
                echo -e "  ${CYAN}⏳ $new_count transfert(s) restant(s)...${NOCOLOR}"
            fi
        fi
        active_count="$new_count"
    done
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "${GREEN}✅ Tous les transferts sont terminés${NOCOLOR}"
    fi
}

###########################################################
# TRANSFERT ASYNCHRONE
###########################################################

# Lancer un transfert en arrière-plan
# Usage: start_async_transfer <tmp_output> <final_output> <file_original> <callback_data>
# callback_data: données pour le logging (checksum_before|sizeBeforeMB|sizeBeforeBytes|tmp_input|ffmpeg_log_temp)
start_async_transfer() {
    local tmp_output="$1"
    local final_output="$2"
    local file_original="$3"
    local callback_data="$4"
    
    # Lancer le transfert dans un sous-shell en arrière-plan
    (
        # Extraire les données du callback
        IFS='|' read -r checksum_before sizeBeforeMB sizeBeforeBytes tmp_input ffmpeg_log_temp <<< "$callback_data"
        
        # Effectuer le déplacement/copie
        local final_actual
        final_actual=$(_finalize_try_move "$tmp_output" "$final_output" "$file_original") || true
        
        # Effectuer le logging et la vérification d'intégrité
        _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "$checksum_before" "$sizeBeforeMB" "$sizeBeforeBytes"
    ) &
    
    local transfer_pid=$!
    _add_transfer_pid "$transfer_pid"
    
    if [[ "$NO_PROGRESS" != true ]]; then
        echo -e "  ${CYAN}📤 Transfert lancé en arrière-plan (PID: $transfer_pid)${NOCOLOR}"
    fi
}

###########################################################
# NETTOYAGE
###########################################################

# Nettoyer les ressources de transfert à la fin du script
cleanup_transfers() {
    # Attendre tous les transferts
    wait_all_transfers
    
    # Supprimer le fichier de PIDs
    if [[ -n "$TRANSFER_PIDS_FILE" ]] && [[ -f "$TRANSFER_PIDS_FILE" ]]; then
        rm -f "$TRANSFER_PIDS_FILE" 2>/dev/null || true
    fi
}
