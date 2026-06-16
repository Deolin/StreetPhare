#!/bin/bash
# ============================================================================
#  scripts/test_integration.sh
#  StreetPhare — Lancement des tests d'intégration sur une cible définie
#
#  Actions :
#    - Vérifie Flutter et la disponibilité d'au moins un appareil
#    - Lance les tests d'intégration Flutter sur la cible spécifiée
#      (appareil physique Android, émulateur, ou Windows natif)
#    - Gère le cas où plusieurs appareils sont connectés
#
#  Usage :
#    bash scripts/test_integration.sh [--device <id>] [--target <fichier_test>]
#    bash scripts/test_integration.sh --device windows
#    bash scripts/test_integration.sh --device android --target integration_test/app_test.dart
#
#  Par défaut : exécute sur le premier appareil Android connecté
# ============================================================================

set -e

VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
NC="\033[0m"

DEVICE=""
TARGET="integration_test"

# ── Parsing des arguments ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage : bash scripts/test_integration.sh [--device <id>] [--target <fichier_test>]"
      echo ""
      echo "  --device <id>     ID de l'appareil cible (ex: 'windows', 'emulator-5554',"
      echo "                    ou un ID complet depuis 'flutter devices')"
      echo "  --target <path>   Chemin du fichier de test (défaut: integration_test)"
      exit 0
      ;;
    *) 
      echo -e "${ROUGE}❌ Argument inconnu : $1${NC}"
      exit 1
      ;;
  esac
done

echo ""
echo "============================================"
echo "  StreetPhare — Tests d'Intégration"
echo "============================================"
echo ""

# ── Vérification Flutter ─────────────────────────────────────────────────
echo -e "${VERT}▶ Vérification de Flutter...${NC}"
if ! command -v flutter &>/dev/null; then
  echo -e "${ROUGE}❌ Flutter introuvable.${NC}"
  exit 1
fi
echo -e "  ${VERT}✅ OK${NC}"

# ── Détection des appareils disponibles ──────────────────────────────────
echo ""
echo -e "${VERT}▶ Appareils disponibles :${NC}"
flutter devices 2>/dev/null | grep -E "•|\(mobile\)|\(desktop\)" || {
  echo -e "${JAUNE}⚠ Aucun appareil détecté.${NC}"
  echo "   Assurez-vous qu'un appareil Android est connecté (USB + débogage activé)."
  echo "   Ou lancez l'application en mode test sur Windows."
}

# ── Sélection de la cible ────────────────────────────────────────────────
if [ -z "$DEVICE" ]; then
  # Détection automatique : premier appareil Android physique
  DEVICE=$(flutter devices --machine 2>/dev/null | python3 -c "
import json, sys
try:
    devices = json.load(sys.stdin)
    for d in devices:
        if d.get('targetPlatform','').startswith('android') and not d.get('emulator', True):
            print(d['id'])
            break
except:
    pass
" 2>/dev/null || echo "")
  
  if [ -z "$DEVICE" ]; then
    # Fallback : Windows desktop
    DEVICE="windows"
    echo -e "${JAUNE}⚠ Aucun appareil Android physique détecté. Utilisation de Windows.${NC}"
  fi
fi

echo ""
echo -e "${VERT}▶ Cible d'exécution :${NC} $DEVICE"
echo -e "${VERT}▶ Fichier de test   :${NC} $TARGET"

# ── Exécution des tests d'intégration ────────────────────────────────────
echo ""
echo -e "${VERT}▶ Lancement des tests d'intégration...${NC}"
echo ""

if [ -d "$TARGET" ] || [ -f "$TARGET" ]; then
  flutter test "$TARGET" -d "$DEVICE" 2>&1
else
  # Tente via 'flutter test integration_test' directement
  echo -e "${JAUNE}⚠ '$TARGET' introuvable, tentative via flutter test...${NC}"
  if [ -d "integration_test" ]; then
    flutter test integration_test -d "$DEVICE" 2>&1
  else
    echo -e "${ROUGE}❌ Aucun dossier integration_test trouvé.${NC}"
    echo "   Créez un dossier integration_test/ avec vos tests d'intégration."
    exit 1
  fi
fi

EXIT_CODE=$?

echo ""
echo "--------------------------------------------"

if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${VERT}✅ Tests d'intégration réussis.${NC}"
else
  echo -e "${ROUGE}❌ Échec des tests d'intégration (code $EXIT_CODE).${NC}"
fi

echo "============================================"

exit $EXIT_CODE