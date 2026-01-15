#!/bin/bash
###########################################################
# INTERNATIONALISATION (i18n)
#
# Ce module gère le chargement des fichiers de locale et
# fournit la fonction msg() pour récupérer les messages
# traduits.
#
# Usage:
#   msg MSG_KEY [args...]
#   msg MSG_ARG_FILE_NOT_FOUND "$filename"
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les modules sont sourcés, pas exécutés directement
###########################################################

# Langue par défaut
readonly I18N_DEFAULT_LANG="fr"

# Répertoire des locales (relatif à SCRIPT_DIR, défini dans nascode)
readonly I18N_LOCALE_DIR="${SCRIPT_DIR}/locale"

# Langue courante (modifiable via --lang ou variable d'environnement NASCODE_LANG)
LANG_UI="${NASCODE_LANG:-$I18N_DEFAULT_LANG}"

###########################################################
# CHARGEMENT DE LA LOCALE
###########################################################

# Charge un fichier de locale.
# Usage: _i18n_load [lang]
# Si lang n'est pas fourni, utilise LANG_UI.
# Fallback automatique vers français si la locale demandée n'existe pas.
_i18n_load() {
    local lang="${1:-$LANG_UI}"
    local locale_file="${I18N_LOCALE_DIR}/${lang}.sh"
    
    if [[ -f "$locale_file" ]]; then
        # shellcheck source=/dev/null
        source "$locale_file"
        LANG_UI="$lang"
    else
        # Fallback vers français
        if [[ "$lang" != "fr" ]] && [[ -f "${I18N_LOCALE_DIR}/fr.sh" ]]; then
            # shellcheck source=/dev/null
            source "${I18N_LOCALE_DIR}/fr.sh"
            LANG_UI="fr"
        fi
    fi
}

###########################################################
# FONCTION msg() — Récupération des messages traduits
###########################################################

# Récupère un message traduit avec substitution des placeholders.
# Usage: msg MSG_KEY [args...]
#
# Exemples:
#   msg MSG_ERROR_FILE_NOT_FOUND
#   msg MSG_ARG_REQUIRES_VALUE "--limit"
#   msg MSG_CONV_COMPLETED "3m 45s" "850 Mo"
#
# Les placeholders %s, %d, etc. sont remplacés par les arguments.
# Si la clé n'existe pas, retourne la clé elle-même (fallback).
msg() {
    local key="$1"
    shift
    
    # Indirection Bash : ${!key} donne la valeur de la variable nommée $key
    local template="${!key:-}"
    
    # Si la clé n'existe pas, retourner la clé comme fallback
    if [[ -z "$template" ]]; then
        echo "$key"
        return
    fi
    
    # Si pas d'arguments, retourner le template tel quel
    if [[ $# -eq 0 ]]; then
        echo "$template"
        return
    fi
    
    # Substitution des placeholders avec printf
    # shellcheck disable=SC2059
    printf "$template" "$@"
}

###########################################################
# INITIALISATION
###########################################################

# Charger la locale au sourcing du module
_i18n_load
