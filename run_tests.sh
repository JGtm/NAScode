#!/bin/bash
###########################################################
# Script pour exécuter les tests unitaires avec Bats
# Affichage condensé par défaut, verbeux avec -v
###########################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
LOGS_DIR="$SCRIPT_DIR/logs/tests"

# Créer le dossier de logs s'il n'existe pas
mkdir -p "$LOGS_DIR"

# Timestamp pour le fichier de log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/tests_${TIMESTAMP}.log"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Cible pour l'affichage temps réel : /dev/tty si réellement ouvrable en
# écriture, sinon /dev/null. On teste par une ouverture effective plutôt que
# par les flags [[ -w ]] : sous Git Bash/MSYS et en contexte non interactif
# (cron, CI sans -v), /dev/tty peut passer -e/-w tout en échouant à l'open
# ("No such device or address"), ce qui crasherait le script sous `set -e`.
TTY_OUT="/dev/tty"
if ! { : >"$TTY_OUT"; } 2>/dev/null; then
    TTY_OUT="/dev/null"
fi

# Options
VERBOSE=false
FILTER=""
SHOW_ONLY_ERRORS=false
FAST_MODE=false
# Nombre de fichiers .bats exécutés en parallèle ("auto" = nombre de cœurs, 1 = séquentiel)
JOBS="auto"

###########################################################
# Fonctions utilitaires
###########################################################

log_to_file() {
    echo -e "$*" >> "$LOG_FILE"
}

print_and_log() {
    echo -e "$*"
    # Supprimer les codes couleur pour le fichier log
    echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

# Traduction des messages d'erreur courants en français
translate_error() {
    local error="$1"
    
    # Remplacements courants
    error="${error//expected/attendu :}"
    error="${error//actual/obtenu :}"
    error="${error//to equal/devrait être égal à}"
    error="${error//to contain/devrait contenir}"
    error="${error//not ok/ÉCHEC}"
    error="${error//\`\$status\' to be/le code retour devrait être}"
    error="${error//\`\$output\' to contain/la sortie devrait contenir}"
    error="${error//but got/mais obtenu}"
    error="${error//assertion failed/assertion échouée}"
    error="${error//file does not exist/$'le fichier n\x27existe pas'}"
    error="${error//command not found/commande introuvable}"
    error="${error//No such file or directory/Fichier ou dossier introuvable}"
    error="${error//Permission denied/Permission refusée}"
    error="${error//is not defined/$'n\x27est pas défini(e)'}"
    error="${error//unbound variable/variable non définie}"
    
    echo "$error"
}

# Compte le nombre de tests dans un fichier .bats
count_tests_in_file() {
    local file="$1"
    grep -c '^@test ' "$file" 2>/dev/null || true
}

###########################################################
# Vérification de Bats
###########################################################

if ! command -v bats &> /dev/null; then
    # Sur Git Bash / MSYS2, bats peut être installé dans un préfixe utilisateur
    if [[ -x "${HOME:-}/.local/bin/bats" ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
    fi
fi

if ! command -v bats &> /dev/null; then
    echo -e "${YELLOW}⚠️  Bats n'est pas installé.${NC}"
    echo ""
    echo "Installation :"
    echo "  • macOS:   brew install bats-core"
    echo "  • Ubuntu:  sudo apt install bats"
    echo "  • Windows: npm install -g bats"
    echo "  • Manual:  git clone https://github.com/bats-core/bats-core.git"
    echo "             cd bats-core && ./install.sh /usr/local"
    echo ""
    exit 1
fi

###########################################################
# Parsing des arguments
###########################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -e|--errors-only)
            SHOW_ONLY_ERRORS=true
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        --fast)
            FAST_MODE=true
            shift
            ;;
        -j|--jobs)
            JOBS="${2:-}"
            if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ || "$JOBS" == "auto" ]]; then
                echo -e "${RED}Valeur invalide pour $1 : '${JOBS}' (entier >= 1 ou auto)${NC}"
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose      Mode verbeux (affiche chaque test)"
            echo "  -e, --errors-only  Affiche uniquement les fichiers avec erreurs"
            echo "  -f, --filter PAT   Exécuter seulement les tests matchant PAT"
            echo "  --fast             Mode rapide (exclut les tests E2E lents)"
            echo "  -j, --jobs N       Fichiers exécutés en parallèle (défaut : auto = nb de cœurs ; 1 = séquentiel)"
            echo "  -h, --help         Afficher cette aide"
            echo ""
            echo "Les résultats sont enregistrés dans: logs/tests/"
            exit 0
            ;;
        *)
            echo -e "${RED}Option inconnue: $1${NC}"
            exit 1
            ;;
    esac
