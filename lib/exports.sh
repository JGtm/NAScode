#!/bin/bash
###########################################################
# EXPORT DES FONCTIONS ET VARIABLES
#
# Note: Les exports sont nécessaires pour que les fonctions
# soient accessibles dans les sous-processus (parallel, etc.)
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Les exports peuvent échouer si une fonction n'existe pas
#    (comportement géré par le contexte appelant)
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

export_variables() {
    # ========================================================
    # FONCTIONS : auto-export de TOUTES les fonctions définies
    # ========================================================
    # exports.sh est chargé en DERNIER (après tous les modules lib/), donc
    # `declare -F` liste l'intégralité des fonctions du programme. On les exporte
    # toutes pour les sous-shells (mode parallèle -j N).
    #
    # Remplace l'ancienne liste manuelle de ~150 `export -f` : c'était une bombe
    # à retardement — toute fonction nouvellement appelée (même transitivement)
    # depuis convert_file en sous-shell devait y être ajoutée, sinon le mode
    # parallèle cassait UNIQUEMENT au runtime (le séquentiel marchait). L'auto-
    # export est un sur-ensemble : impossible d'oublier une fonction.
    local _fn
    while IFS= read -r _fn; do
        [[ -n "$_fn" ]] || continue
        export -f "$_fn" 2>/dev/null || true
    done < <(declare -F | awk '{print $3}')

    # ========================================================
    # VARIABLES DE CONFIGURATION ENCODAGE
    # ========================================================
    export DRYRUN CONVERSION_MODE CONVERSION_ACTION KEEP_INDEX SORT_MODE
    export ENCODER_PRESET TARGET_BITRATE_KBPS TARGET_BITRATE_FFMPEG HWACCEL
    export MAXRATE_KBPS BUFSIZE_KBPS MAXRATE_FFMPEG BUFSIZE_FFMPEG X265_VBV_PARAMS
    export X265_EXTRA_PARAMS X265_PASS1_FAST
    export ENCODER_MODE_PROFILE ENCODER_MODE_PARAMS
    export SKIP_TOLERANCE_PERCENT
    export MIN_SIZE_BYTES
    export DOWNSCALE_MAX_WIDTH DOWNSCALE_MAX_HEIGHT
    export ADAPTIVE_BITRATE_BY_RESOLUTION ADAPTIVE_720P_MAX_HEIGHT ADAPTIVE_720P_SCALE_PERCENT
    export ADAPTIVE_480P_MAX_HEIGHT ADAPTIVE_480P_SCALE_PERCENT
    export MIN_TMP_FREE_MB PARALLEL_JOBS FFMPEG_MIN_VERSION

    # --- Variables mode adaptatif (complexity.sh, constants.sh) ---
    export ADAPTIVE_COMPLEXITY_MODE
    export ADAPTIVE_BPP_BASE ADAPTIVE_C_MIN ADAPTIVE_C_MAX
    export ADAPTIVE_STDDEV_LOW ADAPTIVE_STDDEV_HIGH
    export ADAPTIVE_SAMPLE_DURATION ADAPTIVE_SAMPLE_COUNT
    export ADAPTIVE_MARGIN_START_PCT ADAPTIVE_MARGIN_END_PCT
    export ADAPTIVE_MIN_BITRATE_KBPS ADAPTIVE_MAXRATE_FACTOR ADAPTIVE_BUFSIZE_FACTOR
    export ADAPTIVE_TARGET_KBPS ADAPTIVE_MAXRATE_KBPS ADAPTIVE_BUFSIZE_KBPS

    # --- Variables HFR / limitation FPS (constants.sh, config.sh) ---
    export LIMIT_FPS HFR_THRESHOLD_FPS LIMIT_FPS_TARGET
    export FPS_WAS_LIMITED FPS_ORIGINAL HFR_BITRATE_ADJUSTED HFR_FACTOR

    # --- Variables audio ---
    export AUDIO_CODEC AUDIO_BITRATE_KBPS NO_LOSSLESS FORCE_AUDIO_CODEC AUDIO_FORCE_STEREO
    export AUDIO_TRANSLATE_EQUIV_QUALITY
    export AUDIO_BITRATE_AAC_DEFAULT AUDIO_BITRATE_AC3_DEFAULT AUDIO_BITRATE_OPUS_DEFAULT
    export AUDIO_BITRATE_EAC3_DEFAULT AUDIO_BITRATE_FLAC_DEFAULT
    export AUDIO_BITRATE_OPUS_MULTICHANNEL AUDIO_BITRATE_AAC_MULTICHANNEL AUDIO_BITRATE_EAC3_MULTICHANNEL
    export AUDIO_ANTI_UPSCALE_THRESHOLD_KBPS AUDIO_CONVERSION_THRESHOLD_KBPS
    export AUDIO_CODEC_EFFICIENT_THRESHOLD

    # --- Variables Discord (constants.sh) ---
    export DISCORD_CONTENT_MAX_CHARS DISCORD_CURL_TIMEOUT DISCORD_CURL_RETRIES DISCORD_CURL_RETRY_DELAY
    export DISCORD_PROGRESS_UPDATE_DELAY

    # --- Variables vidéo ---
    export VIDEO_EQUIV_QUALITY_CAP

    # --- i18n ---
    export LANG_UI

    # ========================================================
    # VARIABLES DE CHEMINS
    # ========================================================
    export SOURCE OUTPUT_DIR TMP_DIR SCRIPT_DIR
    export LOG_DIR LOG_SESSION LOG_PROGRESS SUMMARY_FILE SUMMARY_METRICS_FILE
    export QUEUE INDEX INDEX_META INDEX_READABLE

    # ========================================================
    # VARIABLES DE QUEUE ET PROCESSING
    # ========================================================
    export WORKFIFO QUEUE_FULL NEXT_QUEUE_POS_FILE TOTAL_QUEUE_FILE
    export FIFO_WRITER_PID FIFO_WRITER_READY
    export PROCESSED_COUNT_FILE TARGET_COUNT_FILE
    export TRANSFER_PIDS_FILE MAX_CONCURRENT_TRANSFERS

    # ========================================================
    # VARIABLES D'OPTIONS
    # ========================================================
    export DRYRUN_SUFFIX SUFFIX_STRING SUFFIX_MODE NO_PROGRESS UI_QUIET STOP_FLAG LOCKFILE
    export RANDOM_MODE RANDOM_MODE_DEFAULT_LIMIT LIMIT_FILES CUSTOM_QUEUE
    export EXECUTION_TIMESTAMP EXCLUDES_REGEX VMAF_ENABLED REGENERATE_INDEX
    export SAMPLE_MODE SAMPLE_DURATION SAMPLE_MARGIN_START SAMPLE_MARGIN_END SAMPLE_KEYFRAME_POS
    export SINGLE_PASS_MODE CRF_VALUE
    export LOG_DRYRUN_COMPARISON IS_MSYS

    # ========================================================
    # VARIABLES D'AFFICHAGE
    # ========================================================
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE
    export AWK_PROGRESS_SCRIPT AWK_FFMPEG_PROGRESS_SCRIPT IO_PRIORITY_CMD
    export SLOTS_DIR

    # ========================================================
    # VARIABLES DE DÉTECTION D'OUTILS
    # ========================================================
    export HAS_MD5SUM HAS_MD5 HAS_PYTHON3
    export HAS_DATE_NANO HAS_PERL_HIRES HAS_GAWK
    export HAS_SHA256SUM HAS_SHASUM HAS_OPENSSL
    export HAS_LIBVMAF VMAF_QUEUE_FILE FFMPEG_VMAF

    # ========================================================
    # VARIABLES HEURES CREUSES
    # ========================================================
    export OFF_PEAK_ENABLED OFF_PEAK_START OFF_PEAK_END OFF_PEAK_CHECK_INTERVAL
    export OFF_PEAK_WAIT_COUNT OFF_PEAK_TOTAL_WAIT_SECONDS
}
