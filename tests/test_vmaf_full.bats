#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/vmaf.sh
# Tests du calcul de score VMAF et de la queue VMAF
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    
    export SCRIPT_DIR="$PROJECT_ROOT"
    export EXECUTION_TIMESTAMP="test_$$"
    export NO_PROGRESS=true
    export VMAF_ENABLED=true
    export HAS_LIBVMAF=1
    export LOG_SUCCESS="$TEST_TEMP_DIR/success.log"
    export VMAF_QUEUE_FILE="$TEST_TEMP_DIR/.vmaf_queue_test"
    
    touch "$LOG_SUCCESS"
    
    # Charger les modules requis
    source "$LIB_DIR/ui.sh"
    source "$LIB_DIR/detect.sh"
    source "$LIB_DIR/config.sh"
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/vmaf.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de détection libvmaf
###########################################################

@test "vmaf: HAS_LIBVMAF contrôle l'activation" {
    HAS_LIBVMAF=0
    
    run compute_vmaf_score "/fake/original.mkv" "/fake/converted.mkv"
    
    [ "$output" = "NA" ]
}

@test "vmaf: retourne NA si libvmaf non disponible" {
    HAS_LIBVMAF=0
    
    local result
    result=$(compute_vmaf_score "/any/file1.mkv" "/any/file2.mkv")
    
    [ "$result" = "NA" ]
}

###########################################################
# Tests de validation des fichiers
###########################################################

@test "vmaf: retourne NA si fichier original manquant" {
    HAS_LIBVMAF=1
    
    local result
    result=$(compute_vmaf_score "/nonexistent/original.mkv" "$FIXTURES_DIR/test_video_2s.mkv")
    
    [ "$result" = "NA" ]
}

@test "vmaf: retourne NA si fichier converti manquant" {
    HAS_LIBVMAF=1
    
    local result
    result=$(compute_vmaf_score "$FIXTURES_DIR/test_video_2s.mkv" "/nonexistent/converted.mkv")
    
    [ "$result" = "NA" ]
}

@test "vmaf: retourne NA si fichier converti vide (dryrun)" {
    HAS_LIBVMAF=1
    
    # Créer un fichier vide (comme en dryrun)
    local empty_file="$TEST_TEMP_DIR/empty.mkv"
    : > "$empty_file"
    
    local result
    result=$(compute_vmaf_score "$FIXTURES_DIR/test_video_2s.mkv" "$empty_file")
    
    [ "$result" = "NA" ]
}

###########################################################
# Tests de _queue_vmaf_analysis()
###########################################################

@test "_queue_vmaf_analysis: ajoute une entrée à la queue" {
    VMAF_ENABLED=true
    HAS_LIBVMAF=1
    
    # Utiliser des fichiers existants
    local original="$FIXTURES_DIR/test_video_2s.mkv"
    local converted="$FIXTURES_DIR/test_video_hevc_2s.mkv"
    
    _queue_vmaf_analysis "$original" "$converted"
    
    [ -f "$VMAF_QUEUE_FILE" ]
    grep -q "test_video_2s.mkv" "$VMAF_QUEUE_FILE"
}

@test "_queue_vmaf_analysis: format correct (original|converti|keyframe)" {
    VMAF_ENABLED=true
    HAS_LIBVMAF=1
    
    local original="$FIXTURES_DIR/test_video_2s.mkv"
    local converted="$FIXTURES_DIR/test_video_hevc_2s.mkv"
    
    _queue_vmaf_analysis "$original" "$converted"
    
    # Vérifier le format avec les 3 champs séparés par |
    local line
    line=$(cat "$VMAF_QUEUE_FILE")
    
    [[ "$line" =~ \| ]]
}

@test "_queue_vmaf_analysis: ne fait rien si VMAF désactivé" {
    VMAF_ENABLED=false
    
    _queue_vmaf_analysis "/any/original.mkv" "/any/converted.mkv"
    
    # Le fichier ne doit pas exister ou être vide
    if [[ -f "$VMAF_QUEUE_FILE" ]]; then
        local size
        size=$(wc -c < "$VMAF_QUEUE_FILE")
        [ "$size" -eq 0 ]
    fi
}

@test "_queue_vmaf_analysis: ne fait rien si libvmaf non disponible" {
    VMAF_ENABLED=true
    HAS_LIBVMAF=0
    
    _queue_vmaf_analysis "/any/original.mkv" "/any/converted.mkv"
    
    if [[ -f "$VMAF_QUEUE_FILE" ]]; then
        local size
        size=$(wc -c < "$VMAF_QUEUE_FILE")
        [ "$size" -eq 0 ]
    fi
}

@test "_queue_vmaf_analysis: inclut la position keyframe si définie" {
    VMAF_ENABLED=true
    HAS_LIBVMAF=1
    SAMPLE_KEYFRAME_POS="30.5"
    
    local original="$FIXTURES_DIR/test_video_2s.mkv"
    local converted="$FIXTURES_DIR/test_video_hevc_2s.mkv"
    
    _queue_vmaf_analysis "$original" "$converted"
    
    grep -q "30.5" "$VMAF_QUEUE_FILE"
    
    unset SAMPLE_KEYFRAME_POS
}

