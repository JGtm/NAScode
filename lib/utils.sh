#!/bin/bash
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

    # Bytes (nombre pur)
    if [[ "$s" =~ ^[0-9]+$ ]]; then
        echo "$s"
        return 0
    fi

    # Nombre + unité (K/M/G/T)
    if [[ "$s" =~ ^([0-9]+)([KMGT])$ ]]; then
        number="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    case "$unit" in
        K) echo $(( number * 1024 )) ;;
        M) echo $(( number * 1024 * 1024 )) ;;
        G) echo $(( number * 1024 * 1024 * 1024 )) ;;
        T) echo $(( number * 1024 * 1024 * 1024 * 1024 )) ;;
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
            printf "\033[%dA\r\033[K  %s [%d] %-45.45s %s %5.1f%% | %s | ETA: %s | x%.2f\033[%dB\r",
                   lines_up, EMOJI, slot, CURRENT_FILE_NAME, bar, percent, start_time_str, eta_str, speed, lines_up > "/dev/stderr";
        } else {
            printf "\r\033[K  %s %-45.45s %s %5.1f%% | %s | ETA: %s | x%.2f",
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
            printf "\033[%dA\r\033[K  %s [%d] %-40.40s %s 100.0%% | %s | %s | %s\033[%dB\r",
                   lines_up, EMOJI, slot, CURRENT_FILE_NAME, bar_complete, start_time_str, END_MSG, end_time_str, lines_up > "/dev/stderr";
        } else {
            printf "\r\033[K  %s %-45.45s %s 100.0%% | %s | %s | %s\n",
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
