# 🎬 NAScode — Bash Tool — HEVC / AV1 Video Conversion

Bash automation script for converting videos to **HEVC (x265)** or **AV1** in batch (series/movies), with "smart" logic (skip/passthrough) and a persistent queue.

Prerequisites:
- **bash 4+** (Git Bash/WSL on Windows OK)
- **ffmpeg** with `libx265` (AV1 via `libsvtav1` optional, VMAF via `libvmaf` optional)

Installation:
```bash
git clone <repo_url> NAScode
cd NAScode
chmod +x nascode
```

Minimal usage:
```bash
# Convert a folder (serie mode by default)
bash nascode -s "/path/to/series"

# Film mode (more quality-oriented)
bash nascode -m film -s "/path/to/movies"

# Dry-run (simulation)
bash nascode -d -s "/path/source"

# Off-peak hours (default range 22:00-06:00)
bash nascode -p -s "/path/to/series"

# Filter index/queue: ignore small files (useful for movies)
bash nascode -m film --min-size 700M -s "/path/to/movies"
```

Important defaults (from config):
- Mode: `serie`
- Video codec: `hevc`
- Audio codec: `aac`
- Output: `Converted/`

## What the script does

- Converts to **HEVC (x265)** or **AV1** depending on `--codec`.
- Manages a **queue** (persistent index) and can **skip** files already "good".
- Supports **video passthrough** mode (video copied, audio optimized if relevant).
- Adds a **suffix** (dynamic or custom) to reflect video codec, output resolution and (optionally) audio codec.
- Optional: **VMAF** and **sample** for quick testing.
- Limitation: **portrait mode** videos (vertical / rotation metadata) are not effectively supported; resolution/bitrate estimation logic is primarily designed for "landscape" sources and may produce unsuitable parameters.

## 🌐 Internationalization (i18n)

NAScode supports English and French:

```bash
# English output
bash nascode --lang en -s "/path/source"

# French output (default)
bash nascode --lang fr -s "/path/source"
bash nascode -s "/path/source"

# Set language via environment variable
export NASCODE_LANG=en
bash nascode -s "/path/source"
```

Documentation is available in both languages:
- French: [docs/](docs/)
- English: [docs/en/](docs/en/)

## 🎯 Decision Matrices (smart codec)

These tables summarize the most frequent decisions (skip / copy / convert / downscale).
For the complete logic and details, see [docs/en/SMART_CODEC.md](docs/en/SMART_CODEC.md).

### Audio (default: `aac` stereo)

Reminders:
- `--audio copy`: copies audio without modification.
- `--force-audio`: forces conversion to target codec (bypass smart).
- `--no-lossless`: forces conversion of premium codecs (DTS/DTS-HD/TrueHD/FLAC).
- `--equiv-quality` / `--no-equiv-quality`: enables/disables "equivalent quality" mode (audio + video cap).
	(Ignored in `adaptatif` mode: stays enabled.)
- `--limit-fps` / `--no-limit-fps`: limits FPS to 29.97 for HFR content (>30 fps).
	- `serie` mode: enabled by default (size optimization).
	- `film` / `adaptatif` modes: disabled by default (max quality, increased bitrate if HFR).
	- Note: VMAF is ignored if FPS is modified (frame-by-frame comparison impossible).

**Channel management (multichannel):**
- **`serie` mode**: forced stereo (systematic downmix if 5.1/7.1+).
- **`film` / `adaptatif` modes**: target layout stereo (2ch) or **5.1** (automatic downmix if 7.1).
- **Default multichannel codec (film/adaptatif)**: EAC3 384k (TV/receiver compatible).
- **Multichannel AAC**: only with `-a aac --force-audio` (320k cap).
- **Multichannel Opus**: `-a opus` (224k cap).
- **Anti-upscale**: no conversion if source < 256k (unless downmix required).

**Premium codecs (DTS/DTS-HD/TrueHD/FLAC):**
- **Without `--no-lossless`**: passthrough (preserved if already 5.1, otherwise downmix → EAC3 384k).
- **With `--no-lossless`**: forced conversion (stereo → target codec, multichannel → EAC3 384k).

Note: in `serie` mode, forced stereo may convert cases otherwise in `copy` (including premium) to guarantee 2.0 output.

| Source codec | Status | Channels | Source bitrate | Action | Result |
|-------------|--------|----------|----------------|--------|--------|
| DTS / DTS-HD / TrueHD | Premium | 5.1 | * | `copy` | Preserved (passthrough) |
| DTS / DTS-HD / TrueHD | Premium | 7.1 | * | `convert` | → EAC3 384k 5.1 (downmix) |
| FLAC | Lossless | * | * | `copy` | Preserved (max quality) |
| Opus | Efficient | stereo | $\le$ 128k | `copy` | Preserved as-is |
| Opus | Efficient | 5.1+ | $\le$ 224k | `copy` | Preserved as-is |
| AAC | Efficient | stereo | $\le$ 160k | `copy` | Preserved as-is |
| AAC | Efficient | 5.1 | $\le$ 320k | `copy` | Preserved as-is |
| EAC3 | Standard | 5.1 | $\le$ 384k | `copy` | Preserved as-is |
| EAC3 | Standard | 5.1 | $>$ 384k | `downscale` | EAC3 → 384k |
| AC3 | Inefficient | 5.1 | * | `convert` | → EAC3 384k |
| MP3 / PCM / others | Inefficient | * | * | `convert` | → target codec |

### Video (default target: `hevc`)

