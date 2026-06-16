#!/bin/bash
# ============================================================================
#  scripts/build_runner.sh
#  StreetPhare — Génération de code via build_runner (Hive CE, ObjectBox)
#
#  Actions :
#    - Vérifie la présence de Flutter
#    - Force flutter pub get pour synchroniser les dépendances
#    - Exécute build_runner avec --delete-conflicting-outputs
#      pour régénérer proprement les adaptateurs Hive CE et autres
#      fichiers générés (.g.dart, .hive.dart, etc.)
#
#  Usage : bash scripts/build_runner.sh
# ============================================================================

set -e

# ── Couleurs ────────────────────────────────────────────────────────────
VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
NC="\033[0m"

echo ""
echo "============================================"
echo "  StreetPhare — Build Runner (Hive/ObjectBox)"
echo "============================================"
echo ""

# ── Étape 1 : Vérification de Flutter ───────────────────────────────────
echo -e "${VERT}▶ Étape 1/3 : Vérification de Flutter...${NC}"
if ! command -v flutter &>/dev/null; then
  echo -e "${ROUGE}❌ Flutter introuvable dans le PATH.${NC}"
  echo "   Assurez-vous que Flutter est installé et accessible."
  exit 1
fi
echo -e "  ${VERT}✅ Flutter détecté :$(flutter --version 2>/dev/null | head -1)${NC}"

# ── Étape 2 : Synchronisation des dépendances ───────────────────────────
echo ""
echo -e "${VERT}▶ Étape 2/3 : Synchronisation des dépendances (flutter pub get)...${NC}"
if flutter pub get; then
  echo -e "  ${VERT}✅ flutter pub get terminé.${NC}"
else
  echo -e "${ROUGE}❌ flutter pub get a échoué.${NC}"
  exit 1
fi

# ── Étape 3 : Exécution du build_runner ─────────────────────────────────
echo ""
echo -e "${VERT}▶ Étape 3/3 : Génération du code (build_runner)...${NC}"
echo "   Commande : flutter pub run build_runner build --delete-conflicting-outputs"
echo ""

if flutter pub run build_runner build --delete-conflicting-outputs; then
  echo ""
  echo -e "  ${VERT}✅ Génération de code terminée avec succès.${NC}"
else
  echo ""
  echo -e "${ROUGE}❌ La génération de code a échoué.${NC}"
  echo "   Vérifiez les erreurs ci-dessus (conflits de types Hive, annotations manquantes, etc.)."
  exit 1
fi

echo ""
echo "============================================"
echo -e "${VERT}✅ Build Runner terminé.${NC}"
echo "============================================"

exit 0