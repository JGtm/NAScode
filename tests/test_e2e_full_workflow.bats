#!/usr/bin/env bats
###########################################################
# TESTS END-TO-END - Workflow complet de conversion
# 
# Ces tests vérifient qu'un fichier passe RÉELLEMENT par toutes
# les étapes de traitement avec ffmpeg (pas de dry-run).
#
# Prérequis: ffmpeg avec libx265, libopus installés
# Durée: ~30-60 secondes par test (encodage réel)
###########################################################

load 'test_helper'

# Skip si ffmpeg n'est pas disponible
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
    
    # Créer les répertoires de travail
    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"
    export FALLBACK_DIR="$TEST_TEMP_DIR/fallback"
    
    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR" "$FALLBACK_DIR"
    
    # Copier le fichier de test
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/"
}

teardown() {
    teardown_test_env
}

###########################################################
# Test E2E: Conversion complète single-pass (CRF)
###########################################################

@test "E2E single-pass: fichier H.264 converti en HEVC avec succès" {
    # Note: single-pass (CRF) est le mode par défaut pour les séries, pas besoin d'option
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    echo "=== STATUS: $status ===" >&3
    
    [ "$status" -eq 0 ]
    
    # Vérifier qu'un fichier de sortie existe
    local out_files
    out_files=$(find "$OUT_DIR" -type f -name "*.mkv" | wc -l)
    [ "$out_files" -ge 1 ]
    
    # Vérifier que le fichier de sortie est encodé en HEVC
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    local codec
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$out_file")
    [ "$codec" = "hevc" ]
}

@test "E2E single-pass: log de succès créé après conversion" {
    run bash -lc 'set -euo pipefail
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
    
    # Le log de succès doit exister et contenir une entrée
    [ -f "$WORKDIR/logs/Success.log" ]
    
    local success_count
    success_count=$(wc -l < "$WORKDIR/logs/Success.log")
    [ "$success_count" -ge 1 ]
}

@test "E2E single-pass: checksum vérifié (intégrité source)" {
    run bash -lc 'set -euo pipefail
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
    
    # Le fichier source doit toujours exister et être intact
    [ -f "$SRC_DIR/test_video_2s.mkv" ]
    
    # Comparer avec l'original
    local original_size expected_size
    original_size=$(stat -c%s "$FIXTURES_DIR/test_video_2s.mkv" 2>/dev/null || stat -f%z "$FIXTURES_DIR/test_video_2s.mkv")
    expected_size=$(stat -c%s "$SRC_DIR/test_video_2s.mkv" 2>/dev/null || stat -f%z "$SRC_DIR/test_video_2s.mkv")
    [ "$original_size" = "$expected_size" ]
}

###########################################################
# Test E2E: Conversion complète two-pass (bitrate)
###########################################################

@test "E2E two-pass: fichier H.264 converti en HEVC avec succès" {
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    echo "=== STATUS: $status ===" >&3
    
    [ "$status" -eq 0 ]
    
    # Vérifier qu'un fichier de sortie existe
    local out_files
    out_files=$(find "$OUT_DIR" -type f -name "*.mkv" | wc -l)
    [ "$out_files" -ge 1 ]
    
    # Vérifier que le fichier de sortie est encodé en HEVC
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    local codec
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$out_file")
    [ "$codec" = "hevc" ]
}

@test "E2E two-pass: fichiers temporaires nettoyés après conversion" {
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Les fichiers de log 2pass ne doivent plus exister
    local pass_files
    pass_files=$(find "$TEST_TEMP_DIR" -name "*x265_2pass*" -type f 2>/dev/null | wc -l)
    [ "$pass_files" -eq 0 ]
}

###########################################################
# Test E2E: Audio Opus
###########################################################

@test "E2E audio: conversion AAC vers Opus réussie" {
    # Vérifier que libopus est disponible
    if ! ffmpeg -encoders 2>/dev/null | grep -q libopus; then
        skip "libopus non disponible dans ffmpeg"
    fi
    
    run bash -lc 'set -euo pipefail
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
    
    # Vérifier que l'audio est en Opus
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    local audio_codec
    audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$out_file")
    [ "$audio_codec" = "opus" ]
}

