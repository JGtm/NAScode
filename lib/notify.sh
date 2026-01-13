#!/bin/bash
###########################################################
# NOTIFICATIONS (Discord)
# - Centralisé, modulaire, best-effort (ne doit jamais casser le script)
# - Secret: le webhook NE DOIT PAS être commité
#
# Configuration:
#   - NASCODE_DISCORD_WEBHOOK_URL : URL webhook Discord (secret)
#   - NASCODE_DISCORD_NOTIFY      : true/false (optionnel, défaut: activé si URL définie)
###########################################################

_notify_discord_is_enabled() {
    local url="${NASCODE_DISCORD_WEBHOOK_URL:-}"
    [[ -z "$url" ]] && return 1

    local enabled="${NASCODE_DISCORD_NOTIFY:-true}"
    [[ "$enabled" != "true" ]] && return 1

    command -v curl >/dev/null 2>&1 || return 1
    return 0
}

_notify_json_escape() {
    # Escape minimal JSON pour une string (suffisant pour content Discord)
    # - backslash, double quote, newlines, CR, tab
    local s="${1-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

_notify_strip_ansi() {
    # Retire les séquences ANSI (couleurs, etc.)
    # Remarque: GNU sed (Git Bash) supporte \x1B.
    sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'
}

notify_discord_send_markdown() {
    # Best-effort: ne jamais échouer (set -e safe)
    _notify_discord_is_enabled || return 0

    local content="${1-}"
    [[ -z "$content" ]] && return 0

    # Discord limite content à 2000 chars. On coupe à ~1900 pour marge.
    if [[ ${#content} -gt 1900 ]]; then
        content="${content:0:1900}\n..."
    fi

    local payload
    payload="{\"content\":\"$(_notify_json_escape "$content")\"}"

    # Ne jamais afficher le webhook (secret). Silencieux.
    curl -sS -m 10 --retry 2 --retry-delay 1 \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$payload" \
        "${NASCODE_DISCORD_WEBHOOK_URL}" \
        >/dev/null 2>&1 || true

    return 0
}

notify_event() {
    local event="${1-}"
    shift || true

    case "$event" in
        run_started)
            notify_event_run_started "$@"
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

notify_event_run_started() {
    # Envoi unique
    [[ "${NASCODE_NOTIFY_RUN_STARTED_SENT:-0}" == "1" ]] && return 0
    NASCODE_NOTIFY_RUN_STARTED_SENT=1

    _notify_discord_is_enabled || return 0

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    # Construire un mini-résumé stable (évite de dépendre du wording terminal)
    local -a lines
    lines=()

    [[ -n "${CONVERSION_MODE:-}" ]] && lines+=("mode=${CONVERSION_MODE}")
    [[ -n "${SOURCE:-}" ]] && lines+=("source=${SOURCE}")
    [[ -n "${OUTPUT_DIR:-}" ]] && lines+=("dest=${OUTPUT_DIR}")

    lines+=("video_codec=${VIDEO_CODEC:-hevc}")
    [[ -n "${AUDIO_CODEC:-}" ]] && lines+=("audio_codec=${AUDIO_CODEC}")

    [[ "${DRYRUN:-false}" == true ]] && lines+=("dry_run=true")
    [[ "${SAMPLE_MODE:-false}" == true ]] && lines+=("sample_mode=true")
    [[ "${VMAF_ENABLED:-false}" == true ]] && lines+=("vmaf=true")

    [[ "${OFF_PEAK_ENABLED:-false}" == true ]] && lines+=("off_peak=${OFF_PEAK_START:-22:00}-${OFF_PEAK_END:-06:00}")
    [[ -n "${PARALLEL_JOBS:-}" ]] && lines+=("parallel_jobs=${PARALLEL_JOBS}")

    local body="NAScode — démarrage"
    [[ -n "$now" ]] && body+="\n\n**Date**: ${now}"

    body+="\n\n**Paramètres actifs**\n\n\`\`\`text\n"
    local line
    for line in "${lines[@]}"; do
        body+="${line}\n"
    done
    body+="\`\`\`"

    notify_discord_send_markdown "$body"
    return 0
}

notify_event_peak_pause() {
    # Usage: notify_event_peak_pause "22:00-06:00" "1h 20min" "22:00" "60"
    _notify_discord_is_enabled || return 0

    local range="${1-}"
    local wait_fmt="${2-}"
    local resume_time="${3-}"
    local interval="${4-}"

    local body="NAScode — pause (heures pleines)"
    [[ -n "$range" ]] && body+="\n\n**Plage heures creuses**: ${range}"
    [[ -n "$wait_fmt" ]] && body+="\n**Attente estimée**: ${wait_fmt}"
    [[ -n "$resume_time" ]] && body+="\n**Reprise prévue**: ${resume_time}"
    [[ -n "$interval" ]] && body+="\n**Vérification**: toutes les ${interval}s"

    notify_discord_send_markdown "$body"
    return 0
}

notify_event_peak_resume() {
    # Usage: notify_event_peak_resume "22:00-06:00" "1h 18min"
    _notify_discord_is_enabled || return 0

    local range="${1-}"
    local actual_wait="${2-}"

    local body="NAScode — reprise (heures creuses)"
    [[ -n "$range" ]] && body+="\n\n**Plage heures creuses**: ${range}"
    [[ -n "$actual_wait" ]] && body+="\n**Attente réelle**: ${actual_wait}"

    notify_discord_send_markdown "$body"
    return 0
}

notify_event_script_exit() {
    # Appelé depuis cleanup() avec le code de sortie.
    # Envoi unique (et éviter doublon si un autre endroit a déjà envoyé un message de fin).
    [[ "${NASCODE_NOTIFY_RUN_FINISHED_SENT:-0}" == "1" ]] && return 0
    NASCODE_NOTIFY_RUN_FINISHED_SENT=1

    _notify_discord_is_enabled || return 0

    local exit_code="${1-0}"

    # Si un résumé texte existe, l’inclure (déjà sans ANSI via _strip_ansi_stream)
    local summary_snippet=""
    if [[ -n "${SUMMARY_FILE:-}" ]] && [[ -f "${SUMMARY_FILE}" ]]; then
        # Limiter pour rester sous la limite Discord
        summary_snippet=$(head -n 40 "${SUMMARY_FILE}" 2>/dev/null | _notify_strip_ansi | sed 's/[[:space:]]*$//' || true)
    fi

    local status="OK"
    [[ "$exit_code" != "0" ]] && status="ERROR"

    local body="NAScode — fin (${status})\n\n**Exit code**: ${exit_code}"

    if [[ -n "$summary_snippet" ]]; then
        body+="\n\n**Résumé**\n\n\`\`\`text\n${summary_snippet}\n\`\`\`"
    fi

    notify_discord_send_markdown "$body"
    return 0
}
