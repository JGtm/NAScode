#!/bin/bash
###########################################################
# NOTIFY — FORMATAGE (pur)
# Helpers de formatage pour les messages Discord.
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
            body+=$'\n'"- 🎞️  VMAF dégradé : ${vmaf_anomalies}"
        fi
    fi

    if [[ "$show_space_savings" == "true" ]]; then
        if [[ -n "$space_line1" ]] || [[ -n "$space_line2" ]]; then
            body+=$'\n\n'"**Espace économisé**"
            [[ -n "$space_line1" ]] && body+=$'\n'"${space_line1}"
            [[ -n "$space_line2" ]] && body+=$'\n'"${space_line2}"
        fi
    fi

    body+=$'\n\n'"✅ Session terminée"

    printf '%s' "$body"
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
