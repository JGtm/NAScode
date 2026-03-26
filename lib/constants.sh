#!/bin/bash
###########################################################
# CONSTANTES GLOBALES
#
# Ce module centralise les "magic numbers" et constantes
# configurables du projet. Chargé en premier par nascode.
#
# Toutes les constantes utilisent la syntaxe "${VAR:-default}"
# pour permettre l'override via variables d'environnement.
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les modules sont sourcés, pas exécutés directement
###########################################################

# Protection double-load
if [[ -n "${_CONSTANTS_SH_LOADED:-}" ]]; then
    return 0
fi
_CONSTANTS_SH_LOADED=1

###########################################################
# AUDIO — DÉCISION DE RÉENCODAGE (audio_decision.sh)
###########################################################

# Marge de tolérance au-dessus du bitrate cible avant de déclencher un downscale.
# Valeur en pourcentage exprimée sous forme de multiplicateur entier /100.
# 110 = 10% de marge : si source ≤ cible × 1,10, on copie plutôt que downscaler.
AUDIO_BITRATE_MARGIN_PCT="${AUDIO_BITRATE_MARGIN_PCT:-110}"

###########################################################
# MODE ADAPTATIF — PLAFONDS (complexity.sh)
###########################################################

# Plafond du bitrate cible en mode adaptatif, exprimé en % du bitrate original.
# Évite de dépasser 75% du bitrate source (pas de sens d'encoder plus cher que l'original).
ADAPTIVE_MAX_ORIGINAL_PCT="${ADAPTIVE_MAX_ORIGINAL_PCT:-75}"

###########################################################
# FFMPEG — ANALYSE DES STREAMS (transcode_video.sh, ffmpeg_pipeline.sh)
###########################################################

# Taille maximale de données analysées par FFmpeg pour détecter les paramètres
# des streams (résolution, codec, canaux audio, etc.).
# La valeur par défaut FFmpeg (5 Mo) est insuffisante pour les remux Blu-ray avec
# de nombreux streams (8+), en particulier les sous-titres PGS.
FFMPEG_PROBESIZE="${FFMPEG_PROBESIZE:-100M}"

# Durée maximale analysée par FFmpeg pour détecter les paramètres des streams.
# Augmenté pour éviter les erreurs "unspecified size" sur les remux Blu-ray.
FFMPEG_ANALYZEDURATION="${FFMPEG_ANALYZEDURATION:-100M}"

###########################################################
# MODE ADAPTATIF (complexity.sh)
###########################################################

# BPP (Bits Per Pixel) de référence pour HEVC
# Calibré pour produire ~1500-2500 kbps en 1080p@24fps
ADAPTIVE_BPP_BASE="${ADAPTIVE_BPP_BASE:-0.032}"

# Coefficient de complexité : bornes min/max
ADAPTIVE_C_MIN="${ADAPTIVE_C_MIN:-0.85}"
ADAPTIVE_C_MAX="${ADAPTIVE_C_MAX:-1.25}"

# Seuils de mapping std-dev → coefficient C
# Basés sur l'écart-type normalisé des tailles de frames
ADAPTIVE_STDDEV_LOW="${ADAPTIVE_STDDEV_LOW:-0.20}"    # En dessous : contenu statique
ADAPTIVE_STDDEV_HIGH="${ADAPTIVE_STDDEV_HIGH:-0.45}"  # Au dessus : contenu très complexe

# Durée d'échantillon par point (secondes)
ADAPTIVE_SAMPLE_DURATION="${ADAPTIVE_SAMPLE_DURATION:-10}"

# Nombre de points d'échantillonnage pour l'analyse de complexité
ADAPTIVE_SAMPLE_COUNT="${ADAPTIVE_SAMPLE_COUNT:-12}"

# Marge début/fin pour éviter les génériques (% de la durée totale)
ADAPTIVE_MARGIN_START_PCT="${ADAPTIVE_MARGIN_START_PCT:-5}"   # Évite générique début
ADAPTIVE_MARGIN_END_PCT="${ADAPTIVE_MARGIN_END_PCT:-8}"       # Évite générique fin

# Plancher qualité (kbps minimum)
ADAPTIVE_MIN_BITRATE_KBPS="${ADAPTIVE_MIN_BITRATE_KBPS:-800}"

# Facteur multiplicateur pour maxrate (ratio vs target)
ADAPTIVE_MAXRATE_FACTOR="${ADAPTIVE_MAXRATE_FACTOR:-1.4}"

# Facteur multiplicateur pour bufsize (ratio vs target)
ADAPTIVE_BUFSIZE_FACTOR="${ADAPTIVE_BUFSIZE_FACTOR:-2.5}"

# ----- Analyse SI/TI (Spatial/Temporal Information) -----
# Pondération des métriques dans le calcul du score combiné
# stddev (variation tailles frames) + SI (spatial) + TI (temporal) = 1.0
ADAPTIVE_WEIGHT_STDDEV="${ADAPTIVE_WEIGHT_STDDEV:-0.40}"   # 40% - variation frames
ADAPTIVE_WEIGHT_SI="${ADAPTIVE_WEIGHT_SI:-0.30}"           # 30% - complexité spatiale
ADAPTIVE_WEIGHT_TI="${ADAPTIVE_WEIGHT_TI:-0.30}"           # 30% - complexité temporelle

