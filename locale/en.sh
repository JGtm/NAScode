#!/bin/bash
# shellcheck disable=SC2034
###########################################################
# ENGLISH LOCALE
#
# This file contains all user-facing messages in English.
# Structure: MSG_<MODULE>_<DESCRIPTION>="Message with %s placeholders"
#
# Conventions:
#   - Keys in UPPERCASE with underscores
#   - Prefix by module (ARG, UI, CONV, SYS, etc.)
#   - printf placeholders: %s (string), %d (int), %.2f (float)
###########################################################

###########################################################
# ARGUMENTS / CLI (lib/args.sh)
###########################################################

MSG_ARG_REQUIRES_VALUE="%s must be followed by a value"
MSG_ARG_LIMIT_POSITIVE="--limit must be followed by a positive number"
MSG_ARG_LIMIT_MIN_ONE="--jobs must be followed by a number >= 1"
MSG_ARG_MIN_SIZE_REQUIRED="--min-size must be followed by a size (e.g., 700M, 1G)"
MSG_ARG_MIN_SIZE_INVALID="Invalid size for --min-size: '%s' (e.g., 700M, 1G, 500000000)"
MSG_ARG_QUEUE_NOT_FOUND="Queue file '%s' not found"
MSG_ARG_FILE_NOT_FOUND="File '%s' not found"
MSG_ARG_AUDIO_INVALID="Invalid audio codec: '%s'. Accepted values: copy, aac, ac3, eac3, opus"
MSG_ARG_AUDIO_REQUIRES_VALUE="-a/--audio must be followed by a codec name (copy, aac, ac3, eac3, opus)"
MSG_ARG_CODEC_INVALID="Invalid codec: '%s'. Accepted values: hevc, av1, ..."
MSG_ARG_CODEC_REQUIRES_VALUE="--codec must be followed by a codec name (hevc, av1)"
MSG_ARG_OFF_PEAK_INVALID="Invalid format for --off-peak (expected: HH:MM-HH:MM)"
MSG_ARG_UNKNOWN_OPTION="Unknown option: %s"
MSG_ARG_UNEXPECTED="Unexpected argument: %s"
MSG_ARG_UNEXPECTED_HINT="Make sure all options are preceded by a dash (e.g., -l 3)"
MSG_ARG_LANG_INVALID="Invalid language: '%s'. Accepted values: fr, en"

###########################################################
# GENERAL / COMMON
###########################################################

MSG_UNKNOWN="unknown"

###########################################################
# SYSTEM / DEPENDENCIES (lib/system.sh)
###########################################################

MSG_SYS_DEPS_MISSING="Missing dependencies: %s"
MSG_SYS_ENV_CHECK="Environment check"
MSG_SYS_FFMPEG_VERSION_UNKNOWN="Unable to determine ffmpeg version."
MSG_SYS_FFMPEG_VERSION_OLD="FFMPEG version (%s) < Recommended (%s)"
MSG_SYS_FFMPEG_VERSION_DETECTED="Detected ffmpeg version: %s"
MSG_SYS_SOURCE_NOT_FOUND="Source '%s' not found."
MSG_SYS_SUFFIX_FORCED="Forced output suffix: %s"
MSG_SYS_SUFFIX_DISABLED="Output suffix disabled"
MSG_SYS_SUFFIX_CONTINUE_NO_SUFFIX="Continuing WITHOUT suffix. Check Dry Run or logs."
MSG_SYS_SUFFIX_CANCELLED="Operation cancelled. Change the suffix or output folder."
MSG_SYS_VMAF_NOT_AVAILABLE="VMAF requested but libvmaf not available in FFmpeg"
MSG_SYS_ENV_VALIDATED="Environment validated"
MSG_SYS_CONV_MODE_LABEL="Conversion mode"
MSG_SYS_PLEXIGNORE_EXISTS=".plexignore file already present in destination folder"
MSG_SYS_PLEXIGNORE_CREATE="Create a .plexignore file in the destination folder to avoid duplicates in Plex?"
MSG_SYS_PLEXIGNORE_CREATED=".plexignore file created in destination folder"
MSG_SYS_PLEXIGNORE_SKIPPED=".plexignore creation skipped"
MSG_SYS_NO_SUFFIX_ENABLED="--no-suffix option enabled. Suffix is disabled by command."
MSG_SYS_SUFFIX_ENABLED="Output suffix enabled"
MSG_SYS_SUFFIX_USE="Use output suffix?"
MSG_SYS_OVERWRITE_RISK_TITLE="OVERWRITE RISK"
MSG_SYS_OVERWRITE_SAME_DIR="Source and output IDENTICAL: %s"
MSG_SYS_OVERWRITE_WARNING="No suffix will OVERWRITE original files!"
MSG_SYS_DRYRUN_PREVIEW="(DRY RUN MODE): Preview files that will be overwritten"
MSG_SYS_CONTINUE_NO_SUFFIX="Continue WITHOUT suffix in the same folder?"
MSG_SYS_COEXIST_MESSAGE="Original and converted files will coexist in the same folder."
MSG_SYS_VMAF_ALT_FFMPEG="VMAF via alternative FFmpeg (libvmaf detected)"

