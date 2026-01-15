# Mode Adaptatif

Le mode `adaptatif` calcule dynamiquement le bitrate cible pour chaque fichier en analysant sa complexité visuelle. Contrairement aux modes à bitrate fixe, il adapte les paramètres d'encodage au contenu réel.

## Activation

```bash
bash nascode -m adaptatif -s "/chemin/vers/films"
```

---

## Chaîne de Calcul Complète

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ANALYSE DE COMPLEXITÉ                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Fichier vidéo                                                             │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────┐                                   │
│   │  Échantillonnage multi-points       │                                   │
│   │  (20 × 10s répartis sur la durée)   │                                   │
│   │  Marges: 5% début, 8% fin           │                                   │
│   └─────────────────────────────────────┘                                   │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────┐                                   │
│   │  Analyse multi-métriques            │                                   │
│   │  ├─ stddev frames     → 40%         │  ← Variation tailles frames       │
│   │  ├─ SI (spatial)      → 30%         │  ← Textures/détails (ITU-T P.910) │
│   │  └─ TI (temporal)     → 30%         │  ← Mouvement (ITU-T P.910)        │
│   └─────────────────────────────────────┘                                   │
│        │                                                                    │
│        ▼                                                                    │
│   Score combiné normalisé (0 → 1)                                           │
│        │                                                                    │
│        ▼                                                                    │
│   ┌─────────────────────────────────────┐                                   │
│   │  Mapping → Coefficient C            │                                   │
│   │  C_MIN (0.85) ◄──────► C_MAX (1.25) │                                   │
│   │     │                      │        │                                   │
│   │  statique              complexe     │                                   │
│   └─────────────────────────────────────┘                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       CALCUL DU BITRATE                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   R_target = (Width × Height × FPS × BPP_base / 1000) × C                   │
│                                                                             │
│   Où:                                                                       │
│   • BPP_base = 0.032 (Bits Per Pixel, calibré pour HEVC 1080p)              │
│   • C = coefficient de complexité (0.85 → 1.25)                             │
│                                                                             │
│   Exemple 1080p@24fps, C=1.0:                                               │
│   → 1920 × 1080 × 24 × 0.032 / 1000 = 1592 kbps                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GARDE-FOUS                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. Plafond : max 75% du bitrate source                                    │
│      → Évite de gonfler artificiellement                                    │
│                                                                             │
│   2. Plancher : min 800 kbps                                                │
│      → Garantit une qualité minimale                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      PARAMÈTRES VBV                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Maxrate  = R_target × 1.4                                                 │
│   Bufsize  = R_target × 2.5                                                 │
│                                                                             │
│   Exemple (R_target = 1800 kbps):                                           │
│   → Maxrate  = 2520 kbps                                                    │
│   → Bufsize  = 4500 kbps                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                  TRADUCTION INTER-CODECS                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Si codec cible ≠ HEVC (référence du calcul):                              │
│                                                                             │
│   bitrate_codec = bitrate_hevc × (efficacité_cible / efficacité_hevc)       │
│                                                                             │
│   Efficacités (plus bas = plus efficace):                                   │
│   ┌─────────┬────────────┬─────────────────────────────┐                    │
│   │ Codec   │ Efficacité │ Exemple (base 2000 kbps)    │                    │
│   ├─────────┼────────────┼─────────────────────────────┤                    │
│   │ H.264   │ 100        │ 2857 kbps                   │                    │
│   │ HEVC    │ 70         │ 2000 kbps (référence)       │                    │
│   │ AV1     │ 50         │ 1429 kbps                   │                    │
│   │ VVC     │ 35         │ 1000 kbps (futur)           │                    │
│   └─────────┴────────────┴─────────────────────────────┘                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     COMMANDE FFMPEG                                         │
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

## Métriques d'Analyse

### 1. Stddev (Coefficient de Variation des Frames)

Mesure la variation des tailles de frames compressées. Un contenu statique (interview) aura des frames de tailles similaires, tandis qu'un contenu dynamique (action) aura des variations importantes.

- **Plage typique** : 0.15 (statique) → 0.50+ (très dynamique)
- **Pondération** : 40%

### 2. SI (Spatial Information) — ITU-T P.910

Mesure la complexité spatiale : quantité de détails, textures, edges dans chaque frame.

- **Plage typique** : 0-100
- **Contenus bas** : aplats de couleur, anime simple
- **Contenus hauts** : nature, textures fines, grain film
- **Pondération** : 30%

### 3. TI (Temporal Information) — ITU-T P.910

Mesure la complexité temporelle : quantité de mouvement entre frames consécutives.

- **Plage typique** : 0-50
- **Contenus bas** : dialogues, plans fixes
- **Contenus hauts** : sport, action rapide, clips
- **Pondération** : 30%

---

## Configuration

Les paramètres sont définis dans `lib/constants.sh` et overridables via variables d'environnement :

```bash
# Pondération des métriques
export ADAPTIVE_WEIGHT_STDDEV=0.40
export ADAPTIVE_WEIGHT_SI=0.30
export ADAPTIVE_WEIGHT_TI=0.30

# BPP de référence (HEVC)
export ADAPTIVE_BPP_BASE=0.032

# Bornes du coefficient C
export ADAPTIVE_C_MIN=0.85
export ADAPTIVE_C_MAX=1.25

# Garde-fous
export ADAPTIVE_MIN_BITRATE_KBPS=800

# Désactiver SI/TI (fallback stddev seul)
export ADAPTIVE_USE_SITI=false
```

---

## Exemples de Résultats

| Contenu | stddev | SI | TI | C | Bitrate 1080p@24fps |
|---------|--------|-----|-----|-----|---------------------|
| Interview/Podcast | 0.18 | 35 | 8 | 0.87 | 1385 kbps |
| Anime (aplats) | 0.22 | 28 | 15 | 0.90 | 1430 kbps |
| Film dramatique | 0.30 | 52 | 22 | 1.02 | 1625 kbps |
| Documentaire nature | 0.28 | 78 | 18 | 1.12 | 1785 kbps |
| Film action | 0.42 | 55 | 38 | 1.18 | 1880 kbps |
| Film grain 35mm | 0.38 | 85 | 25 | 1.22 | 1945 kbps |

---

## Comparaison avec le Mode Film Standard

| Aspect | Mode `film` | Mode `adaptatif` |
|--------|-------------|---------------------|
| Bitrate | Fixe (2035 kbps) | Dynamique (800-2500+ kbps) |
| Analyse préalable | Non | Oui (~30s par fichier) |
| Encodage | Two-pass | Single-pass CRF avec VBV |
| Précision qualité | Moyenne | Haute |
| Temps total | Plus rapide | Légèrement plus long |

---

## Voir aussi

- [ARCHITECTURE.md](ARCHITECTURE.md) — Vue d'ensemble de l'architecture
- [CONFIG.md](CONFIG.md) — Configuration complète
- [SMART_CODEC.md](SMART_CODEC.md) — Logique de décision codec
