#!/usr/bin/env bats
###########################################################
# TESTS Phase C — segmenter / vmaf_predictive / auto_boost
#
# Tests unitaires + un test d'intégration end-to-end sur un
# sample lavfi généré à la volée (~30s). Le test d'intégration
# est skippé si libvmaf ou libsvtav1 manquent.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules_fast
    source "$LIB_DIR/vmaf.sh"
    source "$LIB_DIR/segmenter.sh"
    source "$LIB_DIR/vmaf_predictive.sh"
    source "$LIB_DIR/auto_boost.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests fonctions définies (régression du scaffolding)
###########################################################

@test "segmenter: _segment_video est définie" {
    declare -f _segment_video >/dev/null
}

@test "segmenter: _concat_segments est définie" {
    declare -f _concat_segments >/dev/null
}

@test "segmenter: _list_keyframes est définie" {
    declare -f _list_keyframes >/dev/null
}

@test "vmaf_predictive: _quick_encode_segment est définie" {
    declare -f _quick_encode_segment >/dev/null
}

@test "vmaf_predictive: _measure_vmaf_segment est définie" {
    declare -f _measure_vmaf_segment >/dev/null
}

@test "vmaf_predictive: _compute_crf_adjustment est définie" {
    declare -f _compute_crf_adjustment >/dev/null
}

@test "vmaf_predictive: VMAF_PREDICTIVE_PROBE_CRF défini par défaut" {
    [ -n "${VMAF_PREDICTIVE_PROBE_CRF:-}" ]
}

@test "vmaf_predictive: VMAF_PREDICTIVE_BOOST_TABLE défini par défaut" {
    [ -n "${VMAF_PREDICTIVE_BOOST_TABLE:-}" ]
}

@test "auto_boost: auto_boost_encode est définie" {
    declare -f auto_boost_encode >/dev/null
}

@test "auto_boost: auto_boost_check_prereqs est définie" {
    declare -f auto_boost_check_prereqs >/dev/null
}

@test "auto_boost: auto_boost_check_prereqs valide la présence des briques" {
    run auto_boost_check_prereqs
    [ "$status" -eq 0 ]
}

@test "auto_boost: AUTO_BOOST_SEGMENT_DURATION défini par défaut" {
    [ -n "${AUTO_BOOST_SEGMENT_DURATION:-}" ]
}

###########################################################
# Tests _compute_crf_adjustment — logique pure
###########################################################

@test "_compute_crf_adjustment: VMAF 95 → +2 (scène facile, économie)" {
    result=$(_compute_crf_adjustment "95")
    [ "$result" = "2" ]
}

@test "_compute_crf_adjustment: VMAF 88 → 0 (scène neutre)" {
    result=$(_compute_crf_adjustment "88")
    [ "$result" = "0" ]
}

@test "_compute_crf_adjustment: VMAF 80 → -2 (scène difficile, boost)" {
    result=$(_compute_crf_adjustment "80")
    [ "$result" = "-2" ]
}

@test "_compute_crf_adjustment: VMAF 60 → -4 (scène très difficile, boost fort)" {
    result=$(_compute_crf_adjustment "60")
    [ "$result" = "-4" ]
}

@test "_compute_crf_adjustment: VMAF=NA → 0 (neutre)" {
    result=$(_compute_crf_adjustment "NA")
    [ "$result" = "0" ]
}

@test "_compute_crf_adjustment: VMAF invalide → 0 (neutre)" {
    result=$(_compute_crf_adjustment "garbage")
    [ "$result" = "0" ]
}

@test "_compute_crf_adjustment: VMAF vide → 0 (neutre)" {
    result=$(_compute_crf_adjustment "")
    [ "$result" = "0" ]
}

@test "_compute_crf_adjustment: VMAF float (87.5) → 0" {
    result=$(_compute_crf_adjustment "87.5")
    [ "$result" = "0" ]
}

@test "_compute_crf_adjustment: VMAF exactement au seuil 92 → +2" {
    result=$(_compute_crf_adjustment "92")
    [ "$result" = "2" ]
}

###########################################################
# Tests _segment_video — erreurs d'usage
###########################################################

@test "_segment_video: arguments manquants → code 2" {
    run _segment_video "" "" ""
    [ "$status" -eq 2 ]
}

@test "_segment_video: input inexistant → code 2" {
    run _segment_video "/no/such/file.mkv" 10 "/tmp/segs"
    [ "$status" -eq 2 ]
}

@test "_segment_video: duration invalide → code 2" {
    # Crée un fichier source bidon (le contrôle de duration est avant ffmpeg).
    local fake; fake=$(mktemp); printf "fake" > "$fake"
    run _segment_video "$fake" "zero" "/tmp/segs"
    [ "$status" -eq 2 ]
    rm -f "$fake"
}

###########################################################
# Tests _concat_segments — erreurs d'usage
###########################################################

@test "_concat_segments: arguments manquants → code 2" {
    run _concat_segments "" ""
    [ "$status" -eq 2 ]
}

@test "_concat_segments: list file inexistant → code 2" {
    run _concat_segments "/no/such/list.txt" "/tmp/out.mkv"
    [ "$status" -eq 2 ]
}

###########################################################
# Test d'intégration end-to-end (skip si pas d'encodeur AV1)
###########################################################

@test "auto_boost: pipeline complet sur sample lavfi 30s" {
    if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libsvtav1; then
        skip "libsvtav1 non disponible"
    fi
    if [[ "${HAS_LIBVMAF:-0}" -ne 1 ]]; then
        # Le pipeline reste valide sans VMAF (delta=0 partout), on n'exige
        # pas libvmaf pour cet integration test, mais on le note.
        :
    fi

    local work; work=$(mktemp -d)
    local sample="${work}/sample.mkv"
    local out="${work}/out.mkv"

    # Sample 30s @ 240x144 24fps avec testsrc2 (a une variance correcte).
    ffmpeg -hide_banner -loglevel error -y \
        -f lavfi -i "testsrc2=duration=30:size=240x144:rate=24" \
        -c:v libx264 -preset ultrafast -crf 23 -g 24 \
        -pix_fmt yuv420p "$sample"
    [ -s "$sample" ]

    # Pipeline auto-boost avec segments courts (10s → 3 segments).
    AUTO_BOOST_SEGMENT_DURATION=10 \
        run auto_boost_encode "$sample" "$out" 25
    [ "$status" -eq 0 ]
    [ -s "$out" ]

    # Vérifier que la sortie est bien de l'AV1 10-bit.
    local codec pix_fmt
    codec=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name -of default=nw=1:nk=1 "$out")
    pix_fmt=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=pix_fmt -of default=nw=1:nk=1 "$out")
    [ "$codec" = "av1" ]
    [ "$pix_fmt" = "yuv420p10le" ]

    # Vérifier que la durée est cohérente (tolérance 1s).
    local duration
    duration=$(ffprobe -v error \
        -show_entries format=duration -of default=nw=1:nk=1 "$out" \
        | awk '{print int($1)}')
    [ "$duration" -ge 29 ]
    [ "$duration" -le 31 ]

    rm -rf "$work"
}
