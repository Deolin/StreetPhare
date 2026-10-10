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

set -euo pipefail

VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
NC="\033[0m"

STRICT=false
WATCH=false
VERBOSE=false

# ── Parsing des arguments ────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --strict)  STRICT=true ;;
    --watch)   WATCH=true ;;
    --verbose) VERBOSE=true ;;
    --help|-h)
      echo "Usage : bash scripts/lint.sh [--strict] [--watch] [--verbose]"
      echo "  --strict   Traite aussi les infos comme des erreurs (tout est fatal)"
      echo "  --watch    Surveille les modifications et ré-analyse automatiquement"
      echo "  --verbose  Active la sortie verbeuse de flutter analyze"
      exit 0
      ;;
    *) echo -e "${JAUNE}⚠ Argument inconnu : $arg${NC}" ;;
  esac
done

echo ""
echo "============================================"
echo "  StreetPhare — Analyse Statique (Lint)"
[ "$STRICT" = true ] && echo "  (mode strict activé : les infos sont fatales)"
[ "$WATCH" = true ] && echo "  (mode surveillance activé)"
[ "$VERBOSE" = true ] && echo "  (mode verbeux activé)"
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

# Met en évidence les lignes "error" (rouge) et "warning" (jaune).
highlight_issues() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *error*)   echo -e "${ROUGE}${line}${NC}" ;;
      *warning*) echo -e "${JAUNE}${line}${NC}" ;;
      *)         echo "$line" ;;
    esac
  done
}

ANALYZE_ARGS=()
[ "$VERBOSE" = true ] && ANALYZE_ARGS+=(--verbose)
# En mode strict, les infos deviennent aussi fatales (analyse plus sévère).
# NB : on n'utilise PAS --no-fatal-* qui masquerait les erreurs réelles.
[ "$STRICT" = true ] && ANALYZE_ARGS+=(--fatal-infos)

if [ "$WATCH" = true ]; then
  echo "   Surveillance en cours (Ctrl+C pour arrêter)..."
  flutter analyze --watch "${ANALYZE_ARGS[@]}" 2>&1 | highlight_issues
else
  flutter analyze "${ANALYZE_ARGS[@]}" 2>&1 | highlight_issues
fi

EXIT_CODE=${PIPESTATUS[0]}

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