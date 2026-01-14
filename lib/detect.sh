#!/bin/bash
# shellcheck disable=SC2034
###########################################################
# DÉTECTION SYSTÈME ET OUTILS
# Module chargé en premier pour détecter l'environnement
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les tests de détection (command -v, etc.) peuvent
#    retourner des codes non-zéro (absence d'outil)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

# ----- Aides de compatibilité pour macOS / Homebrew -----
# Si l'utilisateur a installé GNU coreutils / gawk via Homebrew, privilégier leur répertoire gnubin
if command -v brew >/dev/null 2>&1; then
    core_gnubin="$(brew --prefix coreutils 2>/dev/null)/libexec/gnubin"
    if [[ -d "$core_gnubin" ]]; then
        PATH="$core_gnubin:$PATH"
    fi
    gawk_bin="$(brew --prefix gawk 2>/dev/null)/bin"
    if [[ -d "$gawk_bin" ]]; then
        PATH="$gawk_bin:$PATH"
    fi
    bash_bin="$(brew --prefix bash 2>/dev/null)/bin"
    if [[ -d "$bash_bin" ]]; then
        PATH="$bash_bin:$PATH"
    fi
fi

# ----- Détection unique des outils disponibles -----
# Ces variables sont évaluées une seule fois au démarrage pour éviter
# des appels répétitifs à `command -v` dans les fonctions utilitaires.
HAS_MD5SUM=$(command -v md5sum >/dev/null 2>&1 && echo 1 || echo 0)
HAS_MD5=$(command -v md5 >/dev/null 2>&1 && echo 1 || echo 0)
HAS_PYTHON3=$(command -v python3 >/dev/null 2>&1 && echo 1 || echo 0)
HAS_DATE_NANO=$(date +%s.%N >/dev/null 2>&1 && echo 1 || echo 0)
HAS_PERL_HIRES=$(perl -MTime::HiRes -e '1' 2>/dev/null && echo 1 || echo 0)
# Détecter si awk supporte systime() (GNU awk)
HAS_GAWK=$(awk 'BEGIN { print systime() }' 2>/dev/null | grep -qE '^[0-9]+$' && echo 1 || echo 0)
# Outils pour calcul SHA256 (vérification intégrité transfert)
HAS_SHA256SUM=$(command -v sha256sum >/dev/null 2>&1 && echo 1 || echo 0)
HAS_SHASUM=$(command -v shasum >/dev/null 2>&1 && echo 1 || echo 0)
HAS_OPENSSL=$(command -v openssl >/dev/null 2>&1 && echo 1 || echo 0)

# ----- Détection de libvmaf dans FFmpeg -----
# Le FFmpeg principal peut ne pas avoir libvmaf (ex: MSYS2 avec SVT-AV1)
# On cherche un FFmpeg alternatif qui a libvmaf si nécessaire
HAS_LIBVMAF=0
FFMPEG_VMAF=""  # FFmpeg à utiliser pour VMAF (peut être différent du principal)

# 1. Vérifier si le FFmpeg principal a libvmaf
if ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf; then
    HAS_LIBVMAF=1
    FFMPEG_VMAF="ffmpeg"
else
    # 2. Chercher un FFmpeg alternatif avec libvmaf (typiquement gyan.dev sur Windows)
    _find_ffmpeg_with_vmaf() {
        # Obtenir le nom d'utilisateur de façon portable
        local username="${USER:-${USERNAME:-$(whoami 2>/dev/null)}}"
        
        # Répertoires à scanner pour trouver un FFmpeg alternatif
        local search_dirs=(
            "/c/Users/$username/AppData/Local/Microsoft/WinGet/Packages"
            "/c/ffmpeg"
            "/c/Program Files/ffmpeg"
            "/c/tools/ffmpeg"
        )
        
        # Chercher ffmpeg (ou ffmpeg.exe) dans ces répertoires
        for search_dir in "${search_dirs[@]}"; do
            if [[ -d "$search_dir" ]]; then
                # Utiliser find pour chercher ffmpeg dans ce répertoire
                while IFS= read -r -d '' path; do
                    if [[ -x "$path" ]] && "$path" -hide_banner -filters 2>/dev/null | grep -q libvmaf; then
                        echo "$path"
                        return 0
                    fi
                done < <(find "$search_dir" -maxdepth 5 \( -name "ffmpeg" -o -name "ffmpeg.exe" \) -type f -print0 2>/dev/null)
            fi
        done
        
        # Aussi vérifier les autres ffmpeg dans le PATH (via type -a)
        while IFS= read -r path; do
            if [[ -x "$path" ]] && [[ "$path" != "$(which ffmpeg)" ]] && "$path" -hide_banner -filters 2>/dev/null | grep -q libvmaf; then
                echo "$path"
                return 0
            fi
        done < <(type -ap ffmpeg 2>/dev/null)
        
        return 1
    }
    
    FFMPEG_VMAF=$(_find_ffmpeg_with_vmaf)
    if [[ -n "$FFMPEG_VMAF" ]]; then
        HAS_LIBVMAF=1
    fi
    unset -f _find_ffmpeg_with_vmaf
fi

# ----- Détection de l'environnement MSYS/MinGW/Git Bash sur Windows -----
IS_MSYS=0
if [[ -n "${MSYSTEM:-}" ]] || [[ "$(uname -s)" =~ ^MINGW|^MSYS|^CYGWIN ]]; then
    IS_MSYS=1
fi

###########################################################
# NORMALISATION DES CHEMINS
###########################################################

# Normalisation des chemins pour éviter les problèmes de formats mixtes
# Convertit les chemins MSYS (/c/, /d/, etc.) en format Windows (C:/, D:/, etc.)
# et nettoie les doubles slashes, ./ inutiles, etc.
normalize_path() {
    local path="$1"
    [[ -z "$path" ]] && return 0

    # Sur environnement MSYS/MinGW/Git Bash, convertir /lettre/ en Lettre:/
    if [[ "$IS_MSYS" -eq 1 ]]; then
        # Convertir /c/... en C:/... (lettres de lecteur)
        if [[ "$path" =~ ^/([a-zA-Z])(/|$) ]]; then
            local drive="${BASH_REMATCH[1]}"
            drive="${drive^^}"  # Convertir en majuscule
            path="${drive}:${path:2}"
        fi
    fi

    # Nettoyer les chemins : supprimer les ./ au milieu et les doubles slashes
    # Remplacer /./ par /
    while [[ "$path" =~ /\./ ]]; do
        path="${path//\/.\//\/}"
    done
    # Supprimer les doubles slashes (sauf au début pour les chemins UNC)
    path=$(echo "$path" | sed 's#\([^:]\)//\+#\1/#g')
    # Supprimer le slash final sauf pour la racine
    [[ "$path" != "/" && "$path" != *":" ]] && path="${path%/}"

    echo "$path"
}
