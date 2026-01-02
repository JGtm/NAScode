# 🎬 NAScode — Conversion vidéo HEVC (x265) / AV1

Script Bash d'automatisation pour convertir des vidéos vers **HEVC (x265)** ou **AV1** en batch (séries/films), avec une logique “smart” (skip/passthrough) et une file d’attente persistante.

## TL;DR (30 secondes)

Prérequis rapides :
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
- [docs/README.md](docs/README.md)
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
