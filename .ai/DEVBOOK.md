# DEVBOOK

Ce document sert de **mémoire durable** du projet : décisions, conventions, changements notables.

Objectifs :
- Faciliter les reprises de contexte (humains et agents).
- Garder une trace des évolutions qui impactent le comportement, l'UX CLI, les tests ou l'architecture.

## Format des entrées

- Une entrée par date au format `YYYY-MM-DD`.
- Décrire : **quoi** (résumé), **où** (fichiers), **pourquoi**, et **impact** (tests/doc/risques) si applicable.

## Journal

### 2026-03-10

#### Fix segfault x265 4.x avec -tune fastdecode (régression Windows)

- **Quoi** : correction d'un crash `Segmentation fault` (exit 139) lors de l'encodage HEVC en mode `serie`.
- **Où** :
  - `lib/config.sh` : `FILM_TUNE_FASTDECODE=false` (était `true`) en mode `serie`
  - `lib/transcode_video.sh` : valeur fallback `:-false` dans `_get_tune_option()` (était `:-true`)
  - `lib/codec_profiles.sh` : `build_tune_option()` respecte `FILM_TUNE_FASTDECODE` au lieu de hardcoder `-tune fastdecode`
  - `tests/test_codec_profiles.bats` : tests mis à jour (2 remplacés, 1 nouveau)
- **Pourquoi** :
  - **Bug x265 4.1** (Windows/MSYS2, ffmpeg 8.0.1) : `-tune fastdecode` active implicitement `dhdr10-info`, qui tente d'ouvrir un fichier tone-map inexistant → segfault immédiat après initialisation
  - Comportement absent sur x265 3.x (ancien PC) — régression liée au changement d'environnement
  - Le log ffmpeg s'arrête à `tools: lslices=6 dhdr10-info` sans encoder aucune frame
- **Solution** : désactiver `-tune fastdecode` par défaut. L'option peut être réactivée manuellement via `FILM_TUNE_FASTDECODE=true` si la version x265 utilisée ne présente pas ce bug.
- **Impact** :
  - Mode `serie` : plus de segfault sur x265 4.x Windows
  - Qualité/taille inchangées (l'option n'affecte que le décodage sur appareils anciens)
  - 72 tests passent, 0 régression

### 2026-01-17

#### Fix parsing SI/TI pour le mode adaptatif

- **Quoi** : correction critique du parsing des valeurs SI (Spatial Information) et TI (Temporal Information) dans l'analyse de complexité vidéo.
- **Où** :
  - `lib/complexity.sh` : réécriture de `_compute_siti()` avec parsing awk robuste
  - `tests/test_adaptatif.bats` : +15 tests couvrant parsing, normalisation, agrégation, orchestration et e2e
  - `.gitignore` : ajout de `Converted_Heavier/`
- **Pourquoi** :
  - **Bug critique** : tous les coefficients de complexité étaient ~1.13 quelle que soit la vidéo
  - **Cause racine** : le regex `grep -oP 'SI:\s*\K[0-9.]+'` ne correspondait pas au format réel de FFmpeg qui produit `Spatial Information:\nAverage: X`
  - **Aggravant** : FFmpeg produit DEUX blocs "SITI Summary" (le premier avec `nan`, le second avec les vraies valeurs) — le code prenait le premier (nan) → fallback 50|25 → C constant ~1.13
- **Solution** :
  - Utilisation de `awk` pour extraire la DERNIÈRE occurrence de `Average:` après chaque section
  - Parsing cross-platform (compatible Git Bash Windows, macOS, Linux)
- **Impact** :
  - Mode adaptatif : coefficients de complexité désormais corrects (variation 0.8–1.4 selon contenu)
  - Tests : 853 tests passent (+15 nouveaux tests de régression)
  - Pas de changement d'interface CLI ou de comportement utilisateur visible

### 2026-01-16

#### Documentation multilingue (traduction anglaise complète)

- **Quoi** : traduction de toute la documentation en anglais.
- **Où** :
  - `docs/en/` (nouveau dossier) : traductions complètes de tous les guides.
    - `DOCS.md` : index de la documentation.
    - `USAGE.md` : guide d'utilisation.
    - `CONFIG.md` : configuration avancée.
    - `ARCHITECTURE.md` : architecture du projet.
    - `SMART_CODEC.md` : logique smart codec.
    - `TROUBLESHOOTING.md` : dépannage.
    - `ADAPTATIF.md` : mode adaptatif.
    - `ADDING_NEW_CODEC.md` : guide ajout codec.
    - `CHANGELOG.md` : historique des versions.
    - `SAMPLES.md` : génération de samples FFmpeg.
  - `README.en.md` (nouveau) : version anglaise complète du README.
  - `README.md` : ajout section i18n avec exemples `--lang`.
- **Pourquoi** :
  - Rendre le projet accessible à la communauté anglophone.
  - Compléter l'infrastructure i18n avec de la documentation traduite.
- **Impact** :
  - 10 nouveaux fichiers de documentation anglaise.
  - README français enrichi avec section internationalisation.
  - Liens vers docs/en/ dans README.en.md.

#### Internationalisation (i18n) — Infrastructure multilingue

- **Quoi** : ajout du support multilingue au script, avec français (par défaut) et anglais.
- **Où** :
  - `lib/i18n.sh` (nouveau) : module de chargement des locales, fonction `msg()` avec indirection Bash.
  - `locale/fr.sh` (nouveau) : ~100 clés de messages en français (source de vérité).
  - `locale/en.sh` (nouveau) : traductions anglaises.
  - `lib/args.sh` : ajout de l'option `--lang fr|en` + migration des messages vers `msg()`.
  - `lib/exports.sh` : export des fonctions `msg`, `_i18n_load` et variable `LANG_UI` pour sous-shells.
  - `nascode` : chargement de `i18n.sh` en premier (avant tout message utilisateur).
  - Modules migrés : `lib/system.sh`, `lib/queue.sh`, `lib/lock.sh`, `lib/index.sh`, `lib/processing.sh`, `lib/conversion.sh`, `lib/finalize.sh`, `lib/config.sh`, `lib/off_peak.sh`, `lib/vmaf.sh`, `lib/transcode_video.sh`, `lib/ffmpeg_pipeline.sh`, `lib/conversion_prep.sh`.
- **Pourquoi** :
  - Rendre le script accessible aux utilisateurs anglophones.
  - Préserver le texte français soigneusement rédigé comme source de vérité.
  - Permettre l'ajout futur d'autres langues (structure extensible).
