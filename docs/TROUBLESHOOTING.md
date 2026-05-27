# Troubleshooting

## Logs (where to look)

Logs are in `logs/`.

Typical files:
- `Session_*.log`: unified session journal
- `Summary_*.log`: end-of-conversion summary
- `Progress_*.log`: detailed progress
- `Success_*.log` / `Error_*.log` / `Skipped_*.log`
- `SVT_*.log`: SVT-AV1 config excerpt (debug option, see below)
- `Index`: index of files to process (null-separated)
- `Index_readable_*.txt`: readable index (list)
- `Queue` / `Queue.full`: queue (usually temporary)
- `DryRun_Comparison_*.log`: filename comparison (dry-run)

## No files to process / invalid queue / excluded source

### 1) "No files to process" message

This typically happens when **no files pass the filters** (e.g., `--min-size`) or when the **source** (`-s`) doesn't point to the right folder.

Quick actions:

```bash
# Regenerate index + queue from source
bash nascode -R -s "/path/source"

# If you had a size filter, try without
bash nascode -R -s "/path/source"  # without --min-size
```

### 2) "Invalid queue file format (NUL separator expected)" message

NAScode uses `logs/Index`/`logs/Queue` files in **null-separated** format.
If you provide a custom queue file (`-q` option), it must respect this format.

Quick actions:

```bash
# Delete queue and regenerate
rm -f logs/Queue logs/Queue.full 2>/dev/null || true
bash nascode -R -s "/path/source"
```

### 3) "Source directory is excluded by configuration (EXCLUDES)" error

The config contains an exclusions list (`EXCLUDES`). If your `SOURCE` (after normalization) matches an exclusion, NAScode stops explicitly.

Quick actions:

- Verify you're passing the correct `-s`.
- Adjust `EXCLUDES` (in config) if you want to allow this path.

## Lockfile / Stop flag

In case of crash, the script may leave:
- Lockfile: `/tmp/conversion_video.lock`
- Stop flag: `/tmp/conversion_stop_flag`

If no `nascode` is running, delete:

```bash
rm -f /tmp/conversion_video.lock /tmp/conversion_stop_flag
```

## Check FFmpeg (encoders/filters)

```bash
ffmpeg -hide_banner -encoders | grep libx265
ffmpeg -hide_banner -encoders | grep libsvtav1  # optional (AV1)
ffmpeg -hide_banner -filters | grep libvmaf     # optional (VMAF)
```

## FFmpeg without libx265

```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# macOS
brew install ffmpeg
```

## Windows (Git Bash): FFmpeg with SVT-AV1

The "essentials" version of FFmpeg (gyan.dev) doesn't include `libsvtav1` for AV1 encoding.
If you're using Git Bash with MSYS2, you can install a complete version of FFmpeg:

```bash
# 1. Install FFmpeg and SVT-AV1 via pacman (MSYS2)
pacman -S mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-svt-av1

# 2. Add MSYS2 to PATH (in ~/.bashrc)
echo 'export PATH="/c/msys64/ucrt64/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 3. Verify libsvtav1 is available
ffmpeg -encoders 2>/dev/null | grep libsvtav1
```

Note: without MSYS2, you can use a "full" FFmpeg from https://www.gyan.dev/ffmpeg/builds/.

## Debug SVT-AV1: verify "capped CRF" / `mbr`

If you want to confirm that SVT-AV1 has properly enabled "capped CRF" mode and taken `mbr=<kbps>` into account, you can enable a debug mode that writes a small dedicated log **without spamming the terminal**:

```bash
NASCODE_LOG_SVT_CONFIG=1 bash nascode [options]
```

Result:
- A `logs/SVT_<timestamp>_*.log` file is created per AV1 conversion (SVT-AV1) and contains `Svt[info]: SVT [config] ...` lines including notably `BRC mode ... capped CRF ... max bitrate`.
- The terminal remains unchanged (FFmpeg output is already redirected, we don't display these lines live).

## VMAF

- If your main FFmpeg doesn't have `libvmaf`, the script may look for an alternative FFmpeg depending on the environment.
- When in doubt: test on a file via `-l 1` and enable logs.

Reading benchmarks (indicative):

| Score | Quality |
|-------|---------|
| ≥ 90 | EXCELLENT |
| 80-89 | VERY GOOD |
| 70-79 | GOOD |
| < 70 | DEGRADED |

## Skipped files (skip)

- Check `logs/Skipped_*.log`.

## Encoding errors

1. Check `logs/Error_*.log`
2. Verify disk space in `/tmp`
3. Test with a single file: `bash nascode -l 1`

## File names

The script handles spaces and special characters, but avoid control characters.

## SVT-AV1-Essential (optional, Phase B)

NAScode peut détecter et utiliser à terme le fork
[SVT-AV1-Essential](https://github.com/nekotrix/SVT-AV1-Essential) (par
nekotrix) qui apporte des paramètres perceptuels supplémentaires
(`photon-noise`, `enable-tf=3`, `enable-alt-cdef/dlf`, quarter-step CRF, etc.).

### État actuel (mai 2026)

**Opérationnel.** Quand le binaire est détecté (PATH ou `SVTAV1_ESSENTIAL_BIN`)
et que l'encodeur cible est libsvtav1, NAScode bascule automatiquement vers
le binaire Essential standalone via un pipeline pipe-based
`ffmpeg → yuv4mpegpipe → SvtAv1EncApp → IVF → mux ffmpeg final`.

Flags CLI :
- `--essential`     : force l'usage Essential (override auto-détection).
- `--no-essential`  : force le fallback libsvtav1 mainline.

### Installation Windows

1. Télécharger le binaire optimisé depuis les releases :
   https://github.com/nekotrix/SVT-AV1-Essential/releases
   → `SvtAv1EncApp-X.Y.Z-Essential-Windows_Optimized.exe`
2. Renommer en `SvtAv1EncApp.exe` et placer dans un dossier du PATH
   (par exemple `C:\bin\` ou `C:\Users\<user>\bin\`).
3. Vérifier :
   ```powershell
   SvtAv1EncApp --version
   ```
   La sortie doit contenir le tag `-Essential` (ex. `SVT-AV1-Essential v4.0.1`).

### Forcer / désactiver via env

- `export SVTAV1_USE_ESSENTIAL=true`  → force l'usage Essential
- `export SVTAV1_USE_ESSENTIAL=false` → force le fallback mainline
- variable absente → auto-détection (utilise Essential si présent)

### Vérifier la détection NAScode

```bash
bash -c 'source lib/codec_profiles.sh; source lib/svtav1_essential.sh; \
  detect_svtav1_essential && echo "Essential détecté: $SVTAV1_ESSENTIAL_BIN" \
  || echo "Pas d'\''Essential dans le PATH"'
```