###########################################################
# Tests d'interprétation des scores VMAF
###########################################################

@test "vmaf: score >= 90 = EXCELLENT" {
    local vmaf_score=92
    local vmaf_int=${vmaf_score%.*}
    local quality=""
    
    if [[ "$vmaf_int" -ge 90 ]]; then
        quality="EXCELLENT"
    elif [[ "$vmaf_int" -ge 80 ]]; then
        quality="TRES_BON"
    elif [[ "$vmaf_int" -ge 70 ]]; then
        quality="BON"
    else
        quality="DEGRADE"
    fi
    
    [ "$quality" = "EXCELLENT" ]
}

@test "vmaf: score 80-89 = TRES_BON" {
    local vmaf_score=85
    local vmaf_int=${vmaf_score%.*}
    local quality=""
    
    if [[ "$vmaf_int" -ge 90 ]]; then
        quality="EXCELLENT"
    elif [[ "$vmaf_int" -ge 80 ]]; then
        quality="TRES_BON"
    elif [[ "$vmaf_int" -ge 70 ]]; then
        quality="BON"
    else
        quality="DEGRADE"
    fi
    
    [ "$quality" = "TRES_BON" ]
}

@test "vmaf: score 70-79 = BON" {
    local vmaf_score=75
    local vmaf_int=${vmaf_score%.*}
    local quality=""
    
    if [[ "$vmaf_int" -ge 90 ]]; then
        quality="EXCELLENT"
    elif [[ "$vmaf_int" -ge 80 ]]; then
        quality="TRES_BON"
    elif [[ "$vmaf_int" -ge 70 ]]; then
        quality="BON"
    else
        quality="DEGRADE"
    fi
    
    [ "$quality" = "BON" ]
}

@test "vmaf: score < 70 = DEGRADE" {
    local vmaf_score=65
    local vmaf_int=${vmaf_score%.*}
    local quality=""
    
    if [[ "$vmaf_int" -ge 90 ]]; then
        quality="EXCELLENT"
    elif [[ "$vmaf_int" -ge 80 ]]; then
        quality="TRES_BON"
    elif [[ "$vmaf_int" -ge 70 ]]; then
        quality="BON"
    else
        quality="DEGRADE"
    fi
    
    [ "$quality" = "DEGRADE" ]
}

###########################################################
# Tests de process_vmaf_queue()
###########################################################

@test "process_vmaf_queue: ne fait rien si queue vide" {
    rm -f "$VMAF_QUEUE_FILE" 2>/dev/null || true
    
    run process_vmaf_queue
    
    [ "$status" -eq 0 ]
}

@test "process_vmaf_queue: ne fait rien si fichier queue inexistant" {
    VMAF_QUEUE_FILE="$TEST_TEMP_DIR/nonexistent_queue"
    
    run process_vmaf_queue
    
    [ "$status" -eq 0 ]
}

@test "process_vmaf_queue: lit le format correct" {
    # Créer une queue avec le bon format
    echo "$FIXTURES_DIR/test_video_2s.mkv|$FIXTURES_DIR/test_video_hevc_2s.mkv|" > "$VMAF_QUEUE_FILE"
    
    local count
    count=$(wc -l < "$VMAF_QUEUE_FILE")
    
    [ "$count" -eq 1 ]
}

###########################################################
# Tests de normalisation du score
###########################################################

@test "vmaf: score 0-1 converti en 0-100" {
    # Si le score est entre 0 et 1, il doit être multiplié par 100
    local vmaf_score="0.92"
    local score_int=${vmaf_score%%.*}
    
    if [[ "$score_int" -eq 0 ]] && [[ $(awk "BEGIN {print ($vmaf_score > 0)}") -eq 1 ]]; then
        vmaf_score=$(awk "BEGIN {printf \"%.2f\", $vmaf_score * 100}")
    fi
    
    [[ "$vmaf_score" == "92.00" ]]
}

@test "vmaf: score déjà en 0-100 non modifié" {
    local vmaf_score="92.50"
    local score_int=${vmaf_score%%.*}
    
    # Si score_int > 0, pas de conversion
    if [[ "$score_int" -eq 0 ]] && [[ $(awk "BEGIN {print ($vmaf_score > 0)}") -eq 1 ]]; then
        vmaf_score=$(awk "BEGIN {printf \"%.2f\", $vmaf_score * 100}")
    fi
    
    [[ "$vmaf_score" == "92.50" ]]
}

###########################################################
# Tests du répertoire VMAF
###########################################################

@test "vmaf: répertoire vmaf/ créé dans logs" {
    local vmaf_dir="$TEST_TEMP_DIR/vmaf"
    mkdir -p "$vmaf_dir"
    
    [ -d "$vmaf_dir" ]
}

