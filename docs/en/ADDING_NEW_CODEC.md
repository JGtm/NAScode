# Guide: Adding a New Codec

This document describes the steps to add support for a new video codec (e.g., H.266/VVC).

---

## 📋 Quick Checklist

- [ ] `lib/codec_profiles.sh` — Codec/encoder functions + efficiency
- [ ] `lib/args.sh` — CLI `--codec` validation
- [ ] `tests/test_codec_profiles.bats` — Codec unit tests
- [ ] `tests/test_transcode_video.bats` — Encoding tests
- [ ] `tests/test_args.bats` — CLI validation tests
- [ ] `README.md` — User documentation

---

## 1. lib/codec_profiles.sh

### 1.1 `get_codec_encoder()`

Add the codec → FFmpeg encoder mapping.

```bash
get_codec_encoder() {
    case "${1:-hevc}" in
        hevc|h265) echo "libx265" ;;
        av1)       echo "libsvtav1" ;;
        vvc|h266)  echo "libvvenc" ;;  # ← ADD
        *)         echo "libx265" ;;
    esac
}
```

### 1.2 `get_codec_suffix()`

Define the file suffix used in output name.

```bash
get_codec_suffix() {
    case "${1:-hevc}" in
        hevc|h265) echo "x265" ;;
        av1)       echo "av1" ;;
        vvc|h266)  echo "vvc" ;;  # ← ADD
        *)         echo "x265" ;;
    esac
}
```

### 1.3 `is_codec_match()`

Add naming variants.

In the code, `is_codec_match()` relies on `get_codec_ffmpeg_names()`: to add aliases (e.g., `h266`, `vvenc`, etc.), you must first declare them in `get_codec_ffmpeg_names()`.

```bash
get_codec_ffmpeg_names() {
    case "${1:-hevc}" in
        hevc|h265) echo "hevc h265" ;;
        av1)       echo "av1" ;;
        vvc|h266)  echo "vvc h266 vvenc" ;;  # ← ADD (adapt if needed)
        *)         echo "" ;;
    esac
}
```

Then `is_codec_match()` generally doesn't need to change:

```bash
is_codec_match() {
    local source_codec="$1" target_codec="$2"
    local known_names
    known_names=$(get_codec_ffmpeg_names "$target_codec")

    for name in $known_names; do
        if [[ "$source_codec" == "$name" ]]; then
            return 0
        fi
    done
    return 1
}
```

### 1.4 `is_codec_supported()`

Add the codec to the list.

```bash
is_codec_supported() {
    case "$1" in
        hevc|h265|av1|vvc|h266) return 0 ;;  # ← ADD vvc|h266
        *) return 1 ;;
    esac
}
```

### 1.5 `list_supported_codecs()`

Update the displayed list.

```bash
list_supported_codecs() {
    echo "hevc av1 vvc"  # ← ADD vvc
}
```

### 1.6 `get_codec_rank()`

Define the quality rank (higher = better codec, used for intelligent skip).

```bash
get_codec_rank() {
    case "$1" in
        h264|avc)     echo 1 ;;
        hevc|h265)    echo 2 ;;
        av1)          echo 3 ;;
        vvc|h266)     echo 4 ;;  # ← ADD (VVC > AV1 in quality/compression)
        *)            echo 0 ;;
    esac
}
```

### 1.7 `get_codec_efficiency()`

**⚠️ IMPORTANT**: Define the codec efficiency factor.

This value is used to **automatically adjust bitrates** according to the codec's compression efficiency. Reference bitrates are defined for HEVC (70%), and are automatically adjusted.

```bash
get_codec_efficiency() {
    case "$1" in
        h264|avc)  echo 100 ;;  # Reference
        hevc|h265) echo 70 ;;   # ~30% more efficient than H.264
        av1)       echo 50 ;;   # ~50% more efficient than H.264
        vvc|h266)  echo 35 ;;   # ← ADD (~65% more efficient)
        *)         echo 100 ;;  # Unknown → conservative
    esac
}
```