###########################################################
# QUEUE / INDEX (lib/queue.sh, lib/index.sh)
###########################################################

MSG_QUEUE_FILE_NOT_FOUND="ERROR: Queue file '%s' does not exist."
MSG_QUEUE_FILE_EMPTY="Queue file is empty"
MSG_QUEUE_FORMAT_INVALID="Invalid queue file format (NUL separator expected)"
MSG_QUEUE_VALID="Queue file seems valid (%s files detected)."
MSG_QUEUE_VALIDATED="Queue file validated: %s"
MSG_QUEUE_LIMIT_RANDOM="Selecting %s file(s) maximum"
MSG_QUEUE_LIMIT_NORMAL="%s file(s) maximum"
MSG_INDEX_REGEN_FORCED="Forced index regeneration requested."
MSG_INDEX_NO_META="No metadata for existing index, regenerating..."
MSG_INDEX_SOURCE_NOT_IN_META="Source not found in metadata, regenerating..."
MSG_INDEX_SOURCE_CHANGED="Source changed, automatic index regeneration."
MSG_INDEX_SOURCE_CHANGED_DETAIL="Source has changed:"
MSG_INDEX_REGEN_AUTO="Automatic index regeneration..."
MSG_INDEX_EMPTY="Index empty, regeneration required..."
MSG_INDEX_CREATED_FOR="Index created for"
MSG_INDEX_CURRENT_SOURCE="Current source"
MSG_INDEX_CUSTOM_QUEUE="Using custom queue file: %s"
MSG_INDEX_FORCED_USE="Forced use of existing index"
MSG_INDEX_FOUND_TITLE="Existing index found"
MSG_INDEX_CREATION_DATE="Creation date: %s"
MSG_INDEX_KEEP_QUESTION="Keep this index file?"
MSG_INDEX_REGENERATING="Regenerating new index..."
MSG_INDEX_KEPT="Existing index kept"

###########################################################
# LOCK / INTERRUPTION (lib/lock.sh)
###########################################################

MSG_LOCK_INTERRUPT="Interruption detected, stopping..."
MSG_LOCK_ALREADY_RUNNING="Script already running (PID %s)."
MSG_LOCK_STALE="Lock file found but process absent. Cleaning up..."

###########################################################
# PROCESSING (lib/processing.sh)
###########################################################

MSG_PROC_INTERRUPTED="Processing interrupted (stop requested during wait)"
MSG_PROC_MKFIFO_FAILED="Unable to create FIFO (mkfifo). Falling back to --limit mode without dynamic replacement."
MSG_PROC_MKFIFO_NOT_FOUND="mkfifo not found: --limit mode without dynamic replacement."
MSG_PROC_ALL_OPTIMIZED="All remaining files are already optimized."

###########################################################
# OFF-PEAK HOURS (lib/off_peak.sh)
###########################################################

MSG_OFF_PEAK_STOP="Stop requested during off-peak hours wait"

###########################################################
# CONVERSION (lib/conversion.sh, lib/finalize.sh)
###########################################################

