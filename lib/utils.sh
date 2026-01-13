#!/bin/bash
###########################################################
# FORMATAGE DURÉE
###########################################################

# Formate une durée en secondes vers HH:MM:SS
# Usage: format_duration_seconds <seconds>
# Retourne: "01:23:45" ou "00:05:30"
format_duration_seconds() {
    local seconds="${1:-0}"
    [[ ! "$seconds" =~ ^[0-9]+$ ]] && seconds=0
    local h=$((seconds / 3600))
    local m=$(((seconds % 3600) / 60))
    local s=$((seconds % 60))
    printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

# Formate une durée en secondes de façon compacte (1h 23m 45s ou 5m 30s ou 45s)
# Usage: format_duration_compact <seconds>
# Retourne: "1h 23m 45s" ou "5m 30s" ou "45s"
format_duration_compact() {
    local seconds="${1:-0}"
    [[ ! "$seconds" =~ ^[0-9]+$ ]] && seconds=0
    local h=$((seconds / 3600))
    local m=$(((seconds % 3600) / 60))
    local s=$((seconds % 60))
    if [[ "$h" -gt 0 ]]; then
        echo "${h}h ${m}m ${s}s"
    elif [[ "$m" -gt 0 ]]; then
        echo "${m}m ${s}s"
    else
        echo "${s}s"
    fi
}

###########################################################
# CALCUL MD5 PORTABLE
###########################################################

# préfixe md5 portable (8 premiers caractères) pour créer les noms temporaires
compute_md5_prefix() {
    local input="$1"
    if [[ "$HAS_MD5SUM" -eq 1 ]]; then
        printf "%s" "$input" | md5sum | awk '{print substr($1,1,8)}'
    elif [[ "$HAS_MD5" -eq 1 ]]; then
        # Sur macOS, md5 n'affiche que le digest pour stdin ; gestion robuste
        printf "%s" "$input" | md5 | awk '{print substr($1,1,8)}'
    elif [[ "$HAS_PYTHON3" -eq 1 ]]; then
        # shellcheck disable=SC2259
        printf "%s" "$input" | python3 - <<PY | head -1
import sys,hashlib
print(hashlib.md5(sys.stdin.read().encode()).hexdigest()[:8])
PY
    else
        # repli : utiliser cksum (POSIX) - non cryptographique mais stable et portable
        printf "%s" "$input" | cksum | awk '{printf "%08x", $1}' 2>/dev/null || echo "00000000"
    fi
}

###########################################################
# APPEL CONDITIONNEL DE FONCTION
###########################################################

# Appelle une fonction si elle est définie, sinon retourne 1.
# Usage: call_if_exists func_name [args...]
# Retourne: le code retour de la fonction, ou 1 si non définie
# Exemple:
#   result=$(call_if_exists my_func "$arg") || result="default"
#   call_if_exists increment_counter && echo "incrémenté"
call_if_exists() {
    local func="$1"
    shift
    if declare -f "$func" &>/dev/null; then
        "$func" "$@"
    else
        return 1
    fi
}

###########################################################
# HORODATAGE HAUTE RÉSOLUTION
###########################################################

# horodatage haute résolution (secondes avec fraction)
now_ts() {
    if [[ "$HAS_DATE_NANO" -eq 1 ]]; then
        date +%s.%N
    elif [[ "$HAS_PYTHON3" -eq 1 ]]; then
        python3 -c 'import time; print(time.time())'
    elif [[ "$HAS_PERL_HIRES" -eq 1 ]]; then
        perl -MTime::HiRes -e 'printf("%.6f\n", Time::HiRes::time)'
    else
        date +%s
    fi
}

###########################################################
# CALCUL SHA256 PORTABLE
###########################################################

# Calculer le checksum SHA256 d'un fichier en utilisant les outils disponibles (portable)
compute_sha256() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo ""
        return 0
    fi

    if [[ "$HAS_SHA256SUM" -eq 1 ]]; then
        sha256sum -- "$file" | awk '{print $1}'
    elif [[ "$HAS_SHASUM" -eq 1 ]]; then
        shasum -a 256 -- "$file" | awk '{print $1}'
    elif [[ "$HAS_OPENSSL" -eq 1 ]]; then
        openssl dgst -sha256 -- "$file" | awk '{print $NF}'
    elif [[ "$HAS_PYTHON3" -eq 1 ]]; then
        python3 - <<PY "$file"
import sys,hashlib
with open(sys.argv[1],'rb') as fh:
    print(hashlib.sha256(fh.read()).hexdigest())
PY
    else
        # fallback: vide si aucun outil n'est disponible
        echo ""
    fi
}

