# Configuration

This project is designed to work "out of the box" via CLI, but the base configuration is located in [lib/config.sh](../../lib/config.sh).

## Defaults (important to know)

- Mode: `serie`
- Video codec: `hevc`
- Audio codec: `aac`
- Output: `Converted/` (in the script's directory)

## Conversion Modes

Modes are defined in [lib/config.sh](../../lib/config.sh) via `set_conversion_mode_parameters()`.

| Parameter | `serie` Mode | `film` Mode |
|-----------|--------------|-------------|
| Encoding | **CRF 21** (single-pass, default) or two-pass | Two-pass **forced** |
| Target bitrate (HEVC ref) | 2070 kbps (if two-pass) | 2035 kbps |
| Maxrate (HEVC ref) | 2520 kbps | 3200 kbps |
| GOP (keyint) | 600 (~25s @ ~24fps) | 240 (~10s @ ~24fps) |
| Tune fastdecode | Yes | No |
| x265 extra params | Yes (series optimizations) | No (max quality) |
| Audio (target layout) | **Forced stereo** (downmix if multichannel) | Stereo/5.1 depending on source |

Notes:
- The project aims for **10-bit** (`yuv420p10le`) on the video side.
- The "reference" bitrates above are **HEVC** and are then adjusted according to target codec efficiency (see below).

## Bitrate Adaptation by Resolution (per file)

Goal: avoid wasting size when the output is significantly lower than 1080p (e.g., 720p).

- If the estimated output height is $\le 720p$, the bitrate budget is reduced via `ADAPTIVE_720P_SCALE_PERCENT`.
- Values: `ADAPTIVE_BITRATE_BY_RESOLUTION=true`, `ADAPTIVE_720P_MAX_HEIGHT=720`, `ADAPTIVE_720P_SCALE_PERCENT=70`.

## Codecs & Encoders

### Supported Codecs

- Video: `hevc`, `av1`
- Audio: `aac`, `copy`, `ac3`, `eac3`, `opus`

### Encoder Selection

- The codec→encoder mapping is managed in [lib/codec_profiles.sh](../../lib/codec_profiles.sh).
- To change encoder (e.g., AV1 via `libaom-av1` instead of `libsvtav1`), that's where it's done.

### Codec Efficiency (impact on bitrates)

Bitrates are calculated from a **HEVC reference (70%)** and an efficiency per codec.

Formula (simplified):

$$\text{bitrate}_\text{codec} = \text{bitrate}_\text{hevc} \times \frac{\text{efficiency}_\text{codec}}{70}$$

Example: AV1 (50%) applies a factor of $50/70 \approx 0.71$.

## Hardware Acceleration

Depending on the OS and availability, the project can enable hardware acceleration (e.g., CUDA / VideoToolbox) for decoding/processing.

## Off-Peak Hours

When `-p/--off-peak` is enabled:

- The script only starts new conversions **during** the defined time range.
- If a file is in progress when peak hours return, it **finishes**, then waits for off-peak hours to resume.

## Heavier Outputs / Low Gain ("Heavier")

Goal: avoid the "re-encode" loop when a conversion produces a **heavier** file (or too low gain). In this case, NAScode can redirect the output to an alternative folder (default `Converted_Heavier/`) while preserving the directory structure.

Behavior (if enabled):

- If `output_size >= source_size` **or** if the gain is below a threshold, the output is moved to `OUTPUT_DIR` + suffix (`_Heavier` by default).
- Anti-loop: if a "Heavier" output already exists for the file, NAScode **skips** the file (to avoid converting indefinitely).

Variables:

- `HEAVY_OUTPUT_ENABLED`: `true`/`false` (default `true`).
- `HEAVY_MIN_SAVINGS_PERCENT`: minimum gain in % (default `10`).
- `HEAVY_OUTPUT_DIR_SUFFIX`: suffix added to `OUTPUT_DIR` folder (default `_Heavier`).

## Discord Notifications (optional)

NAScode can send Discord notifications via a webhook (Markdown). This is intentionally **best-effort**: if Discord is unavailable, the conversion continues.

Notes:

- The startup message includes active parameters and a queue preview when it exists.
- If `PARALLEL_JOBS=1`, the UI shows "Parallel jobs: disabled".
- "Start/end" messages are sent for each file, and specific notifications exist for transfers and VMAF (if enabled).
- "Skipped" messages may be sent with the reason.

Environment variables:

- `NASCODE_DISCORD_WEBHOOK_URL` (secret): Discord webhook URL
- `NASCODE_DISCORD_NOTIFY`: `true` / `false` (optional; defaults to `true` if URL is defined)

Recommended: use a local `.env.local` file (ignored by Git) based on [.env.example](../../.env.example).

```bash
cp .env.example .env.local
```

By default, `nascode` automatically loads `./.env.local` (if present) at startup.

- Disable: `NASCODE_ENV_AUTOLOAD=false`
- Use another file: `NASCODE_ENV_FILE=/path/to/my.env`

Security: never commit the webhook. If the URL has been shared publicly, regenerate it on Discord's side.

## Centralized Constants (lib/constants.sh)

Since v2.8, "magic numbers" are centralized in [lib/constants.sh](../../lib/constants.sh). Each constant can be **overridden via environment variable** before running the script.

### Adaptive Mode (complexity.sh)

| Constant | Default | Description |
|----------|---------|-------------|
| `ADAPTIVE_BPP_BASE` | 0.032 | Reference BPP (Bits Per Pixel) for HEVC. Calibrated to produce ~1500-2500 kbps at 1080p@24fps. |
| `ADAPTIVE_C_MIN` | 0.85 | Minimum complexity coefficient (static content). |
| `ADAPTIVE_C_MAX` | 1.25 | Maximum complexity coefficient (very complex content). |
| `ADAPTIVE_STDDEV_LOW` | 0.20 | Standard deviation threshold below which content is considered static. |
| `ADAPTIVE_STDDEV_HIGH` | 0.45 | Standard deviation threshold above which content is considered very complex. |
| `ADAPTIVE_SAMPLE_DURATION` | 10 | Duration (seconds) of each analysis sample. |
| `ADAPTIVE_SAMPLE_COUNT` | 20 | Number of sampling points for complexity analysis. |
| `ADAPTIVE_MARGIN_START_PCT` | 5 | Start margin (% of duration) to avoid opening credits. |
| `ADAPTIVE_MARGIN_END_PCT` | 8 | End margin (% of duration) to avoid closing credits. |
| `ADAPTIVE_MIN_BITRATE_KBPS` | 800 | Quality floor: minimum bitrate in kbps. |
| `ADAPTIVE_MAXRATE_FACTOR` | 1.4 | Multiplier factor for maxrate (ratio vs target). |
| `ADAPTIVE_BUFSIZE_FACTOR` | 2.5 | Multiplier factor for bufsize (ratio vs target). |

### Audio (audio_decision.sh)

| Constant | Default | Description |
|----------|---------|-------------|
| `AUDIO_CODEC_EFFICIENT_THRESHOLD` | 3 | Minimum rank to consider a codec "efficient" (Opus=5, AAC=4, Vorbis=3). Codecs above this threshold are preserved rather than re-encoded. |

### Discord Notifications (notify_discord.sh)

| Constant | Default | Description |
|----------|---------|-------------|
| `DISCORD_CONTENT_MAX_CHARS` | 1900 | Character limit per message (Discord API = 2000, safety margin). |
| `DISCORD_CURL_TIMEOUT` | 10 | Curl timeout for sending (seconds). |
| `DISCORD_CURL_RETRIES` | 2 | Number of curl retries on failure. |
| `DISCORD_CURL_RETRY_DELAY` | 1 | Delay between retries (seconds). |

**Override example:**

```bash
# Increase Discord timeout for slow connections
DISCORD_CURL_TIMEOUT=30 bash nascode -s /path/source

# Adaptive mode with finer analysis (more samples)
ADAPTIVE_SAMPLE_COUNT=30 bash nascode -m adaptatif -s /path/source
```

## Modifiable Variables (excerpt)

In [lib/config.sh](../../lib/config.sh), you'll find notably:

- `CONVERSION_MODE`
- `VIDEO_CODEC`
- `AUDIO_CODEC`
- `AUDIO_FORCE_STEREO` (automatically enabled in `serie` mode)
- `SAMPLE_DURATION`

Other useful variables:
- `SKIP_TOLERANCE_PERCENT` (tolerance for skip decision)
- `SUFFIX_MODE` (suffix ask/on/off/custom)
- `PARALLEL_JOBS` (jobs)

## Suffixes

The suffix can be:

- interactive (question),
- forced "on/off",
- or custom.

Details are documented via CLI help (`bash nascode --help`).
