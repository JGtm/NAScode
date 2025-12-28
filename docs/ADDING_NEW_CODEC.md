# Guide : Ajouter un nouveau codec

Ce document décrit les étapes pour ajouter le support d'un nouveau codec vidéo (ex: H.266/VVC).

---

## 📋 Checklist rapide

- [ ] `lib/codec_profiles.sh` — Fonctions codec/encoder + efficacité
- [ ] `lib/args.sh` — Validation CLI `--codec`
- [ ] `tests/test_codec_profiles.bats` — Tests unitaires codec
- [ ] `tests/test_transcode_video.bats` — Tests encoding
- [ ] `tests/test_args.bats` — Tests validation CLI
- [ ] `README.md` — Documentation utilisateur

---

## 1. lib/codec_profiles.sh

### 1.1 `get_codec_encoder()`

Ajouter le mapping codec → encoder FFmpeg.

```bash
get_codec_encoder() {
    case "${1:-hevc}" in
        hevc|h265) echo "libx265" ;;
        av1)       echo "libsvtav1" ;;
        vvc|h266)  echo "libvvenc" ;;  # ← AJOUTER
        *)         echo "libx265" ;;
    esac
}
```

### 1.2 `get_codec_suffix()`

Définir le suffixe fichier (vide = pas de suffixe additionnel).

```bash
get_codec_suffix() {
    case "${1:-hevc}" in
        hevc|h265) echo "" ;;
        av1)       echo "av1" ;;
        vvc|h266)  echo "vvc" ;;  # ← AJOUTER
        *)         echo "" ;;
    esac
}
```

### 1.3 `is_codec_match()`

Ajouter les variantes de nommage (ffprobe peut retourner différents noms).

```bash
is_codec_match() {
    local detected="$1" target="$2"
    case "$target" in
        hevc) [[ "$detected" =~ ^(hevc|h265|x265)$ ]] ;;
        av1)  [[ "$detected" =~ ^(av1|av01|libaom|svtav1)$ ]] ;;
        vvc)  [[ "$detected" =~ ^(vvc|h266|vvenc)$ ]] ;;  # ← AJOUTER
        *)    [[ "$detected" == "$target" ]] ;;
    esac
}
```

### 1.4 `is_codec_supported()`

Ajouter le codec à la liste.

```bash
is_codec_supported() {
    case "$1" in
        hevc|h265|av1|vvc|h266) return 0 ;;  # ← AJOUTER vvc|h266
        *) return 1 ;;
    esac
}
```

### 1.5 `list_supported_codecs()`

Mettre à jour la liste affichée.

```bash
list_supported_codecs() {
    echo "hevc av1 vvc"  # ← AJOUTER vvc
}
```

### 1.6 `get_codec_rank()`

Définir le rang qualité (plus haut = meilleur codec, utilisé pour skip intelligent).

```bash
get_codec_rank() {
    case "$1" in
        h264|avc)     echo 1 ;;
        hevc|h265)    echo 2 ;;
        av1)          echo 3 ;;
        vvc|h266)     echo 4 ;;  # ← AJOUTER (VVC > AV1 en qualité/compression)
        *)            echo 0 ;;
    esac
}
```

### 1.7 `get_codec_efficiency()`

**⚠️ IMPORTANT** : Définir le facteur d'efficacité du codec.

Cette valeur est utilisée pour **ajuster automatiquement les bitrates** selon l'efficacité de compression du codec. Les bitrates de référence sont définis pour HEVC (70%), et sont automatiquement ajustés.

```bash
get_codec_efficiency() {
    case "$1" in
        h264|avc)  echo 100 ;;  # Référence
        hevc|h265) echo 70 ;;   # ~30% plus efficace que H.264
        av1)       echo 50 ;;   # ~50% plus efficace que H.264
        vvc|h266)  echo 35 ;;   # ← AJOUTER (~65% plus efficace)
        *)         echo 100 ;;  # Inconnu → prudent
    esac
}
```

**Impact** : Pour un bitrate de référence HEVC de 2520 kbps :
- HEVC : 2520 × 70/70 = **2520 kbps**
- AV1 : 2520 × 50/70 = **1800 kbps**
- VVC : 2520 × 35/70 = **1260 kbps**

### 1.8 `get_encoder_mode_params()`

Définir les paramètres spécifiques par mode (serie/film).

