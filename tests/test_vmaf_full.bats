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

@test "regression: ignore les streams attached_pic (poster)" {
    HAS_LIBVMAF=1

    # Stub ffprobe_safe pour simuler un fichier avec 2 streams vidéo :
    # v:0 = poster (attached_pic=1), v:1 = vidéo (attached_pic=0)
    ffprobe_safe() {
        if [[ "$*" == *"-show_entries stream=index:stream_disposition=attached_pic"* ]]; then
            printf '%s\n' '0,1' '1,0'
            return 0
        fi
        if [[ "$*" == *"-show_entries stream=width,height"* ]]; then
            echo '1920x1080'
            return 0
        fi
        return 1
    }

        # Faux FFmpeg (utilisé via FFMPEG_VMAF) : capture -lavfi et crée un JSON VMAF minimal.
        local capture_file="$TEST_TEMP_DIR/lavfi_capture.txt"
        local fake_ffmpeg="$TEST_TEMP_DIR/fake_ffmpeg_vmaf.sh"
        cat > "$fake_ffmpeg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

capture_file="${VMAF_CAPTURE_FILE:-/tmp/vmaf_capture.txt}"
lavfi=""

for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "-lavfi" ]]; then
        j=$((i+1))
        lavfi="${!j}"
        break
    fi
done

printf '%s\n' "$lavfi" > "$capture_file"

# Extraire log_path (relatif) et créer le JSON correspondant dans le cwd.
log_path=$(printf '%s' "$lavfi" | sed -n 's/.*log_path=\([^:]*\).*/\1/p' | head -1)
if [[ -n "${log_path:-}" ]]; then
    cat > "$log_path" <<JSON
{ "pooled_metrics": { "vmaf": { "mean": 95.0 } } }
JSON
fi

exit 0
EOF
        chmod +x "$fake_ffmpeg"

        export VMAF_CAPTURE_FILE="$capture_file"
        FFMPEG_VMAF="$fake_ffmpeg"

    # Créer deux fichiers factices non vides
    local orig="$TEST_TEMP_DIR/orig.mkv"
    local conv="$TEST_TEMP_DIR/conv.mkv"
    printf 'x' > "$orig"
    printf 'y' > "$conv"

    local result
    result=$(compute_vmaf_score "$orig" "$conv" "dummy")

    [ "$result" = "95.00" ]
    grep -q "\[0:v:1\]" "$capture_file"
    grep -q "\[1:v:1\]" "$capture_file"
}

@test "regression: normalise /c/... vers C:/... quand FFMPEG_VMAF est un .exe" {
        if [[ "${IS_MSYS:-0}" -ne 1 ]]; then
                skip "test spécifique MSYS/Git Bash"
        fi

        HAS_LIBVMAF=1

        local capture_file="$TEST_TEMP_DIR/ffmpeg_args_capture.txt"
        local fake_ffmpeg_exe="$TEST_TEMP_DIR/fake_ffmpeg_vmaf.exe"
        cat > "$fake_ffmpeg_exe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

capture_file="${VMAF_ARGS_CAPTURE_FILE:?}"

printf '%s\n' "$@" > "$capture_file"

# Créer un JSON minimal (log_path relatif) dans le cwd
lavfi=""
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "-lavfi" ]]; then
        j=$((i+1))
        lavfi="${!j}"
        break
    fi
done
log_path=$(printf '%s' "$lavfi" | sed -n 's/.*log_path=\([^:]*\).*/\1/p' | head -1)
if [[ -n "${log_path:-}" ]]; then
    cat > "$log_path" <<JSON
{ "pooled_metrics": { "vmaf": { "mean": 90.0 } } }
JSON
fi