Reminders:
- Hierarchy (efficiency): AV1 > HEVC > VP9 > H.264 > MPEG4
- "Skip" depends on a threshold derived from `MAXRATE_KBPS` and tolerance:
	- $\text{threshold} = \mathrm{MAXRATE}_{\mathrm{KBPS}} \times (1 + \text{tolerance})$
	- Default: 10% tolerance
	- If the source is in a **more efficient** codec than the target (e.g., AV1 when target is HEVC), the threshold is **translated** into the source codec space via codec efficiency.
	- Example (`serie` mode, target HEVC): HEVC threshold 2772k → AV1 threshold ≈ $2772 \times 50/70 \approx 1980$k
- `--force-video`: forces video re-encoding (bypass smart).
- `--equiv-quality` / `--no-equiv-quality`: enables/disables "equivalent quality" mode (audio + video cap).
	(Ignored in `adaptatif` mode: stays enabled.)

| Source codec | vs target | Bitrate (vs threshold) | Action | Result |
|-------------|----------|--------------------|--------|--------|
| AV1 | > HEVC | $\le$ threshold (translated) | `skip` | Preserved (better codec, OK bitrate) |
| AV1 | > HEVC | $>$ threshold (translated) | `encode` | Re-encoding **in AV1** (no downgrade) |
| HEVC | = HEVC | $\le$ HEVC threshold | `skip` | Preserved (already optimized) |
| HEVC | = HEVC | $>$ HEVC threshold | `encode` | Re-encoding (bitrate too high) |
| VP9 / H.264 / MPEG4 | < HEVC | * | `encode` | Conversion → HEVC |
| Source > 1080p (e.g., 4K) | * | * | `encode + scale` | Downscale → 1080p + target codec |
| Video OK but audio improvable | * | * | `passthrough` | Video copied + audio processed |

## Usage

Command:
```bash
bash nascode [options]
```

For the complete list of options:
```bash
bash nascode --help
```

Detailed guides:
- [docs/en/DOCS.md](docs/en/DOCS.md)
- [docs/en/USAGE.md](docs/en/USAGE.md)
- [docs/en/CONFIG.md](docs/en/CONFIG.md)

Code reference (audio):
- "Smart codec" decision: [lib/audio_decision.sh](lib/audio_decision.sh)
- FFmpeg/layout construction: [lib/audio_params.sh](lib/audio_params.sh)

## Logs & Output

- Default output: `Converted/` (in script folder)
- Logs: `logs/` (in script folder)
- If a conversion produces a heavier file (or gain < threshold), the output is redirected to `Converted_Heavier/` (configurable) to avoid reprocessing loops.

Details: [docs/en/TROUBLESHOOTING.md](docs/en/TROUBLESHOOTING.md)

### Quick Troubleshooting (common cases)

- **No files to process**: your filters/exclusions probably eliminated everything (e.g., `--min-size`, `EXCLUDES`, wrong `-s`). Retry without filter, or force regeneration: `bash nascode -R -s "..."`.
- **Invalid queue (NUL separator)**: if you provide a custom queue, it must be *null-separated*. Otherwise, delete `logs/Queue` and rerun with `-R`.
- **Source excluded by config**: if you see an error indicating `SOURCE` is in `EXCLUDES`, change `-s` or remove the exclusion (in config).

## Discord Notifications (optional)

NAScode can send notifications via a **Discord webhook** (Markdown format):

- at startup: **active parameters** + queue preview (up to 20 items, with truncation)
- during run: **start/end of each file** (`[i/N]` prefix, duration, sizes `before → after`)
- during run: **file skip** (ignored + reason)
- transfers: **pending** then **completed** (if applicable)
- VMAF (if enabled): start + **result per file** (score/quality) + global end
- entering/exiting peak hours when `--off-peak` is active
- at the end: summary (if available) then an **end message with timestamp**

Configuration (via environment variables):

- `NASCODE_DISCORD_WEBHOOK_URL` (required): webhook URL (secret)
- `NASCODE_DISCORD_NOTIFY` (optional): `true/false` (default `true` if URL is defined)

Recommended (local, not versioned):

```bash
cp .env.example .env.local
# then edit .env.local (DO NOT commit)
bash nascode -s "/path/to/series"
```

By default, `nascode` automatically loads `./.env.local` (if present) at startup.

- Disable: `NASCODE_ENV_AUTOLOAD=false`
- Use another file: `NASCODE_ENV_FILE=/path/to/my.env`

Security: never commit the webhook. If you posted it in a chat/log/issue, consider it compromised and regenerate it on Discord's side.

## Documentation

- Docs index: [docs/en/DOCS.md](docs/en/DOCS.md)
- Advanced configuration & constants: [docs/en/CONFIG.md](docs/en/CONFIG.md)
- Adding a new codec: [docs/en/ADDING_NEW_CODEC.md](docs/en/ADDING_NEW_CODEC.md)
- macOS instructions: [docs/Instructions-Mac.txt](docs/Instructions-Mac.txt)
- Conversion criteria: [docs/en/SMART_CODEC.md](docs/en/SMART_CODEC.md)

## Tests

The repo uses **Bats**:

```bash
bash run_tests.sh

# Verbose
bash run_tests.sh -v

# Filter
bash run_tests.sh -f "queue"  # example
```

On Git Bash / Windows, [run_tests.sh](run_tests.sh) also tries `${HOME}/.local/bin/bats` if `bats` is not in PATH.

## Contributing

- Work rules: [agent.md](.ai/agent.md)
- Copilot (repo-level): [.github/copilot-instructions.md](.github/copilot-instructions.md)

## Changelog

See: [docs/en/CHANGELOG.md](docs/en/CHANGELOG.md)

## License

MIT License - Free to use and modify.
