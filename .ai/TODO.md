# TODO

## Vidéo

- Étudier l'ajout d'un **clamp "adaptation par résolution 720p/480p"** au mode `film-adaptive` (plutôt que d'appliquer un % en plus du modèle BPP×C).
  - Option préférée : limiter `ADAPTIVE_MAXRATE_KBPS` (et `BUFSIZE`) à un plafond dérivé du budget "standard" pour la résolution de sortie, pour éviter les caps trop élevés sur petites résolutions.
  - Attention : éviter le double-compte (la résolution est déjà intégrée au calcul BPP×C).

## Refactorisation future (v3.0+)

- **Globals → Associative arrays** : reporté car les associative arrays ne peuvent pas être exportés vers des sous-shells (`convert_file` en parallèle). Conserver les variables séparées, documentées dans `lib/constants.sh`.

