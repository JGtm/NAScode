#!/bin/bash
###########################################################
# NOTIFY — ÉVÉNEMENTS (routage + envoi)
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les notifications sont best-effort
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

notify_event() {
    local event="${1-}"
    shift || true

    case "$event" in
        run_started)
            notify_event_run_started "$@"
            ;;
        file_started)
            notify_event_file_started "$@"
            ;;
        file_progress_update)
            notify_event_file_progress_update "$@"
            ;;
        file_completed)
            notify_event_file_completed "$@"
            ;;
        file_skipped)
            notify_event_file_skipped "$@"
            ;;
        conversions_completed)
            notify_event_conversions_completed "$@"
            ;;
        transfers_pending)
            notify_event_transfers_pending "$@"
            ;;
        transfers_done)
            notify_event_transfers_done "$@"
            ;;
        vmaf_started)
            notify_event_vmaf_started "$@"
            ;;
        vmaf_file_started)
            notify_event_vmaf_file_started "$@"
            ;;
        vmaf_file_completed)
            notify_event_vmaf_file_completed "$@"
            ;;
        vmaf_completed)
            notify_event_vmaf_completed "$@"
            ;;
        peak_pause)
            notify_event_peak_pause "$@"
            ;;
        peak_resume)
            notify_event_peak_resume "$@"
            ;;
        script_exit)
            notify_event_script_exit "$@"
            ;;
        *)
            return 0
            ;;
    esac
}

notify_event_file_skipped() {
    # Usage: notify_event_file_skipped <filename> [reason]
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_file_skipped "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "file_skipped"
    return 0
}

notify_event_run_started() {
    # Envoi unique
    [[ "${NASCODE_NOTIFY_RUN_STARTED_SENT:-0}" == "1" ]] && return 0
    NASCODE_NOTIFY_RUN_STARTED_SENT=1

    _notify_discord_is_enabled || return 0

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    local body
    body=$(_notify_format_event_run_started "$now")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "run_started"
    return 0
}

notify_event_file_started() {
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_file_started "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "file_started"
    return 0
}

notify_event_file_progress_update() {
    # Usage: notify_event_file_progress_update <filename> <speed> <eta>
    # Envoyé quelques secondes après le début de la conversion, quand FFmpeg a stabilisé sa vitesse
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_file_progress_update "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "file_progress_update"
    return 0
}

notify_event_file_completed() {
    # Usage: notify_event_file_completed <elapsed> <before> <after>
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_file_completed "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "file_completed"
    return 0
}

notify_event_conversions_completed() {
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_conversions_completed "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "conversions_completed"
    return 0
}

notify_event_transfers_pending() {
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_transfers_pending "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "transfers_pending"
    return 0
}

notify_event_transfers_done() {
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_transfers_done)
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "transfers_done"
    return 0
}

notify_event_vmaf_started() {
    # Usage: notify_event_vmaf_started <count> [mode]
    _notify_discord_is_enabled || return 0

    local count="${1-0}"
    local mode="${2-}"

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    local body
    body=$(_notify_format_event_vmaf_started "$now" "$count" "$mode")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "vmaf_started"
    return 0
}

notify_event_vmaf_file_started() {
    # Usage: notify_event_vmaf_file_started <current> <total> <filename>
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_vmaf_file_started "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "vmaf_file_started"
    return 0
}

notify_event_vmaf_file_completed() {
    # Usage: notify_event_vmaf_file_completed <current> <total> <filename> <score> <quality>
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_vmaf_file_completed "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "vmaf_file_completed"
    return 0
}

notify_event_vmaf_completed() {
    # Usage: notify_event_vmaf_completed <count> <ok> <na> <avg> <min> <max> <degraded> <duration>
    # + optionnel: lignes "worst" (déjà formatées)
    _notify_discord_is_enabled || return 0

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    local body
    body=$(_notify_format_event_vmaf_completed "$now" "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "vmaf_completed"
    return 0
}

notify_event_peak_pause() {
    # Usage: notify_event_peak_pause "22:00-06:00" "1h 20min" "22:00" "60"
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_peak_pause "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "peak_pause"
    return 0
}

notify_event_peak_resume() {
    # Usage: notify_event_peak_resume "22:00-06:00" "1h 18min"
    _notify_discord_is_enabled || return 0

    local body
    body=$(_notify_format_event_peak_resume "$@")
    [[ -n "$body" ]] && notify_discord_send_markdown "$body" "peak_resume"
    return 0
}

notify_event_script_exit() {
    # Appelé depuis cleanup() avec le code de sortie.
    [[ "${NASCODE_NOTIFY_RUN_FINISHED_SENT:-0}" == "1" ]] && return 0
    NASCODE_NOTIFY_RUN_FINISHED_SENT=1

    _notify_discord_is_enabled || return 0

    local exit_code="${1-0}"

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    # 1) Résumé
    local summary_body=""
    summary_body=$(_notify_format_event_script_exit_summary "$now" "$exit_code" || true)
    [[ -n "$summary_body" ]] && notify_discord_send_markdown "$summary_body" "summary"

    # 2) Message final (inclut le code de sortie pour distinguer interruption/erreur)
    local end_body
    end_body=$(_notify_format_event_script_exit_end "$now" "$exit_code")
    [[ -n "$end_body" ]] && notify_discord_send_markdown "$end_body" "script_exit"
    return 0
}
