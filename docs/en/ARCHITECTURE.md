# Architecture

NAScode is a **modular** Bash script oriented toward batch processing: it indexes a source, builds a queue, then converts (or skips/passthrough) files according to "smart codec" rules.

## Overview

- Entry point: [../../nascode](../../nascode)
- Modules: [../../lib/](../../lib/) directory
- Default output: `Converted/`
- Logs & session artifacts: `logs/`

## Execution Flow (folder mode)

1. **Bootstrap & config**
   - Loads modules in dependency order (UI/config/utils/logging/…)
   - Parses CLI (source, mode, codec, options)
   - Applies mode parameters via `set_conversion_mode_parameters`

2. **Pre-flight**
   - Lock (prevents multiple simultaneous executions)
   - Dependency verification (FFmpeg/ffprobe, etc.)
   - Hwaccel detection (if available)
   - VMAF verification (optional)

3. **Index + queue**
   - Building / reusing a persistent index (`logs/Index`, `logs/Index_meta`)
   - Building the queue (sort/filter/limit/random)

4. **Parallel processing**
   - Starts `convert_file` in parallel (up to `PARALLEL_JOBS`)
   - Progress via "slots" (multi-worker display)
   - `--off-peak` mode: doesn't start new conversions outside the time range

5. **Finalization**
   - Final summary, logs, temporary cleanup
   - Dry-run: filename comparison instead of encoding

## Execution Flow (single file mode)

When `-f/--file` is provided, the script bypasses index/queue and directly calls `convert_file` on a single file.

## Main Modules (map)

Loading is orchestrated by [../../nascode](../../nascode). Responsibilities are generally:

- **Constants & foundations**
  - `lib/constants.sh`: centralized magic numbers (overridable via env)
  - `lib/env.sh`: environment variables

- **CLI & UX**
  - `lib/args.sh`: option parsing
  - `lib/ui.sh`: colors/display

- **Configuration & profiles**
  - `lib/config.sh`: defaults + mode parameters
  - `lib/codec_profiles.sh`: codec→encoder mapping + profiles + bitrate translation

- **Index / queue / processing**
  - `lib/queue.sh`: persistent index, queue, sorting, filters (`--min-size`, random, limit)
  - `lib/processing.sh`: parallel execution (simple / FIFO limit mode)

- **Decision & media parameters**
  - `lib/media_probe.sh`: probes via ffprobe
  - `lib/audio_decision.sh`: "smart codec" audio decision + multichannel
  - `lib/audio_params.sh`: builds FFmpeg audio parameters (codec/layout/bitrate)
  - `lib/video_params.sh`: pix_fmt, downscale, bitrate, effective suffix
  - `lib/stream_mapping.sh`: stream mapping (e.g., subtitles)
  - `lib/skip_decision.sh`: skip/passthrough/full logic (conversion decision)

- **Conversion & FFmpeg pipeline**
  - `lib/conversion_prep.sh`: file preparation, paths, disk space, temporary transfer
  - `lib/adaptive_mode.sh`: complexity analysis for adaptive mode
  - `lib/transcode_video.sh`: FFmpeg execution (passthrough / CRF / two-pass)
  - `lib/conversion.sh`: per-file orchestration (calls modules above)

- **Quality / analysis**
  - `lib/vmaf.sh`: VMAF calculation (optional)
  - `lib/complexity.sh`: analysis for `adaptatif` mode

- **Robustness & support**
  - `lib/utils.sh`: general helpers (paths, sizes, parsing, command building)
  - `lib/logging.sh`: log files and `log_*` helpers
  - `lib/lock.sh`: lockfile + stop flag
  - `lib/system.sh` / `lib/detect.sh`: system checks, tool detection
  - `lib/off_peak.sh`: off-peak hours logic
  - `lib/finalize.sh`: summary, cleanup
  - `lib/exports.sh`: function/variable exports for subprocesses

## Artifacts (logs/Index/lock)

- **Index**
  - `logs/Index`: index (internal format)
  - `logs/Index_meta`: metadata (SOURCE, date, etc.)
  - `logs/Index_readable_*.txt`: readable versions

- **Queue**
  - `logs/Queue` / `logs/Queue.full`: null-separated queues

- **Lock / stop**
  - Lockfile: `/tmp/conversion_video.lock`
  - Stop flag: `/tmp/conversion_stop_flag`

## Tests

- Harness: [../../run_tests.sh](../../run_tests.sh)
- Tests: [../../tests/](../../tests/) directory
- Tests are primarily Bats tests (unit + regressions + e2e).

## Further Reading

- Usage: [USAGE.md](USAGE.md)
- Config: [CONFIG.md](CONFIG.md)
- Adaptive mode: [ADAPTATIF.md](ADAPTATIF.md)
- Smart codec: [SMART_CODEC.md](SMART_CODEC.md)
- Troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Adding a codec: [ADDING_NEW_CODEC.md](ADDING_NEW_CODEC.md)
