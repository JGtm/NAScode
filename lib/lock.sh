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
        echo -e "\n${YELLOW}⚠️ Interruption détectée, arrêt en cours...${NOCOLOR}"
    fi
    touch "$STOP_FLAG"
    
    # Supprimer les messages résiduels des sous-processus en redirigeant stderr
    # vers /dev/null pendant le cleanup
    exec 2>/dev/null
    
    # Envoyer SIGTERM aux jobs en arrière-plan
    kill $(jobs -p) 2>/dev/null || true
    
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
            echo -e "${RED}⛔ Le script est déjà en cours d'exécution (PID $pid).${NOCOLOR}"
            exit 1
        else
            echo -e "${YELLOW}⚠️ Fichier lock trouvé mais processus absent. Nettoyage...${NOCOLOR}"
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
