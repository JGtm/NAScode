#!/bin/bash
###########################################################
# FONCTIONS UTILITAIRES
# Fonctions diverses : MD5, timestamps, compteurs, exclusions
###########################################################

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
        # repli : utiliser un hash shell simple (non cryptographique mais stable)
        printf "%s" "$input" | awk '{s=0; for(i=1;i<=length($0);i++){s=(s*31+and(255, ord=ord(substr($0,i,1))));} printf "%08x", s}' 2>/dev/null || echo "00000000"
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
    # Utilise la regex pré-compilée pour une vérification O(1) au lieu de O(n)
    if [[ -n "$EXCLUDES_REGEX" ]] && [[ "$f" =~ $EXCLUDES_REGEX ]]; then
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
    for(i=0;i<filled;i++) bar=bar"=";
    if(filled<width) bar=bar">"; for(i=filled+1;i<width;i++) bar=bar" ";
    line = sprintf("%s [%5.2fGiB/s] [%s] %3d%% %s/%s", hms(elapsed), (speed/(1024*1024*1024)), bar, pct, sprintf("%6s", hr(copied)), sprintf("%6s", hr(total)));
    if (newline) {
        printf("\r\033[K%s%s%s\n", color, line, nocolor);
    } else {
        printf("\r\033[K%s%s%s", color, line, nocolor);
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
            -v width=40 -v color="$color" -v nocolor="$NOCOLOR" -v newline=0 \
            "$AWK_PROGRESS_SCRIPT" >&2

        sleep 0.5
    done

    wait "$dd_pid" 2>/dev/null || true

    # valeur finale (avec saut de ligne)
    copied=$(stat -c%s -- "$dst" 2>/dev/null || echo 0)
    current_ts=$(now_ts)
    awk -v copied="$copied" -v total="$total" -v start="$start_ts" -v now="$current_ts" \
        -v width=40 -v color="$color" -v nocolor="$NOCOLOR" -v newline=1 \
        "$AWK_PROGRESS_SCRIPT" >&2

    return 0
}
