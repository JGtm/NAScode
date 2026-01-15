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
    
    # Nettoyer le lock global et STOP_FLAG
    rm -f /tmp/conversion_video.lock
    rm -f /tmp/conversion_stop_flag
    
    # Créer les répertoires de travail
    export WORKDIR="$TEST_TEMP_DIR/work"
    export SRC_DIR="$TEST_TEMP_DIR/src"
    export OUT_DIR="$TEST_TEMP_DIR/out"
    
    mkdir -p "$WORKDIR" "$SRC_DIR" "$OUT_DIR"
}

teardown() {
    rm -f /tmp/conversion_video.lock
    rm -f /tmp/conversion_stop_flag
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
    
    # Chercher dans Session.log (log consolidé)
    local session_log=$(find "$WORKDIR/logs" -name "Session_*.log" -type f 2>/dev/null | head -1)
    
    if [[ -n "$session_log" && -f "$session_log" ]]; then
        if grep -qE "(ERROR|SKIPPED).*corrupted_video" "$session_log" 2>/dev/null; then
            found_in_logs=true
        fi
    fi
    
    # Ou dans la sortie standard (sans dépendre du wording d'erreur)
    if [[ "$output" == *"corrupted_video"* ]]; then
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
# SECTION 4: CAP « QUALITÉ ÉQUIVALENTE » (codec source moins efficace)
###########################################################

@test "E2E EQUIV-QUALITY: H.264 low-bitrate → HEVC ne sur-encode pas (cap)" {
    # Générer une source H.264 en CBR ~1000k (avec audio) pour avoir un bitrate mesurable.
    ffmpeg -y \
        -f lavfi -i "testsrc=duration=2:size=1920x1080:rate=24" \
        -f lavfi -i "sine=frequency=1000:duration=2" \
        -c:v libx264 -preset ultrafast \
        -b:v 1000k -minrate 1000k -maxrate 1000k -bufsize 2000k \
        -x264-params "nal-hrd=cbr" \
        -c:a aac -b:a 96k \
        "$SRC_DIR/src_h264_1000k.mkv" 2>/dev/null

    if [[ ! -f "$SRC_DIR/src_h264_1000k.mkv" ]]; then
        skip "Impossible de créer la vidéo H.264 de test"
    fi

    # Conversion standard (non-adaptive) vers HEVC.
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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

    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*.mkv" 2>/dev/null | head -1)
    [ -n "$out_file" ]

    # Bitrate vidéo source (kbps)
    local src_bits
    src_bits=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$SRC_DIR/src_h264_1000k.mkv" 2>/dev/null | head -1)
    if [[ -z "$src_bits" ]] || ! [[ "$src_bits" =~ ^[0-9]+$ ]] || [[ "$src_bits" -le 0 ]]; then
        skip "Bitrate vidéo source non mesurable (ffprobe)"
    fi
    local src_kbps=$(( src_bits / 1000 ))

    # Bitrate vidéo output (kbps)
    local out_bits
    out_bits=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$out_file" 2>/dev/null | head -1)
    if [[ -z "$out_bits" ]] || ! [[ "$out_bits" =~ ^[0-9]+$ ]] || [[ "$out_bits" -le 0 ]]; then
        skip "Bitrate vidéo output non mesurable (ffprobe)"
    fi
    local out_kbps=$(( out_bits / 1000 ))

    # Cap attendu (codec-aware), calculé via la même fonction que le code.
    local expected_cap_kbps
    expected_cap_kbps=$(bash -lc '
        set -euo pipefail
        source "$PROJECT_ROOT/lib/codec_profiles.sh"
        translate_bitrate_kbps_between_codecs '"$src_kbps"' "h264" "hevc"
    ')

    if [[ -z "$expected_cap_kbps" ]] || ! [[ "$expected_cap_kbps" =~ ^[0-9]+$ ]] || [[ "$expected_cap_kbps" -le 0 ]]; then
        skip "Cap attendu non calculable"
    fi

    # Tolérance: le bitrate réel peut fluctuer; on vérifie surtout qu'on n'est pas proche
    # des budgets par défaut (sans cap). 35% laisse de la marge tout en détectant un oubli.
    local max_allowed_kbps=$(( expected_cap_kbps * 135 / 100 ))

    echo "src_kbps=$src_kbps expected_cap_kbps=$expected_cap_kbps out_kbps=$out_kbps max_allowed_kbps=$max_allowed_kbps" >&3

    [ "$out_kbps" -le "$max_allowed_kbps" ]
}

###########################################################
# SECTION 4: CHEMINS WINDOWS (ACCENTS/ESPACES) + ERREURS I/O
###########################################################

@test "E2E PATHS: chemins avec accents et espaces (source + nom de fichier)" {
    export WEIRD_SRC_DIR="$SRC_DIR/Séries test é"
    mkdir -p "$WEIRD_SRC_DIR"

    cp "$FIXTURES_DIR/test_video_2s.mkv" "$WEIRD_SRC_DIR/Épisode 01 - test éà.mkv"

    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$WEIRD_SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '

    echo "=== OUTPUT ===" >&3
    echo "$output" >&3

    [ "$status" -eq 0 ]

    local out_files
    out_files=$(find "$OUT_DIR" -type f -name "*.mkv" 2>/dev/null | wc -l)
    [ "$out_files" -ge 1 ]
}

@test "E2E I/O: output_dir est un fichier (pas un dossier)" {
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/test_io_error.mkv"

    export OUT_AS_FILE="$TEST_TEMP_DIR/out_as_file"
    echo "not a dir" > "$OUT_AS_FILE"

    run bash -lc '
        set -u
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_AS_FILE" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '

    echo "=== OUTPUT ===" >&3
    echo "$output" >&3

    # Doit échouer (impossible de créer/écrire dans output_dir)
    [ "$status" -ne 0 ]

    # Et ne pas laisser le lock derrière
    [ ! -f /tmp/conversion_video.lock ]
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
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
    
    # PRIORITÉ: Le fichier converti DOIT être dans output_dir
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
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    [ "$status" -eq 0 ]
    
    # Après une fin normale, le STOP_FLAG NE DOIT PAS exister
    # C'est le comportement corrigé: STOP_FLAG n'est créé que lors d'une vraie interruption
    [ ! -f /tmp/conversion_stop_flag ]
    
    # Le message d'interruption ne doit pas avoir été affiché
    [[ ! "$output" =~ "interrompue" ]]
}

@test "E2E STOP_FLAG: interruption en cours (SIGINT) nettoie le lock" {
    # Objectif: simuler un Ctrl+C pendant une conversion et vérifier le cleanup

    # Générer une vidéo un peu plus longue pour réduire la flakiness
    ffmpeg -y -f lavfi -i "testsrc=duration=12:size=1920x1080:rate=24" \
        -c:v libx264 -preset ultrafast -crf 35 \
        "$SRC_DIR/long_test_interrupt.mkv" 2>/dev/null

    if [[ ! -f "$SRC_DIR/long_test_interrupt.mkv" ]]; then
        skip "Impossible de créer la vidéo longue de test"
    fi

    rm -f /tmp/conversion_video.lock /tmp/conversion_stop_flag

    run bash -lc '
        set -u
        cd "$WORKDIR"

        # Lancer NAScode en arrière-plan
        bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1 <<< "n" &
        pid=$!

        # Attendre que NAScode ait réellement démarré (évite les faux négatifs si ça finit trop vite)
        # - lockfile créé
        # - et/ou répertoire TMP_DIR initialisé
        for i in {1..50}; do
            [[ -f /tmp/conversion_video.lock ]] && break
            sleep 0.1
        done
        for i in {1..50}; do
            [[ -d /tmp/video_convert ]] && break
            sleep 0.1
        done

        # Simuler une interruption.
        # Note: Sous Bash/MSYS2, les jobs en arrière-plan peuvent ignorer SIGINT.
        # SIGTERM est plus fiable et est géré par le même trap (_handle_interrupt).
        kill -TERM "$pid" 2>/dev/null || true

        wait "$pid"
        exit_code=$?
        echo "NASCODE_EXIT=$exit_code"

        # Ne pas propager l'exit code ici: le test Bats doit pouvoir l'asserter
        exit 0
    '

    echo "=== OUTPUT ===" >&3
    echo "$output" >&3

    # Le script doit avoir reçu l'interruption (code 130 attendu)
    [[ "$output" =~ "NASCODE_EXIT=130" ]]

    # Le lock doit être nettoyé par cleanup()
    [ ! -f /tmp/conversion_video.lock ]

    # Et un STOP_FLAG doit exister (vraie interruption)
    [ -f /tmp/conversion_stop_flag ]
}

@test "E2E OUTPUT_DIR: fichier converti arrive bien dans output_dir" {
    # PRIORITÉ: Vérifier que le fichier final est dans le bon répertoire
    # Régression: fichier restait dans /tmp/video_convert/ au lieu d'être déplacé
    
    cp "$FIXTURES_DIR/test_video_2s.mkv" "$SRC_DIR/test_output_dir.mkv"
    
    # S'assurer que STOP_FLAG n'existe pas (cause du bug de non-déplacement)
    rm -f /tmp/conversion_stop_flag
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --keep-index \
            --no-suffix \
            --no-progress \
            --limit 1
    '
    
    echo "=== OUTPUT ===" >&3
    echo "$output" >&3
    echo "=== Contenu OUT_DIR ===" >&3
    ls -la "$OUT_DIR" >&3 2>&1 || true
    
    [ "$status" -eq 0 ]
    
    # Le fichier DOIT être dans output_dir
    local out_file
    out_file=$(find "$OUT_DIR" -type f -name "*test_output_dir*.mkv" 2>/dev/null | head -1)
    [ -n "$out_file" ]
    [ -f "$out_file" ]
    
    # Vérifier que le fichier n'est PAS resté dans /tmp
    local tmp_file
    tmp_file=$(find /tmp/video_convert -type f -name "*test_output_dir*.mkv" 2>/dev/null | head -1) || tmp_file=""
    [ -z "$tmp_file" ]
    
    # Pas de message d'interruption
    [[ ! "$output" =~ "Conversion interrompue" ]]
    [[ ! "$output" =~ "fichier temporaire conservé" ]]
}

###########################################################
# SECTION 7: HFR (HIGH FRAME RATE)
###########################################################

@test "E2E HFR: vidéo 60fps avec --limit-fps produit output ≤30fps" {
    # Créer une vidéo 60fps de 1 seconde
    ffmpeg -y -f lavfi -i "testsrc=duration=1:size=1920x1080:rate=60" \
        -c:v libx264 -preset ultrafast -crf 51 \
        "$SRC_DIR/test_60fps.mkv" 2>/dev/null
    
    if [[ ! -f "$SRC_DIR/test_60fps.mkv" ]]; then
        skip "Impossible de créer la vidéo 60fps de test"
    fi
    
    # Vérifier que la source est bien 60fps
    local src_fps
    src_fps=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=r_frame_rate -of csv=p=0 "$SRC_DIR/test_60fps.mkv")
    echo "Source FPS: $src_fps" >&3
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode serie \
            --limit-fps \
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
        # Vérifier le framerate de sortie (format: num/den, ex: 30000/1001)
        local out_fps_raw
        out_fps_raw=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=r_frame_rate -of csv=p=0 "$out_file")
        
        echo "Output FPS raw: $out_fps_raw" >&3
        
        # Calculer le fps effectif (num/den → float)
        local out_fps
        out_fps=$(echo "$out_fps_raw" | awk -F'/' '{if(NF==2 && $2>0) printf "%.2f", $1/$2; else print $1}')
        
        echo "Output FPS: $out_fps" >&3
        
        # Le FPS doit être ≤ 30 (avec marge pour 29.97)
        local fps_ok
        fps_ok=$(echo "$out_fps" | awk '{if($1 <= 30.01) print "yes"; else print "no"}')
        [ "$fps_ok" = "yes" ]
    fi
}

