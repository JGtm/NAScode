# 🎬 NAScode — Outil Bash — Conversion vidéo HEVC / AV1

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

# Filtrer l'index/queue : ignorer les petits fichiers (utile pour films)
bash nascode -m film --min-size 700M -s "/chemin/vers/films"
```

Defaults importants (issus de la config) :
- Mode : `serie`
- Codec vidéo : `hevc`
- Codec audio : `aac`
- Sortie : `Converted/`

## 🌐 Internationalisation (i18n)

NAScode supporte l'anglais et le français :

```bash
# Sortie en anglais
bash nascode --lang en -s "/chemin/source"

# Sortie en français (défaut)
bash nascode --lang fr -s "/chemin/source"
bash nascode -s "/chemin/source"

# Définir la langue via variable d'environnement
export NASCODE_LANG=en
bash nascode -s "/chemin/source"
```

Documentation disponible dans les deux langues :
- Français : [docs/fr/](docs/fr/)
- Anglais : [docs/](docs/)

## Ce que fait le script

- Convertit en **HEVC (x265)** ou **AV1** selon `--codec`.
- Gère une **file d’attente** (index persistant) et peut **skip** les fichiers déjà “bons”.
- Supporte un mode **video passthrough** (vidéo copiée, audio optimisé si pertinent).
- Ajoute un **suffixe** (dynamique ou personnalisé) pour refléter le codec vidéo, la résolution de sortie et (optionnellement) le codec audio.
- Optionnel : **VMAF** et **sample** pour tester rapidement.
- Limitation : les vidéos **en mode portrait** (vertical / rotation metadata) ne sont pas prises en charge de manière effective ; la logique d’estimation résolution/bitrate est principalement conçue pour des sources “paysage”, et peut produire des paramètres peu adaptés.

## 🎯 Matrices de décision (smart codec)

Ces tableaux résument les décisions les plus fréquentes (skip / copy / convert / downscale).
Pour la logique complète et les détails, voir [docs/fr/SMART_CODEC.md](docs/fr/SMART_CODEC.md).

### Audio (par défaut : `aac` stéréo)

Rappels :
- `--audio copy` : copie l'audio sans modification.
- `--force-audio` : force la conversion vers le codec cible (bypass smart).
- `--no-lossless` : force la conversion des codecs premium (DTS/DTS-HD/TrueHD/FLAC).
- `--equiv-quality` / `--no-equiv-quality` : active/désactive le mode "qualité équivalente" (audio + cap vidéo).
	(Ignoré en mode `adaptatif` : reste activé.)
- `--limit-fps` / `--no-limit-fps` : limite le FPS à 29.97 pour le contenu HFR (>30 fps).
	- Mode `serie` : activé par défaut (optimisation taille).
	- Modes `film` / `adaptatif` : désactivé par défaut (qualité max, bitrate majoré si HFR).
	- Note : VMAF est ignoré si le FPS est modifié (comparaison frame-à-frame impossible).

**Gestion des canaux (multicanal) :**
- **Mode `serie`** : stéréo forcée (downmix systématique si 5.1/7.1+).
- **Modes `film` / `adaptatif`** : layout cible stéréo (2ch) ou **5.1** (downmix automatique si 7.1).
- **Codec par défaut multichannel (film/adaptatif)** : EAC3 384k (compatible TV/receivers).
- **AAC multichannel** : uniquement avec `-a aac --force-audio` (plafond 320k).
- **Opus multichannel** : `-a opus` (plafond 224k).
- **Anti-upscale** : pas de conversion si source < 256k (sauf downmix requis).

**Codecs premium (DTS/DTS-HD/TrueHD/FLAC) :**
- **Sans `--no-lossless`** : passthrough (conservés si déjà 5.1, sinon downmix → EAC3 384k).
- **Avec `--no-lossless`** : conversion forcée (stéréo → codec cible, multichannel → EAC3 384k).

Note : en mode `serie`, la stéréo forcée peut convertir des cas autrement en `copy` (y compris premium) afin de garantir une sortie 2.0.

| Codec source | Statut | Channels | Bitrate source | Action | Résultat |
|-------------|--------|----------|----------------|--------|----------|
| DTS / DTS-HD / TrueHD | Premium | 5.1 | * | `copy` | Conservé (passthrough) |
| DTS / DTS-HD / TrueHD | Premium | 7.1 | * | `convert` | → EAC3 384k 5.1 (downmix) |
| FLAC | Lossless | * | * | `copy` | Conservé (qualité max) |
| Opus | Efficace | stéréo | $\le$ 128k | `copy` | Conservé tel quel |
| Opus | Efficace | 5.1+ | $\le$ 224k | `copy` | Conservé tel quel |
| AAC | Efficace | stéréo | $\le$ 160k | `copy` | Conservé tel quel |
| AAC | Efficace | 5.1 | $\le$ 320k | `copy` | Conservé tel quel |
| EAC3 | Standard | 5.1 | $\le$ 384k | `copy` | Conservé tel quel |
| EAC3 | Standard | 5.1 | $>$ 384k | `downscale` | EAC3 → 384k |
| AC3 | Inefficace | 5.1 | * | `convert` | → EAC3 384k |
| MP3 / PCM / autres | Inefficace | * | * | `convert` | → codec cible |

### Vidéo (cible par défaut : `hevc`)

Rappels :
- Hiérarchie (efficacité) : AV1 > HEVC > VP9 > H.264 > MPEG4
- Le “skip” dépend d’un seuil dérivé de `MAXRATE_KBPS` et d’une tolérance :
	- $\text{seuil} = \mathrm{MAXRATE}_{\mathrm{KBPS}} \times (1 + \text{tolérance})$
	- Par défaut : tolérance 10%
	- Si la source est dans un codec **plus efficace** que la cible (ex: AV1 alors que la cible est HEVC), le seuil est **traduit** dans l’espace du codec source via l’efficacité codec.
	- Exemple (mode `serie`, cible HEVC) : seuil HEVC 2772k → seuil AV1 ≈ $2772 \times 50/70 \approx 1980$k
- `--force-video` : force le ré-encodage vidéo (bypass smart).
- `--equiv-quality` / `--no-equiv-quality` : active/désactive le mode "qualité équivalente" (audio + cap vidéo).
	(Ignoré en mode `adaptatif` : reste activé.)

| Codec source | vs cible | Bitrate (vs seuil) | Action | Résultat |
|-------------|----------|--------------------|--------|----------|
| AV1 | > HEVC | $\le$ seuil (traduit) | `skip` | Conservé (meilleur codec, bitrate OK) |
| AV1 | > HEVC | $>$ seuil (traduit) | `encode` | Ré-encodage **en AV1** (pas de downgrade) |
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
- [docs/fr/DOCS.md](docs/fr/DOCS.md)
- [docs/fr/USAGE.md](docs/fr/USAGE.md)
- [docs/fr/CONFIG.md](docs/fr/CONFIG.md)

Référence code (audio) :
- Décision “smart codec” : [lib/audio_decision.sh](lib/audio_decision.sh)
- Construction FFmpeg/layout : [lib/audio_params.sh](lib/audio_params.sh)

## Logs & sortie

- Sortie par défaut : `Converted/` (dans le dossier du script)
- Logs : `logs/` (dans le dossier du script)
- Si une conversion produit un fichier plus lourd (ou un gain < seuil), la sortie est redirigée vers `Converted_Heavier/` (configurable) pour éviter les boucles de re-traitement.

Détails : [docs/fr/TROUBLESHOOTING.md](docs/fr/TROUBLESHOOTING.md)

### Dépannage rapide (cas fréquents)

- **Aucun fichier à traiter** : tes filtres/exclusions ont probablement tout éliminé (ex: `--min-size`, `EXCLUDES`, mauvaise `-s`). Réessaie sans filtre, ou force une régénération : `bash nascode -R -s "..."`.
- **Queue invalide (séparateur NUL)** : si tu fournis une queue custom, elle doit être *null-separated*. Sinon, supprime `logs/Queue` et relance avec `-R`.
- **Source exclue par la config** : si tu vois une erreur indiquant que `SOURCE` est dans `EXCLUDES`, change `-s` ou retire l’exclusion (dans la config).

## Notifications Discord (optionnel)

NAScode peut envoyer des notifications via un **webhook Discord** (format Markdown) :

- au démarrage : **paramètres actifs** + aperçu de la queue (jusqu’à 20 éléments, avec troncature)
- pendant le run : **début/fin de chaque fichier** (préfixe `[i/N]`, durée, tailles `avant → après`)
- pendant le run : **skip d’un fichier** (ignoré + raison)
- transferts : **en attente** puis **terminés** (si applicable)
- VMAF (si activé) : démarrage + **résultat par fichier** (note/qualité) + fin globale
- en entrée/sortie des heures pleines quand `--off-peak` est actif
- à la fin : résumé (si disponible) puis un message de **fin avec horodatage**

Configuration (via variables d’environnement) :

- `NASCODE_DISCORD_WEBHOOK_URL` (obligatoire) : URL du webhook (secret)
- `NASCODE_DISCORD_NOTIFY` (optionnel) : `true/false` (par défaut `true` si l’URL est définie)

Recommandé (local, non versionné) :

```bash
cp .env.example .env.local
# puis édite .env.local (NE PAS commiter)
bash nascode -s "/chemin/vers/series"
```

Par défaut, `nascode` charge automatiquement `./.env.local` (si présent) au démarrage.

- Désactiver : `NASCODE_ENV_AUTOLOAD=false`
- Utiliser un autre fichier : `NASCODE_ENV_FILE=/chemin/vers/mon.env`

Sécurité : ne commit jamais le webhook. Si tu l’as posté dans un chat/log/issue, considère-le compromis et régénère-le côté Discord.

## Documentation

- Index docs : [docs/fr/DOCS.md](docs/fr/DOCS.md)
- Configuration avancée & constantes : [docs/fr/CONFIG.md](docs/fr/CONFIG.md)
- Ajouter un nouveau codec : [docs/fr/ADDING_NEW_CODEC.md](docs/fr/ADDING_NEW_CODEC.md)
- Instructions macOS : [docs/fr/Instructions-Mac.txt](docs/fr/Instructions-Mac.txt)
- Critères de conversion : [docs/fr/SMART_CODEC.md](docs/fr/SMART_CODEC.md)

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

- Règles de travail : [agent.md](.ai/agent.md)
- Copilot (repo-level) : [.github/copilot-instructions.md](.github/copilot-instructions.md)

## Changelog

Voir : [docs/fr/CHANGELOG.md](docs/fr/CHANGELOG.md)

## Licence

MIT License - Libre d'utilisation et de modification.
