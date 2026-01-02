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
