#!/bin/bash
###########################################################
# NOTIFY — FORMATAGE (pur)
# Helpers de formatage pour les messages Discord.
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Le formatage utilise des valeurs par défaut
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

_notify_counter_prefix_plain() {
    local current_num="${CURRENT_FILE_NUMBER:-0}"
    local total_num="${TOTAL_FILES_TO_PROCESS:-0}"
    local limit="${LIMIT_FILES:-0}"

    # Mode random : compteur position [X/Y]
    if [[ "${RANDOM_MODE:-false}" == true ]]; then
        if [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
            printf '[%d/%d]' "$current_num" "$total_num"
        fi
        return 0
    fi

    # Mode limite : afficher [slot/LIMIT] si slot réservé, sinon fallback [current/total]
    if [[ "$limit" -gt 0 ]]; then
        local slot="${LIMIT_DISPLAY_SLOT:-0}"
        if [[ "$slot" =~ ^[0-9]+$ ]] && [[ "$slot" -gt 0 ]]; then
            printf '[%d/%d]' "$slot" "$limit"
        elif [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
            printf '[%d/%d]' "$current_num" "$total_num"
        fi
        return 0
    fi

    # Mode normal : [current/total]
    if [[ "$current_num" -gt 0 ]] && [[ "$total_num" -gt 0 ]]; then
        printf '[%d/%d]' "$current_num" "$total_num"
    fi
}

_notify_truncate_label() {
    local s="${1-}"
    local max="${2:-80}"
    if [[ -z "$s" ]]; then
        return 0
    fi
    if [[ ${#s} -gt "$max" ]]; then
        printf '%s' "${s:0:$((max-3))}..."
    else
        printf '%s' "$s"
    fi
}

_notify_strip_ansi() {
    # Retire les séquences ANSI (couleurs, etc.)
    # Remarque: GNU sed (Git Bash) supporte \x1B.
    sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'
}

_notify_discord_pad() {
    # Discord a tendance à ignorer les sauts de lignes en fin de message.
    # On ajoute un caractère invisible (ZWSP) sur une nouvelle ligne pour forcer un padding visuel.
    printf '%s' $'\n\n\u200B'
}

_notify_discord_lead_pad() {
    # Discord peut ignorer les sauts de ligne en tête de message.
    # On commence par un caractère invisible (ZWSP), puis on ajoute des sauts de lignes.
    printf '%s' $'\u200B\n\n'
}

_notify_kv_get() {
    # Usage: _notify_kv_get <file> <key>
    local file="${1-}"
    local key="${2-}"
    [[ -z "$file" ]] && return 0
    [[ -z "$key" ]] && return 0
    [[ ! -f "$file" ]] && return 0

    local line
    line=$(grep -m 1 -E "^${key}=" "$file" 2>/dev/null || true)
    [[ -z "$line" ]] && return 0
    printf '%s' "${line#*=}"
}

_notify_format_run_summary_markdown() {
    # Usage: _notify_format_run_summary_markdown <metrics_file> <now> <exit_code>
    local metrics_file="${1-}"
    local now="${2-}"
    local exit_code="${3-0}"

    [[ -z "$metrics_file" ]] && return 0
    [[ ! -f "$metrics_file" ]] && return 0

    local duration_total succ skip err size_anomalies checksum_anomalies vmaf_anomalies
    local show_space_savings space_line1 space_line2

    duration_total=$(_notify_kv_get "$metrics_file" "duration_total")
    succ=$(_notify_kv_get "$metrics_file" "succ")
    skip=$(_notify_kv_get "$metrics_file" "skip")
    err=$(_notify_kv_get "$metrics_file" "err")
    size_anomalies=$(_notify_kv_get "$metrics_file" "size_anomalies")
    checksum_anomalies=$(_notify_kv_get "$metrics_file" "checksum_anomalies")
    vmaf_anomalies=$(_notify_kv_get "$metrics_file" "vmaf_anomalies")
    show_space_savings=$(_notify_kv_get "$metrics_file" "show_space_savings")
    space_line1=$(_notify_kv_get "$metrics_file" "space_line1")
    space_line2=$(_notify_kv_get "$metrics_file" "space_line2")

    local body="🧾 Résumé"
    [[ -n "$now" ]] && body+=$'\n\n'"**Fin** : ${now}"
    [[ -n "$duration_total" ]] && body+=$'\n'"**Durée** : ${duration_total}"

    body+=$'\n\n'"**Résultats**"
    [[ -n "$succ" ]] && body+=$'\n'"- Succès : ${succ}"
    [[ -n "$skip" ]] && body+=$'\n'"- Ignorés : ${skip}"
    [[ -n "$err" ]] && body+=$'\n'"- Erreurs : ${err}"

    local any_anomaly=false
    if [[ "${size_anomalies:-0}" =~ ^[0-9]+$ ]] && [[ "$size_anomalies" -gt 0 ]]; then any_anomaly=true; fi
    if [[ "${checksum_anomalies:-0}" =~ ^[0-9]+$ ]] && [[ "$checksum_anomalies" -gt 0 ]]; then any_anomaly=true; fi
    if [[ "${vmaf_anomalies:-0}" =~ ^[0-9]+$ ]] && [[ "$vmaf_anomalies" -gt 0 ]]; then any_anomaly=true; fi

    if [[ "$any_anomaly" == true ]]; then
        body+=$'\n\n'"**Anomalies**"
        if [[ "${size_anomalies:-0}" =~ ^[0-9]+$ ]] && [[ "$size_anomalies" -gt 0 ]]; then
            body+=$'\n'"- ⚠️  Taille : ${size_anomalies}"
        fi
        if [[ "${checksum_anomalies:-0}" =~ ^[0-9]+$ ]] && [[ "$checksum_anomalies" -gt 0 ]]; then
            body+=$'\n'"- ❌ Intégrité : ${checksum_anomalies}"
        fi
        if [[ "${vmaf_anomalies:-0}" =~ ^[0-9]+$ ]] && [[ "$vmaf_anomalies" -gt 0 ]]; then
            body+=$'\n'"- 🎞️  VMAF (NA/dégradé) : ${vmaf_anomalies}"
        fi
    fi

    if [[ "$show_space_savings" == "true" ]]; then
        if [[ -n "$space_line1" ]] || [[ -n "$space_line2" ]]; then
            body+=$'\n\n'"**Espace économisé**"
            [[ -n "$space_line1" ]] && body+=$'\n'"${space_line1}"
            [[ -n "$space_line2" ]] && body+=$'\n'"${space_line2}"
        fi
    fi

    # Message final selon le code de sortie
    if [[ "$exit_code" -eq 0 ]]; then
        body+=$'\n\n'"✅ Session terminée"
    elif [[ "$exit_code" -eq 130 ]]; then
        body+=$'\n\n'"⚠️ Session interrompue (Ctrl+C)"
    else
        body+=$'\n\n'"❌ Session terminée avec erreur (code ${exit_code})"
    fi

    printf '%s' "$body"$(_notify_discord_pad)
}

_notify_format_event_file_skipped() {
    # Usage: _notify_format_event_file_skipped <filename> [reason]
    local filename="${1-}"
    local reason="${2-}"
    [[ -z "$filename" ]] && filename="(inconnu)"

    local prefix
    prefix=$(_notify_counter_prefix_plain)
    [[ -n "$prefix" ]] && prefix+=" "

    local body="${prefix}⏭️ Ignoré : $(_notify_truncate_label "$filename" 120)"
    [[ -n "$reason" ]] && body+=$'\n'"**Raison** : ${reason}"
    printf '%s' "$body"
}

_notify_format_event_run_started() {
    # Usage: _notify_format_event_run_started <now>
    local now="${1-}"

    local body="## Exécution"
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
    local has_queue_preview=false
    if [[ -n "${QUEUE:-}" ]] && [[ -f "${QUEUE}" ]]; then
        local preview
        preview=$(_notify_format_queue_preview "${QUEUE}")
        if [[ -n "$preview" ]]; then
            body+=$'\n\n'"**📋 File d’attente**"$'\n'
            body+=$'\n'"\`\`\`text"$'\n'"${preview}"$'\n'"\`\`\`"
            body+=$'\n\n'
            has_queue_preview=true
        fi
    fi

    # UX Discord: titre de transition avant le début des conversions
    if [[ "$has_queue_preview" == true ]]; then
        # Le bloc queue se termine déjà par \n\n, donc on évite d'en rajouter.
        body+="**Lancement de la conversion**"
    else
        body+=$'\n\n'"**Lancement de la conversion**"
    fi

    printf '%s' "$body"$(_notify_discord_pad)
}

_notify_format_event_file_started() {
    # Usage: _notify_format_event_file_started <filename>
    local filename="${1-}"
    [[ -z "$filename" ]] && filename="(inconnu)"

    local prefix
    prefix=$(_notify_counter_prefix_plain)
    [[ -n "$prefix" ]] && prefix+=" "

    printf '%s' "${prefix}▶️ Démarrage du fichier : $(_notify_truncate_label "$filename" 120)"
}

_notify_format_event_file_progress_update() {
    # Usage: _notify_format_event_file_progress_update <filename> <speed> <eta>
    # Envoyé après stabilisation de la vitesse FFmpeg (~15s)
    # Note: filename est ignoré (on garde juste le compteur et l'emoji)
    local filename="${1-}"
    local speed="${2-}"
    local eta="${3-}"

    local prefix
    prefix=$(_notify_counter_prefix_plain)
    [[ -n "$prefix" ]] && prefix+=" "

    # Formatage: [X/Y] 📊 x1.25 | ETA: 01:23:45
    local body="${prefix}📊"

    if [[ -n "$speed" ]]; then
        body+=" x${speed}"
    fi

    if [[ -n "$eta" ]]; then
        body+=" | ETA: ${eta}"
    fi

    printf '%s' "$body"
}

_notify_format_event_file_completed() {
    # Usage: _notify_format_event_file_completed <elapsed> <before> <after>
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
    printf '%s' "${prefix}✅ Conversion terminée en ${elapsed_part}${size_part}"
}

_notify_format_event_conversions_completed() {
    # Usage: _notify_format_event_conversions_completed <total>
    local total="${1-}"

    local body="✅ Toutes les conversions terminées"
    if [[ -n "$total" ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$total" -gt 0 ]]; then
        body+=" (${total} fichier(s))"
    fi

    # UX Discord: message macro + padding avant/après
    printf '%s' "$(_notify_discord_lead_pad)${body}$(_notify_discord_pad)"
}

_notify_format_event_transfers_pending() {
    # Usage: _notify_format_event_transfers_pending <count>
    local count="${1-}"
    local body="📤 Transferts en attente"
    if [[ -n "$count" ]] && [[ "$count" =~ ^[0-9]+$ ]]; then
        body+=" : ${count}"
    fi
    printf '%s' "$body"
}

_notify_format_event_transfers_done() {
    # UX Discord: laisser une ligne vide après l'étape transferts
    printf '%s' $'✅ Transferts terminés'$(_notify_discord_pad)
}

_notify_format_event_vmaf_started() {
    # Usage: _notify_format_event_vmaf_started <now> <count> [mode]
    local now="${1-}"
    local count="${2-0}"
    local mode="${3-}"

    local body="🎞️ Analyse VMAF — début"
    [[ -n "$now" ]] && body+=$'\n\n'"**Début** : ${now}"
    [[ -n "$count" ]] && body+=$'\n'"**Fichiers** : ${count}"
    [[ -n "$mode" ]] && body+=$'\n'"**Mode** : ${mode}"

    # UX Discord: laisser une ligne vide après l'annonce de début
    printf '%s' "$body"$(_notify_discord_pad)
}

_notify_format_event_vmaf_file_started() {
    # Usage: _notify_format_event_vmaf_file_started <current> <total> <filename>
    local cur="${1-}"
    local total="${2-}"
    local filename="${3-}"

    local prefix=""
    if [[ "$cur" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$cur" -gt 0 ]] && [[ "$total" -gt 0 ]]; then
        prefix="[${cur}/${total}] "
    fi

    printf '%s' "${prefix}🎞️ Début d'analyse : $(_notify_truncate_label "$filename" 30)"
}

_notify_format_vmaf_quality_badge() {
    local quality="${1-NA}"
    case "$quality" in
        EXCELLENT) printf '%s' "✅" ;;
        TRES_BON)  printf '%s' "✅" ;;
        BON)       printf '%s' "🟡" ;;
        DEGRADE)   printf '%s' "❌" ;;
        *)         printf '%s' "ℹ️" ;;
    esac
}

_notify_format_event_vmaf_file_completed() {
    # Usage: _notify_format_event_vmaf_file_completed <current> <total> <filename> <score> <quality>
    local cur="${1-}"
    local total="${2-}"
    local _filename="${3-}"
    local score="${4-NA}"
    local quality="${5-NA}"

    local prefix=""
    if [[ "$cur" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$cur" -gt 0 ]] && [[ "$total" -gt 0 ]]; then
        prefix="[${cur}/${total}] "
    fi

    local badge
    badge=$(_notify_format_vmaf_quality_badge "$quality")

    printf '%s' "${prefix}${badge} VMAF : ${quality} — ${score}"
}

_notify_format_event_vmaf_completed() {
    # Usage: _notify_format_event_vmaf_completed <now> <count> <ok> <na> <avg> <min> <max> <degraded> <duration> [worst_lines...]
    local now="${1-}"
    local count="${2-0}"
    local ok="${3-0}"
    local na="${4-0}"
    local avg="${5-NA}"
    local min="${6-NA}"
    local max="${7-NA}"
    local degraded="${8-0}"
    local duration="${9-}"
    shift 9 || true

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

    # UX Discord: message macro + padding avant/après
    printf '%s' "$(_notify_discord_lead_pad)${body}$(_notify_discord_pad)"
}

_notify_format_event_peak_pause() {
    # Usage: _notify_format_event_peak_pause <range> <wait_fmt> <resume_time> <interval>
    local range="${1-}"
    local wait_fmt="${2-}"
    local resume_time="${3-}"
    local interval="${4-}"

    local body="⏸️ Pause (heures pleines)"
    [[ -n "$range" ]] && body+=$'\n\n'"**Plage heures creuses** : ${range}"
    [[ -n "$wait_fmt" ]] && body+=$'\n'"**Attente estimée** : ${wait_fmt}"
    [[ -n "$resume_time" ]] && body+=$'\n'"**Reprise prévue** : ${resume_time}"
    [[ -n "$interval" ]] && body+=$'\n'"**Vérification** : toutes les ${interval}s"
    printf '%s' "$body"$(_notify_discord_pad)
}

_notify_format_event_peak_resume() {
    # Usage: _notify_format_event_peak_resume <range> <actual_wait>
    local range="${1-}"
    local actual_wait="${2-}"

    local body="▶️ Reprise (heures creuses)"
    [[ -n "$range" ]] && body+=$'\n\n'"**Plage heures creuses** : ${range}"
    [[ -n "$actual_wait" ]] && body+=$'\n'"**Attente réelle** : ${actual_wait}"
    printf '%s' "$body"$(_notify_discord_pad)
}

_notify_format_event_script_exit_summary() {
    # Usage: _notify_format_event_script_exit_summary <now> <exit_code>
    local now="${1-}"
    local exit_code="${2-0}"

    # 1) Résumé (markdown si possible)
    if [[ -n "${SUMMARY_METRICS_FILE:-}" ]] && [[ -f "${SUMMARY_METRICS_FILE}" ]]; then
        _notify_format_run_summary_markdown "${SUMMARY_METRICS_FILE}" "${now}" "${exit_code}"
        return 0
    fi

    # 2) Fallback: snippet texte (format terminal) si métriques absentes
    if [[ -n "${SUMMARY_FILE:-}" ]] && [[ -f "${SUMMARY_FILE}" ]]; then
        local summary_snippet
        summary_snippet=$(head -n 40 "${SUMMARY_FILE}" 2>/dev/null | _notify_strip_ansi | sed 's/[[:space:]]*$//' || true)
        if [[ -n "$summary_snippet" ]]; then
            local body="🧾 Résumé"
            body+=$'\n\n'"\`\`\`text"$'\n'"${summary_snippet}"$'\n'"\`\`\`"$'\n\n'
            printf '%s' "$body"$(_notify_discord_pad)
            return 0
        fi
    fi

    return 0
}

_notify_format_event_script_exit_end() {
    # Usage: _notify_format_event_script_exit_end <now> [exit_code]
    local now="${1-}"
    local exit_code="${2-0}"

    local body
    if [[ "$exit_code" -eq 0 ]]; then
        body="🏁 Fin"
    elif [[ "$exit_code" -eq 130 ]]; then
        body="🛑 Interrompu"
    else
        body="❌ Erreur (code ${exit_code})"
    fi

    [[ -n "$now" ]] && body+=" : ${now}"
    printf '%s' "$body"$(_notify_discord_pad)
}

_notify_basename_any() {
    # basename robuste (support / et \\)
    local p="${1-}"
    p="${p##*/}"
    p="${p##*\\}"
    printf '%s' "$p"
}

_notify_format_parallel_jobs_label() {
    local jobs="${PARALLEL_JOBS:-}"
    if [[ -z "$jobs" ]]; then
        return 0
    fi
    if [[ "$jobs" == "1" ]]; then
        printf '%s' "désactivé"
    else
        printf '%s' "$jobs"
    fi
}

_notify_format_queue_preview() {
    # Usage: _notify_format_queue_preview <queue_file>
    # Retour: lignes "[i/total] filename" avec max 20 lignes.
    # Règle: toujours afficher les 3 derniers; masquer le milieu avec "...".

    local queue_file="${1-}"
    [[ -z "$queue_file" ]] && return 0
    [[ ! -f "$queue_file" ]] && return 0

    # Convertir la queue NUL-separated en lignes et formater en AWK (mémoire bornée)
    tr '\0' '\n' < "$queue_file" 2>/dev/null | awk '
        BEGIN { max=20; head=16; tail=3; n=0 }
        {
            line=$0
            if (line == "") next
            n++
            if (n <= max) first[n]=line
            # ring buffer tail
            idx=((n-1)%tail)+1
            tail_line[idx]=line
            tail_n[idx]=n
        }
        function base(s) { sub(/^.*[\\/]/, "", s); return s }
        function trunc(s, m) { if (length(s) > m) return substr(s, 1, m-3) "..."; return s }
        END {
            if (n == 0) exit
            if (n <= max) {
                for (i=1; i<=n; i++) {
                    f=trunc(base(first[i]), 80)
                    printf("[%d/%d] %s\n", i, n, f)
                }
                exit
            }
            for (i=1; i<=head; i++) {
                f=trunc(base(first[i]), 80)
                printf("[%d/%d] %s\n", i, n, f)
            }
            print "..."
            for (k=n-tail+1; k<=n; k++) {
                for (j=1; j<=tail; j++) {
                    if (tail_n[j] == k) {
                        f=trunc(base(tail_line[j]), 80)
                        printf("[%d/%d] %s\n", k, n, f)
                        break
                    }
                }
            }
        }'
}
