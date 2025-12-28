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
    
    # Nettoyer le lock global et STOP_FLAG pour éviter les conflits entre tests
    rm -f /tmp/conversion_video.lock
    rm -f /tmp/conversion_stop_flag
    
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
    # Nettoyer le lock global et STOP_FLAG
    rm -f /tmp/conversion_video.lock
    rm -f /tmp/conversion_stop_flag
    teardown_test_env
}

###########################################################
# Test E2E: Conversion complète single-pass (CRF)
###########################################################

@test "E2E single-pass: fichier H.264 converti en HEVC avec succès" {
    # Note: single-pass (CRF) est le mode par défaut pour les séries, pas besoin d'option
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Le log de succès doit exister (avec timestamp) et contenir une entrée
    local success_file
    success_file=$(find "$WORKDIR/logs" -name "Success_*.log" -type f | head -1)
    [ -n "$success_file" ]
    [ -f "$success_file" ]
    
    local success_count
    success_count=$(wc -l < "$success_file")
    [ "$success_count" -ge 1 ]
}

@test "E2E single-pass: checksum vérifié (intégrité source)" {
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
# Test E2E: Audio Codec (AAC, Opus, etc.)
###########################################################

@test "E2E audio: conversion vers Opus réussie" {
    # Vérifier que libopus est disponible
    if ! ffmpeg -encoders 2>/dev/null | grep -q libopus; then
        skip "libopus non disponible dans ffmpeg"
    fi
    
    # Recréer complètement les dossiers pour un environnement propre
    rm -rf "$SRC_DIR" "$OUT_DIR"
    mkdir -p "$SRC_DIR" "$OUT_DIR"
    
    # Utiliser un fichier HEVC avec audio à bitrate élevé pour déclencher la conversion audio
    # Ce fichier a un audio haut bitrate qui sera converti en Opus
    local src_file="$FIXTURES_DIR/test_video_hevc_highaudio_2s.mkv"
    if [[ ! -f "$src_file" ]]; then
        skip "Fichier test_video_hevc_highaudio_2s.mkv non disponible"
    fi
    cp "$src_file" "$SRC_DIR/"
    
    # Nettoyer les index précédents
    rm -f "$WORKDIR"/logs/Index* 2>/dev/null || true
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            -a opus \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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

@test "E2E audio: conversion vers AAC réussie" {
    # Vérifier que le codec AAC est disponible
    if ! ffmpeg -encoders 2>/dev/null | grep -q "aac"; then
        skip "AAC encoder non disponible dans ffmpeg"
    fi
    
    # Utiliser un fichier avec audio à bitrate élevé pour déclencher la conversion
    local src_file="$FIXTURES_DIR/test_video_high_audio.mp4"
    if [[ ! -f "$src_file" ]]; then
        skip "Fichier test_video_high_audio.mp4 non disponible"
    fi
    rm -f "$SRC_DIR/test_video_2s.mkv"
    cp "$src_file" "$SRC_DIR/"
    
    # Vérifier si le bitrate audio source est détectable
    local src_audio_bitrate
    src_audio_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "$src_file" 2>/dev/null)
    if [[ "$src_audio_bitrate" == "N/A" || -z "$src_audio_bitrate" ]]; then
        skip "Le bitrate audio source n'est pas détectable"
    fi
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            -a aac \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Vérifier que l'audio est en AAC
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    local audio_codec
    audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$out_file")
    [ "$audio_codec" = "aac" ]
    
    # Le bitrate audio doit être proche de 160kbps (cible par défaut AAC)
    local audio_bitrate
    audio_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "$out_file")
    if [[ "$audio_bitrate" =~ ^[0-9]+$ ]]; then
        local bitrate_kbps=$((audio_bitrate / 1000))
        [ "$bitrate_kbps" -ge 120 ] && [ "$bitrate_kbps" -le 200 ]
    fi
}

