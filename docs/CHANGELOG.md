# Changelog

## v3.0.3

- ✅ **Truncated films**: an interrupted NAS copy went unnoticed, `ffmpeg` encoded the start of the film and the run reported success. The copy to temporary storage is now verified (exit code and size), and every output is compared with its source before publishing: an incomplete output is rejected (`ERROR DURATION`).
- ✅ **Existing truncated outputs**: instead of blocking the file forever, they are renamed to `.corrupt-*` and the film is converted again.
- ✅ **Reliable duration check**: the comparison now uses the video track instead of the container. A subtitle longer than the film no longer blocks `--replace`, and the tolerance goes from 1% to 0.2% (2 s minimum).
- ✅ **"fps mismatch with 1st pass" failure on films with cover art (Windows)**: the native `ffprobe` ends its lines with `\r`, so cover art (`attached_pic`) was never recognised. It was mapped as video tracks and encoded with x265, which made the 2nd pass fail after a full 1st pass. `ffprobe_safe` now strips `\r`, which also makes subtitle language detection and the VMAF stream choice reliable.
- ✅ **Tests**: new `test_regression_duration_integrity.bats`, and two CRLF tests in `test_regression_coverage.bats`.

## v3.0.2

- ✅ **Frozen conversion / skipped episodes in folder mode (`-s`)**: `ffmpeg` inherited the queue as its stdin and read file paths as key presses. A `c` opened its `Enter command:` prompt: frozen progress, an `ffmpeg` that never exits (even once encoding is done) and stays orphaned at 100% CPU after Ctrl+C. On short files, it silently swallowed queue entries (skipped episodes, no error). Fixed: `convert_file` now runs with stdin on `/dev/null`, and every `ffmpeg` call passes `-nostdin`.
- ✅ **Ctrl+C**: encoders (`ffmpeg`, `ffprobe`, `SvtAv1EncApp`) that survive the group SIGTERM get SIGKILL after ~2 s, in the real process group even when nascode is launched behind another program. The temporary files of an interrupted run (`.in`/`.out`, several GB) are deleted; empty `work_*` folders no longer pile up.
- ✅ **Tests**: new `test_regression_ffmpeg_stdin_cleanup.bats` (stdin inheritance, `-nostdin` contract, forced kill, run temp files).

## v3.0.1

- ✅ **macOS — silent stop with `-l N`**: on a large queue, `printf | head` received SIGPIPE and `pipefail` killed the script without any message (exit 141). Fixed in normal and random (`-r`) modes.
- ✅ **macOS — fast indexing**: BSD `find` has no `-printf`; GNU `find` from Homebrew (`gfind`, `findutils`) is now used when available instead of one `stat` per file. The source is also explored only once (count + indexing), which halves the time on a NAS share.
- ✅ **macOS without GNU coreutils**: portable fallbacks for `stat -c` (existing index with `-k`, copy progress), `realpath -m` (output folder), `date -d` (ETA with BSD awk), GNU-only `sed` `\+` (path normalization, Discord) and a BSD awk regex (Discord queue preview).
- ✅ **Tests**: new `test_regression_macos_portability.bats` (SIGPIPE, `find`/`gfind` detection, `stat` fallback, single exploration, BSD `stat`). `run_tests.sh` runs files in parallel (`-j N`, default = CPU count, `-j 1` = sequential): ~10 min → ~3 min.

## v3.0