- **Architecture** :
  - Les messages sont des variables `MSG_*` définies dans les fichiers `locale/*.sh`.
  - `msg "MSG_KEY" [args...]` utilise `printf` avec les placeholders `%s`, `%d`.
  - Fallback automatique vers français si locale demandée absente.
  - Variable d'environnement `NASCODE_LANG` ou option CLI `--lang`.
- **Impact** :
  - UX : nouvelle option `--lang fr|en` dans l'aide.
  - Rétrocompatibilité : totale (français par défaut, comportement inchangé).
  - Documentation : à compléter (section i18n dans README).
- **Prochaines étapes** :
  - Traduction de la documentation (README, docs/).
  - Vérification exhaustive des messages restants non migrés.

### 2026-01-15

#### Gestion HFR (High Frame Rate) avec options --limit-fps / --no-limit-fps

- **Quoi** : ajout de la gestion du contenu HFR (>30 fps) avec deux stratégies :
  1. **Limitation FPS** : réduction à 29.97 fps (mode `serie` par défaut)
  2. **Majoration bitrate** : bitrate × (fps/30) pour préserver la fluidité (modes `film`/`adaptatif`)
- **Où** :
  - `lib/constants.sh` : nouvelles constantes `HFR_THRESHOLD_FPS`, `LIMIT_FPS_TARGET`
  - `lib/args.sh` : options CLI `--limit-fps` et `--no-limit-fps`
  - `lib/config.sh` : `LIMIT_FPS` par défaut selon le mode (true pour serie, false pour film/adaptatif)
  - `lib/video_params.sh` : helpers HFR (`_get_video_fps`, `_is_hfr`, `_compute_hfr_bitrate_factor`, `_apply_hfr_bitrate_adjustment`, `_build_fps_limit_filter`) + intégration dans `compute_video_params` et `compute_video_params_adaptive`
  - `lib/vmaf.sh` : skip VMAF si `FPS_WAS_LIMITED=true` (comparaison frame-à-frame impossible)
  - `lib/exports.sh` : exports des nouvelles fonctions et variables
  - `tests/test_hfr.bats` : 26 tests unitaires
  - `README.md` : documentation de l'option
- **Pourquoi** : 
  - Mode `serie` : optimisation taille (les séries à 60 fps sont rares et la réduction à 30 fps économise ~50% de bitrate)
  - Modes `film`/`adaptatif` : préserver la qualité HFR pour le sport/gaming, avec bitrate ajusté automatiquement
- **Comportement** :
  - Message UI : `📽️ FPS limité (59.94 → 29.97 fps)` ou `📽️ HFR détecté (59.94 fps) → bitrate ajusté ×2.0`
  - VMAF : ignoré avec warning si FPS modifié
- **Impact** :
  - Tests : 722 tests passent (+26 nouveaux)
  - UX : comportement par défaut différent selon le mode
  - Compatibilité : 100% rétrocompatible (comportement inchangé pour contenu ≤30 fps)

#### Renommage mode `film-adaptive` → `adaptatif`

- **Quoi** : renommage du mode de conversion `-m film-adaptive` en `-m adaptatif` (francisation du nom).
- **Où** :
  - CLI : `lib/args.sh`, `lib/config.sh` (case dans `set_conversion_mode_parameters`)
  - Modules : `lib/complexity.sh`, `lib/constants.sh`, `lib/conversion.sh`, `lib/adaptive_mode.sh`, `lib/exports.sh`, `lib/skip_decision.sh`, `lib/transcode_video.sh`, `lib/ui.sh`, `lib/video_params.sh`
  - Documentation : `docs/ADAPTATIF.md` (anciennement `FILM_ADAPTIVE.md`), `docs/ARCHITECTURE.md`, `docs/CHANGELOG.md`, `docs/CONFIG.md`, `docs/SMART_CODEC.md`, `README.md`
  - Tests : `tests/test_adaptatif.bats` (anciennement `test_film_adaptive.bats`), `tests/test_args.bats`, `tests/test_encoding_subfunctions.bats`
  - Contexte agent : `.ai/DEVBOOK.md`, `.ai/handoff.md`, `.ai/TODO.md`
- **Pourquoi** : harmonisation avec la convention de nommage française du projet.
- **Impact** :
  - **Breaking change CLI** : les scripts utilisant `-m film-adaptive` doivent utiliser `-m adaptatif`.
  - Tests : tous les 696 tests passent (0 régression).
  - Documentation : mise à jour complète.

#### Fusion TODO détection de grain

- **Quoi** : contenu de `docs/TODO_GRAIN_DETECTION.md` fusionné dans `.ai/TODO.md`, fichier original supprimé.
- **Où** : `.ai/TODO.md` (nouvelle section "Détection de grain pour mode adaptatif").
- **Pourquoi** : centraliser tous les TODOs dans un seul fichier.

#### Notification Discord : mise à jour de progression avec ETA et vitesse

- **Quoi** : ajout d'une notification Discord envoyée quelques secondes après le début d'une conversion, affichant le pourcentage, la vitesse (x1.25) et l'ETA estimée.
- **Où** :
  - `lib/constants.sh` : nouvelle constante `DISCORD_PROGRESS_UPDATE_DELAY` (défaut: 15s, configurable via env).
  - `lib/notify_events.sh` : nouvel événement `file_progress_update` avec fonction `notify_event_file_progress_update()`.
  - `lib/notify_format.sh` : fonction de formatage `_notify_format_event_file_progress_update()`.
  - `lib/utils.sh` : modification du script AWK `AWK_FFMPEG_PROGRESS_SCRIPT` pour écrire un fichier marqueur avec les métriques (percent, speed, eta) après le délai configuré.
  - `lib/ffmpeg_pipeline.sh` : 3 nouvelles fonctions helper (`_create_progress_marker_file`, `_start_progress_watcher`, `_stop_progress_watcher`) ; intégration dans `_execute_ffmpeg_pipeline` pour lancer le watcher en arrière-plan sur les modes crf/twopass.
  - `lib/transcode_video.sh` : passage des variables `PROGRESS_MARKER_FILE` et `PROGRESS_MARKER_DELAY` au script AWK.
  - `lib/exports.sh` : exports conditionnels des nouvelles fonctions et variable.