MSG_CONV_EMPTY_ENTRY="Empty entry detected in queue, skipping."
MSG_CONV_FILE_NOT_FOUND="File not found, skipping: %s"
MSG_CONV_METADATA_ERROR="Unable to read metadata, skipping: %s"
MSG_CONV_PREP_FAILED="Path preparation failed: %s"
MSG_CONV_TMP_NOT_FOUND="ERROR: Temporary file not found after encoding: %s"
MSG_CONV_GAIN_REDIRECT="Insufficient gain: output redirected to %s"
MSG_CONV_FAILED="Conversion failed: %s"
MSG_CONV_INTERRUPTED="Conversion interrupted, temporary file preserved: %s"
MSG_CONV_MOVE_ERROR="ERROR: Unable to move (custom_pv): %s"

###########################################################
# TRANSCODING (lib/transcode_video.sh)
###########################################################

MSG_TRANSCODE_UNKNOWN_MODE="Unknown encoding mode: %s"
MSG_TRANSCODE_PASS1_ERROR="Error during analysis (pass 1)"

###########################################################
# FFMPEG PIPELINE (lib/ffmpeg_pipeline.sh)
###########################################################

MSG_FFMPEG_UNKNOWN_MODE="Unknown FFmpeg mode: %s"
MSG_FFMPEG_SHORT_VIDEO="Short video: %ss segment starting at %s"
MSG_FFMPEG_REMUX_ERROR="Error during remuxing"
MSG_PROGRESS_DONE="Done ✅"
MSG_PROGRESS_ANALYSIS_OK="Analysis OK"

###########################################################
# VMAF (lib/vmaf.sh)
###########################################################

MSG_VMAF_FPS_IGNORED="VMAF ignored (FPS changed: %s → %s)"
MSG_VMAF_FILE_NOT_FOUND="NA (file not found)"
MSG_VMAF_FILE_EMPTY="NA (empty file)"
MSG_VMAF_QUALITY_EXCELLENT="Excellent"
MSG_VMAF_QUALITY_VERY_GOOD="Very good"
MSG_VMAF_QUALITY_GOOD="Good"
MSG_VMAF_QUALITY_DEGRADED="Degraded"
MSG_VMAF_QUALITY_NA="N/A"

###########################################################
# CONFIGURATION (lib/config.sh)
###########################################################

MSG_CFG_UNKNOWN_MODE="Unknown conversion mode: %s"
MSG_CFG_ENCODER_INVALID="Invalid codec configuration. Verify that FFmpeg supports encoder %s."
MSG_CFG_CODEC_UNSUPPORTED="Unsupported codec: %s"
MSG_CFG_CODEC_AVAILABLE="Available codecs: %s"
MSG_CFG_ENCODER_UNAVAILABLE="Encoder not available in FFmpeg: %s"

###########################################################
# UI / DISPLAY (lib/ui.sh)
###########################################################

MSG_UI_REDIRECT_TITLE="Output redirected"
MSG_UI_REDIRECT_MSG="Insufficient gain: file moved to %s"
MSG_UI_COEXIST_TITLE="File coexistence"
MSG_UI_TASKS_END="End of tasks"

###########################################################
# NASCODE (entry point)
###########################################################

MSG_MAIN_LIB_NOT_FOUND="ERROR: lib directory not found: %s"
MSG_MAIN_LIB_HINT="Make sure all modules are present in the lib/ folder"
MSG_MAIN_PATH_INVALID="ERROR: Invalid file path: %s"
MSG_MAIN_FILE_NOT_EXIST="ERROR: Source file does not exist: %s"
MSG_MAIN_DIR_NOT_EXIST="ERROR: Source directory does not exist: %s"
MSG_MAIN_SOURCE_EXCLUDED="ERROR: Source directory is excluded by configuration (EXCLUDES): %s"
MSG_MAIN_STOP_BEFORE_PROC="Stop requested before processing started."
MSG_MAIN_DRYRUN_DONE="🧪 Dry run completed"

###########################################################
# CLI HELP (show_help)
###########################################################

