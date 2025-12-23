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
readonly ORANGE=$'\033[1;33m'

# === STYLES SUPPLÉMENTAIRES ===
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly ITALIC=$'\033[3m'
readonly UNDERLINE=$'\033[4m'

# === COULEURS CLAIRES (BRIGHT) ===
readonly BRIGHT_GREEN=$'\033[1;32m'
readonly BRIGHT_YELLOW=$'\033[1;33m'
readonly BRIGHT_CYAN=$'\033[1;36m'
readonly BRIGHT_BLUE=$'\033[1;34m'
readonly BRIGHT_MAGENTA=$'\033[1;35m'
readonly BRIGHT_WHITE=$'\033[1;37m'

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
    local color="${2:-$BRIGHT_CYAN}"
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
    echo -e "${color}${BOX_V}${NOCOLOR}${spaces}${BOLD}${title}${NOCOLOR}${spaces}${color}${BOX_V}${NOCOLOR}"
    echo -e "${color}${bottom_line}${NOCOLOR}"
}

# Affiche une section avec titre
# Usage: print_section "Titre de section"
print_section() {
    local title="$1"
    echo ""
    echo -e "${BRIGHT_BLUE}${BOX_ARROW} ${BOLD}${title}${NOCOLOR}"
    print_separator 45 "$DIM"
}

# Affiche un message d'information stylé
# Usage: print_info "Message"
print_info() {
    local message="$1"
    echo -e "  ${CYAN}${BOX_INFO}${NOCOLOR}  ${message}"
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
    local value_color="${3:-$BRIGHT_WHITE}"
    echo -e "  ${DIM}${BOX_DOT}${NOCOLOR} ${label} : ${value_color}${value}${NOCOLOR}"
}

# Affiche une question interactive avec style
# Usage: ask_question "Question ?" variable_name [default: O/n]
ask_question() {
    local question="$1"
    local default="${2:-O/n}"
    echo ""
    echo -e "${BRIGHT_MAGENTA}${BOX_TL}${BOX_H}${BOX_H} ${BOX_QUESTION} ${BOLD}Question${NOCOLOR}"
    echo -e "${BRIGHT_MAGENTA}${BOX_V}${NOCOLOR}"
    echo -e "${BRIGHT_MAGENTA}${BOX_V}${NOCOLOR}  ${question}"
    echo -e "${BRIGHT_MAGENTA}${BOX_V}${NOCOLOR}"
    echo -ne "${BRIGHT_MAGENTA}${BOX_BL}${BOX_H}${BOX_ARROW}${NOCOLOR} ${DIM}(${default})${NOCOLOR} "
}

# Affiche un encadré d'alerte critique
# Usage: print_critical_alert "Titre" "Message ligne 1" "Message ligne 2" ...
print_critical_alert() {
    local title="$1"
    shift
    local messages=("$@")
    
    echo ""
    echo -e "${RED}${BOLD}  ╔════════════════════════════════════════════════════╗${NOCOLOR}"
    echo -e "${RED}${BOLD}  ║  ${BOX_WARN} ${BOX_WARN} ${BOX_WARN}  ${title}  ${BOX_WARN} ${BOX_WARN} ${BOX_WARN}${NOCOLOR}"
    echo -e "${RED}${BOLD}  ╠════════════════════════════════════════════════════╣${NOCOLOR}"
    for msg in "${messages[@]}"; do
        printf "${RED}  ║${NOCOLOR}  %-50s ${RED}║${NOCOLOR}\n" "$msg"
    done
    echo -e "${RED}${BOLD}  ╚════════════════════════════════════════════════════╝${NOCOLOR}"
    echo ""
}

# Affiche un encadré d'attention (warning box)
# Usage: print_warning_box "Titre" "Message"
print_warning_box() {
    local title="$1"
    local message="$2"
    
    echo ""
    echo -e "${YELLOW}  ┌─ ${BOX_WARN} ${BOLD}${title}${NOCOLOR}"
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
    echo -e "${CYAN}  ┌─ ${BOX_INFO} ${BOLD}${title}${NOCOLOR}"
    echo -e "${CYAN}  │${NOCOLOR}"
    echo -e "${CYAN}  │${NOCOLOR}  ${message}"
    echo -e "${CYAN}  └${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${NOCOLOR}"
}

# Affiche une boîte de succès
# Usage: print_success_box "Message"
print_success_box() {
    local message="$1"
    echo -e "${GREEN}  ╭${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}╮${NOCOLOR}"
    echo -e "${GREEN}  │ ${BOX_CHECK} ${message}${NOCOLOR}"
    echo -e "${GREEN}  ╰${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}╯${NOCOLOR}"
}

# Affiche un spinner de chargement (pour les attentes)
# Usage: print_status "En cours..." [couleur]
print_status() {
    local message="$1"
    local color="${2:-$CYAN}"
    echo -e "  ${color}◐${NOCOLOR} ${message}"
}
