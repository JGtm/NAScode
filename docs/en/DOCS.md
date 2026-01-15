# NAScode Documentation

This section contains detailed documentation. The [main README](../../README.en.md) is intentionally kept short.

## Guides

- Usage (options + examples): [USAGE.md](USAGE.md)
- Configuration (modes, variables, codecs, off-peak): [CONFIG.md](CONFIG.md)
- "Smart codec" logic (audio/video, thresholds, `--force`): [SMART_CODEC.md](SMART_CODEC.md)
- FFmpeg samples (edge cases): [SAMPLES.md](SAMPLES.md)
- Architecture & modules: [ARCHITECTURE.md](ARCHITECTURE.md)

Code reference (audio):
- "Smart codec" decision: [../../lib/audio_decision.sh](../../lib/audio_decision.sh)
- FFmpeg/layout construction: [../../lib/audio_params.sh](../../lib/audio_params.sh)
- Troubleshooting (FFmpeg, Windows/macOS, VMAF, logs): [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)

## Dev (contrib)

- Tests (Bats): `bash run_tests.sh`
- Lint (ShellCheck): `make lint`

## Existing docs

- Adding a codec: [ADDING_NEW_CODEC.md](ADDING_NEW_CODEC.md)
- macOS notes: [Instructions-Mac.txt](../Instructions-Mac.txt)