MSG_HELP_USAGE="Usage:"
MSG_HELP_OPTIONS="Options:"
MSG_HELP_SOURCE="Source folder (ARG) [default: parent folder]"
MSG_HELP_OUTPUT="Destination folder (ARG) [default: \`Converted\` at script level]"
MSG_HELP_EXCLUDE="Add an exclusion pattern (ARG)"
MSG_HELP_MODE="Conversion mode: film, adaptive, serie (ARG) [default: serie]"
MSG_HELP_MIN_SIZE="Filter index/queue: keep only files >= SIZE (e.g., 700M, 1G)"
MSG_HELP_DRYRUN="Simulation mode without conversion (FLAG)"
MSG_HELP_SUFFIX="Enable dynamic suffix or set a custom suffix (optional ARG)"
MSG_HELP_NO_SUFFIX="Disable _x265 suffix (FLAG)"
MSG_HELP_RANDOM="Random sort: select random files (FLAG) [default: 10]"
MSG_HELP_LIMIT="Limit processing to N files (ARG)"
MSG_HELP_JOBS="Number of parallel conversions (ARG) [default: 1]"
MSG_HELP_QUEUE="Use a custom queue file (ARG)"
MSG_HELP_NO_PROGRESS="Disable progress indicator display (FLAG)"
MSG_HELP_QUIET="Quiet mode: show only warnings/errors (FLAG)"
MSG_HELP_HELP="Show this help (FLAG)"
MSG_HELP_KEEP_INDEX="Keep existing index without interactive prompt (FLAG)"
MSG_HELP_REGEN_INDEX="Force index regeneration at startup (FLAG)"
MSG_HELP_VMAF="Enable VMAF video quality evaluation (FLAG) [disabled by default]"
MSG_HELP_SAMPLE="Test mode: encode only 30s at a random position (FLAG)"
MSG_HELP_FILE="Convert a single file (bypass index/queue) (ARG)"
MSG_HELP_AUDIO="Target audio codec: copy, aac, ac3, eac3, opus (ARG) [default: aac]"
MSG_HELP_AUDIO_HINT="Multi-channel (5.1+): default target = EAC3 384k\n                                 AAC in multi-channel: only with -a aac --force-audio"
MSG_HELP_TWO_PASS="Force two-pass mode (default: single-pass CRF 21 for series)"
MSG_HELP_CODEC="Target video codec: hevc, av1 (ARG) [default: hevc]"
MSG_HELP_OFF_PEAK="Off-peak mode: process only during off-peak hours"
MSG_HELP_OFF_PEAK_HINT="RANGE in HH:MM-HH:MM format (optional ARG) [default: 22:00-06:00]"
MSG_HELP_FORCE_AUDIO="Force audio conversion to target codec (bypass smart codec)"
MSG_HELP_FORCE_VIDEO="Force video re-encoding (bypass smart codec)"
MSG_HELP_FORCE="Shortcut for --force-audio and --force-video"
MSG_HELP_NO_LOSSLESS="Convert lossless/premium codecs (DTS/DTS-HD/TrueHD/FLAC)"
MSG_HELP_NO_LOSSLESS_HINT="Stereo → target codec, Multi-channel → EAC3 384k 5.1"
MSG_HELP_EQUIV_QUALITY="Enable \"equivalent quality\" mode (audio + video cap)"
MSG_HELP_NO_EQUIV_QUALITY="Disable \"equivalent quality\" mode (audio + video cap)"
MSG_HELP_EQUIV_QUALITY_HINT="Ignored in adaptive mode (stays enabled)"
MSG_HELP_LANG="Interface language: fr, en (ARG) [default: fr]"

MSG_HELP_SHORT_OPTIONS_TITLE="Note on grouped short options:"
MSG_HELP_SHORT_OPTIONS_DESC="Short options can be grouped when they are flags (no argument),\n        for example: -xdrk is equivalent to -x -d -r -k."
MSG_HELP_SHORT_OPTIONS_ARG="Options expecting an argument (marked (ARG) above: -s, -o, -e, -m, -l, -j, -q)\n        must be provided separately with their value, for example: -l 5 or --limit 5."
MSG_HELP_SHORT_OPTIONS_EXAMPLE="for example: ./conversion.sh -xdrk -l 5  (grouped flags then -l 5 separately),\n                      ./conversion.sh --source /path --limit 10."

