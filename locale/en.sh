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
# SYSTEM / DEPENDENCIES (lib/system.sh)
###########################################################

MSG_SYS_DEPS_MISSING="Missing dependencies: %s"
MSG_SYS_FFMPEG_VERSION_UNKNOWN="Unable to determine ffmpeg version."
MSG_SYS_FFMPEG_VERSION_OLD="FFMPEG version (%s) < Recommended (%s)"
MSG_SYS_FFMPEG_VERSION_DETECTED="Detected ffmpeg version: %s"
MSG_SYS_SOURCE_NOT_FOUND="Source '%s' not found."
MSG_SYS_SUFFIX_FORCED="Forced output suffix: %s"
MSG_SYS_SUFFIX_DISABLED="Output suffix disabled"
MSG_SYS_SUFFIX_CONTINUE_NO_SUFFIX="Continuing WITHOUT suffix. Check Dry Run or logs."
MSG_SYS_SUFFIX_CANCELLED="Operation cancelled. Change the suffix or output folder."
MSG_SYS_VMAF_NOT_AVAILABLE="VMAF requested but libvmaf not available in FFmpeg"

###########################################################
# QUEUE / INDEX (lib/queue.sh, lib/index.sh)
###########################################################

MSG_QUEUE_FILE_NOT_FOUND="ERROR: Queue file '%s' does not exist."
MSG_QUEUE_FILE_EMPTY="Queue file is empty"
MSG_QUEUE_FORMAT_INVALID="Invalid queue file format (NUL separator expected)"
MSG_INDEX_REGEN_FORCED="Forced index regeneration requested."
MSG_INDEX_NO_META="No metadata for existing index, regenerating..."
MSG_INDEX_SOURCE_NOT_IN_META="Source not found in metadata, regenerating..."
MSG_INDEX_SOURCE_CHANGED="Source changed, automatic index regeneration."
MSG_INDEX_SOURCE_CHANGED_DETAIL="Source has changed:"
MSG_INDEX_REGEN_AUTO="Automatic index regeneration..."
MSG_INDEX_EMPTY="Index empty, regeneration required..."

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

###########################################################
# VMAF (lib/vmaf.sh)
###########################################################

MSG_VMAF_FPS_IGNORED="VMAF ignored (FPS changed: %s → %s)"

###########################################################
# CONFIGURATION (lib/config.sh)
###########################################################

MSG_CFG_UNKNOWN_MODE="Unknown conversion mode: %s"
MSG_CFG_ENCODER_INVALID="Invalid codec configuration. Verify that FFmpeg supports encoder %s."

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
MSG_UI_OPT_SORT_QUEUE="Queue sort"
MSG_UI_OPT_SAMPLE="Sample mode: 30s at random position"
MSG_UI_OPT_DRYRUN="Dry-run mode: simulation without conversion"
MSG_UI_OPT_VIDEO_CODEC="Video codec"
MSG_UI_OPT_AUDIO_CODEC="Audio codec"
MSG_UI_OPT_SOURCE="Source"
MSG_UI_OPT_DEST="Destination"
MSG_UI_OPT_FILE_COUNT="File counter"
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

###########################################################
# SUMMARY (lib/summary.sh)
###########################################################

MSG_SUMMARY_TITLE="Summary"
MSG_SUMMARY_DURATION="Duration"
MSG_SUMMARY_RESULT="Result"
MSG_SUMMARY_ANOMALIES="Anomalies"
MSG_SUMMARY_SPACE="Space"

###########################################################
# COMPLEXITY (lib/complexity.sh)
###########################################################

MSG_COMPLEX_ANALYZING="Complexity analysis of file"
MSG_COMPLEX_RESULTS="Analysis results"
MSG_COMPLEX_SPATIAL="Spatial complexity (SI)"
MSG_COMPLEX_TEMPORAL="Temporal complexity (TI)"
MSG_COMPLEX_VALUE="Complexity (C)"

###########################################################
# OFF-PEAK (lib/off_peak.sh) - additions
###########################################################

MSG_OFF_PEAK_WAIT_PERIODS="Wait periods"
MSG_OFF_PEAK_TOTAL="total"
MSG_OFF_PEAK_MODE_TITLE="OFF-PEAK MODE ENABLED"
MSG_OFF_PEAK_STATUS="Status"
MSG_OFF_PEAK_IMMEDIATE="Off-peak hours - immediate start"

###########################################################
# NOTIFY FORMAT (lib/notify_format.sh)
###########################################################

MSG_NOTIFY_FILE_START="Starting file"
MSG_NOTIFY_CONV_DONE="Conversion completed in"
MSG_NOTIFY_TRANSFERS_DONE="Transfers completed"
MSG_NOTIFY_ANALYSIS_START="Starting analysis"
MSG_NOTIFY_DISABLED="disabled"

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

###########################################################
# QUEUE (lib/queue.sh) - additions
###########################################################

MSG_QUEUE_NO_FILES="No files to process found (check filters or source)."
MSG_QUEUE_RANDOM_SELECTED="Randomly selected files"

###########################################################
# TRANSCODE VIDEO (lib/transcode_video.sh) - additions
###########################################################

MSG_TRANSCODE_FFMPEG_LOG="Last lines of ffmpeg log (%s)"
