# Documentation NAScode

Cette section contient la documentation détaillée. Le [README principal](../README.md) reste volontairement court.

## Guides

- Usage (options + exemples) : [USAGE.md](USAGE.md)
- Configuration (modes, variables, codecs, off-peak) : [CONFIG.md](CONFIG.md)
- Logique “smart codec” (audio/vidéo, seuils, `--force`) : [SMART_CODEC.md](SMART_CODEC.md)
- Samples FFmpeg (edge cases) : [SAMPLES.md](SAMPLES.md)- Architecture & modules : [ARCHITECTURE.md](ARCHITECTURE.md)
Référence code (audio) :
- Décision “smart codec” : [../lib/audio_decision.sh](../lib/audio_decision.sh)
- Construction FFmpeg/layout : [../lib/audio_params.sh](../lib/audio_params.sh)
- Dépannage (FFmpeg, Windows/macOS, VMAF, logs) : [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Changelog : [CHANGELOG.md](CHANGELOG.md)

## Dev (contrib)

- Tests (Bats) : `bash run_tests.sh`
- Lint (ShellCheck) : `make lint`

## Docs existantes

- Ajouter un codec : [ADDING_NEW_CODEC.md](ADDING_NEW_CODEC.md)
- Notes macOS : [Instructions-Mac.txt](Instructions-Mac.txt)
- Critères de conversion (CSV) : [📋 Tableau récapitulatif - Critères de conversion.csv](📋%20Tableau%20récapitulatif%20-%20Critères%20de%20conversion.csv)