- **Pourquoi** : permettre un retour rapide sur Discord avec l'ETA estimée et la vitesse réelle de conversion, une fois que FFmpeg a stabilisé son rythme.
- **Comportement** :
  - Notification envoyée uniquement si : durée vidéo > (délai + 30s), mode crf ou twopass (pas passthrough), webhook Discord configuré.
  - Format : `[X/Y] 📊 filename | 5.2% | x1.25 | ETA: 01:23:45`
  - Le watcher est automatiquement nettoyé en fin de conversion (succès ou erreur).
- **Impact** :
  - Tests : aucune régression (695/696 tests passent, 1 skip attendu).
  - Config : nouvelle variable env `DISCORD_PROGRESS_UPDATE_DELAY` (défaut 15s).
  - UX : notification supplémentaire optionnelle sur Discord.

#### Audit complet du codebase (Phases A, B, C)

- **Quoi** : audit de professionnalisation et robustesse du codebase complet, en 3 phases :
  - **Phase A** : Documentation `set -euo pipefail` (38 modules), tests equiv-quality cap, tests helpers `_clamp_*`/`_min3`, refactorisation test_helper.bash, centralisation `_translate_bitrate_by_efficiency`.
  - **Phase B** : Analyse algorithmique de 7 modules clés (skip_decision, audio_decision, conversion, adaptive_mode, complexity, queue, processing).
  - **Phase C** : Audit des notifications Discord (notify_discord, notify_events, notify_format).
- **Où** :
  - `lib/codec_profiles.sh` : ajout de `_translate_bitrate_by_efficiency()` (helper générique centralisé).
  - `lib/audio_decision.sh` : refactorisation de `translate_audio_bitrate_kbps_between_codecs()` pour déléguer au helper centralisé.
  - `lib/utils.sh` : suppression de la fonction dupliquée, ajout de protection double-load (`_UTILS_SH_LOADED`).
  - `lib/exports.sh` : export de `_translate_bitrate_by_efficiency`.
  - `tests/test_codec_profiles.bats` : 9 tests pour le helper de traduction (H.264→HEVC, HEVC→AV1, same eff, invalid, fallback).
- **Pourquoi** : éliminer la duplication de code entre audio et vidéo pour la traduction de bitrate, améliorer la couverture de tests, valider la qualité industrielle du code existant.
- **Résultats de l'audit** :
  - **skip_decision.sh** : ⭐⭐⭐⭐⭐ — Logique claire, robustesse excellente, aucune action.
  - **audio_decision.sh** : ⭐⭐⭐⭐⭐ — 618 lignes bien structurées, anti-upscale, traduction equiv-quality.
  - **conversion.sh** : ⭐⭐⭐⭐⭐ — Orchestration en 8 étapes numérotées, modularité exemplaire.
  - **adaptive_mode.sh + complexity.sh** : ⭐⭐⭐⭐⭐ — Multi-sampling sophistiqué, calibration documentée.
  - **queue.sh + processing.sh** : ⭐⭐⭐⭐⭐ — FIFO industriel, compteurs atomiques, reaping propre.
  - **notify_discord.sh** : ⭐⭐⭐⭐⭐ — Sécurité webhook, best-effort, anti-spam tests.
  - **notify_events.sh** : ⭐⭐⭐⭐⭐ — Dispatcher propre, anti-doublon.
  - **notify_format.sh** : ⭐⭐⭐⭐⭐ — Markdown riche, helpers robustes, queue preview AWK.
- **Impact** :
  - Tests : 9+ tests ajoutés, tous passent (700+ au total).
  - Maintenabilité : code mieux factorisé, zéro duplication pour la traduction de bitrate.
  - Documentation : phases B+C n'ont identifié aucun bug, seulement des améliorations documentaires futures.
- **Phases restantes** (voir `.ai/TODO.md` section "Phases Refactor/Audit") :
  - ~~**Phase D**~~ : ✅ Terminée — Documentation (CONFIG.md enrichi, SMART_CODEC.md, CHANGELOG v2.8, ARCHITECTURE.md)
  - ~~**Phase E**~~ : ✅ Terminée — Extraction constantes vers `lib/constants.sh`
  - ~~**Phase F**~~ : ✅ Évaluée — Refactorisation structurelle non nécessaire (code déjà bien structuré, associative arrays incompatibles avec exports parallèles)

#### Phase D : Documentation

- **Quoi** : mise à jour de toute la documentation pour refléter les changements v2.8.
- **Où** :
  - `docs/CONFIG.md` : nouvelle section "Constantes centralisées" avec tableau complet des 17 constantes (ADAPTIVE_*, AUDIO_*, DISCORD_*) et exemples d'override.
  - `docs/SMART_CODEC.md` : enrichissement de la section "Hiérarchie (efficacité)" audio avec les rangs numériques, ajout de la section "Traduction des bitrates par efficacité".
  - `docs/CHANGELOG.md` : entrée v2.8 complète (6 points majeurs).
  - `docs/ARCHITECTURE.md` : ajout de la catégorie "Constantes & fondations" avec `lib/constants.sh` et `lib/env.sh`.
  - `docs/DOCS.md` : ajout du lien vers ARCHITECTURE.md dans les guides.
  - `README.md` : ajout du lien vers CONFIG.md dans la section Documentation.
  - `.ai/TODO.md` : nettoyage des sections terminées (Audio, UI, Phases E/F).
- **Pourquoi** : maintenir la documentation en phase avec le code, faciliter l'onboarding des contributeurs.
- **Impact** : documentation uniquement, aucun changement de code.

### 2026-01-14 (suite)

#### Phase E : Création de lib/constants.sh

- **Quoi** : centralisation des "magic numbers" et constantes configurables dans un module dédié.
- **Où** :
  - `lib/constants.sh` (nouveau) : 12 constantes ADAPTIVE_*, AUDIO_CODEC_EFFICIENT_THRESHOLD, 4 constantes DISCORD_*
  - `lib/complexity.sh` : remplacé les définitions par des fallbacks compacts (`: "${VAR:=default}"`)
  - `lib/audio_decision.sh` : utilise la constante centralisée AUDIO_CODEC_EFFICIENT_THRESHOLD
  - `lib/notify_discord.sh` : utilise les constantes DISCORD_* pour timeout/retries
  - `lib/exports.sh` : ajout exports pour DISCORD_*, AUDIO_CODEC_EFFICIENT_THRESHOLD
  - `nascode` : `constants.sh` chargé en premier dans la chaîne de modules