MSG_HELP_SMART_CODEC_TITLE="Smart Codec logic (audio):"
MSG_HELP_SMART_CODEC_DESC="By default, if the source has a more efficient audio codec than the target, it is preserved.\n  Hierarchy (best to worst): Opus > AAC > E-AC3 > AC3\n  Bitrate is limited by effective codec (e.g., Opus max 128k, AAC max 160k).\n  Use --force-audio to always convert to target codec."

MSG_HELP_MODES_TITLE="Conversion modes:"
MSG_HELP_MODE_FILM="Maximum quality (two-pass ABR, fixed bitrate)"
MSG_HELP_MODE_ADAPTATIF="Adaptive bitrate per file based on complexity (constrained CRF)"
MSG_HELP_MODE_SERIE="Good size/quality balance [default]"

MSG_HELP_OFF_PEAK_TITLE="Off-peak mode:"
MSG_HELP_OFF_PEAK_DESC="Limits processing to defined periods (default 10pm-6am).\n  If a file is in progress when peak hours arrive, it finishes.\n  The script then waits for off-peak hours to resume."

MSG_HELP_EXAMPLES_TITLE="Examples:"

###########################################################
# GENERIC WARNINGS
###########################################################

MSG_WARN_VMAF_DRYRUN="VMAF disabled in dry-run mode"
MSG_WARN_SAMPLE_DRYRUN="Sample mode ignored in dry-run mode"

###########################################################
# UI OPTIONS (lib/ui_options.sh)
###########################################################

MSG_UI_OPT_ACTIVE_PARAMS="Active parameters"
MSG_UI_OPT_VMAF_ENABLED="VMAF evaluation enabled"
MSG_UI_OPT_LIMIT="LIMIT"
MSG_UI_OPT_RANDOM_MODE="Random mode: enabled"
MSG_UI_OPT_SORT_RANDOM="random (selection)"
MSG_UI_OPT_SORT_SIZE_DESC="size descending"
MSG_UI_OPT_SORT_SIZE_ASC="size ascending"
MSG_UI_OPT_SORT_NAME_ASC="name ascending"
MSG_UI_OPT_SORT_NAME_DESC="name descending"
MSG_UI_OPT_SORT_QUEUE="Queue sort order"
MSG_UI_OPT_SAMPLE="Sample mode: 30s at random position"
MSG_UI_OPT_DRYRUN="Dry-run mode: simulation without conversion"
MSG_UI_OPT_VIDEO_CODEC="Video codec"
MSG_UI_OPT_AUDIO_CODEC="Audio codec"
MSG_UI_OPT_SOURCE="Source"
MSG_UI_OPT_DEST="Destination"
MSG_UI_OPT_FILE_COUNT="Files to process"
MSG_UI_OPT_HFR_LIMITED="HFR videos: limited to %s fps"
MSG_UI_OPT_HFR_BITRATE="HFR videos: adjusted bitrate (original fps preserved)"

###########################################################
# UI MESSAGES (lib/ui.sh)
###########################################################

