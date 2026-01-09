# DEVBOOK

Ce document sert de **mémoire durable** du projet : décisions, conventions, changements notables.

Objectifs :
- Faciliter les reprises de contexte (humains et agents).
- Garder une trace des évolutions qui impactent le comportement, l'UX CLI, les tests ou l'architecture.

## Format des entrées

- Une entrée par date au format `YYYY-MM-DD`.
- Décrire : **quoi** (résumé), **où** (fichiers), **pourquoi**, et **impact** (tests/doc/risques) si applicable.

## Journal

### 2026-01-02

#### UX : Compteur fichiers convertis pour mode limite
- **Quoi** : En mode limite (`-l N`), afficher un compteur `[X/N]` qui n'incrémente que sur les fichiers réellement convertis (pas les skips). Afficher un message jaune si la limite n'est pas atteinte car tous les fichiers restants sont déjà optimisés.
- **Où** :
  - `lib/queue.sh` : ajout `increment_converted_count()` et `get_converted_count()` (helpers avec mutex)
  - `lib/processing.sh` : init `CONVERTED_COUNT_FILE`, affichage bloc jaune en fin de run si `converted < limit`
  - `lib/conversion.sh` : modification `_get_counter_prefix()` pour afficher `[X/LIMIT]` en mode limite, incrément après décision "pas skip"
- **Pourquoi** : UX améliorée — l'utilisateur voit clairement combien de fichiers ont été effectivement convertis, et un message explicatif évite la frustration si la limite demandée n'est pas atteinte.
- **Impact** :
  - Mode normal inchangé (compteur `[X/Y]` existant)
  - Tests Bats ajoutés : `test_queue.bats` (5 tests pour les nouveaux helpers)
  - Documentation : `DEVBOOK.md`, `handoff.md`

#### Documentation & Pipeline multimodal
- Ajout du processus "Pipeline de Développement Multimodal" dans `agent.md` et `.github/copilot-instructions.md`.
- Création de `DEVBOOK.md` pour tracer les changements clés et maintenir la mémoire du projet.
- Refonte de `README.md` en version courte (TL;DR + liens) et création d'une documentation détaillée dans `docs/` : `docs/DOCS.md`, `docs/USAGE.md`, `docs/CONFIG.md`, `docs/SMART_CODEC.md`, `docs/TROUBLESHOOTING.md`, `docs/CHANGELOG.md`.

#### Feature : `--min-size` (filtre taille pour index/queue)
- **Quoi** : Nouvelle option CLI `--min-size SIZE` pour filtrer les fichiers lors de la construction de l'index et de la queue (ex: `--min-size 700M`, `--min-size 1.5G`).
- **Où** :
  - `lib/utils.sh` : ajout de `get_file_size_bytes()` et `parse_human_size_to_bytes()` (supporte décimaux via awk)
  - `lib/args.sh` : parsing de l'option `--min-size`
  - `lib/config.sh` : variable `MIN_SIZE_BYTES` (défaut: 0 = pas de filtre)
  - `lib/queue.sh` : filtre appliqué dans `_count_total_video_files()`, `_index_video_files()`, `_handle_custom_queue()`, et `_build_queue_from_index()`
  - `lib/exports.sh` : export de `MIN_SIZE_BYTES`
- **Pourquoi** : Cas d'usage films — ignorer les petits fichiers (bonus, samples, extras) pour ne traiter que les vrais films.
- **Impact** :
  - Le filtre s'applique **uniquement** à l'index/queue (pas à `-f/--file` fichier unique).
  - Les logiques de skip/passthrough/conversion restent inchangées.
  - Tests Bats ajoutés : `test_args.bats` (parsing), `test_queue.bats` (filtrage).
  - Documentation : `README.md` (exemple), `docs/USAGE.md` (option listée).
- **Audit** : Bug corrigé — le compteur de progression était incrémenté avant le filtre taille, causant un affichage incorrect. Fix : déplacement de l'incrément après le filtre.
- **Collaboration** : Implémentation initiale (ChatGPT), audit et corrections (Claude Haiku).