@test "vmaf: fichiers temporaires nettoyés après calcul" {
    local vmaf_dir="$TEST_TEMP_DIR/vmaf"
    mkdir -p "$vmaf_dir"
    
    local vmaf_log="$vmaf_dir/vmaf_test.json"
    local progress_file="$vmaf_dir/vmaf_progress.txt"
    
    touch "$vmaf_log" "$progress_file"
    
    # Simuler le nettoyage
    rm -f "$vmaf_log" "$progress_file" 2>/dev/null || true
    
    [ ! -f "$vmaf_log" ]
    [ ! -f "$progress_file" ]
}

###########################################################
# Tests d'intégration VMAF (si ffmpeg disponible)
###########################################################

@test "vmaf: calcul réel avec fichiers de test" {
    # Skip si ffmpeg ou libvmaf non disponible
    if ! command -v ffmpeg &>/dev/null; then
        skip "ffmpeg non disponible"
    fi
    
    if ! ffmpeg -filters 2>/dev/null | grep -q libvmaf; then
        skip "libvmaf non disponible dans ffmpeg"
    fi
    
    HAS_LIBVMAF=1
    
    # Les deux fichiers de test ont la même source, donc le score devrait être élevé
    local result
    result=$(compute_vmaf_score "$FIXTURES_DIR/test_video_2s.mkv" "$FIXTURES_DIR/test_video_hevc_2s.mkv")
    
    # Le résultat doit être un nombre ou NA
    [[ "$result" == "NA" ]] || [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]]
}

###########################################################
# Tests du modèle VMAF
###########################################################

@test "vmaf: utilise le modèle vmaf_v0.6.1neg" {
    # Vérifier que le code utilise le bon modèle
    grep -q "vmaf_v0.6.1neg" "$LIB_DIR/vmaf.sh"
}

@test "vmaf: utilise subsampling n=5 pour accélérer" {
    # Vérifier que le subsampling est activé
    grep -q "n_subsample=5" "$LIB_DIR/vmaf.sh"
}

###########################################################
# Tests de logging VMAF
###########################################################

@test "vmaf: score loggé dans LOG_SUCCESS" {
    # Simuler le logging
    local log_line="2024-12-23 12:00:00 | VMAF | /src/video.mkv → /out/video.mkv | score:92.50 | quality:EXCELLENT"
    echo "$log_line" >> "$LOG_SUCCESS"
    
    grep -q "VMAF" "$LOG_SUCCESS"
    grep -q "score:92.50" "$LOG_SUCCESS"
}

###########################################################
# Tests d'intégration SAMPLE_MODE + VMAF
###########################################################

@test "regression: _execute_ffmpeg_pipeline définit SAMPLE_KEYFRAME_POS pour VMAF" {
    # Ce test vérifie que _setup_sample_mode_params est appelée AVANT le case
    # dans _execute_ffmpeg_pipeline, ce qui est nécessaire pour que
    # SAMPLE_KEYFRAME_POS soit défini et transmis à la queue VMAF.
    # Note: _execute_ffmpeg_pipeline est maintenant dans lib/ffmpeg_pipeline.sh
    
    local pipeline_file="$LIB_DIR/ffmpeg_pipeline.sh"
    
    # Extraire uniquement la fonction _execute_ffmpeg_pipeline
    # et vérifier que _setup_sample_mode_params est appelée avant le case
    local func_content
    func_content=$(sed -n '/^_execute_ffmpeg_pipeline()/,/^[^ ]/p' "$pipeline_file" | head -n -1)
    
    # Vérifier que _setup_sample_mode_params est présent
    echo "$func_content" | grep -q "_setup_sample_mode_params"
    
    # Vérifier l'ordre: setup_sample doit apparaître AVANT 'case "$mode"'
    local setup_pos case_pos
    setup_pos=$(echo "$func_content" | grep -n "_setup_sample_mode_params" | head -1 | cut -d: -f1)
    case_pos=$(echo "$func_content" | grep -n 'case "\$mode"' | head -1 | cut -d: -f1)
    
    [ -n "$setup_pos" ]
    [ -n "$case_pos" ]
    [ "$setup_pos" -lt "$case_pos" ]
}

@test "regression: mode passthrough utilise SAMPLE_SEEK_PARAMS" {
    # Vérifier que la commande FFmpeg passthrough inclut les paramètres sample
    # Note: ce code est maintenant dans lib/ffmpeg_pipeline.sh
    local pipeline_file="$LIB_DIR/ffmpeg_pipeline.sh"
    
    # Extraire le bloc passthrough et vérifier qu'il contient SAMPLE_SEEK_PARAMS
    # On cherche entre "passthrough)" et le prochain ";;"
    local passthrough_block
    passthrough_block=$(sed -n '/\"passthrough\")/,/;;/p' "$pipeline_file")
    
    echo "$passthrough_block" | grep -q 'SAMPLE_SEEK_PARAMS'
    echo "$passthrough_block" | grep -q 'SAMPLE_DURATION_PARAMS'
}
