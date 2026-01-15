# FFmpeg Samples (edge cases)

This guide allows generating **short** and **reproducible** files via `ffmpeg` (`lavfi` sources) to test somewhat "edge" cases.

> Generated files go in `samples/_generated/` (ignored by git).

## Prerequisites

- `ffmpeg` in PATH
- Encoders:
  - `libx264` for most samples
  - `libx265` for the HEVC 10-bit sample
  - `dca` (DTS) and `truehd` for premium samples (if available)

Note: depending on your `ffmpeg` build, `dca` and `truehd` may be marked *experimental* and require `-strict -2` (the script handles this).

## Generate samples

From the repo root:

```bash
bash tools/generate_ffmpeg_samples.sh
```

Useful options:

```bash
# Shorter duration
bash tools/generate_ffmpeg_samples.sh -d 3

# Overwrite existing files
bash tools/generate_ffmpeg_samples.sh -f

# A subset of cases
bash tools/generate_ffmpeg_samples.sh --only vfr_concat,multiaudio_aac_ac3
```

## Generated Cases

- `01_h264_yuv444p_high444.mkv`: H.264 4:4:4 (`yuv444p`), High 4:4:4 profile
- `02_av1_low_bitrate.mkv`: AV1 (if `libsvtav1` available), useful for "codec better than HEVC" case
- `03_vp9_input.webm`: VP9 (if `libvpx-vp9` available), useful for "codec inferior to HEVC" case
- `04_mpeg4_avi_input.avi`: MPEG4 (AVI container), "old codec" case
- `05_hevc_10bit_bt2020_pq.mkv`: HEVC 10-bit (`yuv420p10le`) + BT.2020/PQ metadata
- `06_hevc_high_bitrate.mkv`: HEVC intentionally very "heavy" to test re-encoding threshold
- `07_h264_odd_dimensions_853x479.mp4`: odd dimensions (scaling/alignment)
- `08_h264_rotate90_metadata.mp4`: rotation via metadata (not a real transpose)
- `09_h264_interlaced_meta_tff.mkv`: interlaced flags (TFF) to test detection
- `10_vfr_concat.mkv`: concat 24fps + 30fps (VFR)
- `11_aac_high_bitrate_stereo.mkv`: stereo AAC at high bitrate (audio downscale case)
- `12_eac3_high_bitrate_5_1.mkv`: EAC3 5.1 at 640k (downscale to 384k case in film mode)
- `13_flac_lossless_5_1.mkv`: FLAC 5.1 lossless ("lossless copied" case, unless `--no-lossless`)
- `14_pcm_7_1.mkv`: PCM 7.1 (8 channels) to test multichannel reduction during conversion
- `15_opus_5_1_224k.mkv`: Opus 5.1 at 224k (efficient multichannel codec, often copied)
- `16_multiaudio_aac_stereo_ac3_5_1.mkv`: 2 audio tracks (stereo AAC + 5.1 AC3)
- `17_subtitles_srt.mkv`: muxed SRT subtitles (MKV)
- `18_dts_5_1.mkv`: DTS 5.1 (premium)
- `19_dts_7_1.mkv`: DTS 7.1 (premium, may be skipped if unsupported)
- `20_truehd_5_1.mkv`: TrueHD 5.1 (premium)
- `21_truehd_7_1.mkv`: TrueHD 7.1 (premium, may be skipped if unsupported)