MSG_UI_DOWNLOAD_TEMP="Downloading to temporary folder"
MSG_UI_FILES_INDEXED="%d files indexed"
MSG_UI_SUMMARY_TITLE="CONVERSION SUMMARY"
MSG_UI_TRANSFERS_DONE="All transfers completed"
MSG_UI_VMAF_DONE="VMAF analyses completed"
MSG_UI_VMAF_TITLE="VMAF ANALYSIS"
MSG_UI_CONVERSIONS_DONE="All conversions completed"
MSG_UI_SKIP_NO_VIDEO="SKIPPED (No video stream)"
MSG_UI_SKIP_EXISTS="SKIPPED (Output file already exists)"
MSG_UI_SKIP_HEAVIER_EXISTS="SKIPPED (Heavier output already exists)"
MSG_UI_VIDEO_PASSTHROUGH="Audio needs optimization"
MSG_UI_REENCODE_BITRATE="Bitrate too high"
MSG_UI_CONVERSION_AUDIO_ONLY="Conversion required: audio needs optimization (video preserved)"
MSG_UI_NO_CONVERSION="No conversion needed"
MSG_UI_DOWNSCALE="Downscale enabled: %sx%s → Max %sx%s"
MSG_UI_10BIT="10-bit output enabled"
MSG_UI_AUDIO_DOWNMIX="Multichannel audio (%sch) → Stereo downmix"
MSG_UI_AUDIO_KEEP_LAYOUT="5.1 multichannel audio (%sch) → Layout preserved (no stereo downmix)"
MSG_UI_VIDEO_OPTIMIZED="Video codec already optimized → Audio-only conversion"
MSG_UI_START_FILE="Starting file"
MSG_UI_FILES_TO_PROCESS="%s file(s) to process"
MSG_UI_INDEXING="Indexing"
MSG_UI_FILES="files"
MSG_UI_PROGRESS_PROCESSING="Processing"
MSG_UI_REASON_NO_VIDEO="No video stream"
MSG_UI_REASON_ALREADY_OPTIMIZED="Already %s & optimized bitrate"
MSG_UI_REASON_ALREADY_OPTIMIZED_ADAPTIVE="Already %s & optimized bitrate (adaptive)"
MSG_UI_CONVERSION_REQUIRED="Conversion required"
MSG_UI_CONVERSION_REQUIRED_CODEC="Conversion required: codec %s → %s (source: %s kbps)"
MSG_UI_CONVERSION_REQUIRED_BITRATE="Conversion required: bitrate %s kbps (%s) > %s kbps (%s)"
MSG_UI_CONVERSION_REQUIRED_BITRATE_NO_DOWNGRADE="Conversion not required: bitrate %s kbps (%s) ≤ %s kbps (%s) (no downgrade for %s)"
MSG_UI_FILES_PENDING="%s file(s) pending"
MSG_UI_FILES_TO_ANALYZE="%s file(s) to analyze"

###########################################################
# SUMMARY (lib/summary.sh)
###########################################################

MSG_SUMMARY_TITLE="Summary"
MSG_SUMMARY_DURATION="Duration"
MSG_SUMMARY_RESULT="Result"
MSG_SUMMARY_ANOMALIES="Anomalies"
MSG_SUMMARY_SPACE="Space"
MSG_SUMMARY_NO_FILES="No files to process"
MSG_SUMMARY_END_DATE_LABEL="End date"
MSG_SUMMARY_TOTAL_DURATION_LABEL="Total duration"
MSG_SUMMARY_SUCCESS_LABEL="Success"
MSG_SUMMARY_SKIPPED_LABEL="Skipped"
MSG_SUMMARY_ERRORS_LABEL="Errors"
MSG_SUMMARY_ANOMALIES_TITLE="Anomalies"
MSG_SUMMARY_ANOM_SIZE_LABEL="Size"
MSG_SUMMARY_ANOM_INTEGRITY_LABEL="Integrity"
MSG_SUMMARY_ANOM_VMAF_LABEL="VMAF"
MSG_SUMMARY_SPACE_SAVED_LABEL="Space saved"

###########################################################
# COMPLEXITY (lib/complexity.sh)
###########################################################

MSG_COMPLEX_ANALYZING="Complexity analysis of file"
MSG_COMPLEX_RESULTS="Analysis results"
MSG_COMPLEX_SPATIAL="Spatial complexity (SI)"
MSG_COMPLEX_TEMPORAL="Temporal complexity (TI)"
MSG_COMPLEX_VALUE="Complexity (C)"
MSG_COMPLEX_PROGRESS_RUNNING="Computing..."
MSG_COMPLEX_PROGRESS_DONE="Done"
MSG_COMPLEX_SITI_RUNNING="SI/TI analysis..."
MSG_COMPLEX_SITI_DONE="SI/TI done"
MSG_COMPLEX_STDDEV_LABEL="Coefficient of variation (stddev)"
MSG_COMPLEX_TARGET_BITRATE_LABEL="Target bitrate (encoding)"
MSG_COMPLEX_DESC_STATIC="static → simple scene, low motion, easy to compress"
MSG_COMPLEX_DESC_STANDARD="standard → normal motion, average compressibility"
MSG_COMPLEX_DESC_COMPLEX="complex → high motion/details, harder to compress"

###########################################################
# TRANSFER (lib/transfer.sh)
###########################################################

MSG_TRANSFER_REMAINING="%s transfer(s) remaining..."
MSG_TRANSFER_BG_STARTED="Transfer started in background"
MSG_TRANSFER_WAIT="Waiting for transfer to finish... (%s in progress)"
MSG_TRANSFER_SLOT_AVAILABLE="Transfer slot available"