done

###########################################################
# En-tête
###########################################################

print_and_log "${CYAN}═══════════════════════════════════════════════════════${NC}"
print_and_log "${CYAN}             Tests Unitaires - NAScode                 ${NC}"
print_and_log "${CYAN}═══════════════════════════════════════════════════════${NC}"
print_and_log ""
if [[ "$FAST_MODE" == true ]]; then
    print_and_log "${YELLOW}⚡ Mode rapide (--fast) : tests E2E lents exclus${NC}"
    print_and_log ""
fi
print_and_log "${DIM}Bats: $(bats --version) | Log: logs/tests/tests_${TIMESTAMP}.log${NC}"
print_and_log ""

###########################################################
# Exécution des tests
###########################################################

# Capturer le temps de départ
START_TIME=$(date +%s)

cd "$TESTS_DIR"

# Collecter les fichiers de test
TEST_FILES=()
# Tests E2E lents (exclus en mode --fast)
SLOW_TESTS=("test_e2e_full_workflow.bats" "test_e2e_stream_mapping.bats" "test_e2e_audio_smart_logic.bats" "test_vmaf_full.bats" "test_regression_e2e.bats")

shopt -s nullglob
for test_file in *.bats; do
    # Mode fast : exclure les tests E2E lents
    if [[ "$FAST_MODE" == true ]]; then
        is_slow=false
        for slow in "${SLOW_TESTS[@]}"; do
            if [[ "$test_file" == "$slow" ]]; then
                is_slow=true
                break
            fi
        done
        if [[ "$is_slow" == true ]]; then
            continue
        fi
    fi

    if [[ -z "$FILTER" ]]; then
        TEST_FILES+=("$test_file")
        continue
    fi

    # Filtrage simple (insensible à la casse) sur le nom de fichier
    if [[ "${test_file,,}" == *"${FILTER,,}"* ]]; then
        TEST_FILES+=("$test_file")
    fi
done
shopt -u nullglob

