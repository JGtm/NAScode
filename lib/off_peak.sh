#!/bin/bash
###########################################################
# GESTION DES HEURES CREUSES
# Module pour restreindre le traitement aux périodes off-peak
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les calculs de temps utilisent des valeurs par défaut
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

###########################################################
# VARIABLES DE CONFIGURATION (par défaut)
###########################################################

# Activation du mode heures creuses
OFF_PEAK_ENABLED=false

# Plage horaire par défaut : 22h00 - 06h00 (format HH:MM)
OFF_PEAK_START="22:00"
OFF_PEAK_END="06:00"

# Intervalle de vérification en secondes (pendant l'attente)
OFF_PEAK_CHECK_INTERVAL=60

# Compteur d'attente heures creuses (pour le résumé)
OFF_PEAK_WAIT_COUNT=0
OFF_PEAK_TOTAL_WAIT_SECONDS=0

###########################################################
# PARSING DE LA PLAGE HORAIRE
###########################################################

# Parse une plage horaire au format HH:MM-HH:MM
# Retourne 0 si valide, 1 sinon
# Usage: parse_off_peak_range "22:00-06:00"
parse_off_peak_range() {
    local range="$1"
    
    # Format attendu : HH:MM-HH:MM
    if [[ ! "$range" =~ ^([0-9]{1,2}):([0-9]{2})-([0-9]{1,2}):([0-9]{2})$ ]]; then
        return 1
    fi
    
    local start_hour="${BASH_REMATCH[1]}"
    local start_min="${BASH_REMATCH[2]}"
    local end_hour="${BASH_REMATCH[3]}"
    local end_min="${BASH_REMATCH[4]}"
    
    # Forcer interprétation décimale (éviter erreur octale avec 08, 09)
    start_hour=$((10#$start_hour))
    start_min=$((10#$start_min))
    end_hour=$((10#$end_hour))
    end_min=$((10#$end_min))
    
    # Validation des valeurs
    if [[ "$start_hour" -gt 23 ]] || [[ "$start_min" -gt 59 ]] || \
       [[ "$end_hour" -gt 23 ]] || [[ "$end_min" -gt 59 ]]; then
        return 1
    fi
    
    # Formater avec zéros initiaux
    OFF_PEAK_START=$(printf "%02d:%02d" "$start_hour" "$start_min")
    OFF_PEAK_END=$(printf "%02d:%02d" "$end_hour" "$end_min")
    
    return 0
}

###########################################################
# VÉRIFICATION DE L'HEURE ACTUELLE
###########################################################

# Convertit HH:MM en minutes depuis minuit
# Usage: time_to_minutes "22:30" => 1350
time_to_minutes() {
    local time="$1"
    local hours="${time%:*}"
    local minutes="${time#*:}"
    # Supprimer les zéros initiaux pour éviter interprétation octale
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    echo $(( hours * 60 + minutes ))
}

# Vérifie si l'heure actuelle est dans la plage heures creuses
# Retourne 0 si on est en heures creuses, 1 sinon
# Gère les plages qui traversent minuit (ex: 22:00-06:00)
is_off_peak_time() {
    local current_time
    current_time=$(date +%H:%M)
    
    local current_mins start_mins end_mins
    current_mins=$(time_to_minutes "$current_time")
    start_mins=$(time_to_minutes "$OFF_PEAK_START")
    end_mins=$(time_to_minutes "$OFF_PEAK_END")
    
    # Cas 1: Plage normale (ex: 08:00-18:00)
    # Cas 2: Plage traversant minuit (ex: 22:00-06:00)
    if [[ "$start_mins" -le "$end_mins" ]]; then
        # Plage normale : start <= current < end
        if [[ "$current_mins" -ge "$start_mins" ]] && [[ "$current_mins" -lt "$end_mins" ]]; then
            return 0
        fi
    else
        # Plage traversant minuit : current >= start OU current < end
        if [[ "$current_mins" -ge "$start_mins" ]] || [[ "$current_mins" -lt "$end_mins" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Calcule le temps restant jusqu'au début des heures creuses (en secondes)
# Utilisé pour afficher le temps d'attente estimé
seconds_until_off_peak() {
    local current_time
    current_time=$(date +%H:%M)
    
    local current_mins start_mins
    current_mins=$(time_to_minutes "$current_time")
    start_mins=$(time_to_minutes "$OFF_PEAK_START")
    
    local wait_mins
    if [[ "$current_mins" -lt "$start_mins" ]]; then
        # Heures creuses plus tard aujourd'hui
        wait_mins=$(( start_mins - current_mins ))
    else
        # Heures creuses demain
        wait_mins=$(( (1440 - current_mins) + start_mins ))
    fi
    
    echo $(( wait_mins * 60 ))
}

# Formate une durée en secondes en format lisible
# Usage: format_wait_time 3661 => "1h 1min 1s"
format_wait_time() {
    local seconds="$1"
    local hours=$(( seconds / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$(( seconds % 60 ))
    
    local result=""
    [[ "$hours" -gt 0 ]] && result="${hours}h "
    [[ "$minutes" -gt 0 ]] && result="${result}${minutes}min "
    [[ "$secs" -gt 0 || -z "$result" ]] && result="${result}${secs}s"
    
    echo "${result% }"
}

###########################################################
# ATTENTE DES HEURES CREUSES
###########################################################

# Attend jusqu'à ce que les heures creuses commencent
# Affiche le temps d'attente et vérifie périodiquement
# Retourne 0 quand les heures creuses commencent, 1 si interruption
wait_for_off_peak() {
    # Si mode heures creuses désactivé, pas d'attente
    if [[ "$OFF_PEAK_ENABLED" != true ]]; then
        return 0
    fi
    
    # Si déjà en heures creuses, pas d'attente
    if is_off_peak_time; then
        return 0
    fi
    
    local wait_start
    wait_start=$(date +%s)
    
    local wait_seconds
    wait_seconds=$(seconds_until_off_peak)
    local wait_formatted
    wait_formatted=$(format_wait_time "$wait_seconds")
    
    print_info "⏸️  Heures pleines détectées (${OFF_PEAK_START}-${OFF_PEAK_END} = heures creuses)"
    print_info "Attente estimée : ${wait_formatted} (reprise à ${OFF_PEAK_START})"
    print_info "Vérification toutes les ${OFF_PEAK_CHECK_INTERVAL}s... (Ctrl+C pour annuler)"

    # Notification externe (Discord) — best-effort
    if declare -f notify_event_peak_pause &>/dev/null; then
        notify_event_peak_pause "${OFF_PEAK_START}-${OFF_PEAK_END}" "${wait_formatted}" "${OFF_PEAK_START}" "${OFF_PEAK_CHECK_INTERVAL}" || true
    fi
    
    # Compteur pour l'affichage périodique
    local check_count=0
    
    while ! is_off_peak_time; do
        # Vérifier si le script a été interrompu
        if [[ -f "$STOP_FLAG" ]]; then
            print_warning "$(msg MSG_OFF_PEAK_STOP)"
            return 1
        fi
        
        # Affichage périodique (toutes les 5 vérifications = ~5 minutes)
        check_count=$((check_count + 1))
        if [[ $((check_count % 5)) -eq 0 ]]; then
            local remaining
            remaining=$(seconds_until_off_peak)
            local remaining_fmt
            remaining_fmt=$(format_wait_time "$remaining")
            print_info "⏳ Temps restant estimé : ${remaining_fmt}"
        fi
        
        sleep "$OFF_PEAK_CHECK_INTERVAL"
    done
    
    local wait_end
    wait_end=$(date +%s)
    local actual_wait=$(( wait_end - wait_start ))
    
    # Mettre à jour les compteurs
    OFF_PEAK_WAIT_COUNT=$((OFF_PEAK_WAIT_COUNT + 1))
    OFF_PEAK_TOTAL_WAIT_SECONDS=$((OFF_PEAK_TOTAL_WAIT_SECONDS + actual_wait))
    
    local actual_wait_fmt
    actual_wait_fmt=$(format_wait_time "$actual_wait")
    print_info "▶️  Heures creuses ! Reprise du traitement (attendu ${actual_wait_fmt})"

    # Notification externe (Discord) — best-effort
    if declare -f notify_event_peak_resume &>/dev/null; then
        notify_event_peak_resume "${OFF_PEAK_START}-${OFF_PEAK_END}" "${actual_wait_fmt}" || true
    fi
    
    return 0
}

###########################################################
# VÉRIFICATION AVANT TRAITEMENT
###########################################################

# Fonction à appeler avant de démarrer une conversion
# Si on n'est pas en heures creuses, attend
# Retourne 0 pour continuer, 1 pour arrêter
check_off_peak_before_processing() {
    if [[ "$OFF_PEAK_ENABLED" != true ]]; then
        return 0
    fi
    
    wait_for_off_peak
    return $?
}

###########################################################
# AFFICHAGE STATUT
###########################################################

# Affiche le statut actuel des heures creuses (pour le résumé)
show_off_peak_status() {
    if [[ "$OFF_PEAK_ENABLED" != true ]]; then
        return
    fi

    if declare -f ui_print_raw &>/dev/null; then
        ui_print_raw "${CYAN}Mode heures creuses :${NOCOLOR}"
        ui_print_raw "  Plage horaire    : ${OFF_PEAK_START} - ${OFF_PEAK_END}"
    else
        echo -e "${CYAN}Mode heures creuses :${NOCOLOR}"
        echo -e "  Plage horaire    : ${OFF_PEAK_START} - ${OFF_PEAK_END}"
    fi
    
    if is_off_peak_time; then
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "  Statut actuel    : ${GREEN}Heures creuses (actif)${NOCOLOR}"
        else
            echo -e "  Statut actuel    : ${GREEN}Heures creuses (actif)${NOCOLOR}"
        fi
    else
        local wait_est
        wait_est=$(seconds_until_off_peak)
        local wait_fmt
        wait_fmt=$(format_wait_time "$wait_est")
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "  Statut actuel    : ${YELLOW}Heures pleines (attente ~${wait_fmt})${NOCOLOR}"
        else
            echo -e "  Statut actuel    : ${YELLOW}Heures pleines (attente ~${wait_fmt})${NOCOLOR}"
        fi
    fi
    
    if [[ "$OFF_PEAK_WAIT_COUNT" -gt 0 ]]; then
        local total_wait_fmt
        total_wait_fmt=$(format_wait_time "$OFF_PEAK_TOTAL_WAIT_SECONDS")
        local wait_label
        wait_label="$(msg MSG_OFF_PEAK_WAIT_PERIODS) : ${OFF_PEAK_WAIT_COUNT} ($(msg MSG_OFF_PEAK_TOTAL) : ${total_wait_fmt})"
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "  ${wait_label}"
        else
            echo -e "  ${wait_label}"
        fi
    fi
}

# Affiche un message au démarrage si le mode est activé
show_off_peak_startup_info() {
    if [[ "$OFF_PEAK_ENABLED" != true ]]; then
        return
    fi

    if declare -f ui_print_raw &>/dev/null; then
        ui_print_raw ""
        ui_print_raw "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        ui_print_raw "${CYAN}⏰ $(msg MSG_OFF_PEAK_MODE_TITLE)${NOCOLOR}"
        ui_print_raw "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        ui_print_raw "  Plage horaire : ${GREEN}${OFF_PEAK_START}${NOCOLOR} - ${GREEN}${OFF_PEAK_END}${NOCOLOR}"
    else
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        echo -e "${CYAN}⏰ $(msg MSG_OFF_PEAK_MODE_TITLE)${NOCOLOR}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        echo -e "  Plage horaire : ${GREEN}${OFF_PEAK_START}${NOCOLOR} - ${GREEN}${OFF_PEAK_END}${NOCOLOR}"
    fi
    
    if is_off_peak_time; then
        local status_label
        status_label="$(msg MSG_OFF_PEAK_STATUS)        : ${GREEN}✓ $(msg MSG_OFF_PEAK_IMMEDIATE)${NOCOLOR}"
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "  ${status_label}"
        else
            echo -e "  ${status_label}"
        fi
    else
        local wait_est
        wait_est=$(seconds_until_off_peak)
        local wait_fmt
        wait_fmt=$(format_wait_time "$wait_est")
        if declare -f ui_print_raw &>/dev/null; then
            ui_print_raw "  Statut        : ${YELLOW}⏳ Heures pleines - attente ~${wait_fmt}${NOCOLOR}"
        else
            echo -e "  Statut        : ${YELLOW}⏳ Heures pleines - attente ~${wait_fmt}${NOCOLOR}"
        fi
    fi

    if declare -f ui_print_raw &>/dev/null; then
        ui_print_raw "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        ui_print_raw ""
    else
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NOCOLOR}"
        echo ""
    fi
}
