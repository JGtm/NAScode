# Changelog

## v2.4 (Décembre 2025)

- ✅ **Audio multi-codec** : option `-a/--audio` pour choisir AAC, AC3, Opus ou copy
- ✅ **Logique anti-upscaling** : ne convertit l'audio que si gain réel (>20%)
- ✅ Bitrates optimisés : AAC 160k, AC3 384k, Opus 128k
- ✅ Suffixe audio dans le nom de fichier (`_aac`, `_opus`, etc.)
- ✅ Refactoring audio : nouveau module `audio_params.sh` dédié
- ✅ Aide colorée avec options mises en évidence
- ✅ Affichage codec vidéo dans les paramètres actifs

## v2.3 (Décembre 2025)

- ✅ **Support multi-codec vidéo** : option `-c/--codec` pour choisir HEVC ou AV1
- ✅ Nouveau module `codec_profiles.sh` pour configuration modulaire des encodeurs
- ✅ Support libsvtav1 et libaom-av1 pour AV1
- ✅ Suffixe dynamique par codec (`_x265_`, `_av1_`)
- ✅ Skip automatique adapté au codec cible
- ✅ Validation encodeur FFmpeg avant conversion

## v2.2 (Décembre 2025)

- ✅ Option `-f/--file` pour convertir un fichier unique (bypass index/queue)
- ✅ Affichage du gain de place total dans le résumé final (avant → après, économie en %)
- ✅ Amélioration fiabilité pipefail et nettoyage fichiers temporaires

## v2.1 (Décembre 2025)

- ✅ Mode film optimisé qualité (two-pass 2035 kbps, keyint=240)
- ✅ GOP différencié : 240 frames (film) vs 600 frames (série)
- ✅ Tune fastdecode optionnel (activé série, désactivé film)
- ✅ Tests refactorisés : comportement vs valeurs en dur
- ✅ Affichage tests condensé avec progression temps réel

## v2.0 (Décembre 2025)

- ✅ Nouveaux paramètres x265 optimisés pour le mode série
- ✅ Pass 1 rapide (`no-slow-firstpass`) pour gain de temps
- ✅ Préparation conversion audio Opus 128k (désactivé temporairement)
- ✅ Amélioration gestion VMAF (détection fichiers vides)
- ✅ Suffixe dynamique avec indicateur `_tuned`
