#!/bin/bash
###########################################################
# FORMATAGE DES OPTIONS UI
# Fonctions pour formater les options actives et print_active_options
# Extrait de ui.sh pour modularité
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. L'affichage UI est best-effort
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

###########################################################
# AFFICHAGE DES OPTIONS ACTIVES (ENCADRÉ)
###########################################################

# Affiche un groupe d'options actives dans un encadré
# Usage: print_active_options "option1" "option2" ...
print_active_options() {
    _ui_is_quiet && return 0
    local options=("$@")
    local count=${#options[@]}
    
    [[ $count -eq 0 ]] && return 0
    
    echo ""
    echo -e "${DIM}  ┌─ Paramètres actifs ──────────────────────────────┐${NOCOLOR}"
    for opt in "${options[@]}"; do
        echo -e "${DIM}  │${NOCOLOR}  $opt"
    done
    echo -e "${DIM}  └────────────────────────────────────────────────┘${NOCOLOR}"
}

###########################################################
# FONCTIONS DE FORMATAGE D'OPTIONS
###########################################################

# Formate une option VMAF pour print_active_options
# Usage: format_option_vmaf
format_option_vmaf() {
    echo -e "${CYAN}ℹ${NOCOLOR}   Évaluation VMAF activée"
}

# Formate une option limitation pour print_active_options
# Usage: format_option_limit "5 fichiers" [mode]
format_option_limit() {
    local message="$1"
    local mode="${2:-normal}"
    local icon="🔒"
    
    if [[ "$mode" == "random" ]]; then
        icon="🎲"
    fi
    
    echo -e "${icon}  ${YELLOW}LIMITATION${NOCOLOR} : ${message}"
}

# Formate une option mode aléatoire pour print_active_options
# Usage: format_option_random_mode
format_option_random_mode() {
    echo -e "🎲  Mode aléatoire : ${YELLOW}activé${NOCOLOR}"
}

# Formate l'ordre de tri effectif de la queue pour print_active_options
# Usage: format_option_sort_mode
format_option_sort_mode() {
    local sort_mode="${SORT_MODE:-size_desc}"

    # En mode random, la sélection est aléatoire (l'ordre initial n'est pas pertinent)
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        echo -e "↕️   Tri de la queue : ${YELLOW}aléatoire (sélection)${NOCOLOR}"
        return 0
    fi

    local label
    case "$sort_mode" in
        size_desc)
            label="taille décroissante"
            ;;
        size_asc)
            label="taille croissante"
            ;;
        name_asc)
            label="nom ascendant"
            ;;
        name_desc)
            label="nom descendant"
            ;;
        *)
            label="$sort_mode"
            ;;
    esac

    echo -e "↕️   Tri de la queue : ${YELLOW}${label}${NOCOLOR}"
}

# Formate une option mode échantillon pour print_active_options
# Usage: format_option_sample
format_option_sample() {
    echo -e "🧪  Mode ${YELLOW}échantillon${NOCOLOR} : 30s à position aléatoire"
}

# Formate une option dry-run pour print_active_options
# Usage: format_option_dryrun
format_option_dryrun() {
    echo -e "🔍  Mode ${YELLOW}dry-run${NOCOLOR} : simulation sans conversion"
}

# Formate une option de codec vidéo pour print_active_options
# Usage: format_option_video
format_option_video() {
    local codec="${VIDEO_CODEC:-hevc}"
    case "$codec" in
        av1)
            echo -e "🎬  Codec vidéo ${MAGENTA}AV1${NOCOLOR} (SVT-AV1)"
            ;;
        hevc)
            echo -e "🎬  Codec vidéo ${MAGENTA}HEVC${NOCOLOR} (x265)"
            ;;
        *)
            echo -e "🎬  Codec vidéo ${MAGENTA}${codec^^}${NOCOLOR}"
            ;;
    esac
}

# Formate une option de codec audio pour print_active_options
# Usage: format_option_audio
format_option_audio() {
    local codec="${AUDIO_CODEC:-copy}"
    
    case "$codec" in
        aac)
            echo -e "🎵  Codec audio ${MAGENTA}AAC${NOCOLOR} @ ${AUDIO_BITRATE_AAC_DEFAULT:-160}k"
            ;;
        ac3)
            echo -e "🎵  Codec audio ${MAGENTA}AC3${NOCOLOR} (Dolby Digital) @ ${AUDIO_BITRATE_AC3_DEFAULT:-384}k"
            ;;
        opus)
            echo -e "🎵  Codec audio ${MAGENTA}Opus${NOCOLOR} @ ${AUDIO_BITRATE_OPUS_DEFAULT:-128}k"
            ;;
        *)
            # copy ou autre : pas d'affichage
            return 1
            ;;
    esac
}

# Formate le chemin source pour print_active_options
# Usage: format_option_source "/chemin/vers/source"
format_option_source() {
    local path="$1"
    echo -e "📂  Source : ${CYAN}${path}${NOCOLOR}"
}

# Formate le chemin de destination pour print_active_options
# Usage: format_option_dest "/chemin/vers/destination"
format_option_dest() {
    local path="$1"
    echo -e "📁  Destination : ${CYAN}${path}${NOCOLOR}"
}

# Formate le nombre de fichiers à traiter pour print_active_options
# Usage: format_option_file_count "19"
format_option_file_count() {
    local count="$1"
    echo -e "📊  Compteur de fichiers à traiter"
}

# Formate une option LIMIT_FPS (HFR) pour print_active_options
# Usage: format_option_limit_fps
format_option_limit_fps() {
    if [[ "${LIMIT_FPS:-false}" == true ]]; then
        echo -e "📽️  Vidéos HFR : ${YELLOW}limitées à ${LIMIT_FPS_TARGET:-29.97} fps${NOCOLOR}"
    else
        echo -e "📽️  Vidéos HFR : ${YELLOW}bitrate ajusté${NOCOLOR} (fps original conservé)"
    fi
}

###########################################################
# FONCTIONS LEGACY (POUR RÉTRO-COMPATIBILITÉ)
###########################################################

# Affiche une limitation active (fonction legacy, utilisée si pas de regroupement)
# Usage: print_limitation "Traitement de 5 fichiers maximum" [mode]
print_limitation() {
    _ui_is_quiet && return 0
    local message="$1"
    local mode="${2:-normal}"  # normal ou random
    local icon="🔒"
    
    if [[ "$mode" == "random" ]]; then
        icon="🎲"
    fi
    
    echo -e "${MAGENTA}  ${icon} ${MAGENTA}LIMITATION${NOCOLOR}${MAGENTA} : ${message}${NOCOLOR}"
    echo ""
}
