#!/bin/bash
###########################################################
# ENV — Chargement optionnel d'un fichier .env local
# - Sûr: ne fait PAS de `source` du fichier .env
# - Scope: importe uniquement les variables NASCODE_*
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Le chargement du .env est optionnel (fichier peut ne pas exister)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

_nascode_load_env_file() {
    # Usage: _nascode_load_env_file <path>
    local env_file="${1-}"
    [[ -z "$env_file" ]] && return 0
    [[ ! -f "$env_file" ]] && return 0

    local line trimmed key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim gauche/droite (espaces)
        trimmed="${line#${line%%[![:space:]]*}}"
        trimmed="${trimmed%${trimmed##*[![:space:]]}}"

        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == \#* ]] && continue

        # Supporte "export KEY=VALUE"
        if [[ "$trimmed" == export[[:space:]]* ]]; then
            trimmed="${trimmed#export}"
            trimmed="${trimmed#${trimmed%%[![:space:]]*}}"
        fi

        [[ "$trimmed" != *=* ]] && continue

        key="${trimmed%%=*}"
        value="${trimmed#*=}"

        # Trim autour de key/value
        key="${key#${key%%[![:space:]]*}}"
        key="${key%${key##*[![:space:]]}}"
        value="${value#${value%%[![:space:]]*}}"
        value="${value%${value##*[![:space:]]}}"

        # Valider le nom de variable + scope NASCODE_
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        [[ "$key" == NASCODE_* ]] || continue

        # Retirer des guillemets englobants simples/doubles (optionnel)
        if [[ "$value" == "\""*"\"" ]] && [[ ${#value} -ge 2 ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == "'"*"'" ]] && [[ ${#value} -ge 2 ]]; then
            value="${value:1:${#value}-2}"
        fi

        export "$key=$value"
    done < "$env_file"

    return 0
}

_nascode_autoload_env() {
    # Usage: _nascode_autoload_env <script_dir>
    # Activé par défaut. Désactivation possible via NASCODE_ENV_AUTOLOAD=false
    local script_dir="${1-}"
    [[ -z "$script_dir" ]] && script_dir="."

    if [[ "${NASCODE_ENV_AUTOLOAD:-true}" != "true" ]]; then
        return 0
    fi

    local env_file="${NASCODE_ENV_FILE:-${script_dir}/.env.local}"
    _nascode_load_env_file "$env_file"
}