- **Pourquoi** : 
  - Éviter la dispersion des valeurs magiques dans le code
  - Permettre l'override via variables d'environnement (`ADAPTIVE_BPP_BASE=0.04 bash nascode`)
  - Faciliter la documentation (toutes les constantes au même endroit)
- **Impact** :
  - Tests : tous passent (695/695)
  - Rétrocompatibilité : totale (fallbacks dans les modules si constants.sh absent)
  - Documentation : les constantes sont maintenant faciles à documenter dans CONFIG.md

#### Phase F : Évaluation de la refactorisation structurelle

- **Quoi** : analyse de deux refactorisations proposées.
- **Décisions** :
  1. `_get_smart_audio_decision()` : **non refactorisée** — déjà bien structurée (~290 lignes avec blocs logiques clairs, closure interne `_emit_audio_decision`)
  2. Globals → Associative arrays : **reportée** — les associative arrays ne peuvent pas être exportés vers des sous-shells (incompatible avec `convert_file` en parallèle)
- **Pourquoi** : coût/bénéfice défavorable, le code actuel fonctionne très bien.
- **Impact** : aucun changement de code, documentation mise à jour dans TODO.md.

### 2026-01-14

#### Audit clean code : documentation et tests

- **Quoi** : implémentation des recommandations d'un audit de code complet (maintenabilité, robustesse, documentation).
- **Où** :
  - Tous les 38 modules `lib/*.sh` : ajout d'en-têtes expliquant pourquoi `set -euo pipefail` n'est pas utilisé localement.
  - `lib/config.sh` : documentation enrichie du verrouillage equiv-quality en mode adaptatif.
  - `tests/test_transcode_video.bats` : 5 nouveaux tests pour `VIDEO_EQUIV_QUALITY_CAP`.
  - `tests/test_audio_translate_equiv_quality.bats` : 10 nouveaux tests pour `_clamp_min`, `_clamp_max`, `_min3`.
  - `tests/test_helper.bash` : refactorisation en API unifiée `load_modules()` avec modes (`base`, `base_fast`, `minimal`, `minimal_fast`).
- **Pourquoi** : améliorer la maintenabilité, documenter les choix d'architecture, augmenter la couverture de tests des fonctions utilitaires critiques.
- **Impact** :
  - Tests : 15 nouveaux tests ajoutés (tous passent).
  - Documentation : clarification du comportement `set -euo pipefail` pour les contributeurs.
  - Compatibilité : rétrocompatibilité totale via wrappers `load_base_modules()`, `load_minimal()`, etc.

#### UX : fin de tâches en mode limite/random (n < limite)
- **Quoi** : évite l’affichage non logique “Tous les fichiers restants sont déjà optimisés.” quand le dossier source contient moins de fichiers que la limite (ex: 9 fichiers avec limite implicite 10).
- **Où** : `lib/processing.sh`.
- **Pourquoi** : la comparaison se faisait contre `LIMIT_FILES` brut, alors que la limite effective doit être `min(LIMIT_FILES, total disponible)`.
- **Impact** : UX uniquement (message de fin plus juste) ; aucune modification de conversion.

#### Suffixe : format simplifié (Option A)
- **Quoi** : simplifie le suffixe de sortie pour s’aligner sur des conventions courantes (suppression des valeurs CRF/bitrate/preset).
- **Format** : `_<codec>_<height>p[_<AUDIO>][_sample]` (audio en majuscules : `AAC`, `AC3`, `OPUS`, etc.).
- **Où** : `lib/video_params.sh` (suffixe effectif), `lib/config.sh` (preview), `lib/system.sh` (hint interactif).
- **Pourquoi** : éviter un suffixe trop verbeux/instable et réduire le bruit dans les noms de fichiers.
- **Tests** : mise à jour des assertions suffixe dans plusieurs suites Bats (dont `tests/test_transcode_video.bats`, `tests/test_audio_codec.bats`, `tests/test_config.bats`).

#### Discord : titre “Exécution” en header Markdown
- **Quoi** : le titre “Exécution” du message `run_started` passe de texte en gras à un header Markdown (`##`) pour être visuellement plus grand dans Discord.
- **Où** : `lib/notify_format.sh`.
- **Pourquoi** : améliorer la hiérarchie visuelle du message d’intro (lisible sur mobile).
- **Impact** : UX notifications uniquement (aucun impact si notifs Discord désactivées).

### 2026-01-13

#### Release : préparation v2.7 (changelog + docs)
- **Quoi** : ajout d’une entrée `v2.7` au changelog + doc index enrichie avec les commandes dev (tests/lint).
- **Où** : `docs/CHANGELOG.md`, `docs/DOCS.md`.
- **Pourquoi** : publier une release cohérente (notes lisibles + chemins doc à jour).
- **Impact** : documentation uniquement (aucun changement de comportement).

#### Docs : mini-spéc “traduction qualité équivalente” (audio)
- **Quoi** : ajout d’une mini-spéc dans le backlog pour cadrer un futur helper de traduction de bitrate audio “qualité équivalente” + stratégie d’activation par mode + invariants + stratégie de tests.
- **Où** : `.ai/TODO.md`.
- **Pourquoi** : aligner l’approche audio sur la logique vidéo existante (sans activer globalement par défaut) et rendre l’implémentation future plus sûre via des tests ciblés.
- **Impact** : doc/backlog uniquement (aucun changement de comportement).

#### Notifications Discord (démarrage / heures creuses / fin)
- **Quoi** : ajout d’un module de notifications externes pour envoyer des messages Discord en Markdown (démarrage avec paramètres actifs, pause/reprise en heures creuses, fin avec résumé).
- **Où** : `lib/notify.sh` (nouveau), `nascode` (chargement + hook démarrage), `lib/off_peak.sh` (hooks pause/reprise), `lib/lock.sh` (hook fin via `cleanup()`), `tests/test_notify.bats`.
- **Pourquoi** : disposer d’un canal de suivi “hands-off” pour les runs longs et faciliter l’extension à d’autres événements sans surcharger les modules existants.
- **Impact** : aucun impact si `NASCODE_DISCORD_WEBHOOK_URL` n’est pas défini ; envoi best-effort (aucune erreur de notif ne doit arrêter NAScode). Secret webhook non versionné (variable d’env ; `.env` local ignoré à sourcer manuellement).

