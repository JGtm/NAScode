# Changelog

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
