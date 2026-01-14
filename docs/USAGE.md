# Usage

## Commande

```bash
bash nascode [options]
```

Astuce : pour l’aide complète, utiliser :

```bash
bash nascode --help
```

## Exemples (les plus utiles)

```bash
# Conversion standard d'un dossier (mode série par défaut)
bash nascode -s "/chemin/vers/series"

# Mode film (plus orienté qualité)
bash nascode -m film -s "/chemin/vers/films"

# Conversion AV1
bash nascode -c av1 -s "/chemin/vers/videos"

# VMAF (si ton ffmpeg a libvmaf)
bash nascode -v -s "/chemin/vers/films"

# Sample (segment ~30s) pour tester rapidement
bash nascode -t -s "/chemin/vers/series"

# Random + limite
bash nascode -r -l 5 -s "/chemin/vers/series"

# Heures creuses (plage par défaut 22:00-06:00)
bash nascode -p -s "/chemin/vers/series"

# Heures creuses avec plage personnalisée
bash nascode --off-peak=23:00-07:00 -s "/chemin/vers/series"

# Fichier unique (bypass index/queue)
bash nascode -f "/chemin/vers/video.mkv"

# Dry-run (simulation)
bash nascode -d -s "/chemin/source"

# Quiet (warnings/erreurs uniquement)
bash nascode --quiet -s "/chemin/vers/series"
```

## Options principales (rappel)

Le script évolue : la table ci-dessous est un rappel, l’autorité reste `bash nascode --help`.

- `-s, --source DIR` : dossier source
- `-o, --output-dir DIR` : dossier de sortie
- `-m, --mode MODE` : `serie` (défaut) ou `film`
- `-c, --codec CODEC` : `hevc` (défaut) ou `av1`
- `-a, --audio CODEC` : `aac` (défaut), `copy`, `ac3`, `eac3`, `opus`
- `--min-size SIZE` : filtrer l’index/queue (ne garder que les fichiers >= SIZE, ex: `700M`, `1G`)
- `-v, --vmaf` : activer VMAF
- `-t, --sample` : encoder un segment de test
- `-n, --no-progress` : désactiver l’affichage des indicateurs de progression
- `-Q, --quiet` : mode silencieux (n’affiche que les warnings/erreurs)
- `-p, --off-peak [HH:MM-HH:MM]` : n’exécuter que pendant les heures creuses
- `--force-audio` / `--force-video` / `--force` : bypass de certaines décisions smart

Pour comprendre les décisions audio/vidéo (skip/passthrough/convert), voir [SMART_CODEC.md](SMART_CODEC.md).

## Sorties plus lourdes / gain faible ("Heavier")

Si une conversion produit un fichier **plus lourd** (ou un gain inférieur à un seuil), NAScode peut rediriger la sortie vers un dossier séparé afin d’éviter les boucles de re-traitement.

- Dossier par défaut : `Converted_Heavier/` (à côté de `Converted/`), en conservant l'arborescence.
- Anti-boucle : si une sortie "Heavier" existe déjà pour un fichier, NAScode **skip** ce fichier.

Réglages (dans la config) :

- `HEAVY_OUTPUT_ENABLED` : `true`/`false`
- `HEAVY_MIN_SAVINGS_PERCENT` : gain minimum en %
- `HEAVY_OUTPUT_DIR_SUFFIX` : suffixe de dossier (défaut `_Heavier`)

Voir aussi : [CONFIG.md](CONFIG.md)

## Notifications Discord (optionnel)

NAScode supporte des notifications via webhook Discord (Markdown). Elles sont **best-effort** : une erreur réseau ne doit pas interrompre la conversion.

Contenu typique des notifications :

- Démarrage : paramètres actifs + aperçu de la queue (format `[i/N]`, jusqu’à 20 éléments)
- Par fichier : démarrage puis fin (durée + tailles `avant → après`)
- Par fichier : skip (ignoré + raison)
- Transferts : en attente puis terminés (si applicable)
- VMAF (si activé) : démarrage + résultat par fichier (note/qualité) + fin globale
- Fin : résumé (si disponible) puis message final avec horodatage

Variables d’environnement :

- `NASCODE_DISCORD_WEBHOOK_URL` : URL du webhook (secret)
- `NASCODE_DISCORD_NOTIFY` : `true` / `false` (optionnel)

### Exemple (Git Bash / WSL)

	# Recommandé : fichier local ignoré par Git
	cp .env.example .env.local

	bash nascode -p -s "/chemin/vers/series"

	# Note : `nascode` charge automatiquement `./.env.local` (si présent).
	# Désactiver : NASCODE_ENV_AUTOLOAD=false
	# Autre fichier : NASCODE_ENV_FILE=/chemin/vers/mon.env

### Exemple (PowerShell)

	$env:NASCODE_DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/<id>/<token>"
	$env:NASCODE_DISCORD_NOTIFY = "true"

	bash .\nascode -s "C:\\chemin\\vers\\series"

Bonnes pratiques : ne mets jamais le webhook dans le repo. Si l’URL a été partagée publiquement, régénère le webhook.
