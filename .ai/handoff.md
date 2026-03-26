# Handoff

## Session en cours (16–17/01/2026 - Internationalisation i18n + Documentation)

### 2026-01-17 — Docs : clarification du rôle et des objectifs (agent)

Branche : `feature/siti-progress-bar`

Contexte : le fichier `agent.md` servait surtout de liste de règles. Objectif : rendre plus explicite la logique derrière ces règles (posture, invariants, priorités), pour guider les refactors Bash et l’ajout de gros blocs de code.

Changements principaux :

- [.ai/agent.md](.ai/agent.md) : introduction reformulée + ajout des sections “Rôle” et “Objectifs (à garder en tête)” (fiabilité, maintenabilité, testabilité, doc utile).
- [.ai/DEVBOOK.md](.ai/DEVBOOK.md) : ajout d’une entrée “Documentation : clarification de l’intention de agent.md”.

Derniers prompts :

- "J'ai besoin que tu analyse le fichiers agent.md…"
- "Oui garde l'esprit actuel…"
- "ok commit et push puis tu merges dans main"

### 2026-01-17 — Docs EN : harmonisation terminologie (movies/savings, series mode)

Branche : `docs/en-terminology-harmonize`

Contexte : revue comparative FR→EN pour valider les termes utilisés selon le contexte du script, puis harmonisation **uniquement** côté documentation anglaise.

Changements principaux :

- [README.en.md](README.en.md) : uniformise "series mode `serie`" et conserve les exemples en "movies".
- [docs/en/USAGE.md](docs/en/USAGE.md) : exemples harmonisés vers "/path/to/movies" + libellé "series mode `serie`".
- [docs/en/SMART_CODEC.md](docs/en/SMART_CODEC.md) : remplace "Serie mode" par "Series mode (`serie`)".
- [docs/en/CONFIG.md](docs/en/CONFIG.md) : standardise "minimum savings" (au lieu de "minimum gain").
- [docs/en/TROUBLESHOOTING.md](docs/en/TROUBLESHOOTING.md) : remplace "unified session journal" par "unified session log".
- [docs/en/CHANGELOG.md](docs/en/CHANGELOG.md) : harmonise les occurrences restantes de "serie mode".

Derniers prompts :

- "Est ce que tu peux comparer les traductions anglaises de toute la documentation de mon projet depuis le français vers l'anglais ?"
- "Oui vasy harmonise. je prefere movies savings du coup"

### 2026-01-16 — i18n : complétion EN (terminal + notifs Discord)

Branche : `fix/i18n-en-discord`

Contexte : avec `--lang en`, certaines sorties restaient en français (UI terminal + notifs Discord). Objectif : supprimer les chaînes FR hardcodées et compléter les clés manquantes dans les locales.

Changements principaux :

- [lib/ui.sh](lib/ui.sh) : migration vers `msg()` des messages restants (indexation, “conversion requise”, raisons de skip, “%s fichier(s) à traiter”) + correctif d’affichage d’indexation (évite le rendu type “9 0 files indexed”).
- [lib/complexity.sh](lib/complexity.sh) : progression + libellés + descriptions de complexité via clés i18n.
- [lib/transcode_video.sh](lib/transcode_video.sh) : texte fixe de progression (“Traitement en cours”) via i18n.
- [lib/transfer.sh](lib/transfer.sh) : messages de transferts via i18n.
- [lib/summary.sh](lib/summary.sh) : libellés du résumé de fin via i18n.
- [lib/notify_format.sh](lib/notify_format.sh) : refonte majeure du markdown Discord pour utiliser `msg MSG_NOTIFY_*` (run_started, file_skipped, progress, VMAF, off-peak, script_exit, résumé).
- [lib/vmaf.sh](lib/vmaf.sh) : messages NA via i18n + labels de qualité via i18n ; suppression d’un doublon de fonction `_vmaf_quality_label()`.
- [locale/en.sh](locale/en.sh), [locale/fr.sh](locale/fr.sh) : ajout des clés manquantes (UI/complexity/summary/transfer/notify/VMAF).
- [tests/test_notify.bats](tests/test_notify.bats) : stabilise la langue (FR par défaut) et ajoute un test minimal sur le résumé en anglais.

Prochaines étapes :

- [ ] Lancer les tests : `bash run_tests.sh` (au moins `-f notify` puis complet).
- [ ] Smoke-run avec `--lang en` sur un petit sample pour confirmer terminal + Discord.

Derniers prompts :

- "Il reste des parties non traduites, également dans les notifs Discord"
- "Continue sans t'arreter"

### 2026-01-16 — i18n : cohérence FR/EN (termes + clé FFmpeg)

Branche : `fix/i18n-en-discord`

Contexte : revue comparative des locales FR/EN pour valider le vocabulaire anglais et la parité des clés.

Changements principaux :

- [locale/fr.sh](locale/fr.sh) : correction d’une ligne concaténée qui empêchait la définition de `MSG_FFMPEG_REMUX_ERROR` (utilisé dans `lib/ffmpeg_pipeline.sh`).
- [locale/en.sh](locale/en.sh) : micro-ajustements de libellés pour un anglais plus idiomatique (ex: “Environment check”, “Queue sort order”, “Files to process”).

Vérification : parité des clés `MSG_*` OK (352/352).

Dernier prompt :

- "Tu peux comparer les deux fichiers de langues en et fr…"
- "Oui vasy"

### 2026-01-16 — Discord : VMAF compact quand count=1

Branche : `fix/i18n-en-discord`

Contexte : quand VMAF ne porte que sur un seul fichier (ex: `--limit 1`), le message Discord de fin était trop verbeux (stats + “Worst files”).

Changements principaux :

- [lib/notify_format.sh](lib/notify_format.sh) : format compact pour `vmaf_completed` si `count=1` (score + qualité + fichier + durée), sans sections “Results” / “Worst files”.
- [locale/fr.sh](locale/fr.sh), [locale/en.sh](locale/en.sh) : ajout de `MSG_NOTIFY_FILE_LABEL`.
- [tests/test_notify.bats](tests/test_notify.bats) : test de régression du rendu compact.

### 2026-01-16 — i18n : Documentation multilingue (traduction anglaise)

Branche : `feature/i18n`

Contexte : Suite à l'infrastructure i18n, traduction complète de toute la documentation en anglais.

Changements principaux :

