#!/bin/bash
###########################################################
# NOTIFY — TRANSPORT DISCORD (webhook)
# Best-effort: aucune erreur réseau ne doit arrêter NAScode.
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les appels réseau sont best-effort (ne doivent jamais bloquer)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

_notify_discord_is_enabled() {
    # Anti-spam tests: en environnement Bats, on désactive par défaut.
    # Opt-in explicite possible pour les tests unitaires de notify.
    if [[ -n "${BATS_TEST_FILENAME:-}" ]] || [[ -n "${BATS_RUN_TMPDIR:-}" ]] || [[ -n "${BATS_VERSION:-}" ]]; then
        [[ "${NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS:-false}" == "true" ]] || return 1
    fi

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

notify_discord_send_markdown() {
    # Best-effort: ne jamais échouer (set -e safe)
    _notify_discord_is_enabled || return 0

    local content="${1-}"
    local event_name="${2-}"  # optionnel, uniquement pour debug
    [[ -z "$content" ]] && return 0

    # Discord limite content à 2000 chars. On coupe à ~1900 pour marge.
    local max_chars="${DISCORD_CONTENT_MAX_CHARS:-1900}"
    if [[ ${#content} -gt "$max_chars" ]]; then
        content="${content:0:$max_chars}"$'\n...'
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
    local curl_timeout="${DISCORD_CURL_TIMEOUT:-10}"
    local curl_retries="${DISCORD_CURL_RETRIES:-2}"
    local curl_retry_delay="${DISCORD_CURL_RETRY_DELAY:-1}"

    if _notify_discord_debug_enabled; then
        local resp_file
        resp_file="$(mktemp 2>/dev/null || echo "")"

        local http_code="000"
        http_code=$(curl -sS -m "$curl_timeout" --retry "$curl_retries" --retry-delay "$curl_retry_delay" \
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
        curl -sS -m "$curl_timeout" --retry "$curl_retries" --retry-delay "$curl_retry_delay" \
            -H "Content-Type: application/json; charset=utf-8" \
            -X POST \
            --data-binary "@${payload_file}" \
            "${NASCODE_DISCORD_WEBHOOK_URL}" \
            >/dev/null 2>&1 || true
    fi

    rm -f "$payload_file" 2>/dev/null || true

    return 0
}