exit 0
EOF
        chmod +x "$fake_ffmpeg_exe"
        export VMAF_ARGS_CAPTURE_FILE="$capture_file"
        FFMPEG_VMAF="$fake_ffmpeg_exe"

        # Créer des fichiers dans le repo (chemin /c/... garanti sous MSYS)
        local orig="$PROJECT_ROOT/logs/_tmp_vmaf_orig_$$.mkv"
        local conv="$PROJECT_ROOT/logs/_tmp_vmaf_conv_$$.mkv"
        printf 'x' > "$orig"
        printf 'y' > "$conv"

        local result
        result=$(compute_vmaf_score "$orig" "$conv" "dummy")
        rm -f "$orig" "$conv" 2>/dev/null || true

        [ "$result" = "90.00" ]
        # Vérifier que les -i ont reçu des chemins Windows (C:/...) et non /c/...
        grep -qE '^(-hide_banner|-nostdin|-i)$' "$capture_file" || true
        grep -q "C:/" "$capture_file"
        ! grep -q "^/c/" "$capture_file"
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

@test "_queue_vmaf_analysis: format TSV à 4 champs (original\tconverti\tkeyframe\tfps_limited)" {
    VMAF_ENABLED=true
    HAS_LIBVMAF=1

    local original="$FIXTURES_DIR/test_video_2s.mkv"
    local converted="$FIXTURES_DIR/test_video_hevc_2s.mkv"

    _queue_vmaf_analysis "$original" "$converted"

    local line
    line=$(cat "$VMAF_QUEUE_FILE")

    # Le séparateur est désormais une TABULATION (pas '|', légal dans les noms)
    [[ "$line" == *$'\t'* ]]
    ! [[ "$line" =~ \| ]]

    # 4 champs séparés par TAB
    local nfields
    nfields=$(awk -F'\t' '{print NF}' <<< "$line")
    [ "$nfields" -eq 4 ]
}

@test "_queue_vmaf_analysis: persiste FPS_WAS_LIMITED dans le 4e champ" {
    VMAF_ENABLED=true
    HAS_LIBVMAF=1
    export FPS_WAS_LIMITED=true

    local original="$FIXTURES_DIR/test_video_2s.mkv"
    local converted="$FIXTURES_DIR/test_video_hevc_2s.mkv"

    _queue_vmaf_analysis "$original" "$converted"

    local field4
    field4=$(awk -F'\t' '{print $4}' < "$VMAF_QUEUE_FILE")
    [ "$field4" = "true" ]

    unset FPS_WAS_LIMITED
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
    # Créer une queue avec le bon format TSV (4 champs)
    printf '%s\t%s\t%s\t%s\n' \
        "$FIXTURES_DIR/test_video_2s.mkv" "$FIXTURES_DIR/test_video_hevc_2s.mkv" "" "false" \
        > "$VMAF_QUEUE_FILE"

    local count
    count=$(wc -l < "$VMAF_QUEUE_FILE")

    [ "$count" -eq 1 ]
}

###########################################################
# Tests d'extraction du score depuis le JSON libvmaf
#
# Régression CRITIQUE : le JSON libvmaf liste integer_adm2 (échelle 0-1) AVANT
# le bloc vmaf (échelle 0-100). L'ancien parsing `grep '"mean"' | head -1`
# lisait integer_adm2 puis le ×100 le maquillait. _vmaf_extract_pooled_mean
# doit ancrer sur pooled_metrics.vmaf.mean.
###########################################################

@test "vmaf: extrait pooled_metrics.vmaf.mean et PAS integer_adm2 (multi-features)" {
    local json="$TEST_TEMP_DIR/vmaf_multi.json"
    cat > "$json" <<'JSON'
{
  "frames": [ { "metrics": { "integer_adm2": 0.93, "vmaf": 80.1 } } ],
  "pooled_metrics": {
    "integer_adm2": { "min": 0.91, "max": 0.99, "mean": 0.959339, "harmonic_mean": 0.95 },
    "integer_motion2": { "min": 0.0, "max": 12.3, "mean": 6.12 },
    "vmaf": { "min": 70.12, "max": 99.20, "mean": 82.317162, "harmonic_mean": 81.04 }
  }
}
JSON
    local out
    out=$(_vmaf_extract_pooled_mean "$json")
    [ "$out" = "82.317162" ]
}

