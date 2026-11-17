#!/bin/bash
###########################################################
# JOURNAL DES TENTATIVES (reprise sans retraitement inutile)
#
# logs/Attempts.tsv garde une ligne par tentative menée à terme :
#   date  résultat  empreinte  profil  taille_source  taille_sortie  gain%  chemin
# résultat : converted (publiée) | heavier (gain sous le seuil, envoyée dans _Heavier)
#            | error (échec ; jamais filtré, sert au cumul du résumé)
#
# Au lancement suivant, un film dont la dernière tentative est "heavier" sort
# de la queue si :
#   - la source est la même (chemin + taille) ;
#   - les paramètres sont les mêmes (empreinte, cf. attempts_fingerprint) ;
#   - le gain obtenu reste sous le seuil actuel (HEAVY_MIN_SAVINGS_PERCENT).
# Changer de codec, de mode ou de qualité, ou baisser le seuil, relance donc
# l'essai. --retry-heavier force un nouvel essai.
# Les erreurs sont notées pour le cumul mais toujours retentées : elles viennent
# souvent d'un bug corrigé depuis. Une interruption (Ctrl+C, crash) n'est pas notée.
#
# Lignes spéciales :
#   #SEED <date> <n> <src>  amorçage unique par source, depuis les logs de session et _Heavier
#   #END  <date> <src>  passage complet de la source : borne le cumul du résumé
#
# NOTE: Ce module n'active pas `set -euo pipefail` (sourcé par nascode qui
# l'active globalement) ; toutes les fonctions sont sûres sous errexit.
###########################################################

_attempts_file() {
    echo "${ATTEMPTS_FILE:-${LOG_DIR:-.}/Attempts.tsv}"
}

# Empreinte courte des paramètres qui changent le résultat d'une conversion.
# Le seuil de gain n'en fait pas partie : il est comparé au gain enregistré.
# Préfixe "v1" : à incrémenter si la liste change, pour invalider les anciennes.
attempts_fingerprint() {
    local s="v1|${VIDEO_CODEC:-}|${VIDEO_ENCODER:-}|${CONVERSION_MODE:-}|${ENCODER_PRESET:-}"
    s+="|${SINGLE_PASS_MODE:-}|${CRF_VALUE:-}|${TARGET_BITRATE_KBPS:-}|${MAXRATE_KBPS:-}|${BUFSIZE_KBPS:-}"
    s+="|${ADAPTIVE_COMPLEXITY_MODE:-}|${AUTO_BOOST_ENABLED:-}|${ENCODER_MODE_PARAMS:-}"
    s+="|${AUDIO_CODEC:-}|${AUDIO_BITRATE_KBPS:-}|${AUDIO_FORCE_STEREO:-}|${NO_LOSSLESS:-}"
    s+="|${FORCE_VIDEO_CODEC:-}|${FORCE_AUDIO_CODEC:-}|${VIDEO_EQUIV_QUALITY_CAP:-}"
    s+="|${AUDIO_TRANSLATE_EQUIV_QUALITY:-}|${EQUIV_QUALITY_OVERRIDE:-}"
    printf '%s' "$s" | cksum | awk '{ printf "%08x\n", $1 }'
}

# Ajout d'une ligne, protégé par un verrou mkdir : jusqu'à deux transferts
# asynchrones peuvent finaliser en même temps.
_attempts_append() {
    local file="$1" line="$2"
    local lockdir="${file}.lock" attempts=0
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.05
        attempts=$((attempts + 1))
        (( attempts > 100 )) && break
    done
    printf '%s\n' "$line" >> "$file" 2>/dev/null || true
    rmdir "$lockdir" 2>/dev/null || true
}

# Note l'issue d'une tentative.
# Usage: attempts_record <converted|heavier|error> <source> <octets_source> <octets_sortie> [date]
# [date] : "AAAA-MM-JJ HH:MM:SS" d'origine (amorçage), maintenant par défaut.
attempts_record() {
    local result="$1" path="$2" src_bytes="${3:-0}" out_bytes="${4:-0}"
    local when="${5:-$(date '+%Y-%m-%d %H:%M:%S')}"

    [[ "${DRYRUN:-false}" == true || "${SAMPLE_MODE:-false}" == true ]] && return 0
    [[ -n "$path" && "$path" != *$'\t'* && "$path" != *$'\n'* ]] || return 0
    [[ "$src_bytes" =~ ^[0-9]+$ && "$out_bytes" =~ ^[0-9]+$ ]] || return 0

    local savings=0
    [[ "$result" != error ]] && (( src_bytes > 0 )) && savings=$(( (src_bytes - out_bytes) * 100 / src_bytes ))

    local line
    printf -v line '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$when" "$result" "$(attempts_fingerprint)" \
        "${CONVERSION_MODE:-}/${VIDEO_CODEC:-}" "$src_bytes" "$out_bytes" "$savings" "$path"
    _attempts_append "$(_attempts_file)" "$line"
    return 0
}