```bash
get_encoder_mode_params() {
    local encoder="$1" mode="$2"
    case "$encoder" in
        libx265)
            # ... existant ...
            ;;
        libsvtav1)
            # ... existant ...
            ;;
        libvvenc)  # ← AJOUTER BLOC
            case "$mode" in
                serie) echo "passes=1" ;;  # Exemple - adapter selon doc vvenc
                film)  echo "passes=2" ;;
                *)     echo "" ;;
            esac
            ;;
    esac
}
```

### 1.8 `get_encoder_params_flag()`

Définir le flag CLI FFmpeg pour les params encoder.

```bash
get_encoder_params_flag() {
    case "$1" in
        libx265)   echo "-x265-params" ;;
        libsvtav1) echo "-svtav1-params" ;;
        libvvenc)  echo "-vvenc-params" ;;  # ← AJOUTER (vérifier doc FFmpeg)
        *)         echo "-x265-params" ;;
    esac
}
```

### 1.9 `build_vbv_params()`

Définir comment construire les params VBV (ou vide si géré autrement).

```bash
build_vbv_params() {
    local encoder="$1" maxrate="$2" bufsize="$3"
    case "$encoder" in
        libx265)   echo "vbv-maxrate=${maxrate}:vbv-bufsize=${bufsize}" ;;
        libsvtav1) echo "" ;;  # VBV via -maxrate/-bufsize FFmpeg
        libvvenc)  echo "" ;;  # ← AJOUTER (adapter selon encoder)
        *)         echo "vbv-maxrate=${maxrate}:vbv-bufsize=${bufsize}" ;;
    esac
}
```

### 1.10 `convert_preset()`

Mapper les presets x265 vers le nouveau encoder.

```bash
convert_preset() {
    local preset="$1" encoder="$2"
    case "$encoder" in
        libsvtav1)
            # x265 preset → SVT-AV1 preset (0-13)
            case "$preset" in
                ultrafast) echo 12 ;; veryslow) echo 2 ;;
                # ...
            esac
            ;;
        libvvenc)  # ← AJOUTER BLOC
            # x265 preset → vvenc preset (adapter selon doc)
            case "$preset" in
                ultrafast) echo "faster" ;;
                fast)      echo "fast" ;;
                medium)    echo "medium" ;;
                slow)      echo "slow" ;;
                slower)    echo "slower" ;;
                *)         echo "medium" ;;
            esac
            ;;
        *) echo "$preset" ;;
    esac
}
```

### 1.11 `build_tune_option()`

Définir l'option -tune si applicable.

```bash
build_tune_option() {
    local encoder="$1" mode="$2"
    case "$encoder" in
        libx265)
            [[ "$mode" == "serie" ]] && echo "-tune fastdecode" || echo ""
            ;;
        libsvtav1|libvvenc)  # ← AJOUTER libvvenc
            echo ""  # Tune via params encoder
            ;;
        *) echo "" ;;
    esac
}
```

### 1.12 `get_mode_keyint()`

Définir le keyint par mode (peut varier selon encoder).

```bash
get_mode_keyint() {
    local encoder="$1" mode="$2"
    # Si keyint identique pour tous encoders, pas de case sur $encoder
    case "$mode" in
        serie) echo 600 ;;
        film)  echo 240 ;;
        *)     echo 250 ;;
    esac
}
```

---

## 2. lib/args.sh

### 2.1 Validation `--codec`

Ajouter le codec dans la validation CLI.

```bash
-c|--codec)
    shift
    case "$1" in
        hevc|av1|vvc)  # ← AJOUTER vvc
            VIDEO_CODEC="$1"
            ;;
        *)
            log_error "Codec non supporté: $1 (valides: hevc, av1, vvc)"  # ← MAJ message
            exit 1
            ;;
    esac
    ;;
```

---

## 3. Tests unitaires

### 3.1 tests/test_codec_profiles.bats

Ajouter les tests pour chaque fonction modifiée :

