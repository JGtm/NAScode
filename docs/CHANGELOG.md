# Changelog

## v2.6

- ✅ **Audio lossless/premium** : option `--no-lossless` pour forcer la conversion des pistes DTS/DTS-HD, TrueHD, FLAC (désactive le passthrough “premium”)
- ✅ **Audio multicanal** : règles finalisées (downmix 7.1 → 5.1, EAC3 par défaut, Opus multicanal via `-a opus`, AAC multicanal uniquement avec `--force-audio`)
- ✅ **Refactor audio** : séparation claire entre décision (`lib/audio_decision.sh`) et paramètres FFmpeg/layout (`lib/audio_params.sh`)
- ✅ **Refactor “clean code light”** : simplification interne des grosses fonctions (audio/vidéo/VMAF/suffixe) et construction des commandes FFmpeg via tableaux d’arguments (pas de changement UX/CLI attendu)
- ✅ **Tests & docs** : nouveaux tests Bats multicanal + docs alignées (README + docs)

## v2.5

- ✅ **Mode film-adaptive** : bitrate adaptatif basé sur une analyse de complexité
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
