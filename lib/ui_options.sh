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
    echo -e "${DIM}  ┌─ $(msg MSG_UI_OPT_ACTIVE_PARAMS) ──────────────────────────────┐${NOCOLOR}"
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
    echo -e "${CYAN}ℹ${NOCOLOR}   $(msg MSG_UI_OPT_VMAF_ENABLED)"
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
    echo -e "🎲  ${YELLOW}$(msg MSG_UI_OPT_RANDOM_MODE)${NOCOLOR}"
}

# Formate l'ordre de tri effectif de la queue pour print_active_options
# Usage: format_option_sort_mode
format_option_sort_mode() {
    local sort_mode="${SORT_MODE:-size_desc}"

    # En mode random, la sélection est aléatoire (l'ordre initial n'est pas pertinent)
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        echo -e "↕️   $(msg MSG_UI_OPT_SORT_QUEUE) : ${YELLOW}$(msg MSG_UI_OPT_SORT_RANDOM)${NOCOLOR}"
        return 0
    fi

    local label
    case "$sort_mode" in
        size_desc)
            label="$(msg MSG_UI_OPT_SORT_SIZE_DESC)"
            ;;
        size_asc)
            label="$(msg MSG_UI_OPT_SORT_SIZE_ASC)"
            ;;
        name_asc)
            label="$(msg MSG_UI_OPT_SORT_NAME_ASC)"
            ;;
        name_desc)
            label="$(msg MSG_UI_OPT_SORT_NAME_DESC)"
            ;;
        *)
            label="$sort_mode"
            ;;
    esac

    echo -e "↕️   $(msg MSG_UI_OPT_SORT_QUEUE) : ${YELLOW}${label}${NOCOLOR}"
}

# Formate une option mode échantillon pour print_active_options
# Usage: format_option_sample
format_option_sample() {
    echo -e "🧪  ${YELLOW}$(msg MSG_UI_OPT_SAMPLE)${NOCOLOR}"
}

# Formate une option dry-run pour print_active_options
# Usage: format_option_dryrun
format_option_dryrun() {
    echo -e "🔍  $(msg MSG_UI_OPT_DRYRUN | sed "s/dry-run/${YELLOW}dry-run${NOCOLOR}/")"
}

# Formate une option de codec vidéo pour print_active_options
# Usage: format_option_video
format_option_video() {
    local codec="${VIDEO_CODEC:-hevc}"
    local codec_label="$(msg MSG_UI_OPT_VIDEO_CODEC)"
    case "$codec" in
        av1)
            echo -e "🎬  ${codec_label} ${MAGENTA}AV1${NOCOLOR} (SVT-AV1)"
            ;;
        hevc)
            echo -e "🎬  ${codec_label} ${MAGENTA}HEVC${NOCOLOR} (x265)"
            ;;
        *)
            echo -e "🎬  ${codec_label} ${MAGENTA}${codec^^}${NOCOLOR}"
            ;;
    esac
}

# Formate une option de codec audio pour print_active_options
# Usage: format_option_audio
format_option_audio() {
    local codec="${AUDIO_CODEC:-copy}"
    local codec_label="$(msg MSG_UI_OPT_AUDIO_CODEC)"
    
    case "$codec" in
        aac)
            echo -e "🎵  ${codec_label} ${MAGENTA}AAC${NOCOLOR} @ ${AUDIO_BITRATE_AAC_DEFAULT:-160}k"
            ;;
        ac3)
            echo -e "🎵  ${codec_label} ${MAGENTA}AC3${NOCOLOR} (Dolby Digital) @ ${AUDIO_BITRATE_AC3_DEFAULT:-384}k"
            ;;
        opus)
            echo -e "🎵  ${codec_label} ${MAGENTA}Opus${NOCOLOR} @ ${AUDIO_BITRATE_OPUS_DEFAULT:-128}k"
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
    echo -e "📂  $(msg MSG_UI_OPT_SOURCE) : ${CYAN}${path}${NOCOLOR}"
}

# Formate le chemin de destination pour print_active_options
# Usage: format_option_dest "/chemin/vers/destination"
format_option_dest() {
    local path="$1"
    echo -e "📁  $(msg MSG_UI_OPT_DEST) : ${CYAN}${path}${NOCOLOR}"
}

# Formate le nombre de fichiers à traiter pour print_active_options
# Usage: format_option_file_count "19"
format_option_file_count() {
    local count="$1"
    echo -e "📊  $(msg MSG_UI_OPT_FILE_COUNT)"
}

# Formate une option LIMIT_FPS (HFR) pour print_active_options
# Usage: format_option_limit_fps
format_option_limit_fps() {
    if [[ "${LIMIT_FPS:-false}" == true ]]; then
        echo -e "📽️  ${YELLOW}$(msg MSG_UI_OPT_HFR_LIMITED "${LIMIT_FPS_TARGET:-29.97}")${NOCOLOR}"
    else
        echo -e "📽️  ${YELLOW}$(msg MSG_UI_OPT_HFR_BITRATE)${NOCOLOR}"
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
