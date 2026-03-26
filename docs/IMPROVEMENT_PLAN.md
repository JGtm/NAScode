# NAScode — Plan d'amélioration

Issu de la revue de code complète du 2026-03-26.
Les items sont ordonnés par priorité et regroupés par thème.

---

## P1 — Robustesse critique

### P1-A · Propagation d'erreurs dans les sous-shells (`conversion.sh`)

**Problème**
Les captures `$(...)` de `ffprobe` avalent silencieusement les erreurs. Un fichier corrompu ou inaccessible peut être traité avec des métadonnées vides/partielles sans aucun signal d'erreur.

**Fichiers concernés**
- `lib/conversion.sh` — fonction `_convert_get_full_metadata()`
- `lib/media_probe.sh` — toute capture de sortie ffprobe via sous-shell

**Action**
Ajouter une vérification explicite du code de retour après chaque capture :

```bash
# Avant
full_metadata=$(_convert_get_full_metadata "$file_original")

# Après
if ! full_metadata=$(_convert_get_full_metadata "$file_original"); then
    log_error "ffprobe failed for: $file_original"
    return 1
fi
```

Vérifier également que `_convert_get_full_metadata()` propage elle-même le code retour de ffprobe (pas de `|| true` implicite).

**Critère de validation**
- Test unitaire : passer un fichier volontairement corrompu → doit produire une erreur loggée, pas un traitement silencieux.
- Test existant à adapter : `tests/test_media_probe.bats`

---

### P1-B · Hardening des fichiers temporaires (`nascode`)

**Problème**
Aucun `umask` restrictif n'est appliqué avant la création des répertoires et fichiers temporaires dans `/tmp/video_convert`. Sur un système multi-utilisateurs, les logs FFmpeg (qui peuvent contenir des chemins de fichiers) sont lisibles par tous.

