#!/bin/bash
###########################################################
# SEGMENTER — découpe et concaténation propres pour Phase C
#
# Phase C de la roadmap (docs/AV1_OPTIMIZATION_PLAN.md §C.3) :
# segmentation d'un fichier vidéo en chunks de durée fixe,
# alignés sur les keyframes, et concaténation propre des chunks
# ré-encodés. Brique de base du mode `adaptatif-vmaf`.
#
# NOTE: Pas de `set -euo pipefail` car sourcé.
###########################################################

###########################################################
# SEGMENTATION
###########################################################

# Découpe un fichier vidéo en segments de durée approximativement fixe,
# alignés sur les keyframes (pour permettre un ré-encodage propre).
# Crée <out_dir>/seg_<index>.<ext> + <out_dir>/segments.list au format
# `ffmpeg -f concat`.
#
# Usage : _segment_video <input> <duration_s> <out_dir>
# Retourne : 0 si OK, code != 0 sinon. Écrit sur stderr en cas d'erreur.
#
# Implémentation : `ffmpeg -f segment -segment_time` qui découpe au
# prochain keyframe après chaque borne (durée réelle ≥ duration_s).
# Mode `-c copy` : aucun ré-encodage, juste un remux propre.
_segment_video() {
    local input="$1"
    local duration_s="$2"
    local out_dir="$3"

    if [[ -z "$input" || -z "$duration_s" || -z "$out_dir" ]]; then
        echo "ERROR: _segment_video usage: <input> <duration_s> <out_dir>" >&2
        return 2
    fi
    if [[ ! -f "$input" ]]; then
        echo "ERROR: _segment_video: input not found: $input" >&2
        return 2
    fi
    if ! [[ "$duration_s" =~ ^[0-9]+$ ]] || [[ "$duration_s" -lt 1 ]]; then
        echo "ERROR: _segment_video: duration_s must be a positive integer" >&2
        return 2
    fi

    mkdir -p "$out_dir" || return 3

    # Extension : on garde celle de l'input (mkv, mp4, etc.) pour rester
    # compatible avec le conteneur source. mkv par défaut si inconnu.
    local ext="${input##*.}"
    [[ -z "$ext" || "$ext" == "$input" ]] && ext="mkv"

    local pattern="${out_dir}/seg_%03d.${ext}"
    local list_file="${out_dir}/segments.list"

    # -reset_timestamps 1 : chaque segment démarre à PTS 0 → concat propre.
    # -map 0:v:0 : on prend seulement la première piste vidéo (audio remuxé
    #              séparément en fin de pipeline auto-boost).
    # -c copy : pas de ré-encodage à ce stade.
    # -segment_list ... : ffmpeg génère le fichier "concat list" pour nous.
    if ! ffmpeg -hide_banner -loglevel error -y \
        -i "$input" \
        -map 0:v:0 -c copy \
        -f segment -segment_time "$duration_s" \
        -reset_timestamps 1 \
        -segment_list "$list_file" \
        -segment_list_type ffconcat \
        "$pattern" 2>&1; then
        echo "ERROR: _segment_video: ffmpeg segment failed" >&2
        return 4
    fi

    if [[ ! -s "$list_file" ]]; then
        echo "ERROR: _segment_video: empty segments list at $list_file" >&2
        return 5
    fi
    return 0
}

# Concaténation propre d'une liste de segments vers un fichier unique.
# Utilise le concat demuxer FFmpeg (`-f concat`) qui exige que tous les
# segments aient les mêmes paramètres structurels (codec, résolution,
# fps, pix_fmt). Pas de réencodage : juste un remux.
#
# Usage : _concat_segments <list_file> <output>
# Retourne : 0 si OK, code != 0 sinon.
_concat_segments() {
    local list_file="$1"
    local output="$2"

    if [[ -z "$list_file" || -z "$output" ]]; then
        echo "ERROR: _concat_segments usage: <list_file> <output>" >&2
        return 2
    fi
    if [[ ! -f "$list_file" ]]; then
        echo "ERROR: _concat_segments: list file not found: $list_file" >&2
        return 2
    fi

    # -safe 0 : autorise les chemins absolus dans la liste (nécessaire
    # quand la liste est générée dans un répertoire temporaire).
    if ! ffmpeg -hide_banner -loglevel error -y \
        -f concat -safe 0 \
        -i "$list_file" \
        -c copy \
        "$output" 2>&1; then
        echo "ERROR: _concat_segments: ffmpeg concat failed" >&2
        return 4
    fi

    if [[ ! -s "$output" ]]; then
        echo "ERROR: _concat_segments: empty output at $output" >&2
        return 5
    fi
    return 0
}

###########################################################
# UTILITAIRES D'INSPECTION
###########################################################

# Liste les keyframes d'un fichier vidéo (timestamps en secondes).
# Utile pour valider l'alignement avant segmentation et pour le
# debug des problèmes de concaténation.
#
# Usage : _list_keyframes <input>
# Retourne : un timestamp par ligne sur stdout (code 0).
_list_keyframes() {
    local input="$1"

    if [[ -z "$input" || ! -f "$input" ]]; then
        echo "ERROR: _list_keyframes: input not found: $input" >&2
        return 2
    fi

    # ffprobe en mode packet : pour chaque packet on a pts_time et flags.
    # Un keyframe a 'K' dans flags. Sortie CSV: pts_time,flags
    ffprobe -v error -select_streams v:0 \
        -show_entries packet=pts_time,flags \
        -of csv=print_section=0 "$input" 2>/dev/null \
        | awk -F',' '$2 ~ /K/ { print $1 }'
}