###########################################################
# NORMALISATION CHEMINS FFPROBE (WINDOWS/GIT BASH)
###########################################################

# Résout un chemin (fichier ou dossier) en chemin absolu.
# Usage: abspath_path <path>
# Retourne le chemin absolu sur stdout. Retourne 1 si résolution impossible.
abspath_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo ""
        return 1
    fi

    local dir base
    dir="$(dirname "$path")"
    base="$(basename "$path")"

    (cd "$dir" 2>/dev/null && printf "%s/%s\n" "$(pwd)" "$base")
}

# Convertit un chemin Git Bash (/c/...) en chemin Windows (C:/...) pour ffprobe
# ffprobe sur Windows/Git Bash ne gère pas bien /c/ avec des caractères spéciaux (accents, apostrophes)
normalize_path_for_ffprobe() {
    local path="$1"
    # Si le chemin commence par /c/, /d/, etc. (lettre de lecteur Git Bash)
    if [[ "$path" =~ ^/([a-zA-Z])/ ]]; then
        # Convertir /c/... en C:/...
        echo "${BASH_REMATCH[1]^}:${path:2}"
    else
        echo "$path"
    fi
}

# Wrapper ffprobe qui normalise automatiquement les chemins Windows/Git Bash.
# Usage identique à ffprobe : ffprobe_safe [options] <file>
# Le dernier argument est considéré comme le fichier à normaliser.
ffprobe_safe() {
    local args=("$@")
    local last_idx=$((${#args[@]} - 1))
    
    # Normaliser le dernier argument (le fichier)
    if [[ $last_idx -ge 0 ]]; then
        args[$last_idx]=$(normalize_path_for_ffprobe "${args[$last_idx]}")
    fi
    
    ffprobe "${args[@]}"
}

###########################################################
# FONCTIONS DE COMPTAGE ET EXCLUSION
###########################################################

# Fonction utilitaire : compter les éléments dans un fichier null-separated
count_null_separated() {
    local file="$1"
    if [[ -f "$file" ]]; then
        tr -cd '\0' < "$file" | wc -c
    else
        echo 0
    fi
}

# Vérifier si un fichier doit être exclu
is_excluded() {
    local f="$1"
    local f_norm
    # Normaliser les backslashes éventuels (Windows) en slashes
    f_norm="${f//\\//}"
    # Utilise la regex pré-compilée pour une vérification O(1) au lieu de O(n)
    if [[ -n "$EXCLUDES_REGEX" ]] && [[ "$f_norm" =~ $EXCLUDES_REGEX ]]; then
        return 0
    fi
    return 1
}

# Pure Bash - évite un fork vers sed
clean_number() {
    local val="${1//[!0-9]/}"
    echo "${val:-0}"
}

###########################################################
# CONSTRUCTION DE COMMANDES (TABLEAUX)
###########################################################

# Ajoute à un tableau (nommé) les mots issus d'une chaîne d'options.
# Convention interne: la chaîne est supposée contrôlée (options FFmpeg, wrappers, etc.).
# Compatible bash 3.2 (pas de local -n).
# Usage: _cmd_append_words cmd "-hwaccel cuda -extra 1"
_cmd_append_words() {
    local array_name="$1"
    local words_str="${2:-}"

    [[ -z "$array_name" || -z "$words_str" ]] && return 0

    local -a _tmp=()
    read -r -a _tmp <<< "$words_str"
    # shellcheck disable=SC2140
    eval "$array_name+=(\"\${_tmp[@]}\")"
}

###########################################################
# SHUFFLE PORTABLE (SANS PYTHON)
###########################################################

# Mélange des lignes sur stdin.
# Utilise shuf si disponible, sinon fallback awk+sort (portable GNU/BSD).
shuffle_lines() {
    if command -v shuf >/dev/null 2>&1; then
        shuf
        return
    fi

    # Fallback : préfixer chaque ligne par un nombre pseudo-aléatoire puis trier.
    # Note : rand() n'est pas cryptographiquement sûr, mais suffisant pour la sélection random.
    awk 'BEGIN{srand()} {printf("%f\t%s\n", rand(), $0)}' | sort -k1,1n | cut -f2-
}

###########################################################
# COMPTEURS FICHIER (LOCK PORTABLE)
###########################################################

# Ajoute delta (entier) au contenu (entier) d'un fichier compteur.
# - flock si dispo
# - sinon lock via mkdir (portable)
# - sinon best-effort sans lock
atomic_add_int_to_file() {
    local file="$1"
    local delta="$2"

    [[ -z "$file" ]] && return 0
    [[ ! -f "$file" ]] && return 0
    [[ ! "$delta" =~ ^-?[0-9]+$ ]] && return 0

    _atomic_add_internal() {
        local current
        current=$(cat "$file" 2>/dev/null || echo 0)
        [[ -z "$current" ]] && current=0
        [[ ! "$current" =~ ^-?[0-9]+$ ]] && current=0
        echo $((current + delta)) > "$file"
    }

    local lock_file="${file}.lock"

    if command -v flock >/dev/null 2>&1; then
        ( flock -x 200; _atomic_add_internal ) 200>"$lock_file" 2>/dev/null && return 0
        # si flock existe mais échoue (FS exotiques), repli mkdir.
    fi

    local lock_dir="${file}.lockdir"
    local i=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        i=$((i + 1))
        [[ "$i" -ge 50 ]] && break
        sleep 0.02
    done

    if [[ -d "$lock_dir" ]]; then
        _atomic_add_internal
        rmdir "$lock_dir" 2>/dev/null || true
        return 0
    fi

    # Ultime repli : best-effort (non atomique)
    _atomic_add_internal 2>/dev/null || true
    return 0
}

###########################################################
# SORTIES "HEAVY" (PLUS LOURDES / GAIN FAIBLE)
###########################################################

# Calcule un chemin de sortie alternatif "Heavier" en conservant l'arborescence.
# Usage: compute_heavy_output_path <final_output> [output_dir]
compute_heavy_output_path() {
    local final_output="$1"
    local output_dir="${2:-${OUTPUT_DIR:-}}"

    [[ -z "$final_output" ]] && return 1
    [[ -z "$output_dir" ]] && return 1

    local out_root="${output_dir%/}"
    local heavy_root="${out_root}${HEAVY_OUTPUT_DIR_SUFFIX:-_Heavier}"

    if [[ "$final_output" == "$out_root"* ]]; then
        printf '%s' "${heavy_root}${final_output#${out_root}}"
        return 0
    fi

    printf '%s' "${heavy_root}/$(basename "$final_output")"
}

###########################################################
# TAILLES DE FICHIERS / PARSING
###########################################################

# Retourne la taille d'un fichier en octets.
# Compatible Linux (stat -c%s) et macOS (stat -f%z). Sur MSYS/Git Bash,
# `stat -c%s` est généralement disponible.
get_file_size_bytes() {
    local path="$1"
    stat -c%s -- "$path" 2>/dev/null || stat -f%z -- "$path" 2>/dev/null || echo 0
}

# Convertit une taille "humaine" en octets.
# Formats acceptés :
#   - bytes : 123456
#   - suffixes binaires : 700K, 700M, 1G, 2T (suffixe optionnel 'B')
#   - décimaux : 1.5G, 2.5M
# Insensible à la casse. Retourne la valeur en octets sur stdout.
parse_human_size_to_bytes() {
    local raw="${1:-}"
    local s unit number

    if [[ -z "$raw" ]]; then
        return 1
    fi

    # Trim espaces
    s="${raw//[[:space:]]/}"
    s="${s^^}"

    # Autoriser un trailing 'B' (ex: 700MB)
    if [[ "$s" == *B ]]; then
        s="${s%B}"
    fi

    # Bytes (nombre pur entier)
    if [[ "$s" =~ ^[0-9]+$ ]]; then
        echo "$s"
        return 0
    fi

    # Nombre (entier ou décimal) + unité (K/M/G/T)
    if [[ "$s" =~ ^([0-9]+\.?[0-9]*)([KMGT])$ ]]; then
        number="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    # Utiliser awk pour gérer les décimaux et tronquer vers un entier
    case "$unit" in
        K) awk -v n="$number" 'BEGIN { printf "%.0f", n * 1024 }' ;;
        M) awk -v n="$number" 'BEGIN { printf "%.0f", n * 1024 * 1024 }' ;;
        G) awk -v n="$number" 'BEGIN { printf "%.0f", n * 1024 * 1024 * 1024 }' ;;
        T) awk -v n="$number" 'BEGIN { printf "%.0f", n * 1024 * 1024 * 1024 * 1024 }' ;;
        *) return 1 ;;
    esac
    return 0
}

