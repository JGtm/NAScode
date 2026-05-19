# Plan d'optimisation AV1 — feuille de route

Document de travail pour la spécialisation perceptuelle AV1 (SVT-AV1) et la
préparation des codecs successeurs (H.266 / AV2). Tient lieu de mémoire de
décisions et de roadmap technique. À mettre à jour au fil des phases.

Auteur initial : Guillaume / Claude
Date : 2026-05

---

## 0. Contexte et état des lieux

### Stack actuelle (mai 2026)
- **Encodeur AV1** : `libsvtav1` linké dans FFmpeg, version `SVT-AV1 Encoder Lib
  v3.1.0-194-g090bdfba` (build Nov 2025, **mainline AOMediaCodec**, pas le fork
  Essential).
- **Modes NAScode** : `serie`, `film`, `adaptatif` — voir
  [CONFIG.md](CONFIG.md) et [ADAPTATIF.md](ADAPTATIF.md).
- **Pipeline** : ffmpeg in-process via `-c:v libsvtav1 -svtav1-params "..."`.

### Patches récents appliqués (sprint scènes sombres mode série)
- [lib/video_params.sh](../lib/video_params.sh) :
  `_select_output_pix_fmt` force `yuv420p10le` quand l'encodeur cible est
  `libsvtav1`, indépendamment du pix_fmt source.
