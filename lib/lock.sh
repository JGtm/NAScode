#!/bin/bash
###########################################################
# GESTION DU VERROUILLAGE
# Verrous pour éviter les exécutions multiples
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Le cleanup() doit continuer même si des commandes
#    échouent (kill, rm sur fichiers absents, etc.)
# 3. Les modules sont sourcés, pas exécutés directement
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
# ARRÊT DES ENCODEURS RÉCALCITRANTS
###########################################################

# Noms des processus lourds à ne jamais laisser orphelins après un cleanup.
_CLEANUP_KILL_NAMES="${_CLEANUP_KILL_NAMES:-ffmpeg ffprobe SvtAv1EncApp}"

# Liste les PID des encodeurs DESCENDANTS de <root> (défaut : ce shell), par
# parcours de l'arbre ppid. À appeler AVANT de tuer les parents : un orphelin est
# rattaché à PID 1 et sort de l'arbre. Ne vise jamais les ffmpeg d'autres
# programmes du même process group (script appelant, autres runs, tests).
# Silencieux et vide si `ps -o` est indisponible (MSYS).
_cleanup_descendant_encoders() {
    local root="${1:-$$}"
    ps -A -o pid= -o ppid= -o comm= 2>/dev/null | awk -v root="$root" -v names="$_CLEANUP_KILL_NAMES" '
        BEGIN { n = split(names, arr, " "); for (i = 1; i <= n; i++) want[arr[i]] = 1 }
        {
            pid = $1; ppid = $2; c = $3
            for (i = 4; i <= NF; i++) c = c " " $i
            sub(/.*\//, "", c)
            parent[pid] = ppid; comm[pid] = c
        }
        END {
            for (pid in parent) {
                if (!(comm[pid] in want)) continue
                p = parent[pid]; depth = 0
                while (p != "" && p != 0 && p != 1 && depth < 64) {
                    if (p == root) { print pid; break }
                    p = parent[p]; depth++
                }
            }
        }'
}

# Un encodeur peut survivre au SIGTERM de groupe (ffmpeg bloqué dans sa saisie
# clavier l'ignore) et rester orphelin à 100 % CPU. Pour les PID donnés (relevés
# par _cleanup_descendant_encoders avant le kill) : SIGTERM, courte période de
# grâce, puis SIGKILL des survivants.
# Usage: _cleanup_kill_survivors <grace_ticks de 0,2 s> [pid...]
_cleanup_kill_survivors() {
    local ticks="${1:-10}"; shift || true
    local -a pids=("$@") alive=()
    local i p
    [[ ${#pids[@]} -eq 0 ]] && return 0
    kill -TERM "${pids[@]}" 2>/dev/null
    for (( i = 0; i <= ticks; i++ )); do
        alive=()
        for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive+=("$p"); done
        [[ ${#alive[@]} -eq 0 ]] && return 0
        (( i < ticks )) && sleep 0.2
    done
    kill -9 "${alive[@]}" 2>/dev/null
    return 0
}

# Supprime les temporaires enregistrés par ce run (cf. _register_temp_path),
# y compris les dérivés (ex. <log>.pass1). Uniquement après interruption : en fin
# normale, des transferts asynchrones peuvent encore utiliser certains fichiers.
_cleanup_run_temp_files() {
    local registry="${TMP_DIR:-/tmp/video_convert}/.run_tmp_${EXECUTION_TIMESTAMP:-0}_$$"
    [[ -f "$registry" ]] || return 0
    local p
    while IFS= read -r p; do
        # Garde-fou : ne jamais supprimer hors de TMP_DIR
        [[ -n "$p" && "$p" == "${TMP_DIR:-/tmp/video_convert}/"* ]] || continue
        rm -rf -- "$p" "$p".* 2>/dev/null || true
    done < "$registry"
    rm -f -- "$registry" 2>/dev/null || true
}

# Supprime les dossiers de travail vides de ce run (créés même en fin normale).
_cleanup_run_empty_workdirs() {
    local registry="${TMP_DIR:-/tmp/video_convert}/.run_tmp_${EXECUTION_TIMESTAMP:-0}_$$"
    [[ -f "$registry" ]] || return 0
    local p
    while IFS= read -r p; do
        [[ "$p" == "${TMP_DIR:-/tmp/video_convert}/work_"* && -d "$p" ]] && rmdir -- "$p" 2>/dev/null
    done < "$registry"
    rm -f -- "$registry" 2>/dev/null || true
    return 0
}

###########################################################
# NETTOYAGE À LA SORTIE
###########################################################

cleanup() {
    local exit_code=$?

    # Désarmer INT/TERM pendant le cleanup. Le `kill -- -$$` plus bas signale
    # TOUT le process group, y compris ce shell (leader). Tant que _handle_interrupt
    # restait armé sur TERM, ce SIGTERM auto-infligé ré-entrait dans le handler →
    # `exit 130`, écrasant le vrai code de sortie (ex. 0 sur `--help`, d'où le
    # exit 130 observé sur une fin normale). En ignorant le signal ici, le shell
    # survit au kill du groupe, termine le cleanup et sort avec exit_code réel.
    # Le cas Ctrl+C garde son 130 : _handle_interrupt l'a déjà posé AVANT ce trap.
    trap '' INT TERM

    # Afficher le message d'interruption seulement si terminaison par signal (INT/TERM)
    # et pas déjà signalé par STOP_FLAG
    # Note: On utilise une variable pour détecter les signaux plutôt que le code de sortie
    if [[ "${_INTERRUPTED:-}" == "1" ]] && [[ ! -f "$STOP_FLAG" ]]; then
        echo ""
        print_warning "$(msg MSG_LOCK_INTERRUPT)"
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

    # Relever NOS encodeurs (descendants) AVANT de tuer leurs parents : une fois
    # orphelins, ils ne seraient plus identifiables comme les nôtres.
    local -a enc_pids=()
    mapfile -t enc_pids < <(_cleanup_descendant_encoders "$$" 2>/dev/null || true)

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

    # `wait` n'attend que les enfants directs : un ffmpeg petit-enfant qui ignore
    # SIGTERM survivrait, orphelin. Période de grâce puis SIGKILL.
    _cleanup_kill_survivors 10 "${enc_pids[@]+"${enc_pids[@]}"}"

    # Petit délai pour laisser les processus finir d'écrire
    sleep 0.2

    if [[ "${_INTERRUPTED:-}" == "1" ]]; then
        _cleanup_run_temp_files
    else
        _cleanup_run_empty_workdirs
    fi

    rm -f "$LOCKFILE"
    rm -f "${LOCKFILE}.flock" 2>/dev/null || true
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
    # Le test "lock existant ?" puis l'écriture du PID forment une fenêtre TOCTOU :
    # deux instances lancées simultanément pouvaient la franchir toutes les deux.
    # On SÉRIALISE cette section critique sous un flock (sur un fichier annexe),
    # de sorte qu'une seule instance à la fois lise/écrive le lock. La DÉCISION
    # reste basée sur le PID (liveness via ps) — compat sémantique et messages.
    # flock est requis par `make doctor` ; à défaut on retombe sur l'ancien
    # comportement non atomique (best-effort).
    local _have_flock=false
    if command -v flock >/dev/null 2>&1; then
        # NB: le 2>/dev/null doit porter sur le groupe, PAS sur le `exec`.
        # `exec 9>f 2>/dev/null` appliquerait la redirection de stderr au
        # SHELL COURANT de façon permanente : plus aucune sortie stderr pour
        # tout le reste du run (barres de progression comprises).
        if { exec 9>"${LOCKFILE}.flock"; } 2>/dev/null; then
            flock 9 2>/dev/null && _have_flock=true
        fi
    fi

    # --- Section critique (atomique entre instances grâce au flock ci-dessus) ---
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null)

        if ps -p "$pid" > /dev/null 2>&1; then
            print_error "$(msg MSG_LOCK_ALREADY_RUNNING "$pid")"
            exit 1
        else
            print_warning "$(msg MSG_LOCK_STALE)"
            rm -f "$LOCKFILE"
        fi
    fi

    echo $$ > "$LOCKFILE"

    # Relâcher le verrou de sérialisation : la protection "déjà en cours" est
    # ensuite assurée par la présence du PID (vérifié ci-dessus), pas par flock.
    # (Sinon une 2e instance bloquerait au lieu de sortir avec "déjà en cours".)
    if [[ "$_have_flock" == true ]]; then
        flock -u 9 2>/dev/null || true
        { exec 9>&-; } 2>/dev/null || true
    fi
}

###########################################################
# CONFIGURATION DES TRAPS
###########################################################

setup_traps() {
    trap cleanup EXIT
    trap _handle_interrupt INT TERM
}