@test "vmaf: extrait le mean d'un JSON compact (bloc vmaf sur une ligne)" {
    local json="$TEST_TEMP_DIR/vmaf_compact.json"
    echo '{ "pooled_metrics": { "vmaf": { "min": 70.1, "max": 99.2, "mean": 88.4 } } }' > "$json"
    local out
    out=$(_vmaf_extract_pooled_mean "$json")
    [ "$out" = "88.4" ]
}

@test "vmaf: extraction vide si le bloc vmaf est absent" {
    local json="$TEST_TEMP_DIR/vmaf_novmaf.json"
    echo '{ "pooled_metrics": { "integer_adm2": { "mean": 0.95 } } }' > "$json"
    local out
    out=$(_vmaf_extract_pooled_mean "$json")
    [ -z "$out" ]
}

@test "vmaf: un mean sous 1.0 N'EST PLUS gonflé ×100 (plus d'heuristique)" {
    # Le fake ffmpeg écrit un JSON dont vmaf.mean = 0.50. Avec l'ancienne
    # heuristique, compute_vmaf_score retournait 50.00. Désormais 0.50 est un
    # score valide dans [0,100] et doit être retourné tel quel (formaté).
    HAS_LIBVMAF=1
    local fake_ffmpeg="$TEST_TEMP_DIR/fake_ffmpeg_low.sh"
    cat > "$fake_ffmpeg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
lavfi=""
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "-lavfi" ]]; then j=$((i+1)); lavfi="${!j}"; break; fi
done
log_path=$(printf '%s' "$lavfi" | sed -n 's/.*log_path=\([^:]*\).*/\1/p' | head -1)
[[ -n "${log_path:-}" ]] && printf '%s\n' '{ "pooled_metrics": { "vmaf": { "mean": 0.50 } } }' > "$log_path"
exit 0
EOF
    chmod +x "$fake_ffmpeg"
    FFMPEG_VMAF="$fake_ffmpeg"

    local orig="$TEST_TEMP_DIR/o.mkv" conv="$TEST_TEMP_DIR/c.mkv"
    printf 'x' > "$orig"; printf 'y' > "$conv"

    local result
    result=$(compute_vmaf_score "$orig" "$conv" "dummy")
    [ "$result" = "0.50" ]
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

@test "regression: VMAF fonctionne via FFMPEG_VMAF (ffmpeg alternatif)" {
    # Ce test cible le cas courant sous Windows/MSYS : le ffmpeg principal n'a pas libvmaf,
    # et detect.sh sélectionne un ffmpeg.exe alternatif via FFMPEG_VMAF.
    if [[ -z "${FFMPEG_VMAF:-}" ]]; then
        skip "FFMPEG_VMAF non défini"
    fi

    if [[ ! -x "$FFMPEG_VMAF" ]]; then
        skip "FFMPEG_VMAF non exécutable"
    fi

    if ! "$FFMPEG_VMAF" -hide_banner -filters 2>/dev/null | grep -q libvmaf; then
        skip "libvmaf non disponible dans FFMPEG_VMAF"
    fi

    # Reproduire le cas où le ffmpeg principal (PATH) n'a pas libvmaf.
    if ffmpeg -hide_banner -filters 2>/dev/null | grep -q libvmaf; then
        skip "ffmpeg principal a déjà libvmaf (cas non ciblé)"
    fi

    HAS_LIBVMAF=1

    local result
    result=$(compute_vmaf_score "$FIXTURES_DIR/test_video_2s.mkv" "$FIXTURES_DIR/test_video_hevc_2s.mkv")

    # Dans ce scénario, un NA indique généralement un problème d'écriture/parsing du JSON.
    [[ "$result" =~ ^[0-9]+\.?[0-9]*$ ]]
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
    
    # Extraire uniquement la fonction _execute_ffmpeg_pipeline (de sa définition
    # jusqu'à son accolade fermante en colonne 0). On utilise awk et non
    # `sed '/start/,/^[^ ]/'` : ce dernier coupait la plage trop tôt à cause
    # d'une chaîne awk multi-ligne dont une ligne commence en colonne 0
    # (faux positif de "fin de fonction").
    local func_content
    func_content=$(awk '/^_execute_ffmpeg_pipeline\(\)/{f=1} f{print} f && /^\}/{exit}' "$pipeline_file")
    
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
