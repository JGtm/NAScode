#!/bin/bash
###########################################################
# SEGMENTER — découpe et concaténation propres pour Phase C
#
# Phase C de la roadmap (docs/AV1_OPTIMIZATION_PLAN.md §C.3) :
# segmentation d'un fichier vidéo en chunks de durée fixe,
# alignés sur les keyframes, et concaténation propre des chunks
# ré-encodés. Brique de base du mode `adaptatif-vmaf`.
#
# **État actuel : STUB / squelette d'API.**
# Les fonctions retournent des codes d'erreur explicites tant
# qu'elles ne sont pas implémentées. Les signatures sont stables.
#
# NOTE: Pas de `set -euo pipefail` car sourcé.
###########################################################

###########################################################
# SEGMENTATION
###########################################################

# Découpe un fichier vidéo en segments de durée approximativement fixe,
# alignés sur les keyframes (pour permettre un ré-encodage propre).
# Crée <out_dir>/seg_<index>.<ext> + un fichier <out_dir>/segments.list
# au format compatible `ffmpeg -f concat`.
#
# Usage : _segment_video <input> <duration_s> <out_dir>
# Retourne : 0 si OK, !=0 sinon.
#
# Implémentation prévue (cf. doc roadmap §C.4) :
#   ffmpeg -hide_banner -i <input> \
#     -c copy -map 0 -f segment -segment_time <duration> \
#     -reset_timestamps 1 -segment_list <out_dir>/segments.list \
#     <out_dir>/seg_%03d.mkv
# Points de vigilance : si l'input n'a pas de keyframes alignées
# sur <duration>, ffmpeg arrondit au prochain keyframe → durée réelle
# variable. Acceptable pour le use-case (chaque segment garde sa
# cohérence interne).
_segment_video() {
    local input="$1"
    local duration_s="$2"
    local out_dir="$3"

    echo "ERROR: _segment_video is not yet implemented." >&2
    echo "       Cf. docs/AV1_OPTIMIZATION_PLAN.md §C.3 (Phase C)." >&2
    return 99
}

# Concaténation propre d'une liste de segments vers un fichier unique.
# Utilise le concat demuxer FFmpeg (`-f concat`) qui exige que tous les
# segments aient les mêmes paramètres structurels (codec, résolution,
# fps, pix_fmt). Pas de réencodage : juste un remux.
#
# Usage : _concat_segments <list_file> <output>
# Retourne : 0 si OK, !=0 sinon.
#
# Implémentation prévue :
#   ffmpeg -hide_banner -f concat -safe 0 -i <list_file> \
#     -c copy <output>
_concat_segments() {
    local list_file="$1"
    local output="$2"

    echo "ERROR: _concat_segments is not yet implemented." >&2
    echo "       Cf. docs/AV1_OPTIMIZATION_PLAN.md §C.3 (Phase C)." >&2
    return 99
}

###########################################################
# UTILITAIRES D'INSPECTION
###########################################################

# Liste les keyframes d'un fichier vidéo (timestamps en secondes).
# Utile pour valider l'alignement avant segmentation et pour le
# debug des problèmes de concaténation.
#
# Usage : _list_keyframes <input>
# Retourne : un timestamp par ligne sur stdout.
#
# Implémentation prévue :
#   ffprobe -v error -select_streams v:0 \
#     -show_entries packet=pts_time,flags \
#     -of csv=print_section=0 <input> \
#     | awk -F',' '$2 ~ /K/ { print $1 }'
_list_keyframes() {
    local input="$1"

    echo "ERROR: _list_keyframes is not yet implemented." >&2
    return 99
}