###########################################################
# SCRIPT AWK UNIFIÉ POUR PROGRESSION FFMPEG
###########################################################

# Script AWK partagé pour afficher la progression FFmpeg (pass 1 & pass 2)
# Variables requises : DURATION, CURRENT_FILE_NAME, NOPROG, START, SLOT, PARALLEL, MAX_SLOTS, EMOJI, END_MSG
# Fonction get_time() doit être injectée selon HAS_GAWK
# Usage: awk -v DURATION=... -v ... "$AWK_TIME_FUNC $AWK_FFMPEG_PROGRESS_SCRIPT"
# shellcheck disable=SC2034
readonly AWK_FFMPEG_PROGRESS_SCRIPT='
function format_time(ts,   cmd,result,h,m,s) {
    # Formater un timestamp Unix en HH:MM:SS
    h = int((ts % 86400) / 3600);
    m = int((ts % 3600) / 60);
    s = int(ts % 60);
    # Ajuster pour le fuseau horaire local (approximation +1h pour CET)
    h = (h + 1) % 24;
    return sprintf("%02d:%02d:%02d", h, m, s);
}
BEGIN {
    duration = DURATION + 0;
    if (duration < 1) exit;
    start = START + 0;
    start_time_str = format_time(start);
    last_update = 0;
    refresh_interval = 2;
    speed = 1;
    slot = SLOT + 0;
    is_parallel = PARALLEL + 0;
    max_slots = MAX_SLOTS + 0;
}