- **docs/en/** (nouveau dossier) : traductions complètes de tous les guides :
  - `DOCS.md` : index de la documentation
  - `USAGE.md` : guide d'utilisation
  - `CONFIG.md` : configuration avancée
  - `ARCHITECTURE.md` : architecture du projet
  - `SMART_CODEC.md` : logique smart codec
  - `TROUBLESHOOTING.md` : dépannage
  - `ADAPTATIF.md` : mode adaptatif
  - `ADDING_NEW_CODEC.md` : guide ajout codec
  - `CHANGELOG.md` : historique des versions
  - `SAMPLES.md` : génération de samples FFmpeg
- **README.en.md** (nouveau) : version anglaise complète du README avec section i18n
- **README.md** : ajout section "Internationalisation (i18n)" avec exemples `--lang`

Prochaines étapes :

- [ ] Lancer les tests : `bash run_tests.sh`
- [ ] Commit sur branche `feature/i18n`

Derniers prompts :

- "et que reste t'il à faire maintenant à part les tests ?"
- "Oui et traduis aussi toute la doc"

---

### 2026-01-16 — i18n : Infrastructure multilingue (français/anglais)

Branche : `feature/i18n`

Contexte : Rendre le script accessible aux utilisateurs anglophones tout en préservant le texte français soigneusement rédigé comme source de vérité.

Changements principaux :

- **lib/i18n.sh** (nouveau) : module de chargement des locales avec fonction `msg()` utilisant l'indirection Bash (`${!key}`). Fallback automatique vers français si locale absente.
- **locale/fr.sh** (nouveau) : ~100 clés de messages en français, organisées par catégorie (MSG_ARG_*, MSG_SYS_*, MSG_QUEUE_*, MSG_CONV_*, MSG_HELP_*, etc.).
- **locale/en.sh** (nouveau) : traductions anglaises complètes.
- **lib/args.sh** : ajout option `--lang fr|en` + migration de tous les messages vers `msg()`.
- **lib/exports.sh** : export des fonctions `msg`, `_i18n_load` et variable `LANG_UI` pour sous-shells.
- **nascode** : chargement de `i18n.sh` en premier (avant tout autre module utilisant des messages).
- **Modules migrés** : system.sh, queue.sh, lock.sh, index.sh, processing.sh, conversion.sh, finalize.sh, config.sh, off_peak.sh, vmaf.sh, transcode_video.sh, ffmpeg_pipeline.sh, conversion_prep.sh.

Architecture i18n :

- Variables MSG_* définies dans locale/*.sh
- msg "MSG_KEY" [args...] → printf avec placeholders %s, %d
- Détection : NASCODE_LANG env var > --lang CLI > défaut fr
- Extensible : ajouter un fichier locale/XX.sh pour nouvelle langue

Prochaines étapes :

- [ ] Vérifier les messages non migrés restants (modules secondaires)
- [ ] Traduction de la documentation (README, docs/) — phase 2
- [ ] Tests fonctionnels avec --lang en

Derniers prompts :

- "Que me proposes tu pour rendre tout mon script dispo en anglais ?"
- "Ok pour l'option 1, tant qu'on touche pas à mon texte consciencieusement choisi en français ça me va"
- "Fais le i18n, toute la doc sera traduite dans un second temps"

---

## Session précédente (14/01/2026 - Audit clean code)

### 2026-01-14 — Audio : traduction “qualité équivalente” (option 1) + UI : messages décoratifs (hors progress)

Branche : `feature/audio-ui`

Changements principaux :

- [lib/audio_decision.sh](lib/audio_decision.sh) : ajoute `translate_audio_bitrate_kbps_between_codecs` + table d'efficacité et applique la traduction **uniquement** quand `action != copy`.
  - Option 1 : le bitrate cible est toujours capé par `min(traduit, cible_config, bitrate_source)`.
- [lib/config.sh](lib/config.sh) : ajoute `AUDIO_TRANSLATE_EQUIV_QUALITY` et l'active par défaut en mode `adaptatif`.
- CLI : ajoute `--equiv-quality` / `--no-equiv-quality` (switch global audio + cap vidéo), avec exception : ignoré en mode `adaptatif`.
- [lib/ui.sh](lib/ui.sh) : ajoute `ui_print_raw` / `ui_print_raw_stderr` pour remplacer `echo -e` dans des modules non-UI.
- UI (hors progress UI) : harmonisation des messages décoratifs via helpers UI dans :
  - [lib/off_peak.sh](lib/off_peak.sh)
  - [lib/index.sh](lib/index.sh)
  - [lib/queue.sh](lib/queue.sh)
  - [lib/video_params.sh](lib/video_params.sh)
  - [lib/transcode_video.sh](lib/transcode_video.sh)

Tests :

- [tests/test_audio_translate_equiv_quality.bats](tests/test_audio_translate_equiv_quality.bats) : tests unit-like + intégration (bypass copy, fallback bitrate inconnu, cap au bitrate source, cas AAC→Opus et Opus→AAC forcé).
- [tests/test_args.bats](tests/test_args.bats) : ajoute des tests sur le parsing et l’override du switch `--equiv-quality` (y compris l’exception `adaptatif`).

Backlog :

- [.ai/TODO.md](.ai/TODO.md) mis à jour (Audio/UI marqués comme implémentés, décision “ne pas centraliser progress UI”).

Derniers prompts :

- "Ok vas y on va appliquer l'option 1 pour l'audio"
- "Continue jusqu'au bout"

### 2026-01-14 — UX : fin de tâches quand n < limite (random)

Branche : `fix/random-limit-suffix`

Contexte : en mode random, une limite implicite (10) peut être supérieure au nombre de fichiers présents (ex: 9). Après traitement des 9 fichiers, un message non logique s’affichait : “Tous les fichiers restants sont déjà optimisés.”

Correctif :

- [lib/processing.sh](lib/processing.sh) : le message “Fin des tâches” compare désormais `converted_count` à une **limite effective** `min(LIMIT_FILES, total disponible)` (via `TOTAL_QUEUE_FILE`).

Notes :

- Le sujet “suffixe sans CRF/preset” est à discuter (options proposées) avant implémentation.

Dernier prompt :

- "Limite de 10 implicite en mode random... corriger cet écart..." + "enlever les valeurs crf et medium du suffixe... suggestions"

### 2026-01-14 — Suffixe : alignement “web/scene” (Option A)

Branche : `fix/random-limit-suffix`

Décision : suffixe simplifié, sans CRF/bitrate/preset.

- Format effectif : `_<codec>_<height>p[_<AUDIO>][_sample]`
- Audio en majuscules (ex: `_AAC`, `_OPUS`).

Changements principaux :

- [lib/video_params.sh](lib/video_params.sh) : construit le suffixe effectif Option A.
- [lib/config.sh](lib/config.sh) : `SUFFIX_STRING` (preview) aligné sur Option A.
- [lib/system.sh](lib/system.sh) : hint d’exemple du prompt suffixe mis à jour.

Tests :

- Mise à jour des tests suffixe (Bats) impactés.

### 2026-01-14 — VMAF : compter les NA comme anomalies

Branche : `feature/robustness-heavy-outputs`

Contexte : VMAF renvoie "NA" sur les derniers runs (probablement suite aux changements `SCRIPT_DIR`/`LOG_DIR`). Décision : considérer les NA comme des anomalies dans le résumé.

Changements principaux :

- [lib/summary.sh](lib/summary.sh) : `vmaf_anomalies` compte désormais `score:NA` **ou** `quality:DEGRADE` (regex `grep -E`).
- [lib/notify_format.sh](lib/notify_format.sh) : le résumé Discord affiche `VMAF (NA/dégradé)` dans la section anomalies.

Tests :

- [tests/test_finalize_transfer_errors.bats](tests/test_finalize_transfer_errors.bats) : ajoute un test de régression `show_summary: VMAF NA est compté comme anomalie`.
- Validation locale : `bash run_tests.sh -f notify` et `bash run_tests.sh -f finalize_transfer_errors`.

Dernier prompt :

- "VMAF echoue sur topus mes derniers runs, je n'ai que des NA (...) Du coup je relève que les NA doivent être considérées comme des anomalies"

### 2026-01-14 — VMAF : cause racine des NA (Windows/MSYS + ffmpeg.exe externe)

Branche : `feature/robustness-heavy-outputs`

Diagnostic confirmé :

- `lib/detect.sh` sélectionne un `ffmpeg.exe` externe (Winget BtbN) pour VMAF car le FFmpeg MSYS principal n’a pas `libvmaf`.
- Dans `lib/vmaf.sh`, `log_path=$vmaf_log_file` était un chemin absolu de type MSYS (`/c/...`) **intégré dans la chaîne `-lavfi`**.
- La conversion de chemins MSYS→Windows ne s’applique pas à l’intérieur des sous-chaînes; `libvmaf` ne pouvait donc pas créer le JSON → `compute_vmaf_score()` retournait `NA` systématiquement.

Correctif :

- [lib/vmaf.sh](lib/vmaf.sh) : `log_path` devient **relatif** (basename), et FFmpeg est exécuté avec `cd "$LOG_DIR/vmaf"` pour que le JSON soit créé au bon endroit, quel que soit le binaire FFmpeg.

Validation :

- `bash run_tests.sh -f vmaf` OK.

### 2026-01-14 — Discord : espacement UX + résumé de fin markdown (metrics)

Branche : `feature/discord-notify-styled`

Changements principaux :

- [lib/notify_events.sh](lib/notify_events.sh) : ajoute un saut de ligne après les blocs de file d’attente (```text```) pour aérer le message, et améliore `script_exit`.
- [lib/summary.sh](lib/summary.sh) : écrit un fichier metrics `key=value` (durée, compteurs, anomalies, espace économisé) dans `SUMMARY_METRICS_FILE`.
- [lib/notify_format.sh](lib/notify_format.sh) : ajoute `_notify_kv_get` + `_notify_format_run_summary_markdown` pour générer un résumé Discord structuré (style proche VMAF) à partir des metrics.
- [lib/notify_format.sh](lib/notify_format.sh) : ajuste le titre “Exécution” en header Markdown (`## Exécution`) pour un rendu plus “gros”.
- [lib/logging.sh](lib/logging.sh) + [lib/exports.sh](lib/exports.sh) : introduit et exporte `SUMMARY_METRICS_FILE`.
- [tests/test_notify.bats](tests/test_notify.bats) : ajoute un test unitaire sur le rendu markdown du résumé via metrics.

Notes :

- Fallback conservé : si `SUMMARY_METRICS_FILE` est absent, `script_exit` retombe sur l’ancien snippet `SUMMARY_FILE` en bloc code.

### 2026-01-14 — Discord : aération des macro-étapes (correctif)

Branche : `feature/discord-notify-styled`

Changements principaux :

- [lib/notify_events.sh](lib/notify_events.sh) :
  - corrige un envoi en double sur l’événement `transfers_done` (un seul message, avec `\n\n` de respiration).
  - rétablit la ligne `**Mode**` dans `vmaf_started` (et garde l’espacement après l’annonce).

### 2026-01-14 — Refactor option 2 : formatage centralisé par événement

Branche : `feature/discord-notify-styled`

Changements principaux :

- [lib/notify_format.sh](lib/notify_format.sh) : ajoute des helpers `_notify_format_event_*` (un par événement) + améliore `_notify_format_run_summary_markdown` (ligne **Fin** + code de sortie).
- [lib/notify_events.sh](lib/notify_events.sh) : devient un routeur/enveloppe (garde-fous + envoi), et délègue le contenu Markdown à `notify_format`.
- [lib/notify_discord.sh](lib/notify_discord.sh) : retire `_notify_strip_ansi` (déplacé côté formatage).

### 2026-01-14 — Natif : autoload de `.env.local` (plus besoin d’export)

Branche : `feature/discord-notify-styled`

Changements principaux :

- [lib/env.sh](lib/env.sh) : charge un fichier `.env` en mode sûr (sans `source`), uniquement pour les variables `NASCODE_*`.
- [nascode](nascode) : auto-charge `./.env.local` au démarrage (si présent) avant le chargement des modules.
  - Désactivation : `NASCODE_ENV_AUTOLOAD=false`
  - Autre fichier : `NASCODE_ENV_FILE=/chemin/vers/mon.env`
- Docs : [README.md](README.md), [docs/USAGE.md](docs/USAGE.md), [docs/CONFIG.md](docs/CONFIG.md) mis à jour.
- Tests : [tests/test_env_autoload.bats](tests/test_env_autoload.bats) couvre le parsing et les flags.

### 2026-01-14 — Discord : notification lors des skips

Branche : `feature/discord-notify-styled`

Changements principaux :

- [lib/notify_events.sh](lib/notify_events.sh) : nouvel événement `file_skipped` (fichier + raison optionnelle).
- Points d’accroche :
  - [lib/ui.sh](lib/ui.sh) : quand `print_skip_message` décide un skip (déjà X265 / pas de flux vidéo / seuil adaptatif).
  - [lib/conversion_prep.sh](lib/conversion_prep.sh) : skip “sortie existe déjà” et “Heavier existe déjà”.
- Tests : [tests/test_notify.bats](tests/test_notify.bats) ajoute un test d’envoi `file_skipped` via curl mock.
- Docs : [README.md](README.md), [docs/USAGE.md](docs/USAGE.md), [docs/CONFIG.md](docs/CONFIG.md) mentionnent les notifs de skip.

### 2026-01-13 — Notifications Discord : refactor Option B + messages “petit écran”

Branche : `feature/discord-notify-styled`

Changements principaux :

- Refactor des notifications en modules (Option B) :
  - [lib/notify.sh](lib/notify.sh) : point d’entrée qui source les modules.
  - [lib/notify_discord.sh](lib/notify_discord.sh) : transport webhook + debug.
  - [lib/notify_format.sh](lib/notify_format.sh) : formatage pur (préfixes, aperçu queue, labels).
  - [lib/notify_events.sh](lib/notify_events.sh) : événements (run/file/transfers/vmaf/exit).
- [nascode](nascode) : la notif `run_started` est envoyée **après** `build_queue` pour inclure l’aperçu de la file (et en mode fichier unique après `export_variables`).
- Notifications demandées :
  - Aperçu de file après paramètres actifs (max 20 lignes, garde les 3 derniers, `...` au milieu).
  - Démarrage fichier : `▶️ Démarrage du fichier : ...` avec préfixe `[i/N]`.
  - Fin fichier : `✅ Conversion terminée en ... | before → after` avec préfixe `[i/N]`.
  - Fin conversions : `✅ Toutes les conversions terminées`.
  - Transferts : `📤 Transferts en attente : N` puis `✅ Transferts terminés` (anti-spam via garde-fous).
  - VMAF : début global + début/fin par fichier (score + qualité) + fin globale.
  - Fin de run : envoi du résumé, puis un second message avec l’heure de fin.
  - Ajustement UX : suppression du préfixe “NAScode —” (channel dédié) et suppression du statut (OK/ERROR) sur le message final ; l’heure de fin suffit.
  - Paramètres actifs : `Jobs parallèles : désactivé` si `PARALLEL_JOBS=1`.
- Points d’accroche :
  - [lib/conversion_prep.sh](lib/conversion_prep.sh) : notif démarrage fichier.
  - [lib/finalize.sh](lib/finalize.sh) : notif fin fichier (durée + tailles).
  - [lib/processing.sh](lib/processing.sh) : notif fin conversions (simple + FIFO).
  - [lib/transfer.sh](lib/transfer.sh) : notifs transferts en attente/terminés.
  - [lib/vmaf.sh](lib/vmaf.sh) : notifs VMAF par fichier.

Tests :

- [tests/test_notify.bats](tests/test_notify.bats) : ajout de tests pour `jobs parallèles : désactivé` et aperçu de queue (max 20 + `...` + 3 derniers).

Correctifs tests (suite Bats) :

- [lib/logging.sh](lib/logging.sh) : `LOG_DIR` reste ancré sur `$SCRIPT_DIR/logs` **par défaut**, mais accepte maintenant un override via variable d’environnement (utile pour l’isolement des runs de tests).
- E2E/régression : forcent `LOG_DIR="$WORKDIR/logs"` pour éviter de polluer le repo et stabiliser les assertions.
- [tests/test_e2e_stream_mapping.bats](tests/test_e2e_stream_mapping.bats) : accepte une sortie redirigée en dossier `_Heavier` (gain insuffisant / fichier plus lourd).
- Validation : `bash run_tests.sh` OK (suite complète).

Derniers prompts :

- "On va travailler sur les notifications dans discord... (Option B)"
- "ok pour option B"
- "PAs besoin d'afficher ce genre de message..." / "Oui retire..." / "Il y a eu des erreurs dans les tests... continue sans t'arreter"

### 2026-01-13 — Robustesse Git Bash : workdir par job + "Heavier" + logs ancrés

Branche : `feature/robustness-heavy-outputs`

Changements principaux :

- Isolation des encodages (two-pass) par job via un répertoire de travail temporaire dédié (`NASCODE_WORKDIR`) pour éviter les collisions de logs two-pass en parallèle.
- Random queue portable sans Python : remplacement `sort -R` par un shuffle best-effort (`shuf` si dispo, sinon `awk`+`sort`).
- Logs ancrés au dossier du script (`$SCRIPT_DIR/logs`) au lieu de dépendre du `cwd`.
- Guardrails Git Bash : fallback si `mkfifo` indisponible/échoue ; compteurs atomiques sans dépendre strictement de `flock`.
- Sorties "plus lourdes" / gain faible : redirection vers `Converted_Heavier/` (suffix configurable) + anti-boucle (skip si une sortie Heavier existe déjà).

Docs/tests :

- [docs/CONFIG.md](docs/CONFIG.md) : nouvelle section sur `HEAVY_OUTPUT_ENABLED`, `HEAVY_MIN_SAVINGS_PERCENT`, `HEAVY_OUTPUT_DIR_SUFFIX` + comportement/anti-boucle.
- [README.md](README.md) : mention de la redirection `Converted_Heavier/` + précision que logs/sortie sont ancrés au dossier du script.
- [tests/test_heavy_outputs.bats](tests/test_heavy_outputs.bats) : test anti-boucle via `_check_output_exists`.

Derniers prompts :

- "Fais une revue globale du code et dis moi ce que tu en penses"
- "Vas y pour la revue plus chirurgicale… (pas de fallback Python)"
- "ok tout est bon go" / "continue"

### Contexte

- Symptôme rapporté : la conversion peut “se bloquer” quand aucun fichier n’est réellement traitable (ex: entrée vide, fichier introuvable, ou source passée dans les exclusions).

### Changements

- [lib/conversion.sh](lib/conversion.sh) : `convert_file()`
  - skip explicite si chemin vide ou fichier introuvable (et incrémente toujours `processed_count` en mode FIFO).
  - si lecture des métadonnées ou préparation des chemins échoue tôt, incrémente `processed_count` avant de sortir.
- [lib/processing.sh](lib/processing.sh) : ignore les entrées vides dans les consumers (`read -d ''`).
- [lib/queue.sh](lib/queue.sh) : durcit `_validate_queue_not_empty()` :
  - queue vide → sortie 0 avec message.
  - queue non-vide mais sans séparateurs NUL → erreur (évite un mode FIFO qui attendrait indéfiniment).
- [nascode](nascode) : garde-fou : si `SOURCE` matche `EXCLUDES`, sortie explicite avec erreur.
  - Harmonisation UI : remplace les `echo -e` d'erreurs early par `print_error` / `print_warning` (fichier unique, source inexistante, source exclue, arrêt avant traitement).

- [lib/notify.sh](lib/notify.sh) : enrichit la notification Discord “run_started” avec les paramètres actifs liés au tri de la queue (`SORT_MODE` / `--random`) et à la limitation (`--limit`).

- [.ai/TODO.md](.ai/TODO.md) : consigne précisément les modules restant à harmoniser côté UI (bannières/progress/printf).

### Documentation

- [README.md](README.md) et [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) : ajoute un dépannage rapide/détaillé sur les cas “source exclue”, “aucun fichier à traiter” et “queue invalide (NUL)”.

### Tests

- [tests/test_conversion.bats](tests/test_conversion.bats) : non-régression sur `processed_count` (entrée vide + fichier introuvable).
- [tests/test_queue.bats](tests/test_queue.bats) : non-régression sur la validation queue vide vs format invalide.

### Dev tooling (ShellCheck)

- [Makefile](Makefile) : `make lint`
  - Options par défaut : `-f gcc` (évite un crash d'encodage Windows) + sévérité `error` (utilisable sur une base avec warnings legacy).
  - Durcissement possible : `make lint SHELLCHECK_SEVERITY=warning`.
- [run_tests.sh](run_tests.sh) : remplacements de messages d'erreur via `$'...'` pour éviter un faux positif ShellCheck sur les apostrophes.

#### 2026-01-13 — Nettoyage ShellCheck (warnings)

- Objectif : faire passer `make lint SHELLCHECK_SEVERITY=warning` sur tout le dépôt.
- [run_tests.sh](run_tests.sh)
  - Corrige SC2010 (supprime `ls | grep`), collecte via glob + filtrage en Bash.
  - Rend `--errors-only` effectif (évite variable inutilisée + réduit le bruit en CI).
- Directives SC2034 (variables globales cross-modules)
  - Ajout au niveau fichier : [lib/args.sh](lib/args.sh), [lib/counters.sh](lib/counters.sh), [lib/detect.sh](lib/detect.sh), [lib/logging.sh](lib/logging.sh), [lib/skip_decision.sh](lib/skip_decision.sh).
  - Ajouts ciblés / renommage variables ignorées : [lib/conversion.sh](lib/conversion.sh), [lib/transcode_video.sh](lib/transcode_video.sh), [lib/ffmpeg_pipeline.sh](lib/ffmpeg_pipeline.sh), [lib/media_probe.sh](lib/media_probe.sh), [lib/utils.sh](lib/utils.sh), [lib/ui.sh](lib/ui.sh), [lib/audio_params.sh](lib/audio_params.sh), [lib/video_params.sh](lib/video_params.sh), [lib/complexity.sh](lib/complexity.sh), [lib/adaptive_mode.sh](lib/adaptive_mode.sh).
- Résultat : `make lint SHELLCHECK_SEVERITY=warning` OK (0 warnings restants).

### Notes (anti-spam Discord en tests)

- [lib/notify.sh](lib/notify.sh) : pendant les tests Bats, les notifications Discord sont désactivées par défaut (évite de spammer le vrai webhook via l’environnement utilisateur).
- [tests/test_notify.bats](tests/test_notify.bats) : opt-in explicite via `NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS=true` pour les tests qui valident l’envoi (avec `curl` mock).

### Dernier prompt

- "Vas y pour les warnings mais sur tout le projet"
- "Oui vas y commit comme tu as dit"
- "Option A pour le moment, tu mettras le reste précisément dans le fichier TODO.md. D'ailleurs tant que tu es sur l'UI dans les messages à envoyer sur discord, il manque les paramètres actifs liés à ordre de tri et limitation"

### 2026-01-13 — Backlog : audio “traduction qualité équivalente” (mini-spéc)

- [.ai/TODO.md](.ai/TODO.md) : ajout d’une mini-spéc pour un futur helper de traduction de bitrate audio (invariants, activation par mode, stratégie de tests).
- [.ai/DEVBOOK.md](.ai/DEVBOOK.md) : entrée DEVBOOK correspondante (doc/backlog uniquement).

### Dernier prompt

- "Ouais j'aime bien tes recommandations pragmatiques, propose moi une mini spec et mets tout ça dans le todo"
- "Dans mes tests j'ai 3 skips, c'est normal non ?"
- "ok commit et puis merge dans main"

### 2026-01-13 — Release : changelog + doc + tag

- [docs/CHANGELOG.md](docs/CHANGELOG.md) : ajout d’une section `v2.7` (notes de release).
- [docs/DOCS.md](docs/DOCS.md) : ajout d’un rappel des commandes dev (`bash run_tests.sh`, `make lint`).
- [.ai/DEVBOOK.md](.ai/DEVBOOK.md) : entrée “préparation v2.7”.

### Dernier prompt

- "tu peux faire un tag pour une nouvelle release ?"
- "ok oui faut sans dout emettre le changelog à jour et la doc"
- "Oui ok vas y"

## Dernière session (13/01/2026 - Doc : notifications Discord + secrets)

### Changements

- [README.md](README.md) : ajout d’une section “Notifications Discord (optionnel)” (variables d’environnement, `.env.local`, exemple d’exécution).
- [docs/USAGE.md](docs/USAGE.md) : ajout d’une section “Notifications Discord (optionnel)” avec exemples Git Bash/WSL et PowerShell.
- [docs/CONFIG.md](docs/CONFIG.md) : ajout d’une section “Notifications Discord (optionnel)” (best-effort + sécurité).

### Notes

- Le webhook Discord doit rester un secret (ne pas le commiter). En cas de fuite, régénérer le webhook côté Discord.

### Suivi (13/01/2026 - Notifs Discord : debug + fix JSON + format)

- [lib/notify.sh](lib/notify.sh) : ajout `NASCODE_DISCORD_NOTIFY_DEBUG=true` (log codes HTTP + extrait de réponse), envoi JSON via `curl --data-binary @file` (évite les 400 “invalid JSON”), et amélioration du rendu (vrais sauts de ligne, liste Markdown, fin avec heure).
- [tests/test_notify.bats](tests/test_notify.bats) : tests mis à jour pour le nouveau mode d’envoi.

## Dernière session (13/01/2026 - Logs SVT-AV1 sans spam terminal)

### Contexte

- Besoin de vérifier en vrai run si SVT-AV1 est bien en mode "capped CRF" (via `mbr=`) et de retrouver les lignes `Svt[info]: SVT [config] ...`.
- Problème : NAScode lance FFmpeg avec `-loglevel warning`, ce qui masque les logs `info` de SVT sur les runs réussis.

### Changements

- [lib/transcode_video.sh](lib/transcode_video.sh) : ajout d’un mode debug opt-in `NASCODE_LOG_SVT_CONFIG=1`.
  - Pour `libsvtav1`, passe FFmpeg en `-loglevel info` (toujours redirigé vers un fichier, donc pas de spam terminal).
  - Extrait uniquement les lignes utiles (`Svt[info]: SVT [config]`, `capped CRF`, `max bitrate`, `BRC mode`) vers `logs/SVT_<timestamp>_*.log`.

### Tests

- [tests/test_transcode_video.bats](tests/test_transcode_video.bats) : tests unitaires sur le choix du loglevel et l’écriture du log SVT.

### Doc

- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) : section “Debug SVT-AV1 : vérifier capped CRF / mbr”.

## Dernière session (12/01/2026 - SVT-AV1 : cap CRF (rc=0 + mbr))

### Contexte

- Des sorties AV1 (SVT-AV1) pouvaient devenir plus grosses que la source en mode CRF (ex: mode adaptatif affichait un bitrate cible faible, mais l'encodage CRF restait trop "généreux").

## 2026-01-13 — Fix mode adaptatif : paramètres appliqués à l'encodage (AV1 + HEVC)

- Problème : en mode `adaptatif`, l'analyse affichait un `Bitrate cible (encodage)` faible mais l'encodage utilisait parfois les paramètres "standard" (symptôme : `mbr=1750` au lieu de ~`target×1.4`).
- Cause : appel `adaptive_info=$(_convert_run_adaptive_analysis_and_export ...)` via `$(...)` ⇒ subshell ⇒ les `export ADAPTIVE_*` internes ne remontaient pas au shell parent.
- Fix : export explicite des `ADAPTIVE_TARGET_KBPS/ADAPTIVE_MAXRATE_KBPS/ADAPTIVE_BUFSIZE_KBPS` dans `convert_file()` après parsing, pour que `lib/transcode_video.sh` utilise bien les budgets adaptatifs.
- Tests : ajout non-régression dans `tests/test_adaptatif.bats` + test ciblé HEVC/x265 dans `tests/test_encoding_subfunctions.bats`.
- Le build local (SVT-AV1 v3.1.2 via FFmpeg) n'accepte pas les clés `max-bitrate` et `buffer-size` dans `-svtav1-params` (erreurs de parsing observées).

### Changements

- [lib/transcode_video.sh](lib/transcode_video.sh) : en single-pass (CRF) + encodeur `libsvtav1`, cappe via `rc=0` + `mbr=<effective_maxrate>` (mode "capped CRF").

### Tests

- [tests/test_transcode_video.bats](tests/test_transcode_video.bats) : assertions SVT ajustées pour `rc=0` + `mbr=` (avec mock `get_video_stream_props()` pour éviter `ffprobe`).

### Branche

- `fix/svtav1-cap-crf`

### Derniers prompts

- "Oui vasy fait comme ça"
- "Nan ça marche pas, d'autres pistes ?"

## Dernière session (11/01/2026 - Debug blocage post-téléchargement)

### Symptôme

- Après le transfert vers le dossier temporaire, l’exécution semblait “bloquée” et nécessitait Ctrl+C.

### Diagnostic

- `nascode` active `set -euo pipefail`.
- `print_conversion_info()` appelait des helpers “informatifs” qui retournent `1` en cas normal (ex: audio stéréo = pas de message multicanal). Avec `errexit`, un `return 1` non géré peut interrompre silencieusement le flux, ce qui ressemble à un blocage.
- `lib/audio_decision.sh` n’était pas sourcé alors que des helpers audio sont utilisés depuis `lib/ui.sh` et `lib/audio_params.sh`.

### Correctifs

- `nascode` : ajout du `source lib/audio_decision.sh` avant `lib/audio_params.sh`.
- `lib/ui.sh` : `print_conversion_info()` ignore explicitement les retours non-erreur des helpers (`|| true`) et rend le probe audio plus robuste sous `set -e`.

### Notes

- Les noms de fichiers avec espaces/accents ne sont pas la cause principale ici (les chemins sont correctement quotés) ; le problème était lié aux codes de retour + `errexit`.

### Statut

- L’utilisateur confirme : “C’est bon ça remarche visiblement”.
- Tests non relancés automatiquement (recommandé : `bash run_tests.sh`).

## Session précédente (11/01/2026 - Refactoring conversion.sh)

### Objectif

Refactoring complet de `lib/conversion.sh` (958 → 178 lignes) selon l'option B+ validée par l'utilisateur.

### Tâches accomplies

**Nouveaux modules créés :**
- `lib/skip_decision.sh` (206 lignes) - Logique skip/passthrough/full
- `lib/conversion_prep.sh` (216 lignes) - Préparation fichiers, chemins, espace disque
- `lib/adaptive_mode.sh` (146 lignes) - Mode adaptatif (analyse complexité)

**Modules modifiés :**
- `lib/ui.sh` (+327 lignes) - Fonctions UI de conversion ajoutées
- `lib/counters.sh` (+13 lignes) - Variables `CURRENT_FILE_NUMBER`, `LIMIT_DISPLAY_SLOT`
- `lib/conversion.sh` (178 lignes) - Orchestration pure uniquement
- `lib/exports.sh` - Renommage exports (`_display_skip_decision` → `print_skip_message`, etc.)
- `nascode` - Chargement des nouveaux modules
- `tests/test_helper.bash` - Chargement nouveaux modules dans tous les loaders
- `tests/test_regression_exports_contract.bats` - Sources des nouveaux modules

**Documentation :**
- `DEVBOOK.md` - Entrée refactoring
- `ARCHITECTURE.md` - Nouveaux modules documentés

### Validation

✅ **Tous les tests passent** : 628/628 (3 skips conditionnels)

### Branche en cours

- `refactor/conversion-split`

### Commits

1. `d796838` - feat(refactor): éclatement de conversion.sh (958 → 178 lignes)
2. `00349ba` - docs: met à jour DEVBOOK.md et ARCHITECTURE.md
3. `ee16d87` - fix(tests): corrige les exports et tests après refactoring

### Prochaines étapes suggérées

1. Review du code sur la branche `refactor/conversion-split`
2. Merge vers `main` après validation
3. Mise à jour `README.md` si nécessaire (comportement inchangé)

---

## Session précédente (11/01/2026 - UX adaptatif + test E2E cap "qualité équivalente")

### Objectif

- Clarifier l’UX adaptatif : distinguer clairement bitrate source / seuil de skip / bitrate appliqué à l’encodage.
- Ajouter un test E2E (avec marge) pour valider le cap “qualité équivalente” (codec source moins efficace).

### Tâches accomplies

- `lib/conversion.sh`
  - Message post-analyse “✅ Conversion requise” : suppression du compteur `[X/Y]`, indentation alignée, ajout du codec source dans la parenthèse.
  - Analyse adaptatif : la ligne “Seuil skip …” est affichée uniquement si la source est déjà dans un codec meilleur/égal (sinon décision “codec”).

- `lib/complexity.sh`
  - Renommage “Bitrate adaptatif” → “Bitrate cible (encodage)” pour clarifier l’usage.

- `tests/test_regression_e2e.bats`
  - Ajout d’un E2E “EQUIV-QUALITY” (H.264 ~1000k → HEVC) avec tolérance sur le bitrate mesuré.
  - Stabilisation du test d’interruption : attendre un signe de démarrage (lock/TMP_DIR) avant d’envoyer SIGTERM.

### Validation

- `bash run_tests.sh -f "test_regression_e2e.bats"` (OK).

### Branche en cours

- `fix/equiv-quality-translate`

## Dernière session (11/01/2026 - Vidéo : cap qualité équivalente (source moins efficace))

### Objectif

- Ajouter une traduction "qualité équivalente" quand la source est dans un codec moins efficace (ex: H.264 → HEVC), sans changer la logique de skip.

### Tâches accomplies

- `lib/conversion.sh`
  - Expose `SOURCE_VIDEO_CODEC` et `SOURCE_VIDEO_BITRATE_BITS` (par fichier) pour le module d'encodage.

- `lib/transcode_video.sh`
  - En modes non adaptatifs : plafonne `TARGET/MAXRATE/BUFSIZE` à un budget "qualité équivalente" (via `translate_bitrate_kbps_between_codecs`) quand la source est moins efficace.

- Tests
  - `tests/test_encoding_subfunctions.bats` : ajout d'un test couvrant le cap (H.264 1000k → HEVC 700k).

- Doc
  - `docs/SMART_CODEC.md` : mention du plafonnement anti-upscaling.
  - `.ai/DEVBOOK.md` : entrée de journal correspondante.

### Validation

- `bash run_tests.sh` (OK).

## Dernière session (11/01/2026 - Tests : stabilisation interruption E2E)

### Objectif

- Corriger le test E2E d'interruption en cours (Windows/MSYS2) qui n'obtenait pas systématiquement `NASCODE_EXIT=130`.

### Tâches accomplies

- `tests/test_regression_e2e.bats`
  - Stabilisation du scénario d'interruption : éviter le pipe en background (PID ambigu) et utiliser `SIGTERM` (fiable en job arrière-plan) au lieu de `SIGINT`.

### Notes / Validation

- Test ciblé relancé via `bats ... -f "interruption en cours"` (OK).
- Suite complète `bash run_tests.sh` (OK, 0 échec).

### Branche en cours

- `feature/adaptatif-ux`

### Derniers prompts

- "✗  [22/32] test_regression_e2e.bats ... `[[ \"$output\" =~ \"NASCODE_EXIT=130\" ]]` failed"

## Dernière session (11/01/2026 - mode adaptatif : seuil codec-aware + no-downgrade)

### Objectif

- Implémenter la traduction du seuil de skip selon l'efficacité codec (comparaison dans l'espace du codec source quand il est meilleur).
- Empêcher tout downgrade vidéo implicite : une source AV1 trop haut débit est ré-encodée en AV1 (plafonnement) plutôt qu'en HEVC.
- Rendre le mode `adaptatif` cohérent avec `--codec av1` (bitrate adaptatif traduit depuis la référence HEVC).

### Tâches accomplies

- `lib/codec_profiles.sh`
  - Efficacités codec configurables via `CODEC_EFFICIENCY_*`.
  - Ajout helper `translate_bitrate_kbps_between_codecs()`.

- `lib/conversion.sh`
  - Seuil codec-aware (traduction `MAXRATE_KBPS`/maxrate adaptatif vers le codec source quand la source est meilleure).
  - Sélection par fichier : `EFFECTIVE_VIDEO_CODEC`/`EFFECTIVE_VIDEO_ENCODER` (no-downgrade sauf `--force-video`).
  - En mode `adaptatif`, traduction des bitrates calculés (référence HEVC) vers le codec cible actif.
  - UX : message explicite "✅ Conversion requise" juste après l'analyse (avant transfert).

- `lib/transcode_video.sh`
  - Support du codec/encodeur effectif par fichier et traduction des budgets bitrate (standard + adaptatif) vers le codec effectif.

- Tests / doc
  - `tests/test_conversion.bats`, `tests/test_conversion_mode.bats` mis à jour/complétés.
  - `README.md` et `docs/SMART_CODEC.md` mis à jour.
  - `.ai/DEVBOOK.md` mis à jour.

### Branche en cours

- `feature/adaptatif-ux`

### Notes / Validation

- Les tests n'ont pas été relancés automatiquement (à faire côté utilisateur : `bash run_tests.sh`).


## Dernière session (11/01/2026 - DEVBOOK + nouveaux tests E2E)

### Objectif

- Remettre `.ai/DEVBOOK.md` en ordre chronologique et compléter le résumé du 10/01.
- Ajouter des tests E2E ciblant des cas d'intégration "terrain" : chemins Windows (accents/espaces), interruption en cours, stream mapping sous-titres, erreurs d'I/O.

### Tâches accomplies

- `.ai/DEVBOOK.md`
  - Ré-ordonnancement chronologique (suppression du doublon `2026-01-09`).
  - Restauration de l'entrée `2026-01-08`.
  - Complétion de l'entrée `2026-01-10` avec : `--quiet`, profil adaptatif 480p/SD, fix audio "cible plus efficace", durcissement tests, doc portrait, ajustement message codec invalide.

- `tests/test_regression_e2e.bats`
  - Ajout E2E chemins avec accents/espaces.
  - Ajout E2E erreur I/O : `output_dir` est un fichier.
  - Ajout E2E interruption en cours (SIGINT) : lock nettoyé + `STOP_FLAG` présent.

- `tests/test_e2e_stream_mapping.bats`
  - Ajout E2E stream mapping sous-titres (fichiers réels générés via ffmpeg).

### Notes / Validation

- Les tests E2E nécessitent `ffmpeg` + `ffprobe` avec `libx265`.
- Tests non relancés automatiquement dans cette session.

### Branche en cours

- `fix/audio-opus-option`

### Derniers prompts

- "ok ajoute en un pour les chemin windows avec accent espace, le stop en cours de traitement aussi et stream mapping erreurs d'I/O aussi. mais avant mets à jour le devbook..."

## Dernière session (10/01/2026 - UX : dry-run (phase conversion))

### Objectif

- Corriger l'encadré de phase (bordures + indentation cohérente).
- En dry-run, rendre le début de phase conversion plus explicite (ne "fait" pas rien).
- Rendre la fin du dry-run plus visible (et au bon moment).

### Tâches accomplies

- `lib/ui.sh`
  - Correction de `print_phase_start()` : ajout de la bordure droite + padding des lignes (titre/sous-titre), et support d'une 3e ligne optionnelle (note).
  - `print_conversion_start()` : en dry-run, ajout d'une note "🧪 Mode dry-run : aucune conversion exécutée" dans l'encadré.
  - `print_conversion_complete()` : message adapté en dry-run ("Simulation terminée (dry-run)") avec padding robuste.
- `nascode`
  - Déplacement du message de fin : la comparaison dry-run s'exécute d'abord, puis affichage d'un encadré final via `print_header "🧪 Dry-run terminé"`.

- `lib/conversion.sh`
  - Mode `adaptatif` : analyse AVANT transfert pour déterminer le seuil adaptatif et décider du skip sans téléchargement inutile, puis affichage "▶️ Démarrage du fichier" (avec compteur) uniquement si on ne skip pas.

- `lib/conversion.sh` / `lib/complexity.sh`
  - Compteur en mode `adaptatif` (notamment en mode random/limite) : fallback `[current/total]` tant que le slot limite n'est pas réservé.
  - Résultat de l'analyse : affichage d'une synthèse explicite (CV, C, bitrate adaptatif) via `print_info`.

- `lib/ui.sh` / `lib/system.sh`
  - Section "Vérification de l'environnement" : indentation du header + séparateur alignée sur les autres lignes (2 espaces) et ajout d'une séparation visuelle après "Environnement validé".

### Validation

- Vérification syntaxe Bash : `bash -n lib/ui.sh` et `bash -n nascode` (OK).
- Vérification syntaxe Bash : `bash -n lib/conversion.sh` (OK).

### Branche en cours

- `feat/ux-preconversion-messages`

### Derniers prompts

- "Ok petit point en mode dry run, UX et UI pas optimales..."

## Dernière session (10/01/2026 - Tests : assertions moins fragiles)

### Objectif

- Réduire le couplage des tests Bats au wording UI (messages FR/EN) pour éviter les régressions lors de tweaks UX.

### Tâches accomplies

- `tests/test_helper.bash`
  - Ajout de helpers d'assertion réutilisables : `assert_glob_exists` et `assert_output_has_no_prompt_lines`.
- `tests/test_regression_non_interactive.bats`
  - Remplacement de l'assertion texte "Dry run" par des invariants : absence de prompt + artefacts logs (`Index`, `Session_*.log`, `Summary_*.log`, `DryRun_Comparison_*.log`).
- `tests/test_lock.bats`
  - Remplacement d'assertions sur message d'erreur par un invariant (lockfile inchangé + PID actif).
- `tests/test_args.bats`
  - Remplacement de checks sur mots FR ("introuvable", "Option", etc.) par la présence des arguments fautifs (ex: chemin, option inconnue).
- `tests/test_e2e_full_workflow.bats` / `tests/test_regression_e2e.bats`
  - Durcissement de checks e2e en privilégiant les fichiers/logs et noms de fichiers plutôt que les libellés.

### Notes

- `run_tests.sh -f` filtre uniquement sur les noms de fichiers (pas d'OR regex multi-fichiers).
- `logs/Queue` est un artefact temporaire nettoyé : ne pas l'asserter en fin de run.

### Validation

- Tests relancés individuellement sur les fichiers modifiés (OK).
- Suite complète : `bash run_tests.sh` (OK après correctif) ; seul échec initial sur `tests/test_regression_exports_contract.bats` (rendu plus robuste via `declare -F` plutôt que sorties attendues).

### Branche en cours

- `feat/ux-preconversion-messages`

### Derniers prompts

- "Oui ça me parait une bonne pratique de ne pas écrire directement le texte attendu dans les tests. Vérifie s'il n'y a pas d'autres tests qui peuvent être optimisés de cette manière"

## Dernière session (10/01/2026 - UX : espaces et mode aléatoire)

### Objectif

- Améliorer la lisibilité des messages UI (sauts de ligne cohérents).
- Rendre le mode aléatoire explicite dans les "Paramètres actifs".
- En mode aléatoire, afficher des noms de fichiers (pas les chemins complets).

### Tâches accomplies

- `lib/system.sh`
  - Ajout d’un saut de ligne après l’item "Mode conversion".
  - UX `.plexignore` :
    - Si le fichier existe déjà : message compact (sans saut de ligne).
    - Si le fichier est créé (réponse à la question) : ajout d’une ligne vide après le succès pour séparer visuellement la suite.
- `lib/ui.sh`
  - Ajout de `print_info_compact()` (info sans ligne vide).
  - Ajout de `format_option_random_mode()` (ligne "Mode aléatoire : activé").
- `lib/queue.sh`
  - Ajout de la ligne "Mode aléatoire : activé" dans l’encadré des paramètres actifs.
  - Liste random : affichage du nom de fichier uniquement (basename) au lieu du chemin complet.

### Tests / validation

- Vérification syntaxe Bash : `bash -n` sur les fichiers modifiés (OK).
- Tests Bats : non relancés dans cette session (à faire côté utilisateur si souhaité).

### Branche en cours

- `feat/ux-preconversion-messages`

### Derniers prompts

- "Plusieurs demandes niveau UI… plexignore… mode conversion… mode aléatoire…"

## Dernière session (10/01/2026 - UX : mode --quiet)

### Objectif

- Ajouter un mode silencieux affichant uniquement les warnings/erreurs.
- Réduire l'éparpillement : centraliser la décision "doit-on afficher ?" dans les helpers UI.

### Tâches accomplies

- `lib/args.sh`
  - Ajout de `-Q/--quiet` : active `UI_QUIET=true` et `NO_PROGRESS=true`.
  - Aide mise à jour pour documenter `--quiet`.
- `lib/config.sh` / `lib/exports.sh`
  - Ajout + export de `UI_QUIET`.
- `lib/ui.sh`
  - Ajout de `_ui_is_quiet()`.
  - Les sorties "info/succès/sections/items/encadrés" deviennent silencieuses en mode quiet.
  - Les warnings/erreurs et les questions interactives restent visibles.
- `lib/queue.sh`
  - Warnings index (régénération forcée, index vide, métadonnées manquantes, source différente) affichés même en mode quiet.
  - En mode quiet, le cas "source différente" est réduit à une seule ligne.

### Validation

- Vérification syntaxe Bash : `bash -n` sur les fichiers modifiés (OK).

### Branche en cours

- `feat/ux-preconversion-messages`

## Dernière session (10/01/2026 - UX : --quiet (couverture complète))

### Objectif

- Rendre `--quiet` fiable à l’échelle du projet : infos/succès/sections silencieux, warnings/erreurs visibles.
- Réduire les `echo -e` “user-facing” hors helpers UI (pour éviter les oublis).

### Tâches accomplies

- `lib/ui.sh`
  - `--quiet` étendu aux helpers restants : `print_success_box`, `print_status`, `print_empty_state`, indexation (`print_indexing_*`), résumés (`print_summary_*`), fin transfert/VMAF/conversion, limitations.
- `lib/off_peak.sh` / `lib/processing.sh`
  - Messages d’attente heures creuses basculés en `print_info` (silencieux en quiet).
  - Les interruptions “arrêt demandé” basculées en `print_warning` (visibles en quiet).
- `lib/finalize.sh`
  - Succès en `print_success` (silencieux en quiet) ; erreurs/warnings en `print_error`/`print_warning` (visibles en quiet, même si `NO_PROGRESS=true`).
- `lib/queue.sh` / `lib/system.sh` / `lib/transfer.sh` / `lib/lock.sh` / `lib/complexity.sh` / `lib/transcode_video.sh` / `lib/conversion.sh`
  - Migration ciblée des prints user-facing vers les helpers UI ; suppression d’un cas bruité en mode `--quiet` (flèche `→` sur transfert temp).

### Tests / doc

- `tests/test_args.bats`
  - Ajout de `UI_QUIET` dans le reset + test `parse_arguments --quiet`.
- `docs/USAGE.md`
  - Ajout d’un exemple `--quiet` + rappel des options `--no-progress` et `--quiet`.

### Branche en cours

- `feat/ux-preconversion-messages`

## Dernière session (09/01/2026 - UX messages pré-conversion)

### Objectif

- Améliorer les messages informatifs affichés juste avant la conversion (modes `serie` et `film`).
- Centraliser l'affichage downscale / 10-bit dans l'orchestrateur (éviter les doublons).

### Tâches accomplies

- `lib/conversion.sh`
  - Extension de `_convert_display_info_messages(...)` :
    - Downscale + 10-bit affichés avant lancement FFmpeg (si encodage vidéo, pas en passthrough).
    - Message multicanal affiché en `serie` ET en `film`, avec wording dépendant de `AUDIO_FORCE_STEREO`.
    - Ajout d'un résumé audio effectif (codec/bitrate/layout) basé sur `_get_smart_audio_decision()`.
  - Ajout d'un flag `VIDEO_PRECONVERSION_VIDEOINFO_SHOWN` (reset par fichier) pour dédoublonner l'affichage côté `transcode_video.sh`.
- `lib/transcode_video.sh`
  - Garde anti-doublon sur les messages downscale/10-bit tout en conservant l'application réelle du filtre.

### Tests / doc

- Tests Bats : non relancés dans cette session (à faire côté utilisateur : `bash run_tests.sh`).
- Documentation : non modifiée (changement purement UX/logs).

### Branche en cours

- `feat/ux-preconversion-messages`

### Fichiers modifiés

- `lib/conversion.sh`
- `lib/transcode_video.sh`

### Derniers prompts

- "Je voudrais que les messages ... soient affichés en mode série et en mode film..."
- "Option B ... oui ... non. Fais moi un plan d’implémentation"
- "Vas-y ... fais une nouvelle branche à partir de refactor/convert-file-cleanup"

## Dernière session (09/01/2026 - stéréo forcée en mode série)

### Objectif

- Garantir une sortie **stéréo** en mode `serie` (downmix systématique) sans réinventer la logique audio.
- Réduire la dispersion des paramètres dépendants du mode (centralisation autour de `set_conversion_mode_parameters`).

### Tâches accomplies

- Ajout d’un flag global `AUDIO_FORCE_STEREO` (activé en `serie`, désactivé en `film` / `adaptatif`).
- Audio :
  - Forçage du layout cible à `stereo` via `_get_target_audio_layout()`.
  - Bypass “stéréo forcée” dans `_get_smart_audio_decision()` pour les sources `>= 6` canaux : décision `convert/downscale` afin de garantir le downmix (y compris pour les cas premium/passthrough).
  - Gestion du cas `AUDIO_CODEC=copy` : bascule vers `aac` si downmix requis (impossible en copy).
- Vidéo / centralisation mode-based :
  - Ajout de `ENCODER_MODE_PROFILE` (ex: `adaptatif` → `film`) et `ENCODER_MODE_PARAMS` calculé une fois dans `set_conversion_mode_parameters`.
  - `lib/transcode_video.sh` n’appelle plus `get_encoder_mode_params(..., CONVERSION_MODE)` à la volée : utilise `ENCODER_MODE_PARAMS`.
  - SVT-AV1 : utilisation de `FILM_KEYINT` (centralisé) au lieu de `get_mode_keyint(CONVERSION_MODE)`.
- CLI : suppression de la désactivation automatique de `SINGLE_PASS_MODE` dans `parse_arguments` (centralisé dans `set_conversion_mode_parameters`).
- Exports : ajout des exports `AUDIO_FORCE_STEREO`, `ENCODER_MODE_PROFILE`, `ENCODER_MODE_PARAMS`.
- UX : en mode limite (`-l`), le compteur affiché sur “Démarrage du fichier” commence à `[1/N]` (slot en cours) au lieu de `[0/N]`.
- UX (robustesse) : le slot `[X/N]` en mode limite est réservé de façon atomique (mutex) pour éviter les doublons quand `PARALLEL_JOBS>1` ; en `adaptatif`, la réservation est faite après l'analyse (évite les slots “gâchés” si skip post-analyse).

### Tests / doc

- Tests Bats mis à jour :
  - `tests/test_args.bats` : prend en compte la centralisation (effet visible après `set_conversion_mode_parameters`).
  - `tests/test_audio_codec.bats` : le cas “série + source multicanal” attend désormais un downmix AAC stéréo.
- Documentation : mise à jour pour expliciter “stéréo forcée en mode `serie`” et ses implications (y compris exceptions à `--audio copy`).

### Fichiers modifiés

- `lib/config.sh`
- `lib/audio_params.sh`
- `lib/audio_decision.sh`
- `lib/transcode_video.sh`
- `lib/args.sh`
- `lib/exports.sh`
- `tests/test_args.bats`
- `tests/test_audio_codec.bats`
- `README.md`
- `docs/SMART_CODEC.md`
- `docs/CONFIG.md`
- `.ai/DEVBOOK.md`

### Validation

- Vérification éditeur : aucun problème signalé dans les fichiers modifiés.
- Suite de tests complète : **non lancée** (à faire côté utilisateur : `bash run_tests.sh`).

### Branche en cours

- `fix/docs-index-link`

### Derniers prompts

- "m’assurer que --force-audio donne le même résultat que --force"
- "est-ce qu’on force bien la sortie stéréo par défaut dans le mode série ?"
- "ok option C… stéréo garantie… réanalyse… et recentraliser dans set_conversion_mode_parameters" + "go"

## Dernière session (09/01/2026 - samples FFmpeg)

### Tâches accomplies

#### Ajout de samples FFmpeg (edge cases)

- Ajout du script `tools/generate_ffmpeg_samples.sh` pour générer des médias courts et reproductibles via `lavfi`.
- Ajout de la doc `docs/SAMPLES.md` + lien dans `docs/DOCS.md`.
- Ajout d'une règle `.gitignore` pour ignorer `samples/_generated/`.
- Correction `vfr_concat` sous Git Bash/Windows (concat demuxer + chemins relatifs).
- Ajout DTS/TrueHD : génération 5.1 OK; 7.1 dépend du support de l'encodeur (skip explicite si non supporté).

### Branche en cours

- `fix/docs-index-link`

### Derniers prompts

2026-01-09 : "Nan regarde plutôt pour le script ne considère pas ce fichier comme une vidéo" — ajout d'un nettoyage automatique des artefacts invalides (0 octet / sans flux vidéo) pour `21_truehd_7_1.mkv` et `19_dts_7_1.mkv` quand `--force` n'est pas utilisé.

2026-01-09 : "Juste petit correction niveau UI" — harmonisation du prompt `.plexignore` avec le format UI standard (`ask_question` + `print_success`).

### Tâches accomplies

- VMAF : validation du refactor de `compute_vmaf_score()` (commande FFmpeg dédupliquée, `-progress` conditionnel).
- Suffixe vidéo : refactor de `_build_effective_suffix_for_dims()` en helpers internes dans `lib/video_params.sh` (réduction de complexité, aucun changement de format attendu).
- Documentation : mise à jour du tableau récapitulatif des critères de conversion (vidéo skip vs bitrate, audio premium passthrough, section multicanal, exemple mis à jour).

### Fichiers modifiés

- `lib/video_params.sh`
- `docs/📋 Tableau récapitulatif - Critères de conversion.csv`
- `.ai/handoff.md`
- `.ai/DEVBOOK.md`

### Validation

- Tests ciblés : `bash run_tests.sh -f vmaf` (OK, 1 skip)
- Tests ciblés : `bash run_tests.sh -f transcode_video` (OK)
- Tests ciblés : `bash run_tests.sh -f encoding_subfunctions` (OK)
- Tests ciblés : `bash run_tests.sh -f audio_codec` (OK)

### Branche en cours

- `fix/clean-code-light`

### Derniers prompts

- "Fais un check sur les opportunités de refactorisations, surtout pour les longues fonctions d'audio ou de video"
- "Fais le plan pour tous les axes que tu as détecté"
- "on exécute c’est bon"

## Dernière session (08/01/2026 - clean code)

### Tâches accomplies

- Refactor ciblé "clean code" sans changement UX : commande FFmpeg construite via tableaux d'arguments (réduit le word-splitting implicite).
- Durcissement léger de la décision de conversion : valeurs par défaut sûres si `MAXRATE_KBPS` / `SKIP_TOLERANCE_PERCENT` sont absents ou non numériques.
- Ajout de tests Bats dédiés sur la décision `skip` / `video_passthrough` / `full`.
- VMAF: refactor des appels `ffmpeg` en tableaux d'arguments + usage de `get_file_size_bytes`.

### Fichiers modifiés

- `lib/transcode_video.sh`
- `lib/conversion.sh`
- `lib/vmaf.sh`
- `tests/test_conversion_mode.bats` (nouveau)

### Validation

- Tests ciblés : `bash run_tests.sh -f args` (OK)
- Tests ciblés : `bash run_tests.sh -f conversion_mode` (OK)
- Tests ciblés : `bash run_tests.sh -f transcode_video` (OK)
- Tests ciblés : `bash run_tests.sh -f vmaf` (OK, 1 skip)

### Notes

- `ffprobe_safe` est utilisé pour éviter les soucis de chemins Windows/Git Bash (accents, /c/...).
- ShellCheck n'était pas disponible dans l'environnement Git Bash pendant cette session.

### Branche en cours

- `fix/clean-code-light`

### Derniers prompts

- "Estce que tu peux me dire si mon code respecte les principes du clean code ?"
- "vas y puis dresse moi un petit plan pour améliorer tout ça, sans que ça soit trop lourd"
- "Vas y fait tout"
- "vas y continue"
- "option A et B"
- "vas y continue jusqu'au bout"

## Suite (Option A + B)

- Remplacements ciblés `ffprobe` → `ffprobe_safe` (robustesse Windows/Git Bash) dans `lib/vmaf.sh` et `lib/video_params.sh`.
- Durcissement léger du parsing CLI : ajout de `_args_require_value` dans `lib/args.sh` pour éviter les cas “option sans valeur” et fournir une erreur claire.
- Tests : ajout de cas Bats sur `--source` / `--output-dir` sans valeur dans `tests/test_args.bats`.


## Dernière session (08/01/2026)

### Tâches accomplies

#### Implémentation multichannel audio et option --no-lossless

**Nouvelles fonctionnalités :**
- `--no-lossless` : force la conversion des codecs premium (DTS/DTS-HD/TrueHD/FLAC)
- Gestion complète de l'audio multichannel (5.1, 7.1)

**Règles multichannel implémentées :**
- DTS/DTS-HD/TrueHD : passthrough si 5.1 ou moins, conversion obligatoire si 7.1 (downmix)
- 7.1 → 5.1 : toujours downmixer (re-encode requis)
- EAC3 : codec par défaut pour multichannel (cap 384kbps)
- AAC multichannel : uniquement avec `-a aac --force-audio` (320kbps)
- Opus multichannel : avec `-a opus` (224kbps)
- AC3 → EAC3 (ou Opus avec `-a opus`)
- Anti-upscale : copy si source < 256kbps (ne pas gonfler artificiellement)

**Code ajouté/modifié :**
- `lib/config.sh` : constantes multichannel (bitrates, seuils)
- `lib/args.sh` : parsing `--no-lossless`
- `lib/audio_decision.sh` : module dédié à la décision audio (smart codec + multichannel)
  - `_get_smart_audio_decision()`, `_get_audio_conversion_info()`, `_should_convert_audio()`
  - `is_audio_codec_premium_passthrough()`, `_compute_eac3_target_bitrate_kbps()`, `_get_multichannel_target_bitrate()`
- `lib/audio_params.sh` : allégé (layout audio + construction des paramètres FFmpeg)
- `lib/exports.sh` : exports des nouvelles fonctions/variables
- `README.md` : documentation des règles multichannel

**Refactor (option 2) :**
- Extraction de la logique “decision engine” audio vers `lib/audio_decision.sh`
- Mise à jour de `docs/SMART_CODEC.md` (pointeurs vers les bons modules)

**Tests :**
- Nouveau fichier `tests/test_audio_multichannel.bats` : 38 tests
- Mise à jour `tests/test_audio_codec.bats` : comportement multichannel
- **610 tests passent (100%)**

### Fichiers modifiés

- `lib/config.sh`
- `lib/args.sh`
- `lib/audio_params.sh`
- `lib/audio_decision.sh` (nouveau)
- `lib/exports.sh`
- `README.md`
- `tests/test_audio_codec.bats`
- `tests/test_audio_multichannel.bats` (nouveau)

### Branche en cours

- `feature/no-lossless-multichannel`

### Prochain step

- Review/merge vers `main` après validation utilisateur

---

## Session précédente (08/01/2026)

### Tâches accomplies

- Ajout d'une entrée `v2.6 (Janvier 2026)` dans `docs/CHANGELOG.md`.
- Préparation de la release `v2.6` (tag Git) pour refléter les changements récents.

## Dernière session (03/01/2026)

### Tâches accomplies

#### 1. Refactorisation Quick Wins
- **format_duration_seconds()** et **format_duration_compact()** ajoutées à `lib/utils.sh`
- Remplacement de 5 calculs de durée inline dans `lib/finalize.sh`
- Remplacement de tous les `stat -c%s || stat -f%z` par `get_file_size_bytes()` (finalize.sh, vmaf.sh)
- Suppression de **85 lignes de code mort** (`_build_encoder_ffmpeg_args()`)
- 13 tests unitaires ajoutés dans `tests/test_utils.bats`

#### 2. Refactorisation Structurelle
- **_run_ffmpeg_encode()** : fusion des deux branches if/else dupliquées en une seule commande FFmpeg
- Réduction de 40 à 30 lignes (-14 lignes net)
- `convert_file()` analysée : déjà bien structurée, pas de refacto nécessaire

### Commits
- `4cb2fed` : refactor: quick wins - factorisation et nettoyage de code
- `953e2cf` : refactor(transcode): déduplique l'appel FFmpeg dans _run_ffmpeg_encode()

### Derniers prompts
- "occupe toi des quicks wins et de la refactorisation structurelle que tu as jugé nécessaire et n'oublies pas de mettre à jour les tests"

### Branche en cours
- `fix/ui-vmaf-improvements`

### À faire (non commencé)
- Tests à lancer par l'utilisateur : `bash run_tests.sh`
- Push si tests OK

---

## Dernière session (02/01/2026 - après-midi)

### Tâches accomplies

#### 1. UX Compteur mode limite
- **Problème** : En mode limite (`-l N`), pas de compteur visible et frustration si la limite n'est pas atteinte.
- **Solution** :
  - Nouveau compteur `CONVERTED_COUNT_FILE` qui ne compte que les fichiers réellement convertis (pas les skips)
  - Affichage `[X/N]` en mode limite (commence à `[0/N]`)
  - Bloc jaune en fin de run : "Tous les fichiers restants sont déjà optimisés. (X/N)" si limite non atteinte
- **Fichiers modifiés** :
  - `lib/queue.sh` : +`increment_converted_count()`, +`get_converted_count()`
  - `lib/processing.sh` : init compteur + message fin
  - `lib/conversion.sh` : `_get_counter_prefix()` modifié + incrément après décision skip
- **Tests** : 5 tests ajoutés dans `test_queue.bats`

### Derniers prompts
- Réflexion sur compteur fichiers à traiter pour mode limite
- Validation approche modulaire (option A)
- Implémentation + tests + doc

### Branche en cours
- `fix/limit-counter-ux`

---

## Dernière session (02/01/2026)

### Tâches accomplies

#### 1. Ajout du pipeline multimodal (process)
- **agent.md** : ajout d'une section "Pipeline de développement multimodal (LLM)".
- **.github/copilot-instructions.md** : ajout d'une section "Pipeline de Développement Multimodal".

#### 2. Refonte de la documentation (README + docs/)
- **README.md** : simplification en page d'entrée (TL;DR, commandes clés, liens vers docs).
- **docs/** : création de guides séparés : `README.md`, `USAGE.md`, `CONFIG.md`, `SMART_CODEC.md`, `TROUBLESHOOTING.md`, `CHANGELOG.md`.
- Correction de cohérence doc : le codec audio par défaut est `aac` (conforme à `lib/config.sh`).

#### 3. Mémoire projet
- **DEVBOOK.md** : création puis mise à jour avec les changements de process et doc.

### Derniers prompts
- Mise en place du pipeline de développement multimodal.
- Audit/refonte du README (TL;DR, organisation, réduction répétitions) + proposition de docs séparées.

### Branche en cours
- `docs/multimodal-pipeline`

---

## Dernière session (31/12/2025)

### Tâches accomplies

#### 1. Améliorations UI - Messages et affichage
- **lib/conversion.sh** :
  - Ajout message visible `📋 Vidéo conservée (X265 optimisé) → conversion audio seule` pour mode video_passthrough
  - Amélioration message SKIPPED : indique si le codec est meilleur que la cible (ex: "AV1 (meilleur que HEVC)")
  - Ajout compteur `[X/Y]` sur la ligne "Démarrage du fichier"
  - Suppression redondance : ne plus afficher le nom de fichier dans le bloc de transfert (déjà sur la ligne de démarrage)

#### 2. Compteur de fichiers X/Y
- **lib/processing.sh** : 
  - Ajout variables `STARTING_FILE_COUNTER_FILE` et `TOTAL_FILES_TO_PROCESS`
  - Export pour utilisation dans les workers parallèles
- **lib/queue.sh** :
  - Nouvelle fonction `increment_starting_counter()` avec mutex pour comptage atomique
- **lib/exports.sh** : Export de `increment_starting_counter`

#### 3. Troncature noms de fichiers augmentée à 45 caractères
- **lib/utils.sh** : Script AWK - passage de `%-30.30s` à `%-45.45s`
- **lib/finalize.sh** : Ligne "Terminé en" - passage de 30 à 45 caractères
- **lib/vmaf.sh** : Tous les affichages VMAF - passage de 30 à 45 caractères

#### 4. Simplification bloc de transfert
- **lib/ui.sh** : `print_transfer_item()` affiche maintenant "📥 Copie vers temp..." au lieu du nom de fichier (évite la répétition)

### Derniers prompts
- Améliorations UI : messages audio-only, compteur X/Y, réduction répétition nom fichier, troncature 45 caractères

### Branches en cours
- `feature/ui-improvements` (actuelle)

---

## Session précédente (31/12/2025)

### Tâches accomplies

#### 1. Nettoyage des codes couleurs ANSI dans le fichier Summary
- **lib/finalize.sh** : ajout de `_strip_ansi_stream()` et écriture de `SUMMARY_FILE` via `tee >(_strip_ansi_stream > "$SUMMARY_FILE")`
- Objectif : garder les couleurs à l'écran, mais produire un fichier `Summary_*.log` lisible (sans séquences `\x1b[...]`).

#### 2. Test de non-régression
- **tests/test_finalize_transfer_errors.bats** : ajout d'une assertion garantissant l'absence de caractère ESC (`\x1b`) dans `SUMMARY_FILE`.

### Derniers prompts
- "C'est possible de nettoyer les codes couleurs quand on fait le tee \"$SUMMARY_FILE\" ?"

### Branches en cours
- `fix/strip-ansi-summary`

## Dernière session (30/12/2025)

### Tâches accomplies

#### 1. Fix option `-S` et refactoring SUFFIX_MODE
- **Fix `-S` option** : Correction de l'erreur "unbound variable" pour `CUSTOM_SUFFIX_STRING`
- **Refactoring SUFFIX_MODE** : Unification de 3 variables en une seule `SUFFIX_MODE` avec valeurs : "ask", "on", "off", "custom:xxx"
- **Fix indentation UI** : Uniformisation de l'indentation (2 espaces) dans `queue.sh`

#### 2. Centralisation ffprobe audio
- **Création `_probe_audio_info()`** dans `media_probe.sh` pour centraliser les appels ffprobe audio
- **Refactoring audio (decision engine)** : `_get_smart_audio_decision()` et `_get_audio_conversion_info()` utilisent `_probe_audio_info()` (désormais dans `lib/audio_decision.sh`)
- **Export fonctions codec_profiles.sh** : `get_codec_encoder`, `get_codec_suffix`, `is_codec_better_or_equal`, etc.
- **Suppression fallbacks `declare -f`** dans `config.sh`, `conversion.sh`, `transcode_video.sh`, `video_params.sh`

#### 3. Nettoyage code et duplications
- **config.sh** : Initialisation `CRF_VALUE=21` par défaut (évite variable non définie)
- **transcode_video.sh** : Suppression `_get_encoder_params_flag_internal()` (dupliquait codec_profiles.sh)
- **system.sh** : Factorisation extraction hint suffixe avec `_extract_suffix_hint()`
- **utils.sh** : Fallback hash remplacé par `cksum` (POSIX portable)

#### 4. Amélioration maintenabilité (branche `refactor/improve-maintainability`)
- **finalize.sh** : 
  - Création `_count_log_pattern()` pour factoriser 6 appels grep similaires
  - Création `_calculate_space_savings()` pour isoler le calcul d'économie d'espace
  - `show_summary()` réduite de ~150 à ~70 lignes
- **video_params.sh** : 
  - Suppression `compute_output_height()` et `compute_effective_bitrate()` (wrappers jamais utilisés)
- **audio_decision.sh** : `_get_smart_audio_decision()` (ex-audio_params.sh) déjà bien structurée avec early-returns

### Bilan
- **~180 lignes supprimées** (duplications, fallbacks, wrappers)
- **542 tests passent** (100%)
- Code plus maintenable et portable

### Améliorations restantes (optionnelles)
| Fichier | Amélioration | Effort |
|---------|-------------|--------|
| `utils.sh` | Créer `safe_grep_count()` pour factoriser grep -c | 15 min |

### Derniers prompts
- "continue"

### Branches en cours
- `refactor/improve-maintainability` - prêt à merger
