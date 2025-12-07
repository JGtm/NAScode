**Conversion Libx265 v18**

Script Bash d'automatisation de la conversion vidéo vers HEVC (libx265) avec gestion de file d'attente, logs, mode dry-run et protection contre l'écrasement.

**But :**
- **Description :** Convertir des vidéos (mp4/mkv/avi/mov) en Matroska HEVC (`libx265`) en batch, avec options de tri, limitation, mode aléatoire, et journalisation détaillée.

**Prérequis :**
- **Système :** GNU/Linux ou macOS avec Bash compatible (`bash` moderne).
- **Outils :** `ffmpeg` (recommandé >= 8), `ffprobe`, `awk`/`gawk`, `md5sum` (ou `md5` sur macOS), `stat`, `dd`.
- **Optionnel :** `brew` (pour compatibilité macOS), `python3` (fallbacks), `ionice` (optimisation IO).

**Fichiers :**
- **Script principal :** `Conversion_Libx265_v18.sh`
- **Logs et index :** créés dans `./logs/` lors de l'exécution

**Installation rapide :**
- Copier le script dans le dossier contenant vos vidéos (ou ajuster `--source`).
- Rendre exécutable : `chmod +x Conversion_Libx265_v18.sh`

**Usage basique :**
- Lancer en mode par défaut (séries) :
  - `./Conversion_Libx265_v18.sh`
- Spécifier un dossier source et de sortie :
  - `./Conversion_Libx265_v18.sh -s /chemin/vers/source -o /chemin/vers/Converted`

**Options importantes :**
- `-s, --source DIR` : Dossier source (par défaut le dossier parent du script).
- `-o, --output-dir DIR` : Dossier de sortie (par défaut `Converted` au même niveau que le script).
- `-m, --mode MODE` : `film` ou `serie` (défaut : `serie`).
- `-d, --dry-run` : Simulation — aucun encodage effectué, fichiers vides créés pour vérification.
- `-x, --no-suffix` : Ne pas ajouter le suffixe de sortie (`_x265`). ATTENTION : risque d'écrasement si sortie = source.
- `-r, --random` : Sélection aléatoire (utilisable avec `--limit`).
- `-l, --limit N` : Limiter le nombre de fichiers à traiter.
- `-q, --queue FILE` : Utiliser un fichier `queue` personnalisé (séparateur NUL attendu).
- `-n, --no-progress` : Désactive l'affichage des barres/progressions.
- `-k, --keep-index` : Réutiliser l'index existant sans confirmation interactive.

**Exemples :**
- Conversion standard :
  - `./Conversion_Libx265_v18.sh`
- Conversion en mode film (qualité supérieure) en simulation :
  - `./Conversion_Libx265_v18.sh --mode film --dry-run`
- Traiter 5 fichiers aléatoires :
  - `./Conversion_Libx265_v18.sh -r -l 5`

**Logs et sortie :**
- Logs : `./logs/Success_*.log`, `Error_*.log`, `Skipped_*.log`, `Progress_*.log`.
- Index temporaire et queue : `./logs/Index`, `./logs/Queue_readable_*.txt`.

**Sécurité / bonnes pratiques :**
- Ne lancez pas avec `--no-suffix` si `--output-dir` est le même que la source (risque d'écrasement). Le script avertit et demande confirmation.
- Utilisez `--dry-run` avant toute grosse exécution pour vérifier la nomenclature et les collisions.
- Vérifiez l'espace libre sur `/tmp` (ou configurez `TMP_DIR`) ; le script requiert par défaut au moins `2048 MB` libres.

**Personnalisation :**
- `CRF`, `ENCODER_PRESET` et autres paramètres sont définis par le mode (`film` / `serie`) via `set_conversion_mode_parameters`.
- Vous pouvez modifier `SUFFIX_STRING`, `BITRATE_CONVERSION_THRESHOLD_KBPS`, `PARALLEL_JOBS` en tête du script.

**Comportement avancé :**
- Le script construit un `INDEX` (taille\tchemin) puis une `QUEUE` triée (par défaut par taille décroissante).
- Si `--limit` est utilisé, la queue est limitée et alimentée dynamiquement si des fichiers sont `SKIPPED`.
- Un FIFO dans `./logs/` est utilisé pour la coordination en parallèle.

**Troubleshooting rapide :**
- Erreurs ffmpeg -> consulter `./logs/Error_*.log` pour détails détaillés.
- Problèmes de dépendances -> exécuter `ffmpeg -version` et `ffprobe -version`.

**Licence et contributions :**
- License : `MIT`
- Contributions : ouvrir une issue ou un pull request sur le dépôt GitHub.

---