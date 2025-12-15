#!/bin/bash
###########################################################
# EXPORT DES FONCTIONS ET VARIABLES
# Pour le traitement parallèle (sous-shells)
###########################################################

export_variables() {
    # --- Fonctions de conversion ---
    export -f convert_file get_video_metadata should_skip_conversion clean_number custom_pv
    
    # --- Fonctions de préparation fichiers ---
    export -f _prepare_file_paths _check_output_exists _handle_dryrun_mode
    export -f _setup_temp_files_and_logs _check_disk_space _get_temp_filename
    
    # --- Fonctions d'analyse et copie ---
    export -f _analyze_video _copy_to_temp_storage _execute_conversion
    
    # --- Fonctions de finalisation ---
    export -f _finalize_conversion_success _finalize_try_move
    export -f _finalize_log_and_verify _finalize_conversion_error
    
    # --- Fonctions de gestion de queue ---
    export -f _handle_custom_queue _handle_existing_index
    export -f _count_total_video_files _index_video_files _generate_index
    export -f _build_queue_from_index _apply_queue_limitations _validate_queue_not_empty
    export -f _display_random_mode_selection _create_readable_queue_copy
    export -f build_queue validate_queue_file
    
    # --- Fonctions de traitement parallèle ---
    export -f prepare_dynamic_queue _process_queue_simple _process_queue_with_fifo
    export -f increment_processed_count update_queue
    
    # --- Fonctions utilitaires ---
    export -f is_excluded count_null_separated compute_md5_prefix now_ts compute_sha256
    
    # --- Fonctions VMAF (qualité vidéo) ---
    export -f compute_vmaf_score _queue_vmaf_analysis process_vmaf_queue check_vmaf
    
    # --- Variables de configuration ---
    export DRYRUN CONVERSION_MODE KEEP_INDEX SORT_MODE
    export ENCODER_PRESET TARGET_BITRATE_KBPS TARGET_BITRATE_FFMPEG HWACCEL
    export MAXRATE_KBPS BUFSIZE_KBPS MAXRATE_FFMPEG BUFSIZE_FFMPEG X265_VBV_PARAMS
    export BITRATE_CONVERSION_THRESHOLD_KBPS SKIP_TOLERANCE_PERCENT
    export MIN_TMP_FREE_MB PARALLEL_JOBS FFMPEG_MIN_VERSION
    
    # --- Variables de chemins ---
    export SOURCE OUTPUT_DIR TMP_DIR SCRIPT_DIR
    export LOG_DIR LOG_SUCCESS LOG_SKIPPED LOG_ERROR LOG_PROGRESS SUMMARY_FILE
    export QUEUE INDEX INDEX_READABLE
    
    # --- Variables de queue dynamique (mode FIFO) ---
    export WORKFIFO QUEUE_FULL NEXT_QUEUE_POS_FILE TOTAL_QUEUE_FILE
    export FIFO_WRITER_PID FIFO_WRITER_READY
    export PROCESSED_COUNT_FILE TARGET_COUNT_FILE
    
    # --- Variables d'options ---
    export DRYRUN_SUFFIX SUFFIX_STRING NO_PROGRESS STOP_FLAG
    export RANDOM_MODE RANDOM_MODE_DEFAULT_LIMIT LIMIT_FILES CUSTOM_QUEUE
    export EXECUTION_TIMESTAMP EXCLUDES_REGEX VMAF_ENABLED
    
    # --- Variables de couleurs et affichage ---
    export NOCOLOR GREEN YELLOW RED CYAN MAGENTA BLUE ORANGE
    export AWK_PROGRESS_SCRIPT IO_PRIORITY_CMD
    
    # --- Fonctions et variables de progression parallèle ---
    export -f acquire_progress_slot release_progress_slot cleanup_progress_slots setup_progress_display
    export SLOTS_DIR
    
    # --- Variables de détection d'outils ---
    export HAS_MD5SUM HAS_MD5 HAS_PYTHON3
    export HAS_DATE_NANO HAS_PERL_HIRES HAS_GAWK
    export HAS_SHA256SUM HAS_SHASUM HAS_OPENSSL
    export HAS_LIBVMAF VMAF_QUEUE_FILE
    
    # --- Export du tableau EXCLUDES ---
    ( IFS=:; export EXCLUDES="${EXCLUDES[*]}" )
}
