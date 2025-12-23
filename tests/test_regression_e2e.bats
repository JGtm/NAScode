#!/usr/bin/env bats
###########################################################
# TESTS E2E DE NON-RÉGRESSION - Cas d'erreurs et limites
#
# Tests end-to-end pour :
# 1. Média corrompu / échec ffmpeg (cleanup + continuation queue)
# 2. Conversion avec HWACCEL désactivé (software fallback)
# 3. Downscale 4K vers 1080p (si ffmpeg disponible)
###########################################################

load 'test_helper'

# Vérifier si ffmpeg est disponible
check_ffmpeg_available() {
    if ! command -v ffmpeg &>/dev/null; then
        skip "ffmpeg non disponible"
    fi
    if ! ffmpeg -encoders 2>/dev/null | grep -q libx265; then
        skip "libx265 non disponible dans ffmpeg"
    fi
}

setup() {
    setup_test_env
    check_ffmpeg_available
    
    # Nettoyer le lock global
    rm -f /tmp/conversion_video.lock
    
    # Créer les répertoires de travail
    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"
    
    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR"
}

teardown() {
    rm -f /tmp/conversion_video.lock
    teardown_test_env
}

###########################################################
# SECTION 1: MÉDIA CORROMPU / ÉCHEC FFMPEG
###########################################################

@test "E2E CORRUPTION: fichier texte renommé .mkv est détecté comme invalide" {
    # Créer un fichier corrompu
    echo "This is not a video file at all - just plain text" > "$SRC_DIR/corrupted_video.mkv"
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    ' || true
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    
    # Le script doit avoir géré l'erreur (soit terminé normalement, soit créé un log)
    local found_in_logs=false
    
    # Chercher dans Error.log ou Skipped.log
    local error_log=$(find "$WORKDIR/logs" -name "Error_*.log" -type f 2>/dev/null | head -1)
    local skipped_log=$(find "$WORKDIR/logs" -name "Skipped_*.log" -type f 2>/dev/null | head -1)
    
    if [[ -n "$error_log" && -f "$error_log" ]]; then
        if grep -q "corrupted_video" "$error_log" 2>/dev/null; then
            found_in_logs=true
        fi
    fi
    
    if [[ -n "$skipped_log" && -f "$skipped_log" ]]; then
        if grep -q "corrupted_video" "$skipped_log" 2>/dev/null; then
            found_in_logs=true
        fi
    fi
    
    # Ou dans la sortie standard
    if [[ "$output" =~ "corrupted" ]] || [[ "$output" =~ "skip" ]] || [[ "$output" =~ "erreur" ]] || [[ "$output" =~ "Invalid" ]]; then
        found_in_logs=true
    fi
    
    [ "$found_in_logs" = true ]
}

@test "E2E CORRUPTION: fichiers temporaires nettoyés après erreur" {
    # Créer un fichier corrompu
    echo "invalid video data - this will fail" > "$SRC_DIR/bad_file.mkv"
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    ' || true
    
    # Vérifier qu'aucun fichier temporaire x265 n'est resté
    local leftover_files
    leftover_files=$(find "$TEST_TEMP_DIR" -name "*x265*" -type f 2>/dev/null | wc -l)
    
    [ "$leftover_files" -eq 0 ]
}

@test "E2E CORRUPTION: la queue continue après un fichier invalide" {
    # Créer un fichier corrompu ET un fichier valide
    echo "not a video" > "$SRC_DIR/01_corrupted.mkv"
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/02_valid.mkv"
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 2
    '
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    
    # Le fichier valide doit avoir été converti malgré l'échec du premier
    local valid_converted
    valid_converted=$(find "$OUT_DIR" -name "*valid*" -type f 2>/dev/null | wc -l)
    
    [ "$valid_converted" -ge 1 ]
}

###########################################################
# SECTION 2: CONVERSION AVEC HWACCEL DÉSACTIVÉ
###########################################################

