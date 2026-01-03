#!/bin/bash
###########################################################
# TRAITEMENT DE LA FILE D'ATTENTE
# Gestion du traitement parallèle et FIFO
###########################################################

###########################################################
# TRAITEMENT SIMPLE (SANS FIFO)
###########################################################

# Traitement simple sans FIFO (quand pas de limite)
_process_queue_simple() {
    local nb_files=0
    if [[ -f "$QUEUE" ]]; then
        nb_files=$(count_null_separated "$QUEUE")
    fi
    
    # Initialiser le compteur de fichiers pour l'affichage "X/Y"
    STARTING_FILE_COUNTER_FILE="$LOG_DIR/starting_file_counter_${EXECUTION_TIMESTAMP}"
    echo "0" > "$STARTING_FILE_COUNTER_FILE"
    export STARTING_FILE_COUNTER_FILE
    
    TOTAL_FILES_TO_PROCESS="$nb_files"
    export TOTAL_FILES_TO_PROCESS
    
    if [[ "$NO_PROGRESS" != true ]]; then
        print_conversion_start "$nb_files"
        # Réserver espace affichage pour les workers parallèles
        setup_progress_display
    fi
    
    # Lire la queue et traiter en parallèle
    local file
    local -a _pids=()
    while IFS= read -r -d '' file; do
        # Vérifier les heures creuses avant de lancer une nouvelle conversion
        if ! check_off_peak_before_processing; then
            echo -e "${YELLOW}⚠️  Traitement interrompu (arrêt demandé pendant l'attente)${NOCOLOR}"
            break
        fi
        
        convert_file "$file" "$OUTPUT_DIR" &
        _pids+=("$!")
        if [[ "${#_pids[@]}" -ge "$PARALLEL_JOBS" ]]; then
            if ! wait -n 2>/dev/null; then
                wait "${_pids[0]}" 2>/dev/null || true
            fi
            local -a _still=()
            for p in "${_pids[@]}"; do
                if kill -0 "$p" 2>/dev/null; then
                    _still+=("$p")
                fi
            done
            _pids=("${_still[@]}")
        fi
    done < "$QUEUE"
    
    # Attendre tous les jobs restants
    for p in "${_pids[@]}"; do
        wait "$p" || true
    done
    
    wait 2>/dev/null || true
    sleep 1
    
    if [[ "$NO_PROGRESS" != true ]] && [[ "$nb_files" -gt 0 ]]; then
        print_conversion_complete
    fi
}

###########################################################
# TRAITEMENT AVEC FIFO (MODE LIMITE)
###########################################################