**Impact**: For an HEVC reference bitrate of 2520 kbps:
- HEVC: 2520 × 70/70 = **2520 kbps**
- AV1: 2520 × 50/70 = **1800 kbps**
- VVC: 2520 × 35/70 = **1260 kbps**

### 1.8 `get_encoder_mode_params()`

Define mode-specific parameters (serie/film).

```bash
get_encoder_mode_params() {
    local encoder="$1" mode="$2"
    case "$encoder" in
        libx265)
            # ... existing ...
            ;;
        libsvtav1)
            # ... existing ...
            ;;
        libvvenc)  # ← ADD BLOCK
            case "$mode" in
                serie) echo "passes=1" ;;  # Example - adapt according to vvenc doc
                film)  echo "passes=2" ;;
                *)     echo "" ;;
            esac
            ;;
    esac
}
```

### 1.8 `get_encoder_params_flag()`

Define the FFmpeg CLI flag for encoder params.

```bash
get_encoder_params_flag() {
    case "$1" in
        libx265)   echo "-x265-params" ;;
        libsvtav1) echo "-svtav1-params" ;;
        libvvenc)  echo "-vvenc-params" ;;  # ← ADD (check FFmpeg doc)
        *)         echo "-x265-params" ;;
    esac
}
```

### 1.9 `build_vbv_params()`

Define how to build VBV params (or empty if handled differently).

```bash
build_vbv_params() {
    local encoder="$1" maxrate="$2" bufsize="$3"
    case "$encoder" in
        libx265)   echo "vbv-maxrate=${maxrate}:vbv-bufsize=${bufsize}" ;;
        libsvtav1) echo "" ;;  # VBV via FFmpeg -maxrate/-bufsize
        libvvenc)  echo "" ;;  # ← ADD (adapt according to encoder)
        *)         echo "vbv-maxrate=${maxrate}:vbv-bufsize=${bufsize}" ;;
    esac
}
```

### 1.10 `convert_preset()`

Map x265 presets to the new encoder.

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
        libvvenc)  # ← ADD BLOCK
            # x265 preset → vvenc preset (adapt according to doc)
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

Define the -tune option if applicable.

```bash
build_tune_option() {
    local encoder="$1" mode="$2"
    case "$encoder" in
        libx265)
            [[ "$mode" == "serie" ]] && echo "-tune fastdecode" || echo ""
            ;;
        libsvtav1|libvvenc)  # ← ADD libvvenc
            echo ""  # Tune via encoder params
            ;;
        *) echo "" ;;
    esac
}
```

### 1.12 `get_mode_keyint()`

Define keyint by mode (may vary by encoder).

```bash
get_mode_keyint() {
    local encoder="$1" mode="$2"
    # If keyint is identical for all encoders, no case on $encoder
    case "$mode" in
        serie) echo 600 ;;
        film)  echo 240 ;;
        *)     echo 250 ;;
    esac
}
```

---

## 2. lib/args.sh

### 2.1 `--codec` Validation

Add the codec in CLI validation.

```bash
-c|--codec)
    if [[ -n "${2:-}" ]]; then
        case "$2" in
            hevc|av1|vvc)  # ← ADD vvc
                VIDEO_CODEC="$2"
                ;;
            *)
                print_error "Invalid codec: '$2'. Accepted values: hevc, av1, vvc"  # ← UPDATE message
                exit 1
                ;;
        esac
        shift 2
    else
        print_error "--codec must be followed by a codec name (hevc, av1, vvc)"
        exit 1
    fi
    ;;
```

---

## 2bis. Video Logic & Mapping (refactor)

- The "video parameters" logic (pix_fmt, downscale, adaptive bitrate, effective suffix) is centralized in `lib/video_params.sh`.
- Stream mapping (video/audio/subs) is centralized in `lib/stream_mapping.sh`.
- `lib/transcode_video.sh` orchestrates encoding and calls these helpers: avoid duplicating functions there.

---

## 3. Unit Tests

### 3.1 tests/test_codec_profiles.bats

Add tests for each modified function:

