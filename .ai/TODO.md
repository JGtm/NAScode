# TODO

## Vidéo

- Étudier l’ajout d’un **clamp “adaptation par résolution 720p/480p”** au mode `film-adaptive` (plutôt que d’appliquer un % en plus du modèle BPP×C).
  - Option préférée : limiter `ADAPTIVE_MAXRATE_KBPS` (et `BUFSIZE`) à un plafond dérivé du budget “standard” pour la résolution de sortie, pour éviter les caps trop élevés sur petites résolutions.
  - Attention : éviter le double-compte (la résolution est déjà intégrée au calcul BPP×C).

## Audio

- ✅ Implémenté : mode “**traduction qualité équivalente**” pour l’audio (analogue à `translate_bitrate_kbps_between_codecs` côté vidéo).
  - Option retenue (1) : **ne jamais dépasser le bitrate source** lors d’un transcodage.
  - Activation : `film-adaptive` ON par défaut, `film`/`serie` OFF (activable).
  - ✅ CLI : `--equiv-quality` / `--no-equiv-quality` (switch global audio + vidéo). `film-adaptive` ignore l’override.

### Mini-spéc (proposition)

**But**
- Quand on a déjà décidé de *transcoder* l’audio, convertir le bitrate “source” vers un bitrate cible “équivalent” pour le codec de sortie.
- Réduire les cas où l’audio grossit “par défaut”, tout en restant conservateur (qualité stable, pas de surprises).

**Invariants (non négociables)**
- La traduction ne s’applique **jamais** si la décision audio est `copy`.
- La traduction ne doit **jamais augmenter** le bitrate au-dessus d’un plafond par mode/codec (configurable).
- Si le bitrate source est inconnu/non-fiable (ex: N/A), on retombe sur la logique actuelle (fallback).

**API / Helper**
- Ajout : `translate_audio_bitrate_kbps_between_codecs <src_codec> <dst_codec> <src_kbps> [channels] [sample_rate]`
  - Retour : `dst_kbps` (entier) ou vide (no-translation).

**Règles (conservatrices)**
- Garder une table de “ratios d’efficacité” par codec (ex: AAC/Opus plus efficaces que AC3).
- Appliquer un clamp :
  - `dst_kbps = round(src_kbps * ratio(src->dst))`
  - puis `dst_kbps = clamp(dst_kbps, AUDIO_MINRATE_KBPS, AUDIO_MAXRATE_KBPS)`
- Optionnel (si facile) : ajuster légèrement selon `channels` (stéréo vs 5.1) et/ou `sample_rate`.

**Activation**
- Flag config : `AUDIO_TRANSLATE_EQUIV_QUALITY=true|false` (surchargé par mode dans `set_conversion_mode_parameters`).

**Tests (Bats)**
- ✅ Ajout : tests unit-like + intégration décision (bypass copy, fallback bitrate inconnu, cap au bitrate source).

## UI (audit messages non centralisés)

- ✅ Harmonisé les messages « décoratifs »/bannières qui utilisaient encore `echo -e`/`printf` en dehors de `lib/ui*.sh`.
  - `lib/off_peak.sh` : bannières / infos “heures creuses” (mise en forme).
  - `lib/index.sh` : messages d’information sur l’index (ex: source changée, détails affichés).
  - `lib/queue.sh` : entêtes “sélection aléatoire”, messages “Aucun fichier…” et affichage contextuel de la queue.
  - `lib/video_params.sh` + `lib/transcode_video.sh` : messages vidéo (downscale 1080p, 10-bit/pix_fmt, etc.).
- Décision : **ne pas centraliser la progress UI** (inchangé).

