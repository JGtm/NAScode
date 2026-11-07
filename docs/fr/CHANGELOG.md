# Changelog

## v3.0.2

- ✅ **Conversion figée / épisodes sautés en mode dossier (`-s`)** : `ffmpeg` héritait de la queue comme entrée et lisait les chemins comme des touches. Un « c » ouvrait son invite `Enter command:` : progression figée, `ffmpeg` qui ne se termine jamais (même encodage fini) et reste orphelin à 100 % CPU après Ctrl+C. Sur des fichiers courts, il avalait silencieusement des entrées de la queue (épisodes sautés, sans erreur). Corrigé : `convert_file` tourne avec stdin sur `/dev/null`, et chaque appel `ffmpeg` passe `-nostdin`.
- ✅ **Ctrl+C** : les encodeurs (`ffmpeg`, `ffprobe`, `SvtAv1EncApp`) qui survivent au SIGTERM de groupe reçoivent SIGKILL après ~2 s, dans le vrai groupe de processus même si nascode est lancé derrière un autre programme. Les fichiers temporaires d'un run interrompu (`.in`/`.out`, plusieurs Go) sont supprimés ; les dossiers `work_*` vides ne s'accumulent plus.
- ✅ **Tests** : nouveau `test_regression_ffmpeg_stdin_cleanup.bats` (héritage de stdin, contrat `-nostdin`, arrêt forcé, temporaires du run).

## v3.0.1

- ✅ **macOS — arrêt silencieux avec `-l N`** : sur une grosse queue, `printf | head` recevait SIGPIPE et `pipefail` tuait le script sans message (exit 141). Corrigé en mode normal et aléatoire (`-r`).
- ✅ **macOS — indexation rapide** : le `find` BSD n'a pas `-printf` ; le `find` GNU de Homebrew (`gfind`, `findutils`) est désormais utilisé s'il est présent, au lieu d'un `stat` par fichier. La source n'est plus explorée qu'une fois (comptage + indexation), soit deux fois moins de temps sur un partage NAS.
- ✅ **macOS sans GNU coreutils** : replis portables pour `stat -c` (index existant avec `-k`, progression de copie), `realpath -m` (dossier de sortie), `date -d` (heure de fin avec awk BSD), `\+` propre à GNU `sed` (normalisation des chemins, Discord) et une regex refusée par awk BSD (aperçu de queue Discord).
- ✅ **Tests** : nouveau `test_regression_macos_portability.bats` (SIGPIPE, détection `find`/`gfind`, repli `stat`, exploration unique, `stat` BSD). `run_tests.sh` lance les fichiers en parallèle (`-j N`, défaut = nb de cœurs, `-j 1` = séquentiel) : ~10 min → ~3 min.

## v3.0

- ✅ **Nouveau mode `gaming`** : variante adaptative calibrée pour le high-motion (replays, captures de jeux), cap à 29.97 fps par défaut.
- ✅ **Nouveau mode `adaptatif-vmaf` (AV1)** : CRF adapté par scène via VMAF (« auto-boost-lite », Bash pur), avec progression façon NAScode, notifications Discord et smart codec audio. Encodeur optionnel via pipe `SVT-AV1-Essential` (non combinable avec `adaptatif-vmaf` en V1).
- ✅ **Option `--replace`** : remplace la source par le fichier converti, uniquement après transfert vérifié, gain réel et durée identique ; jamais sur un extrait. Mentionnée au démarrage.
- ✅ **Option `--keep-metadata`** : conserve les métadonnées, les chapitres et la date de modification de la source.
- ✅ **Indexation accélérée** : taille obtenue directement via `find -printf` (plus de `stat` par fichier), compteur en mémoire et affichage de progression limité. Un dossier illisible (ex. `#recycle` du NAS) ne tue plus le run.
- ✅ **Cache des sondes `ffprobe`** : un fichier n'est sondé qu'une fois par run pour des options identiques (invalidé si le fichier change) ; les capacités `ffmpeg` sont aussi mises en cache.
- ✅ **Robustesse** : transfert atomique `.partial` vérifié avant publication, fenêtre TOCTOU du lock fermée (`flock`), `umask 0077` sur les temporaires, webhook Discord hors de l'argv `curl`, course `wait -n` corrigée.
- ✅ **Correctifs** : VMAF lit le vrai `pooled_metrics.vmaf.mean` ; `--limit-fps` cape réellement l'fps ; précédence CLI > preset de mode > env > `.env.local` ; décision audio smart qui re-sonde les canaux (cohérence skip/encode) ; crash des sous-titres PGS sur remux Blu-ray ; segfault x265 4.x `fastdecode` ; parsing SI/TI ; barre de progression (mintty, PGS, fuseau horaire système).
- ✅ **SVT-AV1** : optimisation perceptuelle du profil série, `film-grain` abaissé (8 → 6) sur le profil film, `enable-overlays` / `film-grain` désactivés en mode adaptatif, `SvtAv1EncApp` zombies tués sur SIGINT/SIGTERM.
- ✅ **UX** : l'analyse de complexité SI/TI affiche une barre de progression ; couleurs ANSI émises seulement vers un terminal (`NO_COLOR` respecté).
- ✅ **Outillage dev** : workflow GitHub Actions (lint + Bats), `run_tests.sh` strict (ne peut plus mentir), constantes centralisées (`lib/constants.sh`), export automatique des fonctions, documentation en anglais langue principale (français dans `docs/fr/`).

