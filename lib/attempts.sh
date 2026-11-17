#!/bin/bash
###########################################################
# JOURNAL DES TENTATIVES (reprise sans retraitement inutile)
#
# logs/Attempts.tsv garde une ligne par conversion menée à terme :
#   date  résultat  empreinte  profil  taille_source  taille_sortie  gain%  chemin
# résultat : converted (publiée) | heavier (gain sous le seuil, envoyée dans _Heavier)
#
# Au lancement suivant, un film dont la dernière tentative est "heavier" sort
# de la queue si :
#   - la source est la même (chemin + taille) ;
#   - les paramètres sont les mêmes (empreinte, cf. attempts_fingerprint) ;
#   - le gain obtenu reste sous le seuil actuel (HEAVY_MIN_SAVINGS_PERCENT).
# Changer de codec, de mode ou de qualité, ou baisser le seuil, relance donc
# l'essai. --retry-heavier force un nouvel essai.
# Les erreurs ne sont jamais notées : elles viennent souvent d'un bug corrigé
# depuis, on les retente toujours.
#
# Lignes spéciales :
#   #SEED <date> <n>    amorçage unique depuis le dossier _Heavier existant
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

# Note une conversion menée à terme.
# Usage: attempts_record <converted|heavier> <source> <octets_source> <octets_sortie>
attempts_record() {
    local result="$1" path="$2" src_bytes="${3:-0}" out_bytes="${4:-0}"

    [[ "${DRYRUN:-false}" == true || "${SAMPLE_MODE:-false}" == true ]] && return 0
    [[ -n "$path" && "$path" != *$'\t'* && "$path" != *$'\n'* ]] || return 0
    [[ "$src_bytes" =~ ^[0-9]+$ && "$out_bytes" =~ ^[0-9]+$ ]] || return 0

    local savings=0
    (( src_bytes > 0 )) && savings=$(( (src_bytes - out_bytes) * 100 / src_bytes ))

    local line
    printf -v line '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$result" "$(attempts_fingerprint)" \
        "${CONVERSION_MODE:-}/${VIDEO_CODEC:-}" "$src_bytes" "$out_bytes" "$savings" "$path"
    _attempts_append "$(_attempts_file)" "$line"
    return 0
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

# Amorçage unique : note comme "heavier" chaque sortie déjà présente dans le
# dossier _Heavier, en retrouvant sa source dans l'INDEX (même dossier relatif,
# même nom, éventuellement suivi du suffixe de sortie). Les paramètres de ces
# anciennes tentatives sont inconnus : on suppose ceux du run courant.
# Après l'amorçage, le contenu de _Heavier peut être supprimé sans perdre la mémoire.
# Films redirigés vers _Heavier d'après les logs de session (HEAVY_OUTPUT_REDIRECT),
# sauf ceux remplacés ensuite (REPLACED) ou déjà amorcés ($@).
# Taille source lue dans l'INDEX (film absent → ignoré) ; taille de sortie
# déduite du gain journalisé. Sortie : "src_bytes<TAB>out_bytes<TAB>chemin".
_attempts_heavy_from_logs() {
    local -a logs=()
    local f
    for f in "${LOG_DIR:-}"/Session_*.log; do [[ -f "$f" ]] && logs+=("$f"); done
    (( ${#logs[@]} > 0 )) || return 0
    # Les fichiers sont triés par date dans leur nom : l'ordre du glob est chronologique
    {
        printf 'D\t%s\n' "$@"
        awk '
            function src(s,   i) { s = substr(s, index(s, " | ") + 3); s = substr(s, index(s, " | ") + 3)
                                   i = index(s, " -> "); if (!i) i = index(s, " → "); return i ? substr(s, 1, i - 1) : "" }
            / \| HEAVY_OUTPUT_REDIRECT \| / {
                p = src($0); if (p == "") next
                g = $0; sub(/.*savings:/, "", g); sub(/%.*/, "", g)
                print "H\t" g "\t" p; next
            }
            / \| REPLACED \| / { p = src($0); if (p != "") print "R\t\t" p }
        ' "${logs[@]}"
        awk '{ print "I\t" $0 }' "$INDEX"
    } | awk -F'\t' '
        $1 == "D" { done[substr($0, 3)] = 1; next }
        $1 == "H" { p = substr($0, length($1 $2) + 3); state[p] = "H"; gain[p] = $2; next }
        $1 == "R" { p = substr($0, 4); state[p] = "R"; next }
        $1 == "I" {
            p = substr($0, length($1 $2) + 3)
            if (state[p] != "H" || (p in done)) next
            if ($2 !~ /^[0-9]+$/ || gain[p] !~ /^-?[0-9]+$/) next
            printf "%s\t%.0f\t%s\n", $2, $2 * (100 - gain[p]) / 100, p
            done[p] = 1
        }'
}

# Usage: attempts_seed_from_heavy   (après construction de l'INDEX)
attempts_seed_from_heavy() {
    [[ "${DRYRUN:-false}" == true || "${SAMPLE_MODE:-false}" == true ]] && return 0
    local file
    file=$(_attempts_file)
    grep -q '^#SEED' "$file" 2>/dev/null && return 0

    local heavy_root="${OUTPUT_DIR%/}${HEAVY_OUTPUT_DIR_SUFFIX:-_Heavier}"
    local src_root="${SOURCE%/}"
    local count=0 h rel stem match src_bytes src_path out_bytes
    local -a seeded=()

    if [[ -d "$heavy_root" && -f "${INDEX:-}" ]]; then
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
            src_bytes="${match%%$'\t'*}"
            src_path="${match#*$'\t'}"
            out_bytes=$(get_file_size_bytes "$h")
            attempts_record heavier "$src_path" "$src_bytes" "$out_bytes"
            seeded+=("$src_path")
            count=$((count + 1))
        done < <(find "$heavy_root" -type f -iname '*.mkv' -print0 2>/dev/null || true)
    fi

    # Sorties lourdes déjà supprimées de _Heavier : les logs de session les gardent
    if [[ -f "${INDEX:-}" ]]; then
        while IFS=$'\t' read -r src_bytes out_bytes src_path; do
            [[ -n "$src_path" ]] || continue
            attempts_record heavier "$src_path" "$src_bytes" "$out_bytes"
            count=$((count + 1))
        done < <(_attempts_heavy_from_logs "${seeded[@]}")
    fi

    _attempts_append "$file" "$(printf '#SEED\t%s\t%s' "$(date '+%Y-%m-%d %H:%M:%S')" "$count")"
    if (( count > 0 )) && [[ "${NO_PROGRESS:-false}" != true ]]; then
        print_info "$(msg MSG_ATTEMPTS_SEEDED "$count")"
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
# Sortie : "nb_converted|octets_avant|octets_après|nb_heavier|date_début|nb_antérieurs"
# nb_antérieurs = lignes de la campagne écrites avant ce run (1..ATTEMPTS_START_LINE).
attempts_campaign_totals() {
    local file
    file=$(_attempts_file)
    [[ -s "$file" && -n "${SOURCE:-}" ]] || { echo "0|0|0|0||0"; return 0; }

    awk -F'\t' -v root="${SOURCE%/}/" -v src="${SOURCE%/}" -v start="${ATTEMPTS_START_LINE:-0}" '
        function reset() { delete res; delete sb; delete ob; first = ""; old = 0 }
        $1 == "#END" { if ($3 == src) reset(); next }
        /^#/ { next }
        {
            p = $8; for (i = 9; i <= NF; i++) p = p "\t" $i
            if (index(p, root) != 1) next
            if (first == "") first = $1
            # Toute ligne antérieure compte, même si le film a été refait depuis
            if (NR <= start) old++
            res[p] = $2; sb[p] = $5; ob[p] = $6
        }
        END {
            nc = 0; nh = 0; before = 0; after = 0
            for (p in res) {
                if (res[p] == "converted") { nc++; before += sb[p]; after += ob[p] }
                else if (res[p] == "heavier") nh++
            }
            printf "%d|%.0f|%.0f|%d|%s|%d\n", nc, before, after, nh, first, old
        }' "$file"
}