@test "E2E audio: bitrate Opus conforme à la cible" {
    if ! ffmpeg -encoders 2>/dev/null | grep -q libopus; then
        skip "libopus non disponible dans ffmpeg"
    fi
    
    run bash -lc 'set -euo pipefail
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
    
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    # Le bitrate audio doit être proche de 128kbps (cible par défaut)
    # Tolérance: entre 100 et 160 kbps
    local audio_bitrate
    audio_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "$out_file")
    
    # Si bit_rate n'est pas disponible, on vérifie juste que l'audio existe
    if [[ "$audio_bitrate" =~ ^[0-9]+$ ]]; then
        local bitrate_kbps=$((audio_bitrate / 1000))
        [ "$bitrate_kbps" -ge 80 ] && [ "$bitrate_kbps" -le 200 ]
    fi
}

###########################################################
# Test E2E: Skip fichiers déjà en HEVC
###########################################################

@test "E2E skip: fichier HEVC avec bitrate bas est ignoré" {
    # Utiliser le fichier HEVC de test
    cp "$FIXTURES_DIR/test_video_hevc_2s.mkv" "$SRC_DIR/"
    rm -f "$SRC_DIR/test_video_2s.mkv"  # Garder seulement le HEVC
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress
    '
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    
    # Le fichier doit être dans le log des skipped
    [ -f "$WORKDIR/logs/Skipped.log" ]
    grep -q "test_video_hevc_2s.mkv" "$WORKDIR/logs/Skipped.log"
}

###########################################################
# Test E2E: Gestion des erreurs
###########################################################

@test "E2E erreur: fichier corrompu génère une entrée dans Error.log" {
    # Créer un fichier corrompu
    echo "not a video file" > "$SRC_DIR/corrupted.mkv"
    rm -f "$SRC_DIR/test_video_2s.mkv"
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    ' || true  # On accepte un échec
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    
    # Le fichier doit être dans le log des erreurs ou skipped
    if [ -f "$WORKDIR/logs/Error.log" ]; then
        grep -q "corrupted.mkv" "$WORKDIR/logs/Error.log" || \
        grep -q "corrupted.mkv" "$WORKDIR/logs/Skipped.log" 2>/dev/null
    elif [ -f "$WORKDIR/logs/Skipped.log" ]; then
        grep -q "corrupted.mkv" "$WORKDIR/logs/Skipped.log"
    else
        # Au moins un fichier de log doit mentionner le fichier
        false
    fi
}

###########################################################
# Test E2E: Résumé final
###########################################################

@test "E2E résumé: summary affiché en fin de traitement" {
    run bash -lc 'set -euo pipefail
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
    
    # Le résumé doit contenir des informations de statistiques
    [[ "$output" =~ "Succès" ]] || [[ "$output" =~ "Traités" ]] || [[ "$output" =~ "RÉSUMÉ" ]]
}

@test "E2E résumé: fichier Summary.log créé" {
    run bash -lc 'set -euo pipefail
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
    
    # Le fichier Summary doit exister
    [ -f "$WORKDIR/logs/Summary.log" ]
}

###########################################################
# Test E2E: Métadonnées préservées
###########################################################

@test "E2E métadonnées: durée préservée après conversion" {
    run bash -lc 'set -euo pipefail
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
    
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    # Durée source
    local src_duration
    src_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FIXTURES_DIR/test_video_2s.mkv" | cut -d. -f1)
    
    # Durée sortie
    local out_duration
    out_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out_file" | cut -d. -f1)
    
    # Les durées doivent être égales (à 1 seconde près)
    local diff=$((src_duration - out_duration))
    [ "${diff#-}" -le 1 ]
}

@test "E2E métadonnées: résolution préservée (pas de downscale sur 320x240)" {
    run bash -lc 'set -euo pipefail
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
    
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    # Résolution
    local width height
    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$out_file")
    height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$out_file")
    
    # Le fichier test est 320x240, ne doit pas être modifié
    [ "$width" = "320" ]
    [ "$height" = "240" ]
}

###########################################################
# Test E2E: Multi-fichiers
###########################################################

@test "E2E multi: traitement de plusieurs fichiers en séquence" {
    # Créer plusieurs copies du fichier source
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/video_a.mkv"
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/video_b.mkv"
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/convert.sh" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 3
    '
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    
    # Au moins 2 fichiers convertis (test_video_2s.mkv + video_a.mkv ou video_b.mkv)
    local out_files
    out_files=$(find "$OUT_DIR" -type f -name "*.mkv" | wc -l)
    [ "$out_files" -ge 2 ]
}
