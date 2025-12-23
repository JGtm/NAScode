#!/usr/bin/env bats
###########################################################
# TESTS RÉGRESSION - PIPESTATUS
# Vérifie que PIPESTATUS est capturé immédiatement après
# les pipelines ffmpeg, avant toute autre commande.
#
# Bug corrigé: PIPESTATUS était lu après rm/release_progress_slot
# ce qui l'écrasait et faisait échouer _execute_conversion même
# quand ffmpeg réussissait.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "regression: PIPESTATUS capturé immédiatement après pipeline pass2 ffmpeg" {
    # Vérifie que dans _execute_conversion, PIPESTATUS est capturé
    # sur la ligne qui suit immédiatement le pipeline ffmpeg | awk
    # et AVANT les commandes rm ou release_progress_slot.
    
    local transcode_file="$LIB_DIR/transcode_video.sh"
    
    # Extraire le bloc entre le pipeline pass2 (END_MSG="Terminé") et la lecture de PIPESTATUS
    # Le pattern attendu est:
    #   ... "$awk_time_func $AWK_FFMPEG_PROGRESS_SCRIPT"
    #   <capture PIPESTATUS ici, pas de commande entre>
    #   local ffmpeg_rc=${PIPESTATUS[0]...
    
    # Chercher la ligne après "Terminé" qui contient PIPESTATUS
    # Il ne doit PAS y avoir de commande (rm, if, release_progress_slot) entre les deux
    
    # Approche: extraire les lignes entre le pattern "Terminé" et "PIPESTATUS"
    local between_lines
    between_lines=$(awk '
        /END_MSG="Terminé/ { found=1; next }
        found && /PIPESTATUS/ { exit }
        found { print }
    ' "$transcode_file")
    
    # Les seules lignes autorisées entre le pipeline et PIPESTATUS sont:
    # - lignes vides
    # - commentaires
    # Pas de commandes exécutables (rm, if, local sans PIPESTATUS, etc.)
    
    local has_executable=false
    while IFS= read -r line; do
        # Ignorer lignes vides et commentaires
        local trimmed="${line##*([[:space:]])}"
        if [[ -z "$trimmed" ]] || [[ "$trimmed" == \#* ]]; then
            continue
        fi
        # Si on trouve une commande exécutable (pas local ffmpeg_rc=..PIPESTATUS..)
        if [[ "$trimmed" =~ ^(rm|if|release_|for|while|local[[:space:]]+[^P]) ]]; then
            has_executable=true
            echo "Commande trouvée entre pipeline et PIPESTATUS: $trimmed" >&2
            break
        fi
    done <<< "$between_lines"
    
    [ "$has_executable" = false ]
}

@test "regression: PIPESTATUS capturé avant rm dans _execute_conversion" {
    # Test complémentaire: vérifier que la ligne "local ffmpeg_rc=\${PIPESTATUS"
    # apparaît dans _run_ffmpeg_encode et que rm -f est après dans _execute_conversion
    
    local transcode_file="$LIB_DIR/transcode_video.sh"
    
    # Vérifier que PIPESTATUS est capturé dans _run_ffmpeg_encode
    # La fonction unifiée capture PIPESTATUS juste après le pipeline ffmpeg
    local pipestatus_in_encode
    pipestatus_in_encode=$(grep -n "ffmpeg_rc=.*PIPESTATUS" "$transcode_file" | head -1 | cut -d: -f1)
    
    # Vérifier que rm -f x265_2pass est dans _execute_conversion (après l'appel)
    local rm_line
    rm_line=$(grep -n 'rm -f "x265_2pass.log"' "$transcode_file" | head -1 | cut -d: -f1)
    
    # Les deux patterns doivent exister
    [ -n "$pipestatus_in_encode" ]
    [ -n "$rm_line" ]
    
    # Le PIPESTATUS est dans _run_ffmpeg_encode qui est appelé avant rm dans _execute_conversion
    # Donc PIPESTATUS est toujours capturé avant que rm soit exécuté
    [ "$pipestatus_in_encode" -lt "$rm_line" ]
}

@test "regression: pattern PIPESTATUS immédiat présent dans transcode_video.sh" {
    # Vérifie que le commentaire de documentation est présent
    # pour rappeler pourquoi PIPESTATUS doit être capturé immédiatement
    
    local transcode_file="$LIB_DIR/transcode_video.sh"
    
    grep -q "CRITIQUE.*PIPESTATUS.*immédiatement" "$transcode_file" || \
    grep -q "capturer PIPESTATUS immédiatement" "$transcode_file"
}
