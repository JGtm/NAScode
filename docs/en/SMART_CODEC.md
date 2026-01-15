# "Smart Codec" Logic (audio & video)

This document explains *why* the script may **skip**, **copy** (passthrough), or **convert**.

## Audio (default target: AAC)

- The default target audio codec is `aac`.
- The script avoids unnecessary conversions (anti-upscaling): it only converts if the gain is real.

### Decisions (summary faithful to behavior)

Main rules:

- If `--audio copy`: audio is copied **unless** a downmix is explicitly required (e.g., forced stereo in `serie` mode).
- If the source is **lossless** (FLAC, TrueHD): copied by default, unless a downmix/conversion is required (e.g., `--no-lossless`, 7.1→5.1 in film mode, or forced stereo in `serie` mode).
- If the source is already the **same codec** as the target:
	- copied if bitrate $\le$ target,
	- downscaled if bitrate $>$ 110% of target,
	- otherwise copied (margin against "micro-conversions").
- If the source is a codec deemed **efficient** (Opus/AAC/Vorbis): copied, with possible downscale if too high.
- Otherwise: conversion to target codec (default `aac`).

To force conversion (bypass smart): `--force-audio`.

### Audio Channel Management (multichannel)

The script automatically manages the number of audio channels according to mode:

| Mode | Source | Result |
|------|--------|--------|
| `serie` | Stereo (2ch) | Stereo |
| `serie` | 5.1 (6ch) | **Downmix → Stereo** |
| `serie` | 7.1 (8ch) | **Downmix → Stereo** |
| `film` / `adaptatif` | Stereo (2ch) | Stereo |
| `film` / `adaptatif` | 5.1 (6ch) | **Layout preserved (no stereo downmix)** |
| `film` / `adaptatif` | 7.1 (8ch) | **Reduced → 5.1** |

**Why?**
- **Serie mode**: priority on space savings. Stereo is sufficient for viewing on PC/tablet/mobile.
- **Film mode**: priority on quality. 5.1 allows enjoying a home theater system.

Note: if a `copy` decision is retained, channels are kept as-is. In `serie` mode, a multichannel source forces a conversion/downmix decision to guarantee stereo output.

### Hierarchy (efficiency)

The logic relies on an efficiency rank (see `get_audio_codec_rank()` in [lib/audio_decision.sh](../../lib/audio_decision.sh)):

- Opus (very efficient, rank 5)
- AAC (efficient, rank 4)
- Vorbis (efficient, rank 3)
- E-AC3 (rank 2) / AC3 (rank 1) / DTS / MP3 / PCM… (less efficient, rank 0)

The `AUDIO_CODEC_EFFICIENT_THRESHOLD` threshold (default 3) determines which codecs are considered "efficient" and thus preserved rather than re-encoded. This threshold is configurable via [lib/constants.sh](../../lib/constants.sh).

### Bitrate Translation by Efficiency

When the source codec differs from the target codec, bitrate thresholds are **translated** to compare apples to apples:

$$\text{threshold}_{source} = \text{threshold}_{target} \times \frac{\mathrm{eff}(source)}{\mathrm{eff}(target)}$$

This logic (function `_translate_bitrate_by_efficiency()` in [lib/codec_profiles.sh](../../lib/codec_profiles.sh)) is centralized and reused for:
- Audio decisions (anti-upscaling)
- Video decisions (skip/encode)

## Video (default target: HEVC)

- Default target video codec: `hevc`.
- A codec "better or equal" to the target codec can be preserved if the bitrate is reasonable.
- If the source is in a more efficient codec than the target (e.g., AV1 vs target HEVC), the threshold is **translated** into the source codec space via codec efficiency (cf. `get_codec_efficiency()` in `lib/codec_profiles.sh`).
- Default policy: **don't downgrade** the video codec (e.g., an AV1 with too high bitrate is re-encoded in AV1 to cap the bitrate, not in HEVC).
- If the source is in a **less efficient** codec than the encoding codec (e.g., H.264 → HEVC) and its bitrate is already low, the bitrate budget can be **capped** at an "equivalent quality" value to avoid unnecessarily increasing bitrate during re-encoding (anti-upscaling).
- If the video is OK but audio can be optimized, the script can do **video passthrough**.

To force re-encoding: `--force-video`.

### Video Codec Hierarchy (general rule)

The script compares source codec to target codec via an efficiency hierarchy:

AV1 > HEVC > VP9 > H.264 > MPEG4

### Skip Thresholds & Tolerance

The "skip because already optimized" decision uses a tolerance:

$$\text{threshold} = \mathrm{MAXRATE}_{\mathrm{KBPS}} \times \left(1 + \frac{\text{SKIP\\_TOLERANCE\\_PERCENT}}{100}\right)$$

`MAXRATE_KBPS` depends on:
- the mode (`serie` / `film`),
- the target codec (codec efficiency),
- and possibly a resolution adaptation (see [CONFIG.md](CONFIG.md)).

When the source is in a codec "better or equal" to the target, the threshold is compared in the source codec:

$$\text{threshold}_{source} = \text{threshold}_{target} \times \frac{\mathrm{eff}(source)}{\mathrm{eff}(target)}$$

Example (target HEVC, source AV1): $2772k \times 50/70 \approx 1980k$.

### Common Cases (simplified)

- Source better or equal to target codec + reasonable bitrate: **skip** (preserve)
- Source better or equal but bitrate too high: **encode** (in the **source codec** if it's superior)
- Source worse than target: **encode**
- Video compliant but audio improvable: **video passthrough** (video copied, audio processed)

To force: `--force-video`.

## `--force` Options

- `--force-audio`: bypass smart audio decisions
- `--force-video`: bypass smart video decisions
- `--force`: enables both

## Notes

Exact thresholds and fine logic depend on mode, resolution, and encoding parameters.

For "source code" reading:
- Audio: [lib/audio_decision.sh](../../lib/audio_decision.sh) (decision) + [lib/audio_params.sh](../../lib/audio_params.sh) (FFmpeg/layout)
- Video: [lib/video_params.sh](../../lib/video_params.sh), [lib/transcode_video.sh](../../lib/transcode_video.sh)