## v2.9

- ✅ **Internationalisation (i18n)** : système complet de traduction avec support français et anglais. Nouvelle option `--lang <fr|en>` pour choisir la langue de l'interface.
- ✅ **Module i18n** : nouveau module `lib/i18n.sh` avec fonction `msg()` utilisant l'indirection Bash pour les traductions dynamiques.
- ✅ **Fichiers de locale** : `locale/fr.sh` et `locale/en.sh` contenant ~305 messages traduits (CLI, erreurs, logs, notifications Discord).
- ✅ **Documentation traduite** : 10 fichiers de documentation disponibles en anglais dans `docs/en/` (ARCHITECTURE, CHANGELOG, CONFIG, USAGE, TROUBLESHOOTING, etc.).
- ✅ **README bilingue** : `README.md` complet + section i18n dans le README principal (`README.fr.md`).
- ✅ **Auto-chargement i18n** : `ui.sh` charge automatiquement `i18n.sh` si `msg()` n'est pas définie (compatibilité tests/subshells).
- ✅ **Tests i18n** : nouveau fichier `test_i18n.bats` (13 tests) validant le chargement des locales, le fallback, les placeholders et la cohérence des clés.
- ✅ **Tests audio_decision** : nouveau fichier `test_audio_decision.bats` (55 tests) couvrant la logique smart codec audio.
- ✅ **Tests video_params** : nouveau fichier `test_video_params.bats` (36 tests) couvrant pix_fmt, downscale, bitrate adaptatif.
- ✅ **Tests notify enrichis** : `test_notify.bats` étendu de 8 à 19 tests (notify_format.sh).
- ✅ **Mode --fast** : nouvelle option `run_tests.sh --fast` excluant les tests E2E lents (~11 min vs ~15 min).
- ✅ **Couverture tests** : passage de ~728 à ~830 tests, 3 modules critiques couverts (i18n, audio_decision, video_params).

## v2.8

- ✅ **Gestion HFR (High Frame Rate)** : nouvelles options `--limit-fps` / `--no-limit-fps` pour gérer les vidéos >30 fps. En mode série (défaut), les vidéos HFR sont limitées à 29.97 fps pour optimiser la taille. En mode film/adaptatif, le bitrate est ajusté proportionnellement au framerate.
- ✅ **Affichage option HFR** : l'option LIMIT_FPS apparaît dans les paramètres actifs (terminal) et dans la notification Discord `run_started`.
- ✅ **Skip VMAF intelligent** : le score VMAF est automatiquement ignoré lorsque le framerate est modifié (comparaison invalide).
- ✅ **Tests HFR** : 26 tests unitaires + 2 tests e2e pour la gestion HFR.
- ✅ **Constantes centralisées** : nouveau module `lib/constants.sh` regroupant les "magic numbers" (mode adaptatif, seuils audio, paramètres Discord, seuils HFR). Toutes les constantes sont overridables via variables d'environnement.
- ✅ **Robustesse documentation** : documentation systématique de `set -euo pipefail` dans les 38 modules `lib/`.
- ✅ **Tests renforcés** : nouveaux tests unitaires pour `VIDEO_EQUIV_QUALITY_CAP`, `_clamp_min`, `_clamp_max`, `_min3`.
- ✅ **Factorisation bitrate** : fonction `_translate_bitrate_by_efficiency()` centralisée dans `codec_profiles.sh` (audio + vidéo).
- ✅ **Test helpers** : refactoring de `test_helper.bash` (variables standardisées, skip intelligent, modularité).
- ✅ **Documentation** : CONFIG.md enrichi (section constantes), SMART_CODEC.md mis à jour (rangs audio, traduction bitrate).

## v2.7

