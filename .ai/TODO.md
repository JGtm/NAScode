# TODO

## Vidéo

- Étudier l’ajout d’un **clamp “adaptation par résolution 720p/480p”** au mode `film-adaptive` (plutôt que d’appliquer un % en plus du modèle BPP×C).
  - Option préférée : limiter `ADAPTIVE_MAXRATE_KBPS` (et `BUFSIZE`) à un plafond dérivé du budget “standard” pour la résolution de sortie, pour éviter les caps trop élevés sur petites résolutions.
  - Attention : éviter le double-compte (la résolution est déjà intégrée au calcul BPP×C).

## Audio

- Réfléchir à un mode “**traduction qualité équivalente**” pour l’audio (analogue à `translate_bitrate_kbps_between_codecs` côté vidéo).
  - Objectif : éviter de gonfler l’audio (ou le ré-encoder inutilement) quand la source est déjà à un débit bas/efficace.

### Mini-spéc (proposition)

**But**
- Quand on a déjà décidé de *transcoder* l’audio, convertir le bitrate “source” vers un bitrate cible “équivalent” pour le codec de sortie.
- Réduire les cas où l’audio grossit “par défaut”, tout en restant conservateur (qualité stable, pas de surprises).

**Invariants (non négociables)**
- La traduction ne s’applique **jamais** si la décision audio est `copy`.
- La traduction ne doit **jamais augmenter** le bitrate au-dessus d’un plafond par mode/codec (configurable).
- Si le bitrate source est inconnu/non-fiable (ex: N/A), on retombe sur la logique actuelle (fallback).

**API / Helper (idée)**
- Ajouter un helper du style : `translate_audio_bitrate_kbps_between_codecs <src_codec> <dst_codec> <src_kbps> [channels] [sample_rate]`
  - Retourne un `dst_kbps` (entier) ou une valeur spéciale “no-translation”.
  - Helper pur, testable en table-driven.

**Règles (conservatrices)**
- Garder une table de “ratios d’efficacité” par codec (ex: AAC/Opus plus efficaces que AC3).
- Appliquer un clamp :
  - `dst_kbps = round(src_kbps * ratio(src->dst))`
  - puis `dst_kbps = clamp(dst_kbps, AUDIO_MINRATE_KBPS, AUDIO_MAXRATE_KBPS)`
- Optionnel (si facile) : ajuster légèrement selon `channels` (stéréo vs 5.1) et/ou `sample_rate`.

**Activation (recommandé)**
- Rendre la fonctionnalité **disponible dans tous les modes**, mais activable par config.
- Par défaut :
  - `film-adaptive` : ON
  - `film` : OFF (mais activable)
  - `serie` : OFF (mais activable)
- Ajouter un flag config du type : `AUDIO_TRANSLATE_EQUIV_QUALITY=1|0` (avec overrides par mode si le système le permet).

**Tests (Bats)**
- Unit-like (helper pur) : table de cas `src/dst codec + kbps` → assert sur propriétés (pas d’augmentation, clamp respecté, fallback).
- Intégration décision : vérifier que “copy” bypass toujours la traduction.
- Cas divers : AAC bas débit, AC3 haut débit, EAC3, Opus, stéréo vs 5.1.

## Gestion des sorties plus lourdes

- Définir une stratégie quand le fichier converti est **plus lourd que l’original** (ou quand le gain est **< 10%** vs l’original).
  - Le seuil (ex: `10%`) doit être **configurable dans la config** pour ajustement manuel facile.
  - Option A : ne pas transférer et marquer l’item comme “heavy”.
  - Option B : déclencher une re-conversion avec paramètres plus stricts.
  - Option C : transférer vers un dossier séparé (ex: `Converted_Heavier/`) **en conservant obligatoirement l’architecture de répertoires cible**.

## UI (audit messages non centralisés)

- Harmoniser les messages « décoratifs »/bannières qui utilisent encore `echo -e`/`printf` en dehors de `lib/ui*.sh`.
  - `lib/off_peak.sh` : bannières / infos “heures creuses” (mise en forme).
  - `lib/index.sh` : messages d’information sur l’index (ex: source changée, détails affichés).
  - `lib/queue.sh` : entêtes “sélection aléatoire”, messages “Aucun fichier…” et affichage contextuel de la queue.
  - `lib/video_params.sh` + `lib/transcode_video.sh` : messages vidéo (downscale 1080p, 10-bit/pix_fmt, etc.).
- Décider si on centralise aussi la **progress UI** (plus risqué car dépend de TTY / rafraîchissement en place).
  - `lib/progress.sh` : barres/compteurs en `printf`.
  - `lib/vmaf.sh` : progression + affichage des stats.
  - `lib/finalize.sh` : récap / progress/printf.