###########################################################
# OFF-PEAK (lib/off_peak.sh) - additions
###########################################################

MSG_OFF_PEAK_WAIT_PERIODS="Wait periods"
MSG_OFF_PEAK_TOTAL="total"
MSG_OFF_PEAK_MODE_TITLE="OFF-PEAK MODE ENABLED"
MSG_OFF_PEAK_STATUS="Status"
MSG_OFF_PEAK_IMMEDIATE="Off-peak hours - immediate start"
MSG_OFF_PEAK_MODE_LABEL="Off-peak mode"
MSG_OFF_PEAK_RANGE_LABEL="Time range"
MSG_OFF_PEAK_STATUS_ACTIVE="Off-peak hours (active)"
MSG_OFF_PEAK_STATUS_WAIT="Peak hours (wait ~%s)"
MSG_OFF_PEAK_DETECTED="Peak hours detected (%s = off-peak)"
MSG_OFF_PEAK_WAIT_EST="Estimated wait: %s (resume at %s)"
MSG_OFF_PEAK_CHECK_INTERVAL="Checking every %ss... (Ctrl+C to cancel)"
MSG_OFF_PEAK_REMAINING="Estimated remaining time: %s"
MSG_OFF_PEAK_RESUME="Off-peak hours! Resuming processing (waited %s)"

###########################################################
# NOTIFY FORMAT (lib/notify_format.sh)
###########################################################

MSG_NOTIFY_FILE_START="Starting file"
MSG_NOTIFY_CONV_DONE="Conversion completed in"
MSG_NOTIFY_TRANSFERS_DONE="Transfers completed"
MSG_NOTIFY_ANALYSIS_START="Starting analysis"
MSG_NOTIFY_ANALYSIS_STARTED="Complexity analysis…"
MSG_NOTIFY_DISABLED="disabled"
MSG_NOTIFY_SUMMARY_TITLE="Summary"
MSG_NOTIFY_END_LABEL="End"
MSG_NOTIFY_DURATION_LABEL="Duration"
MSG_NOTIFY_RESULTS_LABEL="Results"
MSG_NOTIFY_SUCCESS_LABEL="Success"
MSG_NOTIFY_SKIPPED_LABEL="Skipped"
MSG_NOTIFY_ERRORS_LABEL="Errors"
MSG_NOTIFY_ANOMALIES_LABEL="Anomalies"
MSG_NOTIFY_ANOM_SIZE_LABEL="Size"
MSG_NOTIFY_ANOM_INTEGRITY_LABEL="Integrity"
MSG_NOTIFY_ANOM_VMAF_LABEL="VMAF"
MSG_NOTIFY_SPACE_SAVED_LABEL="Space saved"
MSG_NOTIFY_SESSION_DONE_OK="Session completed"
MSG_NOTIFY_SESSION_DONE_INTERRUPTED="Session interrupted"
MSG_NOTIFY_SESSION_DONE_ERROR="Session ended with error (code %s)"
MSG_NOTIFY_SKIPPED_TITLE="Skipped"
MSG_NOTIFY_REASON_LABEL="Reason"
MSG_NOTIFY_RUN_TITLE="Run"
MSG_NOTIFY_START_LABEL="Start"
MSG_NOTIFY_ACTIVE_PARAMS_LABEL="Active parameters"
MSG_NOTIFY_MODE_LABEL="Mode"
MSG_NOTIFY_SOURCE_LABEL="Source"
MSG_NOTIFY_DEST_LABEL="Destination"
MSG_NOTIFY_VIDEO_CODEC_LABEL="Video codec"
MSG_NOTIFY_AUDIO_CODEC_LABEL="Audio codec"
MSG_NOTIFY_HFR_LABEL="HFR"
MSG_NOTIFY_HFR_LIMITED="Limited to %s fps"
MSG_NOTIFY_HFR_ADJUSTED="Adjusted bitrate (original fps kept)"
MSG_NOTIFY_LIMIT_LABEL="Limit"
MSG_NOTIFY_LIMIT_MAX="max %s"
MSG_NOTIFY_DRYRUN_LABEL="Dry-run"
MSG_NOTIFY_SAMPLE_LABEL="Sample mode"
MSG_NOTIFY_VMAF_LABEL="VMAF"
MSG_NOTIFY_OFF_PEAK_LABEL="Off-peak"
MSG_NOTIFY_JOBS_LABEL="Parallel jobs"
MSG_NOTIFY_QUEUE_TITLE="Queue"
MSG_NOTIFY_CONV_LAUNCH="Starting conversion"
MSG_NOTIFY_SPEED_LABEL="Speed"
MSG_NOTIFY_ETA_LABEL="ETA"
MSG_NOTIFY_FILES_COUNT="%s files"
MSG_NOTIFY_TRANSFERS_PENDING="Transfers pending"
MSG_NOTIFY_VMAF_STARTED_TITLE="VMAF analysis started"
MSG_NOTIFY_FILES_LABEL="Files"
MSG_NOTIFY_FILE_LABEL="File"
MSG_NOTIFY_VMAF_DONE_TITLE="VMAF analysis completed"
MSG_NOTIFY_VMAF_ANALYZED_LABEL="Analyzed"
MSG_NOTIFY_VMAF_AVG_LABEL="Average"
MSG_NOTIFY_VMAF_MINMAX_LABEL="Min / Max"
MSG_NOTIFY_VMAF_DEGRADED_LABEL="Degraded"
MSG_NOTIFY_VMAF_WORST_LABEL="Worst files"
MSG_NOTIFY_PEAK_PAUSE_TITLE="Pause (peak hours)"
MSG_NOTIFY_PEAK_RESUME_TITLE="Resume (off-peak)"
MSG_NOTIFY_OFF_PEAK_RANGE_LABEL="Off-peak range"
MSG_NOTIFY_WAIT_ESTIMATED_LABEL="Estimated wait"
MSG_NOTIFY_RESUME_AT_LABEL="Resume at"
MSG_NOTIFY_CHECK_EVERY_LABEL="Check every"
MSG_NOTIFY_SECONDS="%ss"
MSG_NOTIFY_WAIT_ACTUAL_LABEL="Actual wait"
MSG_NOTIFY_RUN_END_OK="End"
MSG_NOTIFY_RUN_END_INTERRUPTED="Interrupted"
MSG_NOTIFY_RUN_END_ERROR="Error (code %s)"

