#!/bin/bash
###########################################################
# NOTIFY — ÉVÉNEMENTS (format + envoi)
###########################################################

notify_event() {
    local event="${1-}"
    shift || true

    case "$event" in
        run_started)
            notify_event_run_started "$@"
            ;;
        file_started)
            notify_event_file_started "$@"
            ;;
        file_completed)
            notify_event_file_completed "$@"
            ;;
        file_skipped)
            notify_event_file_skipped "$@"
            ;;
        conversions_completed)
            notify_event_conversions_completed "$@"
            ;;
        transfers_pending)
            notify_event_transfers_pending "$@"
            ;;
        transfers_done)
            notify_event_transfers_done "$@"
            ;;
        vmaf_started)
            notify_event_vmaf_started "$@"
            ;;
        vmaf_file_started)
            notify_event_vmaf_file_started "$@"
            ;;
        vmaf_file_completed)
            notify_event_vmaf_file_completed "$@"
            ;;
        vmaf_completed)
            notify_event_vmaf_completed "$@"
            ;;
        peak_pause)
            notify_event_peak_pause "$@"
            ;;
        peak_resume)
            notify_event_peak_resume "$@"
            ;;
        script_exit)
            notify_event_script_exit "$@"
            ;;
        *)
            return 0
            ;;
    esac
}

notify_event_file_skipped() {
    # Usage: notify_event_file_skipped <filename> [reason]
    _notify_discord_is_enabled || return 0

    local filename="${1-}"
    local reason="${2-}"
    [[ -z "$filename" ]] && filename="(inconnu)"

    local prefix
    prefix=$(_notify_counter_prefix_plain)
    [[ -n "$prefix" ]] && prefix+=" "

    local body="${prefix}⏭️ Ignoré : $(_notify_truncate_label "$filename" 120)"
    if [[ -n "$reason" ]]; then
        body+=$'\n'"**Raison** : ${reason}"
    fi

    notify_discord_send_markdown "$body" "file_skipped"
    return 0
}

notify_event_run_started() {
    # Envoi unique
    [[ "${NASCODE_NOTIFY_RUN_STARTED_SENT:-0}" == "1" ]] && return 0
    NASCODE_NOTIFY_RUN_STARTED_SENT=1

    _notify_discord_is_enabled || return 0

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    local body="Démarrage"
    [[ -n "$now" ]] && body+=$'\n\n'"**Début** : ${now}"

    body+=$'\n\n'"**Paramètres actifs**"$'\n'
    [[ -n "${CONVERSION_MODE:-}" ]] && body+=$'\n'"- **📊  Mode** : ${CONVERSION_MODE}"
    [[ -n "${SOURCE:-}" ]] && body+=$'\n'"- **📂  Source** : ${SOURCE}"
    [[ -n "${OUTPUT_DIR:-}" ]] && body+=$'\n'"- **📂  Destination** : ${OUTPUT_DIR}"
    body+=$'\n'"- **🎬  Codec vidéo** : ${VIDEO_CODEC:-hevc}"
    [[ -n "${AUDIO_CODEC:-}" ]] && body+=$'\n'"- **🎵  Codec audio** : ${AUDIO_CODEC}"

    # Tri / limitation (queue)
    local sort_mode="${SORT_MODE:-size_desc}"
    local sort_label
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        sort_label="aléatoire (sélection)"
    else
        case "$sort_mode" in
            size_desc) sort_label="taille décroissante" ;;
            size_asc)  sort_label="taille croissante" ;;
            name_asc)  sort_label="nom ascendant" ;;
            name_desc) sort_label="nom descendant" ;;
            *)         sort_label="$sort_mode" ;;
        esac
    fi
    body+=$'\n'"- **↕️  Tri de la queue** : ${sort_label}"

    if [[ "${LIMIT_FILES:-0}" -gt 0 ]]; then
        local limit_icon="🔒"
        [[ "${RANDOM_MODE:-false}" == true ]] && limit_icon="🎲"
        body+=$'\n'"- **${limit_icon}  Limitation** : ${LIMIT_FILES} fichier(s) maximum"
    fi

    [[ "${DRYRUN:-false}" == true ]] && body+=$'\n'"- **🔍  Dry-run**"
    [[ "${SAMPLE_MODE:-false}" == true ]] && body+=$'\n'"- **🧪  Échantillon**"
    [[ "${VMAF_ENABLED:-false}" == true ]] && body+=$'\n'"- **🎞️  VMAF**"

    if [[ "${OFF_PEAK_ENABLED:-false}" == true ]]; then
        body+=$'\n'"- **⏰  Heures creuses** : ${OFF_PEAK_START:-22:00}-${OFF_PEAK_END:-06:00}"
    fi

    local jobs_label
    jobs_label=$(_notify_format_parallel_jobs_label)
    [[ -n "${jobs_label:-}" ]] && body+=$'\n'"- **⏭️  Jobs parallèles** : ${jobs_label}"

    # Aperçu de la queue (si disponible)
    if [[ -n "${QUEUE:-}" ]] && [[ -f "${QUEUE}" ]]; then
        local preview
        preview=$(_notify_format_queue_preview "${QUEUE}")
        if [[ -n "$preview" ]]; then
            body+=$'\n\n'"**📋 File d’attente**"$'\n'
            body+=$'\n'"\`\`\`text"$'\n'"${preview}"$'\n'"\`\`\`"
            body+=$'\n\n'
        fi
    fi

    notify_discord_send_markdown "$body" "run_started"
    return 0
}

