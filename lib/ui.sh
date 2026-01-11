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

_ui_is_quiet() {
    [[ "${UI_QUIET:-false}" == true ]]
}

# Affiche un séparateur horizontal stylé
# Usage: print_separator [largeur] [couleur]
print_separator() {
    _ui_is_quiet && return 0
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
    _ui_is_quiet && return 0
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
    echo -e "  ${color}${top_line}${NOCOLOR}"
    echo -e "  ${color}${BOX_V}${NOCOLOR}${spaces}${WHITE}${title}${NOCOLOR}${spaces}${color}${BOX_V}${NOCOLOR}"
    echo -e "  ${color}${bottom_line}${NOCOLOR}"
}

# Affiche une section avec titre
# Usage: print_section "Titre de section"
print_section() {
    _ui_is_quiet && return 0
    local title="$1"
    echo ""

    # Indentation cohérente avec print_item/print_success/print_warning
    echo -e "  ${BLUE}${BOX_ARROW} ${WHITE}${title}${NOCOLOR}"

    local width=45
    local line=""
    for ((i=0; i<width; i++)); do
        line+="$BOX_H"
    done
    echo -e "  ${DIM}${line}${NOCOLOR}"
}

# Affiche un message d'information stylé
# Usage: print_info "Message"
print_info() {
    _ui_is_quiet && return 0
    local message="$1"
    echo -e "  ${CYAN}${BOX_INFO}${NOCOLOR}  ${message}"
    echo ""
}

# Affiche un message d'information stylé (version compacte, sans saut de ligne)
# Usage: print_info_compact "Message"
print_info_compact() {
    _ui_is_quiet && return 0
    local message="$1"
    echo -e "  ${CYAN}${BOX_INFO}${NOCOLOR}  ${message}"
}

# Affiche un message de succès stylé
# Usage: print_success "Message"
print_success() {
    _ui_is_quiet && return 0
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
    _ui_is_quiet && return 0
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
    _ui_is_quiet && return 0
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
    _ui_is_quiet && return 0
    local message="$1"
    echo -e "${GREEN}  ╭${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}╮${NOCOLOR}"
    echo -e "${GREEN}  │ ${BOX_CHECK} ${GREEN}${message}${NOCOLOR}"
    echo -e "${GREEN}  ╰${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}╯${NOCOLOR}"
}

# Affiche un en-tête de transfert/téléchargement
# Usage: print_transfer_item "Nom du fichier"
print_transfer_item() {
    _ui_is_quiet && return 0
    local filename="$1"
    echo -e "${CYAN}  ┌─ 📥 ${WHITE}Téléchargement vers dossier temporaire${NOCOLOR}"
    echo -e "${CYAN}  │${NOCOLOR}"
}

# Ferme l'encadré de transfert (après la barre de progression)
# Usage: print_transfer_item_end
print_transfer_item_end() {
    _ui_is_quiet && return 0
    echo -e "${CYAN}  └───────────────────────────────────────${NOCOLOR}"
}

# Affiche un spinner de chargement (pour les attentes)
# Usage: print_status "En cours..." [couleur]
print_status() {
    _ui_is_quiet && return 0
    local message="$1"
    local color="${2:-$CYAN}"
    echo -e "  ${color}◐${NOCOLOR} ${message}"
}

# Affiche un état vide (rien à traiter)
# Usage: print_empty_state "Message"
print_empty_state() {
    _ui_is_quiet && return 0
    local message="$1"
    echo ""
    echo -e "${DIM}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${DIM}  ┃  ${CYAN}${BOX_INFO}${NOCOLOR}  ${WHITE}${message}${NOCOLOR}"
    echo -e "${DIM}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
    echo ""
}

###########################################################
# INDEXATION
###########################################################

# Affiche l'en-tête du bloc d'indexation
# Usage: print_indexing_start
print_indexing_start() {
    _ui_is_quiet && return 0
    echo ""
    echo -e "${MAGENTA}  ┌──────────────────────────────────────────────────┐${NOCOLOR}"
}

# Affiche la progression de l'indexation (sur une seule ligne, mise à jour in-place)
# Usage: print_indexing_progress <current> <total>
# Largeur interne : 50 caractères (supporte jusqu'à 9999/9999 fichiers)
print_indexing_progress() {
    _ui_is_quiet && return 0
    local current="$1"
    local total="$2"
    # Format : "  │  📊 Indexation : 9999/9999 fichiers             │"
    printf "\r${MAGENTA}  │${NOCOLOR}  📊 Indexation : ${CYAN}%4d${NOCOLOR}/${WHITE}%4d${NOCOLOR} fichiers              ${MAGENTA}│${NOCOLOR}" "$current" "$total" >&2
}

