# Documentation NAScode

Cette section contient la documentation détaillée. Le [README principal](../README.md) reste volontairement court.

## Index (par besoin)

- Démarrer vite (commandes + options clés) : [USAGE.md](USAGE.md)
- Comprendre l’architecture et les modules : [ARCHITECTURE.md](ARCHITECTURE.md)
- Configuration (modes, variables, codecs, off-peak) : [CONFIG.md](CONFIG.md)
- Logique “smart codec” (audio/vidéo, multicanal, seuils, `--force`) : [SMART_CODEC.md](SMART_CODEC.md)
- Dépannage (FFmpeg, Windows/macOS, VMAF, logs) : [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Changelog : [CHANGELOG.md](CHANGELOG.md)

## Guides contributeur

- Ajouter un codec : [ADDING_NEW_CODEC.md](ADDING_NEW_CODEC.md)
- Notes macOS : [Instructions-Mac.txt](Instructions-Mac.txt)
- Critères de conversion (CSV) : [📋 Tableau récapitulatif - Critères de conversion.csv](📋%20Tableau%20récapitulatif%20-%20Critères%20de%20conversion.csv)

## Références code (points d’entrée)

- Point d’entrée CLI : [../nascode](../nascode)
- Conversion (orchestration fichier) : [../lib/conversion.sh](../lib/conversion.sh)
- Pipeline FFmpeg vidéo : [../lib/transcode_video.sh](../lib/transcode_video.sh)
- Paramètres vidéo (pix_fmt/downscale/bitrate/suffixe) : [../lib/video_params.sh](../lib/video_params.sh)
- Décision audio (smart + multichannel) : [../lib/audio_decision.sh](../lib/audio_decision.sh)
- Paramètres audio (FFmpeg/layout) : [../lib/audio_params.sh](../lib/audio_params.sh)
- File d’attente / index : [../lib/queue.sh](../lib/queue.sh)
- Traitement parallèle : [../lib/processing.sh](../lib/processing.sh)