/out_time_us=/ {
    if (match($0, /[0-9]+/)) {
        current_time = substr($0, RSTART, RLENGTH) / 1000000;
    } else {
        current_time = 0;
    }

    percent = (current_time / duration) * 100;
    if (percent > 100) percent = 100;

    now = get_time();
    elapsed = now - start;
    speed = (elapsed > 0 ? current_time / elapsed : 1);
    remaining = duration - current_time;
    eta = (speed > 0 ? remaining / speed : 0);

    h = int(eta / 3600);
    m = int((eta % 3600) / 60);
    s = int(eta % 60);
    eta_str = sprintf("%02d:%02d:%02d", h, m, s);

    bar_width = 20;
    filled = int(percent * bar_width / 100);
    bar = "";
    for (i = 0; i < filled; i++) bar = bar "█";
    for (i = filled; i < bar_width; i++) bar = bar "░";
    bar = "╢" bar "╟";

    if (NOPROG != "true" && (now - last_update >= refresh_interval || percent >= 99)) {
        if (is_parallel && slot > 0) {
            lines_up = max_slots - slot + 2;
            printf "\033[%dA\r\033[K  %s [%d] %-25.25s %s %5.1f%% | %s | ETA: %s | x%.2f\033[%dB\r",
                   lines_up, EMOJI, slot, CURRENT_FILE_NAME, bar, percent, start_time_str, eta_str, speed, lines_up > "/dev/stderr";
        } else {
            printf "\r\033[K  %s %-25.25s %s %5.1f%% | %s | ETA: %s | x%.2f",
                   EMOJI, CURRENT_FILE_NAME, bar, percent, start_time_str, eta_str, speed > "/dev/stderr";
        }
        fflush("/dev/stderr");
        last_update = now;
    }
}