# Traitement avec FIFO (quand limite active - permet le remplacement dynamique)
_process_queue_with_fifo() {
    WORKFIFO="$LOG_DIR/queue_fifo_${EXECUTION_TIMESTAMP}"
    FIFO_WRITER_PID="$LOG_DIR/fifo_writer_pid_${EXECUTION_TIMESTAMP}"
    FIFO_WRITER_READY="$LOG_DIR/fifo_writer.ready_${EXECUTION_TIMESTAMP}"
    
    # Fichier compteur : nombre de fichiers traités (succès + erreur + skip)
    PROCESSED_COUNT_FILE="$LOG_DIR/processed_count_${EXECUTION_TIMESTAMP}"
    echo "0" > "$PROCESSED_COUNT_FILE"
    export PROCESSED_COUNT_FILE
    
    # Compteur pour l'affichage "X/Y" (incrémenté au début du traitement)
    STARTING_FILE_COUNTER_FILE="$LOG_DIR/starting_file_counter_${EXECUTION_TIMESTAMP}"
    echo "0" > "$STARTING_FILE_COUNTER_FILE"
    export STARTING_FILE_COUNTER_FILE

    # Compteur de fichiers réellement convertis (pas les skips) pour UX mode limite
    CONVERTED_COUNT_FILE="$LOG_DIR/converted_count_${EXECUTION_TIMESTAMP}"
    echo "0" > "$CONVERTED_COUNT_FILE"
    export CONVERTED_COUNT_FILE

    # Queue complète et position pour alimentation dynamique
    QUEUE_FULL="$QUEUE.full"
    NEXT_QUEUE_POS_FILE="$LOG_DIR/next_queue_pos_${EXECUTION_TIMESTAMP}"
    TOTAL_QUEUE_FILE="$LOG_DIR/total_queue_${EXECUTION_TIMESTAMP}"

    # Calculer le total de la queue complète
    local total_full=0
    if [[ -f "$QUEUE_FULL" ]]; then
        total_full=$(count_null_separated "$QUEUE_FULL")
    fi
    echo "$total_full" > "$TOTAL_QUEUE_FILE"
    
    # Nombre de fichiers à traiter (queue limitée)
    local target_count=0
    if [[ -f "$QUEUE" ]]; then
        target_count=$(count_null_separated "$QUEUE")
    fi
    # Position initiale = nombre de fichiers déjà dans la queue limitée
    echo "$target_count" > "$NEXT_QUEUE_POS_FILE"
    
    # Total de fichiers pour l'affichage "X/Y"
    TOTAL_FILES_TO_PROCESS="$target_count"
    export TOTAL_FILES_TO_PROCESS
    
    # Fichier cible pour le writer
    TARGET_COUNT_FILE="$LOG_DIR/target_count_${EXECUTION_TIMESTAMP}"
    echo "$target_count" > "$TARGET_COUNT_FILE"
    export TARGET_COUNT_FILE QUEUE_FULL NEXT_QUEUE_POS_FILE TOTAL_QUEUE_FILE WORKFIFO

    # Créer le FIFO et lancer un writer de fond
    rm -f "$WORKFIFO" 2>/dev/null || true
    mkfifo "$WORKFIFO"
    
    # Writer : écrit la queue initiale puis attend que tous les fichiers soient traités
    (
        exec 3<> "$WORKFIFO"
        # Écrire le contenu initial (NUL séparés)
        if [[ -f "$QUEUE" ]]; then
            cat "$QUEUE" >&3
        fi
        # Signaler prêt
        touch "$FIFO_WRITER_READY" 2>/dev/null || true
        
        # Fichier de fin normale (différent de STOP_FLAG qui indique une interruption)
        local fifo_done="${FIFO_WRITER_PID}.done"
        
        # Attendre que le nombre de fichiers traités atteigne la cible
        # ou qu'un signal de fin (normale ou interruption) soit reçu
        while [[ ! -f "$STOP_FLAG" ]] && [[ ! -f "$fifo_done" ]]; do
            local processed=0
            if [[ -f "$PROCESSED_COUNT_FILE" ]]; then
                processed=$(cat "$PROCESSED_COUNT_FILE" 2>/dev/null || echo 0)
            fi
            local target=$target_count
            if [[ -f "$TARGET_COUNT_FILE" ]]; then
                target=$(cat "$TARGET_COUNT_FILE" 2>/dev/null || echo "$target_count")
            fi
            
            if [[ "$processed" -ge "$target" ]]; then
                break
            fi
            sleep 0.5
        done
        exec 3>&-
    ) &
    printf "%d" "$!" > "$FIFO_WRITER_PID" 2>/dev/null || true
    
    # Traitement des fichiers
    local nb_files=$target_count
    if [[ "$NO_PROGRESS" != true ]]; then
        print_conversion_start "$nb_files"
        # Réserver espace affichage pour les workers parallèles
        setup_progress_display
    fi
    
    # Consumer : lire les noms de fichiers séparés par NUL et lancer les conversions en parallèle
    _consumer_run() {
        local file
        local -a _pids=()
        while IFS= read -r -d '' file; do
            # Vérifier les heures creuses avant de lancer une nouvelle conversion
            if ! check_off_peak_before_processing; then
                echo -e "${YELLOW}⚠️  Traitement interrompu (arrêt demandé pendant l'attente)${NOCOLOR}"
                break
            fi
            
            convert_file "$file" "$OUTPUT_DIR" &
            _pids+=("$!")
            if [[ "${#_pids[@]}" -ge "$PARALLEL_JOBS" ]]; then
                if ! wait -n 2>/dev/null; then
                    wait "${_pids[0]}" 2>/dev/null || true
                fi
                local -a _still=()
                for p in "${_pids[@]}"; do
                    if kill -0 "$p" 2>/dev/null; then
                        _still+=("$p")
                    fi
                done
                _pids=("${_still[@]}")
            fi
        done < "$WORKFIFO"
        for p in "${_pids[@]}"; do
            wait "$p" || true
        done
    }
    _consumer_run &
    local consumer_pid=$!

    # Attendre que le consumer termine
    wait "$consumer_pid" 2>/dev/null || true
    
    # Signaler au writer FIFO qu'il doit se terminer (fin normale, pas interruption)
    # On utilise FIFO_DONE pour différencier de STOP_FLAG qui indique une vraie interruption
    local fifo_done="${FIFO_WRITER_PID}.done"
    touch "$fifo_done" 2>/dev/null || true
    
    # Si un writer a enregistré son PID, demander son arrêt proprement
    if [[ -n "${FIFO_WRITER_PID:-}" ]] && [[ -f "${FIFO_WRITER_PID}" ]]; then
        local _writer_pid
        _writer_pid=$(cat "$FIFO_WRITER_PID" 2>/dev/null || echo "")
        if [[ -n "$_writer_pid" ]] && [[ "$_writer_pid" != "" ]]; then
            kill "$_writer_pid" 2>/dev/null || true
            wait "$_writer_pid" 2>/dev/null || true
        fi
    fi

    # Message UX si la limite n'a pas été atteinte (tous les fichiers restants étaient déjà optimisés)
    if [[ "$NO_PROGRESS" != true ]] && [[ ! -f "$STOP_FLAG" ]]; then
        local converted_count=0
        if [[ -f "$CONVERTED_COUNT_FILE" ]]; then
            converted_count=$(cat "$CONVERTED_COUNT_FILE" 2>/dev/null || echo 0)
        fi
        if [[ "$converted_count" -lt "$LIMIT_FILES" ]]; then
            print_warning_box "Fin des tâches" "Tous les fichiers restants sont déjà optimisés."
        fi
    fi

    # Nettoyer les artefacts FIFO
    rm -f "$WORKFIFO" "$FIFO_WRITER_PID" "$FIFO_WRITER_READY" "$fifo_done" 2>/dev/null || true
    rm -f "$PROCESSED_COUNT_FILE" "$TARGET_COUNT_FILE" "$CONVERTED_COUNT_FILE" 2>/dev/null || true
    rm -f "$NEXT_QUEUE_POS_FILE" "$TOTAL_QUEUE_FILE" 2>/dev/null || true
    
    # Tentative de terminaison des processus enfants éventuels restants
    _reap_children() {
        local children=""
        if command -v pgrep >/dev/null 2>&1; then
            children=$(pgrep -P $$ 2>/dev/null || true)
        elif ps -o pid=,ppid= >/dev/null 2>&1; then
            children=$(ps -o pid=,ppid= | awk -v p=$$ '$2==p {print $1}' || true)
        fi
        for c in $children; do
            if [[ -n "$c" ]] && [[ "$c" != "$$" ]]; then
                kill "$c" 2>/dev/null || true
                wait "$c" 2>/dev/null || true
            fi
        done
    }
    _reap_children 2>/dev/null || true

    wait 2>/dev/null || true
    sleep 1
    
    if [[ "$NO_PROGRESS" != true ]] && [[ "$nb_files" -gt 0 ]]; then
        print_conversion_complete
    fi
}

###########################################################
# POINT D'ENTRÉE DU TRAITEMENT
###########################################################

# Point d'entrée : choisit le mode de traitement selon la présence d'une limite
prepare_dynamic_queue() {
    if [[ "$LIMIT_FILES" -gt 0 ]]; then
        # Mode FIFO : permet le remplacement dynamique des fichiers skippés
        _process_queue_with_fifo
    else
        # Mode simple : traitement direct sans overhead FIFO
        _process_queue_simple
    fi
}
