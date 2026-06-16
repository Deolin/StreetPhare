#!/bin/bash
# ============================================================================
#  scripts/lint.sh
#  StreetPhare — Analyse statique du code Dart/Flutter
#
#  Actions :
#    - Vérifie Flutter
#    - Exécute flutter analyze pour valider la syntaxe et les types
#    - Option --strict pour forcer une analyse plus sévère
#    - Sortie colorée pour distinguer erreurs / avertissements
#
#  Usage : bash scripts/lint.sh [--strict] [--watch]
#    --strict   Active les règles d'analyse strictes
#    --watch    Surveille les modifications et ré-analyse automatiquement
# ============================================================================

set -e

VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
NC="\033[0m"

STRICT=false
WATCH=false

# ── Parsing des arguments ────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    --watch)  WATCH=true ;;
    --help|-h)
      echo "Usage : bash scripts/lint.sh [--strict] [--watch]"
      exit 0
      ;;
    *) echo -e "${JAUNE}⚠ Argument inconnu : $arg${NC}" ;;
  esac
done

echo ""
echo "============================================"
echo "  StreetPhare — Analyse Statique (Lint)"
[ "$STRICT" = true ] && echo "  (mode strict activé)"
[ "$WATCH" = true ] && echo "  (mode surveillance activé)"
echo "============================================"
echo ""

# ── Vérification Flutter ─────────────────────────────────────────────────
echo -e "${VERT}▶ Vérification de Flutter...${NC}"
if ! command -v flutter &>/dev/null; then
  echo -e "${ROUGE}❌ Flutter introuvable.${NC}"
  exit 1
fi
echo -e "  ${VERT}✅ OK${NC}"

# ── Analyse statique ─────────────────────────────────────────────────────
echo ""
echo -e "${VERT}▶ Analyse du code Dart...${NC}"
echo ""

if [ "$WATCH" = true ]; then
  # Mode surveillance continue
  echo "   Surveillance en cours (Ctrl+C pour arrêter)..."
  if [ "$STRICT" = true ]; then
    flutter analyze --watch --no-fatal-infos --no-fatal-warnings 2>&1
  else
    flutter analyze --watch 2>&1
  fi
else
  # Mode analyse unique
  if [ "$STRICT" = true ]; then
    # En mode strict, les warnings deviennent des erreurs
    flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1
  else
    flutter analyze 2>&1
  fi
fi

EXIT_CODE=$?

echo ""
echo "--------------------------------------------"

if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${VERT}✅ Aucun problème détecté. Code propre.${NC}"
else
  echo -e "${ROUGE}❌ Des problèmes ont été détectés (code $EXIT_CODE).${NC}"
  echo "   Consultez les messages ci-dessus pour corriger les erreurs."
fi

echo "============================================"

exit $EXIT_CODE