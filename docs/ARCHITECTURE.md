# Architecture

NAScode est un script Bash **modulaire** orienté batch : il indexe une source, construit une file d’attente, puis convertit (ou skip/passthrough) les fichiers selon des règles “smart codec”.

## Vue d’ensemble

- Point d’entrée : [../nascode](../nascode)
- Modules : dossier [../lib/](../lib/)
- Sortie par défaut : `Converted/`
- Logs & artefacts de session : `logs/`

## Flux d’exécution (mode dossier)

1. **Bootstrap & config**
   - Charge les modules dans un ordre de dépendances (UI/config/utils/logging/…)
   - Parse la CLI (source, mode, codec, options)
   - Applique les paramètres du mode via `set_conversion_mode_parameters`

2. **Pré-flight**
   - Lock (évite plusieurs exécutions simultanées)
   - Vérification dépendances (FFmpeg/ffprobe, etc.)
   - Détection hwaccel (si dispo)
   - Vérification VMAF (optionnel)

3. **Index + queue**
   - Construction / réutilisation d’un index persistant (`logs/Index`, `logs/Index_meta`)
   - Construction de la queue (tri/filtre/limite/random)

4. **Traitement parallèle**
   - Démarre `convert_file` en parallèle (jusqu’à `PARALLEL_JOBS`)
   - Progression via “slots” (affichage multi-workers)
   - Mode `--off-peak` : ne lance pas de nouvelles conversions hors plage

5. **Finalisation**
   - Résumé final, logs, nettoyage des temporaires
   - Dry-run : comparaison des noms au lieu d’encoder

## Flux d’exécution (mode fichier unique)

Quand `-f/--file` est fourni, le script bypass index/queue et appelle directement `convert_file` sur un seul fichier.

## Modules principaux (carte)

Le chargement est orchestré par [../nascode](../nascode). Les responsabilités sont globalement :

- **Constantes & fondations**
  - `lib/constants.sh` : magic numbers centralisés (overridables via env)
  - `lib/env.sh` : variables d'environnement

- **CLI & UX**
  - `lib/args.sh` : parsing options
  - `lib/ui.sh` : couleurs/affichage

- **Configuration & profils**
  - `lib/config.sh` : defaults + paramètres par mode
  - `lib/codec_profiles.sh` : mapping codec→encodeur + profils + traduction bitrate

- **Index / queue / traitement**
  - `lib/queue.sh` : index persistant, queue, tri, filtres (`--min-size`, random, limit)
  - `lib/processing.sh` : exécution parallèle (simple / FIFO mode limite)

- **Décision & paramètres média**
  - `lib/media_probe.sh` : probes via ffprobe
  - `lib/audio_decision.sh` : décision audio “smart codec” + multichannel
  - `lib/audio_params.sh` : construit les paramètres FFmpeg audio (codec/layout/bitrate)
  - `lib/video_params.sh` : pix_fmt, downscale, bitrate, suffixe effectif
  - `lib/stream_mapping.sh` : mapping streams (ex: sous-titres)
  - `lib/skip_decision.sh` : logique skip/passthrough/full (décision de conversion)

- **Conversion & pipeline FFmpeg**
  - `lib/conversion_prep.sh` : préparation fichiers, chemins, espace disque, transfert temporaire
  - `lib/adaptive_mode.sh` : analyse complexité pour mode film-adaptive
  - `lib/transcode_video.sh` : exécution FFmpeg (passthrough / CRF / two-pass)
  - `lib/conversion.sh` : orchestration par fichier (appelle les modules ci-dessus)

- **Qualité / analyse**
  - `lib/vmaf.sh` : calcul VMAF (optionnel)
  - `lib/complexity.sh` : analyse pour `film-adaptive`

- **Robustesse & support**
  - `lib/utils.sh` : helpers généraux (paths, tailles, parsing, construction commandes)
  - `lib/logging.sh` : fichiers de log et helpers `log_*`
  - `lib/lock.sh` : lockfile + stop flag
  - `lib/system.sh` / `lib/detect.sh` : checks système, détection outils
  - `lib/off_peak.sh` : logique heures creuses
  - `lib/finalize.sh` : résumé, cleanup
  - `lib/exports.sh` : export des fonctions/variables pour les sous-processus

## Artefacts (logs/Index/lock)

- **Index**
  - `logs/Index` : index (format interne)
  - `logs/Index_meta` : métadonnées (SOURCE, date, etc.)
  - `logs/Index_readable_*.txt` : versions lisibles

- **Queue**
  - `logs/Queue` / `logs/Queue.full` : files null-separated

- **Lock / stop**
  - Lockfile : `/tmp/conversion_video.lock`
  - Stop flag : `/tmp/conversion_stop_flag`

## Tests

- Harness : [../run_tests.sh](../run_tests.sh)
- Tests : dossier [../tests/](../tests/)
- Les tests sont principalement des tests Bats (unitaire + régressions + e2e).

## Pour aller plus loin

- Usage : [USAGE.md](USAGE.md)
- Config : [CONFIG.md](CONFIG.md)
- Smart codec : [SMART_CODEC.md](SMART_CODEC.md)
- Dépannage : [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Ajouter un codec : [ADDING_NEW_CODEC.md](ADDING_NEW_CODEC.md)
