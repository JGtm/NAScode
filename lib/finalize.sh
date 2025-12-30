#!/bin/bash
###########################################################
# FINALISATION ET RÉSULTATS
###########################################################

###########################################################
# DÉPLACEMENT DU FICHIER CONVERTI
###########################################################

# Essayer de déplacer le fichier produit vers la destination finale.
# Renvoie le chemin réel utilisé pour le fichier final sur stdout.
# Usage : _finalize_try_move <tmp_output> <final_output> <file_original>
_finalize_try_move() {
    local tmp_output="$1"
    local final_output="$2"
    local file_original="$3"

    local max_try="${MOVE_RETRY_MAX_TRY:-3}"
    local retry_sleep="${MOVE_RETRY_SLEEP_SECONDS:-2}"
    local try=0

    # Tentative mv (3 essais)
    while [[ $try -lt $max_try ]]; do
        if mv "$tmp_output" "$final_output" 2>/dev/null; then
            printf "%s" "$final_output"
            return 0
        fi
        try=$((try+1))
        [[ "$retry_sleep" != "0" ]] && sleep "$retry_sleep"
    done

    # Essayer cp + rm (3 essais)
    try=0
    while [[ $try -lt $max_try ]]; do
        if cp "$tmp_output" "$final_output" 2>/dev/null; then
            rm -f "$tmp_output" 2>/dev/null || true
            printf "%s" "$final_output"
            return 0
        fi
        try=$((try+1))
        [[ "$retry_sleep" != "0" ]] && sleep "$retry_sleep"
    done

    # Repli local : dossier fallback
    local local_fallback_dir="${FALLBACK_DIR:-$HOME/Conversion_failed_uploads}"
    mkdir -p "$local_fallback_dir" 2>/dev/null || true
    local fallback_target="$local_fallback_dir/$(basename "$final_output")"
    if mv "$tmp_output" "$fallback_target" 2>/dev/null; then
        printf "%s" "$fallback_target"
        return 1
    fi
    if cp "$tmp_output" "$fallback_target" 2>/dev/null; then
        rm -f "$tmp_output" 2>/dev/null || true
        printf "%s" "$fallback_target"
        return 1
    fi

    # Ultime repli : laisser le temporaire et l'utiliser
    printf "%s" "$tmp_output"
    return 2
}

###########################################################
# VÉRIFICATION D'INTÉGRITÉ ET LOGGING
###########################################################

