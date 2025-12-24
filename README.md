# 🎬 Conversion Video x265

Script Bash d'automatisation pour convertir des vidéos vers **HEVC (x265)** en batch, optimisé pour les séries et films.

## ✨ Fonctionnalités

### Encodage
- **Encodage** : single-pass (CRF) ou two-pass (bitrate cible) selon le mode/options
- **Deux modes de conversion** :
  - `serie` : optimisé vitesse (~1 Go/h), preset medium, CRF ou 2070 kbps
  - `film` : optimisé qualité (aligné TyHD), preset slow, two-pass 2035 kbps
- **Paramètres x265 optimisés** pour le mode série :
  - `sao=0` : désactive Sample Adaptive Offset (gain ~5%)
  - `strong-intra-smoothing=0` : préserve les détails fins
  - `limit-refs=3` : limite les références motion
  - `subme=2` : précision sub-pixel réduite
  - `no-slow-firstpass=1` : pass 1 rapide (gain ~15%)
  - `-tune fastdecode` : décodage fluide sur appareils variés
- **Mode film** (aligné sur TyHD) :
  - Two-pass forcé pour qualité maximale
  - GOP court (keyint=240, ~10s) pour meilleur seeking
  - Pas de tune fastdecode (qualité prioritaire)
- **Format 10-bit** (`yuv420p10le`) pour une meilleure qualité
- **Accélération matérielle** : CUDA (Windows/Linux) ou VideoToolbox (macOS)

### Gestion des fichiers
- **File d'attente intelligente** avec index persistant
- **Modes de tri** : par taille (asc/desc) ou par nom (asc/desc)
- **Skip automatique** : fichiers déjà en x265 avec bitrate optimisé
- **Suffixe dynamique** reflétant les paramètres : `_x265_2070k_medium_tuned`
- **Transfert vérifié** avec checksum SHA256

### Évaluation qualité
- **Score VMAF** (optionnel) : évaluation perceptuelle de la qualité vidéo
- **Mode sample** (`-t`) : encode un segment de 30s pour test rapide
- Analyse VMAF en batch à la fin des conversions

### Audio
- Copie de l'audio source (`-c:a copy`)
- *[Préparé]* Conversion Opus 128 kbps (désactivé, en attente support VLC)

## 📋 Prérequis

- **Système** : GNU/Linux, macOS, Windows (Git Bash/WSL)
- **FFmpeg** avec `libx265` et optionnellement `libvmaf`
- **Outils** : `bash 4+`, `awk`, `stat`, `md5sum`/`md5`

Vérifier FFmpeg :
```bash
ffmpeg -hide_banner -encoders | grep libx265
ffmpeg -hide_banner -filters | grep libvmaf
```

## 🚀 Installation

```bash
git clone <repo_url> Conversion
cd Conversion
chmod +x convert.sh
```

## 🧪 Tests

Le repo utilise **Bats**.

```bash
bash run_tests.sh

# Verbose
bash run_tests.sh -v

# Filtrer
bash run_tests.sh -f "queue"  # exemple
```

Sur Git Bash / Windows, [run_tests.sh](run_tests.sh) tente aussi `${HOME}/.local/bin/bats` si `bats` n’est pas sur le PATH.

## 🤝 Contribution

- Règles de travail : lire [agent.md](agent.md) (modularité, plan avant gros changements, tests/doc, post-merge `main`).
- Template de commit :

```bash
git config commit.template .gitmessage.txt
```

- Copilot (repo-level) : voir [.github/copilot-instructions.md](.github/copilot-instructions.md).

## 📖 Usage

```bash
bash convert.sh [options]
```

### Options principales

| Option | Description |
|--------|-------------|
| `-s, --source DIR` | Dossier source (défaut: `../`) |
| `-o, --output-dir DIR` | Dossier de sortie (défaut: `Converted/`) |
| `-m, --mode MODE` | Mode de conversion : `serie` (défaut) ou `film` |
| `-d, --dry-run` | Simulation sans encodage (alias : `--dryrun`) |
| `-t, --sample` | Mode sample : encode ~30s pour test rapide (alias : `--test`) |
| `-v, --vmaf` | Activer l'évaluation VMAF |
| `--opus` | Convertir l'audio en Opus 128kbps (expérimental, problèmes VLC surround) |
| `-2, --two-pass` | Forcer le mode two-pass (défaut : single-pass CRF pour séries) |
| `-l, --limit N` | Limiter à N fichiers |
| `-r, --random` | Sélection aléatoire des fichiers |
| `-k, --keep-index` | Réutiliser l'index existant |
| `-n, --no-progress` | Désactiver les barres de progression |
| `-x, --no-suffix` | Pas de suffixe sur les fichiers de sortie |
| `-e, --exclude PATTERN` | Exclure des fichiers (glob) |
| `-q, --queue FILE` | Utiliser une file d'attente personnalisée |
| `-p, --off-peak [HH:MM-HH:MM]` | Mode heures creuses (défaut : `22:00-06:00`) |
| `-h, --help` | Afficher l'aide |

### Exemples

```bash
# Conversion standard d'un dossier de séries
bash convert.sh -s "/chemin/vers/series"

# Mode film avec évaluation VMAF
bash convert.sh -m film -v -s "/chemin/vers/films"

# Test rapide sur 5 fichiers aléatoires (30s chacun)
bash convert.sh -t -v -r -l 5

# Heures creuses (plage par défaut 22:00-06:00)
bash convert.sh -p -s "/chemin/vers/series"

# Heures creuses avec plage personnalisée
bash convert.sh --off-peak=23:00-07:00 -s "/chemin/vers/series"

# Simulation pour vérifier la configuration
bash convert.sh -d -s "/chemin/source"

# Conversion avec limite et index conservé
bash convert.sh -l 10 -k
```

