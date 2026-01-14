#!/bin/bash
# shellcheck disable=SC2034
###########################################################
# GESTION DES LOGS
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les opérations de log sont best-effort (ne doivent pas
#    bloquer le script en cas d'échec d'écriture)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

###########################################################
# FONCTIONS DE LOG
###########################################################

# Log une erreur sur stderr avec formatage cohérent.
# Usage: log_error <message> [show_in_tty]
# Ex: log_error "Fichier introuvable"
log_error() {
    local message="$1"
    local show_in_tty="${2:-false}"
    
    echo -e "${RED:-}❌ ${message}${NOCOLOR:-}" >&2
    
    if [[ "$show_in_tty" == true && -n "${TTY_DEV:-}" ]]; then
        echo -e "${RED:-}❌ ${message}${NOCOLOR:-}" > "$TTY_DEV" 2>/dev/null || true
    fi
}

# Log un avertissement sur stderr avec formatage cohérent.
# Usage: log_warning <message>
log_warning() {
    local message="$1"
    echo -e "${YELLOW:-}⚠️  ${message}${NOCOLOR:-}" >&2
}

# Log une info sur stdout avec formatage cohérent.
# Usage: log_info <message>
log_info() {
    local message="$1"
    echo -e "${GREEN:-}ℹ️  ${message}${NOCOLOR:-}"
}

# Log un succès sur stdout avec formatage cohérent.
# Usage: log_success <message>
log_success() {
    local message="$1"
    echo -e "${GREEN:-}✅ ${message}${NOCOLOR:-}"
}

# Nettoie les logs de plus de X jours (défaut 30)
cleanup_old_logs() {
    local days="${1:-30}"
    if [[ -d "$LOG_DIR" ]]; then
        # Nettoyage silencieux des fichiers de plus de X jours
        # On exclut l'Index et Index.meta qui sont persistants
        find "$LOG_DIR" -type f -mtime +"$days" \
            ! -name "Index" ! -name "Index.meta" ! -name "Index_readable*" \
            -exec rm -f {} + 2>/dev/null || true
    fi
}

###########################################################
# CHEMINS DES LOGS
###########################################################

readonly LOG_DIR="${LOG_DIR:-"$SCRIPT_DIR/logs"}"
readonly LOG_SESSION="$LOG_DIR/Session_${EXECUTION_TIMESTAMP}.log"
readonly SUMMARY_FILE="$LOG_DIR/Summary_${EXECUTION_TIMESTAMP}.log"
readonly SUMMARY_METRICS_FILE="$LOG_DIR/SummaryMetrics_${EXECUTION_TIMESTAMP}.kv"
readonly LOG_PROGRESS="$LOG_DIR/Progress_${EXECUTION_TIMESTAMP}.log"
readonly INDEX="$LOG_DIR/Index"
readonly INDEX_META="$LOG_DIR/Index.meta"
readonly INDEX_READABLE="$LOG_DIR/Index_readable_${EXECUTION_TIMESTAMP}.txt"
readonly QUEUE="$LOG_DIR/Queue"
readonly LOG_DRYRUN_COMPARISON="$LOG_DIR/DryRun_Comparison_${EXECUTION_TIMESTAMP}.log"
readonly VMAF_QUEUE_FILE="$LOG_DIR/.vmaf_queue_${EXECUTION_TIMESTAMP}"

# Fichiers compteurs pour le suivi des gains de place (en octets)
readonly TOTAL_SIZE_BEFORE_FILE="$LOG_DIR/.total_size_before_${EXECUTION_TIMESTAMP}"
readonly TOTAL_SIZE_AFTER_FILE="$LOG_DIR/.total_size_after_${EXECUTION_TIMESTAMP}"

###########################################################
# INITIALISATION DES RÉPERTOIRES
###########################################################

initialize_directories() {
    mkdir -p "$LOG_DIR" "$TMP_DIR" "$OUTPUT_DIR"
    
    rm -f "$STOP_FLAG"
    
    # Nettoyage automatique des vieux logs (30 jours)
    cleanup_old_logs 30
    
    # Créer les fichiers de log
    for log_file in "$LOG_SESSION" "$SUMMARY_FILE" "$SUMMARY_METRICS_FILE" "$LOG_PROGRESS"; do
        touch "$log_file"
    done
    # Le log de comparaison dry-run n'est créé que si on est en mode dry-run
    if [[ "$DRYRUN" == true ]]; then
        touch "$LOG_DRYRUN_COMPARISON"
    fi
    
    # Initialiser les compteurs de taille (pour le gain de place)
    echo "0" > "$TOTAL_SIZE_BEFORE_FILE"
    echo "0" > "$TOTAL_SIZE_AFTER_FILE"
}
