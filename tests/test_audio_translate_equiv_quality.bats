#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - Traduction "qualité équivalente" audio
# Option 1 : ne jamais dépasser le bitrate source.
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    load_base_modules_fast
}

teardown() {
    teardown_test_env
}

@test "AUDIO_TRANSLATE: translate_audio_bitrate_kbps_between_codecs retourne vide si src_kbps invalide" {
    run translate_audio_bitrate_kbps_between_codecs "aac" "opus" "N/A"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AUDIO_TRANSLATE: translate_audio_bitrate_kbps_between_codecs réduit AAC→Opus (valide)" {
    out=$(translate_audio_bitrate_kbps_between_codecs "aac" "opus" "200")
    [[ "$out" =~ ^[0-9]+$ ]]
    [ "$out" -gt 0 ]
    [ "$out" -lt 200 ]
}

@test "AUDIO_TRANSLATE: _get_smart_audio_decision applique la traduction (AAC 96k → Opus)" {
    AUDIO_TRANSLATE_EQUIV_QUALITY=true
    AUDIO_CODEC="opus"
    AUDIO_BITRATE_KBPS=0
    FORCE_AUDIO_CODEC=false

    decision=$(_get_smart_audio_decision "/fake.mkv" "aac" "96" "2")
    IFS='|' read -r action codec bitrate reason <<< "$decision"

    [ "$action" = "convert" ]
    [ "$codec" = "opus" ]
    [[ "$bitrate" =~ ^[0-9]+$ ]]

    # Invariant option 1 : jamais au-dessus du bitrate source.
    [ "$bitrate" -le 96 ]

    # Doit être plus bas que la cible par défaut opus (128k), sinon la traduction est inutile.
    [ "$bitrate" -lt "${AUDIO_BITRATE_OPUS_DEFAULT}" ]

    # Plancher stéréo (v1) : éviter des valeurs absurdes quand la source est raisonnable.
    [ "$bitrate" -ge 64 ]

    [ -n "$reason" ]
}

@test "AUDIO_TRANSLATE: pas de traduction quand bitrate source inconnu (fallback logique actuelle)" {
    AUDIO_TRANSLATE_EQUIV_QUALITY=true
    AUDIO_CODEC="opus"
    AUDIO_BITRATE_KBPS=0
    FORCE_AUDIO_CODEC=false

    decision=$(_get_smart_audio_decision "/fake.mkv" "aac" "0" "2")
    IFS='|' read -r action codec bitrate reason <<< "$decision"

    [ "$action" = "convert" ]
    [ "$codec" = "opus" ]
    [ "$bitrate" -eq "${AUDIO_BITRATE_OPUS_DEFAULT}" ]
    [ -n "$reason" ]
}

@test "AUDIO_TRANSLATE: ne s'applique jamais quand AUDIO_CODEC=copy" {
    AUDIO_TRANSLATE_EQUIV_QUALITY=true
    AUDIO_CODEC="copy"

    decision=$(_get_smart_audio_decision "/fake.mkv" "aac" "96" "2")
    IFS='|' read -r action codec bitrate reason <<< "$decision"

    [ "$action" = "copy" ]
    [ "$codec" = "copy" ]
    [ "$bitrate" -eq 0 ]
    [ "$reason" = "mode_copy" ]
}

@test "AUDIO_TRANSLATE: force_convert vers codec moins efficace est capé au bitrate source" {
    AUDIO_TRANSLATE_EQUIV_QUALITY=true
    AUDIO_CODEC="aac"
    AUDIO_BITRATE_KBPS=0
    FORCE_AUDIO_CODEC=true

    decision=$(_get_smart_audio_decision "/fake.mkv" "opus" "96" "2")
    IFS='|' read -r action codec bitrate reason <<< "$decision"

    [ "$action" = "convert" ]
    [ "$codec" = "aac" ]
    [ "$bitrate" -eq 96 ]
    [ "$reason" = "force_convert" ]
}

###########################################################
# Tests des helpers _clamp_min, _clamp_max, _min3
###########################################################

@test "_clamp_min: valeur inférieure au minimum → retourne minimum" {
    result=$(_clamp_min 50 64)
    [ "$result" -eq 64 ]
}

@test "_clamp_min: valeur supérieure au minimum → retourne valeur" {
    result=$(_clamp_min 100 64)
    [ "$result" -eq 100 ]
}

@test "_clamp_min: valeur égale au minimum → retourne valeur" {
    result=$(_clamp_min 64 64)
    [ "$result" -eq 64 ]
}

@test "_clamp_max: valeur supérieure au maximum → retourne maximum" {
    result=$(_clamp_max 500 384)
    [ "$result" -eq 384 ]
}

@test "_clamp_max: valeur inférieure au maximum → retourne valeur" {
    result=$(_clamp_max 200 384)
    [ "$result" -eq 200 ]
}

@test "_clamp_max: valeur égale au maximum → retourne valeur" {
    result=$(_clamp_max 384 384)
    [ "$result" -eq 384 ]
}

@test "_min3: retourne le minimum des trois valeurs (premier)" {
    result=$(_min3 50 100 75)
    [ "$result" -eq 50 ]
}

@test "_min3: retourne le minimum des trois valeurs (deuxième)" {
    result=$(_min3 100 50 75)
    [ "$result" -eq 50 ]
}

@test "_min3: retourne le minimum des trois valeurs (troisième)" {
    result=$(_min3 75 100 50)
    [ "$result" -eq 50 ]
}

@test "_min3: gère les valeurs égales" {
    result=$(_min3 100 100 100)
    [ "$result" -eq 100 ]
}
