#!/bin/bash
###########################################################
# GESTION DES LOGS
# Chemins des fichiers de log et initialisation des répertoires
###########################################################

###########################################################
# CHEMINS DES LOGS
###########################################################

readonly LOG_DIR="./logs"
readonly LOG_SUCCESS="$LOG_DIR/Success_${EXECUTION_TIMESTAMP}.log"
readonly LOG_SKIPPED="$LOG_DIR/Skipped_${EXECUTION_TIMESTAMP}.log"
readonly LOG_ERROR="$LOG_DIR/Error_${EXECUTION_TIMESTAMP}.log"
readonly SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
readonly LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
readonly INDEX="$LOG_DIR/Index"
readonly INDEX_READABLE="$LOG_DIR/Index_readable_${EXECUTION_TIMESTAMP}.txt"
readonly QUEUE="$LOG_DIR/Queue"
readonly LOG_DRYRUN_COMPARISON="$LOG_DIR/DryRun_Comparison_${EXECUTION_TIMESTAMP}.log"
readonly VMAF_QUEUE_FILE="$LOG_DIR/.vmaf_queue_${EXECUTION_TIMESTAMP}"

###########################################################
# INITIALISATION DES RÉPERTOIRES
###########################################################

initialize_directories() {
    mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR"
    
    rm -f "$STOP_FLAG"
    
    # Créer les fichiers de log
    for log_file in "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_ERROR" "$SUMMARY_FILE" "$LOG_PROGRESS"; do
        touch "$log_file"
    done
    # Le log de comparaison dry-run n'est créé que si on est en mode dry-run
    if [[ "$DRYRUN" == true ]]; then
        touch "$LOG_DRYRUN_COMPARISON"
    fi
}
