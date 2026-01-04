# Logique “smart codec” (audio & vidéo)

Ce document explique *pourquoi* le script peut **skip**, **copier** (passthrough) ou **convertir**.

## Audio (cible par défaut : AAC)

- Le codec audio cible par défaut est `aac`.
- Le script évite les conversions inutiles (anti-upscaling) : il ne convertit que si le gain est réel.

### Décisions (résumé fidèle au comportement)

Règles principales :

- Si `--audio copy` : l’audio est toujours copié.
- Si la source est **lossless** (FLAC, TrueHD) : toujours copié.
- Si la source est déjà le **même codec** que la cible :
	- copié si bitrate $\le$ cible,
	- downscale si bitrate $>$ 110% de la cible,
	- sinon copié (marge anti “micro-conversions”).
- Si la source est un codec jugé **efficace** (Opus/AAC/Vorbis) : copié, avec downscale possible si trop haut.
- Sinon : conversion vers le codec cible (par défaut `aac`).

Pour forcer la conversion (bypass smart) : `--force-audio`.

### Gestion des canaux audio (multicanal)

Le script gère automatiquement le nombre de canaux audio selon le mode :

| Mode | Source | Résultat |
|------|--------|----------|
| `serie` | Stéréo (2ch) | Stéréo |
| `serie` | 5.1 (6ch) | **Downmix → Stéréo** |
| `serie` | 7.1 (8ch) | **Downmix → Stéréo** |
| `film` / `film-adaptive` | Stéréo (2ch) | Stéréo |
| `film` / `film-adaptive` | 5.1 (6ch) | **Préservé 5.1** |
| `film` / `film-adaptive` | 7.1 (8ch) | **Réduit → 5.1** |

**Pourquoi ?**
- **Mode série** : priorité à l'économie d'espace. La stéréo suffit pour un visionnage sur PC/tablette/mobile.
- **Mode film** : priorité à la qualité. Le 5.1 permet de profiter d'un système home cinema.

Cette logique s'applique uniquement lors d'une **conversion** (`convert` ou `downscale`). Si l'audio est copié (`copy`), les canaux sont conservés tels quels.

### Hiérarchie (efficacité)

La logique s’appuie sur un rang d’efficacité (voir `get_audio_codec_rank()` dans [lib/audio_params.sh](../lib/audio_params.sh)) :

- Opus (très efficace)
- AAC (efficace)
- Vorbis (efficace)
- E-AC3 / AC3 / DTS / MP3 / PCM… (moins efficaces)

## Vidéo (cible par défaut : HEVC)

- Codec vidéo cible par défaut : `hevc`.
- Un codec “meilleur ou égal” au codec cible peut être conservé si le bitrate est raisonnable.
- Si la vidéo est OK mais l’audio peut être optimisé, le script peut faire du **video passthrough**.

Pour forcer le ré-encodage : `--force-video`.

### Hiérarchie des codecs vidéo (règle générale)

Le script compare le codec source au codec cible via une hiérarchie d’efficacité :

AV1 > HEVC > VP9 > H.264 > MPEG4

### Seuils & tolérance de skip

La décision “skip car déjà optimisé” utilise une tolérance :

$$\text{seuil} = \mathrm{MAXRATE}_{\mathrm{KBPS}} \times \left(1 + \frac{\text{SKIP\\_TOLERANCE\\_PERCENT}}{100}\right)$$

`MAXRATE_KBPS` dépend :
- du mode (`serie` / `film`),
- du codec cible (efficacité codec),
- et éventuellement d’une adaptation par résolution (voir [CONFIG.md](CONFIG.md)).

### Cas usuels (simplifiés)

- Source meilleur ou égal au codec cible + bitrate raisonnable : **skip** (conserver)
- Source meilleur ou égal mais bitrate trop élevé : **encode**
- Source moins bon que cible : **encode**
- Vidéo conforme mais audio perfectible : **video passthrough** (vidéo copiée, audio traité)

Pour forcer : `--force-video`.

## Options `--force`

- `--force-audio` : bypass des décisions smart audio
- `--force-video` : bypass des décisions smart vidéo
- `--force` : active les deux

## Notes

Les seuils exacts et la logique fine dépendent du mode, de la résolution et des paramètres d’encodage.

Pour une lecture “code source” :
- Audio : [lib/audio_params.sh](../lib/audio_params.sh)
- Vidéo : [lib/video_params.sh](../lib/video_params.sh), [lib/transcode_video.sh](../lib/transcode_video.sh)
