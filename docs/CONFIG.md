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
- Des messages “ignoré” (skip) peuvent être envoyés avec la raison.

Variables d’environnement :

- `NASCODE_DISCORD_WEBHOOK_URL` (secret) : URL du webhook Discord
- `NASCODE_DISCORD_NOTIFY` : `true` / `false` (optionnel ; défaut `true` si l’URL est définie)

Recommandé : utiliser un fichier local `.env.local` (ignoré par Git) basé sur [.env.example](../.env.example).

```bash
cp .env.example .env.local
```

Par défaut, `nascode` charge automatiquement `./.env.local` (si présent) au démarrage.

- Désactiver : `NASCODE_ENV_AUTOLOAD=false`
- Utiliser un autre fichier : `NASCODE_ENV_FILE=/chemin/vers/mon.env`

Sécurité : ne commit jamais le webhook. Si l’URL a été partagée publiquement, régénère-le côté Discord.

## Constantes centralisées (lib/constants.sh)

Depuis v2.8, les "magic numbers" sont centralisés dans [lib/constants.sh](../lib/constants.sh). Chaque constante peut être **overridée via variable d'environnement** avant de lancer le script.

### Mode film-adaptive (complexity.sh)

| Constante | Défaut | Description |
|-----------|--------|-------------|
| `ADAPTIVE_BPP_BASE` | 0.032 | BPP (Bits Per Pixel) de référence pour HEVC. Calibré pour produire ~1500-2500 kbps en 1080p@24fps. |
| `ADAPTIVE_C_MIN` | 0.85 | Coefficient de complexité minimum (contenu statique). |
| `ADAPTIVE_C_MAX` | 1.25 | Coefficient de complexité maximum (contenu très complexe). |
| `ADAPTIVE_STDDEV_LOW` | 0.20 | Seuil écart-type en dessous duquel le contenu est considéré statique. |
| `ADAPTIVE_STDDEV_HIGH` | 0.45 | Seuil écart-type au dessus duquel le contenu est considéré très complexe. |
| `ADAPTIVE_SAMPLE_DURATION` | 10 | Durée (secondes) de chaque échantillon d'analyse. |
| `ADAPTIVE_SAMPLE_COUNT` | 20 | Nombre de points d'échantillonnage pour l'analyse de complexité. |
| `ADAPTIVE_MARGIN_START_PCT` | 5 | Marge début (% de la durée) pour éviter le générique d'ouverture. |
| `ADAPTIVE_MARGIN_END_PCT` | 8 | Marge fin (% de la durée) pour éviter le générique de fin. |
| `ADAPTIVE_MIN_BITRATE_KBPS` | 800 | Plancher qualité : bitrate minimum en kbps. |
| `ADAPTIVE_MAXRATE_FACTOR` | 1.4 | Facteur multiplicateur pour maxrate (ratio vs target). |
| `ADAPTIVE_BUFSIZE_FACTOR` | 2.5 | Facteur multiplicateur pour bufsize (ratio vs target). |

### Audio (audio_decision.sh)

| Constante | Défaut | Description |
|-----------|--------|-------------|
| `AUDIO_CODEC_EFFICIENT_THRESHOLD` | 3 | Rang minimum pour considérer un codec "efficace" (Opus=5, AAC=4, Vorbis=3). Les codecs au-dessus de ce seuil sont préservés plutôt que ré-encodés. |

### Notifications Discord (notify_discord.sh)

| Constante | Défaut | Description |
|-----------|--------|-------------|
| `DISCORD_CONTENT_MAX_CHARS` | 1900 | Limite de caractères par message (API Discord = 2000, marge de sécurité). |
| `DISCORD_CURL_TIMEOUT` | 10 | Timeout curl pour l'envoi (secondes). |
| `DISCORD_CURL_RETRIES` | 2 | Nombre de retries curl en cas d'échec. |
| `DISCORD_CURL_RETRY_DELAY` | 1 | Délai entre retries (secondes). |

**Exemple d'override :**

```bash
# Augmenter le timeout Discord pour les connexions lentes
DISCORD_CURL_TIMEOUT=30 bash nascode -s /chemin/source

# Mode film-adaptive avec analyse plus fine (plus d'échantillons)
ADAPTIVE_SAMPLE_COUNT=30 bash nascode -m film-adaptive -s /chemin/source
```

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
