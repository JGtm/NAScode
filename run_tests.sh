#!/bin/bash
###########################################################
# Script pour exécuter les tests unitaires avec Bats
###########################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}         Tests Unitaires - Conversion Script           ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"

# Vérifier si bats est installé
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

echo -e "${GREEN}✓ Bats trouvé: $(bats --version)${NC}"
echo ""

# Options
VERBOSE=""
FILTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE="--verbose-run"
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose     Afficher les détails des tests"
            echo "  -f, --filter PAT  Exécuter seulement les tests matchant PAT"
            echo "  -h, --help        Afficher cette aide"
            exit 0
            ;;
        *)
            echo -e "${RED}Option inconnue: $1${NC}"
            exit 1
            ;;
    esac
done

# Exécuter les tests
cd "$TESTS_DIR"

if [[ -n "$FILTER" ]]; then
    echo -e "${CYAN}Exécution des tests filtrant: $FILTER${NC}"
    bats --pretty $VERBOSE --filter "$FILTER" *.bats
else
    echo -e "${CYAN}Exécution de tous les tests...${NC}"
    echo ""
    bats --pretty $VERBOSE *.bats
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    Tests terminés                      ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