## ⚙️ Configuration

### Modes de conversion

| Paramètre | Mode `serie` | Mode `film` |
|-----------|--------------|-------------|
| Bitrate cible | 2070 kbps | 2035 kbps |
| Maxrate | 2520 kbps | 3200 kbps |
| Preset | medium | slow |
| Keyint (GOP) | 600 (~25s) | 240 (~10s) |
| Tune fastdecode | Oui | Non |
| Optimisations x265 | Oui (tuned) | Non (qualité max) |
| Pass 1 rapide | Oui | Non |
| Mode par défaut | Single-pass CRF | Two-pass forcé |

### Variables modifiables (`lib/config.sh`)

```bash
CONVERSION_MODE="serie"           # Mode par défaut
SORT_MODE="name_asc"              # Tri de la file d'attente
SAMPLE_DURATION=30                # Durée du segment test (secondes)
BITRATE_CONVERSION_THRESHOLD_KBPS=2520  # Seuil pour skip
```

### Paramètres x265 (mode série)

```
amp=0:rect=0:sao=0:strong-intra-smoothing=0:limit-refs=3:subme=2
```

### Mode heures creuses (off-peak)

Quand `-p/--off-peak` est activé :

- Le script ne démarre de nouvelles conversions **que** pendant la plage définie.
- Si un fichier est en cours quand les heures pleines reviennent, il **termine**, puis le script attend le retour des heures creuses.
- La plage par défaut est `22:00-06:00` (modifiable via `--off-peak=HH:MM-HH:MM`).

## 📁 Structure

```
Conversion/
├── convert.sh          # Script principal
├── lib/
│   ├── args.sh              # Parsing des arguments
│   ├── audio_params.sh      # Paramètres audio
│   ├── colors.sh            # Codes couleur terminal
│   ├── config.sh            # Configuration globale
│   ├── conversion.sh        # Orchestration FFmpeg
│   ├── detect.sh            # Détection outils/système
│   ├── exports.sh           # Exports pour sous-shells
│   ├── finalize.sh          # Finalisation et résumé
│   ├── lock.sh              # Verrou + traps
│   ├── logging.sh           # Gestion des logs
│   ├── media_probe.sh       # Propriétés média (ffprobe)
│   ├── off_peak.sh          # Heures creuses
│   ├── processing.sh        # Traitement (queue, FIFO)
│   ├── progress.sh          # Progression
│   ├── queue.sh             # Index + file d'attente
│   ├── stream_mapping.sh    # Mapping des flux
│   ├── system.sh            # Vérifications système
│   ├── transcode_video.sh   # Logique vidéo (x265, downscale)
│   ├── transfer.sh          # Transferts asynchrones
│   ├── utils.sh             # Utilitaires
│   ├── video_params.sh      # Paramètres vidéo
│   └── vmaf.sh              # Évaluation VMAF
├── logs/               # Logs d'exécution
│   ├── Success_*.log
│   ├── Error_*.log
│   ├── Progress_*.log
│   └── Index
└── Converted/          # Fichiers convertis
```

## 📊 Logs

- `Success_*.log` : fichiers convertis avec succès
- `Error_*.log` : erreurs de conversion
- `Progress_*.log` : progression détaillée
- `Skipped_*.log` : fichiers ignorés (déjà optimisés)
- `Index` : index des fichiers à traiter
- `Index_readable_*.txt` : index lisible (liste des fichiers)
- `Queue` : file d'attente (format null-separated)

## 🔍 Évaluation VMAF

Le score VMAF (Video Multi-Method Assessment Fusion) évalue la qualité perceptuelle :

| Score | Qualité |
|-------|---------|
| ≥ 90 | EXCELLENT |
| 80-89 | TRÈS BON |
| 70-79 | BON |
| < 70 | DÉGRADÉ |

```bash
# Activer VMAF avec mode test
bash convert.sh -v -t
```

## 🛠️ Dépannage

### FFmpeg sans libx265
```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# macOS
brew install ffmpeg

# Windows : télécharger depuis gyan.dev ou utiliser WSL
```

### Fichiers sautés
Consultez `logs/Skipped_*.log` - le fichier est probablement déjà en x265 avec un bitrate optimisé.

### Erreurs d'encodage
1. Vérifiez `logs/Error_*.log`
2. Vérifiez l'espace disque dans `/tmp`
3. Testez avec un seul fichier : `bash convert.sh -l 1`

### Caractères spéciaux dans les noms
Le script gère les espaces et caractères spéciaux, mais évitez les caractères de contrôle.

## 📝 Changelog récent

### v2.1 (Décembre 2025)
- ✅ Mode film aligné sur TyHD (two-pass 2035 kbps, keyint=240)
- ✅ GOP différencié : 240 frames (film) vs 600 frames (série)
- ✅ Tune fastdecode optionnel (activé série, désactivé film)
- ✅ Tests refactorisés : comportement vs valeurs en dur
- ✅ Affichage tests condensé avec progression temps réel

### v2.0 (Décembre 2025)
- ✅ Nouveaux paramètres x265 optimisés pour le mode série
- ✅ Pass 1 rapide (`no-slow-firstpass`) pour gain de temps
- ✅ Préparation conversion audio Opus 128k (désactivé temporairement)
- ✅ Amélioration gestion VMAF (détection fichiers vides)
- ✅ Suffixe dynamique avec indicateur `_tuned`

## 📄 Licence

MIT License - Libre d'utilisation et de modification.
