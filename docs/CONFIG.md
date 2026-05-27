# Configuration

This project is designed to work "out of the box" via CLI, but the base configuration is located in [lib/config.sh](../lib/config.sh).

## Defaults (important to know)

- Mode: `serie`
- Video codec: `hevc`
- Audio codec: `aac`
- Output: `Converted/` (in the script's directory)

## Conversion Modes

Modes are defined in [lib/config.sh](../lib/config.sh) via `set_conversion_mode_parameters()`.
NAScode supports **five modes** with distinct philosophies, summarized below.

### Philosophies en bref

- **`serie`** — Efficace, compromis qualité/stockage. Idéal pour les séries TV
  où on accepte une qualité "très bonne" pour gagner en vitesse et limiter la taille.
- **`film`** — Qualité maximale, taille optimisée. Le mode le plus exigeant.
  Idéal pour l'archivage de films (one-shot, on accepte le surcoût temps).
- **`adaptatif`** — Variable, adapte les paramètres **par fichier** selon
  l'analyse de complexité (stddev / SI / TI). Bon compromis pour catalogues
  hétérogènes où la complexité varie d'un film à l'autre. Calibré pour
  contenu **cinéma 24fps** (BPP_BASE=0.032 ≈ 2-3 Mbit/s pour 1080p24).
- **`gaming`** — Variante de `adaptatif` calibrée pour le **high-motion**
  (replays OBS, captures jeux, screencasts). **Cap FPS de sortie à 29.97
  par défaut** (comme `serie`) — pour des replays, la fluidité 60fps natif
  est moins critique que la qualité visuelle par frame. Compensation :
  `ADAPTIVE_BPP_BASE=0.16` (doublé vs 60fps + 0.080), ce qui donne le
  **même bitrate target** mais **2× plus de bits par frame**. Override
  via `LIMIT_FPS=false` pour préserver le 60+fps natif. Le profil SVT-AV1
  reste celui d'adaptatif.
- **`adaptatif-vmaf`** — Variable, adapte le CRF **par scène** (segment) via
  VMAF prédictif. Le plus lent mais qualité ciblée sur les scènes difficiles
  (Phase C de [AV1_OPTIMIZATION_PLAN.md](AV1_OPTIMIZATION_PLAN.md)).

### Comparaison détaillée

| Aspect | `serie` | `film` | `adaptatif` | `gaming` | `adaptatif-vmaf` |
|---|---|---|---|---|---|
| **Vitesse relative** | Rapide | Lente | Modérée | Modérée | Très lente |
| **Pass** | single CRF | **two-pass ABR** | single CRF capped | single CRF capped | single CRF par segment |
| **Pass1 fast** | ✓ (+15% vitesse) | ✗ (analyse complète) | n/a | n/a | n/a |
| **Bitrate strategy** | fixe CRF 21 | budget two-pass | calculé par fichier | calculé par fichier (BPP×2.5) | calculé par scène (VMAF) |
| **Target bitrate (HEVC ref)** | 2070 kbps | 2035 kbps | 2500 kbps | **5000 kbps** | 2500 kbps |
| **Maxrate (HEVC ref)** | 2520 kbps | 3200 kbps | 3500 kbps | **7000 kbps** | 3500 kbps |
| **`ADAPTIVE_BPP_BASE`** | n/a | n/a | 0.032 (cinéma) | **0.16** (high-motion + cap 30) | 0.032 |
| **GOP (keyint)** | **360** (~15s @ 24fps) | 240 (~10s @ 24fps) | 240 | 240 | 240 |
| **`LIMIT_FPS`** | **true** (cap 29.97) | false | false | **true** (cap 29.97, override possible) | false |
| **Audio (target layout)** | **stéréo forcé** | multichannel préservé | multichannel + equiv-qual | multichannel + equiv-qual | multichannel + smart codec |
| **`ADAPTIVE_COMPLEXITY_MODE`** | ✗ | ✗ | ✓ (par fichier) | ✓ (par fichier) | ✗ (auto-boost à la place) |
| **`AUTO_BOOST_ENABLED`** | ✗ | ✗ | ✗ | ✗ | ✓ (Phase C, par scène) |

### Mode `gaming` : exemples de bitrate target

Formule : `R_target = W × H × FPS_OUT × ADAPTIVE_BPP_BASE × complexity_C`.
Avec `ADAPTIVE_BPP_BASE=0.16` (défaut gaming) et `C=1.0`, FPS de sortie cap
à 29.97 par défaut :

| Résolution × FPS sortie | Bitrate target | Output 30s |
|---|---|---|
| **1080p30** (défaut, source 60fps→30) | **~10 Mbit/s** | **~37 Mo** |
| 1080p30 (source 30fps native) | ~10 Mbit/s | ~37 Mo |
| 1440p30 | ~17 Mbit/s | ~64 Mo |
| 4K30 | ~40 Mbit/s | ~150 Mo |
| **Override LIMIT_FPS=false** : 1080p60 | ~20 Mbit/s | ~75 Mo |

À résolution × FPS_OUT × BPP constants, le bitrate target est identique.
La stratégie "cap 30fps + BPP doublé" garantit le même fichier qu'un encode
60fps + BPP moitié, mais avec **2× plus de bits par frame** → qualité
visuelle nettement supérieure par frame.

Le garde-fou **`ADAPTIVE_MAX_ORIGINAL_PCT=75`** plafonne en bout de chaîne :
le target ne dépasse jamais 75% du bitrate source.

Override possible via env :
- `export ADAPTIVE_BPP_BASE_GAMING=0.20` → +25% qualité (~47 Mo)
- `export ADAPTIVE_BPP_BASE_GAMING=0.12` → -25% taille (~28 Mo)
- `export LIMIT_FPS=false` → préserver 60fps natif (file size ×2)

### SVT-AV1 — paramètres perceptuels par mode

Tous les modes utilisent le **10-bit forcé** en sortie (`yuv420p10le`) et le
**preset SVT-AV1 5** (médium, dérivé de `medium` x265). Les params suivants
diffèrent par mode pour adapter le trade-off qualité/vitesse :

| Param SVT-AV1 | `serie` | `film` | `adaptatif` / `adaptatif-vmaf` | Effet |
|---|---|---|---|---|
| `film-grain` | **absent** | **8** | 0 (interdit HWACCEL) | Synthèse de grain ; coûte ~10× en temps. Banni de serie après bisection (2026-05-19). |
| `variance-boost-strength` | **3** (max pratique) | 2 (défaut) | 3 (compense no-grain) | Boost qualité sur zones plates (low-variance). |
| `luminance-qp-bias` | **20** (agressif) | 15 (modéré) | 15 | Alloue plus de bits aux blocs sombres (loi de Weber). |
| `sharpness` | 1 | 1 | 1 | Préserve un peu plus de détail fin. |
| `enable-qm` + `qm-min` | 1 / 0 | 1 / 0 | 1 / 0 | Quantization matrices activées. Coût taille négligeable. |
| `ac-bias` | 0.25 | 0.25 | 0.25 | Biais AC (défaut Essential v4). |
| `tune` | 0 (Visual) | 0 | 0 | Optimisation perceptuelle (vs PSNR=1). |
| `enable-overlays` | 1 | 1 | **0** (interdit HWACCEL) | Alt-ref overlay frames pour qualité. |
| `lp` | 6 (max) | 6 | 6 | Level of Parallelism (range [0-6] — pas un thread count). |

Pourquoi ces différences :
- **`serie`** : pas de `film-grain` (coût rédhibitoire pour batch série), mais
  les params perceptuels sont les **plus agressifs** (variance-boost à 3,
  luma-bias à 20) pour compenser l'absence de grain dans les scènes sombres.
- **`film`** : `film-grain=8` apporte un grain photographique naturel, ce qui
  rend l'agressivité des autres params moins nécessaire (variance à 2, luma à 15).
- **`adaptatif` / `adaptatif-vmaf`** : `film-grain=0` est **forcé** par une
  contrainte historique (crash RAM/VRAM avec HWACCEL CUDA, cf.
  [lib/config.sh:298](../lib/config.sh#L298)). On compense par variance à 3
  et luma à 15. `enable-overlays=0` pour la même raison.

### SVT-AV1-Essential (Phase B, opt-in)

Si le binaire `SvtAv1EncApp.exe` Essential est installé (cf.
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) section "SVT-AV1-Essential"), NAScode
peut basculer vers un pipeline pipe-based qui apporte :
- `photon-noise` (remplace `film-grain`, grain plus naturel)
- `enable-tf=3` (temporal filter sur toutes frames)
- `enable-alt-cdef=1`, `enable-alt-dlf=1` (CDEF/deblocking améliorés)

Activation : flag `--essential` (override) ou auto-détection au boot. Le flag
`--no-essential` force le fallback libsvtav1 mainline.

Notes :
- The "reference" bitrates above are **HEVC** and are then adjusted according
  to target codec efficiency (see below).
- Voir [AV1_OPTIMIZATION_PLAN.md](AV1_OPTIMIZATION_PLAN.md) pour l'historique
  des décisions perceptuelles (Phase A, B, C de la roadmap).

## Bitrate Adaptation by Resolution (per file)

Goal: avoid wasting size when the output is significantly lower than 1080p (e.g., 720p).

- If the estimated output height is $\le 720p$, the bitrate budget is reduced via `ADAPTIVE_720P_SCALE_PERCENT`.
- Values: `ADAPTIVE_BITRATE_BY_RESOLUTION=true`, `ADAPTIVE_720P_MAX_HEIGHT=720`, `ADAPTIVE_720P_SCALE_PERCENT=70`.

## Codecs & Encoders

### Supported Codecs

- Video: `hevc`, `av1`
- Audio: `aac`, `copy`, `ac3`, `eac3`, `opus`

### Encoder Selection

- The codec→encoder mapping is managed in [lib/codec_profiles.sh](../lib/codec_profiles.sh).
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

Recommended: use a local `.env.local` file (ignored by Git) based on [.env.example](../.env.example).

```bash
cp .env.example .env.local
```

By default, `nascode` automatically loads `./.env.local` (if present) at startup.

- Disable: `NASCODE_ENV_AUTOLOAD=false`
- Use another file: `NASCODE_ENV_FILE=/path/to/my.env`

Security: never commit the webhook. If the URL has been shared publicly, regenerate it on Discord's side.

## Centralized Constants (lib/constants.sh)

Since v2.8, "magic numbers" are centralized in [lib/constants.sh](../lib/constants.sh). Each constant can be **overridden via environment variable** before running the script.

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

In [lib/config.sh](../lib/config.sh), you'll find notably:

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