**Fichiers concernés**
- `nascode` (point d'entrée)
- `lib/ffmpeg_pipeline.sh` — création des logs x265

**Action**
Ajouter en tête du script principal, après les déclarations initiales :

```bash
# Restreindre les permissions des fichiers créés par le processus
umask 0077
```

Vérifier que les `mktemp` existants n'ont pas besoin d'ajustements supplémentaires.

**Critère de validation**
- Lancer une conversion, vérifier que les fichiers dans `/tmp/video_convert` ont les permissions `600`/`700`.

---

### P1-C · Normalisation des chemins de sortie (`config.sh`)

**Problème**
`OUTPUT_DIR="$SCRIPT_DIR/Converted"` est correct par défaut, mais si l'utilisateur passe un `OUTPUT_DIR` absolu via variable d'environnement, la concaténation `$SCRIPT_DIR/$OUTPUT_DIR` produit un chemin invalide.

**Fichiers concernés**
- `lib/config.sh` — initialisation de `OUTPUT_DIR`
- Potentiellement `lib/args.sh` si `--output` est un argument CLI

**Action**
Normaliser après l'initialisation et après le parsing des arguments :

```bash
# Résoudre en chemin absolu si relatif
if [[ "$OUTPUT_DIR" != /* ]]; then
    OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
fi
# Résoudre les .. et symlinks
OUTPUT_DIR=$(realpath -m "$OUTPUT_DIR")
```

(`realpath -m` ne requiert pas l'existence du répertoire.)

**Critère de validation**
- Test : `OUTPUT_DIR=/tmp/out nascode ...` → le répertoire créé est bien `/tmp/out`, pas `$SCRIPT_DIR//tmp/out`.

---

## P2 — Qualité du code

### P2-A · Extraction de `_emit_audio_decision()` (`audio_decision.sh`)

**Problème**
`_emit_audio_decision()` est définie à l'intérieur de `_get_smart_audio_decision()`. Cela :
- Empêche les tests unitaires directs sur `_emit_audio_decision()`
- Redéfinit la fonction à chaque appel du parent (overhead mineur)
- Crée une fuite de scope implicite sur les variables parentes

**Fichiers concernés**
- `lib/audio_decision.sh` — lignes ~319–351

**Action**
Déplacer `_emit_audio_decision()` au niveau module (avant `_get_smart_audio_decision()`). Vérifier que les variables utilisées sont passées en paramètre ou déclarées `local` dans le parent.

**Critère de validation**
- `_emit_audio_decision()` peut être appelée directement dans un test Bats sans charger `_get_smart_audio_decision()`.
- Les tests existants `tests/test_audio_decision.bats` passent sans modification.

---

### P2-B · Centralisation des constantes magiques (`constants.sh`)

**Problème**
Plusieurs seuils numériques sont éparpillés dans le code sans nom explicite :
- `110` (marge 10%) dans `audio_decision.sh` ligne ~531
- `10` (tolérance 10%) dans `skip_decision.sh`
- D'autres seuils dans `complexity.sh` et `video_params.sh`

**Fichiers concernés**
- `lib/audio_decision.sh`, `lib/skip_decision.sh`, `lib/complexity.sh`, `lib/video_params.sh`
- `lib/constants.sh` (destination)

**Action**
Inventorier toutes les occurrences de nombres "magiques" portant une signification métier.
Pour chaque occurrence, ajouter une constante dans `constants.sh` avec commentaire explicatif, puis remplacer l'occurrence.

Exemples :

```bash
# constants.sh
# Marge de tolérance bitrate audio : on accepte jusqu'à 10% au-dessus du seuil
# avant de forcer un réencodage
AUDIO_BITRATE_MARGIN_PCT="${AUDIO_BITRATE_MARGIN_PCT:-110}"

# Gain minimal pour justifier un réencodage vidéo (en % de réduction de taille)
VIDEO_MIN_GAIN_PCT="${VIDEO_MIN_GAIN_PCT:-10}"
```

**Critère de validation**
- `grep -n '[^A-Z_][0-9]\{2,3\}[^0-9]' lib/audio_decision.sh` retourne significativement moins de résultats.
- Les constantes sont overridables via env var (pattern `${VAR:-default}` déjà en place).

---

### P2-C · Gardes sur champs vides dans le parsing IFS (`conversion.sh`)

**Problème**
Les lectures `IFS='|' read -r filename final_dir ...` ne vérifient pas si les champs sont vides avant de continuer. Une ligne malformée dans la queue peut produire un traitement avec `filename=""`.

**Fichiers concernés**
- `lib/conversion.sh` — lignes autour de 131

**Action**
Ajouter des gardes après chaque lecture IFS :

```bash
IFS='|' read -r filename final_dir conversion_params <<< "$queue_line"
[[ -z "$filename" ]] && { log_warn "Skipping malformed queue entry: $queue_line"; continue; }
```

**Critère de validation**
- Test : injecter une ligne vide ou mal formée dans la queue → doit logger un warning et passer à l'entrée suivante sans crash.

---

## P3 — Performance et maintenabilité

### P3-A · Validation du format de sortie ffprobe (`media_probe.sh`)

**Problème**
Le parsing AWK suppose une structure de sortie ffprobe fixe. Un changement de version de ffprobe (ou un fichier avec un format inhabituel) produit des échecs silencieux avec des variables vides.

**Fichiers concernés**
- `lib/media_probe.sh` — fonction `get_full_media_metadata()`

**Action**
Après le parsing, valider les champs critiques avant de les retourner :

```bash
# Vérifier que les champs minimaux sont présents
if [[ -z "$VIDEO_CODEC" || -z "$VIDEO_WIDTH" ]]; then
    log_error "ffprobe output missing critical fields for: $file"
    log_debug "Raw ffprobe output: $raw_output"
    return 1
fi
```

Optionnellement, logger la version ffprobe au démarrage pour faciliter le debug.

**Critère de validation**
- Test : passer un fichier audio-only (sans stream vidéo) → erreur claire, pas de variable vide propagée.

---

### P3-B · Indexation incrémentale (`queue.sh`)

**Problème**
Si l'index est invalide ou si `-R` est passé, une exploration complète du filesystem est effectuée. Pour de grandes bibliothèques (plusieurs milliers de fichiers), cela prend un temps significatif.

**Fichiers concernés**
- `lib/queue.sh`

**Action**
Stocker le timestamp du dernier scan dans l'index. Lors d'une mise à jour, utiliser `find -newer <timestamp_file>` pour ne rescanner que les fichiers modifiés. Conserver le scan complet pour `-R` et la première initialisation.

```bash
# Scan incrémental
find "$SOURCE" -newer "$INDEX_TIMESTAMP_FILE" -type f \( -name "*.mkv" -o -name "*.mp4" ... \)
```

**Critère de validation**
- Benchmark : sur une bibliothèque de 1000 fichiers, le deuxième scan (sans changement) est < 1s.
- Le scan complet reste accessible via `-R`.

---

### P3-C · Parallélisation de l'analyse VMAF (`vmaf.sh`)

**Problème**
L'analyse VMAF s'exécute séquentiellement même quand plusieurs fichiers sont dans la queue post-conversion. Chaque analyse nécessite un décodage complet, ce qui est coûteux.

**Fichiers concernés**
- `lib/vmaf.sh`

**Action**
Si `PARALLEL_JOBS > 1`, lancer les analyses VMAF en parallèle avec le même mécanisme de throttling que le traitement principal (FIFO ou `wait -n`). Réutiliser la logique de `processing.sh` si possible plutôt que de la dupliquer.

**Critère de validation**
- Avec `-j 2` et 4 fichiers à analyser, 2 analyses VMAF tournent simultanément.
- Les résultats sont correctement agrégés (pas de collision sur les fichiers de sortie).

---

## P4 — Tests

### P4-A · Tests de chemins Windows/Git Bash

**Problème**
Les chemins Windows (`C:\Users\...`, espaces dans les noms, séparateurs `\`) ne sont pas couverts par les tests existants. Les utilisateurs Git Bash sur Windows peuvent rencontrer des comportements inattendus.

**Fichiers concernés**
- `tests/` — nouveau fichier `test_windows_paths.bats`

**Action**
Créer un fichier de test dédié avec des fixtures simulant des chemins Windows typiques :
- Chemins avec espaces
- Chemins avec caractères spéciaux (`(`, `)`, `[`, `]`)
- Chemins très longs (> 200 caractères)

Mocker `realpath` si nécessaire pour simuler le comportement Git Bash.

**Critère de validation**
- Les tests passent à la fois sur Linux/macOS et sous Git Bash Windows.

---

### P4-B · Tests du traitement parallèle (`processing.sh`)

**Problème**
Le traitement parallèle (mode FIFO + `wait -n`) n'est pas testé. Les bugs de concurrence sont difficiles à reproduire manuellement.

**Fichiers concernés**
- `tests/` — nouveau fichier `test_parallel_processing.bats`

**Action**
Créer des tests avec des jobs fictifs (sleeps) pour vérifier :
- Que le throttling respecte `PARALLEL_JOBS`
- Qu'une erreur dans un job parallèle est bien propagée
- Que le cleanup est correct si un job est tué en cours

Utiliser des timeouts courts (1–2s) pour garder les tests rapides.

**Critère de validation**
- Un test avec `PARALLEL_JOBS=2` et 4 jobs vérifie que max 2 tournent simultanément (via comptage de PIDs actifs).

---

## Correctifs hors plan (bugs rapportés)

### BUG-1 · Crash sur sous-titres PGS (remux Blu-ray) — **Résolu 2026-03-26**

**Symptôme**
```
[sost#0:5/ssa] Subtitle encoding currently only possible from text to text or bitmap to bitmap
Error opening output file ...
```

**Cause** : `_build_stream_mapping()` (`lib/stream_mapping.sh`) mappait les streams de sous-titres sans `-c:s copy`. FFmpeg tentait alors de transcoder les sous-titres PGS (bitmap Blu-ray) en SSA (texte), opération impossible.

**Fix appliqué** : Ajout de `-c:s copy` systématique en fin de `_build_stream_mapping()`. Ajout d'un test de régression dédié dans `tests/test_regression_coverage.bats`.

**Bonus** : Ajout de `-probesize 100M -analyzeduration 100M` aux commandes FFmpeg (`lib/transcode_video.sh`, `lib/ffmpeg_pipeline.sh`) pour éviter les warnings "unspecified size" sur les remux avec 8+ streams. Valeur configurable via `FFMPEG_PROBESIZE` / `FFMPEG_ANALYZEDURATION`.

---

## Suivi

| ID | Titre | Priorité | Statut |
|----|-------|----------|--------|
| BUG-1 | Crash sous-titres PGS Blu-ray | — | ✅ Résolu |
| P1-A | Propagation erreurs sous-shells | P1 | ✅ Résolu |
| P1-B | Hardening fichiers temporaires | P1 | ✅ Résolu |
| P1-C | Normalisation chemins de sortie | P1 | ✅ Résolu |
| P2-A | Extraction `_emit_audio_decision` | P2 | À faire |
| P2-B | Centralisation constantes magiques | P2 | ✅ Résolu |
| P2-C | Gardes parsing IFS | P2 | ✅ Déjà couvert (`processing.sh:42`, garde `if !` sur `_prepare_file_paths`) |
| P3-A | Validation format ffprobe | P3 | ✅ Résolu (inclus dans P1-A) |
| P3-B | Indexation incrémentale | P3 | À faire |
| P3-C | Parallélisation VMAF | P3 | À faire |
| P4-A | Tests chemins Windows | P4 | À faire |
| P4-B | Tests traitement parallèle | P4 | À faire |
