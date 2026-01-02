# 🎬 NAScode — Conversion vidéo HEVC (x265) / AV1

Script Bash d'automatisation pour convertir des vidéos vers **HEVC (x265)** ou **AV1** en batch (séries/films), avec une logique “smart” (skip/passthrough) et une file d’attente persistante.

Prérequis :
- **bash 4+** (Git Bash/WSL sur Windows OK)
- **ffmpeg** avec `libx265` (AV1 via `libsvtav1` optionnel, VMAF via `libvmaf` optionnel)

Installation :
```bash
git clone <repo_url> NAScode
cd NAScode
chmod +x nascode
```

Usage minimal :
```bash
# Convertir un dossier (mode série par défaut)
bash nascode -s "/chemin/vers/series"

# Mode film (plus orienté qualité)
bash nascode -m film -s "/chemin/vers/films"

# Dry-run (simulation)
bash nascode -d -s "/chemin/source"

# Heures creuses (plage par défaut 22:00-06:00)
bash nascode -p -s "/chemin/vers/series"
```

Defaults importants (issus de la config) :
- Mode : `serie`
- Codec vidéo : `hevc`
- Codec audio : `aac`
- Sortie : `Converted/`

## Ce que fait le script

- Convertit en **HEVC (x265)** ou **AV1** selon `--codec`.
- Gère une **file d’attente** (index persistant) et peut **skip** les fichiers déjà “bons”.
- Supporte un mode **video passthrough** (vidéo copiée, audio optimisé si pertinent).
- Ajoute un **suffixe** (dynamique ou personnalisé) pour refléter les paramètres.
- Optionnel : **VMAF** et **sample** pour tester rapidement.

## 🎯 Matrices de décision (smart codec)

Ces tableaux résument les décisions les plus fréquentes (skip / copy / convert / downscale).
Pour la logique complète et les détails, voir [docs/SMART_CODEC.md](docs/SMART_CODEC.md).

### Audio (cible par défaut : `aac`)

Rappels :
- `--audio copy` : copie l'audio sans modification.
- `--force-audio` : force la conversion vers le codec cible (bypass smart).


| Codec source | Statut | Bitrate source | Action | Résultat (défaut) |
|-------------|--------|----------------|--------|-------------------|
| FLAC / TrueHD | Lossless | * | `copy` | Conservé (qualité max) |
| Opus | Efficace | $\le$ 128k | `copy` | Conservé tel quel |
| Opus | Efficace | $>$ 128k | `downscale` | Opus → 128k |
| AAC | Efficace | $\le$ 160k | `copy` | Conservé tel quel |
| AAC | Efficace | $>$ 176k | `downscale` | AAC → 160k |
| Vorbis | Efficace | * | `copy` | Conservé tel quel |
| E-AC3 / AC3 / DTS | Inefficace | * | `convert` | → AAC 160k |
| MP3 / PCM / autres | Inefficace | * | `convert` | → AAC 160k |

### Vidéo (cible par défaut : `hevc`)

Rappels :
- Hiérarchie (efficacité) : AV1 > HEVC > VP9 > H.264 > MPEG4
- Le “skip” dépend d’un seuil dérivé de `MAXRATE_KBPS` et d’une tolérance :
	- $\text{seuil} = \mathrm{MAXRATE}_{\mathrm{KBPS}} \times (1 + \text{tolérance})$
	- Par défaut : tolérance 10%
	- Exemples (mode `serie`) : HEVC maxrate 2520k → seuil 2772k ; AV1 maxrate 1800k → seuil 1980k
- `--force-video` : force le ré-encodage vidéo (bypass smart).

| Codec source | vs cible | Bitrate (vs seuil) | Action | Résultat |
|-------------|----------|--------------------|--------|----------|
| AV1 | > HEVC | $\le$ seuil AV1 | `skip` | Conservé (meilleur codec, bitrate OK) |
| AV1 | > HEVC | $>$ seuil AV1 | `encode` | Ré-encodage (bitrate trop élevé) |
| HEVC | = HEVC | $\le$ seuil HEVC | `skip` | Conservé (déjà optimisé) |
| HEVC | = HEVC | $>$ seuil HEVC | `encode` | Ré-encodage (bitrate trop élevé) |
| VP9 / H.264 / MPEG4 | < HEVC | * | `encode` | Conversion → HEVC |
| Source > 1080p (ex: 4K) | * | * | `encode + scale` | Downscale → 1080p + codec cible |
| Vidéo OK mais audio perfectible | * | * | `passthrough` | Vidéo copiée + audio traité |

## Utilisation

Commande :
```bash
bash nascode [options]
```

Pour la liste complète des options :
```bash
bash nascode --help
```

Guides détaillés :
- [docs/DOCS.md](docs/DOCS.md)
- [docs/USAGE.md](docs/USAGE.md)
- [docs/CONFIG.md](docs/CONFIG.md)

## Logs & sortie

- Sortie par défaut : `Converted/`
- Logs : `logs/` (session, erreurs, skipped, index/queue)

Détails : [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Documentation

- Index docs : [docs/README.md](docs/README.md)
- Ajouter un nouveau codec : [docs/ADDING_NEW_CODEC.md](docs/ADDING_NEW_CODEC.md)
- Instructions macOS : [docs/Instructions-Mac.txt](docs/Instructions-Mac.txt)
- Critères de conversion (CSV) : [docs/📋%20Tableau%20récapitulatif%20-%20Critères%20de%20conversion.csv](docs/%F0%9F%93%8B%20Tableau%20r%C3%A9capitulatif%20-%20Crit%C3%A8res%20de%20conversion.csv)

## Tests

Le repo utilise **Bats** :

```bash
bash run_tests.sh

# Verbose
bash run_tests.sh -v

# Filtrer
bash run_tests.sh -f "queue"  # exemple
```

Sur Git Bash / Windows, [run_tests.sh](run_tests.sh) tente aussi `${HOME}/.local/bin/bats` si `bats` n’est pas sur le PATH.

## Contribution

- Règles de travail : [agent.md](agent.md)
- Copilot (repo-level) : [.github/copilot-instructions.md](.github/copilot-instructions.md)

## Changelog

Voir : [docs/CHANGELOG.md](docs/CHANGELOG.md)

## Licence

MIT License - Libre d'utilisation et de modification.
