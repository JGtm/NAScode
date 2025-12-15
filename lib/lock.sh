#!/bin/bash
###########################################################
# GESTION DU VERROUILLAGE
# Verrous pour éviter les exécutions multiples
###########################################################

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
