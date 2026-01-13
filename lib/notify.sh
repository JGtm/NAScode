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

_notify_discord_debug_enabled() {
    [[ "${NASCODE_DISCORD_NOTIFY_DEBUG:-false}" == "true" ]]
}

_notify_discord_debug_log_file() {
    local log_dir="${LOG_DIR:-./logs}"
    mkdir -p "$log_dir" 2>/dev/null || true

    local ts="${EXECUTION_TIMESTAMP:-}"
    if [[ -z "$ts" ]]; then
        ts=$(date +'%Y%m%d_%H%M%S' 2>/dev/null || echo "")
    fi
    [[ -z "$ts" ]] && ts="unknown"

    printf '%s' "${log_dir}/discord_notify_${ts}.log"
}

_notify_discord_debug_log() {
    _notify_discord_debug_enabled || return 0

    local msg="${1-}"
    [[ -z "$msg" ]] && return 0

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    {
        [[ -n "$now" ]] && printf '[%s] ' "$now"
        printf '%s\n' "$msg"
    } >> "$(_notify_discord_debug_log_file)" 2>/dev/null || true

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
    local event_name="${2-}"  # optionnel, uniquement pour debug
    [[ -z "$content" ]] && return 0

    # Discord limite content à 2000 chars. On coupe à ~1900 pour marge.
    if [[ ${#content} -gt 1900 ]]; then
        content="${content:0:1900}"$'\n...'
    fi

    local payload
    payload="{\"content\":\"$(_notify_json_escape "$content")\"}"

    # Écrire le payload dans un fichier temporaire et utiliser --data-binary.
    # Cela évite les surprises de parsing/encodage quand le JSON contient des caractères spéciaux.
    local payload_file
    payload_file="$(mktemp 2>/dev/null || echo "")"
    if [[ -z "$payload_file" ]]; then
        payload_file="/tmp/nascode_discord_payload_$$.json"
    fi
    printf '%s' "$payload" > "$payload_file" 2>/dev/null || true

    # Ne jamais afficher le webhook (secret).
    # En debug: log le code HTTP et un extrait de la réponse (sans URL).
    if _notify_discord_debug_enabled; then
        local resp_file
        resp_file="$(mktemp 2>/dev/null || echo "")"

        local http_code="000"
        http_code=$(curl -sS -m 10 --retry 2 --retry-delay 1 \
            -H "Content-Type: application/json; charset=utf-8" \
            -X POST \
            --data-binary "@${payload_file}" \
            -o "${resp_file:-/dev/null}" -w '%{http_code}' \
            "${NASCODE_DISCORD_WEBHOOK_URL}" \
            2>/dev/null || echo "000")

        local curl_exit=$?

        local payload_len=${#payload}
        _notify_discord_debug_log "event=${event_name:-unknown} http=${http_code} curl_exit=${curl_exit} payload_len=${payload_len}"

        # Si la requête est rejetée, log un extrait de la réponse (utile pour 400 Invalid Form Body)
        if [[ -n "${resp_file:-}" ]] && [[ -f "${resp_file}" ]] && [[ "${http_code}" =~ ^[45] ]]; then
            local resp_snippet
            resp_snippet=$(head -c 400 "${resp_file}" 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)
            [[ -n "${resp_snippet}" ]] && _notify_discord_debug_log "event=${event_name:-unknown} resp=${resp_snippet}"
        fi

        [[ -n "${resp_file:-}" ]] && rm -f "${resp_file}" 2>/dev/null || true
    else
        curl -sS -m 10 --retry 2 --retry-delay 1 \
            -H "Content-Type: application/json; charset=utf-8" \
            -X POST \
            --data-binary "@${payload_file}" \
            "${NASCODE_DISCORD_WEBHOOK_URL}" \
            >/dev/null 2>&1 || true
    fi

    rm -f "$payload_file" 2>/dev/null || true

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
    [[ -n "$now" ]] && body+=$'\n\n'"**Date**: ${now}"

    body+=$'\n\n'"**Paramètres actifs**"$'\n\n'"\`\`\`text"$'\n'
    local line
    for line in "${lines[@]}"; do
        body+="${line}"$'\n'
    done
    body+="\`\`\`"

    notify_discord_send_markdown "$body" "run_started"
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
    [[ -n "$range" ]] && body+=$'\n\n'"**Plage heures creuses**: ${range}"
    [[ -n "$wait_fmt" ]] && body+=$'\n'"**Attente estimée**: ${wait_fmt}"
    [[ -n "$resume_time" ]] && body+=$'\n'"**Reprise prévue**: ${resume_time}"
    [[ -n "$interval" ]] && body+=$'\n'"**Vérification**: toutes les ${interval}s"

    notify_discord_send_markdown "$body" "peak_pause"
    return 0
}

notify_event_peak_resume() {
    # Usage: notify_event_peak_resume "22:00-06:00" "1h 18min"
    _notify_discord_is_enabled || return 0

    local range="${1-}"
    local actual_wait="${2-}"

    local body="NAScode — reprise (heures creuses)"
    [[ -n "$range" ]] && body+=$'\n\n'"**Plage heures creuses**: ${range}"
    [[ -n "$actual_wait" ]] && body+=$'\n'"**Attente réelle**: ${actual_wait}"

    notify_discord_send_markdown "$body" "peak_resume"
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

    local body="NAScode — fin (${status})"$'\n\n'"**Exit code**: ${exit_code}"

    if [[ -n "$summary_snippet" ]]; then
        body+=$'\n\n'"**Résumé**"$'\n\n'"\`\`\`text"$'\n'"${summary_snippet}"$'\n'"\`\`\`"
    fi

    notify_discord_send_markdown "$body" "script_exit"
    return 0
}
