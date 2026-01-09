# Samples FFmpeg (edge cases)

Ce guide permet de générer des fichiers **courts** et **reproductibles** via `ffmpeg` (sources `lavfi`) pour tester des cas un peu "edge".

> Les fichiers générés vont dans `samples/_generated/` (ignoré par git).

## Prérequis

- `ffmpeg` sur le PATH
- Encoders :
  - `libx264` pour la plupart des samples
  - `libx265` pour le sample HEVC 10-bit
  - `dca` (DTS) et `truehd` pour les samples premium (si disponibles)

Note : selon ta build `ffmpeg`, `dca` et `truehd` peuvent être marqués *expérimentaux* et nécessiter `-strict -2` (le script le gère).

## Générer les samples

Depuis la racine du repo :

```bash
bash tools/generate_ffmpeg_samples.sh
```

Options utiles :

```bash
# Durée plus courte
bash tools/generate_ffmpeg_samples.sh -d 3

# Écraser les fichiers existants
bash tools/generate_ffmpeg_samples.sh -f

# Un sous-ensemble de cas
bash tools/generate_ffmpeg_samples.sh --only vfr_concat,multiaudio_aac_ac3
```

## Cas générés

- `01_h264_yuv444p_high444.mkv` : H.264 4:4:4 (`yuv444p`), profil High 4:4:4
- `02_av1_low_bitrate.mkv` : AV1 (si `libsvtav1` dispo), utile pour le cas “codec meilleur que HEVC”
- `03_vp9_input.webm` : VP9 (si `libvpx-vp9` dispo), utile pour le cas “codec inférieur à HEVC”
- `04_mpeg4_avi_input.avi` : MPEG4 (conteneur AVI), cas “ancien codec”
- `05_hevc_10bit_bt2020_pq.mkv` : HEVC 10-bit (`yuv420p10le`) + metadata BT.2020/PQ
- `06_hevc_high_bitrate.mkv` : HEVC volontairement très “lourd” pour tester le seuil de re-encodage
- `07_h264_odd_dimensions_853x479.mp4` : dimensions impaires (scaling/alignement)
- `08_h264_rotate90_metadata.mp4` : rotation via metadata (pas un vrai transpose)
- `09_h264_interlaced_meta_tff.mkv` : flags interlaced (TFF) pour tester la détection
- `10_vfr_concat.mkv` : concat 24fps + 30fps (VFR)
- `11_aac_high_bitrate_stereo.mkv` : AAC stéréo à bitrate élevé (cas downscale audio)
- `12_eac3_high_bitrate_5_1.mkv` : EAC3 5.1 à 640k (cas downscale vers 384k en mode film)
- `13_flac_lossless_5_1.mkv` : FLAC 5.1 lossless (cas “lossless copié”, sauf `--no-lossless`)
- `14_pcm_7_1.mkv` : PCM 7.1 (8 canaux) pour tester la réduction multicanal lors d'une conversion
- `15_opus_5_1_224k.mkv` : Opus 5.1 à 224k (codec efficace multicanal, souvent copié)
- `16_multiaudio_aac_stereo_ac3_5_1.mkv` : 2 pistes audio (AAC stéréo + AC3 5.1)
- `17_subtitles_srt.mkv` : sous-titres SRT muxés (MKV)
- `18_dts_5_1.mkv` : DTS 5.1 (premium)
- `19_dts_7_1.mkv` : DTS 7.1 (premium, peut être skip si non supporté)
- `20_truehd_5_1.mkv` : TrueHD 5.1 (premium)
- `21_truehd_7_1.mkv` : TrueHD 7.1 (premium, peut être skip si non supporté)
