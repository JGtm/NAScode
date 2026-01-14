#!/bin/bash
###########################################################
# NOTIFICATIONS (Discord)
# - Centralisé, modulaire, best-effort (ne doit jamais casser le script)
# - Secret: le webhook NE DOIT PAS être commité
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les notifications sont best-effort (ne doivent jamais
#    bloquer le script en cas d'échec réseau/webhook)
# 3. Les modules sont sourcés, pas exécutés directement
#
# Modules:
# - notify_discord.sh : transport webhook + robustesse
# - notify_format.sh  : helpers de formatage (pur)
# - notify_events.sh  : événements (format + envoi)
###########################################################

_notify__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Best-effort : si un module manque, ne jamais casser le script.
if [[ -f "${_notify__dir}/notify_discord.sh" ]]; then
    # shellcheck disable=SC1090
    source "${_notify__dir}/notify_discord.sh"
fi
if [[ -f "${_notify__dir}/notify_format.sh" ]]; then
    # shellcheck disable=SC1090
    source "${_notify__dir}/notify_format.sh"
fi
if [[ -f "${_notify__dir}/notify_events.sh" ]]; then
    # shellcheck disable=SC1090
    source "${_notify__dir}/notify_events.sh"
fi
