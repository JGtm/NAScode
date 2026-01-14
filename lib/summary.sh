#!/bin/bash
###########################################################
# RÉSUMÉ FINAL
# Affichage du résumé de conversion et calculs de statistiques
# Extrait de finalize.sh pour modularité
###########################################################

###########################################################
# FONCTIONS UTILITAIRES POUR LE RÉSUMÉ
###########################################################

# Compte les occurrences d'un pattern dans le log de session
# Usage: _count_log_pattern <pattern> [flags]
# Retourne 0 si pas de log ou pattern non trouvé
_count_log_pattern() {
    local pattern="$1"
    local flags="${2:-}"
    local count=0
    
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        if [[ -n "$flags" ]]; then
            count=$(grep -c"$flags" "$pattern" "$LOG_SESSION" 2>/dev/null || true)
        else
            count=$(grep -c "$pattern" "$LOG_SESSION" 2>/dev/null || true)
        fi
        count=$(echo "${count:-0}" | tr -d '[:space:]')
    fi
    [[ -z "$count" ]] && count=0
    echo "$count"
}

# Formate une taille en octets en format lisible (Ko, Mo, Go)
# Usage: _format_size_bytes <bytes>
_format_size_bytes() {
    local bytes="${1:-0}"
    
    if [[ "$bytes" -ge 1073741824 ]]; then
        # Go
        awk "BEGIN {printf \"%.2f Go\", $bytes / 1073741824}"
    elif [[ "$bytes" -ge 1048576 ]]; then
        # Mo
        awk "BEGIN {printf \"%.2f Mo\", $bytes / 1048576}"
    elif [[ "$bytes" -ge 1024 ]]; then
        # Ko
        awk "BEGIN {printf \"%.2f Ko\", $bytes / 1024}"
    else
        echo "${bytes} octets"
    fi
}

# Formate une taille en format compact (ex: 4.3G, 850M, 12K)
# Usage: _format_size_bytes_compact <bytes>
_format_size_bytes_compact() {
    local bytes="${1:-0}"
    
    if [[ "$bytes" -ge 1073741824 ]]; then
        awk "BEGIN {printf \"%.1fG\", $bytes / 1073741824}"
    elif [[ "$bytes" -ge 1048576 ]]; then
        awk "BEGIN {printf \"%.0fM\", $bytes / 1048576}"
    elif [[ "$bytes" -ge 1024 ]]; then
        awk "BEGIN {printf \"%.0fK\", $bytes / 1024}"
    else
        echo "${bytes}B"
    fi
}

# Supprime les séquences ANSI (couleurs / contrôles) d'un flux texte.
# Usage: some_cmd | _strip_ansi_stream
_strip_ansi_stream() {
    # Regex ANSI assez large (CSI) : ESC [ ... @-~
    # Compatible awk GNU/macOS (mawk/gawk).
    awk '{ gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/, ""); print }'
}

# Calcule les économies d'espace à partir des fichiers de taille totale
# Retourne: show|line1|line2 où show=true/false
_calculate_space_savings() {
    # Note: N'est pas calculé en mode sample ou dry-run (pas représentatif)
    if [[ "${SAMPLE_MODE:-false}" == true ]] || [[ "${DRYRUN:-false}" == true ]]; then
        echo "false||"
        return
    fi
    
    if [[ ! -f "${TOTAL_SIZE_BEFORE_FILE:-}" ]] || [[ ! -f "${TOTAL_SIZE_AFTER_FILE:-}" ]]; then
        echo "false||"
        return
    fi
    
    local total_before total_after
    total_before=$(cat "$TOTAL_SIZE_BEFORE_FILE" 2>/dev/null || echo 0)
    total_after=$(cat "$TOTAL_SIZE_AFTER_FILE" 2>/dev/null || echo 0)
    total_before=$(echo "$total_before" | tr -d '[:space:]')
    total_after=$(echo "$total_after" | tr -d '[:space:]')
    [[ -z "$total_before" ]] && total_before=0
    [[ -z "$total_after" ]] && total_after=0
    
    if [[ "$total_before" -le 0 ]] || [[ "$total_after" -le 0 ]]; then
        echo "false||"
        return
    fi
    
    local space_saved
    space_saved=$((total_before - total_after))
    local before_fmt
    before_fmt=$(_format_size_bytes "$total_before")
    local after_fmt
    after_fmt=$(_format_size_bytes "$total_after")
    local line1="${before_fmt} → ${after_fmt}"
    local line2=""
    
    if [[ "$space_saved" -ge 0 ]]; then
        local saved_fmt
        saved_fmt=$(_format_size_bytes "$space_saved")
        local savings_percent=""
        if [[ "$total_before" -gt 0 ]]; then
            savings_percent=$(awk "BEGIN {printf \"%.1f\", ($space_saved / $total_before) * 100}")
        fi
        line2="(−${saved_fmt}, ${savings_percent}%)"
    else
        # Cas rare : fichiers plus gros après conversion
        local increase_fmt
        increase_fmt=$(_format_size_bytes "$((-space_saved))")
        line2="(+${increase_fmt})"
    fi
    
    echo "true|${line1}|${line2}"
}