- [lib/codec_profiles.sh:256](../lib/codec_profiles.sh#L256) :
  profil série SVT-AV1 enrichi à
  `tune=0:enable-overlays=1:variance-boost-strength=3:luminance-qp-bias=20:sharpness=1`.
  **Note** : `film-grain=4` a été testé puis **retiré** suite à un slowdown
  d'encodage massif (~10×, voir §Bisection ci-dessous).
- [lib/codec_profiles.sh:337](../lib/codec_profiles.sh#L337) +
  [lib/config.sh:328](../lib/config.sh#L328) : `FILM_KEYINT` série
  600 → 360 frames (~15 s @ 24 fps).
- `SVTAV1_LP_DEFAULT=6` par défaut : force le `lp=6` (max) plutôt que de
  laisser SVT-AV1 auto-détecter `lp=5`. Gain CPU modeste (~67°C → ~80°C),
  surtout utile pour exploiter la marge thermique sur les X3D.
- Tests bats : suite complète 80/80 sur codec_profiles (906+ total).

### Bisection 2026-05-19 — `film-grain` coupable du slowdown

Test sur 9000-series X3D, 1080p single-pass CRF :

| Configuration | Speed | Temp CPU |
|---|---|---|
| Baseline avant 5 patches | ~x10 | ~70°C |
| Avec 5 patches + lp=5 (auto) | **x0.85** | ~80°C |
| Avec 5 patches + lp=6 | x0.85 (idem) | ~80°C |
| 5 patches **moins** film-grain + lp=5 | **x8-9** | ~67°C |
| 5 patches **moins** film-grain + lp=6 | x8-9 | ~80°C |

**Conclusion** :
- `film-grain=4` multiplie seul le temps d'encodage par ~10×. Analyse de la
  grain table SVT-AV1 extrêmement coûteuse, particulièrement combinée à
  d'autres params perceptuels. Retiré du profil `serie`.
- `lp=6` vs `lp=5` impact CPU réel mais speed équivalent ; on garde lp=6 par
  défaut pour exploiter la marge thermique X3D, sans coût qualité ni temps.
- Les 4 autres params perceptuels (variance-boost, luma-bias, sharpness,
  10-bit forcé) ont un coût marginal acceptable (~+10-15% temps cumulé).

### Comparaison mainline v3.1 vs Essential v4.0.1

Le fork **SVT-AV1-Essential** (par nekotrix, dernière release 2026-03-14)
modifie certains défauts dans une direction "qualité perceptuelle" et ajoute
des paramètres nouveaux. Sont fournis des binaires **Windows officiels**
(`SvtAv1EncApp.exe`, ~6.7 Mo) — pas besoin de compiler.

| Aspect | Mainline v3.1 | Essential v4.0.1 |
|---|---|---|
| Bit-depth | 8 ou 10 selon source | **10 forcé** |
| `variance-boost-strength` défaut | 2 | 1 |
| `luminance-qp-bias` défaut | 0 | 10 |
| `sharpness` défaut | 0 | 1 |
| `film-grain` | OK | déprécié → `--photon-noise` |
| `--enable-tf` | 0/1 | 0/1/2/**3** |
| `--enable-alt-cdef`, `--enable-alt-dlf` | absent | présent |
| `--photon-noise-chroma` | absent | présent |
| `--ac-bias` | défaut 0 | défaut 0.25 |
| Distortion-bias preset | absent | présent |
| Quarter-step CRF | absent | présent (CRF 21.25 etc.) |
| `--zones` (per-segment params) | absent | présent |

### Hypothèse architecturale
On ne refactorise **pas** l'app pour ne devenir compatible que AV1. La couche
`get_encoder_mode_params encoder mode` dans `lib/codec_profiles.sh` reste le
point d'extension pour les futurs codecs (libvvenc pour H.266, libsvtav2 pour
AV2). Cf. section "Préparation codecs successeurs" en fin de document.

---

## Phase A — Rétroportage des défauts Essential sur mainline

**Objectif** : aligner les modes `film` et `adaptatif` sur la philosophie
"qualité perceptuelle" déjà appliquée au mode `serie`, en utilisant uniquement
des paramètres supportés par le mainline SVT-AV1 v3.x actuellement installé.
**Pas de changement architectural**, juste des params à ajouter.

**Effort** : ~2 h dont tests bats.
**Risque** : très faible. Tous les params sont déjà supportés et testés.

### A.1 — Profil `film` (libsvtav1)

État actuel ([codec_profiles.sh:258](../lib/codec_profiles.sh#L258)) :
```
tune=0:enable-overlays=1:film-grain=8:film-grain-denoise=0
```

Cible :
```
tune=0:enable-overlays=1:film-grain=8:film-grain-denoise=0:variance-boost-strength=2:luminance-qp-bias=15:sharpness=1:enable-qm=1:qm-min=0
```

Rationale :
- `variance-boost-strength=2` : on **garde le défaut** (vs serie=3) car le
  `film-grain=8` compense déjà partiellement la perte sur zones plates.
  Pas la peine de cumuler.
- `luminance-qp-bias=15` : moins agressif que serie (20) pour la même raison.
- `sharpness=1` : préserve un poil plus de détail fin. Gratuit.
- `enable-qm=1:qm-min=0` : active les quantization matrices et autorise QM
  minimal à 0. Défaut Essential. Coût taille négligeable, gain qualité visible
  sur les textures fines.

### A.2 — Profil `adaptatif` (libsvtav1)

État actuel ([codec_profiles.sh:261](../lib/codec_profiles.sh#L261)) :
```
tune=0:enable-overlays=0:film-grain=0
```

Cible :
```
tune=0:enable-overlays=0:film-grain=0:variance-boost-strength=3:luminance-qp-bias=15:sharpness=1:enable-qm=1:qm-min=0
```

Rationale :
- **`enable-overlays=0` et `film-grain=0` restent** : contrainte documentée
  ([codec_profiles.sh:259](../lib/codec_profiles.sh#L259)) — combinaison
  HWACCEL + overlays/grain provoque crash RAM/VRAM. Ne pas y toucher tant que
  ce code path existe.
- `variance-boost-strength=3` : compense l'absence de film-grain pour les
  scènes sombres, identique au mode série.
- `luminance-qp-bias=15` : valeur intermédiaire (films + séries adaptatifs).
- `sharpness=1` : idem.
- `enable-qm=1:qm-min=0` : idem mode film.

### A.3 — Tests bats à ajouter

Dans `tests/test_codec_profiles.bats`, dupliquer le pattern des tests série
pour les nouveaux contrats `film` et `adaptatif` :

```bats
@test "get_encoder_mode_params: libsvtav1 film active luminance-qp-bias=15" { ... }
@test "get_encoder_mode_params: libsvtav1 film active variance-boost-strength=2" { ... }
@test "get_encoder_mode_params: libsvtav1 film active sharpness=1" { ... }
@test "get_encoder_mode_params: libsvtav1 film active enable-qm=1" { ... }
@test "get_encoder_mode_params: libsvtav1 adaptatif active variance-boost-strength=3" { ... }
@test "get_encoder_mode_params: libsvtav1 adaptatif active luminance-qp-bias=15" { ... }
@test "get_encoder_mode_params: libsvtav1 adaptatif active sharpness=1" { ... }
@test "get_encoder_mode_params: libsvtav1 adaptatif active enable-qm=1" { ... }
@test "get_encoder_mode_params: libsvtav1 adaptatif garde enable-overlays=0" { ... }  # protection contre régression crash
@test "get_encoder_mode_params: libsvtav1 adaptatif garde film-grain=0" { ... }       # idem
```

### A.4 — Validation
- Encoder 1 épisode témoin (scène nocturne connue) en mode `serie` puis `film`,
  comparer A/B avec l'état d'avant Phase A.
- Pas de cap taille : on accepte le surcoût modeste (~+1-3%) sur film et
  adaptatif, comme déjà acté sur serie.

### A.5 — Critères de succès Phase A
- [ ] Tests bats verts (suite complète 906+ tests).
- [ ] Diff visuel A/B sur 1 épisode et 1 film montre amélioration des noirs
  sans régression sur scènes lumineuses dynamiques.
- [ ] Commit unique "feat(av1): rétroporte les défauts perceptuels Essential
  sur les profils film et adaptatif".

---

## Phase B — Intégration optionnelle du fork Essential

**Objectif** : permettre à NAScode d'utiliser le binaire
`SvtAv1EncApp-4.0.1-Essential-Windows_Optimized.exe` quand il est présent dans
le PATH (opt-in transparent), tout en gardant le fallback `libsvtav1` mainline
pour les machines qui n'ont pas le fork.

**Effort** : 1-2 semaines de refactor + tests + doc d'installation.
**Risque** : modéré. Changement architectural significatif sur le pipeline
ffmpeg.

### B.1 — Détection runtime

Ajouter une fonction `detect_svtav1_essential` dans `lib/codec_profiles.sh` :

```bash
detect_svtav1_essential() {
    local bin="${SVTAV1_ESSENTIAL_BIN:-SvtAv1EncApp}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo ""
        return 1
    fi
    # Essential dump contient "-Essential" dans la version string
    local ver
    ver=$("$bin" --version 2>&1 | head -3)
    if [[ "$ver" =~ Essential ]]; then
        echo "$bin"
        return 0
    fi
    echo ""
    return 1
}
```

Set `SVTAV1_USE_ESSENTIAL=true` automatiquement si détecté, ou via flag CLI
`--essential` pour forcer.

### B.2 — Refactor du pipeline d'encodage

Architecture cible :
```
ffmpeg -i <input> [filters] -f yuv4mpegpipe -pix_fmt yuv420p10le -
    | SvtAv1EncApp -i stdin --params... -b stdout
    | ffmpeg -i pipe:0 [audio passthrough/transcode] -c:v copy <output>
```

Points d'attention :
- **Audio + sous-titres** : doivent toujours transiter par ffmpeg. La sortie
  IVF/raw AV1 de SvtAv1EncApp doit ensuite être muxée avec le pipeline audio
  via un second ffmpeg.
- **Progress reporting** : SvtAv1EncApp écrit son progress sur stderr (format
  différent de ffmpeg). À parser dans `_start_progress_watcher`
  ([lib/ffmpeg_pipeline.sh:186](../lib/ffmpeg_pipeline.sh#L186)).
- **Two-pass** : Essential supporte two-pass via `--stats <file>`. La
  séquence devient :
  ```
  SvtAv1EncApp --pass 1 --stats stats.bin ...
  SvtAv1EncApp --pass 2 --stats stats.bin ...
  ```
  À orchestrer dans `_execute_ffmpeg_pipeline`.

### B.3 — Mapping des paramètres mainline → Essential

Réécriture par mode dans `get_encoder_mode_params` quand Essential est actif :

| Profil | Mainline (svtav1-params) | Essential (CLI args) |
|---|---|---|
| `serie` | `tune=0:enable-overlays=1:variance-boost-strength=3:luminance-qp-bias=20:film-grain=4:sharpness=1` | `--tune 0 --enable-overlays 1 --variance-boost-strength 3 --luminance-qp-bias 20 --photon-noise 4 --photon-noise-chroma 1 --sharpness 1 --enable-tf 3 --enable-alt-cdef 1 --enable-alt-dlf 1` |
| `film` | `tune=0:enable-overlays=1:film-grain=8:film-grain-denoise=0:variance-boost-strength=2:luminance-qp-bias=15:sharpness=1:enable-qm=1:qm-min=0` | `--tune 0 --enable-overlays 1 --photon-noise 20 --photon-noise-chroma 1 --variance-boost-strength 2 --luminance-qp-bias 15 --sharpness 1 --enable-qm 1 --qm-min 0 --enable-tf 3 --enable-alt-cdef 1 --enable-alt-dlf 1 --ac-bias 0.25` |
| `adaptatif` | `tune=0:enable-overlays=0:film-grain=0:variance-boost-strength=3:luminance-qp-bias=15:sharpness=1:enable-qm=1:qm-min=0` | `--tune 0 --enable-overlays 0 --variance-boost-strength 3 --luminance-qp-bias 15 --sharpness 1 --enable-qm 1 --qm-min 0 --enable-tf 2 --ac-bias 0.25` (`--photon-noise` à tester, risque crash similaire) |

**Note `photon-noise`** : remplace `film-grain`. Échelle ~0-50, "noise level"
mesuré en ISO-photographique. Mode `film` mérite des tests avec valeur 15-30
selon le grain visé. Mode `serie` à valeur basse (4-8) pour ne pas alourdir.

### B.4 — Documentation install pour utilisateur final

Ajouter une section dans [TROUBLESHOOTING.md](TROUBLESHOOTING.md) :
- Télécharger `SvtAv1EncApp-4.0.1-Essential-Windows_Optimized.exe` depuis
  https://github.com/nekotrix/SVT-AV1-Essential/releases
- Renommer en `SvtAv1EncApp.exe`
- Placer dans un dossier du PATH (`C:\bin\` typique sous MSYS2 ou Windows pur)
- Vérifier : `SvtAv1EncApp --version` doit afficher `-Essential` dans la
  chaîne.

### B.5 — Tests
- Ajouter un nouveau fichier `tests/test_essential_mode.bats` avec skip si
  Essential non détecté (pattern déjà utilisé pour autres tests
  conditionnels).
- Tests minimaux : détection, params mapping, fallback gracieux quand
  Essential n'est pas dispo.

### B.6 — Critères de succès Phase B
- [ ] Détection Essential fiable (pas de faux positifs / négatifs).
- [ ] Fallback mainline transparent si Essential pas dispo.
- [ ] 1 encode complet OK en mode Essential pour les 3 modes (serie, film,
  adaptatif).
- [ ] Audio + sous-titres correctement muxés.
- [ ] Two-pass fonctionnel.
- [ ] Tests bats verts (suite complète + nouveaux tests).
- [ ] Documentation install à jour.

---

## Phase C — Auto-boost-lite per-segment (variante C, pure Bash)

**Objectif** : implémenter une variante simplifiée d'Auto-Boost-Essential, en
pur Bash + ffmpeg + libvmaf (déjà dans la stack via
[lib/vmaf.sh](../lib/vmaf.sh)), sans Python ni Vapoursynth. Améliore le mode
`adaptatif` en passant de "1 CRF par fichier basé sur stddev/SI/TI" à "1 CRF
par segment basé sur VMAF prédictif".

**Effort** : ~3 jours.
**Risque** : modéré. La concaténation propre de segments AV1 a des pièges
(timestamps, DTS, alignement keyframes).

### C.1 — Algorithme

```
1. Découper l'input en segments de durée fixe (ex. 30s) alignés sur
   keyframes via `ffmpeg -ss/-to -force_key_frames` ou
   `ffmpeg -f segment -segment_time 30 -reset_timestamps 1`.
2. Pour chaque segment, encoder une version "preview rapide" :
   - preset SVT-AV1 maxi (12 = ultra-fast)
   - CRF de référence (ex. 32)
3. Calculer VMAF segment-vs-source-segment via libvmaf.
4. Construire un map `segment_index → ajustement_CRF` :
   - VMAF moyen >= 92 → CRF +2 (économie)
   - VMAF moyen 85-91 → CRF inchangé
   - VMAF moyen 75-84 → CRF -2 (boost)
   - VMAF moyen < 75 → CRF -4 (boost fort)
5. Re-encoder chaque segment avec son CRF ajusté, en config qualité (preset
   réel, params perceptuels).
6. Concaténer via `ffmpeg -f concat -i list.txt -c copy output`.
7. Mux final avec audio + sous-titres via ffmpeg standard.
```

### C.2 — Nouveau mode `adaptatif-vmaf` ou option `--auto-boost`

Deux choix d'intégration :
- **Option A** : nouveau mode `adaptatif-vmaf` dans `lib/config.sh`.
  Pro : isolation, pas d'impact sur l'adaptatif existant. Con : duplication.
- **Option B** : flag `--auto-boost` sur le mode `adaptatif` existant.
  Pro : compose mieux. Con : couplage plus fort.

Recommandation : **option A** pour cette V1, on consolide en option B après
stabilisation.

### C.3 — Modules à créer

- **`lib/segmenter.sh`** : segmentation propre alignée keyframes.
  Fonctions : `_segment_video <input> <duration> <out_dir>`,
  `_concat_segments <list_file> <output>`.
- **`lib/vmaf_predictive.sh`** : encode rapide + mesure VMAF par segment.
  Fonctions : `_quick_encode_segment`, `_measure_vmaf_segment`,
  `_compute_crf_adjustment`.
- **`lib/auto_boost.sh`** : orchestration du pipeline 6 étapes ci-dessus.

### C.4 — Points de vigilance

- **Alignement keyframes** : `ffmpeg -f segment` est plus robuste que `-ss/-to`
  pour la segmentation alignée. Vérifier que le segment_time correspond bien
  au `keyint` (sinon découpe mal placée).
- **Concat AV1** : nécessite tous les segments encodés avec **les mêmes
  paramètres structurels** (résolution, fps, pix_fmt, profile). Seul le CRF
  varie. Garder une checklist explicite.
- **Audio** : ne JAMAIS le passer dans la boucle segmentation. Le mux audio
  se fait une seule fois en fin de pipeline, sur le concat vidéo.
- **Métadonnées / chapitres** : à propager via un dernier mux ffmpeg
  (`-map_metadata 0 -map_chapters 0`).
- **Two-pass au sein des segments** : NE PAS faire — explosion de complexité.
  On reste en single-pass CRF dans chaque segment (le boost se fait via le
  CRF ajusté, pas via two-pass).

### C.5 — Tests bats à créer

- `tests/test_segmenter.bats` : segmentation correcte, alignement keyframes,
  concat sans glitch.
- `tests/test_vmaf_predictive.bats` : mesure VMAF d'un segment connu,
  ajustement CRF selon table.
- `tests/test_auto_boost.bats` : pipeline complet sur 1 sample court (< 1 min),
  vérification que la sortie a la même durée + signal vidéo cohérent.

### C.6 — Tradeoffs documentés

| Aspect | Effet |
|---|---|
| Temps d'encodage | **+50-80%** (passe rapide + métriques + encode final segmenté) |
| Taille fichier | Variable : peut être plus petit (CRF augmenté sur scènes faciles) ou plus gros (CRF abaissé sur scènes dures), généralement **±5%** |
| Qualité perçue | **Gain net** sur les contenus à variance forte (alternance scènes faciles/dures), gain marginal sur contenus uniformes |
| Complexité opérationnelle | Plus de fichiers temporaires, plus d'étapes, plus de points de panne. Logging détaillé indispensable. |

### C.7 — Quand utiliser ce mode

Le mode `adaptatif-vmaf` n'est **pas** un remplaçant universel de `adaptatif`.
Il convient :
- Films d'archivage haute valeur (1 encode, plusieurs visionnages).
- Catalogues hétérogènes (mix scènes faciles/dures par fichier).

Il n'est PAS adapté à :
- Encodages massifs en série (le surcoût temps est rédhibitoire).
- Contenus à complexité homogène (le mode `adaptatif` standard fait le job).

### C.8 — Critères de succès Phase C
- [ ] Pipeline complet fonctionnel sur 1 sample de 5 min.
- [ ] Concat sans artefacts (vérifier visuellement les transitions de
  segments).
- [ ] VMAF global de la sortie >= VMAF de l'adaptatif standard sur le même
  fichier, à taille ±5%.
- [ ] Tests bats verts.
- [ ] Doc utilisateur : ajout d'une section dans
  [USAGE.md](USAGE.md) pour le nouveau mode.

---

## Considérations CPU thermal (transversal aux phases)

Sur AMD Ryzen 9 9000 X3D série, TJmax = ~95°C. Un encodage SVT-AV1 à 70°C en
charge sous-utilise la marge thermique disponible. Trois leviers pour pousser
la machine sans risque, par ordre de simplicité :

### T.1 — Preset SVT-AV1 plus lent
Variable d'env / config : `SVTAV1_PRESET_DEFAULT` (actuellement 8 via
[lib/codec_profiles.sh:34](../lib/codec_profiles.sh#L34) probablement, à
vérifier). Passer de 5 (medium) à 3 (slower) :
- CPU : +50% utilisation
- Temps : +50-100% encodage
- Qualité : **+2-3% bitrate équivalent VMAF** (gratuit)
- Recommandation : **levier #1**, c'est le seul qui apporte aussi un gain
  qualité.

### T.2 — `lp` (Level of Parallelism) — pourquoi ce levier ne marche pas

**Historique** : Avant SVT-AV1 v3.0 (~avril 2024), il existait un paramètre
`LogicalProcessors=N` qui était un **vrai thread count** (range large, on
pouvait mettre 8, 12, 16). Beaucoup de blogs et forums datent de cette
époque et parlent encore de "monter lp à 8 ou plus" — info **obsolète**.

**v3.0 a déprécié `LogicalProcessors`** et l'a remplacé par
`LevelOfParallelism` (alias court `--lp`) avec une **sémantique différente** :
un niveau abstrait [0-6] où l'encodeur décide lui-même du mapping vers les
threads. Quote de la doc officielle Parameters.md :

> LevelOfParallelism (previously LogicalProcessors, which was deprecated in
> v3.0 and replaced with LevelOfParallelism)
> --lp | range [0, 6] | default 0

Test direct sur SVT-AV1 v3.1.0 Nov 2025 (machine de référence) :
```
=== lp=8 ===
Svt[warn]: Level of parallelism supports levels [0-6]. Setting maximum parallelism level.
Svt[warn]: Level of parallelism does not correspond to a target number of processors to use.
```

Sur le 9000-series X3D, auto-détection donne `lp=5`. Forcer `lp=6` peut
gagner marginalement (~5-10% utilisation CPU), pas le saut vers 80°C qu'on
cherchait.

**`LevelOfParallelism=6` via ffmpeg-libsvtav1 ne marche pas** : le nom long
n'est exposé que dans la CLI standalone `SvtAv1EncApp`, pas via `-svtav1-params`.
Erreur observée : `Error parsing option LevelOfParallelism: 6`. Côté ffmpeg,
seul le nom court `lp` est accepté.

**Aucun param SVT-AV1 v3+ n'accepte un thread count explicite**. Le seul
levier "N cores" restant est `--pin N` mais c'est de l'**affinité CPU**
(force sur les N premiers cores → contrainte, pas extension). Pas pertinent
pour pousser le CPU plus haut.

**Conclusion** : T.2 est un **faux levier** dans la pratique. Le vrai gain
CPU passe par T.1 (preset plus lent) ou T.3 (encodages parallèles).

L'infrastructure d'override existe quand même via `SVTAV1_LP_DEFAULT=6` dans
l'env, au cas où l'auto-détection sous-évaluerait sur une machine donnée
(donnerait lp=2 ou 3 alors que la machine peut faire 6).

### T.3 — Encodages parallèles
En mode batch (plusieurs fichiers à traiter), lancer 2 instances ffmpeg
simultanées via xargs/parallel/&. Le X3D digère bien deux SVT-AV1 en parallèle.
- Pas de modif NAScode requise (wrapper externe).
- Gain : ~80% throughput sur deux fichiers vs un.

### T.4 — À ne pas faire
- Désactiver les protections thermiques (CPU TDC/EDC limits BIOS).
- Forcer un TDP supérieur sans vérification VRM/refroidissement.
- Encoder à `pin=0` sans comprendre les implications NUMA/scheduler.

---

## Préparation codecs successeurs (H.266 / AV2)

### H.266 / VVC via libvvenc

`libvvenc` est l'encodeur VVC de référence (Fraunhofer HHI). Disponible
expérimentalement dans FFmpeg récents. Ratio compression cible : **~30%
meilleur que HEVC, ~10-15% meilleur qu'AV1** sur contenu généraliste, mais
encodage 2-3× plus lent à qualité égale vs SVT-AV1.

**Points de transférabilité depuis le travail AV1** :
- Profil perceptuel : libvvenc expose `--qpa` (perceptual QP adaptation, ~=
  luma-bias) et `--qg` (quantization granularity, ~= variance-boost
  philosophique).
- 10-bit forcé : libvvenc gère nativement 10-bit, même décision applicable.
- Film grain : `--film-grain-analysis` génère une SEI message, équivalent
  conceptuel.

**Plan d'ajout** : suivre [ADDING_NEW_CODEC.md](ADDING_NEW_CODEC.md), créer
les profils mode dans `get_encoder_mode_params` en mappant les concepts
perceptuels documentés ici. Estimation : 1-2 semaines après que libvvenc soit
shipped dans les builds Windows FFmpeg standard.

### AV2 (futur)

Spécification AV2 en cours de finalisation (AOM, courant 2026 prévu, à
suivre). Pas de release encodeur stable à date.

**Hypothèse** : `libsvtav2` ou successeur reprendra la philosophie SVT-AV1
en termes d'options. Les concepts (variance-boost, luma-bias, photon-noise)
sont assez universels pour survivre. Le mapping sera probablement direct.

### Garde-fous architecturaux à conserver
- Ne pas hardcoder de noms de params SVT-AV1 hors de `get_encoder_mode_params`.
- Garder la séparation `get_encoder_params_flag` (préfixe `-svtav1-params`,
  `-vvenc-params`, etc.) propre.
- Tests bats par codec, pas des tests "AV1 only".

---

## Suivi des phases

| Phase | État | Date début | Date fin | Notes |
|---|---|---|---|---|
| Pré-phase (5 patches scène sombres série) | Terminé | 2026-05-19 | 2026-05-19 | 906/906 tests verts ; film-grain banni après bisection |
| A — Rétroportage défauts Essential | **Terminé** | 2026-05-19 | 2026-05-19 | Profils film + adaptatif enrichis (qm, ac-bias, perceptual params). 13 nouveaux tests bats. |
| B — Intégration Essential .exe | **Scaffolding terminé** | 2026-05-19 | | Détection runtime, override env, mapping params, doc install. Reste : refactor pipe-based (§B.2) |
| C — Auto-boost-lite per-segment | **Branché en CLI + audio smart** | 2026-05-19 | 2026-05-19 | Mode `adaptatif-vmaf` opérationnel. Pipeline complet : segment → VMAF → CRF adapté → mux audio smart (Opus/AAC/EAC3 selon source). 34 tests verts. |
| Codecs successeurs (H.266) | Veille | | | Quand libvvenc est shipped Windows |

### Détail état des phases (au 2026-05-19)

**Phase A — TERMINÉE.**
- [lib/codec_profiles.sh:268-300](../lib/codec_profiles.sh#L268) : profils
  `serie`, `film`, `adaptatif` enrichis avec base commune
  `enable-qm=1:qm-min=0:ac-bias=0.25` + params perceptuels spécifiques par
  mode.
- 13 tests bats ajoutés ; suite codec_profiles : 91/91 OK.
- Décisions actées : `film-grain` reste BANNI du profil série (coût 10×),
  conservé sur `film` (one-shot d'archive), désactivé sur `adaptatif`
  (crash HWACCEL documenté).

**Phase B — SCAFFOLDING TERMINÉ. Refactor pipe RESTE À FAIRE.**
- [lib/svtav1_essential.sh](../lib/svtav1_essential.sh) : module créé
  avec détection runtime (`detect_svtav1_essential`), helpers
  (`should_use_svtav1_essential`, `get_essential_mode_params`) et stub
  pour le pipeline pipe-based (`_essential_pipe_encode`).
- Mapping params mainline → Essential : OK (photon-noise remplace film-grain,
  ajout de enable-tf=3 / alt-cdef / alt-dlf).
- Documentation install Windows : [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
  section "SVT-AV1-Essential (optional, Phase B)".
- Tests bats : 18 tests dans `tests/test_svtav1_essential.bats`.
- **Ce qui reste à faire** : refactor de `_execute_ffmpeg_pipeline` pour
  utiliser le binaire standalone via pipe YUV4MPEG (§B.2). Estimation
  1-2 semaines de boulot incluant validation manuelle sur les 3 modes,
  gestion two-pass, progress reporting via stderr SvtAv1EncApp.

**Phase C — IMPLÉMENTATION TERMINÉE. Branchement CLI RESTE À FAIRE.**
- [lib/segmenter.sh](../lib/segmenter.sh) : `_segment_video` (via
  `ffmpeg -f segment` aligné keyframes), `_concat_segments` (concat
  demuxer avec paths relatifs pour robustesse MSYS2/Windows),
  `_list_keyframes` (ffprobe packets).
- [lib/vmaf_predictive.sh](../lib/vmaf_predictive.sh) :
  `_quick_encode_segment` (preset 12, CRF 32 par défaut),
  `_measure_vmaf_segment` (réutilise `compute_vmaf_score` de vmaf.sh),
  `_compute_crf_adjustment` (parser table CSV via awk pour gérer floats).
  Table par défaut : `92:+2,85:0,75:-2,0:-4`.
- [lib/auto_boost.sh](../lib/auto_boost.sh) : orchestration
  `auto_boost_encode` 6 étapes. Sortie : vidéo AV1 10-bit only (audio mux
  délégué au caller). `auto_boost_check_prereqs` valide la chaîne de
  dépendances.
- Modules sourcés dans [nascode](../nascode) après vmaf.sh.
- Tests bats : 27 tests dans `tests/test_phase_c_scaffolding.bats` dont
  un test d'intégration end-to-end qui :
  - génère un sample 30s @ 240x144 via `testsrc2` lavfi,
  - lance auto_boost_encode avec segments de 10s (→ 3 segments),
  - vérifie codec=av1, pix_fmt=yuv420p10le, durée 29-31s.
- Validation manuelle smoke test : 3 segments encodés en ~25s, sortie
  AV1 10-bit ~1 Mo pour un sample 30s.
- **Ce qui reste à faire** :
  - **Branchement dans le pipeline CLI** : créer le mode `adaptatif-vmaf`
    dans `lib/config.sh`, l'ajouter à `lib/args.sh` (parsing + help), et
    router `_execute_ffmpeg_pipeline` vers `auto_boost_encode` quand ce
    mode est actif. Sensible — touche au flow audio/sous-titres/metadata.
    Estimation 1-2 jours avec validation manuelle sur fichiers réels.
  - **Mux audio post-encode** : `auto_boost_encode` produit une vidéo
    AV1 only ; le caller doit muxer audio + subs + chapitres + métadata
    depuis la source via un dernier ffmpeg `-map_metadata 0 -map_chapters 0`.
  - **Logs détaillés** : intégrer le pattern de progress NAScode (slot
    UI, watcher progress, etc.).
  - **Edge cases** : fichiers très courts (< AUTO_BOOST_SEGMENT_DURATION),
    fichiers sans keyframes alignées, segments avec VMAF=NA (libvmaf
    indispo).

#### Branchement CLI V1 (2026-05-19) — `adaptatif-vmaf`
- [lib/config.sh](../lib/config.sh) : nouveau mode `adaptatif-vmaf` qui
  hérite du profil SVT-AV1 `adaptatif` (params perceptuels sans
  film-grain), avec `ADAPTIVE_COMPLEXITY_MODE=false` (auto-boost a sa
  propre analyse par segment via VMAF) et `AUTO_BOOST_ENABLED=true`.
- [lib/args.sh](../lib/args.sh) : ligne mode ajoutée au help.
- [lib/conversion.sh](../lib/conversion.sh) : routage étape 7 vers
  `_execute_auto_boost_conversion` quand `AUTO_BOOST_ENABLED=true`.
- [lib/auto_boost.sh](../lib/auto_boost.sh) : nouveau
  `_execute_auto_boost_conversion` wrapper d'intégration :
  1. `auto_boost_encode` → vidéo AV1 only (`*.vonly.mkv`).
  2. Mux ffmpeg final : vidéo copy + audio/subs/metadata/chapters
     depuis l'input source (tout en COPY pour cette V1).
- Tests bats : 8 nouveaux dans `tests/test_phase_c_scaffolding.bats`.

##### §C.9 — Ce qui reste à faire pour une V2 complète
- ~~**Transcodage audio "smart"**~~ — **FAIT 2026-05-19** :
  `_execute_auto_boost_conversion` appelle `_build_audio_params` du module
  audio standard. Décision smart codec NAScode appliquée (copy / Opus /
  AAC / EAC3 / FLAC selon source + cible vidéo). Smoke test validé :
  AC3 5.1 → E-AC3 5.1 avec layout normalisé. Fallback `-c:a copy` si
  le module audio n'est pas chargé.
- ~~**Progress reporting NAScode-style**~~ — **FAIT 2026-05-19** :
  `auto_boost_encode` utilise désormais `print_status` (couleur magenta)
  pour les étapes intermédiaires et `print_error` pour les erreurs.
  Fallback `echo` quand l'UI n'est pas chargée (tests / scripts).
  Le progress per-frame ffmpeg n'est pas encore canalisé via les slots
  `lib/progress.sh` (TODO mineur, peu d'impact UX en mode CLI).
- ~~**Notifications Discord** : `analysis_started` / `analysis_completed`~~
  — **PARTIELLEMENT FAIT** : `analysis_started` émis au début du
  pipeline auto-boost. `analysis_completed` reste à implémenter avec un
  payload pertinent (nombre de segments, deltas CRF moyens, etc.).
- ~~**VMAF final**~~ — **GRATUIT** : `_finalize_conversion_success`
  appelle déjà `_queue_vmaf_analysis "$file_original" "$final_actual"`
  pour tous les modes. Le VMAF global de la sortie auto-boost est donc
  mesuré automatiquement, comme pour les autres modes. Le VMAF par
  segment du pipeline est une métrique interne distincte (qualité
  par scène pour ajuster le CRF).
- **Sample mode** : tester l'interaction `--sample` / `-S` (encode d'un
  échantillon court pour VMAF), à vérifier si le découpage est cohérent
  avec la segmentation auto-boost.

---

## Décisions actées

- **Pas de Phase C originale** (intégration Auto-Boost-Essential Python /
  Vapoursynth) : trop lourd architecturalement vs gain. On fait l'équivalent
  en Bash.
- **Ne pas refuser le surcoût taille modeste** sur les modes serie/film
  perceptuel : "la taille du fichier étant déjà très faible, c'est acceptable
  comme trade-off" (Guillaume, 2026-05-19).
- **Tests bats coupled FR** : pas de NASCODE_LANG=en en CI. Voir memory
  `nascode-tests-locale-fr`.
