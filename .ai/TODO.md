# TODO

## Vidéo

- Étudier l’ajout d’un **clamp “adaptation par résolution 720p/480p”** au mode `film-adaptive` (plutôt que d’appliquer un % en plus du modèle BPP×C).
  - Option préférée : limiter `ADAPTIVE_MAXRATE_KBPS` (et `BUFSIZE`) à un plafond dérivé du budget “standard” pour la résolution de sortie, pour éviter les caps trop élevés sur petites résolutions.
  - Attention : éviter le double-compte (la résolution est déjà intégrée au calcul BPP×C).

## Audio

- Réfléchir à un mode “**traduction qualité équivalente**” pour l’audio (analogue à `translate_bitrate_kbps_between_codecs` côté vidéo).
  - Objectif : éviter de gonfler l’audio (ou le ré-encoder inutilement) quand la source est déjà à un débit bas/efficace.

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