###########################################################
# AFFICHAGE DU RÉSUMÉ FINAL
###########################################################

show_summary() {
    # Traiter toutes les analyses VMAF en attente
    process_vmaf_queue

    _get_term_cols() {
        local cols="${COLUMNS:-}"
        if [[ -n "$cols" ]] && [[ "$cols" =~ ^[0-9]+$ ]]; then
            echo "$cols"
            return 0
        fi
        if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
            cols=$(tput cols 2>/dev/null || echo "")
        fi
        [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]] && cols=999
        echo "$cols"
    }

    _render_summary_compact() {
        local end_date="$1"
        local total_elapsed_str="$2"
        local succ="$3"
        local skip="$4"
        local err="$5"
        local size_anomalies="$6"
        local checksum_anomalies="$7"
        local vmaf_anomalies="$8"
        local show_vmaf_anomaly="$9"
        shift 9 || true
        local show_space_savings="$1"
        local line1="$2"
        local line2="$3"

        echo ""
        echo -e "${GREEN}Résumé${NOCOLOR} ${DIM}(${end_date})${NOCOLOR}"
        echo -e "${DIM}Durée:${NOCOLOR} ${CYAN}${total_elapsed_str}${NOCOLOR}"
        echo -e "${DIM}Résultat:${NOCOLOR} ${GREEN}OK=${succ}${NOCOLOR}  ${YELLOW}SKIP=${skip}${NOCOLOR}  ${RED}ERR=${err}${NOCOLOR}"

        local has_any_anomaly=false
        if [[ "$size_anomalies" -gt 0 ]] || [[ "$checksum_anomalies" -gt 0 ]]; then
            has_any_anomaly=true
        fi
        if [[ "${VMAF_ENABLED:-false}" == true ]] && [[ "$vmaf_anomalies" -gt 0 ]]; then
            has_any_anomaly=true
        fi

        if [[ "$has_any_anomaly" == true ]]; then
            echo -e "${YELLOW}Anomalies:${NOCOLOR} taille=${size_anomalies} intégrité=${checksum_anomalies}${NOCOLOR}"${show_vmaf_anomaly:+" vmaf=${vmaf_anomalies}"}
        fi

        if [[ "$show_space_savings" == true ]]; then
            echo -e "${DIM}Espace:${NOCOLOR} ${GREEN}${line1}${NOCOLOR}"
            [[ -n "$line2" ]] && echo -e "${GREEN}${line2}${NOCOLOR}"
        fi
        echo ""
    }

    # Durée totale du traitement
    local total_elapsed_str="N/A"
    if [[ -n "${START_TS_TOTAL:-}" ]] && [[ "${START_TS_TOTAL}" =~ ^[0-9]+$ ]]; then
        local end_ts
        end_ts=$(date +%s)
        local elapsed
        elapsed=$((end_ts - START_TS_TOTAL))
        total_elapsed_str=$(format_duration_seconds "$elapsed")
    fi
    
    # Comptage des statistiques depuis le log de session
    local succ
    succ=$(_count_log_pattern ' | SUCCESS')
    local skip
    skip=$(_count_log_pattern ' | SKIPPED')
    local err
    err=$(_count_log_pattern ' | ERROR ')
    local size_anomalies
    size_anomalies=$(_count_log_pattern 'WARNING: FICHIER PLUS LOURD')
    local checksum_anomalies
    checksum_anomalies=$(_count_log_pattern ' ERROR (MISMATCH|SIZE_MISMATCH|NO_CHECKSUM) ' 'E')
    local vmaf_anomalies
    # VMAF : considérer comme anomalie les scores "DEGRADE" ET les NA.
    # Exemple ligne log: "... | VMAF | ... | score:NA | quality:NA"
    vmaf_anomalies=$(_count_log_pattern ' \| VMAF \| .* \| (score:NA|quality:DEGRADE)' 'E')
    
    # Calcul du gain de place total
    local savings_data line1 line2 show_space_savings
    savings_data=$(_calculate_space_savings)
    IFS='|' read -r show_space_savings line1 line2 <<< "$savings_data"
    
    # Afficher message si aucun fichier traité (queue vide ou tout skippé)
    local total_processed
    total_processed=$((succ + err))
    if [[ "$total_processed" -eq 0 ]]; then
        print_empty_state "Aucun fichier à traiter"
    fi
    
    # Déterminer si on doit afficher la section anomalies
    local has_any_anomaly=false
    local show_vmaf_anomaly=false
    
    if [[ "$size_anomalies" -gt 0 ]] || [[ "$checksum_anomalies" -gt 0 ]]; then
        has_any_anomaly=true
    fi
    
    # VMAF : afficher seulement si activé ET anomalies détectées
    if [[ "${VMAF_ENABLED:-false}" == true ]] && [[ "$vmaf_anomalies" -gt 0 ]]; then
        has_any_anomaly=true
        show_vmaf_anomaly=true
    fi
    
    local end_date
    end_date=$(date +"%Y-%m-%d %H:%M:%S")

    # Écrire des métriques machine-readable (pour notifications Discord)
    # Format: key=value (une ligne par clé)
    if [[ -n "${SUMMARY_METRICS_FILE:-}" ]]; then
        {
            printf 'end_date=%s\n' "$end_date"
            printf 'duration_total=%s\n' "${total_elapsed_str:-}"
            printf 'succ=%s\n' "$succ"
            printf 'skip=%s\n' "$skip"
            printf 'err=%s\n' "$err"
            printf 'size_anomalies=%s\n' "$size_anomalies"
            printf 'checksum_anomalies=%s\n' "$checksum_anomalies"
            printf 'vmaf_anomalies=%s\n' "$vmaf_anomalies"
            printf 'show_vmaf_anomaly=%s\n' "$show_vmaf_anomaly"
            printf 'has_any_anomaly=%s\n' "$has_any_anomaly"
            printf 'show_space_savings=%s\n' "$show_space_savings"
            printf 'space_line1=%s\n' "${line1:-}"
            printf 'space_line2=%s\n' "${line2:-}"
        } > "${SUMMARY_METRICS_FILE}" 2>/dev/null || true
    fi

    local cols
    cols=$(_get_term_cols)
    local compact=false
    [[ "$cols" -lt 80 ]] && compact=true

    if [[ "$compact" == true ]]; then
        _render_summary_compact "$end_date" "$total_elapsed_str" "$succ" "$skip" "$err" "$size_anomalies" "$checksum_anomalies" "$vmaf_anomalies" "$show_vmaf_anomaly" "$show_space_savings" "$line1" "$line2" \
            | tee >(_strip_ansi_stream > "$SUMMARY_FILE")
    else
        {
            print_summary_header
            print_summary_item "Date fin" "$end_date"
            print_summary_item "Durée totale" "${total_elapsed_str}" "$CYAN"
            print_summary_separator
            print_summary_item "Succès" "$succ" "$GREEN"
            print_summary_item "Ignorés" "$skip" "$YELLOW"
            print_summary_item "Erreurs" "$err" "$RED"
            # Section anomalies : intégrée avec titre centré
            if [[ "$has_any_anomaly" == true ]]; then
                print_summary_separator
                print_summary_section_title "⚠  ANOMALIE(S)  ⚠"
                print_summary_separator
                [[ "$size_anomalies" -gt 0 ]] && print_summary_item "Taille" "$size_anomalies" "$YELLOW"
                [[ "$checksum_anomalies" -gt 0 ]] && print_summary_item "Intégrité" "$checksum_anomalies" "$RED"
                [[ "$show_vmaf_anomaly" == true ]] && print_summary_item "VMAF" "$vmaf_anomalies" "$YELLOW"
            fi
            # Afficher le gain de place si disponible (sur deux lignes)
            if [[ "$show_space_savings" == true ]]; then
                print_summary_separator
                print_summary_item "Espace économisé" "$line1" "$GREEN"
                print_summary_value_only "$line2" "$GREEN"
            fi
            print_summary_footer
        } | tee >(_strip_ansi_stream > "$SUMMARY_FILE")
    fi
    
    # Note: Le statut heures creuses est déjà affiché au démarrage (show_off_peak_startup_info)
    # Pas besoin de le réafficher après le résumé final
}