- ✅ **Robustesse queue / FIFO** : évite les blocages quand aucun fichier n’est traitable (entrées vides, fichiers introuvables, queue invalide) + sortie explicite si la source est exclue.
- ✅ **Notifications Discord (optionnel)** : messages démarrage/pause(off-peak)/fin, payload plus robuste + mode debug opt-in, docs + tests dédiés.
- ✅ **Mode adaptatif fiabilisé** : les budgets calculés sont réellement appliqués à l'encodage (exports) + cap SVT-AV1 en CRF (`mbr=`) et logs debug SVT opt-in.
- ✅ **Vidéo “smart codec”** : seuil de skip codec-aware + politique “no downgrade” (source AV1 ré-encodée en AV1 si nécessaire) + cap “qualité équivalente” sur sources moins efficaces.
- ✅ **UX/CLI** : meilleure cohérence des messages (skip/erreurs early) et option `--quiet` documentée dans les guides.
- ✅ **Dev tooling** : `make lint` (ShellCheck) + nettoyage des warnings, améliore la maintenabilité.
- ✅ **Tests & docs** : ajouts/renforcements Bats (queue, conversion, notifs) + dépannage et guides alignés.

## v2.6

- ✅ **Audio lossless/premium** : option `--no-lossless` pour forcer la conversion des pistes DTS/DTS-HD, TrueHD, FLAC (désactive le passthrough “premium”)
- ✅ **Audio multicanal** : règles finalisées (downmix 7.1 → 5.1, EAC3 par défaut, Opus multicanal via `-a opus`, AAC multicanal uniquement avec `--force-audio`)
- ✅ **Refactor audio** : séparation claire entre décision (`lib/audio_decision.sh`) et paramètres FFmpeg/layout (`lib/audio_params.sh`)
- ✅ **Refactor “clean code light”** : simplification interne des grosses fonctions (audio/vidéo/VMAF/suffixe) et construction des commandes FFmpeg via tableaux d’arguments (pas de changement UX/CLI attendu)
- ✅ **Tests & docs** : nouveaux tests Bats multicanal + docs alignées (README + docs)

## v2.5

- ✅ **Mode adaptatif** : bitrate adaptatif basé sur une analyse de complexité
- ✅ **Filtre de taille** : option `--min-size` pour filtrer l'index/queue (utile en mode film)
- ✅ **Audio multicanal** : normalisation des layouts (stéréo / 5.1) + logique de préservation selon le mode
- ✅ **Windows / Git Bash** : normalisation chemins/CRLF et meilleure robustesse avec caractères spéciaux
- ✅ **VMAF & UX** : ajustements d'affichage + paramètre de subsampling, amélioration des messages et compteurs
- ✅ **Tests** : refactor et optimisations pour exécution plus rapide et plus robuste
- ✅ **Refactor audio** : extraction de la logique “smart codec” dans `lib/audio_decision.sh` (et `lib/audio_params.sh` recentré sur FFmpeg/layout)

## v2.4

- ✅ **Audio multi-codec** : option `-a/--audio` pour choisir AAC, AC3, Opus ou copy
- ✅ **Logique anti-upscaling** : ne convertit l'audio que si gain réel (>20%)
- ✅ Bitrates optimisés : AAC 160k, AC3 384k, Opus 128k
- ✅ Suffixe audio dans le nom de fichier (`_aac`, `_opus`, etc.)
- ✅ Refactoring audio : nouveau module `audio_params.sh` dédié (paramètres FFmpeg/layout)
- ✅ Aide colorée avec options mises en évidence
- ✅ Affichage codec vidéo dans les paramètres actifs

## v2.3

- ✅ **Support multi-codec vidéo** : option `-c/--codec` pour choisir HEVC ou AV1
- ✅ Nouveau module `codec_profiles.sh` pour configuration modulaire des encodeurs
- ✅ Support libsvtav1 et libaom-av1 pour AV1
- ✅ Suffixe dynamique par codec (`_x265_`, `_av1_`)
- ✅ Skip automatique adapté au codec cible
- ✅ Validation encodeur FFmpeg avant conversion

## v2.2

- ✅ Option `-f/--file` pour convertir un fichier unique (bypass index/queue)
- ✅ Affichage du gain de place total dans le résumé final (avant → après, économie en %)
- ✅ Amélioration fiabilité pipefail et nettoyage fichiers temporaires

## v2.1

- ✅ Mode film optimisé qualité (two-pass 2035 kbps, keyint=240)
- ✅ GOP différencié : 240 frames (film) vs 600 frames (série)
- ✅ Tune fastdecode optionnel (activé série, désactivé film)
- ✅ Tests refactorisés : comportement vs valeurs en dur
- ✅ Affichage tests condensé avec progression temps réel

## v2.0

- ✅ Nouveaux paramètres x265 optimisés pour le mode série
- ✅ Pass 1 rapide (`no-slow-firstpass`) pour gain de temps
- ✅ Préparation conversion audio Opus 128k (désactivé temporairement)
- ✅ Amélioration gestion VMAF (détection fichiers vides)
- ✅ Suffixe dynamique avec indicateur `_tuned`
