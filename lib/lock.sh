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
    # Attendre brièvement que les processus en arrière-plan détectent le STOP_FLAG
    sleep 0.3
    kill $(jobs -p) 2>/dev/null || true
    # Attendre que les jobs se terminent pour éviter les messages après le prompt
    wait 2>/dev/null || true
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
# HELPERS PORTABLES POUR VERROU/DÉVERROUILLAGE
###########################################################

# Utilisation : lock <chemin> [timeout_seconds]
# Si `flock` est disponible il est privilégié, sinon on utilise un verrou par répertoire (mkdir).
lock() {
    local file="$1"
    local timeout="${2:-10}"

    if [[ -z "$file" ]]; then
        return 1
    fi

    if command -v flock >/dev/null 2>&1; then
        # Utilise un descripteur de fichier dédié pour maintenir le flock
        exec 200>"$file" || return 1
        local elapsed=0
        while ! flock -n 200; do
            sleep 1
            elapsed=$((elapsed+1))
            if (( elapsed >= timeout )); then
                return 2
            fi
        done
        return 0
    else
        # Repli : créer un répertoire de verrou (opération atomique sur les systèmes POSIX)
        local lockdir="${file}.lock"
        local elapsed_ms=0
        while ! mkdir "$lockdir" 2>/dev/null; do
            sleep 0.1
            elapsed_ms=$((elapsed_ms+1))
            if (( elapsed_ms >= timeout * 10 )); then
                return 2
            fi
        done
        printf "%s\n" "$$" > "$lockdir/pid" 2>/dev/null || true
        return 0
    fi
}

# Utilisation : unlock <chemin>
unlock() {
    local file="$1"
    if [[ -z "$file" ]]; then
        return 1
    fi

    if command -v flock >/dev/null 2>&1; then
        # Ferme le descripteur 200 si ouvert
        exec 200>&- 2>/dev/null || true
        return 0
    else
        local lockdir="${file}.lock"
        rm -rf "$lockdir" 2>/dev/null || true
        return 0
    fi
}

###########################################################
# CONFIGURATION DES TRAPS
###########################################################

setup_traps() {
    trap cleanup EXIT
    trap _handle_interrupt INT TERM
}