###########################################################
# FFMPEG PIPELINE (lib/ffmpeg_pipeline.sh) - additions
###########################################################

MSG_FFMPEG_SEGMENT="Segment of %ss starting from %s"

###########################################################
# FINALIZE (lib/finalize.sh) - additions
###########################################################

MSG_FINAL_GENERATED="GENERATED"
MSG_FINAL_ANOMALY_COUNT="%d naming ANOMALY(IES) found."
MSG_FINAL_ANOMALY_HINT="Please check for special characters or encoding issues for these files."
MSG_FINAL_NO_ANOMALY="No naming anomalies detected."
MSG_FINAL_COMPARE_IGNORED="Name comparison ignored."
MSG_FINAL_FFMPEG_ERROR="Detailed FFMPEG error"
MSG_FINAL_INTERRUPTED="INTERRUPTED"
MSG_FINAL_TEMP_KEPT="temp file kept"
MSG_FINAL_TEMP_MISSING="temp file missing"
MSG_FINAL_CONV_DONE="Conversion completed in %s"
MSG_FINAL_SHOW_COMPARISON="Show comparison of original and generated filenames?"
MSG_LOG_HEAVIER_FILE="HEAVIER FILE"
MSG_LOG_DISK_SPACE="Insufficient disk space in %s (%s MB free)"
MSG_FINAL_FILENAME_SIM_TITLE="FILENAME SIMULATION"
###########################################################
# QUEUE (lib/queue.sh) - additions
###########################################################

MSG_QUEUE_NO_FILES="No files to process found (check filters or source)."
MSG_QUEUE_RANDOM_SELECTED="Randomly selected files"

###########################################################
# TRANSCODE VIDEO (lib/transcode_video.sh) - additions
###########################################################

MSG_TRANSCODE_FFMPEG_LOG="Last lines of ffmpeg log (%s)"