# Nettoyage local des artefacts temporaires et calculs de taille/checksum.
# Usage : _finalize_log_and_verify <file_original> <final_actual> <tmp_input> <ffmpeg_log_temp> <checksum_before> <size_before_mb> <size_before_bytes> <final_intended> <move_status>
_finalize_log_and_verify() {
    local file_original="$1"
    local final_actual="$2"
    local tmp_input="$3"
    local ffmpeg_log_temp="$4"
    local checksum_before="$5"
    local size_before_mb="$6"
    local size_before_bytes="${7:-0}"
    local final_intended="${8:-}"
    local move_status="${9:-0}"

    # Nettoyer les artefacts temporaires liés à l'entrée et au log ffmpeg
    rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null || true

    # Taille après (en MB et en octets)
    local size_after_mb=0 size_after_bytes=0
    if [[ -e "$final_actual" ]]; then
        size_after_mb=$(du -m "$final_actual" 2>/dev/null | awk '{print $1}') || size_after_mb=0
        # Taille exacte en octets (stat -c%s sur Linux, stat -f%z sur macOS)
        size_after_bytes=$(stat -c%s "$final_actual" 2>/dev/null || stat -f%z "$final_actual" 2>/dev/null || echo 0)
    fi

    local size_comparison="${size_before_mb}MB → ${size_after_mb}MB"

    if [[ "$size_after_mb" -ge "$size_before_mb" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: FICHIER PLUS LOURD ($size_comparison). | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        fi
    fi

    # Si le transfert ne s'est pas fait vers la destination prévue, le signaler comme erreur.
    # move_status: 0=OK vers destination, 1=fallback, 2=échec (temporaire)
    if [[ "$move_status" != "0" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            local intended_msg="${final_intended:-$final_actual}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR TRANSFER_FALLBACK | $file_original -> $intended_msg | actual:$final_actual | move_status:$move_status" >> "$LOG_SESSION" 2>/dev/null || true
        fi
    fi

    # Log success (conversion OK) — même si le transfert a dû passer par un fallback, on garde la trace.
    if [[ -n "$LOG_SESSION" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file_original → $final_actual | $size_comparison" >> "$LOG_SESSION" 2>/dev/null || true
    fi

    # Vérification d'intégrité : d'abord comparer la taille exacte (rapide), puis checksum si nécessaire
    local verify_status="OK"
    local checksum_after=""
    
    # Nettoyer le checksum_before (supprimer espaces/newlines parasites)
    checksum_before="${checksum_before//[$'\n\r\t ']/}"
    
    if [[ ! -e "$final_actual" ]]; then
        verify_status="TRANSFER_FAILED"
    elif [[ "$size_before_bytes" -gt 0 && "$size_after_bytes" -gt 0 && "$size_before_bytes" -ne "$size_after_bytes" ]]; then
        # Taille différente = transfert incomplet ou corrompu
        verify_status="SIZE_MISMATCH"
    elif [[ -n "$checksum_before" ]]; then
        # Taille identique, vérifier le checksum
        checksum_after=$(compute_sha256 "$final_actual" 2>/dev/null || echo "")
        # Nettoyer le checksum_after également
        checksum_after="${checksum_after//[$'\n\r\t ']/}"
        if [[ -z "$checksum_after" ]]; then
            verify_status="NO_CHECKSUM"
        elif [[ "$checksum_before" != "$checksum_after" ]]; then
            verify_status="MISMATCH"
        fi
    elif [[ -z "$checksum_before" ]]; then
        verify_status="SKIPPED"
    fi

    # Écrire uniquement dans les logs : VERIFY
    if [[ -n "$LOG_SESSION" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | VERIFY | $file_original → $final_actual | size:${size_before_bytes}B->${size_after_bytes}B | checksum:${checksum_before:-NA}/${checksum_after:-NA} | status:${verify_status}" >> "$LOG_SESSION" 2>/dev/null || true
    fi

    # Enregistrer pour analyse VMAF ultérieure (sera traité après toutes les conversions)
    if declare -f _queue_vmaf_analysis &>/dev/null; then
        _queue_vmaf_analysis "$file_original" "$final_actual"
    fi

    # En cas de problème, journaliser dans le log d'erreur
    if [[ "$verify_status" != "OK" && "$verify_status" != "SKIPPED" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ${verify_status} | $file_original -> $final_actual | size:${size_before_bytes}B->${size_after_bytes}B | checksum:${checksum_before:-NA}/${checksum_after:-NA}" >> "$LOG_SESSION" 2>/dev/null || true
        fi
    fi

    # --- Comptabiliser les gains de place (uniquement si conversion réussie) ---
    # Note: size_before_mb vient du fichier original, size_after_bytes du fichier converti
    if [[ "$verify_status" == "OK" || "$verify_status" == "SKIPPED" ]] && [[ -e "$final_actual" ]]; then
        # Taille originale en octets (convertir depuis MB ou recalculer si le fichier existe encore)
        local original_size_bytes=0
        if [[ -e "$file_original" ]]; then
            original_size_bytes=$(stat -c%s "$file_original" 2>/dev/null || stat -f%z "$file_original" 2>/dev/null || echo 0)
        else
            # Fichier original supprimé, estimer depuis size_before_mb
            original_size_bytes=$((size_before_mb * 1024 * 1024))
        fi
        
        # Incrémenter les compteurs atomiquement (flock pour éviter race conditions en parallèle)
        if [[ -n "${TOTAL_SIZE_BEFORE_FILE:-}" ]] && [[ -f "$TOTAL_SIZE_BEFORE_FILE" ]]; then
            (
                flock -x 200
                local current
                current=$(cat "$TOTAL_SIZE_BEFORE_FILE" 2>/dev/null || echo 0)
                echo $((current + original_size_bytes)) > "$TOTAL_SIZE_BEFORE_FILE"
            ) 200>"${TOTAL_SIZE_BEFORE_FILE}.lock" 2>/dev/null || true
        fi
        
        if [[ -n "${TOTAL_SIZE_AFTER_FILE:-}" ]] && [[ -f "$TOTAL_SIZE_AFTER_FILE" ]]; then
            (
                flock -x 200
                local current
                current=$(cat "$TOTAL_SIZE_AFTER_FILE" 2>/dev/null || echo 0)
                echo $((current + size_after_bytes)) > "$TOTAL_SIZE_AFTER_FILE"
            ) 200>"${TOTAL_SIZE_AFTER_FILE}.lock" 2>/dev/null || true
        fi
    fi
    
    return 0
}

###########################################################
# FINALISATION CONVERSION SUCCÈS
###########################################################

# Fonction principale de finalisation (regroupe l'affichage, le déplacement, le logging)
# Le transfert est lancé en arrière-plan pour ne pas bloquer les conversions suivantes
_finalize_conversion_success() {
    local filename="$1"
    local file_original="$2"
    local tmp_input="$3"
    local tmp_output="$4"
    local final_output="$5"
    local ffmpeg_log_temp="$6"
    local size_before_mb="$7"

    # Si un marqueur d'arrêt global existe, ne pas finaliser normalement.
    # IMPORTANT: On garde tmp_output si le fichier existe pour ne pas perdre le travail.
    # Le fichier sera nettoyé au prochain lancement ou manuellement récupéré.
    if [[ -f "$STOP_FLAG" ]]; then
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null || true
        # Avertir si un fichier converti risque d'être perdu
        if [[ -f "$tmp_output" ]]; then
            echo -e "  ${YELLOW}⚠️  Conversion interrompue, fichier temporaire conservé: $tmp_output${NOCOLOR}" >&2
            # Log pour récupération manuelle si besoin
            if [[ -n "$LOG_SESSION" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | INTERRUPTED | $file_original -> $tmp_output (fichier temp conservé)" >> "$LOG_SESSION" 2>/dev/null || true
            fi
        fi
        return 1
    fi

    if [[ "$NO_PROGRESS" != true ]]; then
        # Calculer la durée écoulée depuis le début de la conversion (START_TS défini avant l'appel à ffmpeg)
        local elapsed_str="N/A"
        local elapsed_display="N/A"
        local start_for_file="${FILE_START_TS:-${START_TS:-}}"
        if [[ -n "${start_for_file:-}" ]] && [[ "${start_for_file}" =~ ^[0-9]+$ ]]; then
            local end_ts
            end_ts=$(date +%s)
            local elapsed=$((end_ts - start_for_file))
            local eh=$((elapsed / 3600))
            local em=$(((elapsed % 3600) / 60))
            local es=$((elapsed % 60))
            elapsed_str=$(printf "%02d:%02d:%02d" "$eh" "$em" "$es")

            if [[ "$eh" -gt 0 ]]; then
                elapsed_display="${eh}h${em}m${es}s"
            else
                elapsed_display="${em}m${es}s"
            fi
        fi

        local display_name
        display_name="$(basename "${final_output:-$filename}")"

        # Tronquer comme ailleurs (ex: VMAF) : 30 caractères max.
        local display_name_trunc="$display_name"
        if [[ ${#display_name_trunc} -gt 30 ]]; then
            display_name_trunc="${display_name_trunc:0:27}..."
        fi

        local size_part=""
        if [[ "${SAMPLE_MODE:-false}" != true ]]; then
            local before_bytes after_bytes
            before_bytes=0
            after_bytes=0

            if [[ -e "$file_original" ]]; then
                before_bytes=$(stat -c%s "$file_original" 2>/dev/null || stat -f%z "$file_original" 2>/dev/null || echo 0)
            elif [[ -n "${size_before_mb:-}" ]] && [[ "${size_before_mb}" =~ ^[0-9]+$ ]]; then
                before_bytes=$((size_before_mb * 1024 * 1024))
            fi

            if [[ -e "$tmp_output" ]]; then
                after_bytes=$(stat -c%s "$tmp_output" 2>/dev/null || stat -f%z "$tmp_output" 2>/dev/null || echo 0)
            fi

            local before_fmt after_fmt
            before_fmt=$(_format_size_bytes_compact "$before_bytes")
            after_fmt=$(_format_size_bytes_compact "$after_bytes")
            size_part=" | ${before_fmt} → ${after_fmt}"
        fi

        echo -e "  ${GREEN}✅ ${display_name_trunc} | Terminé en ${elapsed_display}${size_part}${NOCOLOR}"
    fi

    # Vérifier que le fichier de sortie temporaire existe
    if [[ ! -f "$tmp_output" ]]; then
        echo -e "  ${RED}❌ ERREUR: Fichier temporaire introuvable après encodage: $tmp_output${NOCOLOR}" >&2
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR MISSING_OUTPUT | $file_original -> $tmp_output (fichier temp absent)" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null || true
        return 1
    fi

    # checksum et taille exacte avant déplacement (pour vérification intégrité)
    local checksum_before size_before_bytes
    checksum_before=$(compute_sha256 "$tmp_output" 2>/dev/null || echo "")
    size_before_bytes=$(stat -c%s "$tmp_output" 2>/dev/null || stat -f%z "$tmp_output" 2>/dev/null || echo 0)

    # Vérifier si le système de transfert asynchrone est initialisé
    if [[ -n "${TRANSFER_PIDS_FILE:-}" ]] && declare -f start_async_transfer &>/dev/null; then
        # Attendre qu'un slot de transfert soit disponible (max 2 simultanés)
        wait_for_transfer_slot
        
        # Préparer les données de callback pour le transfert asynchrone
        # Format: checksum_before|size_before_mb|size_before_bytes|tmp_input|ffmpeg_log_temp
        local callback_data="${checksum_before}|${size_before_mb}|${size_before_bytes}|${tmp_input}|${ffmpeg_log_temp}"
        
        # Lancer le transfert en arrière-plan
        start_async_transfer "$tmp_output" "$final_output" "$file_original" "$callback_data"
    else
        # Mode synchrone (fallback si transfert asynchrone non initialisé)
        # Déplacer / copier / fallback et récupérer le chemin réel
        local final_actual move_status
        final_actual=$(_finalize_try_move "$tmp_output" "$final_output" "$file_original")
        move_status=$?

        # Nettoyage, logs et vérifications
        _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "$checksum_before" "$size_before_mb" "$size_before_bytes" "$final_output" "$move_status"
    fi
}

###########################################################
# FINALISATION CONVERSION ERREUR
###########################################################

_finalize_conversion_error() {
    local filename="$1"
    local file_original="$2"
    local tmp_input="$3"
    local tmp_output="$4"
    local ffmpeg_log_temp="$5"
    
    if [[ ! -f "$STOP_FLAG" ]]; then
        if [[ "$NO_PROGRESS" != true ]]; then
            echo -e "  ${RED}❌ Échec de la conversion : $filename${NOCOLOR}"
        fi
    fi
    if [[ -n "$LOG_SESSION" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_SESSION" 2>/dev/null || true
        if [[ -n "$ffmpeg_log_temp" ]] && [[ -f "$ffmpeg_log_temp" ]] && [[ -s "$ffmpeg_log_temp" ]]; then
            cat "$ffmpeg_log_temp" >> "$LOG_SESSION" 2>/dev/null || true
        else
            echo "(Log d'erreur : ffmpeg_log_temp='$ffmpeg_log_temp' exists=$([ -f "$ffmpeg_log_temp" ] && echo 'OUI' || echo 'NON'))" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        echo "-------------------------------" >> "$LOG_SESSION" 2>/dev/null || true
    fi
    rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
}

###########################################################
# AFFICHAGE DU RÉSUMÉ FINAL
###########################################################

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

show_summary() {
    # Traiter toutes les analyses VMAF en attente
    process_vmaf_queue

    # Durée totale du traitement
    local total_elapsed_str="N/A"
    if [[ -n "${START_TS_TOTAL:-}" ]] && [[ "${START_TS_TOTAL}" =~ ^[0-9]+$ ]]; then
        local end_ts
        end_ts=$(date +%s)
        local elapsed=$((end_ts - START_TS_TOTAL))
        local eh=$((elapsed / 3600))
        local em=$(((elapsed % 3600) / 60))
        local es=$((elapsed % 60))
        total_elapsed_str=$(printf "%02d:%02d:%02d" "$eh" "$em" "$es")
    fi
    
    local succ=0
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        succ=$(grep -c ' | SUCCESS' "$LOG_SESSION" 2>/dev/null || true)
        succ=$(echo "${succ:-0}" | tr -d '[:space:]')
        [[ -z "$succ" ]] && succ=0
    fi

    local skip=0
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        skip=$(grep -c ' | SKIPPED' "$LOG_SESSION" 2>/dev/null || true)
        skip=$(echo "${skip:-0}" | tr -d '[:space:]')
        [[ -z "$skip" ]] && skip=0
    fi

    local err=0
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        err=$(grep -c ' | ERROR ' "$LOG_SESSION" 2>/dev/null || true)
        err=$(echo "${err:-0}" | tr -d '[:space:]')
        [[ -z "$err" ]] && err=0
    fi

    # Anomalies : fichiers plus lourds après conversion
    local size_anomalies=0
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        size_anomalies=$(grep -c 'WARNING: FICHIER PLUS LOURD' "$LOG_SESSION" 2>/dev/null | tr -d '\r\n') || size_anomalies=0
    fi

    # Anomalies : erreurs de vérification checksum/taille lors du transfert
    local checksum_anomalies=0
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        checksum_anomalies=$(grep -cE ' ERROR (MISMATCH|SIZE_MISMATCH|NO_CHECKSUM) ' "$LOG_SESSION" 2>/dev/null | tr -d '\r\n') || checksum_anomalies=0
    fi

    # Anomalies VMAF : fichiers avec qualité dégradée (score < 70)
    local vmaf_anomalies=0
    if [[ -f "$LOG_SESSION" && -s "$LOG_SESSION" ]]; then
        vmaf_anomalies=$(grep -c ' | VMAF | .* | quality:DEGRADE' "$LOG_SESSION" 2>/dev/null | tr -d '\r\n') || vmaf_anomalies=0
    fi
    
    # Calcul du gain de place total
    # Note: N'est pas affiché en mode sample ou dry-run (pas représentatif)
    local total_before=0 total_after=0 space_saved=0 
    local space_saved_line1="" space_saved_line2=""
    local show_space_savings=false
    
    if [[ "${SAMPLE_MODE:-false}" != true ]] && [[ "${DRYRUN:-false}" != true ]]; then
        if [[ -f "${TOTAL_SIZE_BEFORE_FILE:-}" ]] && [[ -f "${TOTAL_SIZE_AFTER_FILE:-}" ]]; then
            total_before=$(cat "$TOTAL_SIZE_BEFORE_FILE" 2>/dev/null || echo 0)
            total_after=$(cat "$TOTAL_SIZE_AFTER_FILE" 2>/dev/null || echo 0)
            total_before=$(echo "$total_before" | tr -d '[:space:]')
            total_after=$(echo "$total_after" | tr -d '[:space:]')
            [[ -z "$total_before" ]] && total_before=0
            [[ -z "$total_after" ]] && total_after=0
            
            if [[ "$total_before" -gt 0 ]] && [[ "$total_after" -gt 0 ]]; then
                space_saved=$((total_before - total_after))
                local before_fmt=$(_format_size_bytes "$total_before")
                local after_fmt=$(_format_size_bytes "$total_after")
                local saved_fmt=$(_format_size_bytes "$space_saved")
                # Calculer le pourcentage d'économie
                local savings_percent=""
                if [[ "$total_before" -gt 0 ]]; then
                    savings_percent=$(awk "BEGIN {printf \"%.1f\", ($space_saved / $total_before) * 100}")
                fi
                if [[ "$space_saved" -ge 0 ]]; then
                    # Ligne 1: tailles avant → après
                    space_saved_line1="${before_fmt} → ${after_fmt}"
                    # Ligne 2: économie (alignée à droite)
                    space_saved_line2="(−${saved_fmt}, ${savings_percent}%)"
                else
                    # Cas rare : fichiers plus gros après conversion
                    local increase_fmt=$(_format_size_bytes "$((-space_saved))")
                    space_saved_line1="${before_fmt} → ${after_fmt}"
                    space_saved_line2="(+${increase_fmt})"
                fi
                show_space_savings=true
            fi
        fi
    fi
    
    # Afficher message si aucun fichier traité (queue vide ou tout skippé)
    # Spécification: si tout est skippé, on dit aussi "Aucun fichier à traiter".
    local total_processed=$((succ + err))
    if [[ "$total_processed" -eq 0 ]]; then
        print_empty_state "Aucun fichier à traiter"
    fi
    
    # Déterminer si on doit afficher la section anomalies
    # - Anomalies VMAF : seulement si VMAF est activé ET il y a des anomalies
    # - Autres anomalies : seulement si > 0
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
    
    {
        print_summary_header
        print_summary_item "Date fin" "$(date +"%Y-%m-%d %H:%M:%S")"
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
            print_summary_item "Espace économisé" "$space_saved_line1" "$GREEN"
            print_summary_value_only "$space_saved_line2" "$GREEN"
        fi
        print_summary_footer
    } | tee "$SUMMARY_FILE"
    
    # Afficher le résumé des heures creuses si activé
    if [[ "${OFF_PEAK_ENABLED:-false}" == true ]]; then
        echo ""
        show_off_peak_status
    fi
}

###########################################################
# DRY RUN AVANCÉ (Comparaison et Anomalies de nommage)
###########################################################

dry_run_compare_names() {
    local TTY_DEV="/dev/tty"
    local LOG_FILE="$LOG_DRYRUN_COMPARISON"

    ask_question "Afficher la comparaison des noms de fichiers originaux et générés ?"
    read -r response
    
    case "$response" in
        [oO]|[yY]|'')
            {
                print_header "SIMULATION DES NOMS DE FICHIERS"
            } | tee -a "$LOG_FILE"
            
            local total_files=$(count_null_separated "$QUEUE")
            local count=0
            local anomaly_count=0
            
            while IFS= read -r -d $'\0' file_original; do
                local filename_raw=$(basename "$file_original")
                local filename=$(echo "$filename_raw" | tr -d '\r\n')
                local base_name="${filename%.*}"
                
                local relative_path="${file_original#$SOURCE}"
                relative_path="${relative_path#/}"
                local relative_dir=$(dirname "$relative_path")
                local final_dir="$OUTPUT_DIR/$relative_dir"

                # Suffixe effectif (par fichier) : inclut bitrate adapté + résolution.
                # Fallback : si les fonctions ne sont pas chargées, on garde SUFFIX_STRING.
                local effective_suffix="$SUFFIX_STRING"
                if [[ -n "$SUFFIX_STRING" ]] && declare -f get_video_stream_props &>/dev/null && declare -f _build_effective_suffix_for_dims &>/dev/null; then
                    local stream_props
                    stream_props=$(get_video_stream_props "$file_original")
                    local input_width input_height _pix_fmt
                    IFS='|' read -r input_width input_height _pix_fmt <<< "$stream_props"
                    effective_suffix=$(_build_effective_suffix_for_dims "$input_width" "$input_height")
                fi

                if [[ "$DRYRUN" == true ]]; then
                    effective_suffix="${effective_suffix}${DRYRUN_SUFFIX}"
                fi

                local final_output="$final_dir/${base_name}${effective_suffix}.mkv"
                local final_output_basename=$(basename "$final_output")

                # --- PRÉPARATION POUR LA VÉRIFICATION D'ANOMALIE ---
                local generated_base_name="${final_output_basename%.mkv}"
                
                # 1. RETRAIT DU SUFFIXE DRY RUN (toujours en premier car il est le dernier ajouté)
                if [[ "$DRYRUN" == true ]]; then
                    generated_base_name="${generated_base_name%"$DRYRUN_SUFFIX"}"
                fi
                
                # 2. RETRAIT DU SUFFIXE EFFECTIF (par fichier)
                if [[ -n "$effective_suffix" ]]; then
                    local effective_suffix_no_dryrun="$effective_suffix"
                    if [[ "$DRYRUN" == true ]]; then
                        effective_suffix_no_dryrun="${effective_suffix_no_dryrun%"$DRYRUN_SUFFIX"}"
                    fi
                    generated_base_name="${generated_base_name%"$effective_suffix_no_dryrun"}"
                fi

                count=$((count + 1))
                
                {
                    echo -e "[ $count / $total_files ]"
                    
                    local anomaly_message=""
                    
                    # --- VÉRIFICATION D'ANOMALIE ---
                    if [[ "$base_name" != "$generated_base_name" ]]; then
                        anomaly_count=$((anomaly_count + 1))
                        anomaly_message="🚨 ANOMALIE DÉTECTÉE : Le nom de base original diffère du nom généré sans suffixe !"
                    fi
                    
                    if [[ -n "$anomaly_message" ]]; then
                        echo "$anomaly_message"
                        echo -e "${RED}  $anomaly_message${NOCOLOR}" > $TTY_DEV
                    fi
                    
                    # Affichage des noms
                    printf "  ${ORANGE}%-10s${NOCOLOR} : %s\n" "ORIGINAL" "$filename"
                    printf "  ${GREEN}%-10s${NOCOLOR}    : %s\n" "GÉNÉRÉ" "$final_output_basename"
                    
                    echo ""
                
                } | tee -a "$LOG_FILE"
                
            done < "$QUEUE"
            
            # AFFICHAGE ET LOG DU RÉSUMÉ DES ANOMALIES
            {
                echo "-------------------------------------------"
                if [[ "$anomaly_count" -gt 0 ]]; then
                    printf "  $anomaly_count ANOMALIE(S) de nommage trouvée(s)."
                    printf "  Veuillez vérifier les caractères spéciaux ou les problèmes d'encodage pour ces fichiers."
                else
                    printf " ${GREEN}Aucune anomalie de nommage détectée.${NOCOLOR}"
                fi
				echo ""
                echo "-------------------------------------------"
            } | tee -a "$LOG_FILE"         
            ;;
        [nN]|*)
            echo "Comparaison des noms ignorée."
            ;;
    esac
}