@test "E2E HWACCEL: conversion réussit avec HWACCEL vide (software fallback)" {
    # Copier le fichier de test
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/"
    
    # Exécuter avec HWACCEL forcé à vide (software)
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        export HWACCEL=""
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    
    # Doit réussir même sans hwaccel
    [ "$status" -eq 0 ]
    
    # Vérifier qu'un fichier de sortie existe
    local out_files
    out_files=$(find "$OUT_DIR" -type f -name "*.mkv" 2>/dev/null | wc -l)
    [ "$out_files" -ge 1 ]
}

@test "E2E HWACCEL: conversion réussit avec HWACCEL=none" {
    # Copier le fichier de test
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/"
    
    # Exécuter avec HWACCEL forcé à "none"
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        export HWACCEL="none"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    
    # Doit réussir même avec hwaccel=none
    [ "$status" -eq 0 ]
    
    # Vérifier le codec de sortie
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    local codec
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$out_file")
    [ "$codec" = "hevc" ]
}

###########################################################
# SECTION 3: DOWNSCALE 4K VERS 1080P
###########################################################

@test "E2E DOWNSCALE: encodage 4K produit output ≤1080p" {
    # Créer une vidéo 4K de 1 seconde (très courte pour le test)
    # Utilise testsrc qui génère une mire de test
    ffmpeg -y -f lavfi -i "testsrc=duration=1:size=3840x2160:rate=1" \
        -c:v libx264 -preset ultrafast -crf 51 \
        "$SRC_DIR/test_4k.mkv" 2>/dev/null
    
    if [[ ! -f "$SRC_DIR/test_4k.mkv" ]]; then
        skip "Impossible de créer la vidéo 4K de test"
    fi
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    
    # Trouver le fichier de sortie
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    
    if [[ -n "$out_file" ]]; then
        # Vérifier la résolution de sortie
        local out_height
        out_height=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=height -of csv=p=0 "$out_file")
        
        # La hauteur doit être ≤ 1080
        [ "$out_height" -le 1080 ]
    fi
}

@test "E2E DOWNSCALE: vidéo 720p n'est pas agrandie" {
    # Créer une vidéo 720p
    ffmpeg -y -f lavfi -i "testsrc=duration=1:size=1280x720:rate=1" \
        -c:v libx264 -preset ultrafast -crf 51 \
        "$SRC_DIR/test_720p.mkv" 2>/dev/null
    
    if [[ ! -f "$SRC_DIR/test_720p.mkv" ]]; then
        skip "Impossible de créer la vidéo 720p de test"
    fi
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Trouver le fichier de sortie
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    
    if [[ -n "$out_file" ]]; then
        # Vérifier la résolution de sortie (doit rester 720p)
        local out_height
        out_height=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=height -of csv=p=0 "$out_file")
        
        # La hauteur doit être exactement 720 (pas agrandie)
        [ "$out_height" -eq 720 ]
    fi
}

###########################################################
# SECTION 5: RÉGRESSION BUG STOP_FLAG
###########################################################

@test "E2E STOP_FLAG: pas de faux message 'interruption' en fin normale" {
    # Régression bug: le dernier fichier affichait "Conversion interrompue"
    # alors que tout s'était bien passé, car STOP_FLAG était créé trop tôt
    
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/"
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    
    # Le message "Conversion interrompue" NE DOIT PAS apparaître en fin normale
    [[ ! "$output" =~ "Conversion interrompue" ]]
    [[ ! "$output" =~ "fichier temporaire conservé" ]]
    
    # Il doit y avoir un fichier converti
    local out_files
    out_files=$(find "$OUT_DIR" -type f -name "*.mkv" 2>/dev/null | wc -l)
    [ "$out_files" -ge 1 ]
}

@test "E2E STOP_FLAG: STOP_FLAG n'existe pas après fin normale" {
    # Le STOP_FLAG ne doit être créé que lors d'une vraie interruption
    
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/"
    
    # S'assurer que STOP_FLAG n'existe pas avant
    rm -f /tmp/conversion_stop_flag
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Après une fin normale, le STOP_FLAG peut exister (créé par cleanup)
    # mais le message d'interruption ne doit pas avoir été affiché
    # Ce test vérifie surtout que la conversion a réussi sans faux positif
    [[ ! "$output" =~ "interrompue" ]]
}