if [[ -n "$FILTER" && ${#TEST_FILES[@]} -eq 0 ]]; then
    print_and_log "${YELLOW}Aucun fichier de test correspondant à '$FILTER'${NC}"
    exit 1
fi

TOTAL_FILES=${#TEST_FILES[@]}
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
TOTAL_TESTS=0
TOTAL_HARNESS_ERRORS=0
FAILED_FILES=()
FILE_NUM=0

# Fichier temporaire pour récupérer le code de sortie de bats à travers la
# process substitution (sinon $? reflète la boucle while, pas bats).
BATS_RC_TMP=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/nascode_bats_rc.$$")

###########################################################
# Exécution parallèle (préparation)
###########################################################
# Les fichiers sont lancés en arrière-plan ; la boucle d'affichage ci-dessous
# relit ensuite leurs sorties TAP dans l'ordre habituel (même parsing, mêmes
# contrôles de harnais).
#   - fichiers "isolables" : en parallèle, chacun avec son propre
#     NASCODE_RUNTIME_DIR (lockfile, stop flag et TMP_DIR séparés) ;
#   - fichiers qui codent en dur /tmp/conversion_* ou /tmp/video_convert
#     (E2E, lock) : à la suite, dans un seul worker, comme avant.
PREPARED_DIR=""
PREP_PIDS=()

_cleanup_runner() {
    rm -f "$BATS_RC_TMP" 2>/dev/null || true
    if [[ ${#PREP_PIDS[@]} -gt 0 ]]; then
        kill "${PREP_PIDS[@]}" 2>/dev/null || true
        pkill -P $$ 2>/dev/null || true
    fi
    if [[ -n "$PREPARED_DIR" && -d "$PREPARED_DIR" ]]; then
        rm -rf "$PREPARED_DIR" 2>/dev/null || true
    fi
}
trap _cleanup_runner EXIT
trap 'exit 130' INT TERM

if [[ "$JOBS" == "auto" ]]; then
    JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || JOBS=4
fi

# Lance un fichier .bats et écrit <fichier>.tap puis <fichier>.rc (écrit en dernier :
# sa présence signale que le fichier est terminé).
# Usage: _prepare_one <fichier.bats> <isolé:0|1>
_prepare_one() {
    local f="$1" isolated="$2" rt="" rc=0
    if [[ "$isolated" == 1 ]]; then
        rt=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/nascode_rt_$$_$RANDOM")
        # TMP_DIR par défaut = $NASCODE_RUNTIME_DIR/video_convert (lib/config.sh) :
        # certains tests supposent qu'il existe, comme /tmp/video_convert en séquentiel.
        mkdir -p "$rt/video_convert"
        NASCODE_RUNTIME_DIR="$rt" bats --tap "$f" > "$PREPARED_DIR/$f.tap" 2>&1 || rc=$?
        rm -rf "$rt" 2>/dev/null || true
    else
        bats --tap "$f" > "$PREPARED_DIR/$f.tap" 2>&1 || rc=$?
    fi
    echo "$rc" > "$PREPARED_DIR/$f.rc.tmp"
    mv "$PREPARED_DIR/$f.rc.tmp" "$PREPARED_DIR/$f.rc"
}

if [[ "$JOBS" -gt 1 && "$TOTAL_FILES" -gt 1 ]]; then
    PREPARED_DIR=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/nascode_tests_$$")
    mkdir -p "$PREPARED_DIR"

    PARALLEL_FILES=()
    SERIAL_FILES=()
    for test_file in "${TEST_FILES[@]}"; do
        if grep -qE '/tmp/(conversion_|video_convert)' "$test_file"; then
            SERIAL_FILES+=("$test_file")
        else
            PARALLEL_FILES+=("$test_file")
        fi
    done

    print_and_log "${DIM}⚡ Parallèle : ${JOBS} jobs (${#PARALLEL_FILES[@]} fichiers isolés, ${#SERIAL_FILES[@]} à la suite) — -j 1 pour séquentiel${NC}"
    print_and_log ""

    # Worker séquentiel (fichiers partageant /tmp) : démarré en premier, c'est le plus long.
    if [[ ${#SERIAL_FILES[@]} -gt 0 ]]; then
        ( for f in "${SERIAL_FILES[@]}"; do _prepare_one "$f" 0; done ) &
        PREP_PIDS+=($!)
    fi

    # Pool parallèle pour les fichiers isolés (un slot est laissé au worker séquentiel).
    pool_size=$JOBS
    [[ ${#SERIAL_FILES[@]} -gt 0 && "$pool_size" -gt 1 ]] && pool_size=$((pool_size - 1))
    if [[ ${#PARALLEL_FILES[@]} -gt 0 ]]; then
        (
            running=0
            for f in "${PARALLEL_FILES[@]}"; do
                if [[ "$running" -ge "$pool_size" ]]; then
                    wait -n 2>/dev/null || true
                    running=$((running - 1))
                fi
                _prepare_one "$f" 1 &
                running=$((running + 1))
            done
            wait
        ) &
        PREP_PIDS+=($!)
    fi
fi

for test_file in "${TEST_FILES[@]}"; do
    ((FILE_NUM++)) || true
    
    # Compter les tests dans ce fichier
    test_count=$(count_tests_in_file "$test_file")
    TOTAL_TESTS=$((TOTAL_TESTS + test_count))
    
    # Afficher le fichier en cours AVANT exécution
    if [[ "$VERBOSE" == true ]]; then
        print_and_log ""
        print_and_log "${BOLD}[$FILE_NUM/$TOTAL_FILES] $test_file${NC} ($test_count tests)"
        print_and_log "${DIM}────────────────────────────────────────${NC}"
    else
        if [[ "$SHOW_ONLY_ERRORS" != true ]]; then
            # Mode condensé : afficher le fichier en cours (colonnes alignées)
            printf "${YELLOW}⏳${NC} [%2d/%-2d] %-55s (%2d/%-2d)" "$FILE_NUM" "$TOTAL_FILES" "$test_file" 0 "$test_count" >"$TTY_OUT"
        fi
    fi
    
    # Variables pour le parsing en streaming
    local_passed=0
    local_failed=0
    local_skipped=0
    tap_output=""
    declare -a local_errors=()
    current_error=""
    in_error=false
    
    # Exécuter bats et lire la sortie en temps réel
    set +e
    while IFS= read -r line; do
        tap_output+="$line"$'\n'
        
        if [[ "$line" =~ ^ok\ [0-9]+\ .*\#\ skip ]]; then
            # Test ignoré (skip)
            ((local_skipped++)) || true
            in_error=false
            if [[ -n "$current_error" ]]; then
                local_errors+=("$current_error")
                current_error=""
            fi
        elif [[ "$line" =~ ^ok\ [0-9]+\ (.*)$ ]]; then
            # Test réussi
            ((local_passed++)) || true
            in_error=false
            if [[ -n "$current_error" ]]; then
                local_errors+=("$current_error")
                current_error=""
            fi
            
            if [[ "$VERBOSE" == true ]]; then
                test_name="${BASH_REMATCH[1]}"
                echo -e "  ${GREEN}✓${NC} $test_name"
                echo "  ✓ $test_name" >> "$LOG_FILE"
            else
                if [[ "$SHOW_ONLY_ERRORS" != true ]]; then
                    # Mettre à jour le compteur en temps réel
                    done_count=$((local_passed + local_failed + local_skipped))
                    printf "\r${YELLOW}⏳${NC} [%2d/%-2d] %-55s (%2d/%-2d)" "$FILE_NUM" "$TOTAL_FILES" "$test_file" "$done_count" "$test_count" >"$TTY_OUT"
                fi
            fi
            
        elif [[ "$line" =~ ^not\ ok\ [0-9]+\ (.*)$ ]]; then
            # Test échoué
            if [[ -n "$current_error" ]]; then
                local_errors+=("$current_error")
            fi
            ((local_failed++)) || true
            in_error=true
            current_error="Test: ${BASH_REMATCH[1]}"
            
            if [[ "$VERBOSE" == true ]]; then
                echo -e "  ${RED}✗${NC} ${BASH_REMATCH[1]}"
                echo "  ✗ ${BASH_REMATCH[1]}" >> "$LOG_FILE"
            else
                if [[ "$SHOW_ONLY_ERRORS" != true ]]; then
                    # Mettre à jour le compteur
                    done_count=$((local_passed + local_failed + local_skipped))
                    printf "\r${YELLOW}⏳${NC} [%2d/%-2d] %-55s (%2d/%-2d)" "$FILE_NUM" "$TOTAL_FILES" "$test_file" "$done_count" "$test_count" >"$TTY_OUT"
                fi
            fi
            
        elif [[ "$in_error" == true && "$line" =~ ^#\ (.*)$ ]]; then
            # Détail d'erreur
            error_detail="${BASH_REMATCH[1]}"
            current_error+=$'\n'"  $error_detail"
            if [[ "$VERBOSE" == true ]]; then
                translated=$(translate_error "$error_detail")
                echo -e "    ${DIM}$translated${NC}"
                echo "    $translated" >> "$LOG_FILE"
            fi
        fi
    done < <(
        if [[ -n "$PREPARED_DIR" ]]; then
            # Mode parallèle : attendre la fin du fichier, puis relire sa sortie TAP
            while [[ ! -f "$PREPARED_DIR/$test_file.rc" ]]; do sleep 0.2; done
            cat "$PREPARED_DIR/$test_file.tap"
            cat "$PREPARED_DIR/$test_file.rc" > "$BATS_RC_TMP"
        else
            bats --tap "$test_file" 2>&1; echo "$?" > "$BATS_RC_TMP"
        fi
    )
    set -e

    # Récupérer le code de sortie de bats (écrit dans le sous-shell ci-dessus).
    bats_rc=$(cat "$BATS_RC_TMP" 2>/dev/null || echo 0)
    [[ "$bats_rc" =~ ^[0-9]+$ ]] || bats_rc=0

    # Ajouter la dernière erreur si elle existe
    if [[ -n "$current_error" ]]; then
        local_errors+=("$current_error")
    fi

    # --- Réconciliation : détecter les fichiers qui n'ont pas tourné correctement ---
    # Un .bats qui crashe au chargement (helper manquant, erreur de syntaxe)
    # n'émet aucune ligne `not ok` → local_failed=0 alors que bats_rc != 0.
    # De même, un nombre de tests exécutés différent du nombre attendu signale
    # une interruption ou une découverte partielle.
    executed=$((local_passed + local_failed + local_skipped))
    harness_error=""
    if [[ "$bats_rc" -ne 0 && "$local_failed" -eq 0 ]]; then
        harness_error="bats a retourné le code $bats_rc sans émettre d'échec TAP (crash de chargement ?)"
    elif [[ "$test_count" -gt 0 && "$executed" -ne "$test_count" ]]; then
        harness_error="$executed test(s) exécuté(s) sur $test_count attendu(s) (fichier interrompu ?)"
    fi
    if [[ -n "$harness_error" ]]; then
        TOTAL_HARNESS_ERRORS=$((TOTAL_HARNESS_ERRORS + 1))
        print_and_log "${RED}✗  [HARNESS] $test_file : $harness_error${NC}"
    fi
    # Bookkeeping centralisé : un fichier est en échec s'il a des `not ok` OU
    # un problème de harnais (peu importe le mode verbeux/condensé).
    if [[ "$local_failed" -gt 0 || -n "$harness_error" ]]; then
        FAILED_FILES+=("$test_file")
    fi

    # Mettre à jour les totaux
    TOTAL_PASSED=$((TOTAL_PASSED + local_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + local_failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + local_skipped))

    # Copier les erreurs dans _ERRORS pour l'affichage
    _ERRORS=("${local_errors[@]+"${local_errors[@]}"}")
    _FAILED=$local_failed
    
    # Affichage condensé : afficher le résultat final
    if [[ "$VERBOSE" != true ]]; then
        # Indicateur de skip : ⚠ si des tests ont été ignorés
        skip_indicator=""
        skip_indicator_plain=""
        if [[ $local_skipped -gt 0 ]]; then
            skip_indicator=" ${YELLOW}⚠${NC}"
            skip_indicator_plain=" ⚠"
        fi
        
        if [[ $local_failed -eq 0 && -z "$harness_error" ]]; then
            if [[ "$SHOW_ONLY_ERRORS" != true ]]; then
                printf "\r${GREEN}✓${NC}  [%2d/%-2d] %-55s ${DIM}(%2d/%-2d)${NC}%b\n" "$FILE_NUM" "$TOTAL_FILES" "$test_file" "$local_passed" "$test_count" "$skip_indicator" >"$TTY_OUT"
                printf "✓  [%2d/%-2d] %-55s (%2d/%-2d)%s\n" "$FILE_NUM" "$TOTAL_FILES" "$test_file" "$local_passed" "$test_count" "$skip_indicator_plain" >> "$LOG_FILE"
            fi
        elif [[ $local_failed -gt 0 ]]; then
            printf "\r${RED}✗${NC}  [%2d/%-2d] %-55s ${RED}%2d échec(s)${NC} ${DIM}/ %-2d${NC}%b\n" "$FILE_NUM" "$TOTAL_FILES" "$test_file" "$local_failed" "$test_count" "$skip_indicator" >"$TTY_OUT"
            printf "✗  [%2d/%-2d] %-55s %2d échec(s) / %-2d%s\n" "$FILE_NUM" "$TOTAL_FILES" "$test_file" "$local_failed" "$test_count" "$skip_indicator_plain" >> "$LOG_FILE"

            # Afficher les erreurs traduites
            if [[ ${#_ERRORS[@]} -gt 0 ]]; then
                for error in "${_ERRORS[@]}"; do
                    translated=$(translate_error "$error")
                    echo -e "    ${DIM}└─${NC} ${RED}$translated${NC}" | head -3
                    echo "    └─ $translated" >> "$LOG_FILE"
                done
            fi
        fi
    fi
    
    # Log complet de la sortie TAP
    log_to_file ""
    log_to_file "=== $test_file ==="
    log_to_file "$tap_output"
done

###########################################################
# Résumé final
###########################################################

print_and_log ""
print_and_log "${CYAN}═══════════════════════════════════════════════════════${NC}"

# Calculer le pourcentage de réussite
if [[ $TOTAL_TESTS -gt 0 ]]; then
    SUCCESS_RATE=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
else
    SUCCESS_RATE=0
fi

# Afficher le résumé avec couleur selon le résultat.
# Un run est en échec s'il y a des tests `not ok` OU des erreurs de harnais
# (fichier qui n'a pas tourné / a crashé au chargement).
if [[ $TOTAL_FAILED -eq 0 && $TOTAL_HARNESS_ERRORS -eq 0 ]]; then
    print_and_log "${GREEN}✓ SUCCÈS${NC} — Tous les tests sont passés !"
    print_and_log ""
    print_and_log "  ${GREEN}$TOTAL_PASSED${NC} réussi(s)  ${DIM}|${NC}  $TOTAL_FILES fichiers  ${DIM}|${NC}  $SUCCESS_RATE%"
else
    print_and_log "${RED}✗ ÉCHECS DÉTECTÉS${NC}"
    print_and_log ""
    print_and_log "  ${GREEN}$TOTAL_PASSED${NC} réussi(s)  ${DIM}|${NC}  ${RED}$TOTAL_FAILED${NC} échoué(s)  ${DIM}|${NC}  ${YELLOW}$TOTAL_SKIPPED${NC} ignoré(s)"
    if [[ $TOTAL_HARNESS_ERRORS -gt 0 ]]; then
        print_and_log "  ${RED}$TOTAL_HARNESS_ERRORS${NC} fichier(s) avec erreur de harnais (tests non exécutés)"
    fi
    print_and_log ""
    print_and_log "${DIM}Fichiers en échec :${NC}"
    for f in "${FAILED_FILES[@]}"; do
        print_and_log "  ${RED}•${NC} $f"
    done
fi

if [[ $TOTAL_SKIPPED -gt 0 ]]; then
    print_and_log "${YELLOW}ℹ ${TOTAL_SKIPPED} test(s) ignoré(s) (skip)${NC}"
fi

# Calculer et afficher le temps total d'exécution
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))
print_and_log ""
print_and_log "${DIM}⏱  Temps d'exécution : ${ELAPSED_MIN}m ${ELAPSED_SEC}s${NC}"
print_and_log "${DIM}Log complet : $LOG_FILE${NC}"
print_and_log "${CYAN}═══════════════════════════════════════════════════════${NC}"

# Code de sortie
if [[ $TOTAL_FAILED -gt 0 || $TOTAL_HARNESS_ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
