#!/bin/bash
###########################################################
# EXPORT DES FONCTIONS ET VARIABLES
#
# Note: Les exports sont nécessaires pour que les fonctions
# soient accessibles dans les sous-processus (parallel, etc.)
###########################################################

export_variables() {
    # ========================================================
    # FONCTIONS UTILITAIRES DE BASE
    # ========================================================
    export -f normalize_path_for_ffprobe ffprobe_safe
    
    # ========================================================
    # FONCTIONS DE CONVERSION PRINCIPALES
    # ========================================================
    export -f convert_file get_video_metadata get_video_stream_props detect_hwaccel
    export -f should_skip_conversion should_skip_conversion_adaptive
    export -f _determine_conversion_mode _display_skip_decision clean_number custom_pv
    
    # --- Fonctions codec_profiles.sh (gestion des codecs vidéo) ---
    export -f get_codec_encoder get_codec_suffix get_codec_ffmpeg_names
    export -f is_codec_match is_codec_supported get_codec_rank get_codec_efficiency
    export -f is_codec_better_or_equal convert_preset validate_codec_config
    export -f get_encoder_params_flag
    
    # --- Fonctions de paramètres vidéo (video_params.sh) ---
    export -f _select_output_pix_fmt _build_downscale_filter_if_needed
    export -f _compute_output_height_for_bitrate _compute_effective_bitrate_kbps_for_height
    export -f _build_effective_suffix_for_dims compute_video_params_adaptive
    
    # --- Fonctions d'analyse de complexité (complexity.sh) ---
    export -f analyze_video_complexity _map_stddev_to_complexity _describe_complexity
    export -f _show_analysis_progress _get_frame_sizes _compute_normalized_stddev
    export -f compute_adaptive_target_bitrate compute_adaptive_maxrate compute_adaptive_bufsize
    export -f get_adaptive_encoding_params display_complexity_analysis
    
    # --- Fonctions d'encodage (transcode_video.sh) ---
    export -f _setup_video_encoding_params _setup_sample_mode_params
    export -f _run_ffmpeg_encode _execute_conversion _execute_video_passthrough
    
    # --- Fonctions audio et sous-titres ---
    export -f _get_audio_target_bitrate _get_audio_conversion_info _build_audio_params _build_stream_mapping
    export -f _should_convert_audio _probe_audio_info _probe_audio_channels _probe_audio_full
    export -f _is_audio_multichannel _get_target_audio_layout _build_audio_layout_filter
    export -f _get_multichannel_target_bitrate _compute_eac3_target_bitrate_kbps
    export -f is_audio_codec_premium_passthrough is_audio_codec_lossless is_audio_codec_efficient
    export -f get_audio_codec_rank get_audio_ffmpeg_encoder get_audio_codec_target_bitrate
    
    # ========================================================
    # FONCTIONS DE PRÉPARATION ET FINALISATION
    # ========================================================
    export -f _get_counter_prefix
    export -f _prepare_file_paths _check_output_exists _handle_dryrun_mode
    export -f _setup_temp_files_and_logs _check_disk_space _get_temp_filename
    export -f _analyze_video _copy_to_temp_storage
    export -f _finalize_conversion_success _finalize_try_move
    export -f _finalize_log_and_verify _finalize_conversion_error
    
    # ========================================================
    # FONCTIONS DE TRANSFERT ASYNCHRONE
    # ========================================================
    export -f init_async_transfers start_async_transfer
    export -f wait_for_transfer_slot wait_all_transfers cleanup_transfers
    export -f _add_transfer_pid _cleanup_finished_transfers _count_active_transfers
    
    # ========================================================
    # FONCTIONS DE GESTION DE QUEUE
    # ========================================================
    export -f _handle_custom_queue _handle_existing_index
    export -f _normalize_source_path _validate_index_source _save_index_metadata
    export -f _count_total_video_files _index_video_files _generate_index
    export -f _build_queue_from_index _apply_queue_limitations _validate_queue_not_empty
    export -f _display_random_mode_selection _create_readable_queue_copy _show_active_options
    export -f build_queue validate_queue_file
    
    # ========================================================
    # FONCTIONS DE TRAITEMENT PARALLÈLE
    # ========================================================
    export -f prepare_dynamic_queue _process_queue_simple _process_queue_with_fifo
    export -f increment_processed_count increment_starting_counter update_queue
    
    # ========================================================
    # FONCTIONS UTILITAIRES
    # ========================================================
    export -f is_excluded count_null_separated compute_md5_prefix now_ts compute_sha256
    export -f normalize_path
    
    # --- Fonctions de logging (logging.sh) ---
    export -f log_error log_warning log_info log_success
    
    # --- Fonctions VMAF (qualité vidéo) ---
    export -f compute_vmaf_score _queue_vmaf_analysis process_vmaf_queue check_vmaf
    
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
    
    # --- Variables mode film-adaptive (complexity.sh) ---
    export ADAPTIVE_COMPLEXITY_MODE
    export ADAPTIVE_BPP_BASE ADAPTIVE_C_MIN ADAPTIVE_C_MAX
    export ADAPTIVE_STDDEV_LOW ADAPTIVE_STDDEV_HIGH
    export ADAPTIVE_SAMPLE_DURATION ADAPTIVE_MIN_BITRATE_KBPS
    export ADAPTIVE_MAXRATE_FACTOR ADAPTIVE_BUFSIZE_FACTOR
    export ADAPTIVE_TARGET_KBPS ADAPTIVE_MAXRATE_KBPS ADAPTIVE_BUFSIZE_KBPS
    
    # --- Variables audio ---
    export AUDIO_CODEC AUDIO_BITRATE_KBPS NO_LOSSLESS FORCE_AUDIO_CODEC AUDIO_FORCE_STEREO
    export AUDIO_BITRATE_AAC_DEFAULT AUDIO_BITRATE_AC3_DEFAULT AUDIO_BITRATE_OPUS_DEFAULT
    export AUDIO_BITRATE_EAC3_DEFAULT AUDIO_BITRATE_FLAC_DEFAULT
    export AUDIO_BITRATE_OPUS_MULTICHANNEL AUDIO_BITRATE_AAC_MULTICHANNEL AUDIO_BITRATE_EAC3_MULTICHANNEL
    export AUDIO_ANTI_UPSCALE_THRESHOLD_KBPS AUDIO_CONVERSION_THRESHOLD_KBPS
    
    # ========================================================
    # VARIABLES DE CHEMINS
    # ========================================================
    export SOURCE OUTPUT_DIR TMP_DIR SCRIPT_DIR
    export LOG_DIR LOG_SESSION LOG_PROGRESS SUMMARY_FILE
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
    export DRYRUN_SUFFIX SUFFIX_STRING SUFFIX_MODE NO_PROGRESS STOP_FLAG LOCKFILE
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
    
    # --- Progression parallèle ---
    export -f acquire_progress_slot release_progress_slot cleanup_progress_slots setup_progress_display
    export SLOTS_DIR
    
    # ========================================================
    # VARIABLES DE DÉTECTION D'OUTILS
    # ========================================================
    export HAS_MD5SUM HAS_MD5 HAS_PYTHON3
    export HAS_DATE_NANO HAS_PERL_HIRES HAS_GAWK
    export HAS_SHA256SUM HAS_SHASUM HAS_OPENSSL
    export HAS_LIBVMAF VMAF_QUEUE_FILE FFMPEG_VMAF
    
    # ========================================================
    # VARIABLES ET FONCTIONS HEURES CREUSES
    # ========================================================
    export OFF_PEAK_ENABLED OFF_PEAK_START OFF_PEAK_END OFF_PEAK_CHECK_INTERVAL
    export OFF_PEAK_WAIT_COUNT OFF_PEAK_TOTAL_WAIT_SECONDS
    export -f is_off_peak_time wait_for_off_peak check_off_peak_before_processing
    export -f parse_off_peak_range time_to_minutes seconds_until_off_peak format_wait_time
    export -f show_off_peak_status show_off_peak_startup_info
}