#### Notifications Discord : debug + robustesse payload + format
- **Quoi** :
  - ajout d’un mode debug opt-in (`NASCODE_DISCORD_NOTIFY_DEBUG=true`) qui loggue le code HTTP (et un extrait de réponse en cas d’erreur) dans `logs/discord_notify_<timestamp>.log`.
  - correctif “400 invalid JSON” : envoi du JSON via fichier temporaire + `curl --data-binary @file`.
  - amélioration UX : vrais retours à la ligne et “paramètres actifs” en liste Markdown ; message de fin avec heure de fin, exit code affiché seulement en cas d’erreur.
- **Où** : `lib/notify.sh`, tests dans `tests/test_notify.bats`.
- **Pourquoi** : diagnostiquer les erreurs Discord sans exposer le webhook, fiabiliser l’envoi sur Git Bash/Windows et améliorer la lisibilité des messages.

#### Tests : anti-spam notifications Discord
- **Quoi** : désactivation par défaut des notifications Discord quand NAScode est exécuté sous Bats, avec un opt-in explicite pour les tests unitaires.
- **Où** : `lib/notify.sh` (garde-fou Bats), `tests/test_notify.bats` (opt-in `NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS=true`).
- **Pourquoi** : éviter de spammer un vrai webhook via l’environnement utilisateur pendant les tests E2E.
- **Impact** : aucun impact en run normal ; les tests notifs continuent de valider le payload via `curl` mock.

#### Notifications Discord : messages “mobiles” + événements détaillés
- **Quoi** : refonte des notifications Discord pour être plus lisibles sur petit écran et refléter le cycle de vie du run.
  - Aperçu de la queue au démarrage (format `[i/N]`, troncature déterministe)
  - Messages par fichier : début + fin (durée, tailles `avant → après`)
  - Statut transferts : en attente puis terminés (si applicable)
  - VMAF (si activé) : annonce globale + résultat par fichier (note/qualité) + fin globale
  - Fin : résumé (si dispo) puis message final avec horodatage
- **Où** : `lib/notify.sh` (entrypoint), `lib/notify_discord.sh`, `lib/notify_format.sh`, `lib/notify_events.sh`, hooks dans `nascode`, `lib/conversion_prep.sh`, `lib/finalize.sh`, `lib/processing.sh`, `lib/transfer.sh`, `lib/vmaf.sh` ; tests `tests/test_notify.bats`.
- **Pourquoi** : réduire le bruit, améliorer le suivi “hands-off”, et aligner les messages Discord sur les lignes clés déjà affichées dans le terminal.
- **Impact** : changement UX uniquement quand les notifs Discord sont activées ; envoi best-effort inchangé ; documentation mise à jour (README + docs).

#### Tests E2E : isolement des logs + compatibilité "Heavier"
- **Quoi** : les tests E2E/régression forcent désormais `LOG_DIR="$WORKDIR/logs"` pour isoler index/logs par test et éviter de polluer le repo ; le test stream mapping accepte que la sortie soit redirigée en dossier `_Heavier` si le fichier final est plus lourd / gain insuffisant.
- **Où** : `lib/logging.sh` (LOG_DIR override possible), `tests/test_e2e_full_workflow.bats`, `tests/test_e2e_stream_mapping.bats`, `tests/test_regression_non_interactive.bats`, `tests/test_regression_smoke_dryrun.bats`.
- **Pourquoi** : fiabiliser les assertions E2E (artefacts logs) et éviter des flakes liés à l’index persistant ; rendre le test sous-titres robuste face au mécanisme “Heavier”.
- **Impact** : aucun en run normal (LOG_DIR par défaut inchangé) ; améliore la stabilité des tests.

#### Fix : éviter les blocages quand la queue ne produit aucun fichier traitable
- **Quoi** : sécurise le mode FIFO/limite pour qu’un run ne puisse plus “attendre indéfiniment” si aucun fichier n’est effectivement traité (entrée vide, fichier introuvable, ou échec très tôt dans `convert_file`).
- **Où** :
  - `lib/conversion.sh` : `convert_file()` marque toujours un fichier comme “traité” en mode FIFO (via `increment_processed_count`) même en cas de skip/erreur précoce.
  - `lib/processing.sh` : ignore les entrées vides lues depuis la queue/FIFO.
  - `lib/queue.sh` : `_validate_queue_not_empty()` détecte le format invalide (pas de séparateurs NUL) et échoue explicitement.
  - `nascode` : sortie explicite si `SOURCE` matche `EXCLUDES`.
- **Pourquoi** : empêcher les deadlocks FIFO (writer qui attend `processed>=target`) et rendre les cas “0 fichier” explicites.
- **Tests** : `tests/test_conversion.bats`, `tests/test_queue.bats`, ajustement non-régression `tests/test_adaptatif.bats` (fichier factice créé).

#### Dev : cible Makefile `make lint` (ShellCheck)
- **Quoi** : ajout d’une cible `lint` pour exécuter ShellCheck sur les scripts Bash du repo (avec message d’aide si ShellCheck n’est pas installé).
- **Où** : `Makefile`.
- **Pourquoi** : standardiser le lint local et réduire les régressions Bash.
- **Notes Windows/MSYS2** :
  - ShellCheck peut échouer avec `commitBuffer: invalid argument (invalid character)` quand il tente d’afficher des extraits de code contenant des caractères non-ASCII (accents) selon la console/locale.
  - Le lint utilise désormais le format `gcc` (pas d’extraits) + une sévérité par défaut `error` pour être exploitable sur une base legacy (opt-in strict via `make lint SHELLCHECK_SEVERITY=warning`).

### 2026-01-13

#### Fix : le mode `adaptatif` applique réellement les budgets à l'encodage (AV1 + HEVC/x265)
- **Quoi** : en mode `adaptatif`, les budgets calculés (`ADAPTIVE_TARGET_KBPS`, `ADAPTIVE_MAXRATE_KBPS`, `ADAPTIVE_BUFSIZE_KBPS`) sont maintenant effectivement utilisés par l'encodage.
- **Où** :
  - `lib/conversion.sh` : export explicite des `ADAPTIVE_*` après parsing des valeurs retournées par l'analyse.
  - Tests : `tests/test_adaptatif.bats`, `tests/test_encoding_subfunctions.bats`.
- **Pourquoi** : l'analyse était appelée via `$(...)` (subshell Bash), donc les `export` réalisés dans la fonction d'analyse ne remontaient pas au shell parent ; l'encodage retombait sur les paramètres "standard" (symptôme observé : cap SVT `mbr` trop haut vs le `bitrate cible`).
- **Impact** :
  - AV1/SVT-AV1 : le cap "capped CRF" (`mbr`) suit désormais bien le budget adaptatif (au lieu du budget standard 720p).
  - HEVC/x265 : le VBV (maxrate/bufsize) suit le budget adaptatif.
  - Tests Bats : ajout de non-régressions, exécution locale OK (filtres `test_adaptatif` et `test_encoding_subfunctions`).

