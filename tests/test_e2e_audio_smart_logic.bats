#!/usr/bin/env bats
###########################################################
# TESTS E2E - Logique Smart Audio avec vrais fichiers
# Vérifie que la détection des codecs fonctionne avec FFmpeg réel
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/media_probe.sh"
    
    # Vérifier présence ffmpeg
    if ! command -v ffmpeg >/dev/null; then
        skip "ffmpeg non trouvé"
    fi
}

teardown() {
    teardown_test_env
}

# Génère un petit fichier vidéo de test
# Usage: generate_test_video <filename> <audio_codec> <audio_bitrate>
generate_test_video() {
    local filename="$1"
    local acodec="$2"
    local abitrate="$3"
    
    # Génération 1 seconde de vidéo noire + audio sine
    # Utilisation de -y pour écraser
    run ffmpeg -y -hide_banner -loglevel error \
        -f lavfi -i color=c=black:s=640x480:d=1 \
        -f lavfi -i sine=frequency=1000:duration=1 \
        -c:v libx264 -preset ultrafast \
        -c:a "$acodec" -b:a "$abitrate" \
        "$filename"
        
    if [ "$status" -ne 0 ]; then
        echo "Erreur génération vidéo: $output" >&2
        return 1
    fi
}

@test "E2E: Détecte et convertit AC3 (inefficace) vers AAC" {
    local test_file="$TEST_TEMP_DIR/test_ac3.mkv"
    
    # Générer un fichier avec AC3 192k
    # Note: ac3 est supporté par défaut dans ffmpeg
    generate_test_video "$test_file" "ac3" "192k"
    
    # Configurer pour cible AAC (défaut)
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    
    # 1. Test via _get_audio_conversion_info (logique interne)
    # Cette fonction fait son propre probe si pas d'args
    run _get_audio_conversion_info "$test_file"
    
    [ "$status" -eq 0 ]
    # Format retour: codec|bitrate|should_convert
    # On s'attend à ce que should_convert soit 1 (true) car AC3 est "inefficace" vs AAC
    local should_convert=$(echo "$output" | cut -d'|' -f3)
    local detected_codec=$(echo "$output" | cut -d'|' -f1)
    
    [ "$detected_codec" = "ac3" ]
    [ "$should_convert" -eq 1 ]
}

@test "E2E: Détecte et conserve AAC (efficace)" {
    local test_file="$TEST_TEMP_DIR/test_aac.mkv"
    
    # Générer un fichier avec AAC 128k
    generate_test_video "$test_file" "aac" "128k"
    
    # Configurer pour cible AAC
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=160
    
    run _get_audio_conversion_info "$test_file"
    
    [ "$status" -eq 0 ]
    local should_convert=$(echo "$output" | cut -d'|' -f3)
    local detected_codec=$(echo "$output" | cut -d'|' -f1)
    
    [ "$detected_codec" = "aac" ]
    # AAC source (128k) <= Cible (160k) -> Pas de conversion nécessaire
    [ "$should_convert" -eq 0 ]
}

@test "E2E: Détecte et convertit E-AC3 (inefficace) vers Opus" {
    local test_file="$TEST_TEMP_DIR/test_eac3.mkv"
    
    # Vérifier si l'encodeur eac3 est dispo (souvent expérimental ou absent)
    if ! ffmpeg -encoders | grep -q "eac3"; then
        skip "Encodeur E-AC3 non disponible pour générer le test"
    fi
    
    generate_test_video "$test_file" "eac3" "256k"
    
    # Configurer pour cible Opus
    AUDIO_CODEC="opus"
    
    run _get_audio_conversion_info "$test_file"
    
    [ "$status" -eq 0 ]
    local should_convert=$(echo "$output" | cut -d'|' -f3)
    local detected_codec=$(echo "$output" | cut -d'|' -f1)
    
    # ffprobe peut rapporter "eac3" ou "ec-3"
    [[ "$detected_codec" == "eac3" || "$detected_codec" == "ec-3" ]]
    
    # E-AC3 est moins efficace que Opus -> conversion
    [ "$should_convert" -eq 1 ]
}

@test "E2E: Intégration complète avec get_full_media_metadata" {
    local test_file="$TEST_TEMP_DIR/test_full.mkv"
    generate_test_video "$test_file" "ac3" "384k"
    
    # 1. Récupérer les métadonnées complètes (nouvelle fonction optimisée)
    run get_full_media_metadata "$test_file"
    [ "$status" -eq 0 ]
    
    # Format: v_bitrate|v_codec|duration|width|height|pix_fmt|a_codec|a_bitrate
    local meta="$output"
    local a_codec=$(echo "$meta" | cut -d'|' -f7)
    local a_bitrate=$(echo "$meta" | cut -d'|' -f8)
    
    [ "$a_codec" = "ac3" ]
    # Bitrate peut varier légèrement selon l'encodage, on vérifie juste qu'il est > 0
    [ "$a_bitrate" -gt 0 ]
    
    # 2. Passer ces métadonnées à la décision
    AUDIO_CODEC="aac"
    run _should_convert_audio "$test_file" "$a_codec" "$a_bitrate"
    
    # _should_convert_audio retourne 0 (true) si conversion nécessaire
    [ "$status" -eq 0 ]
}