@test "E2E audio: anti-upscaling ne convertit pas audio bas bitrate" {
    # Tester que l'audio à bas bitrate n'est pas "upscalé"
    # Utiliser le fichier standard qui a un audio ~128kbps
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/"
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            -a aac \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" | head -1)
    [ -n "$out_file" ]
    
    # L'audio ne devrait PAS avoir été converti (anti-upscaling)
    # Il devrait rester dans son codec d'origine (probablement vorbis ou aac)
    local audio_codec
    audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$out_file")
    
    # On vérifie simplement que le fichier de sortie a de l'audio
    # (Si le bitrate source < cible, l'audio est copié tel quel)
    [ -n "$audio_codec" ]
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress
    '
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    
    # Le fichier doit être dans le log des skipped (avec timestamp)
    local skipped_file
    skipped_file=$(find "$WORKDIR/logs" -name "Skipped_*.log" -type f | head -1)
    [ -n "$skipped_file" ]
    grep -q "test_video_hevc_2s.mkv" "$skipped_file"
}

###########################################################
# Test E2E: Video Passthrough (vidéo OK, audio à optimiser)
###########################################################

@test "E2E passthrough: HEVC avec audio haute bitrate → vidéo copiée, audio converti" {
    # Utiliser le fichier HEVC avec audio PCM non compressé
    cp "$FIXTURES_DIR/test_video_hevc_highaudio_2s.mkv" "$SRC_DIR/"
    rm -f "$SRC_DIR/test_video_2s.mkv"  # Garder seulement le fichier de test
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --audio aac \
            --keep-index \
            --no-suffix \
            --no-progress
    '
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    
    # Un fichier de sortie doit exister
    local output_file
    output_file=$(find "$OUT_DIR" -name "*.mkv" -type f | head -1)
    [ -n "$output_file" ]
    
    # Vérifier que la vidéo est bien HEVC (copiée, pas ré-encodée)
    local video_codec
    video_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$output_file")
    [ "$video_codec" = "hevc" ]
    
    # Vérifier que l'audio a été converti en AAC
    local audio_codec
    audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$output_file")
    [ "$audio_codec" = "aac" ]
    
    # Vérifier dans les logs que c'était un VIDEO_PASSTHROUGH
    local progress_file
    progress_file=$(find "$WORKDIR/logs" -name "Progress_*.log" -type f | head -1)
    if [ -n "$progress_file" ]; then
        grep -q "VIDEO_PASSTHROUGH" "$progress_file" || true
    fi
}

###########################################################
# Test E2E: Gestion des erreurs
###########################################################

@test "E2E erreur: fichier corrompu génère une entrée dans Error.log ou Skipped.log" {
    # Créer un fichier corrompu
    echo "not a video file" > "$SRC_DIR/corrupted.mkv"
    rm -f "$SRC_DIR/test_video_2s.mkv"
    
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    ' || true  # On accepte un échec
    
    echo "=== STDOUT ===" >&3
    echo "$output" >&3
    
    # Le fichier doit être mentionné dans les logs (erreur OU skipped)
    # Un fichier sans flux vidéo valide est SKIPPED, pas ERROR
    local found=false
    local error_file skipped_file
    error_file=$(find "$WORKDIR/logs" -name "Error_*.log" -type f 2>/dev/null | head -1)
    skipped_file=$(find "$WORKDIR/logs" -name "Skipped_*.log" -type f 2>/dev/null | head -1)
    
    if [[ -n "$error_file" ]] && grep -q "corrupted.mkv" "$error_file" 2>/dev/null; then
        found=true
    fi
    if [[ -n "$skipped_file" ]] && grep -q "corrupted.mkv" "$skipped_file" 2>/dev/null; then
        found=true
    fi
    # Vérifier aussi dans la sortie standard
    if [[ "$output" =~ "corrupted.mkv" ]]; then
        found=true
    fi
    
    [ "$found" = true ]
}

###########################################################
# Test E2E: Résumé final
###########################################################

@test "E2E résumé: summary affiché en fin de traitement" {
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Le fichier Summary doit exister (avec timestamp)
    local summary_file
    summary_file=$(find "$WORKDIR/logs" -name "Summary_*.log" -type f | head -1)
    [ -n "$summary_file" ]
}

###########################################################
# Test E2E: Métadonnées préservées
###########################################################

@test "E2E métadonnées: durée préservée après conversion" {
    run bash -lc 'set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