- ✅ **New `gaming` mode**: adaptive variant calibrated for high-motion content (replays, game captures), 29.97 fps cap by default.
- ✅ **New `adaptatif-vmaf` mode (AV1)**: per-scene CRF adaptation driven by VMAF ("auto-boost-lite", pure Bash), with NAScode-style progress, Discord notifications and the audio smart codec. Optional `SVT-AV1-Essential` pipe encoder (not combinable with `adaptatif-vmaf` in V1).
- ✅ **`--replace` option**: replaces the source with the converted file, only after a verified transfer, real savings and matching duration; never on samples. Mentioned at startup.
- ✅ **`--keep-metadata` option**: preserves metadata, chapters and source modification date.
- ✅ **Faster indexing**: sizes obtained directly from `find -printf` (no `stat` per file), in-memory counter and throttled progress display. An unreadable folder (e.g. NAS `#recycle`) no longer kills the run.
- ✅ **`ffprobe` probe cache**: a file is probed once per run for identical options (invalidated if the file changes); `ffmpeg` capabilities are also cached.
- ✅ **Robustness**: atomic `.partial` transfer verified before publication, lock TOCTOU closed (`flock`), `umask 0077` on temporary files, Discord webhook kept out of the `curl` argv, `wait -n` race fixed.
- ✅ **Fixes**: VMAF now reads the real `pooled_metrics.vmaf.mean`; `--limit-fps` actually caps the fps; option precedence CLI > mode preset > env > `.env.local`; smart audio decision re-probes channels (skip/encode consistency); PGS subtitle crashes on Blu-ray remux; x265 4.x `fastdecode` segfault; SI/TI parsing; progress bar in mintty / PGS / system timezone.
- ✅ **SVT-AV1**: perceptual tuning of the series profile, `film-grain` lowered (8 → 6) on the film profile, `enable-overlays` / `film-grain` disabled in adaptive mode, zombie `SvtAv1EncApp` killed on SIGINT/SIGTERM.
- ✅ **UX**: SI/TI complexity analysis now shows a progress bar; ANSI colors only emitted to a terminal (`NO_COLOR` honored).
- ✅ **Dev tooling**: GitHub Actions workflow (lint + Bats), strict `run_tests.sh` (can no longer report a false success), centralized constants (`lib/constants.sh`), automatic function export, docs in English as primary language (French in `docs/fr/`).

## v2.8

- ✅ **HFR (High Frame Rate) Management**: new `--limit-fps` / `--no-limit-fps` options to handle videos >30 fps. In series mode (default), HFR videos are limited to 29.97 fps to optimize size. In film/adaptatif mode, bitrate is proportionally adjusted to framerate.
- ✅ **HFR option display**: LIMIT_FPS option appears in active parameters (terminal) and in `run_started` Discord notification.
- ✅ **Intelligent VMAF skip**: VMAF score is automatically ignored when framerate is modified (invalid comparison).
- ✅ **HFR tests**: 26 unit tests + 2 e2e tests for HFR management.
- ✅ **Centralized constants**: new `lib/constants.sh` module grouping "magic numbers" (adaptive mode, audio thresholds, Discord parameters, HFR thresholds). All constants are overridable via environment variables.
- ✅ **Documentation robustness**: systematic documentation of `set -euo pipefail` in 38 `lib/` modules.
- ✅ **Reinforced tests**: new unit tests for `VIDEO_EQUIV_QUALITY_CAP`, `_clamp_min`, `_clamp_max`, `_min3`.
- ✅ **Bitrate factorization**: `_translate_bitrate_by_efficiency()` function centralized in `codec_profiles.sh` (audio + video).
- ✅ **Test helpers**: refactoring of `test_helper.bash` (standardized variables, intelligent skip, modularity).
- ✅ **Documentation**: CONFIG.md enriched (constants section), SMART_CODEC.md updated (audio ranks, bitrate translation).

## v2.7

- ✅ **Queue / FIFO robustness**: avoids blocking when no files are processable (empty entries, missing files, invalid queue) + explicit exit if source is excluded.
- ✅ **Discord notifications (optional)**: start/pause(off-peak)/end messages, more robust payload + opt-in debug mode, dedicated docs + tests.
- ✅ **Stabilized adaptive mode**: calculated budgets are actually applied to encoding (exports) + SVT-AV1 cap in CRF (`mbr=`) and opt-in SVT debug logs.
- ✅ **Video "smart codec"**: codec-aware skip threshold + "no downgrade" policy (AV1 source re-encoded in AV1 if necessary) + "equivalent quality" cap on less efficient sources.
- ✅ **UX/CLI**: better message consistency (skip/early errors) and `--quiet` option documented in guides.
- ✅ **Dev tooling**: `make lint` (ShellCheck) + warnings cleanup, improves maintainability.
- ✅ **Tests & docs**: Bats additions/reinforcements (queue, conversion, notifs) + troubleshooting and aligned guides.

