# Adaptive Mode

The `adaptatif` mode dynamically calculates the target bitrate for each file by analyzing its visual complexity. Unlike fixed bitrate modes, it adapts encoding parameters to the actual content.

## Activation

```bash
bash nascode -m adaptatif -s "/path/to/movies"
```

---

## Complete Calculation Chain

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        COMPLEXITY ANALYSIS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Video file                                                                │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────┐                                   │
│   │  Multi-point sampling               │                                   │
│   │  (20 × 10s distributed over length) │                                   │
│   │  Margins: 5% start, 8% end          │                                   │
│   └─────────────────────────────────────┘                                   │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────┐                                   │
│   │  Multi-metric analysis              │                                   │
│   │  ├─ stddev frames     → 40%         │  ← Frame size variation           │
│   │  ├─ SI (spatial)      → 30%         │  ← Textures/details (ITU-T P.910) │
│   │  └─ TI (temporal)     → 30%         │  ← Motion (ITU-T P.910)           │
│   └─────────────────────────────────────┘                                   │
│        │                                                                    │
│        ▼                                                                    │
│   Normalized combined score (0 → 1)                                         │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────┐                                   │
│   │  Mapping → Coefficient C            │                                   │
│   │  C_MIN (0.85) ◄──────► C_MAX (1.25) │                                   │
│   │     │                      │        │                                   │
│   │   static               complex      │                                   │
│   └─────────────────────────────────────┘                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       BITRATE CALCULATION                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   R_target = (Width × Height × FPS × BPP_base / 1000) × C                   │
│                                                                             │
│   Where:                                                                    │
│   • BPP_base = 0.032 (Bits Per Pixel, calibrated for HEVC 1080p)            │
│   • C = complexity coefficient (0.85 → 1.25)                                │
│                                                                             │
│   Example 1080p@24fps, C=1.0:                                               │
│   → 1920 × 1080 × 24 × 0.032 / 1000 = 1592 kbps                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GUARDRAILS                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. Ceiling: max 75% of source bitrate                                     │
│      → Avoids artificial inflation                                          │
│                                                                             │
│   2. Floor: min 800 kbps                                                    │
│      → Guarantees minimum quality                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      VBV PARAMETERS                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Maxrate  = R_target × 1.4                                                 │
│   Bufsize  = R_target × 2.5                                                 │
│                                                                             │
│   Example (R_target = 1800 kbps):                                           │
│   → Maxrate  = 2520 kbps                                                    │
│   → Bufsize  = 4500 kbps                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                  CROSS-CODEC TRANSLATION                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   If target codec ≠ HEVC (calculation reference):                           │
│                                                                             │
│   bitrate_codec = bitrate_hevc × (target_efficiency / hevc_efficiency)      │
│                                                                             │
│   Efficiencies (lower = more efficient):                                    │
│   ┌─────────┬────────────┬─────────────────────────────┐                    │
│   │ Codec   │ Efficiency │ Example (base 2000 kbps)    │                    │
│   ├─────────┼────────────┼─────────────────────────────┤                    │
│   │ H.264   │ 100        │ 2857 kbps                   │                    │
│   │ HEVC    │ 70         │ 2000 kbps (reference)       │                    │
│   │ AV1     │ 50         │ 1429 kbps                   │                    │
│   │ VVC     │ 35         │ 1000 kbps (future)          │                    │
│   └─────────┴────────────┴─────────────────────────────┘                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     FFMPEG COMMAND                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ffmpeg -i input.mkv                                                       │
│     -c:v libx265                                                            │
│     -crf 21                                                                 │
│     -b:v {R_target}k                                                        │
│     -maxrate {Maxrate}k                                                     │
│     -bufsize {Bufsize}k                                                     │
│     -x265-params "vbv-maxrate={Maxrate}:vbv-bufsize={Bufsize}:..."          │
│     ...                                                                     │
│     output.mkv                                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Analysis Metrics

### 1. Stddev (Frame Coefficient of Variation)

Measures the variation in compressed frame sizes. Static content (interview) will have similar frame sizes, while dynamic content (action) will have significant variations.

- **Typical range**: 0.15 (static) → 0.50+ (very dynamic)
- **Weight**: 40%

### 2. SI (Spatial Information) — ITU-T P.910

Measures spatial complexity: amount of details, textures, edges in each frame.

- **Typical range**: 0-100
- **Low content**: flat colors, simple anime
- **High content**: nature, fine textures, film grain
- **Weight**: 30%

### 3. TI (Temporal Information) — ITU-T P.910

Measures temporal complexity: amount of motion between consecutive frames.

- **Typical range**: 0-50
- **Low content**: dialogues, static shots
- **High content**: sports, fast action, clips
- **Weight**: 30%

---

## Configuration

Parameters are defined in `lib/constants.sh` and overridable via environment variables:

```bash
# Metric weights
export ADAPTIVE_WEIGHT_STDDEV=0.40
export ADAPTIVE_WEIGHT_SI=0.30
export ADAPTIVE_WEIGHT_TI=0.30

# Reference BPP (HEVC)
export ADAPTIVE_BPP_BASE=0.032

# Coefficient C bounds
export ADAPTIVE_C_MIN=0.85
export ADAPTIVE_C_MAX=1.25

# Guardrails
export ADAPTIVE_MIN_BITRATE_KBPS=800

# Disable SI/TI (stddev-only fallback)
export ADAPTIVE_USE_SITI=false
```

---

## Example Results

| Content | stddev | SI | TI | C | Bitrate 1080p@24fps |
|---------|--------|-----|-----|-----|---------------------|
| Interview/Podcast | 0.18 | 35 | 8 | 0.87 | 1385 kbps |
| Anime (flat colors) | 0.22 | 28 | 15 | 0.90 | 1430 kbps |
| Drama film | 0.30 | 52 | 22 | 1.02 | 1625 kbps |
| Nature documentary | 0.28 | 78 | 18 | 1.12 | 1785 kbps |
| Action film | 0.42 | 55 | 38 | 1.18 | 1880 kbps |
| 35mm film grain | 0.38 | 85 | 25 | 1.22 | 1945 kbps |
