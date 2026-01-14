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

## Phases Refactor/Audit (2026-01-15)

Améliorations identifiées lors de l'audit complet du codebase (Phases B+C).

### Phase E : Extraction constantes (priorité haute)

- [ ] Créer `lib/constants.sh` pour regrouper les constantes magiques :
  - Constantes `ADAPTIVE_*` (actuellement dans `complexity.sh`)
  - Seuils audio (`AUDIO_CODEC_EFFICIENT_THRESHOLD`, bitrates par défaut)
  - Tolérances skip (`SKIP_TOLERANCE_PERCENT`)
  - Limites Discord (1900 chars, timeout 10s)
- [ ] Mettre à jour `nascode` pour sourcer `constants.sh` en premier.
- [ ] Vérifier que les overrides utilisateur (`ADAPTIVE_BPP_BASE=...`) fonctionnent toujours.

### Phase F : Refactorisation structurelle (priorité moyenne)

- [x] **audio_decision.sh** : analysé, la fonction `_get_smart_audio_decision()` est déjà bien structurée avec des blocs logiques clairs et des `return 0` explicites. Décomposition en sous-fonctions non nécessaire (closure `_emit_audio_decision` dépend du contexte local).
- [ ] **Globals → Associative arrays** : **REPORTÉ** (v3.0+)
  - Raison : les associative arrays ne peuvent pas être exportés vers des sous-shells (`convert_file` en parallèle)
  - Alternative : conserver les variables séparées, bien documentées dans `lib/constants.sh`
  - Évaluation : le code actuel fonctionne bien, pas de gain majeur à refactoriser maintenant

### Phase D : Documentation (priorité basse — en dernier)

- [ ] **README.md** : vérifier que les options CLI sont à jour, exemples cohérents.
- [ ] **docs/USAGE.md** : documenter les nouveaux paramètres (`--equiv-quality`, modes audio smart).
- [ ] **docs/CONFIG.md** : documenter les constantes `ADAPTIVE_*` (film-adaptive) :
  - `ADAPTIVE_BPP_BASE`, `ADAPTIVE_C_MIN`, `ADAPTIVE_C_MAX`
  - `ADAPTIVE_STDDEV_LOW`, `ADAPTIVE_STDDEV_HIGH`
  - `ADAPTIVE_SAMPLE_DURATION`, `ADAPTIVE_SAMPLE_COUNT`
  - `ADAPTIVE_MARGIN_START_PCT`, `ADAPTIVE_MARGIN_END_PCT`
  - `ADAPTIVE_MIN_BITRATE_KBPS`, `ADAPTIVE_MAXRATE_FACTOR`, `ADAPTIVE_BUFSIZE_FACTOR`
- [ ] **docs/SMART_CODEC.md** : enrichir la doc audio smart codec (multicanal, anti-upscale, equiv-quality).
- [ ] **docs/CHANGELOG.md** : ajouter entrée v2.8 avec les améliorations audit.
- [ ] **docs/ARCHITECTURE.md** : mettre à jour le diagramme de modules (nouveaux modules).
- [ ] **docs/TROUBLESHOOTING.md** : ajouter section notifications Discord (debug, erreurs courantes).

