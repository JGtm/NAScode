#!/usr/bin/env bats
###########################################################
# TESTS UNITAIRES - lib/i18n.sh
# Tests du système d'internationalisation
###########################################################

load 'test_helper'

setup() {
    setup_test_env
    export SCRIPT_DIR="$PROJECT_ROOT"
    # Charger i18n directement pour tester ses fonctions
    source "$LIB_DIR/i18n.sh"
}

teardown() {
    teardown_test_env
}

###########################################################
# Tests de _i18n_load()
###########################################################

@test "_i18n_load: charge la locale française par défaut" {
    LANG_UI="fr"
    _i18n_load
    
    # Vérifier qu'une variable de message est définie
    [ -n "${MSG_NOTIFY_DISABLED:-}" ]
}

@test "_i18n_load: charge la locale anglaise" {
    _i18n_load "en"
    
    # Vérifier que LANG_UI est mis à jour
    [ "$LANG_UI" = "en" ]
    # Vérifier qu'une variable de message est définie
    [ -n "${MSG_NOTIFY_DISABLED:-}" ]
}

@test "_i18n_load: fallback vers français si locale inexistante" {
    _i18n_load "zz"
    
    # Doit revenir au français
    [ "$LANG_UI" = "fr" ]
}

###########################################################
# Tests de msg()
###########################################################

@test "msg: retourne le message français" {
    _i18n_load "fr"
    
    local result
    result=$(msg MSG_NOTIFY_DISABLED)
    
    # Doit retourner "désactivé" en français
    [ "$result" = "désactivé" ]
}

@test "msg: retourne le message anglais" {
    _i18n_load "en"
    
    local result
    result=$(msg MSG_NOTIFY_DISABLED)
    
    # Doit retourner "disabled" en anglais
    [ "$result" = "disabled" ]
}

@test "msg: retourne la clé si message inexistant (fallback)" {
    local result
    result=$(msg MSG_INEXISTANT_KEY_12345)
    
    # Doit retourner la clé elle-même
    [ "$result" = "MSG_INEXISTANT_KEY_12345" ]
}

@test "msg: substitue les placeholders %s" {
    _i18n_load "fr"
    
    # MSG_ARG_REQUIRES_VALUE = "%s doit être suivi d'une valeur"
    local result
    result=$(msg MSG_ARG_REQUIRES_VALUE "--test")
    
    # Doit contenir l'argument substitué
    [[ "$result" =~ "--test" ]]
    [[ "$result" =~ "valeur" ]]
}

@test "msg: gère message sans placeholder" {
    _i18n_load "fr"
    
    # MSG_NOTIFY_DISABLED n'a pas de placeholder
    local result
    result=$(msg MSG_NOTIFY_DISABLED)
    
    [ "$result" = "désactivé" ]
}

###########################################################
# Tests de cohérence des locales
###########################################################

@test "locale: fr.sh et en.sh ont le même nombre de messages" {
    local fr_count en_count
    
    fr_count=$(grep -c "^MSG_" "$PROJECT_ROOT/locale/fr.sh" || echo 0)
    en_count=$(grep -c "^MSG_" "$PROJECT_ROOT/locale/en.sh" || echo 0)
    
    [ "$fr_count" -eq "$en_count" ]
}

@test "locale: toutes les clés MSG_ de fr.sh existent dans en.sh" {
    local missing_keys=""
    
    while IFS= read -r key; do
        if ! grep -q "^${key}=" "$PROJECT_ROOT/locale/en.sh"; then
            missing_keys+="$key "
        fi
    done < <(grep -o "^MSG_[A-Z0-9_]*" "$PROJECT_ROOT/locale/fr.sh")
    
    if [[ -n "$missing_keys" ]]; then
        echo "Clés manquantes dans en.sh: $missing_keys" >&2
        return 1
    fi
}

@test "locale: toutes les clés MSG_ de en.sh existent dans fr.sh" {
    local missing_keys=""
    
    while IFS= read -r key; do
        if ! grep -q "^${key}=" "$PROJECT_ROOT/locale/fr.sh"; then
            missing_keys+="$key "
        fi
    done < <(grep -o "^MSG_[A-Z0-9_]*" "$PROJECT_ROOT/locale/en.sh")
    
    if [[ -n "$missing_keys" ]]; then
        echo "Clés manquantes dans fr.sh: $missing_keys" >&2
        return 1
    fi
}

###########################################################
# Tests d'intégration avec ui.sh
###########################################################

@test "ui.sh: charge automatiquement i18n.sh" {
    # Désactiver msg si déjà défini
    unset -f msg 2>/dev/null || true
    unset MSG_WELCOME 2>/dev/null || true
    
    # Charger ui.sh dans un subshell propre
    run bash -c 'export SCRIPT_DIR="'"$PROJECT_ROOT"'"; source "'"$LIB_DIR"'/ui.sh"; declare -f msg >/dev/null && echo "msg_defined"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "msg_defined" ]
}

@test "ui.sh: msg() fonctionne après chargement auto" {
    run bash -c 'export SCRIPT_DIR="'"$PROJECT_ROOT"'"; source "'"$LIB_DIR"'/ui.sh"; msg MSG_NOTIFY_DISABLED'
    
    [ "$status" -eq 0 ]
    [ "$output" = "désactivé" ]
}
