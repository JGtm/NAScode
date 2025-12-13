# Conversion_Libx265 — README

Description
- **But:** : Script d'automatisation pour convertir des vidéos vers HEVC (`libx265`) en batch, spécialement orienté pour des séries/films.
- **Script principal:** : `Conversion_Libx265.sh` (ou `Conversion_Libx265_v18.sh` selon votre copie).

Prérequis
- **Système:** : GNU/Linux, macOS ou Windows via WSL / Git Bash.
- **Outils:** : `ffmpeg` (build avec `libx265`), `ffprobe` (optionnel), utilitaires shell standards (`awk`, `stat`, `md5sum` ou `md5`).

Installation rapide
- Copier le script dans le dossier contenant vos fichiers vidéo (ou préciser `--source`).
- Rendre exécutable : `chmod +x Conversion_Libx265.sh`

Usage
- **Commande générale:** :

```bash
bash Conversion_Libx265.sh [options]
```

- **Paramètres courants:**
  - **`--source` / `-s` :** dossier source (par défaut, dossier du script).
  - **`--output-dir` / `-o` :** dossier de sortie (par défaut `Converted`).
  - **`--mode` / `-m` :** `serie` (défaut) ou `film` (ajuste CRF/preset).
  - **`--dry-run` / `-d` :** simulation sans lancer d'encodage.
  - **`--no-suffix` / `-x` :** n'ajoute pas le suffixe de sortie (risque d'écrasement).
  - **`--random` / `-r`` et `--limit` / `-l` :** sélectionner un sous-ensemble aléatoire.

Options recommandées
- **CRF:** règle la qualité (ex. `--crf 20`). Plus bas = meilleure qualité et fichier plus gros.
- **Preset:** `--preset slow|medium|fast` — presets plus lents offrent meilleure compression.
- **Audio:** `--audio-copy` pour garder l'audio original, ou `--audio-bitrate 192k` pour réencoder.

Exemples
- Conversion rapide avec CRF 22 :

```bash
bash Conversion_Libx265.sh -s "/chemin/vers/source" -o "/chemin/vers/Converted" --crf 22 --preset medium
```

- Simulation en mode film :

```bash
bash Conversion_Libx265.sh --mode film --dry-run
```

Bonnes pratiques
- Tester sur un épisode/clip court avant d'encoder toute une saison.
- Toujours lancer avec `--dry-run` pour valider la nomenclature et éviter écrasement.
- Conserver les originaux jusqu'à validation finale.

Logs & sorties
- Les logs et fichiers temporaires sont créés dans `./logs/` (ex. `Success_*.log`, `Error_*.log`, `Index`, `Queue_readable_*.txt`).

Dépannage
- Vérifier que `ffmpeg` supporte `libx265` : `ffmpeg -version`.
- Consulter `./logs/Error_*.log` en cas d'échec d'encodage.

Personnalisation
- Paramètres modifiables en tête du script : `SUFFIX_STRING`, `CRF` par mode, `ENCODER_PRESET`, `PARALLEL_JOBS`, etc.

Sécurité
- N'utilisez pas `--no-suffix` sans changer `--output-dir` hors du dossier source.

**Fonctionnalités principales**
- Traitement batch de dossiers (séries, films).
- File d'attente et indexation (tri par taille, filtrage, limitation).
- Mode `--dry-run` pour valider sans encoder.
- Protection contre l'écrasement (suffixes, confirmations).
- Gestion des logs détaillés et reprise possible.

**Paramètres & options détaillées**
**Paramètres & options détaillées**
- `-s, --source DIR` : dossier source (par défaut : le dossier parent du script). Le chemin est converti en absolu au démarrage.
- `-o, --output-dir DIR` : dossier de sortie (par défaut : `Converted` dans le répertoire du script).
- `-e, --exclude PATTERN` : ajouter un pattern d'exclusion (glob) pour ignorer des fichiers/dossiers.
- `-m, --mode MODE` : `serie` (défaut) ou `film` — ajuste les paramètres internes (`TARGET_BITRATE_KBPS`, `ENCODER_PRESET`, etc.).
- `-d, --dry-run | --dryrun` : mode simulation — aucun encodage; les fichiers de sortie sont simplement créés (utile pour vérification).
- `-x, --no-suffix` : désactive le suffixe de sortie (`_x265`). Le script demandera confirmation si la sortie est le même répertoire (protection contre écrasement).
- `-r, --random` : sélection aléatoire des fichiers (si utilisé, `--limit` s'applique à la sélection). Par défaut, si `--random` est activé et `--limit` absent, la limite par défaut est 10.
- `-l, --limit N` : limiter le nombre de fichiers traités à N (doit être un entier strictement positif).
- `-q, --queue FILE` : utiliser un fichier `queue` personnalisé (format attendu : noms de fichiers séparés par NUL). Le fichier doit exister et ne pas être vide.
- `-n, --no-progress` : désactiver les barres et sorties de progression (utile pour exécution non interactive).
- `-k, --keep-index` : conserver un `Index` existant sans demander confirmation (réutilise l'index déjà généré).
- `-v, --vmaf` : activer l'évaluation VMAF (nécessite `libvmaf` présent dans la build `ffmpeg`).
- `-h, --help` : afficher l'aide intégrée et les options prises en charge.

Remarques importantes :
- Le script réalise systématiquement un encodage en deux passes pour la vidéo (pass 1 = analyse, pass 2 = encodage final).
- L'audio est copié par défaut (`-c:a copy` dans la commande `ffmpeg`) ; il n'y a pas d'option CLI pour réencoder l'audio — modifiez le script si vous souhaitez un comportement différent.
- Les paramètres d'encodage (préset, bitrate cible, seuils, suffixe, parallélisation) sont contrôlés par des variables en tête du script : `ENCODER_PRESET`, `TARGET_BITRATE_KBPS`, `SUFFIX_STRING`, `PARALLEL_JOBS`, `BITRATE_CONVERSION_THRESHOLD_KBPS`, `SORT_MODE`, etc. Ces réglages ne sont pas tous exposés en ligne de commande.
- Modes de tri disponibles pour la construction de la file d'attente : `size_desc`, `size_asc`, `name_asc`, `name_desc` (variable `SORT_MODE`).

Options avancées (exemples d'utilisation interne)
- `BITRATE_CONVERSION_THRESHOLD_KBPS` : seuil au-dessus duquel l'audio est réencodé ou conservé.
- `PARALLEL_JOBS` : variable pour ajuster la parallélisation dans le script.

Exemples avancés
- Encodage de base (CRF 22, preset medium) :

```bash
bash Conversion_Libx265.sh -s "/chemin/vers/source" -o "/chemin/vers/Converted" --crf 22 --preset medium
```

- Conserver l'audio et les sous-titres :

```bash
bash Conversion_Libx265.sh "Episode.mkv" "Episode_x265.mkv" --crf 20 --audio-copy --copy-subs
```

- Encodage 2-pass pour bitrate cible (ex. 2000 kbps) :

```bash
bash Conversion_Libx265.sh input.mkv output_x265.mkv --two-pass --target-bitrate 2000k
```

- Incruster (hardsub) un fichier de sous-titres :

```bash
bash Conversion_Libx265.sh input.mkv output_x265.mkv --crf 20 --hardsub subs.srt
```

- Traitement parallèle (N jobs) :

```bash
bash Conversion_Libx265.sh -s "/chemin" --parallel 4
```

Windows / WSL / Git Bash
- Sur Windows, préférez WSL (Ubuntu) pour compatibilité complète avec Bash et outils POSIX.
- Avec Git Bash, certaines fonctionnalités (ionice, fifo) peuvent manquer.
- Vérifiez `ffmpeg -version`; si `libx265` n'apparaît pas, installez une build tierce ou utilisez WSL.

Commandes utiles
- Vérifier ffmpeg et libx265 :

```bash
ffmpeg -version
ffmpeg -hide_banner -encoders | grep libx265
```

- Extraire les pistes audio / subs avec `ffprobe`/`ffmpeg` si nécessaire.

Dépannage rapide
- Erreur `libx265` non trouvée → installer ffmpeg avec `libx265` ou utiliser WSL.
- Fichiers sautés / erreurs → consulter `./logs/Error_*.log` et `Progress_*.log`.
- Vérifiez l'espace disque, permissions et les noms de fichiers / caractères spéciaux.

Personnalisation
- Variables en tête du script (ex. `SUFFIX_STRING`, `DEFAULT_CRF_SERIE`, `DEFAULT_CRF_FILM`, `PARALLEL_JOBS`) peuvent être ajustées selon vos besoins.

FAQ rapide
- Puis-je restaurer les originaux ? Oui — conservez-les jusqu'à validation, ou ajoutez une option `--remove-source` après validation manuelle.
- Le script gère-t-il les chapitres ? Le support dépend de la façon dont `ffmpeg` est appelé dans le script ; on peut ajouter la copie des chapitres (`-map_chapters`).