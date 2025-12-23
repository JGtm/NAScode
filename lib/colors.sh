#!/bin/bash
###########################################################
# COULEURS ANSI & STYLES D'AFFICHAGE
# Définition des codes couleurs et formatage pour le terminal
###########################################################

# === COULEURS DE BASE ===
readonly NOCOLOR=$'\033[0m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly RED=$'\033[0;31m'
readonly CYAN=$'\033[0;36m'
readonly BLUE=$'\033[0;34m'
readonly MAGENTA=$'\033[0;35m'
readonly WHITE=$'\033[0;37m'
readonly ORANGE=$'\033[1;33m'

# === STYLES SUPPLÉMENTAIRES ===
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly ITALIC=$'\033[3m'
readonly UNDERLINE=$'\033[4m'

# === CARACTÈRES DE DESSIN DE BOÎTE (Unicode) ===
readonly BOX_TL="╭"    # Top-left
readonly BOX_TR="╮"    # Top-right
readonly BOX_BL="╰"    # Bottom-left
readonly BOX_BR="╯"    # Bottom-right
readonly BOX_H="─"     # Horizontal
readonly BOX_V="│"     # Vertical
readonly BOX_ARROW="▶"
readonly BOX_DOT="●"
readonly BOX_CHECK="✔"
readonly BOX_CROSS="✖"
readonly BOX_WARN="⚠"
readonly BOX_INFO="ℹ"
readonly BOX_QUESTION="?"

###########################################################
# FONCTIONS D'AFFICHAGE STYLISÉ
###########################################################

# Affiche un séparateur horizontal stylé
# Usage: print_separator [largeur] [couleur]
print_separator() {
    local width="${1:-50}"
    local color="${2:-$DIM}"
    local line=""
    for ((i=0; i<width; i++)); do
        line+="$BOX_H"
    done
    echo -e "${color}${line}${NOCOLOR}"
}

# Affiche un titre encadré
# Usage: print_header "Titre" [couleur]
print_header() {
    local title="$1"
    local color="${2:-$CYAN}"
    local padding=2
    local title_len=${#title}
    local total_width=$((title_len + padding * 2 + 2))
    
    local top_line="${BOX_TL}"
    local bottom_line="${BOX_BL}"
    for ((i=0; i<total_width-2; i++)); do
        top_line+="$BOX_H"
        bottom_line+="$BOX_H"
    done
    top_line+="${BOX_TR}"
    bottom_line+="${BOX_BR}"
    
    local spaces=""
    for ((i=0; i<padding; i++)); do
        spaces+=" "
    done
    
    echo ""
    echo -e "${color}${top_line}${NOCOLOR}"
    echo -e "${color}${BOX_V}${NOCOLOR}${spaces}${WHITE}${title}${NOCOLOR}${spaces}${color}${BOX_V}${NOCOLOR}"
    echo -e "${color}${bottom_line}${NOCOLOR}"
}

# Affiche une section avec titre
# Usage: print_section "Titre de section"
print_section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}${BOX_ARROW} ${WHITE}${title}${NOCOLOR}"
    print_separator 45 "$DIM"
}

# Affiche un message d'information stylé
# Usage: print_info "Message"
print_info() {
    local message="$1"
    echo -e "  ${CYAN}${BOX_INFO}${NOCOLOR}  ${message}"
    echo ""
}

# Affiche un message de succès stylé
# Usage: print_success "Message"
print_success() {
    local message="$1"
    echo -e "  ${GREEN}${BOX_CHECK}${NOCOLOR}  ${GREEN}${message}${NOCOLOR}"
}

# Affiche un message d'avertissement stylé
# Usage: print_warning "Message"
print_warning() {
    local message="$1"
    echo -e "  ${YELLOW}${BOX_WARN}${NOCOLOR}  ${YELLOW}${message}${NOCOLOR}"
}

# Affiche un message d'erreur stylé
# Usage: print_error "Message"
print_error() {
    local message="$1"
    echo -e "  ${RED}${BOX_CROSS}${NOCOLOR}  ${RED}${message}${NOCOLOR}"
}

# Affiche un élément de liste
# Usage: print_item "Label" "Valeur" [couleur_valeur]
print_item() {
    local label="$1"
    local value="$2"
    local value_color="${3:-$WHITE}"
    echo -e "  ${DIM}${BOX_DOT}${NOCOLOR} ${label} : ${value_color}${value}${NOCOLOR}"
}

