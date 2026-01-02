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
- `-p, --off-peak [HH:MM-HH:MM]` : n’exécuter que pendant les heures creuses
- `--force-audio` / `--force-video` / `--force` : bypass de certaines décisions smart

Pour comprendre les décisions audio/vidéo (skip/passthrough/convert), voir [SMART_CODEC.md](SMART_CODEC.md).
