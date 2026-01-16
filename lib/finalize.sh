#!/bin/bash
###########################################################
# FINALISATION ET RÉSULTATS
# Note: Les fonctions de résumé (show_summary, etc.) sont dans lib/summary.sh
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les opérations de déplacement/nettoyage peuvent échouer
#    partiellement (comportement géré par le code)
# 3. Les modules sont sourcés, pas exécutés directement
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
    local fallback_target
    fallback_target="$local_fallback_dir/$(basename "$final_output")"
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
        size_after_bytes=$(get_file_size_bytes "$final_actual")
    fi

    local size_comparison="${size_before_mb}MB → ${size_after_mb}MB"

    if [[ "$size_after_mb" -ge "$size_before_mb" ]]; then
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: $(msg MSG_LOG_HEAVIER_FILE) ($size_comparison). | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
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
            original_size_bytes=$(get_file_size_bytes "$file_original")
        else
            # Fichier original supprimé, estimer depuis size_before_mb
            original_size_bytes=$((size_before_mb * 1024 * 1024))
        fi
        
        # Incrémenter les compteurs de façon robuste (flock si dispo, sinon lock portable).
        if declare -f atomic_add_int_to_file &>/dev/null; then
            [[ -n "${TOTAL_SIZE_BEFORE_FILE:-}" ]] && atomic_add_int_to_file "$TOTAL_SIZE_BEFORE_FILE" "$original_size_bytes"
            [[ -n "${TOTAL_SIZE_AFTER_FILE:-}" ]] && atomic_add_int_to_file "$TOTAL_SIZE_AFTER_FILE" "$size_after_bytes"
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
            print_warning "$(msg MSG_CONV_INTERRUPTED "$tmp_output")"
            # Log pour récupération manuelle si besoin
            if [[ -n "$LOG_SESSION" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') | $(msg MSG_FINAL_INTERRUPTED) | $file_original -> $tmp_output ($(msg MSG_FINAL_TEMP_KEPT))" >> "$LOG_SESSION" 2>/dev/null || true
            fi
        fi
        return 1
    fi

    if [[ "$NO_PROGRESS" != true ]]; then
        # Calculer la durée écoulée depuis le début de la conversion (START_TS défini avant l'appel à ffmpeg)
        local elapsed_display="N/A"
        local start_for_file="${FILE_START_TS:-${START_TS:-}}"
        if [[ -n "${start_for_file:-}" ]] && [[ "${start_for_file}" =~ ^[0-9]+$ ]]; then
            local end_ts
            end_ts=$(date +%s)
            local elapsed
            elapsed=$((end_ts - start_for_file))
            elapsed_display=$(format_duration_compact "$elapsed")
        fi

        local display_name
        display_name="$(basename "${final_output:-$filename}")"

        # Tronquer à 45 caractères max pour l'affichage
        local display_name_trunc="$display_name"
        if [[ ${#display_name_trunc} -gt 45 ]]; then
            display_name_trunc="${display_name_trunc:0:42}..."
        fi

        local size_part=""
        if [[ "${SAMPLE_MODE:-false}" != true ]]; then
            local before_bytes after_bytes
            before_bytes=0
            after_bytes=0

            if [[ -e "$file_original" ]]; then
                before_bytes=$(get_file_size_bytes "$file_original")
            elif [[ -n "${size_before_mb:-}" ]] && [[ "${size_before_mb}" =~ ^[0-9]+$ ]]; then
                before_bytes=$((size_before_mb * 1024 * 1024))
            fi

            if [[ -e "$tmp_output" ]]; then
                after_bytes=$(get_file_size_bytes "$tmp_output")
            fi

            local before_fmt after_fmt
            before_fmt=$(_format_size_bytes_compact "$before_bytes")
            after_fmt=$(_format_size_bytes_compact "$after_bytes")
            size_part=" | ${before_fmt} → ${after_fmt}"
        fi

        # Notification Discord (best-effort) : fin fichier
        if declare -f notify_event &>/dev/null; then
            if [[ "${SAMPLE_MODE:-false}" == true ]]; then
                notify_event file_completed "${elapsed_display}" "" "" || true
            else
                notify_event file_completed "${elapsed_display}" "${before_fmt:-}" "${after_fmt:-}" || true
            fi
        fi

        print_success "$(msg MSG_FINAL_CONV_DONE "$elapsed_display")${size_part}"
    fi

    # Vérifier que le fichier de sortie temporaire existe
    if [[ ! -f "$tmp_output" ]]; then
        print_error "$(msg MSG_CONV_TMP_NOT_FOUND "$tmp_output")"
        if [[ -n "$LOG_SESSION" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR MISSING_OUTPUT | $file_original -> $tmp_output ($(msg MSG_FINAL_TEMP_MISSING))" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        rm -f "$tmp_input" "$ffmpeg_log_temp" 2>/dev/null || true
        return 1
    fi

    # checksum et taille exacte avant déplacement (pour vérification intégrité)
    local checksum_before size_before_bytes
    checksum_before=$(compute_sha256 "$tmp_output" 2>/dev/null || echo "")
    size_before_bytes=$(get_file_size_bytes "$tmp_output")

    # Gestion des sorties "lourdes" : si la sortie n'apporte pas assez de gain (ou grossit),
    # rediriger vers un dossier séparé (OUTPUT_DIR + suffix) en conservant l'arborescence.
    local final_output_target="$final_output"
    if [[ "${HEAVY_OUTPUT_ENABLED:-true}" == true ]] && [[ "${SAMPLE_MODE:-false}" != true ]]; then
        local original_bytes encoded_bytes
        original_bytes=0
        encoded_bytes=0

        if [[ -e "$file_original" ]]; then
            original_bytes=$(get_file_size_bytes "$file_original")
        elif [[ -n "${size_before_mb:-}" ]] && [[ "${size_before_mb}" =~ ^[0-9]+$ ]]; then
            original_bytes=$((size_before_mb * 1024 * 1024))
        fi
        if [[ -e "$tmp_output" ]]; then
            encoded_bytes=$(get_file_size_bytes "$tmp_output")
        fi

        local min_savings="${HEAVY_MIN_SAVINGS_PERCENT:-10}"
        if [[ "$min_savings" =~ ^[0-9]+$ ]] && [[ "$original_bytes" -gt 0 ]] && [[ "$encoded_bytes" -gt 0 ]]; then
            local savings_percent
            savings_percent=$(((original_bytes - encoded_bytes) * 100 / original_bytes))

            if [[ "$encoded_bytes" -ge "$original_bytes" || "$savings_percent" -lt "$min_savings" ]]; then
                if declare -f compute_heavy_output_path &>/dev/null; then
                    local heavy_target
                    heavy_target=$(compute_heavy_output_path "$final_output" "$OUTPUT_DIR" 2>/dev/null || echo "")
                    if [[ -n "$heavy_target" ]]; then
                        final_output_target="$heavy_target"
                        mkdir -p "$(dirname "$final_output_target")" 2>/dev/null || true

                        if declare -f print_heavy_output_redirect &>/dev/null; then
                            print_heavy_output_redirect "$final_output_target"
                        else
                            print_warning "$(msg MSG_CONV_GAIN_REDIRECT "$final_output_target")"
                        fi

                        if [[ -n "$LOG_SESSION" ]]; then
                            echo "$(date '+%Y-%m-%d %H:%M:%S') | HEAVY_OUTPUT_REDIRECT | $file_original -> $final_output_target | savings:${savings_percent}% (threshold:${min_savings}%)" >> "$LOG_SESSION" 2>/dev/null || true
                        fi
                    fi
                fi
            fi
        fi
    fi

    # Vérifier si le système de transfert asynchrone est initialisé
    if [[ -n "${TRANSFER_PIDS_FILE:-}" ]] && declare -f start_async_transfer &>/dev/null; then
        # Attendre qu'un slot de transfert soit disponible (max 2 simultanés)
        wait_for_transfer_slot
        
        # Préparer les données de callback pour le transfert asynchrone
        # Format: checksum_before|size_before_mb|size_before_bytes|tmp_input|ffmpeg_log_temp
        local callback_data="${checksum_before}|${size_before_mb}|${size_before_bytes}|${tmp_input}|${ffmpeg_log_temp}"
        
        # Lancer le transfert en arrière-plan
        start_async_transfer "$tmp_output" "$final_output_target" "$file_original" "$callback_data"
    else
        # Mode synchrone (fallback si transfert asynchrone non initialisé)
        # Déplacer / copier / fallback et récupérer le chemin réel
        local final_actual move_status
        final_actual=$(_finalize_try_move "$tmp_output" "$final_output_target" "$file_original")
        move_status=$?

        # Nettoyage, logs et vérifications
        _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "$checksum_before" "$size_before_mb" "$size_before_bytes" "$final_output_target" "$move_status"
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
        print_error "$(msg MSG_CONV_FAILED "$filename")"
    fi
    if [[ -n "$LOG_SESSION" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_SESSION" 2>/dev/null || true
        echo "--- $(msg MSG_FINAL_FFMPEG_ERROR) ---" >> "$LOG_SESSION" 2>/dev/null || true
        if [[ -n "$ffmpeg_log_temp" ]] && [[ -f "$ffmpeg_log_temp" ]] && [[ -s "$ffmpeg_log_temp" ]]; then
            cat "$ffmpeg_log_temp" >> "$LOG_SESSION" 2>/dev/null || true
        else
            echo "(Log error: ffmpeg_log_temp='$ffmpeg_log_temp' exists=$([ -f "$ffmpeg_log_temp" ] && echo 'YES' || echo 'NO'))" >> "$LOG_SESSION" 2>/dev/null || true
        fi
        echo "-------------------------------" >> "$LOG_SESSION" 2>/dev/null || true
    fi
    rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
}

###########################################################
# DRY RUN AVANCÉ (Comparaison et Anomalies de nommage)
###########################################################

dry_run_compare_names() {
    local TTY_DEV="/dev/tty"
    local LOG_FILE="$LOG_DRYRUN_COMPARISON"

    ask_question "$(msg MSG_FINAL_SHOW_COMPARISON)"
    read -r response
    
    case "$response" in
        [oO]|[yY]|'')
            {
                print_header "$(msg MSG_FINAL_FILENAME_SIM_TITLE)"
            } | tee -a "$LOG_FILE"
            
            local total_files
            total_files=$(count_null_separated "$QUEUE")
            local count=0
            local anomaly_count=0
            
            while IFS= read -r -d $'\0' file_original; do
                local filename_raw
                filename_raw=$(basename "$file_original")
                local filename
                filename=$(echo "$filename_raw" | tr -d '\r\n')
                local base_name="${filename%.*}"
                
                local relative_path="${file_original#$SOURCE}"
                relative_path="${relative_path#/}"
                local relative_dir
                relative_dir=$(dirname "$relative_path")
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
                local final_output_basename
                final_output_basename=$(basename "$final_output")

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
                    printf "  ${GREEN}%-10s${NOCOLOR}    : %s\n" "$(msg MSG_FINAL_GENERATED)" "$final_output_basename"
                    
                    echo ""
                
                } | tee -a "$LOG_FILE"
                
            done < "$QUEUE"
            
            # AFFICHAGE ET LOG DU RÉSUMÉ DES ANOMALIES
            {
                echo "-------------------------------------------"
                if [[ "$anomaly_count" -gt 0 ]]; then
                    msg MSG_FINAL_ANOMALY_COUNT "$anomaly_count"
                    echo ""
                    msg MSG_FINAL_ANOMALY_HINT
                else
                    printf " ${GREEN}$(msg MSG_FINAL_NO_ANOMALY)${NOCOLOR}"
                fi
				echo ""
                echo "-------------------------------------------"
            } | tee -a "$LOG_FILE"         
            ;;
        [nN]|*)
            msg MSG_FINAL_COMPARE_IGNORED
            ;;
    esac
}
