# Outils de progression pour Conversion_v17

Ce dossier contient deux petits scripts Python utilisés par `Conversion_v17.sh` pour fournir un affichage de progression robuste, multi-processus et cross-platform lors d'encodages FFmpeg exécutés en parallèle.

Fichiers
- `ffmpeg_progress_writer.py` : lit la sortie `-progress pipe:1` de `ffmpeg` et écrit périodiquement des fichiers de progression atomiques dans un répertoire partagé (p.ex. `/tmp/video_convert/progress`). Chaque job écrit un fichier `job_<id>.txt` contenant des champs séparés par `|` : `name|percent|seconds`.
- `progress_monitor.py` : lit le répertoire de progression et affiche une vue agrégée (une ligne par job) dans le terminal. Supporte une option `--plain` pour sortir en texte simple (utile si le terminal n'accepte pas les séquences ANSI, p.ex. certains environnements Windows).

But et architecture
- Contexte : lors d'exécutions en parallèle (`xargs -P`), plusieurs processus `ffmpeg` écrivant simultanément sur stdout provoquent un affichage mélangé et illisible.
- Solution : chaque tâche `ffmpeg` pipe sa sortie `-progress pipe:1` vers `ffmpeg_progress_writer.py` qui écrit un petit fichier atomique pour cette tâche. Un seul moniteur (`progress_monitor.py`) lit ces fichiers et met à jour l'affichage.

Format des fichiers job
- Nom du fichier : `job_<RANDOM>_<PID>.txt` (ou autre convention choisie par le script appelant).
- Contenu (ligne unique, champs séparés par `|`) :
  - `name` : nom affiché du job (généralement le nom de base du fichier traité)
  - `percent` : pourcentage (nombre réel, ex: `23.4`)
  - `seconds` : time progress ou timestamp utile pour calculer ETA (nombre)

Exemples d'utilisation

1) Lancer le moniteur (séparément)

Sur Linux/macOS (terminal ANSI):

```bash
python3 tools/progress_monitor.py --dir /tmp/video_convert/progress --refresh 0.7
```

Sur Windows (PowerShell) si les séquences ANSI posent problème :

```powershell
python tools/progress_monitor.py --dir C:\Temp\video_convert\progress --plain
```

2) Exemple d'utilisation côté `ffmpeg` (ceci est fait automatiquement par `Conversion_v17.sh` lorsque `PROGRESS_DIR` existe) :

```bash
ffmpeg -i input -c:v hevc_nvenc ... -progress pipe:1 -nostats 2> ffmpeg_err.log | \
  python3 tools/ffmpeg_progress_writer.py --duration 1234 --job-file /tmp/video_convert/progress/job_123.txt --name "Episode_01"
```

- `--duration` : durée totale estimée en secondes (nécessaire pour calculer le pourcentage).
- `--job-file` : chemin du fichier à écrire (le script fait une écriture atomique via un `.tmp` puis `os.replace`).
- `--name` : étiquette du job pour l'affichage.

Notes sur l'intégration avec `Conversion_v17.sh`
- Le script `Conversion_v17.sh` crée `PROGRESS_DIR` (par défaut `"$TMP_DIR/progress"`) et lance `progress_monitor.py` en arrière-plan avant de lancer les jobs en parallèle. Chaque conversion individuelle appelle `ffmpeg_progress_writer.py` via un pipe depuis ffmpeg.
- Si Python n'est pas disponible ou si `NO_PROGRESS=true`, le script retombe sur l'ancien pipeline `awk` pour la compatibilité.

Dépendances
- Python 3.8+ (aucune dépendance externe requise). Le code utilise uniquement la stdlib.
- `ffmpeg`/`ffprobe` (gérés par `Conversion_v17.sh`).

Conseils Windows
- PowerShell moderne et Windows 10+ affichent correctement les séquences ANSI. Si vous rencontrez des problèmes d'affichage, lancer le moniteur avec `--plain` évite l'utilisation des mouvements du curseur et produit une sortie ligne-par-ligne.
- Assurez-vous que le répertoire `PROGRESS_DIR` est accessible en écriture par les processus ffmpeg/les scripts (p.ex. `C:\Temp\video_convert\progress`).

Dépannage
- Aucun fichier job créé : vérifiez que `ffmpeg` pipe bien `-progress pipe:1` vers le writer et que `python` est présent.
- Moniteur vide : vérifiez que les fichiers job existent dans le répertoire, que leurs permissions sont correctes et que le format est `name|percent|seconds`.
- Moniteur non-ANSI : réessayez avec `--plain`.

Commandes de test rapides
- Démarrer le moniteur (Linux) :

```bash
python3 tools/progress_monitor.py --dir /tmp/video_convert/progress --refresh 0.7
```

- Simuler un job (écrire manuellement un fichier job pour vérifier le moniteur) :

```bash
mkdir -p /tmp/video_convert/progress
printf "Episode_01|12.3|45" > /tmp/video_convert/progress/job_test.txt
# Mettre à jour le fichier plusieurs fois pour simuler la progression
sleep 1; printf "Episode_01|45.0|120" > /tmp/video_convert/progress/job_test.txt
```

Améliorations proposées
- Ajouter un contrôle optionnel dans `check_dependencies()` de `Conversion_v17.sh` pour vérifier la présence de `python3` ou `python` et avertir l'utilisateur si absent.
- Ajout d'un petit `tools/requirements.txt` si l'on venait à ajouter des dépendances externes plus tard.

Retrait / nettoyage
- Supprimer les fichiers job après chaque conversion (le script `Conversion_v17.sh` supprime le fichier job à la fin du job). Pour nettoyage manuel :

```bash
rm -rf /tmp/video_convert/progress/*
```

Contact / suite
- Si vous voulez, je peux :
  - Ajouter la vérification `python` dans `Conversion_v17.sh` (modification de `check_dependencies()`).
  - Ajuster le moniteur pour gérer d'autres métadonnées (p.ex. vitesse d'encodage, ETA plus précise).

---

Merci — dites-moi si vous souhaitez que j'ajoute la vérification `python` directement dans `Conversion_v17.sh` ou que j'adapte le README en anglais.