/progress=end/ {
    if (NOPROG != "true") {
        bar_complete = "╢████████████████████╟";
        end_now = get_time();
        end_time_str = format_time(end_now);
        if (is_parallel && slot > 0) {
            lines_up = max_slots - slot + 2;
            printf "\033[%dA\r\033[K  %s [%d] %-25.25s %s 100.0%% | %s | %s | %s\033[%dB\r",
                   lines_up, EMOJI, slot, CURRENT_FILE_NAME, bar_complete, start_time_str, END_MSG, end_time_str, lines_up > "/dev/stderr";
        } else {
            printf "\r\033[K  %s %-25.25s %s 100.0%% | %s | %s | %s\n",
                   EMOJI, CURRENT_FILE_NAME, bar_complete, start_time_str, END_MSG, end_time_str > "/dev/stderr";
        }
        fflush("/dev/stderr");
    }
}
'

###########################################################
# COPIE AVEC PROGRESSION (custom_pv)
###########################################################

# Script AWK partagé pour l'affichage de progression (évite la duplication)
# Arguments attendus: copied, total, start, now, width, color, nocolor, newline (0 ou 1)
readonly AWK_PROGRESS_SCRIPT='
function hr(bytes,   units,i,div,val){
    units[0]="B"; units[1]="KiB"; units[2]="MiB"; units[3]="GiB"; units[4]="TiB";
    val=bytes+0;
    for(i=4;i>=0;i--){ div = 2^(10*i); if(val>=div){ return sprintf("%.2f%s", val/div, units[i]) } }
    return sprintf("%dB", bytes);
}
function hms(secs,   s,h,m){ s=int(secs+0.5); h=int(s/3600); m=int((s%3600)/60); s=s%60; return sprintf("%d:%02d:%02d", h, m, s); }
BEGIN{
    elapsed = (now - start) + 0.0;
    if(elapsed <= 0) elapsed = 0.000001;
    speed = (copied / elapsed);
    pct = (total>0 ? int( (copied*100)/total ) : (newline ? 100 : 0));
    if(pct>100) pct=100;
    filled = int(pct * width / 100);
    bar="";
    for(i=0;i<filled;i++) bar=bar"▰";
    for(i=filled;i<width;i++) bar=bar"▱";
    line = sprintf("%s %s %3d%% %s @ %.2fG/s", hms(elapsed), bar, pct, hr(copied), (speed/(1024*1024*1024)));
    # Préfixe avec la bordure de style
    prefix = "  \033[0;36m│\033[0m  ";
    if (newline) {
        printf("\r\033[K%s%s%s%s\n", prefix, color, line, nocolor);
    } else {
        printf("\r\033[K%s%s%s%s", prefix, color, line, nocolor);
    }
    fflush();
}
'

# custom_pv : remplacement simple et sûr pour les binaires de `pv` utilisant `dd` + interrogation
# de la taille de destination.
# Utilisation : custom_pv <src> <dst> [couleur]
# Remarques : utilise `dd` et `stat` ; affiche la progression sur `stderr` (colorée) et termine
# à 100% à la fin.
custom_pv() {
    local src="$1"
    local dst="$2"
    local color="${3:-$CYAN}"

    if [[ ! -f "$src" ]]; then
        return 1
    fi

    local total copied start_ts current_ts dd_pid
    total=$(stat -c%s -- "$src" 2>/dev/null) || total=0
    if [[ $total -le 0 ]]; then
        # repli : copie simple
        dd if="$src" of="$dst" bs=4M status=none 2>/dev/null
        return $?
    fi

    rm -f -- "$dst" 2>/dev/null || true

    # Démarrer dd en arrière-plan
    dd if="$src" of="$dst" bs=4M status=none &
    dd_pid=$!

    start_ts=$(now_ts)

    # Interroger la progression pendant l'exécution de dd
    while kill -0 "$dd_pid" 2>/dev/null; do
        copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
        current_ts=$(now_ts)

        # Afficher la progression (sans saut de ligne)
        awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" \
            -v width=30 -v color="$color" -v nocolor="$NOCOLOR" -v newline=0 \
            "$AWK_PROGRESS_SCRIPT" >&2

        sleep 0.5
    done

    wait "$dd_pid" 2>/dev/null || true

    # valeur finale (avec saut de ligne)
    copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
    current_ts=$(now_ts)
    awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" \
        -v width=30 -v color="$color" -v nocolor="$NOCOLOR" -v newline=1 \
        "$AWK_PROGRESS_SCRIPT" >&2

    return 0
}