# Note un échec de conversion (sauf interruption volontaire : Ctrl+C, arrêt).
# Usage: attempts_record_error <source>
attempts_record_error() {
    local path="$1"
    [[ -n "${STOP_FLAG:-}" && -f "$STOP_FLAG" ]] && return 0
    local src_bytes=0
    [[ -e "$path" ]] && src_bytes=$(get_file_size_bytes "$path")
    attempts_record error "$path" "$src_bytes" 0
}

# Filtre des lignes d'index ("taille<TAB>chemin") lues sur stdin : retire les
# films déjà tentés sans gain avec les mêmes paramètres, et écrit leurs chemins
# (un par ligne) dans <fichier_ignorés>.
# Usage: attempts_filter_index_lines <fichier_ignorés>
attempts_filter_index_lines() {
    local skipped_file="$1"
    : > "$skipped_file"

    local file
    file=$(_attempts_file)
    if [[ "${RETRY_HEAVIER:-false}" == true || ! -s "$file" ]]; then
        cat
        return 0
    fi

    awk -F'\t' -v fp="$(attempts_fingerprint)" -v thr="${HEAVY_MIN_SAVINGS_PERCENT:-10}" \
        -v ledger="$file" -v skipped="$skipped_file" '
        BEGIN {
            while ((getline l < ledger) > 0) {
                if (l ~ /^#/) continue
                n = split(l, a, "\t")
                if (n < 8) continue
                p = a[8]
                for (i = 9; i <= n; i++) p = p "\t" a[i]
                last[p] = l
            }
            close(ledger)
        }
        {
            size = $1
            path = substr($0, index($0, "\t") + 1)
            if (path in last) {
                split(last[path], a, "\t")
                if (a[2] == "heavier" && a[3] == fp && a[5] == size && a[7] + 0 < thr + 0) {
                    print path > skipped
                    next
                }
            }
            print
        }'
}

# Le film a-t-il une entrée (quels que soient les paramètres) dans le journal ?
# Sert à ne pas laisser l'ancien anti-boucle (fichier dans _Heavier) bloquer un
# film que le journal autorise à retenter.
attempts_has_entry() {
    local path="$1" file
    file=$(_attempts_file)
    [[ -s "$file" ]] || return 1
    awk -F'\t' -v p="$path" '
        /^#/ { next }
        { q = $8; for (i = 9; i <= NF; i++) q = q "\t" $i; if (q == p) { found = 1; exit } }
        END { exit found ? 0 : 1 }' "$file"
}

# Événements des logs de session, un par ligne, dans l'ordre chronologique :
#   H <date> <gain%> <chemin>          sortie redirigée vers _Heavier
#   C <date> <avant> <après> <chemin>  conversion publiée (REPLACED en octets, sinon SUCCESS en Mo)
#   E <date> <chemin>                  échec de conversion
# Ne comptent pas comme échecs : KEEP_METADATA, TRANSFER_FALLBACK (sortie publiée
# ailleurs) et l'ancien « ERROR REPLACE … reason:heavier_output » (sortie lourde).
_attempts_log_events() {
    local -a logs=()
    local f
    for f in "${LOG_DIR:-}"/Session_*.log; do [[ -f "$f" ]] && logs+=("$f"); done
    (( ${#logs[@]} > 0 )) || return 0
    # Noms horodatés : l'ordre du glob est chronologique
    awk -v heavy="${HEAVY_OUTPUT_DIR_SUFFIX:-_Heavier}/" '
        function cut(s,   i, j, k) {
            i = index(s, " -> "); j = index(s, " → "); k = index(s, " | ")
            if (j && (!i || j < i)) i = j
            if (k && (!i || k < i)) i = k
            return i ? substr(s, 1, i - 1) : s
        }
        !/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] \| / { next }
        {
            d = substr($0, 1, 19)
            rest = substr($0, 23)
            i = index(rest, " | "); if (!i) next
            kind = substr(rest, 1, i - 1)
            payload = substr(rest, i + 3)
            p = cut(payload); if (p == "") next
        }
        kind == "HEAVY_OUTPUT_REDIRECT" {
            g = payload; if (!sub(/.*savings:/, "", g)) next; sub(/%.*/, "", g)
            print "H\t" d "\t" g "\t" p; next
        }
        kind == "REPLACED" {
            if (!match(payload, /size:[0-9]+B->[0-9]+B/)) next
            sz = substr(payload, RSTART + 5, RLENGTH - 6); split(sz, a, "B->")
            print "C\t" d "\t" a[1] "\t" a[2] "\t" p; next
        }
        kind == "SUCCESS" {
            if (index(payload, heavy)) next
            if (!match(payload, /\| [0-9]+MB → [0-9]+MB/)) next
            sz = substr(payload, RSTART + 2, RLENGTH - 4); split(sz, a, "MB → ")
            printf "C\t%s\t%.0f\t%.0f\t%s\n", d, a[1] * 1048576, a[2] * 1048576, p; next
        }
        kind ~ /^ERROR/ {
            if (kind == "ERROR KEEP_METADATA" || kind == "ERROR TRANSFER_FALLBACK") next
            if (index(payload, "reason:heavier_output")) next
            print "E\t" d "\t" p
        }
    ' "${logs[@]}"
}

# Amorçage unique du journal avec l'historique d'avant son existence :
#   - logs de session : dernière issue de chaque film (convertie, sans gain, échec),
#     à sa date d'origine, pour que le cumul du résumé reparte du premier run ;
#   - dossier _Heavier : sorties sans gain (taille exacte), y compris celles des
#     runs dont les logs ont été purgés ; la source est retrouvée dans l'INDEX
#     (même dossier relatif, même nom, éventuellement suivi du suffixe de sortie).
# Les sans-gain et les échecs ne sont repris que si le film est encore dans l'INDEX.
# Les paramètres de ces anciennes tentatives sont inconnus : on suppose ceux du run courant.
# Après l'amorçage, le contenu de _Heavier peut être supprimé sans perdre la mémoire.
# Usage: attempts_seed_from_heavy   (après construction de l'INDEX)
attempts_seed_from_heavy() {
    [[ "${DRYRUN:-false}" == true || "${SAMPLE_MODE:-false}" == true ]] && return 0
    [[ -f "${INDEX:-}" ]] || return 0
    local file
    file=$(_attempts_file)
    # Une fois par dossier source : une autre source garde son propre amorçage
    awk -F'\t' -v src="${SOURCE%/}" '$1 == "#SEED" && $4 == src { found = 1; exit } END { exit !found }' "$file" 2>/dev/null && return 0

    local heavy_root="${OUTPUT_DIR%/}${HEAVY_OUTPUT_DIR_SUFFIX:-_Heavier}"
    local src_root="${SOURCE%/}"
    local h rel stem match mtime folder=""

    if [[ -d "$heavy_root" ]]; then
        while IFS= read -r -d '' h; do
            rel="${h#"$heavy_root"/}"
            stem="${rel%.*}"
            # 1. même chemin relatif (éventuellement suivi d'un suffixe "_…", le plus long gagne) ;
            # 2. sinon même nom de fichier n'importe où, s'il est unique : les anciennes
            #    versions posaient à plat dans _Heavier les films des sous-dossiers.
            match=$(awk -F'\t' -v root="$src_root/" -v hs="$stem" '
                function base(x) { sub(/.*\//, "", x); return x }
                {
                    p = substr($0, index($0, "\t") + 1)
                    if (index(p, root) != 1) next
                    s = substr(p, length(root) + 1)
                    sub(/\.[^.\/]*$/, "", s)
                    if (s == hs) { print $1 "\t" p; exact = 1; exit }
                    if (index(hs, s) == 1 && substr(hs, length(s) + 1, 1) == "_" && length(s) > best_len) {
                        best = $1 "\t" p; best_len = length(s)
                    }
                    if (index(hs, "/") == 0 && base(s) == hs) { flat = $1 "\t" p; nflat++ }
                }
                END {
                    if (exact) exit
                    if (best != "") print best
                    else if (nflat == 1) print flat
                }' "$INDEX")
            [[ -n "$match" ]] || continue
            mtime=$(date -r "$h" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || mtime=$(date '+%Y-%m-%d %H:%M:%S')
            # F <octets_source> <octets_sortie> <date> <chemin>
            folder+="F"$'\t'"${match%%$'\t'*}"$'\t'"$(get_file_size_bytes "$h")"$'\t'"$mtime"$'\t'"${match#*$'\t'}"$'\n'
        done < <(find "$heavy_root" -type f -iname '*.mkv' -print0 2>/dev/null || true)
    fi

    local nc=0 nh=0 ne=0 date result src_bytes out_bytes path
    while IFS=$'\t' read -r date result src_bytes out_bytes path; do
        [[ -n "$path" ]] || continue
        attempts_record "$result" "$path" "$src_bytes" "$out_bytes" "$date"
        case "$result" in
            converted) nc=$((nc + 1)) ;;
            heavier)   nh=$((nh + 1)) ;;
            error)     ne=$((ne + 1)) ;;
        esac
    done < <(
        {
            awk '{ print "I\t" $0 }' "$INDEX"
            _attempts_log_events
            printf '%s' "$folder"
        } | awk -F'\t' -v root="$src_root/" '
            function rest(n,   s, i) { s = $0; for (i = 1; i < n; i++) s = substr(s, index(s, "\t") + 1); return s }
            $1 == "I" { idx[rest(3)] = $2; next }
            $1 == "H" { p = rest(4); st[p] = "H"; dt[p] = $2; gain[p] = $3; next }
            $1 == "C" { p = rest(5); st[p] = "C"; dt[p] = $2; sb[p] = $3; ob[p] = $4; next }
            $1 == "E" { p = rest(3); st[p] = "E"; dt[p] = $2; next }
            $1 == "F" { p = rest(5); fsb[p] = $2; fob[p] = $3; fdt[p] = $4; next }
            END {
                # Sortie lourde encore présente : taille exacte, sauf si le film a été converti ou a échoué depuis
                for (p in fsb) {
                    if (st[p] != "" && st[p] != "H") continue
                    printf "%s\theavier\t%s\t%s\t%s\n", (dt[p] != "" ? dt[p] : fdt[p]), fsb[p], fob[p], p
                    done[p] = 1
                }
                for (p in st) {
                    # Seulement les films de cette source : les autres auront leur propre amorçage
                    if ((p in done) || index(p, root) != 1) continue
                    if (st[p] == "C") {
                        printf "%s\tconverted\t%.0f\t%.0f\t%s\n", dt[p], sb[p], ob[p], p
                    } else if (st[p] == "H") {
                        if (!(p in idx) || idx[p] !~ /^[0-9]+$/ || gain[p] !~ /^-?[0-9]+$/) continue
                        printf "%s\theavier\t%s\t%.0f\t%s\n", dt[p], idx[p], idx[p] * (100 - gain[p]) / 100, p
                    } else if (st[p] == "E") {
                        if (!(p in idx)) continue
                        printf "%s\terror\t%s\t0\t%s\n", dt[p], idx[p], p
                    }
                }
            }' | LC_ALL=C sort -s -t$'\t' -k1,1
    )

    _attempts_append "$file" "$(printf '#SEED\t%s\t%s\t%s' "$(date '+%Y-%m-%d %H:%M:%S')" "$((nc + nh + ne))" "$src_root")"
    if (( nc + nh + ne > 0 )) && [[ "${NO_PROGRESS:-false}" != true ]]; then
        print_info "$(msg MSG_ATTEMPTS_SEEDED "$nc" "$nh" "$ne")"
    fi
    return 0
}

# Marque la fin d'un passage complet de la source (borne du cumul).
attempts_mark_campaign_end() {
    [[ -n "${SOURCE:-}" ]] || return 0
    _attempts_append "$(_attempts_file)" "$(printf '#END\t%s\t%s' "$(date '+%Y-%m-%d %H:%M:%S')" "${SOURCE%/}")"
}

# Cumul depuis le dernier passage complet de la source : dernière tentative
# de chaque film seulement (un film reconverti n'est pas compté deux fois).
# Sortie : "nb_converted|octets_avant|octets_après|nb_heavier|date_début|nb_antérieurs|nb_erreurs"
# date_début = plus ancienne tentative de la campagne.
# nb_antérieurs = lignes de la campagne écrites avant ce run (1..ATTEMPTS_START_LINE).
# nb_erreurs = films dont la dernière tentative a échoué (pas réussis depuis).
attempts_campaign_totals() {
    local file
    file=$(_attempts_file)
    [[ -s "$file" && -n "${SOURCE:-}" ]] || { echo "0|0|0|0||0|0"; return 0; }

    awk -F'\t' -v root="${SOURCE%/}/" -v src="${SOURCE%/}" -v start="${ATTEMPTS_START_LINE:-0}" '
        function reset() { delete res; delete sb; delete ob; first = ""; old = 0 }
        $1 == "#END" { if ($3 == src) reset(); next }
        /^#/ { next }
        {
            p = $8; for (i = 9; i <= NF; i++) p = p "\t" $i
            if (index(p, root) != 1) next
            if (first == "" || $1 < first) first = $1
            # Toute ligne antérieure compte, même si le film a été refait depuis
            if (NR <= start) old++
            res[p] = $2; sb[p] = $5; ob[p] = $6
        }
        END {
            nc = 0; nh = 0; ne = 0; before = 0; after = 0
            for (p in res) {
                if (res[p] == "converted") { nc++; before += sb[p]; after += ob[p] }
                else if (res[p] == "heavier") nh++
                else if (res[p] == "error") ne++
            }
            printf "%d|%.0f|%.0f|%d|%s|%d|%d\n", nc, before, after, nh, first, old, ne
        }' "$file"
}
