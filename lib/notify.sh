#!/bin/bash
###########################################################
# NOTIFICATIONS (Discord)
# - Centralisé, modulaire, best-effort (ne doit jamais casser le script)
# - Secret: le webhook NE DOIT PAS être commité
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