```bash
# get_codec_encoder
@test "get_codec_encoder: retourne libvvenc pour vvc" {
    result=$(get_codec_encoder "vvc")
    [ "$result" = "libvvenc" ]
}

# get_codec_suffix
@test "get_codec_suffix: retourne vvc pour vvc" {
    result=$(get_codec_suffix "vvc")
    [ "$result" = "vvc" ]
}

# is_codec_match
@test "is_codec_match: vvc matche vvc" {
    is_codec_match "vvc" "vvc"
}

@test "is_codec_match: h266 matche vvc" {
    is_codec_match "h266" "vvc"
}

@test "is_codec_match: vvc ne matche pas hevc" {
    ! is_codec_match "vvc" "hevc"
}

# is_codec_supported
@test "is_codec_supported: vvc est supporté" {
    is_codec_supported "vvc"
}

# get_codec_rank
@test "get_codec_rank: vvc > av1" {
    vvc_rank=$(get_codec_rank "vvc")
    av1_rank=$(get_codec_rank "av1")
    [ "$vvc_rank" -gt "$av1_rank" ]
}

# is_codec_better_or_equal
@test "is_codec_better_or_equal: vvc >= av1" {
    run is_codec_better_or_equal "vvc" "av1"
    [ "$status" -eq 0 ]
}

@test "is_codec_better_or_equal: vvc >= hevc" {
    run is_codec_better_or_equal "vvc" "hevc"
    [ "$status" -eq 0 ]
}

@test "is_codec_better_or_equal: av1 < vvc" {
    run is_codec_better_or_equal "av1" "vvc"
    [ "$status" -ne 0 ]
}

# get_encoder_mode_params
@test "get_encoder_mode_params: libvvenc serie retourne des params" {
    result=$(get_encoder_mode_params "libvvenc" "serie")
    # Adapter selon implémentation réelle
    [[ -n "$result" ]] || [[ -z "$result" ]]  # Au minimum, pas d'erreur
}

# get_encoder_params_flag
@test "get_encoder_params_flag: libvvenc retourne -vvenc-params" {
    result=$(get_encoder_params_flag "libvvenc")
    [ "$result" = "-vvenc-params" ]
}

# build_vbv_params
@test "build_vbv_params: libvvenc retourne selon implémentation" {
    result=$(build_vbv_params "libvvenc" 2520 3780)
    # Adapter selon choix d'implémentation
    [[ -z "$result" ]] || [[ "$result" =~ "maxrate" ]]
}

# convert_preset
@test "convert_preset: medium -> libvvenc" {
    result=$(convert_preset "medium" "libvvenc")
    [ "$result" = "medium" ]  # Adapter selon mapping choisi
}

# build_tune_option
@test "build_tune_option: libvvenc retourne vide" {
    result=$(build_tune_option "libvvenc" "serie")
    [ -z "$result" ]
}
```

### 3.2 tests/test_args.bats

```bash
@test "parse_args: --codec vvc accepté" {
    parse_args --codec vvc
    [ "$VIDEO_CODEC" = "vvc" ]
}
```

---

## 4. README.md

### 4.1 Section "Codecs supportés"

```markdown
## Codecs supportés

| Codec | Encoder FFmpeg | Suffixe | Qualité |
|-------|----------------|---------|---------|
| HEVC/H.265 | libx265 | _(aucun)_ | ⭐⭐ |
| AV1 | libsvtav1 | `.av1` | ⭐⭐⭐ |
| VVC/H.266 | libvvenc | `.vvc` | ⭐⭐⭐⭐ |
```

### 4.2 Section "Options CLI"

```markdown
-c, --codec CODEC    Codec cible : hevc (défaut), av1, vvc
```

### 4.3 Section "Exemples"

```bash
# Conversion en VVC (H.266)
bash nascode -c vvc -s "/chemin/source"
```

---

## 5. Validation finale

```bash
# 1. Lancer tous les tests
bash run_tests.sh

# 2. Test manuel rapide
bash nascode -c vvc -d -s "/chemin/test"  # Mode dry-run

# 3. Vérifier la commande FFmpeg générée dans les logs
```

---

## 📝 Notes spécifiques par codec

### H.266/VVC (libvvenc)

- **Statut FFmpeg** : Support expérimental (vérifier version FFmpeg)
- **Presets** : `faster`, `fast`, `medium`, `slow`, `slower`
- **Paramètres recommandés** : À documenter après tests
- **Containers supportés** : MP4 (vérifier MKV)

### Autres considérations

- **Dépendances** : Vérifier que l'encoder est compilé dans FFmpeg (`ffmpeg -encoders | grep vvenc`)
- **Performance** : VVC est ~2-3x plus lent que HEVC à qualité égale
- **Compatibilité** : Peu de lecteurs supportent VVC actuellement

---

## Estimation temps

| Étape | Durée |
|-------|-------|
| Implémentation codec_profiles.sh | 15-20 min |
| Mise à jour args.sh | 5 min |
| Tests unitaires | 15-20 min |
| Documentation README | 10 min |
| Validation / debug | 10-15 min |
| **Total** | **~1h** |
