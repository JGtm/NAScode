# Usage

## Command

```bash
bash nascode [options]
```

Tip: for full help, use:

```bash
bash nascode --lang en --help
```

## Examples (most useful)

```bash
# Standard folder conversion (series mode by default)
bash nascode -s "/path/to/series"

# Film mode (more quality-oriented)
bash nascode -m film -s "/path/to/films"

# AV1 conversion
bash nascode -c av1 -s "/path/to/videos"

# VMAF (if your ffmpeg has libvmaf)
bash nascode -v -s "/path/to/films"

# Sample (segment ~30s) for quick testing
bash nascode -t -s "/path/to/series"

# Random + limit
bash nascode -r -l 5 -s "/path/to/series"

# Off-peak hours (default range 22:00-06:00)
bash nascode -p -s "/path/to/series"

# Off-peak hours with custom range
bash nascode --off-peak=23:00-07:00 -s "/path/to/series"

# Single file (bypass index/queue)
bash nascode -f "/path/to/video.mkv"

# Dry-run (simulation)
bash nascode -d -s "/path/source"

# Quiet (warnings/errors only)
bash nascode --quiet -s "/path/to/series"

# English interface
bash nascode --lang en -s "/path/to/series"
```

## Main options (reminder)

The script evolves: the table below is a reminder, the authority remains `bash nascode --help`.

- `-s, --source DIR`: source folder
- `-o, --output-dir DIR`: output folder
- `-m, --mode MODE`: `serie` (default) or `film`
- `-c, --codec CODEC`: `hevc` (default) or `av1`
- `-a, --audio CODEC`: `aac` (default), `copy`, `ac3`, `eac3`, `opus`
- `--min-size SIZE`: filter index/queue (keep only files >= SIZE, e.g., `700M`, `1G`)
- `-v, --vmaf`: enable VMAF
- `-t, --sample`: encode a test segment
- `-n, --no-progress`: disable progress indicator display
- `-Q, --quiet`: quiet mode (show only warnings/errors)
- `-p, --off-peak [HH:MM-HH:MM]`: run only during off-peak hours
- `--force-audio` / `--force-video` / `--force`: bypass certain smart decisions
- `--lang LANG`: interface language (`fr` or `en`)

To understand audio/video decisions (skip/passthrough/convert), see [SMART_CODEC.md](SMART_CODEC.md).

## Heavier outputs / low gain ("Heavier")

If a conversion produces a **heavier** file (or a gain below a threshold), NAScode can redirect the output to a separate folder to avoid reprocessing loops.

- Default folder: `Converted_Heavier/` (next to `Converted/`), preserving the folder structure.
- Anti-loop: if a "Heavier" output already exists for a file, NAScode **skips** that file.

Settings (in config):

- `HEAVY_OUTPUT_ENABLED`: `true`/`false`
- `HEAVY_MIN_SAVINGS_PERCENT`: minimum savings in %
- `HEAVY_OUTPUT_DIR_SUFFIX`: folder suffix (default `_Heavier`)

See also: [CONFIG.md](CONFIG.md)

## Discord notifications (optional)

NAScode supports notifications via Discord webhook (Markdown). They are **best-effort**: a network error should not interrupt the conversion.

Typical notification content:

- Startup: active parameters + queue preview (format `[i/N]`, up to 20 items)
- Per file: start then end (duration + sizes `before → after`)
- Per file: skip (ignored + reason)
- Transfers: pending then completed (if applicable)
- VMAF (if enabled): start + result per file (score/quality) + global end
- End: summary (if available) then final message with timestamp

Environment variables:

- `NASCODE_DISCORD_WEBHOOK_URL`: webhook URL (secret)
- `NASCODE_DISCORD_NOTIFY`: `true` / `false` (optional)

### Example (Git Bash / WSL)

	# Recommended: local file ignored by Git
	cp .env.example .env.local

	bash nascode -p -s "/path/to/series"

	# Note: `nascode` automatically loads `./.env.local` (if present).
	# Disable: NASCODE_ENV_AUTOLOAD=false
	# Other file: NASCODE_ENV_FILE=/path/to/my.env

### Example (PowerShell)

	$env:NASCODE_DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/<id>/<token>"
	$env:NASCODE_DISCORD_NOTIFY = "true"

	bash .\nascode -s "C:\\path\\to\\series"

Best practices: never put the webhook in the repo. If the URL has been shared publicly, regenerate the webhook.