#### Backlog (interne)
- **Quoi** : création d'une liste TODO structurée.
- **Où** : `.ai/TODO.md`.

### 2026-01-11

#### Refactorisation : split de conversion.sh en 4 modules
- **Quoi** : extraction de `conversion.sh` (958 lignes) en modules spécialisés pour améliorer la maintenabilité et la testabilité.
- **Où** :
  - `lib/skip_decision.sh` (206 lignes) : logique de décision skip/passthrough/full (`_determine_conversion_mode`, `should_skip_conversion*`), variables `CONVERSION_ACTION`, `EFFECTIVE_VIDEO_*`, `SKIP_THRESHOLD_*`.
  - `lib/conversion_prep.sh` (216 lignes) : préparation fichiers (`_prepare_file_paths`, `_check_output_exists`, `_get_temp_filename`, `_setup_temp_files_and_logs`, `_check_disk_space`, `_copy_to_temp_storage`).
  - `lib/adaptive_mode.sh` (146 lignes) : mode adaptatif (`_convert_run_adaptive_analysis_and_export`, `_convert_handle_adaptive_mode`).
  - `lib/ui.sh` (+327 lignes) : fonctions d'affichage conversion (`_get_counter_prefix`, `print_skip_message`, `print_conversion_required`, `print_conversion_not_required`, `print_conversion_info` + helpers).
  - `lib/counters.sh` (+13 lignes) : variables `CURRENT_FILE_NUMBER`, `LIMIT_DISPLAY_SLOT`.
  - `lib/conversion.sh` (178 lignes) : orchestration pure (`convert_file`, `_convert_get_full_metadata`).
  - `nascode` : ajout des sources pour les nouveaux modules.
- **Pourquoi** : conversion.sh était devenu trop long (958 lignes) avec des responsabilités mélangées (décision, préparation, UI, adaptatif). La séparation permet des tests unitaires ciblés et une meilleure lisibilité.
- **Impact** : aucun changement de comportement ; doc ARCHITECTURE.md mise à jour.

#### Fix : évite un arrêt silencieux (set -e) après préparation
- **Quoi** : sécurisation de l'affichage audio (retours “informatifs” non fatals) + sourcing du module audio manquant.
- **Où** : `nascode` (source `lib/audio_decision.sh`), `lib/ui.sh` (`print_conversion_info()` protège les helpers audio qui peuvent retourner `1`).
- **Pourquoi** : sous `set -euo pipefail`, un `return 1` “normal” dans un helper UI arrêtait le script et donnait l’impression d’un blocage.
- **Impact** : NAScode continue la conversion au lieu de quitter silencieusement ; pas de changement de paramètres d’encodage.

#### Vidéo : seuil de skip codec-aware + politique "no downgrade" (dont mode `adaptatif`)
- **Quoi** :
  - Traduction du seuil de skip dans l’espace du codec source quand celui-ci est **meilleur/plus efficace** (ex: AV1 vs cible HEVC), via les facteurs d’efficacité codec.
  - Politique par défaut : **ne jamais downgrade** le codec vidéo. Si une source AV1 est jugée “trop haut débit”, elle est ré-encodée **en AV1** pour plafonner le bitrate (sauf `--force-video`).
  - En mode `adaptatif`, les bitrates calculés (référence HEVC) sont désormais traduits vers le codec cible actif (ex: `--codec av1`).
- **Où** :
  - `lib/conversion.sh` : seuil codec-aware + sélection `EFFECTIVE_VIDEO_CODEC` et message explicite "Conversion requise" après analyse.
  - `lib/transcode_video.sh` : support d'un codec/encodeur effectif par fichier et traduction des budgets bitrate (standard + adaptatif).
  - `lib/codec_profiles.sh` : `translate_bitrate_kbps_between_codecs()` + overrides `CODEC_EFFICIENCY_*`.
  - Tests : `tests/test_conversion.bats`, `tests/test_conversion_mode.bats`.
- **Pourquoi** : éviter des skips trop agressifs sur codecs plus efficaces et empêcher la régression qualité liée à un downgrade codec implicite.
- **Impact** : change le comportement de skip sur sources AV1 quand la cible est HEVC (seuil plus strict) ; doc mise à jour (`README.md`, `docs/SMART_CODEC.md`).

#### Tests : stabilisation E2E interruption (Windows/MSYS2)
- **Quoi** : fiabilisation du test d'interruption en cours : sous Bash/MSYS2, un job lancé en arrière-plan peut ignorer `SIGINT`, donc le test passait parfois avec un exit code `0` au lieu de `130`.
- **Où** : `tests/test_regression_e2e.bats`.
- **Pourquoi** : rendre le test déterministe sur Windows (Git Bash/MSYS2).
- **Impact** : test E2E plus stable ; aucun changement de comportement runtime de NAScode.

#### Vidéo : cap "qualité équivalente" quand la source est moins efficace (mode standard)
- **Quoi** : en modes non adaptatifs, si la source est dans un codec moins efficace que le codec d’encodage effectif (ex: H.264 → HEVC) et que son bitrate est bas, plafonnement des budgets (target/maxrate/bufsize) à une valeur “qualité équivalente” via `translate_bitrate_kbps_between_codecs()`.
- **Où** : `lib/transcode_video.sh` (calcul budgets), `lib/conversion.sh` (expose codec/bitrate source au module d’encodage), tests dans `tests/test_encoding_subfunctions.bats`.
- **Pourquoi** : éviter d’augmenter inutilement le bitrate/surface disque lors d’un ré-encodage vers un codec plus efficace.
- **Impact** : paramètres d’encodage potentiellement plus bas sur sources H.264 bas débit ; logique de skip inchangée.

#### SVT-AV1 : plafonnement du bitrate en mode CRF (MBR)
- **Quoi** : en single-pass CRF avec `libsvtav1`, ajout du paramètre `mbr=` (Maximum BitRate) pour limiter le débit instantané et éviter des fichiers plus gros que la source sur du contenu très complexe.
- **Où** : `lib/transcode_video.sh` (construction `ENCODER_BASE_PARAMS` pour `libsvtav1`).
- **Pourquoi** : rendre le mode CRF plus prédictible côté taille quand la complexité explose.
- **Impact** : uniquement SVT-AV1 + CRF ; pas d’impact sur x265/two-pass.