# Affiche une question interactive avec style
# Usage: ask_question "Question ?" [default: O/n]
ask_question() {
    local question="$1"
    local default="${2:-O/n}"
    echo ""
    echo -e "${MAGENTA}${BOX_TL}${BOX_H}${BOX_H} ${WHITE}${question}${NOCOLOR}"
    echo -ne "${MAGENTA}${BOX_BL}${BOX_H}${BOX_ARROW}${NOCOLOR} ${DIM}(${default})${NOCOLOR} "
}

# Affiche un encadré d'alerte critique
# Usage: print_critical_alert "Titre" "Message ligne 1" "Message ligne 2" ...
print_critical_alert() {
    local title="$1"
    shift
    local messages=("$@")
    
    echo ""
    echo -e "${RED}  ╔════════════════════════════════════════════════════╗${NOCOLOR}"
    echo -e "${RED}  ║  ${BOX_WARN} ${BOX_WARN} ${BOX_WARN}  ${WHITE}${title}${NOCOLOR}${RED}  ${BOX_WARN} ${BOX_WARN} ${BOX_WARN}${NOCOLOR}"
    echo -e "${RED}  ╠════════════════════════════════════════════════════╣${NOCOLOR}"
    for msg in "${messages[@]}"; do
        printf "${RED}  ║${NOCOLOR}  %-50s ${RED}║${NOCOLOR}\n" "$msg"
    done
    echo -e "${RED}  ╚════════════════════════════════════════════════════╝${NOCOLOR}"
    echo ""
}

# Affiche un encadré d'attention (warning box)
# Usage: print_warning_box "Titre" "Message"
print_warning_box() {
    local title="$1"
    local message="$2"
    
    echo ""
    echo -e "${YELLOW}  ┌─ ${BOX_WARN} ${YELLOW}${title}${NOCOLOR}"
    echo -e "${YELLOW}  │${NOCOLOR}"
    echo -e "${YELLOW}  │${NOCOLOR}  ${message}"
    echo -e "${YELLOW}  └${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${NOCOLOR}"
}

# Affiche un encadré d'information
# Usage: print_info_box "Titre" "Message"
print_info_box() {
    local title="$1"
    local message="$2"
    
    echo ""
    echo -e "${CYAN}  ┌─ ${BOX_INFO} ${CYAN}${title}${NOCOLOR}"
    echo -e "${CYAN}  │${NOCOLOR}"
    echo -e "${CYAN}  │${NOCOLOR}  ${message}"
    echo -e "${CYAN}  └${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${NOCOLOR}"
}

# Affiche une boîte de succès
# Usage: print_success_box "Message"
print_success_box() {
    local message="$1"
    echo -e "${GREEN}  ╭${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}╮${NOCOLOR}"
    echo -e "${GREEN}  │ ${BOX_CHECK} ${GREEN}${message}${NOCOLOR}"
    echo -e "${GREEN}  ╰${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}╯${NOCOLOR}"
}

# Affiche un en-tête de transfert/téléchargement
# Usage: print_transfer_item "Nom du fichier"
print_transfer_item() {
    local filename="$1"
    echo ""
    echo -e "${CYAN}  ┌─ 📥 ${WHITE}${filename}${NOCOLOR}"
    echo -e "${CYAN}  │${NOCOLOR}"
}

# Ferme l'encadré de transfert (après la barre de progression)
# Usage: print_transfer_item_end
print_transfer_item_end() {
    echo -e "${CYAN}  └───────────────────────────────────────${NOCOLOR}"
}

# Affiche un spinner de chargement (pour les attentes)
# Usage: print_status "En cours..." [couleur]
print_status() {
    local message="$1"
    local color="${2:-$CYAN}"
    echo -e "  ${color}◐${NOCOLOR} ${message}"
}

# Affiche un état vide (rien à traiter)
# Usage: print_empty_state "Message"
print_empty_state() {
    local message="$1"
    echo ""
    echo -e "${DIM}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${DIM}  ┃  ${CYAN}${BOX_INFO}${NOCOLOR}  ${WHITE}${message}${NOCOLOR}"
    echo -e "${DIM}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
    echo ""
}

###########################################################
# RÉSUMÉ FINAL
###########################################################

# Affiche l'en-tête du résumé de conversion
# Usage: print_summary_header
print_summary_header() {
    echo ""
    echo -e "${GREEN}  ╔═══════════════════════════════════════════╗${NOCOLOR}"
    echo -e "${GREEN}  ║                                           ║${NOCOLOR}"
    echo -e "${GREEN}  ║       📋  RÉSUMÉ DE CONVERSION  📋        ║${NOCOLOR}"
    echo -e "${GREEN}  ║                                           ║${NOCOLOR}"
    echo -e "${GREEN}  ╠═══════════════════════════════════════════╣${NOCOLOR}"
}

