#!/bin/bash
###########################################################
# SYSTÈME DE SLOTS POUR PROGRESSION PARALLÈLE
# Gestion de l'affichage multi-workers
###########################################################

# Répertoire pour les fichiers de verrouillage des slots
readonly SLOTS_DIR="/tmp/video_convert_slots_${EXECUTION_TIMESTAMP}"

# Acquérir un slot libre pour affichage de progression
# Usage: acquire_progress_slot
# Retourne le numero de slot (1 à PARALLEL_JOBS) sur stdout
acquire_progress_slot() {
    mkdir -p "$SLOTS_DIR" 2>/dev/null || true
    local max_slots=${PARALLEL_JOBS:-1}
    local slot=1
    while [[ $slot -le $max_slots ]]; do
        local slot_file="$SLOTS_DIR/slot_$slot"
        if mkdir "$slot_file" 2>/dev/null; then
            echo "$$" > "$slot_file/pid"
            echo "$slot"
            return 0
        fi
        ((slot++))
    done
    # Aucun slot libre, retourner 0 (mode dégradé)
    echo "0"
}

# Libérer un slot de progression
# Usage: release_progress_slot <slot_number>
release_progress_slot() {
    local slot="$1"
    if [[ -n "$slot" && "$slot" -gt 0 ]]; then
        rm -rf "$SLOTS_DIR/slot_$slot" 2>/dev/null || true
    fi
}

# Nettoyer tous les slots (appelé en fin de script)
cleanup_progress_slots() {
    rm -rf "$SLOTS_DIR" 2>/dev/null || true
}

# Préparer espace affichage pour les workers parallèles
# Usage: setup_progress_display
setup_progress_display() {
    local max_slots=${PARALLEL_JOBS:-1}
    if [[ "$max_slots" -gt 1 && "$NO_PROGRESS" != true ]]; then
        # Réserver des lignes vides pour chaque slot
        for ((i=1; i<=max_slots; i++)); do
            echo ""
        done
        # Ligne séparatrice
        echo -e "${CYAN}─────────────────────────────────────────────────────────────────────────${NOCOLOR}"
    fi
}
