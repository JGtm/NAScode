#!/usr/bin/env bats
###########################################################
# TESTS RÉGRESSION - Repli en décodage logiciel
# Gladiator II (2026-11-18) : en pass 1, le décodage CUDA a lâché vers 1 h 55
# ("Failed to transfer data to output frame: -12", VRAM prise par un jeu).
# La passe est refaite une fois sans -hwaccel au lieu de perdre le film ;
# le log de session garde le détail de l'erreur de pass 1.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules
    source "$LIB_DIR/transcode_video.sh"
    export LOG_SESSION="$TEST_TEMP_DIR/session.log"
    : > "$LOG_SESSION"
    export NO_PROGRESS=true EFFECTIVE_DURATION=10 HWACCEL=cuda
    export FFMPEG_CALLS="$TEST_TEMP_DIR/calls"
    : > "$FFMPEG_CALLS"
    _compute_total_frames() { echo 0; }
}

teardown() {
    teardown_test_env
}

# ffmpeg factice : avec -hwaccel il écrit sur stderr le message réel puis échoue
_stub_ffmpeg_gpu_failure() {
    ffmpeg() {
        printf '%s\n' "$*" >> "$FFMPEG_CALLS"
        if [[ " $* " == *" -hwaccel "* ]]; then
            echo "[h264 @ 000001849a929700] Failed to transfer data to output frame: -12." >&2
            echo "Error processing packet in decoder: Cannot allocate memory" >&2
            return 1
        fi
        echo "progress=end"
        return 0
    }
}

_encode() {
    _run_ffmpeg_encode "$1" "$TEST_TEMP_DIR/in.mkv" "${2:-}" "$TEST_TEMP_DIR/ff.log" "Film" \
        "" "" "" 0 false "" 2>/dev/null
}

@test "détection: panne du décodage matériel reconnue, erreur ordinaire non" {
    printf '%s\n' "x265 [info]: Main profile" \
        "[h264 @ 0x1] Failed to transfer data to output frame: -12." > "$TEST_TEMP_DIR/gpu.log"
    printf '%s\n' "[hevc @ 0x1] Invalid data found when processing input" > "$TEST_TEMP_DIR/other.log"
    _ffmpeg_log_has_hwaccel_failure "$TEST_TEMP_DIR/gpu.log"
    ! _ffmpeg_log_has_hwaccel_failure "$TEST_TEMP_DIR/other.log"
    ! _ffmpeg_log_has_hwaccel_failure "$TEST_TEMP_DIR/absent.log"
}

@test "repli: la passe est refaite une fois sans -hwaccel et réussit" {
    _stub_ffmpeg_gpu_failure
    run _encode pass1
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$FFMPEG_CALLS")" -eq 2 ]
    [[ "$(sed -n 1p "$FFMPEG_CALLS")" == *"-hwaccel cuda"* ]]
    [[ "$(sed -n 2p "$FFMPEG_CALLS")" != *"-hwaccel"* ]]
    grep -q "WARNING: HWACCEL_FALLBACK | Film | mode:pass1" "$LOG_SESSION"
}

@test "repli: pas de nouvel essai pour une erreur sans rapport avec le GPU" {
    ffmpeg() {
        printf '%s\n' "$*" >> "$FFMPEG_CALLS"
        echo "Invalid data found when processing input" >&2
        return 1
    }
    run _encode pass1
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$FFMPEG_CALLS")" -eq 1 ]
}

@test "repli: un seul nouvel essai, même si le décodage logiciel échoue aussi" {
    ffmpeg() {
        printf '%s\n' "$*" >> "$FFMPEG_CALLS"
        echo "Failed to transfer data to output frame: -12." >&2
        return 1
    }
    run _encode pass1
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$FFMPEG_CALLS")" -eq 2 ]
}

@test "log de session: l'erreur d'une pass 1 est recopiée (log .pass1)" {
    source "$LIB_DIR/finalize.sh"
    local log="$TEST_TEMP_DIR/err.log"
    echo "Cannot allocate memory" > "${log}.pass1"
    _finalize_conversion_error "Film.mkv" "/z/Film.mkv" "" "" "$log" 2>/dev/null || true
    grep -q "Cannot allocate memory" "$LOG_SESSION"
    ! grep -q "exists=NO" "$LOG_SESSION"
}
