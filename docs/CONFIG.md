# Configuration

Ce projet est conçu pour fonctionner “out of the box” via la CLI, mais la configuration de base se trouve dans [lib/config.sh](../lib/config.sh).

## Defaults (à connaître)

- Mode : `serie`
- Codec vidéo : `hevc`
- Codec audio : `aac`
- Sortie : `Converted/` (dans le dossier du script)

## Modes de conversion

Les modes sont définis dans [lib/config.sh](../lib/config.sh) via `set_conversion_mode_parameters()`.

| Paramètre | Mode `serie` | Mode `film` |
|-----------|--------------|-------------|
| Encodage | **CRF 21** (single-pass, par défaut) ou two-pass | Two-pass **forcé** |
| Target bitrate (HEVC ref) | 2070 kbps (si two-pass) | 2035 kbps |
| Maxrate (HEVC ref) | 2520 kbps | 3200 kbps |
| GOP (keyint) | 600 (~25s @ ~24fps) | 240 (~10s @ ~24fps) |
| Tune fastdecode | Oui | Non |
| x265 extra params | Oui (optimisations série) | Non (qualité max) |
| Audio (layout cible) | **Stéréo forcée** (downmix si multicanal) | Stéréo/5.1 selon la source |

Notes :
- Le projet vise du **10-bit** (`yuv420p10le`) côté vidéo.
- Les bitrates “référence” ci-dessus sont **HEVC** et sont ensuite ajustés selon l’efficacité du codec cible (voir plus bas).

## Adaptation bitrate par résolution (par fichier)

Objectif : éviter de gaspiller de la taille quand la sortie est nettement inférieure à 1080p (ex: 720p).

- Si la hauteur de sortie estimée est $\le 720p$, le budget bitrate est réduit via `ADAPTIVE_720P_SCALE_PERCENT`.
- Valeurs : `ADAPTIVE_BITRATE_BY_RESOLUTION=true`, `ADAPTIVE_720P_MAX_HEIGHT=720`, `ADAPTIVE_720P_SCALE_PERCENT=70`.

## Codecs & encodeurs

### Codecs supportés

- Vidéo : `hevc`, `av1`
- Audio : `aac`, `copy`, `ac3`, `eac3`, `opus`

### Choix de l’encodeur

- Le mapping codec→encodeur est géré dans [lib/codec_profiles.sh](../lib/codec_profiles.sh).
- Pour changer d’encodeur (ex: AV1 via `libaom-av1` au lieu de `libsvtav1`), c’est là que ça se fait.

### Efficacité codec (impact sur les bitrates)

Les bitrates sont calculés à partir d’un **référentiel HEVC (70%)** et d’une efficacité par codec.

Formule (simplifiée) :

$$\text{bitrate}_\text{codec} = \text{bitrate}_\text{hevc} \times \frac{\text{efficacité}_\text{codec}}{70}$$

Exemple : AV1 (50%) applique un facteur $50/70 \approx 0{,}71$.

## Accélération matérielle

Selon l’OS et la disponibilité, le projet peut activer une accélération matérielle (ex: CUDA / VideoToolbox) pour décodage/traitements.

## Heures creuses (off-peak)

Quand `-p/--off-peak` est activé :

- Le script ne démarre de nouvelles conversions **que** pendant la plage définie.
- Si un fichier est en cours quand les heures pleines reviennent, il **termine**, puis attend le retour des heures creuses.

## Sorties plus lourdes / gain faible ("Heavier")

Objectif : éviter la boucle "re-encode" quand une conversion produit un fichier **plus lourd** (ou un gain trop faible). Dans ce cas, NAScode peut rediriger la sortie vers un dossier alternatif (par défaut `Converted_Heavier/`) en conservant l'arborescence.

Comportement (si activé) :

- Si `taille_sortie >= taille_source` **ou** si le gain est inférieur à un seuil, la sortie est déplacée vers `OUTPUT_DIR` + suffixe (`_Heavier` par défaut).
- Anti-boucle : si une sortie "Heavier" existe déjà pour le fichier, NAScode **skip** le fichier (pour éviter de reconvertir indéfiniment).

Variables :

- `HEAVY_OUTPUT_ENABLED` : `true`/`false` (défaut `true`).
- `HEAVY_MIN_SAVINGS_PERCENT` : gain minimum en % (défaut `10`).
- `HEAVY_OUTPUT_DIR_SUFFIX` : suffixe ajouté au dossier `OUTPUT_DIR` (défaut `_Heavier`).

## Notifications Discord (optionnel)

NAScode peut envoyer des notifications Discord via un webhook (Markdown). C’est volontairement **best-effort** : si Discord est indisponible, la conversion continue.

Notes :

- Le message de démarrage inclut les paramètres actifs, et un aperçu de la queue quand elle existe.
- Si `PARALLEL_JOBS=1`, l’UI indique « Jobs parallèles : désactivé ».
- Des messages “début/fin” sont envoyés pour chaque fichier, et des notifications spécifiques existent pour les transferts et VMAF (si activé).

Variables d’environnement :

- `NASCODE_DISCORD_WEBHOOK_URL` (secret) : URL du webhook Discord
- `NASCODE_DISCORD_NOTIFY` : `true` / `false` (optionnel ; défaut `true` si l’URL est définie)

Recommandé : utiliser un fichier local `.env.local` (ignoré par Git) basé sur [.env.example](../.env.example).

```bash
cp .env.example .env.local
set -a
source ./.env.local
set +a
```

Sécurité : ne commit jamais le webhook. Si l’URL a été partagée publiquement, régénère-le côté Discord.

## Variables modifiables (extrait)

Dans [lib/config.sh](../lib/config.sh), on retrouve notamment :

- `CONVERSION_MODE`
- `VIDEO_CODEC`
- `AUDIO_CODEC`
- `AUDIO_FORCE_STEREO` (activé automatiquement en mode `serie`)
- `SAMPLE_DURATION`

Autres variables utiles :
- `SKIP_TOLERANCE_PERCENT` (tolérance pour décider un skip)
- `SUFFIX_MODE` (suffixe ask/on/off/custom)
- `PARALLEL_JOBS` (jobs)

## Suffixes

Le suffixe peut être :

- interactif (question),
- forcé “on/off”,
- ou personnalisé.

Le détail est documenté via l’aide CLI (`bash nascode --help`).
