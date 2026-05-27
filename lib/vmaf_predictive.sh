#!/bin/bash
###########################################################
# VMAF PRÉDICTIF — encode rapide + métrique par segment
#
# Phase C de la roadmap (docs/AV1_OPTIMIZATION_PLAN.md §C.3) :
# pour chaque segment d'un fichier vidéo, on encode rapidement
# avec un CRF de référence, on mesure le VMAF de la sortie vs
# la source, et on en déduit un ajustement du CRF cible pour
# l'encodage final ("boost" pour scènes difficiles, "économie"
# pour scènes faciles).
#
# Dépend de lib/vmaf.sh (compute_vmaf_score).
#
# NOTE: Pas de `set -euo pipefail` car sourcé.
###########################################################

###########################################################
# CONFIGURATION
###########################################################

# CRF de référence pour la passe d'analyse rapide (volontairement
# élevé pour rester rapide, l'objectif n'est pas la qualité finale
# mais d'identifier les scènes difficiles).
VMAF_PREDICTIVE_PROBE_CRF="${VMAF_PREDICTIVE_PROBE_CRF:-32}"

# Preset SVT-AV1 pour la passe d'analyse rapide (12 = ultra-fast).
VMAF_PREDICTIVE_PROBE_PRESET="${VMAF_PREDICTIVE_PROBE_PRESET:-12}"

# Table d'ajustement du CRF selon le VMAF moyen du segment.
# Format CSV : `min:delta,min:delta,...` (triée du plus exigeant au moins).
# Sémantique : VMAF élevé = scène facile → on peut augmenter le CRF
# (économie taille). VMAF faible = scène difficile → on baisse le CRF
# (boost qualité). Le delta retenu est celui de la première paire dont
# `min` <= VMAF observé (parcours descendant).
#
# Défaut : VMAF >= 92 → +2, 85-91 → 0, 75-84 → -2, < 75 → -4.
VMAF_PREDICTIVE_BOOST_TABLE="${VMAF_PREDICTIVE_BOOST_TABLE:-92:+2,85:0,75:-2,0:-4}"

###########################################################
# ENCODE RAPIDE
###########################################################

# Encode un segment avec un preset rapide pour analyse VMAF.
# Le but est de produire un "proxy" qui révèle les difficultés
# de compression du segment.
#
# Usage : _quick_encode_segment <input_seg> <out_seg> [crf] [preset]
# Retourne : 0 si OK, code != 0 sinon.
_quick_encode_segment() {
    local input_seg="$1"
    local out_seg="$2"
    local crf="${3:-$VMAF_PREDICTIVE_PROBE_CRF}"
    local preset="${4:-$VMAF_PREDICTIVE_PROBE_PRESET}"

    if [[ -z "$input_seg" || -z "$out_seg" ]]; then
        echo "ERROR: _quick_encode_segment usage: <input_seg> <out_seg> [crf] [preset]" >&2
        return 2
    fi
    if [[ ! -f "$input_seg" ]]; then
        echo "ERROR: _quick_encode_segment: input not found: $input_seg" >&2
        return 2
    fi

    # -an -sn : pas d'audio ni sous-titres dans le proxy (seul le signal
    # vidéo nous intéresse pour la mesure VMAF).
    # tune=0 + lp=6 : alignés sur notre profil (cohérence VMAF).
    if ! ffmpeg -hide_banner -loglevel error -y \
        -i "$input_seg" \
        -c:v libsvtav1 \
        -crf "$crf" \
        -preset "$preset" \
        -svtav1-params "tune=0:lp=6" \
        -pix_fmt yuv420p10le \
        -an -sn \
        "$out_seg" 2>&1; then
        echo "ERROR: _quick_encode_segment: ffmpeg encode failed" >&2
        return 4
    fi

    if [[ ! -s "$out_seg" ]]; then
        echo "ERROR: _quick_encode_segment: empty output at $out_seg" >&2
        return 5
    fi
    return 0
}

###########################################################
# MESURE VMAF
###########################################################

# Calcule le VMAF moyen d'un segment encodé vs son segment source.
# Réutilise compute_vmaf_score() de lib/vmaf.sh.
#
# Usage : _measure_vmaf_segment <encoded_seg> <source_seg>
# Retourne : VMAF moyen sur stdout (float 0-100) ou "NA".
_measure_vmaf_segment() {
    local encoded_seg="$1"
    local source_seg="$2"

    if [[ -z "$encoded_seg" || -z "$source_seg" ]]; then
        echo "NA"
        return 2
    fi
    if ! declare -f compute_vmaf_score >/dev/null; then
        echo "ERROR: _measure_vmaf_segment: compute_vmaf_score not sourced (load lib/vmaf.sh first)" >&2
        echo "NA"
        return 3
    fi

    # compute_vmaf_score(<original>, <converted>) — interface de lib/vmaf.sh.
    compute_vmaf_score "$source_seg" "$encoded_seg"
}

###########################################################
# CALCUL D'AJUSTEMENT
###########################################################

# Calcule le delta CRF à appliquer pour un VMAF mesuré, selon la table
# VMAF_PREDICTIVE_BOOST_TABLE. Parcourt la table dans l'ordre déclaré
# (du seuil le plus élevé au plus bas) et retourne le premier delta dont
# le seuil est <= vmaf_avg.
#
# Usage : _compute_crf_adjustment <vmaf_avg>
# Retourne : delta sur stdout (entier signé, ex. "-2", "0", "2"). 0 par
# défaut si vmaf == "NA" ou table mal formée.
_compute_crf_adjustment() {
    local vmaf_avg="$1"

    # VMAF indisponible : neutre (delta=0).
    if [[ -z "$vmaf_avg" || "$vmaf_avg" == "NA" ]]; then
        echo "0"
        return 0
    fi
    # Validation : float entre 0 et 100.
    if ! [[ "$vmaf_avg" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "0"
        return 0
    fi

    # Parcourt VMAF_PREDICTIVE_BOOST_TABLE et retourne le delta du
    # premier seuil <= vmaf_avg. Compare en awk pour gérer les floats.
    local table="${VMAF_PREDICTIVE_BOOST_TABLE:-92:+2,85:0,75:-2,0:-4}"
    awk -v vmaf="$vmaf_avg" -v table="$table" 'BEGIN {
        n = split(table, pairs, ",")
        for (i = 1; i <= n; i++) {
            if (split(pairs[i], kv, ":") != 2) continue
            min = kv[1] + 0
            delta = kv[2]
            if (vmaf + 0 >= min) {
                # Normaliser +N → N (awk gère, mais bash retient le +)
                gsub(/^\+/, "", delta)
                print delta
                exit 0
            }
        }
        print "0"
    }'
}