#### Feature : `film-adaptive` (bitrate adaptatif par fichier)
- **Quoi** : Nouveau mode de conversion `-m film-adaptive` qui analyse la complexité de chaque fichier et calcule un bitrate personnalisé.
- **Où** :
  - `lib/complexity.sh` : nouveau module — analyse statistique des frames (multi-échantillonnage à 25%, 50%, 75%)
  - `lib/config.sh` : constantes `ADAPTIVE_*`, ajout du mode `film-adaptive`
  - `lib/video_params.sh` : intégration des paramètres adaptatifs dans `compute_video_params()`
  - `lib/transcode_video.sh` : utilisation des variables `ADAPTIVE_TARGET_KBPS`, `ADAPTIVE_MAXRATE_KBPS`
  - `lib/conversion.sh` : seuil de skip adaptatif pour le mode
  - `lib/exports.sh` : export des nouvelles variables
  - `tests/test_film_adaptive.bats` : 22 tests unitaires couvrant le module
- **Pourquoi** : Les films ont une complexité variable (dialogues vs action). Un bitrate fixe sous-encode les scènes complexes ou sur-encode les scènes simples.
- **Formule de bitrate** :
  ```
  R_target = (W × H × FPS × BPP_base / 1000) × C
  ```
  Avec :
  - `BPP_base = 0.045` (bits par pixel de référence HEVC)
  - `C` = coefficient de complexité ∈ [0.75, 1.35], mappé linéairement depuis l'écart-type normalisé des tailles de frames
- **Garde-fous** :
  - Ne jamais dépasser 75% du bitrate original
  - Plancher qualité : 800 kbps minimum
  - `maxrate = target × 1.4`
  - `bufsize = target × 2.5`
- **Niveaux de complexité** :
  | Écart-type | Coefficient C | Description |
  |------------|---------------|-------------|
  | ≤ 0.15 | 0.75 | Statique (dialogues/interviews) |
  | 0.15–0.35 | interpolé | Standard (film typique) |
  | ≥ 0.35 | 1.35 | Complexe (action/grain/pluie) |
- **Impact** :
  - Compatible avec le skip intelligent et le passthrough
  - Log enrichi avec coefficient C et description du contenu
  - Tests Bats : 22 tests dans `test_film_adaptive.bats`

### 2026-01-03

#### Refactorisation Quick Wins et Structurelle
- **Quoi** : Factorisation de code dupliqué et suppression de code mort.
- **Où** :
  - `lib/utils.sh` : ajout `format_duration_seconds()` et `format_duration_compact()`
  - `lib/finalize.sh` : remplacement de 5 calculs de durée inline + 5 appels stat par les helpers
  - `lib/vmaf.sh` : remplacement de 1 appel stat par `get_file_size_bytes()`
  - `lib/transcode_video.sh` : suppression de `_build_encoder_ffmpeg_args()` (85 lignes de code mort, jamais appelé), fusion des deux branches if/else dans `_run_ffmpeg_encode()` (-14 lignes)
  - `tests/test_utils.bats` : 13 tests unitaires pour les nouvelles fonctions format_duration_*
- **Pourquoi** : 
  - Réduire la duplication améliore la maintenabilité
  - Le code mort crée de la confusion et du bruit
  - Les helpers testables sont plus fiables
- **Impact** :
  - ~100 lignes supprimées/factorisées
  - Aucun changement de comportement
  - Tests ajoutés pour les nouvelles fonctions

### 2026-01-09

#### Outil : génération de samples FFmpeg (edge cases)
- **Quoi** : Ajout d'un script pour générer des médias courts et reproductibles (VFR, 10-bit, multiaudio, sous-titres, metadata rotate, dimensions impaires, etc.).
- **Où** :
  - `tools/generate_ffmpeg_samples.sh`
  - `docs/SAMPLES.md`
  - `docs/DOCS.md` (lien ajouté)
  - `.gitignore` (ignore `samples/_generated/`)
- **Pourquoi** : Faciliter les tests manuels / debugging sur des cas "edge" sans dépendre de fichiers réels.
- **Impact** : Aucun impact sur NAScode; artefacts générés ignorés par git.