### 2026-01-10

#### UX CLI : `--quiet` (warnings/erreurs uniquement) + centralisation des sorties
- **Quoi** : consolidation du mode `--quiet` pour garantir une sortie “warnings/erreurs only” (infos/succès/sections silencieux), et migration ciblée de sorties user-facing (`echo -e`) vers les helpers UI centralisés.
- **Où** :
  - `lib/ui.sh` : extension des guards quiet à des fonctions restantes (status, success_box, empty_state, indexation, summary, fins de phases).
  - `lib/off_peak.sh`, `lib/processing.sh` : attente heures creuses en `print_info`; interruptions en `print_warning`.
  - `lib/finalize.sh` : succès en `print_success` (silencieux), erreurs/warnings en `print_error`/`print_warning` (visibles même si `NO_PROGRESS=true`).
  - `lib/queue.sh`, `lib/system.sh`, `lib/transfer.sh`, `lib/lock.sh`, `lib/complexity.sh`, `lib/transcode_video.sh`, `lib/conversion.sh` : migration de messages user-facing vers helpers UI et suppression d’un cas bruité en quiet.
- **Pourquoi** : éviter les oublis (prints dispersés) et rendre `--quiet` prédictible.
- **Impact** :
  - UX : `--quiet` devient globalement cohérent.
  - Tests : `tests/test_args.bats` couvre `--quiet` (et reset `UI_QUIET`).
  - Doc : `docs/USAGE.md` mentionne `--quiet`.

#### Bitrate : profil adaptatif 480p/SD
- **Quoi** : ajout d’un profil adaptatif dédié aux sources SD (≤480p), en réduisant le bitrate cible (ex: 1080p→2070k vs 480p→~1035k) pour éviter les encodages trop “généreux” sur basse résolution.
- **Où** : `lib/config.sh` (constantes), `lib/video_params.sh` (priorité 480p avant 720p), `lib/exports.sh`.
- **Pourquoi** : mieux aligner taille/qualité sur la résolution source.

#### Audio : respecter le codec cible plus efficace que la source
- **Quoi** : si le codec cible est plus efficace que la source (ex: cible `opus` vs source `aac`), conversion forcée (corrige le cas où `-a opus` pouvait être ignoré sur source AAC).
- **Où** : `lib/audio_decision.sh`, tests dans `tests/test_regression_coverage.bats`.
- **Pourquoi** : respecter l’intention utilisateur et la logique “efficacité codec”.

#### Tests : assertions moins fragiles
- **Quoi** : ajout de helpers d’assertion Bats et remplacement d’assertions dépendantes du wording UI par des invariants (glob, détection de prompts, contrats de fonctions/export).
- **Où** : `tests/test_helper.bash` + ajustements dans plusieurs suites (args/lock/queue/e2e/regressions) et mise à jour `.ai/handoff.md`.
- **Pourquoi** : stabiliser la CI locale et réduire les faux positifs lors d’évolutions UX.

#### Docs : préciser la limite des vidéos portrait
- **Quoi** : précision documentaire sur le traitement/limite des vidéos portrait.
- **Où** : `README.md`.

#### UX : ajustement message d’erreur codec vidéo
- **Quoi** : message d’erreur “codec invalide” rendu plus générique (liste non exhaustive), pour éviter une doc/UX trompeuse si la liste évolue.
- **Où** : `lib/args.sh`.

### 2026-01-09

#### Audio : stéréo forcée en mode `serie` + centralisation mode-based (vidéo)
- **Quoi** : en mode `serie`, garantir une sortie stéréo (downmix) même pour les sources multicanal et même si elles auraient été copiées (premium/passthrough). En parallèle, calculer une fois les paramètres encodeur dépendants du mode.
- **Où** :
  - `lib/config.sh` : `AUDIO_FORCE_STEREO`, `ENCODER_MODE_PROFILE`, `ENCODER_MODE_PARAMS` + initialisation par mode
  - `lib/audio_decision.sh` : bypass décision “stéréo forcée” pour `channels>=6`
  - `lib/audio_params.sh` : layout cible `stereo` si `AUDIO_FORCE_STEREO=true`
  - `lib/transcode_video.sh` : utilisation de `ENCODER_MODE_PARAMS` et `FILM_KEYINT` centralisés
  - `lib/args.sh` : suppression de la règle film→two-pass dans le parsing (centralisé dans `set_conversion_mode_parameters`)
  - Tests : `tests/test_args.bats`, `tests/test_audio_codec.bats`
- **Pourquoi** : compatibilité maximale et taille maîtrisée en série ; éviter des décisions “mode-based” dispersées.
- **Impact** : changement de comportement en mode `serie` (5.1/7.1 → stéréo systématique). Mode `film` / `adaptatif` inchangé.
- **Doc** : `README.md`, `docs/SMART_CODEC.md`, `docs/CONFIG.md`.

#### UX : compteur mode limite 1-based
- **Quoi** : en mode limite (`-l`), le préfixe affiché sur la ligne “Démarrage du fichier” ne commence plus à `[0/N]` mais à `[1/N]` (slot en cours).
- **Où** : `lib/conversion.sh` (préfixe `_get_counter_prefix` via `LIMIT_DISPLAY_SLOT`).
- **Pourquoi** : éviter une impression de bug et rendre la progression plus intuitive.

#### UX : compteur mode limite robuste en parallèle
- **Quoi** : le slot `[X/N]` en mode limite est désormais réservé de façon **atomique** (mutex) via `increment_converted_count`, ce qui évite les slots dupliqués quand `PARALLEL_JOBS>1`.
- **Où** : `lib/conversion.sh`.
- **Pourquoi** : stabiliser l'UX et éviter les collisions de compteur en exécution concurrente.
- **Notes** : en mode `adaptatif`, le slot est réservé après l'analyse (pour éviter de "gâcher" des slots sur des skips post-analyse).

