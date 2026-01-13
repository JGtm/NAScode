#!/bin/bash
###########################################################
# GESTION DU VERROUILLAGE
# Verrous pour éviter les exécutions multiples
###########################################################

###########################################################
# NETTOYAGE DES FICHIERS TEMPORAIRES X265
###########################################################

# Nettoyer les fichiers de log x265 two-pass créés par FFmpeg
# Ces fichiers sont générés dans le répertoire courant lors de l'encodage
_cleanup_x265_logs() {
    local found_files=0
    
    # Chercher les fichiers x265_2pass.log et .cutree dans le répertoire du script
    # et dans le répertoire courant
    for search_dir in "${SCRIPT_DIR:-.}" "$(pwd)"; do
        if [[ -d "$search_dir" ]]; then
            # Utiliser find pour trouver les fichiers (plus robuste)
            while IFS= read -r -d '' log_file; do
                if [[ -f "$log_file" ]]; then
                    rm -f "$log_file" 2>/dev/null && found_files=$((found_files + 1))
                fi
            done < <(find "$search_dir" -maxdepth 1 -name "x265_2pass.log*" -print0 2>/dev/null)
        fi
    done
    
    # Afficher un message si des fichiers ont été nettoyés
    if [[ "$found_files" -gt 0 ]] && [[ "${NO_PROGRESS:-}" != true ]]; then
        echo -e "${CYAN}🧹 Nettoyage de $found_files fichier(s) x265 temporaire(s)${NOCOLOR}"
    fi
}

###########################################################
# NETTOYAGE À LA SORTIE
###########################################################

cleanup() {
    local exit_code=$?
    # Afficher le message d'interruption seulement si terminaison par signal (INT/TERM)
    # et pas déjà signalé par STOP_FLAG
    # Note: On utilise une variable pour détecter les signaux plutôt que le code de sortie
    if [[ "${_INTERRUPTED:-}" == "1" ]] && [[ ! -f "$STOP_FLAG" ]]; then
        echo ""
        print_warning "Interruption détectée, arrêt en cours..."
    fi

    # Notification externe (Discord) — best-effort
    if declare -f notify_event_script_exit &>/dev/null; then
        notify_event_script_exit "$exit_code" || true
    fi
    
    # IMPORTANT: Ne créer le STOP_FLAG que lors d'une vraie interruption (Ctrl+C, kill, etc.)
    # En fin normale, le flag ne doit PAS être créé pour éviter de bloquer les transferts asynchrones
    # qui vérifient ce flag pour savoir s'ils doivent finaliser ou non.
    if [[ "${_INTERRUPTED:-}" == "1" ]]; then
        touch "$STOP_FLAG"
    fi
    
    # Supprimer les messages résiduels des sous-processus en redirigeant stderr
    # vers /dev/null pendant le cleanup
    exec 2>/dev/null
    
    # Envoyer SIGTERM aux jobs en arrière-plan
    local -a job_pids=()
    mapfile -t job_pids < <(jobs -p 2>/dev/null || true)
    if (( ${#job_pids[@]} > 0 )); then
        kill "${job_pids[@]}" 2>/dev/null || true
    fi
    
    # Tuer tous les processus enfants du process group (inclut les sous-processus
    # lancés par des pipes/subshells qui échappent à jobs -p)
    # Le - devant $$ cible tout le process group
    kill -- -$$ 2>/dev/null || true
    
    # Attendre que tous les processus enfants se terminent proprement
    # Cela évite que leurs messages s'affichent après le retour au prompt
    wait 2>/dev/null || true
    
    # Petit délai pour laisser les processus finir d'écrire
    sleep 0.2
    
    rm -f "$LOCKFILE"
    # Nettoyage des artefacts de queue dynamique
    if [[ -n "${WORKFIFO:-}" ]]; then
        rm -f "${WORKFIFO}" 2>/dev/null || true
    fi
    # Suppression des artefacts du writer FIFO si présents
    if [[ -n "${FIFO_WRITER_PID:-}" ]]; then
        rm -f "${FIFO_WRITER_PID}" "${FIFO_WRITER_READY:-}" 2>/dev/null || true
    fi
    # Nettoyage des slots de progression parallèle
    cleanup_progress_slots
    
    # Nettoyage des fichiers temporaires x265 two-pass (logs d'encodage)
    # Ces fichiers sont créés dans le répertoire courant par FFmpeg/x265
    _cleanup_x265_logs

    # Nettoyage des logs temporaires (Queue, Progress) - même en cas d'interruption
    # On garde Index_readable comme demandé
    if [[ -d "${LOG_DIR:-./logs}" ]]; then
        rm -f "${LOG_DIR:-./logs}/Queue" "${LOG_DIR:-./logs}/Progress_"* 2>/dev/null || true
        # Supprimer aussi les fichiers temporaires .vmaf_queue, compteurs de taille, etc.
        rm -f "${LOG_DIR:-./logs}/.vmaf_queue_"* 2>/dev/null || true
        rm -f "${LOG_DIR:-./logs}/.total_size_"* 2>/dev/null || true
        rm -f "${LOG_DIR:-./logs}/next_queue_pos_"* 2>/dev/null || true
        rm -f "${LOG_DIR:-./logs}/fifo_writer"* 2>/dev/null || true
    fi
}

# Variable pour détecter une vraie interruption (Ctrl+C ou kill)
_INTERRUPTED=0
_handle_interrupt() {
    _INTERRUPTED=1
    exit 130
}

###########################################################
# VÉRIFICATION DU VERROU PRINCIPAL
###########################################################

check_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE")
        
        if ps -p "$pid" > /dev/null 2>&1; then
            print_error "Le script est déjà en cours d'exécution (PID $pid)."
            exit 1
        else
            print_warning "Fichier lock trouvé mais processus absent. Nettoyage..."
            rm -f "$LOCKFILE"
        fi
    fi
    
    echo $$ > "$LOCKFILE"
}

###########################################################
# CONFIGURATION DES TRAPS
###########################################################

setup_traps() {
    trap cleanup EXIT
    trap _handle_interrupt INT TERM
}
