#!/bin/bash
###########################################################
# FINALISATION ET RÉSULTATS
# Déplacement des fichiers, vérification d'intégrité, résumé
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

    local max_try=3
    local try=0

    # Tentative mv (3 essais)
    while [[ $try -lt $max_try ]]; do
        if mv "$tmp_output" "$final_output" 2>/dev/null; then
            printf "%s" "$final_output"
            return 0
        fi
        try=$((try+1))
        sleep 2
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
        sleep 2
    done

    # Repli local : dossier fallback
    local local_fallback_dir="${FALLBACK_DIR:-$HOME/Conversion_failed_uploads}"
    mkdir -p "$local_fallback_dir" 2>/dev/null || true
    if mv "$tmp_output" "$local_fallback_dir/" 2>/dev/null; then
        printf "%s" "$local_fallback_dir/$(basename "$final_output")"
        return 0
    fi
    if cp "$tmp_output" "$local_fallback_dir/" 2>/dev/null; then
        rm -f "$tmp_output" 2>/dev/null || true
        printf "%s" "$local_fallback_dir/$(basename "$final_output")"
        return 0
    fi

    # Ultime repli : laisser le temporaire et l'utiliser
    printf "%s" "$tmp_output"
    return 2
}

###########################################################
# VÉRIFICATION D'INTÉGRITÉ ET LOGGING
###########################################################