## v2.6

- ✅ **Lossless/premium audio**: `--no-lossless` option to force conversion of DTS/DTS-HD, TrueHD, FLAC tracks (disables "premium" passthrough)
- ✅ **Multichannel audio**: finalized rules (downmix 7.1 → 5.1, EAC3 by default, multichannel Opus via `-a opus`, multichannel AAC only with `--force-audio`)
- ✅ **Audio refactor**: clear separation between decision (`lib/audio_decision.sh`) and FFmpeg parameters/layout (`lib/audio_params.sh`)
- ✅ **"Clean code light" refactor**: internal simplification of large functions (audio/video/VMAF/suffix) and FFmpeg command building via argument arrays (no expected UX/CLI change)
- ✅ **Tests & docs**: new Bats multichannel tests + aligned docs (README + docs)

## v2.5

- ✅ **Adaptive mode**: adaptive bitrate based on complexity analysis
- ✅ **Size filter**: `--min-size` option to filter index/queue (useful in film mode)
- ✅ **Multichannel audio**: layout normalization (stereo / 5.1) + preservation logic according to mode
- ✅ **Windows / Git Bash**: path/CRLF normalization and better robustness with special characters
- ✅ **VMAF & UX**: display adjustments + subsampling parameter, improved messages and counters
- ✅ **Tests**: refactor and optimizations for faster and more robust execution
- ✅ **Audio refactor**: extraction of "smart codec" logic into `lib/audio_decision.sh` (and `lib/audio_params.sh` refocused on FFmpeg/layout)

## v2.4

- ✅ **Multi-codec audio**: `-a/--audio` option to choose AAC, AC3, Opus or copy
- ✅ **Anti-upscaling logic**: only converts audio if real gain (>20%)
- ✅ Optimized bitrates: AAC 160k, AC3 384k, Opus 128k
- ✅ Audio suffix in filename (`_aac`, `_opus`, etc.)
- ✅ Audio refactoring: new dedicated `audio_params.sh` module (FFmpeg parameters/layout)
- ✅ Colored help with highlighted options
- ✅ Video codec display in active parameters

## v2.3

- ✅ **Multi-codec video support**: `-c/--codec` option to choose HEVC or AV1
- ✅ New `codec_profiles.sh` module for modular encoder configuration
- ✅ libsvtav1 and libaom-av1 support for AV1
- ✅ Dynamic suffix by codec (`_x265_`, `_av1_`)
- ✅ Automatic skip adapted to target codec
- ✅ FFmpeg encoder validation before conversion

## v2.2

- ✅ `-f/--file` option to convert a single file (bypasses index/queue)
- ✅ Total space savings display in final summary (before → after, savings in %)
- ✅ Improved pipefail reliability and temporary file cleanup

## v2.1

- ✅ Quality-optimized film mode (two-pass 2035 kbps, keyint=240)
- ✅ Differentiated GOP: 240 frames (film) vs 600 frames (serie)
- ✅ Optional tune fastdecode (enabled serie, disabled film)
- ✅ Refactored tests: behavior vs hardcoded values
- ✅ Condensed test display with real-time progress

## v2.0

- ✅ New optimized x265 parameters for series mode
- ✅ Fast pass 1 (`no-slow-firstpass`) for time savings
- ✅ Opus 128k audio conversion preparation (temporarily disabled)
- ✅ Improved VMAF management (empty file detection)
- ✅ Dynamic suffix with `_tuned` indicator