# Affiche la fin du bloc d'indexation avec le résultat
# Usage: print_indexing_end <count>
print_indexing_end() {
    _ui_is_quiet && return 0
    local count="$1"
    echo "" >&2
    echo -e "${MAGENTA}  ├──────────────────────────────────────────────────┤${NOCOLOR}" >&2
    # Format : "  │  ✅ 9999 fichiers indexés                       │"
    printf "${MAGENTA}  │${NOCOLOR}  ${GREEN}✅ ${WHITE}%4d${GREEN} fichiers indexés${NOCOLOR}                        ${MAGENTA}│${NOCOLOR}\n" "$count" >&2
    echo -e "${MAGENTA}  └──────────────────────────────────────────────────┘${NOCOLOR}" >&2
}

# Affiche un cadre quand l'index existant est conservé
# Usage: print_index_kept <message>
print_index_kept() {
    _ui_is_quiet && return 0
    local message="$1"
    # Compenser les caractères UTF-8 multi-octets (accentués)
    # strlen compte les octets, wc -m compte les caractères visuels
    local byte_len=${#message}
    local char_len=$(printf '%s' "$message" | wc -m)
    local extra=$((byte_len - char_len + 2))
    local width=$((44 + extra))
    
    echo "" >&2
    echo -e "${MAGENTA}  ┌──────────────────────────────────────────────────┐${NOCOLOR}" >&2
    printf "${MAGENTA}  │${NOCOLOR}  ${GREEN}✔${NOCOLOR}  %-${width}s${MAGENTA}│${NOCOLOR}\n" "$message" >&2
    echo -e "${MAGENTA}  └──────────────────────────────────────────────────┘${NOCOLOR}" >&2
}

###########################################################
# RÉSUMÉ FINAL
###########################################################

# Affiche l'en-tête du résumé de conversion
# Usage: print_summary_header
print_summary_header() {
    _ui_is_quiet && return 0
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
    _ui_is_quiet && return 0
    local label="$1"
    local value="$2"
    local color="${3:-$WHITE}"
    # Largeur intérieure totale = 43 colonnes visuelles
    # Format: "  <label><padding><value>  " avec au moins 1 espace entre label et value
    
    local label_cols value_cols total_content_width
    local available_padding content_padding content
    
    label_cols=$(printf '%s' "$label" | wc -m)
    value_cols=$(printf '%s' "$value" | wc -m)
    
    # Contenu sans padding: 2 espaces début + label + value + 2 espaces fin = 4 + label + value
    # Total disponible = 43, donc padding = 43 - 4 - label_cols - value_cols
    total_content_width=$((label_cols + value_cols))
    available_padding=$((39 - total_content_width))
    [[ $available_padding -lt 1 ]] && available_padding=1
    
    content_padding=$(printf '%*s' "$available_padding" '')
    content="  ${label}${content_padding}${value}  "
    
    echo -e "${GREEN}  ║${NOCOLOR}${color}${content}${NOCOLOR}${GREEN}║${NOCOLOR}"
}

# Affiche une valeur seule (sans label) alignée à droite dans le résumé
# Usage: print_summary_value_only "Valeur" [couleur_valeur]
print_summary_value_only() {
    _ui_is_quiet && return 0
    local value="$1"
    local color="${2:-$WHITE}"
    # Largeur intérieure totale = 43 colonnes, valeur alignée à droite avec 2 espaces de marge
    local value_cols value_pad padding content
    
    value_cols=$(printf '%s' "$value" | wc -m)
    value_pad=$((41 - value_cols))
    [[ $value_pad -lt 0 ]] && value_pad=0
    
    padding=$(printf '%*s' "$value_pad" '')
    content="${padding}${value}  "
    
    echo -e "${GREEN}  ║${NOCOLOR}${color}${content}${NOCOLOR}${GREEN}║${NOCOLOR}"
}

# Affiche un séparateur dans le résumé
# Usage: print_summary_separator
print_summary_separator() {
    echo -e "${GREEN}  ╟───────────────────────────────────────────╢${NOCOLOR}"
}

# Affiche un titre de section dans le résumé (ex: ANOMALIE(S))
# Usage: print_summary_section_title "⚠  ANOMALIE(S)  ⚠"
print_summary_section_title() {
    local title="$1"
    local title_cols
    title_cols=$(printf '%s' "$title" | wc -m)
    
    # Centrer le titre dans 43 caractères
    local total_padding=$((43 - title_cols))
    local left_pad=$((total_padding / 2))
    local right_pad=$((total_padding - left_pad))
    
    local left_spaces=$(printf '%*s' "$left_pad" '')
    local right_spaces=$(printf '%*s' "$right_pad" '')
    
    echo -e "${GREEN}  ║${NOCOLOR}${YELLOW}${left_spaces}${title}${right_spaces}${NOCOLOR}${GREEN}║${NOCOLOR}"
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
    _ui_is_quiet && return 0
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

# Note: Les fonctions print_active_options, format_option_*, print_limitation
# sont maintenant dans lib/ui_options.sh

# Affiche le début de la section transfert
# Usage: print_transfer_start [nb_fichiers]
print_transfer_start() {
    local nb_files="${1:-}"
    local subtitle=""
    if [[ -n "$nb_files" ]]; then
        subtitle="$nb_files fichier(s) en attente"
    fi
    print_phase_start "📤 TRANSFERT" "$subtitle" "$CYAN"
}

# Affiche la fin de la section transfert
# Usage: print_transfer_complete
print_transfer_complete() {
    _ui_is_quiet && return 0
    echo ""
    echo -e "${CYAN}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${CYAN}  ┃  ${GREEN}${BOX_CHECK}${NOCOLOR}  ${GREEN}Tous les transferts terminés${NOCOLOR}${CYAN}        ┃${NOCOLOR}"
    echo -e "${CYAN}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
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
    _ui_is_quiet && return 0
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
    
    print_phase_start "🎬 CONVERSION" "$nb_files fichier(s) à traiter" "$BLUE"
    
    if [[ -n "$limitation" ]]; then
        print_limitation "$limitation"
    fi
}

# Affiche la fin de la section conversion
# Usage: print_conversion_complete
print_conversion_complete() {
    _ui_is_quiet && return 0
    echo ""
    echo -e "${BLUE}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NOCOLOR}"
    echo -e "${BLUE}  ┃  ${GREEN}${BOX_CHECK}${NOCOLOR}  ${GREEN}Toutes les conversions terminées${NOCOLOR}${BLUE}    ┃${NOCOLOR}"
    echo -e "${BLUE}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NOCOLOR}"
}

###########################################################
# MESSAGES DE CONVERSION (SKIP / DÉCISION / INFO)
###########################################################

# Génère le préfixe [X/Y] pour les messages si le compteur est disponible
# Usage: _get_counter_prefix
# - Avec limite (-l) : affiche [slot/LIMIT] (commence à 1)
# - Sans limite : affiche [X/Y] avec le total réel
# Retourne une chaîne vide si pas de compteur actif
_get_counter_prefix() {
    local current_num="${CURRENT_FILE_NUMBER:-0}"
    local total_num="${TOTAL_FILES_TO_PROCESS:-0}"
    local limit="${LIMIT_FILES:-0}"

    # Mode random : le "total" est déjà la sélection (ex: 10 fichiers).
    # UX attendue : compteur de position [X/Y], pas une logique de slot/limite.
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        if [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
            echo "${DIM}[${current_num}/${total_num}]${NOCOLOR} "
        fi
        return
    fi
    
    # Mode limite : afficher [slot/LIMIT] uniquement si un slot a été réservé.
    if [[ "$limit" -gt 0 ]]; then
        local slot="${LIMIT_DISPLAY_SLOT:-0}"
        if [[ "$slot" =~ ^[0-9]+$ ]] && [[ "$slot" -gt 0 ]]; then
            echo "${DIM}[${slot}/${limit}]${NOCOLOR} "
        elif [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
            # Fallback (ex: film-adaptive) : le slot est réservé après l'analyse,
            # mais on veut un compteur visible dès le démarrage.
            echo "${DIM}[${current_num}/${total_num}]${NOCOLOR} "
        fi
        return
    fi
    
    # Mode normal : afficher [current/total]
    if [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
        echo "${DIM}[${current_num}/${total_num}]${NOCOLOR} "
    fi
}

# Affichage et logging de la décision de skip
# Usage: print_skip_message <codec> <filename> <file_original>
print_skip_message() {
    local codec="$1"
    local filename="$2"
    local file_original="$3"
    
    local counter_prefix=$(_get_counter_prefix)
    case "$CONVERSION_ACTION" in
        "skip")
            if [[ -z "$codec" ]]; then
                echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (Pas de flux vidéo) : $filename${NOCOLOR}" >&2
                if [[ -n "$LOG_SESSION" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
                fi
            else
                local codec_display="${codec^^}"
                [[ "$codec" == "hevc" || "$codec" == "h265" ]] && codec_display="X265"
                local skip_msg="Déjà ${codec_display} & bitrate optimisé"
                # En mode adaptatif, préciser que c'est par rapport au seuil adaptatif
                if [[ "${ADAPTIVE_COMPLEXITY_MODE:-false}" == true ]]; then
                    skip_msg="Déjà ${codec_display} & bitrate ≤ seuil adaptatif"
                fi
                echo -e "${counter_prefix}${BLUE}⏭️  SKIPPED (${skip_msg}) : $filename${NOCOLOR}" >&2
                if [[ -n "$LOG_SESSION" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (${skip_msg}) | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
                fi
            fi
            ;;
        "video_passthrough")
            # Log discret - le message visible sera affiché après le transfert
            if [[ -n "$LOG_PROGRESS" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | VIDEO_PASSTHROUGH | Audio à optimiser | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
            fi
            ;;
        "full")
            # Détecter si le fichier est dans un codec meilleur/égal mais avec bitrate trop élevé
            local target_codec="${VIDEO_CODEC:-hevc}"
            local is_better_or_equal=false
            if declare -f is_codec_better_or_equal &>/dev/null; then
                is_codec_better_or_equal "$codec" "$target_codec" && is_better_or_equal=true
            fi
            
            if [[ "$is_better_or_equal" == true && -n "$LOG_PROGRESS" ]]; then
                local codec_display="${codec^^}"
                [[ "$codec" == "hevc" || "$codec" == "h265" ]] && codec_display="X265"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING (Ré-encodage ${codec_display}) | Bitrate trop élevé | $file_original" >> "$LOG_PROGRESS" 2>/dev/null || true
            fi
            ;;
    esac
}

# Affiche que la conversion est requise (mode adaptatif)
# Usage: print_conversion_required <v_codec> <v_bitrate_bits>
print_conversion_required() {
    local v_codec="$1"
    local v_bitrate_bits="$2"

    [[ "${UI_QUIET:-false}" == true ]] && return 0
    [[ "${NO_PROGRESS:-false}" == true ]] && return 0

    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        echo -e "${CYAN}  ⚠ Conversion requise : audio à optimiser (vidéo conservée)${NOCOLOR}" >&2
        return 0
    fi

    if [[ ! "$v_bitrate_bits" =~ ^[0-9]+$ ]] || [[ "$v_bitrate_bits" -le 0 ]]; then
        echo -e "${CYAN}  ⚠ Conversion requise${NOCOLOR}" >&2
        return 0
    fi

    local src_kbps=$(( v_bitrate_bits / 1000 ))
    local threshold_bits="${SKIP_THRESHOLD_MAX_TOLERATED_BITS:-0}"
    local threshold_kbps=0
    if [[ "$threshold_bits" =~ ^[0-9]+$ ]] && [[ "$threshold_bits" -gt 0 ]]; then
        threshold_kbps=$(( threshold_bits / 1000 ))
    fi

    local cmp_codec="${SKIP_THRESHOLD_CODEC:-$v_codec}"
    local cmp_display="${cmp_codec^^}"
    [[ "$cmp_codec" == "hevc" || "$cmp_codec" == "h265" ]] && cmp_display="X265"

    local src_display="${v_codec^^}"
    [[ "$v_codec" == "hevc" || "$v_codec" == "h265" ]] && src_display="X265"
    [[ "$v_codec" == "av1" ]] && src_display="AV1"

    local effective_codec="${EFFECTIVE_VIDEO_CODEC:-${VIDEO_CODEC:-hevc}}"
    local target_codec="${VIDEO_CODEC:-hevc}"

    local target_display="${target_codec^^}"
    [[ "$target_codec" == "hevc" || "$target_codec" == "h265" ]] && target_display="X265"
    [[ "$target_codec" == "av1" ]] && target_display="AV1"

    local is_better_or_equal=false
    if declare -f is_codec_better_or_equal &>/dev/null; then
        is_codec_better_or_equal "$v_codec" "$target_codec" && is_better_or_equal=true
    fi

    if [[ -n "$threshold_kbps" && "$threshold_kbps" -gt 0 ]]; then
        if [[ "$is_better_or_equal" != true ]]; then
            # Source dans un codec moins efficace : la conversion est requise pour changer de codec
            # (le seuil skip n'est pas pertinent dans ce cas).
            echo -e "${CYAN}  ⚠ Conversion requise : codec source ${src_display} → ${target_display} (bitrate ${src_kbps}k)${NOCOLOR}" >&2
        else
            # Source déjà dans un codec meilleur/égal : la conversion est requise car le bitrate est trop élevé.
            if [[ "$effective_codec" != "$target_codec" ]]; then
                echo -e "${CYAN}  ⚠ Conversion requise : bitrate ${src_kbps}k (${src_display}) > seuil de conservation ${threshold_kbps}k (${cmp_display}) → pas de downgrade (encodage ${effective_codec^^})${NOCOLOR}" >&2
            else
                echo -e "${CYAN}  ⚠ Conversion requise : bitrate ${src_kbps}k (${src_display}) > seuil de conservation ${threshold_kbps}k (${cmp_display})${NOCOLOR}" >&2
            fi
        fi
    else
        echo -e "${CYAN}  ⚠ Conversion requise${NOCOLOR}" >&2
    fi
}

# Affiche que la conversion n'est pas requise (mode adaptatif, après analyse)
# Usage: print_conversion_not_required
print_conversion_not_required() {
    [[ "${UI_QUIET:-false}" == true ]] && return 0
    [[ "${NO_PROGRESS:-false}" == true ]] && return 0

    echo -e "${CYAN}  ✅ Pas de conversion nécessaire${NOCOLOR}" >&2
}

###########################################################
# HELPERS AFFICHAGE CONVERSION INFO
###########################################################

# Affiche l'info de downscale si activé
# Usage: _print_downscale_info <v_width> <v_height>
_print_downscale_info() {
    local v_width="$1"
    local v_height="$2"
    
    if declare -f _build_downscale_filter_if_needed &>/dev/null; then
        local downscale_filter
        downscale_filter=$(_build_downscale_filter_if_needed "$v_width" "$v_height")
        if [[ -n "$downscale_filter" ]]; then
            echo -e "${CYAN}  ⬇️  Downscale activé : ${v_width}x${v_height} → Max ${DOWNSCALE_MAX_WIDTH}x${DOWNSCALE_MAX_HEIGHT}${NOCOLOR}"
            return 0
        fi
    fi
    return 1
}

# Affiche l'info 10-bit si activé
# Usage: _print_10bit_info <v_pix_fmt>
_print_10bit_info() {
    local v_pix_fmt="$1"
    
    if declare -f _select_output_pix_fmt &>/dev/null; then
        local output_pix_fmt
        output_pix_fmt=$(_select_output_pix_fmt "$v_pix_fmt")
        if [[ -n "$v_pix_fmt" && "$output_pix_fmt" == "yuv420p10le" ]]; then
            echo -e "${CYAN}  🎨 Sortie 10-bit activée${NOCOLOR}"
            return 0
        fi
    fi
    return 1
}

# Affiche l'info audio multicanal
# Usage: _print_audio_multichannel_info <channels>
_print_audio_multichannel_info() {
    local channels="$1"
    
    if [[ -n "$channels" && "$channels" =~ ^[0-9]+$ ]] && declare -f _is_audio_multichannel &>/dev/null; then
        if _is_audio_multichannel "$channels"; then
            if [[ "${AUDIO_FORCE_STEREO:-false}" == true ]]; then
                echo -e "${CYAN}  🔊 Audio multicanal (${channels}ch) → Downmix stéréo${NOCOLOR}"
            else
                if [[ "$channels" -gt 6 ]]; then
                    echo -e "${CYAN}  🔊 Audio multicanal (${channels}ch) → Downmix 7.1 → 5.1${NOCOLOR}"
                else
                    echo -e "${CYAN}  🔊 Audio multicanal 5.1 (${channels}ch) → Layout conservé (pas de downmix stéréo)${NOCOLOR}"
                fi
            fi
            return 0
        fi
    fi
    return 1
}

# Affiche le résumé de conversion audio
# Usage: _print_audio_conversion_summary <tmp_input> <a_codec> <a_bitrate> <channels>
_print_audio_conversion_summary() {
    local tmp_input="$1"
    local a_codec="$2"
    local a_bitrate="$3"
    local channels="$4"
    
    if ! declare -f _get_smart_audio_decision &>/dev/null; then
        return 1
    fi
    if [[ -z "$channels" ]] || ! [[ "$channels" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    local audio_decision action effective_codec target_bitrate reason
    audio_decision=$(_get_smart_audio_decision "$tmp_input" "$a_codec" "$a_bitrate" "$channels")
    IFS='|' read -r action effective_codec target_bitrate reason <<< "$audio_decision"

    local show_audio_summary=false
    if [[ "$action" != "copy" ]]; then
        show_audio_summary=true
    elif [[ "${AUDIO_FORCE_STEREO:-false}" == true && "$channels" -ge 6 ]]; then
        show_audio_summary=true
    fi

    if [[ "$show_audio_summary" == true ]]; then
        local layout=""
        if declare -f _get_target_audio_layout &>/dev/null; then
            layout=$(_get_target_audio_layout "$channels")
        else
            if [[ "${AUDIO_FORCE_STEREO:-false}" == true ]]; then
                layout="stereo"
            else
                layout=$([[ "$channels" -ge 6 ]] && echo "5.1" || echo "stereo")
            fi
        fi

        local codec_label="${effective_codec^^}"
        [[ "$effective_codec" == "eac3" ]] && codec_label="EAC3"
        [[ "$effective_codec" == "aac" ]] && codec_label="AAC"
        [[ "$effective_codec" == "opus" ]] && codec_label="OPUS"

        if [[ -n "$target_bitrate" && "$target_bitrate" =~ ^[0-9]+$ ]] && [[ "$target_bitrate" -gt 0 ]]; then
            echo -e "${CYAN}  🎧 Conversion audio vers ${codec_label} ${target_bitrate}k (${layout})${NOCOLOR}"
        else
            echo -e "${CYAN}  🎧 Conversion audio vers ${codec_label} (${layout})${NOCOLOR}"
        fi
        return 0
    fi
    return 1
}

# Affiche les messages informatifs avant la conversion (codec, bitrate, downscale/10-bit, audio).
# Usage: print_conversion_info <v_codec> <tmp_input> <v_width> <v_height> <v_pix_fmt> <a_codec> <a_bitrate>
# Effets de bord: echo vers stdout
print_conversion_info() {
    local v_codec="$1"
    local tmp_input="$2"
    local v_width="${3:-}"
    local v_height="${4:-}"
    local v_pix_fmt="${5:-}"
    local a_codec="${6:-}"
    local a_bitrate="${7:-}"

    [[ "$NO_PROGRESS" == true ]] && return 0

    local codec_display="${v_codec^^}"
    [[ "$v_codec" == "hevc" || "$v_codec" == "h265" ]] && codec_display="X265"
    [[ "$v_codec" == "av1" ]] && codec_display="AV1"

    if [[ "${CONVERSION_ACTION:-full}" == "video_passthrough" ]]; then
        echo -e "${CYAN}  📋 Codec vidéo déjà optimisé → Conversion audio seule${NOCOLOR}"
    else
        local target_codec="${VIDEO_CODEC:-hevc}"
        if declare -f is_codec_better_or_equal &>/dev/null && is_codec_better_or_equal "$v_codec" "$target_codec"; then
            echo -e "${CYAN}  🎯 Codec ${codec_display} optimal → Limitation du bitrate${NOCOLOR}"
        fi
    fi

    # Affichage downscale + 10-bit (uniquement si on encode la vidéo)
    if [[ "${CONVERSION_ACTION:-full}" != "video_passthrough" ]]; then
        _print_downscale_info "$v_width" "$v_height" && VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=true
        _print_10bit_info "$v_pix_fmt" && VIDEO_PRECONVERSION_VIDEOINFO_SHOWN=true
    fi

    # Probe canaux audio (une fois) sur le fichier local
    local channels=""
    if declare -f _probe_audio_channels &>/dev/null; then
        local channel_info
        channel_info=$(_probe_audio_channels "$tmp_input")
        channels=$(echo "$channel_info" | cut -d'|' -f1)
    fi

    # Info audio multicanal
    _print_audio_multichannel_info "$channels"

    # Résumé audio effectif
    _print_audio_conversion_summary "$tmp_input" "$a_codec" "$a_bitrate" "$channels"
}