notify_event_file_started() {
    _notify_discord_is_enabled || return 0

    local filename="${1-}"
    [[ -z "$filename" ]] && filename="(inconnu)"

    local prefix
    prefix=$(_notify_counter_prefix_plain)
    [[ -n "$prefix" ]] && prefix+=" "

    local body="${prefix}▶️ Démarrage du fichier : $(_notify_truncate_label "$filename" 120)"
    notify_discord_send_markdown "$body" "file_started"
    return 0
}

notify_event_file_completed() {
    # Usage: notify_event_file_completed <elapsed> <before> <after>
    _notify_discord_is_enabled || return 0

    local elapsed="${1-}"
    local before_fmt="${2-}"
    local after_fmt="${3-}"

    local prefix
    prefix=$(_notify_counter_prefix_plain)
    [[ -n "$prefix" ]] && prefix+=" "

    local size_part=""
    if [[ -n "$before_fmt" ]] && [[ -n "$after_fmt" ]]; then
        size_part=" | ${before_fmt} → ${after_fmt}"
    fi

    local elapsed_part="${elapsed:-N/A}"

    local body="${prefix}✅ Conversion terminée en ${elapsed_part}${size_part}"
    notify_discord_send_markdown "$body" "file_completed"
    return 0
}

notify_event_conversions_completed() {
    _notify_discord_is_enabled || return 0

    local total="${1-}"
    local body="✅ Toutes les conversions terminées"
    if [[ -n "$total" ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$total" -gt 0 ]]; then
        body+=" (${total} fichier(s))"
    fi
    
        # UX Discord: laisser une ligne vide après les étapes “macro”
        body+=$'\n\n'

    notify_discord_send_markdown "$body" "conversions_completed"
    return 0
}

notify_event_transfers_pending() {
    _notify_discord_is_enabled || return 0

    local count="${1-}"
    local body="📤 Transferts en attente"
    if [[ -n "$count" ]] && [[ "$count" =~ ^[0-9]+$ ]]; then
        body+=" : ${count}"
    fi

    notify_discord_send_markdown "$body" "transfers_pending"
    return 0
}

notify_event_transfers_done() {
    _notify_discord_is_enabled || return 0

    # UX Discord: laisser une ligne vide après l'étape transferts
    notify_discord_send_markdown $'✅ Transferts terminés\n\n' "transfers_done"
    return 0
}

notify_event_vmaf_started() {
    # Usage: notify_event_vmaf_started <count> [mode]
    _notify_discord_is_enabled || return 0

    local count="${1-0}"
    local mode="${2-}"

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    local body="🎞️ Analyse VMAF — début"
    [[ -n "$now" ]] && body+=$'\n\n'"**Début** : ${now}"
    [[ -n "$count" ]] && body+=$'\n'"**Fichiers** : ${count}"
    [[ -n "$mode" ]] && body+=$'\n'"**Mode** : ${mode}"
    
        # UX Discord: laisser une ligne vide après l'annonce de début
        body+=$'\n\n'

    notify_discord_send_markdown "$body" "vmaf_started"
    return 0
}

notify_event_vmaf_file_started() {
    # Usage: notify_event_vmaf_file_started <current> <total> <filename>
    _notify_discord_is_enabled || return 0

    local cur="${1-}"
    local total="${2-}"
    local filename="${3-}"

    local prefix=""
    if [[ "$cur" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$cur" -gt 0 ]] && [[ "$total" -gt 0 ]]; then
        prefix="[${cur}/${total}] "
    fi

    local body="${prefix}🎞️ Début VMAF : $(_notify_truncate_label "$filename" 30)"
    notify_discord_send_markdown "$body" "vmaf_file_started"
    return 0
}

notify_event_vmaf_file_completed() {
    # Usage: notify_event_vmaf_file_completed <current> <total> <filename> <score> <quality>
    _notify_discord_is_enabled || return 0

    local cur="${1-}"
    local total="${2-}"
    local filename="${3-}"
    local score="${4-NA}"
    local quality="${5-NA}"

    local prefix=""
    if [[ "$cur" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$cur" -gt 0 ]] && [[ "$total" -gt 0 ]]; then
        prefix="[${cur}/${total}] "
    fi

    local badge=""
    case "$quality" in
        EXCELLENT) badge="✅" ;;
        TRES_BON)  badge="✅" ;;
        BON)       badge="🟡" ;;
        DEGRADE)   badge="❌" ;;
        *)         badge="ℹ️" ;;
    esac

    local body="${prefix}${badge} VMAF : ${quality} — ${score}"

    notify_discord_send_markdown "$body" "vmaf_file_completed"
    return 0
}

notify_event_vmaf_completed() {
    # Usage: notify_event_vmaf_completed <count> <ok> <na> <avg> <min> <max> <degraded> <duration>
    # + optionnel: lignes "worst" (déjà formatées)
    _notify_discord_is_enabled || return 0

    local count="${1-0}"
    local ok="${2-0}"
    local na="${3-0}"
    local avg="${4-NA}"
    local min="${5-NA}"
    local max="${6-NA}"
    local degraded="${7-0}"
    local duration="${8-}"
    shift 8 || true

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    local body="✅ Analyse VMAF — terminée"
    [[ -n "$now" ]] && body+=$'\n\n'"**Fin** : ${now}"
    [[ -n "$duration" ]] && body+=$'\n'"**Durée** : ${duration}"

    body+=$'\n\n'"**Résultats**"
    body+=$'\n'"- Analysés : ${ok}/${count}"
    body+=$'\n'"- NA : ${na}"
    body+=$'\n'"- Moyenne : ${avg}"
    body+=$'\n'"- Min / Max : ${min} / ${max}"
    body+=$'\n'"- Dégradés : ${degraded}"

    if [[ "$#" -gt 0 ]]; then
        body+=$'\n\n'"**Pires scores**"
        local line
        for line in "$@"; do
            [[ -n "$line" ]] && body+=$'\n'"$line"
        done
    fi

    notify_discord_send_markdown "$body" "vmaf_completed"
    return 0
}

notify_event_peak_pause() {
    # Usage: notify_event_peak_pause "22:00-06:00" "1h 20min" "22:00" "60"
    _notify_discord_is_enabled || return 0

    local range="${1-}"
    local wait_fmt="${2-}"
    local resume_time="${3-}"
    local interval="${4-}"

    local body="⏸️ Pause (heures pleines)"
    [[ -n "$range" ]] && body+=$'\n\n'"**Plage heures creuses** : ${range}"
    [[ -n "$wait_fmt" ]] && body+=$'\n'"**Attente estimée** : ${wait_fmt}"
    [[ -n "$resume_time" ]] && body+=$'\n'"**Reprise prévue** : ${resume_time}"
    [[ -n "$interval" ]] && body+=$'\n'"**Vérification** : toutes les ${interval}s"

    notify_discord_send_markdown "$body" "peak_pause"
    return 0
}

notify_event_peak_resume() {
    # Usage: notify_event_peak_resume "22:00-06:00" "1h 18min"
    _notify_discord_is_enabled || return 0

    local range="${1-}"
    local actual_wait="${2-}"

    local body="▶️ Reprise (heures creuses)"
    [[ -n "$range" ]] && body+=$'\n\n'"**Plage heures creuses** : ${range}"
    [[ -n "$actual_wait" ]] && body+=$'\n'"**Attente réelle** : ${actual_wait}"

    notify_discord_send_markdown "$body" "peak_resume"
    return 0
}

notify_event_script_exit() {
    # Appelé depuis cleanup() avec le code de sortie.
    [[ "${NASCODE_NOTIFY_RUN_FINISHED_SENT:-0}" == "1" ]] && return 0
    NASCODE_NOTIFY_RUN_FINISHED_SENT=1

    _notify_discord_is_enabled || return 0

    local exit_code="${1-0}"

    local now
    now=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "")

    # 1) Résumé (markdown si possible)
    local summary_body=""
    if [[ -n "${SUMMARY_METRICS_FILE:-}" ]] && [[ -f "${SUMMARY_METRICS_FILE}" ]]; then
        summary_body=$(_notify_format_run_summary_markdown "${SUMMARY_METRICS_FILE}" "${now}" "${exit_code}")
    fi

    # Fallback: snippet texte (format terminal) si métriques absentes
    if [[ -z "$summary_body" ]]; then
        local summary_snippet=""
        if [[ -n "${SUMMARY_FILE:-}" ]] && [[ -f "${SUMMARY_FILE}" ]]; then
            summary_snippet=$(head -n 40 "${SUMMARY_FILE}" 2>/dev/null | _notify_strip_ansi | sed 's/[[:space:]]*$//' || true)
        fi

        if [[ -n "$summary_snippet" ]]; then
            summary_body="🧾 Résumé"
            summary_body+=$'\n\n'"\`\`\`text"$'\n'"${summary_snippet}"$'\n'"\`\`\`"$'\n\n'
        fi
    fi

    [[ -n "$summary_body" ]] && notify_discord_send_markdown "$summary_body" "summary"

    # 2) Message final (heure de fin)
    [[ -n "$now" ]] && local end_body+=$'\n\n'"🏁 Fin : ${now}"

    notify_discord_send_markdown "$end_body" "script_exit"
    return 0
}