# Nettoyage local des artefacts temporaires et calculs de taille/checksum.
# Usage : _finalize_log_and_verify <file_original> <final_actual> <tmp_input> <ffmpeg_log_temp> <checksum_before> <size_before_mb> <size_before_bytes>
_finalize_log_and_verify() {
    local file_original="$1"
    local final_actual="$2"
    local tmp_input="$3"
    local ffmpeg_log_temp="$4"
    local checksum_before="$5"
    local size_before_mb="$6"
    local size_before_bytes="${7:-0}"

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
        if [[ -n "$LOG_SKIPPED" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | WARNING: FICHIER PLUS LOURD ($size_comparison). | $file_original" >> "$LOG_SKIPPED" 2>/dev/null || true
        fi
    fi

    # Log success
    if [[ -n "$LOG_SUCCESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | SUCCESS | $file_original → $final_actual | $size_comparison" >> "$LOG_SUCCESS" 2>/dev/null || true
    fi

    # Vérification d'intégrité : d'abord comparer la taille exacte (rapide), puis checksum si nécessaire
    local verify_status="OK"
    local checksum_after=""
    
    # Nettoyer le checksum_before (supprimer espaces/newlines parasites)
    checksum_before="${checksum_before//[$'\n\r\t ']/}"
    
    if [[ "$size_before_bytes" -gt 0 && "$size_after_bytes" -gt 0 && "$size_before_bytes" -ne "$size_after_bytes" ]]; then
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
    if [[ -n "$LOG_SUCCESS" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | VERIFY | $file_original → $final_actual | size:${size_before_bytes}B->${size_after_bytes}B | checksum:${checksum_before:-NA}/${checksum_after:-NA} | status:${verify_status}" >> "$LOG_SUCCESS" 2>/dev/null || true
    fi

    # Enregistrer pour analyse VMAF ultérieure (sera traité après toutes les conversions)
    _queue_vmaf_analysis "$file_original" "$final_actual"

    # En cas de problème, journaliser dans le log d'erreur
    if [[ "$verify_status" == "MISMATCH" || "$verify_status" == "SIZE_MISMATCH" ]]; then
        if [[ -n "$LOG_ERROR" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ${verify_status} | $file_original -> $final_actual | size:${size_before_bytes}B->${size_after_bytes}B | checksum:${checksum_before:-NA}/${checksum_after:-NA}" >> "$LOG_ERROR" 2>/dev/null || true
        fi
    fi
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

    # Si un marqueur d'arrêt global existe, ne pas finaliser (message déjà affiché par cleanup)
    if [[ -f "$STOP_FLAG" ]]; then
        rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null || true
        return 1
    fi

    if [[ "$NO_PROGRESS" != true ]]; then
        # Calculer la durée écoulée depuis le début de la conversion (START_TS défini avant l'appel à ffmpeg)
        local elapsed_str="N/A"
        if [[ -n "${START_TS:-}" ]]; then
            local end_ts
            end_ts=$(date +%s)
            local elapsed=$((end_ts - START_TS_TOTAL))
            local eh=$((elapsed / 3600))
            local em=$(((elapsed % 3600) / 60))
            local es=$((elapsed % 60))
            elapsed_str=$(printf "%02d:%02d:%02d" "$eh" "$em" "$es")
        fi

        echo -e "  ${GREEN}✅ Fichier converti : $filename (durée: ${elapsed_str})${NOCOLOR}"
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
        local final_actual
        final_actual=$(_finalize_try_move "$tmp_output" "$final_output" "$file_original") || true

        # Nettoyage, logs et vérifications
        _finalize_log_and_verify "$file_original" "$final_actual" "$tmp_input" "$ffmpeg_log_temp" "$checksum_before" "$sizeBeforeMB" "$sizeBeforeBytes"
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
    if [[ -n "$LOG_ERROR" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file_original" >> "$LOG_ERROR" 2>/dev/null || true
        echo "--- Erreur détaillée FFMPEG ---" >> "$LOG_ERROR" 2>/dev/null || true
        if [[ -n "$ffmpeg_log_temp" ]] && [[ -f "$ffmpeg_log_temp" ]] && [[ -s "$ffmpeg_log_temp" ]]; then
            cat "$ffmpeg_log_temp" >> "$LOG_ERROR" 2>/dev/null || true
        else
            echo "(Log d'erreur : ffmpeg_log_temp='$ffmpeg_log_temp' exists=$([ -f "$ffmpeg_log_temp" ] && echo 'OUI' || echo 'NON'))" >> "$LOG_ERROR" 2>/dev/null || true
        fi
        echo "-------------------------------" >> "$LOG_ERROR" 2>/dev/null || true
    fi
    rm -f "$tmp_input" "$tmp_output" "$ffmpeg_log_temp" 2>/dev/null
}

###########################################################
# AFFICHAGE DU RÉSUMÉ FINAL
###########################################################

show_summary() {
    # Traiter toutes les analyses VMAF en attente
    process_vmaf_queue
    
    local succ=0
    if [[ -f "$LOG_SUCCESS" && -s "$LOG_SUCCESS" ]]; then
        succ=$(grep -c ' | SUCCESS' "$LOG_SUCCESS" 2>/dev/null || echo 0)
    fi

    local skip=0
    if [[ -f "$LOG_SKIPPED" && -s "$LOG_SKIPPED" ]]; then
        skip=$(grep -c ' | SKIPPED' "$LOG_SKIPPED" 2>/dev/null || echo 0)
    fi

    local err=0
    if [[ -f "$LOG_ERROR" && -s "$LOG_ERROR" ]]; then
        err=$(grep -c ' | ERROR ffmpeg | ' "$LOG_ERROR" 2>/dev/null || echo 0)
    fi

    # Anomalies : fichiers plus lourds après conversion
    local size_anomalies=0
    if [[ -f "$LOG_SKIPPED" && -s "$LOG_SKIPPED" ]]; then
        size_anomalies=$(grep -c 'WARNING: FICHIER PLUS LOURD' "$LOG_SKIPPED" 2>/dev/null | tr -d '\r\n') || size_anomalies=0
    fi

    # Anomalies : erreurs de vérification checksum/taille lors du transfert
    local checksum_anomalies=0
    if [[ -f "$LOG_ERROR" && -s "$LOG_ERROR" ]]; then
        checksum_anomalies=$(grep -cE ' ERROR (MISMATCH|SIZE_MISMATCH|NO_CHECKSUM) ' "$LOG_ERROR" 2>/dev/null | tr -d '\r\n') || checksum_anomalies=0
    fi

    # Anomalies VMAF : fichiers avec qualité dégradée (score < 70)
    local vmaf_anomalies=0
    if [[ -f "$LOG_SUCCESS" && -s "$LOG_SUCCESS" ]]; then
        vmaf_anomalies=$(grep -c ' | VMAF | .* | quality:DEGRADE' "$LOG_SUCCESS" 2>/dev/null | tr -d '\r\n') || vmaf_anomalies=0
    fi
    
    {
        echo ""
        echo "-------------------------------------------"
        echo "           RÉSUMÉ DE CONVERSION            "
        echo "-------------------------------------------"
        echo "Date fin  : $(date +"%Y-%m-%d %H:%M:%S")"
        echo "Succès    : $succ"
        echo "Ignorés   : $skip"
        echo "Erreurs   : $err"
        echo "-------------------------------------------"
        echo "           ANOMALIES DÉTECTÉES             "
        echo "-------------------------------------------"
        echo "Taille    : $size_anomalies"
        echo "Intégrité : $checksum_anomalies"
        echo "VMAF      : $vmaf_anomalies"
        echo "-------------------------------------------"
    } | tee "$SUMMARY_FILE"
}

###########################################################
# DRY RUN AVANCÉ (Comparaison et Anomalies de nommage)
###########################################################

dry_run_compare_names() {
    local TTY_DEV="/dev/tty"
    local LOG_FILE="$LOG_DRYRUN_COMPARISON"

    echo ""
    read -r -p "Souhaitez-vous afficher la comparaison entre les noms de fichiers originaux et générés ? (O/n) " response
    
    case "$response" in
        [oO]|[yY]|'')
            {
                echo ""
                echo "-------------------------------------------"
                echo "      SIMULATION DES NOMS DE FICHIERS"
                echo "-------------------------------------------"
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
                
                local effective_suffix="$SUFFIX_STRING"
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
                
                # 2. RETRAIT DU SUFFIXE D'ORIGINE ($SUFFIX_STRING)
                if [[ -n "$SUFFIX_STRING" ]]; then
                    generated_base_name="${generated_base_name%"$SUFFIX_STRING"}"
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