# Valeurs typiques pour normalisation (basées sur ITU-T P.910)
# SI typique: 0-100 (textures/edges), TI typique: 0-50 (mouvement)
ADAPTIVE_SI_MAX="${ADAPTIVE_SI_MAX:-100}"
ADAPTIVE_TI_MAX="${ADAPTIVE_TI_MAX:-50}"

# Activer/désactiver l'analyse SI/TI (fallback sur stddev seul si false)
ADAPTIVE_USE_SITI="${ADAPTIVE_USE_SITI:-true}"

###########################################################
# LIMITATION FPS (HFR - High Frame Rate)
###########################################################

# Seuil FPS au-delà duquel on considère le contenu comme HFR
HFR_THRESHOLD_FPS="${HFR_THRESHOLD_FPS:-30}"

# FPS cible pour la limitation (29.97 = standard NTSC, compatible partout)
LIMIT_FPS_TARGET="${LIMIT_FPS_TARGET:-29.97}"

###########################################################
# SEUILS AUDIO (audio_decision.sh, config.sh)
###########################################################

# Rang minimum pour considérer un codec comme "efficace" (à garder)
# Opus=5, AAC=4, Vorbis=3, EAC3=2, AC3=1, autres=0
AUDIO_CODEC_EFFICIENT_THRESHOLD="${AUDIO_CODEC_EFFICIENT_THRESHOLD:-3}"

# Seuil anti-upscale pour multicanal (kbps) — défini readonly dans config.sh
# Si le bitrate source est en dessous, on ne transcode pas vers un codec plus gourmand
# NOTE: AUDIO_ANTI_UPSCALE_THRESHOLD_KBPS est défini dans config.sh — NE PAS REDÉFINIR ICI

###########################################################
# TOLÉRANCE SKIP (skip_decision.sh)
###########################################################

# Pourcentage de tolérance au-dessus de MAXRATE pour décider un skip
# Ex: 10% → un fichier à 2772 kbps sera skippé si MAXRATE=2520 kbps
# NOTE: Défini comme readonly dans config.sh. Cette valeur sert de documentation.
# SKIP_TOLERANCE_PERCENT est défini dans config.sh (readonly) — NE PAS REDÉFINIR ICI

###########################################################
# NOTIFICATIONS DISCORD (notify_discord.sh)
###########################################################

# Limite de caractères Discord (API = 2000, marge = 1900)
DISCORD_CONTENT_MAX_CHARS="${DISCORD_CONTENT_MAX_CHARS:-1900}"

# Timeout curl pour l'envoi (secondes)
DISCORD_CURL_TIMEOUT="${DISCORD_CURL_TIMEOUT:-10}"

# Nombre de retries curl en cas d'échec
DISCORD_CURL_RETRIES="${DISCORD_CURL_RETRIES:-2}"

# Délai entre retries (secondes)
DISCORD_CURL_RETRY_DELAY="${DISCORD_CURL_RETRY_DELAY:-1}"

# Délai avant l'envoi de la mise à jour de progression (secondes)
# Permet à FFmpeg de stabiliser sa vitesse avant d'envoyer l'ETA
DISCORD_PROGRESS_UPDATE_DELAY="${DISCORD_PROGRESS_UPDATE_DELAY:-15}"

###########################################################
# EXPORTS
###########################################################

# Exporter les constantes pour les sous-shells (convert_file en parallèle)
# NOTE: Les readonly de config.sh sont exportés via exports.sh
export ADAPTIVE_BPP_BASE ADAPTIVE_C_MIN ADAPTIVE_C_MAX
export ADAPTIVE_STDDEV_LOW ADAPTIVE_STDDEV_HIGH
export ADAPTIVE_SAMPLE_DURATION ADAPTIVE_SAMPLE_COUNT
export ADAPTIVE_MARGIN_START_PCT ADAPTIVE_MARGIN_END_PCT
export ADAPTIVE_MIN_BITRATE_KBPS ADAPTIVE_MAXRATE_FACTOR ADAPTIVE_BUFSIZE_FACTOR
export ADAPTIVE_WEIGHT_STDDEV ADAPTIVE_WEIGHT_SI ADAPTIVE_WEIGHT_TI
export ADAPTIVE_SI_MAX ADAPTIVE_TI_MAX ADAPTIVE_USE_SITI
export AUDIO_CODEC_EFFICIENT_THRESHOLD
export HFR_THRESHOLD_FPS LIMIT_FPS_TARGET
export DISCORD_CONTENT_MAX_CHARS DISCORD_CURL_TIMEOUT DISCORD_CURL_RETRIES DISCORD_CURL_RETRY_DELAY
export DISCORD_PROGRESS_UPDATE_DELAY