#### Refactor “clean code light” (sans changement UX/CLI)
- **Quoi** : refactor ciblé des fonctions longues audio/vidéo/VMAF, avec une construction de commandes FFmpeg plus sûre via tableaux d’arguments, et découpage de `_build_effective_suffix_for_dims()` en helpers internes.
- **Où** :
  - `lib/utils.sh` : ajout helper `_cmd_append_words()` (append contrôlé d’options multi-mots dans un tableau)
  - `lib/audio_decision.sh` / `lib/audio_params.sh` : normalisation centralisée des noms de codecs audio via `_normalize_audio_codec()`
  - `lib/transcode_video.sh` : construction cmd FFmpeg via `_cmd_append_words()`, extraction d’aides pipeline (release slot / affichage erreurs)
  - `lib/conversion.sh` : extraction helpers metadata/adaptive pour clarifier `convert_file()`
  - `lib/vmaf.sh` : déduplication de la commande FFmpeg, `-progress` conditionnel
  - `lib/video_params.sh` : découpage suffixe (`_build_effective_suffix_for_dims()`)
- **Pourquoi** : améliorer lisibilité/maintenabilité et réduire les risques de word-splitting implicite dans les commandes FFmpeg.
- **Impact** : aucun changement attendu côté utilisateur (formats et options inchangés).
- **Validation** : tests Bats ciblés OK (transcode_video / encoding_subfunctions / audio_codec / vmaf / regression_exports_contract).

#### Docs : tableau récapitulatif des critères de conversion
- **Quoi** : alignement du tableau sur le comportement réel (vidéo : le codec “supérieur” peut être ré-encodé si le bitrate dépasse le seuil ; audio : premium passthrough par défaut, ajout section multicanal et exemple E-AC3 mis à jour).
- **Où** : `docs/📋 Tableau récapitulatif - Critères de conversion.csv`
- **Pourquoi** : éviter les règles obsolètes/inexactes côté documentation et garder une “source de vérité” cohérente avec le code.

#### Outil : génération de samples FFmpeg (edge cases)
- **Quoi** : ajout d'un script pour générer des médias courts et reproductibles (VFR, 10-bit, multiaudio, sous-titres, metadata rotate, dimensions impaires, etc.).
- **Où** :
  - `tools/generate_ffmpeg_samples.sh`
  - `docs/SAMPLES.md`
  - `docs/DOCS.md` (lien ajouté)
  - `.gitignore` (ignore `samples/_generated/`)
- **Pourquoi** : faciliter les tests manuels / debugging sur des cas "edge" sans dépendre de fichiers réels.
- **Impact** : aucun impact sur NAScode; artefacts générés ignorés par git.

#### Samples : cas 7.1 (TrueHD/DTS) plus robustes
- **Quoi** : détection préventive du support 7.1 par les encodeurs FFmpeg (`truehd`, `dca`) + suppression d'artefacts invalides (0 octet / sans vidéo) quand `--force` n'est pas utilisé.
- **Où** : `tools/generate_ffmpeg_samples.sh`
- **Pourquoi** : sur certaines builds, les encodeurs refusent 7.1 (jusqu'à 5.1 seulement) ; éviter du bruit d'erreurs et empêcher qu'un ancien fichier audio-only soit réutilisé.
- **Impact** : `19_dts_7_1.mkv` / `21_truehd_7_1.mkv` peuvent être "skip" proprement ; pas de fichiers invalides laissés sur disque.

#### UI : prompt `.plexignore` harmonisé
- **Quoi** : l'invite de création du fichier `.plexignore` utilise désormais le même rendu que les autres questions (bloc `ask_question` + messages `print_success`/`print_info`).
- **Où** : `lib/system.sh` (`check_plexignore()`).
- **Pourquoi** : cohérence de l'UI interactive.

### 2026-01-08

#### Feature : `--no-lossless` (multi-canal)
- **Quoi** : ajout d'une option pour éviter le passthrough lossless/premium en audio, y compris en contexte multi-canal.
- **Où** :
  - `lib/args.sh`, `nascode` : parsing / câblage CLI
  - `lib/audio_decision.sh`, `lib/audio_params.sh` : décision smart audio, règles multi-canal
  - `lib/config.sh`, `lib/exports.sh` : config + exports
  - Tests : `tests/test_audio_codec.bats`, `tests/test_audio_multichannel.bats`
  - Docs : `docs/SMART_CODEC.md`, `docs/DOCS.md`, `README.md`, `docs/CHANGELOG.md`
- **Pourquoi** : permettre un mode “compatibilité / taille” où l'audio lossless n'est pas conservé, même si le fichier source est premium.

#### Refactor : extraction du moteur de décision audio
- **Quoi** : factorisation/clarification de la logique de décision smart audio.
- **Où** : `lib/audio_decision.sh`, `lib/audio_params.sh` (+ doc `docs/SMART_CODEC.md`).
- **Pourquoi** : rendre les règles plus lisibles, testables et faciles à faire évoluer.

#### Docs : changelog v2.6
- **Quoi** : mise à jour du changelog pour refléter les évolutions.
- **Où** : `docs/CHANGELOG.md`

### 2026-01-03

#### Refactorisation Quick Wins et Structurelle
- **Quoi** : factorisation de code dupliqué et suppression de code mort.
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

#### Feature : mode `adaptatif` (bitrate adaptatif par fichier)
- **Quoi** : Nouveau mode de conversion `-m adaptatif` qui analyse la complexité de chaque fichier et calcule un bitrate personnalisé.
- **Où** :
  - `lib/complexity.sh` : nouveau module — analyse statistique des frames (multi-échantillonnage à 25%, 50%, 75%)
  - `lib/config.sh` : constantes `ADAPTIVE_*`, ajout du mode `adaptatif`
  - `lib/video_params.sh` : intégration des paramètres adaptatifs dans `compute_video_params()`
  - `lib/transcode_video.sh` : utilisation des variables `ADAPTIVE_TARGET_KBPS`, `ADAPTIVE_MAXRATE_KBPS`
  - `lib/conversion.sh` : seuil de skip adaptatif pour le mode
  - `lib/exports.sh` : export des nouvelles variables
  - `tests/test_adaptatif.bats` : 22 tests unitaires couvrant le module
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
  - Tests Bats : 22 tests dans `test_adaptatif.bats`

#### Documentation : clarification de l’intention de `agent.md`
- **Quoi** : Clarification du rôle et des objectifs “à garder en tête” pour guider les contributions sans transformer le document en checklist exhaustive.
- **Où** :
  - `.ai/agent.md` : ajout des sections “Rôle” et “Objectifs”, et reformulation de l’introduction
- **Pourquoi** : Les listes d’actions vieillissent vite ; l’intention (contrats, invariants, robustesse, testabilité) aide à prendre de bonnes décisions quand le code grossit.
- **Impact** : Documentation interne plus explicite ; aucune modification de comportement du script.