# Affiche une ligne du résumé
# Usage: print_summary_item "Label" "Valeur" [couleur_valeur]
print_summary_item() {
    local label="$1"
    local value="$2"
    local color="${3:-$WHITE}"
    # Largeur intérieure totale = 43 caractères
    # Compenser les caractères multi-bytes (é, è, etc. = 2 bytes mais 1 colonne)
    local byte_len char_len extra label_width content
    byte_len=$(echo -n "$label" | wc -c)
    char_len=$(echo -n "$label" | wc -m)
    extra=$((byte_len - char_len))
    label_width=$((20 + extra))
    content=$(printf "  %-${label_width}s%19s  " "$label" "$value")
    echo -e "${GREEN}  ║${NOCOLOR}${color}${content}${NOCOLOR}${GREEN}║${NOCOLOR}"
}

# Affiche un séparateur dans le résumé
# Usage: print_summary_separator
print_summary_separator() {
    echo -e "${GREEN}  ╟───────────────────────────────────────────╢${NOCOLOR}"
}

# Ferme l'encadré du résumé
# Usage: print_summary_footer
print_summary_footer() {
    echo -e "${GREEN}  ╚═══════════════════════════════════════════╝${NOCOLOR}"
    echo ""
}

###########################################################
# ENCADRÉS DE PHASE (Conversion / Transfert)
###########################################################

# Affiche le démarrage d'une phase de traitement
# Usage: print_phase_start "🎬 CONVERSION" "5 fichiers" [couleur]
print_phase_start() {
    local title="$1"
    local subtitle="$2"
    local color="${3:-$CYAN}"
    
    echo ""
    echo -e "${color}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${color}  ┃  ${WHITE}${title}${NOCOLOR}"
    if [[ -n "$subtitle" ]]; then
        echo -e "${color}  ┃  ${DIM}${subtitle}${NOCOLOR}"
    fi
    echo -e "${color}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
    echo ""
}

# Affiche une limitation active
# Usage: print_limitation "Traitement de 5 fichiers maximum" [mode]
print_limitation() {
    local message="$1"
    local mode="${2:-normal}"  # normal ou random
    local icon="🔒"
    
    if [[ "$mode" == "random" ]]; then
        icon="🎲"
    fi
    
    echo -e "${MAGENTA}  ${icon} ${MAGENTA}LIMITATION${NOCOLOR}${MAGENTA} : ${message}${NOCOLOR}"
    echo ""
}

# Affiche le début de la section transfert
# Usage: print_transfer_start [nb_fichiers]
print_transfer_start() {
    local nb_files="${1:-}"
    local subtitle=""
    if [[ -n "$nb_files" ]]; then
        subtitle="$nb_files fichier(s) en attente"
    fi
    print_phase_start "📤 TRANSFERT" "$subtitle" "$BLUE"
}

# Affiche la fin de la section transfert
# Usage: print_transfer_complete
print_transfer_complete() {
    echo ""
    echo -e "${BLUE}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${BLUE}  ┃  ${GREEN}${BOX_CHECK}${NOCOLOR}  ${GREEN}Tous les transferts terminés${NOCOLOR}${BLUE}        ┃${NOCOLOR}"
    echo -e "${BLUE}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
}

# Affiche le début de la section VMAF
# Usage: print_vmaf_start nb_fichiers
print_vmaf_start() {
    local nb_files="$1"
    print_phase_start "📊 ANALYSE VMAF" "$nb_files fichier(s) à analyser" "$YELLOW"
}

# Affiche la fin de la section VMAF
# Usage: print_vmaf_complete
print_vmaf_complete() {
    echo ""
    echo -e "${YELLOW}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${YELLOW}  ┃  ${GREEN}${BOX_CHECK}${NOCOLOR}  ${GREEN}Analyses VMAF terminées${NOCOLOR}${YELLOW}             ┃${NOCOLOR}"
    echo -e "${YELLOW}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
}

# Affiche le début de la section conversion
# Usage: print_conversion_start nb_fichiers [limitation]
print_conversion_start() {
    local nb_files="$1"
    local limitation="${2:-}"
    
    print_phase_start "🎬 CONVERSION" "$nb_files fichier(s) à traiter" "$CYAN"
    
    if [[ -n "$limitation" ]]; then
        print_limitation "$limitation"
    fi
}

# Affiche la fin de la section conversion
# Usage: print_conversion_complete
print_conversion_complete() {
    echo ""
    echo -e "${CYAN}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${CYAN}  ┃  ${GREEN}${BOX_CHECK}${NOCOLOR}  ${GREEN}Toutes les conversions terminées${NOCOLOR}${CYAN}    ┃${NOCOLOR}"
    echo -e "${CYAN}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
}