@test "E2E HFR: vidéo 60fps avec --no-limit-fps conserve fps original" {
    # Créer une vidéo 60fps de 1 seconde
    ffmpeg -y -f lavfi -i "testsrc=duration=1:size=1920x1080:rate=60" \
        -c:v libx264 -preset ultrafast -crf 51 \
        "$SRC_DIR/test_60fps_keep.mkv" 2>/dev/null
    
    if [[ ! -f "$SRC_DIR/test_60fps_keep.mkv" ]]; then
        skip "Impossible de créer la vidéo 60fps de test"
    fi
    
    run bash -lc '
        set -euo pipefail
        cd "$WORKDIR"
        printf "n\n" | bash "$PROJECT_ROOT/nascode" \
            -s "$SRC_DIR" -o "$OUT_DIR" \
            --mode film \
            --no-limit-fps \
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
        # Vérifier le framerate de sortie
        local out_fps_raw
        out_fps_raw=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=r_frame_rate -of csv=p=0 "$out_file")
        
        echo "Output FPS raw: $out_fps_raw" >&3
        
        # Calculer le fps effectif
        local out_fps
        out_fps=$(echo "$out_fps_raw" | awk -F'/' '{if(NF==2 && $2>0) printf "%.2f", $1/$2; else print $1}')
        
        echo "Output FPS: $out_fps" >&3
        
        # Le FPS doit être ≥ 50 (proche de 60)
        local fps_ok
        fps_ok=$(echo "$out_fps" | awk '{if($1 >= 50) print "yes"; else print "no"}')
        [ "$fps_ok" = "yes" ]
    fi
}