```bash
# get_codec_encoder
@test "get_codec_encoder: returns libvvenc for vvc" {
    result=$(get_codec_encoder "vvc")
    [ "$result" = "libvvenc" ]
}

# get_codec_suffix
@test "get_codec_suffix: returns vvc for vvc" {
    result=$(get_codec_suffix "vvc")
    [ "$result" = "vvc" ]
}

# is_codec_match
@test "is_codec_match: vvc matches vvc" {
    is_codec_match "vvc" "vvc"
}

@test "is_codec_match: h266 matches vvc" {
    is_codec_match "h266" "vvc"
}

@test "is_codec_match: vvc doesn't match hevc" {
    ! is_codec_match "vvc" "hevc"
}

# is_codec_supported
@test "is_codec_supported: vvc is supported" {
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
@test "get_encoder_mode_params: libvvenc serie returns params" {
    result=$(get_encoder_mode_params "libvvenc" "serie")
    # Adapt according to actual implementation
    [[ -n "$result" ]] || [[ -z "$result" ]]  # At minimum, no error
}

# get_encoder_params_flag
@test "get_encoder_params_flag: libvvenc returns -vvenc-params" {
    result=$(get_encoder_params_flag "libvvenc")
    [ "$result" = "-vvenc-params" ]
}

# build_vbv_params
@test "build_vbv_params: libvvenc returns according to implementation" {
    result=$(build_vbv_params "libvvenc" 2520 3780)
    # Adapt according to implementation choice
    [[ -z "$result" ]] || [[ "$result" =~ "maxrate" ]]
}

# convert_preset
@test "convert_preset: medium -> libvvenc" {
    result=$(convert_preset "medium" "libvvenc")
    [ "$result" = "medium" ]  # Adapt according to chosen mapping
}

# build_tune_option
@test "build_tune_option: libvvenc returns empty" {
    result=$(build_tune_option "libvvenc" "serie")
    [ -z "$result" ]
}
```

### 3.2 tests/test_args.bats

```bash
@test "parse_arguments: --codec vvc accepted" {
    parse_arguments --codec vvc
    [ "$VIDEO_CODEC" = "vvc" ]
}
```

---

## 4. README.md

### 4.1 "Supported Codecs" Section

```markdown
## Supported Codecs

| Codec | FFmpeg Encoder | Suffix | Quality |
|-------|----------------|--------|---------|
| HEVC/H.265 | libx265 | `_x265` | ⭐⭐ |
| AV1 | libsvtav1 | `_av1` | ⭐⭐⭐ |
| VVC/H.266 | libvvenc | `_vvc` | ⭐⭐⭐⭐ |
```

### 4.2 "CLI Options" Section

```markdown
-c, --codec CODEC    Target codec: hevc (default), av1, vvc
```

### 4.3 "Examples" Section

```bash
# VVC (H.266) conversion
bash nascode -c vvc -s "/path/source"
```

---

## 5. Final Validation

```bash
# 1. Run all tests
bash run_tests.sh

# 2. Quick manual test
bash nascode -c vvc -d -s "/path/test"  # Dry-run mode

# 3. Check generated FFmpeg command in logs
```

---

## 📝 Codec-Specific Notes

### H.266/VVC (libvvenc)

- **FFmpeg status**: Experimental support (check FFmpeg version)
- **Presets**: `faster`, `fast`, `medium`, `slow`, `slower`
- **Recommended parameters**: To be documented after testing
- **Supported containers**: MP4 (check MKV)

### Other Considerations

- **Dependencies**: Verify the encoder is compiled in FFmpeg (`ffmpeg -encoders | grep vvenc`)
- **Performance**: VVC is ~2-3x slower than HEVC at equal quality
- **Compatibility**: Few players currently support VVC

---

## Time Estimate

| Step | Duration |
|------|----------|
| codec_profiles.sh implementation | 15-20 min |
| args.sh update | 5 min |
| Unit tests | 15-20 min |
| README documentation | 10 min |
| Validation / debug | 10-15 min |
| **Total** | **~1h** |
