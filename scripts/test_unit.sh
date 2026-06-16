#!/bin/bash
# ============================================================================
#  scripts/test_unit.sh
#  StreetPhare — Lancement des tests unitaires et de cryptographie
#
#  Actions :
#    - Vérifie Flutter
#    - Exécute flutter test avec couverture de code
#    - Filtre les tests de cryptographie (fichiers *crypto*)
#    - Génère un rapport de couverture lcov si disponible
#
#  Usage : bash scripts/test_unit.sh [--coverage] [--crypto-only]
#    --coverage     Génère un rapport de couverture (lcov.info)
#    --crypto-only  Exécute uniquement les tests de cryptographie
# ============================================================================

set -e

VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
NC="\033[0m"

COVERAGE=false
CRYPTO_ONLY=false

# ── Parsing des arguments ────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --coverage)   COVERAGE=true ;;
    --crypto-only) CRYPTO_ONLY=true ;;
    --help|-h)
      echo "Usage : bash scripts/test_unit.sh [--coverage] [--crypto-only]"
      exit 0
      ;;
    *) echo -e "${JAUNE}⚠ Argument inconnu : $arg${NC}" ;;
  esac
done

echo ""
echo "============================================"
echo "  StreetPhare — Tests Unitaires"
[ "$CRYPTO_ONLY" = true ] && echo "  (mode : cryptographie uniquement)"
echo "============================================"
echo ""

# ── Vérification Flutter ─────────────────────────────────────────────────
echo -e "${VERT}▶ Vérification de Flutter...${NC}"
if ! command -v flutter &>/dev/null; then
  echo -e "${ROUGE}❌ Flutter introuvable.${NC}"
  exit 1
fi
echo -e "  ${VERT}✅ OK${NC}"

# ── Exécution des tests ──────────────────────────────────────────────────
echo ""
echo -e "${VERT}▶ Exécution des tests unitaires...${NC}"

if [ "$CRYPTO_ONLY" = true ]; then
  # Filtre les fichiers contenant "crypto" dans leur chemin
  echo "   Recherche des fichiers de test crypto..."
  CRYPTO_TESTS=$(find test -type f -name "*crypto*" 2>/dev/null || true)
  if [ -z "$CRYPTO_TESTS" ]; then
    echo -e "${JAUNE}⚠ Aucun fichier de test crypto trouvé dans test/.${NC}"
    echo "   Exécution de tous les tests unitaires par défaut..."
    flutter test
  else
    echo "   Fichiers trouvés :"
    echo "$CRYPTO_TESTS" | while read f; do echo "    - $f"; done
    flutter test $CRYPTO_TESTS
  fi
elif [ "$COVERAGE" = true ]; then
  echo "   Génération de la couverture de code (lcov)..."
  flutter test --coverage 2>&1
  if [ -f "coverage/lcov.info" ]; then
    echo ""
    echo -e "  ${VERT}✅ Rapport de couverture généré : coverage/lcov.info${NC}"
    # Affiche un résumé rapide si lcov est installé
    if command -v lcov &>/dev/null; then
      echo ""
      lcov --summary coverage/lcov.info 2>/dev/null || true
    fi
  fi
else
  flutter test 2>&1
fi

EXIT_CODE=$?

echo ""
echo "--------------------------------------------"

if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${VERT}✅ Tous les tests unitaires ont réussi.${NC}"
else
  echo -e "${ROUGE}❌ Certains tests unitaires ont échoué (code $EXIT_CODE).${NC}"
fi

echo "============================================"

exit $EXIT_CODE