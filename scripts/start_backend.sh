#!/bin/bash
# ============================================================================
#  scripts/start_backend.sh
#  StreetPhare — Démarrage du serveur de relais WebSocket local (Node.js)
#
#  Actions :
#    - Vérifie Node.js et les dépendances npm
#    - Installe les dépendances si nécessaire
#    - Démarre le serveur principal (port 3000 par défaut)
#      avec le LiveMonitor WebSocket (port 4001)
#    - Affiche les URLs de connexion pour le NetworkCoordinator Flutter
#
#  Usage : bash scripts/start_backend.sh [--port <port>] [--all]
#    --port <port>   Port du serveur principal (défaut: 3000)
#    --all           Démarre TOUS les serveurs (primary + backup + dashboard + vitrine)
#
#  Variables d'environnement :
#    STREETPHARE_MASTER_KEY   Clé maître de chiffrement (défaut: streetphare-dev-key)
#    PORT                     Port du serveur primaire (défaut: 3000)
# ============================================================================

set -e

VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

PRIMARY_PORT="${PORT:-3000}"
START_ALL=false

# ── Parsing des arguments ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PRIMARY_PORT="$2"
      shift 2
      ;;
    --all)
      START_ALL=true
      shift
      ;;
    --help|-h)
      echo "Usage : bash scripts/start_backend.sh [--port <port>] [--all]"
      echo ""
      echo "  --port <port>   Port du serveur principal (défaut: 3000)"
      echo "  --all           Démarre tous les serveurs (primary + backup + dashboard + vitrine)"
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
echo "  StreetPhare — Serveur Backend WebSocket"
echo "============================================"
echo ""

# ── Vérification Node.js ─────────────────────────────────────────────────
echo -e "${VERT}▶ Vérification de Node.js...${NC}"
if ! command -v node &>/dev/null; then
  echo -e "${ROUGE}❌ Node.js introuvable dans le PATH.${NC}"
  echo "   Installez Node.js >= 18 depuis https://nodejs.org/"
  exit 1
fi
NODE_VERSION=$(node --version)
echo -e "  ${VERT}✅ Node.js $NODE_VERSION détecté${NC}"

# ── Vérification et installation des dépendances ─────────────────────────
echo ""
echo -e "${VERT}▶ Vérification des dépendances npm...${NC}"
cd test_servers

if [ ! -d "node_modules" ] || [ ! -d "node_modules/express" ] || [ ! -d "node_modules/ws" ]; then
  echo -e "  ${JAUNE}⚠ Dépendances manquantes. Installation...${NC}"
  npm install --no-audit --no-fund --loglevel=error
  echo -e "  ${VERT}✅ Dépendances installées.${NC}"
else
  echo -e "  ${VERT}✅ Dépendances présentes.${NC}"
fi

cd ..

# ── Démarrage du/des serveurs ────────────────────────────────────────────
echo ""
echo -e "${VERT}▶ Démarrage du serveur backend...${NC}"

if [ "$START_ALL" = true ]; then
  echo -e "  ${CYAN}🚀 Lancement de TOUS les services StreetPhare :${NC}"
  echo ""
  cd test_servers
  
  # Définition des variables d'environnement pour launch_all.js
  export STREETPHARE_MASTER_KEY="${STREETPHARE_MASTER_KEY:-streetphare-dev-key-CHANGE_ME_IN_PROD}"
  export STREETPHARE_LOG="1"
  export NODE_ENV="development"
  
  node launch_all.js &
  LAUNCH_PID=$!
  
  cd ..
  
  echo ""
  echo "--------------------------------------------"
  echo -e "  ${CYAN}Services StreetPhare :${NC}"
  echo "  • Primary   → http://localhost:3000/ping"
  echo "  • Backup    → http://localhost:3001/ping"
  echo "  • Admin     → http://localhost:4000/dashboard"
  echo "  • Vitrine   → http://localhost:5000"
  echo "  • LiveMon.  → ws://localhost:4001"
  echo "--------------------------------------------"
  echo ""
  echo -e "  ${VERT}✅ PID du launchpad : $LAUNCH_PID${NC}"
  echo "  Appuyez sur Ctrl+C pour arrêter tous les services."
  
  # Attente du processus principal
  wait $LAUNCH_PID 2>/dev/null || true
  
else
  echo -e "  ${CYAN}🚀 Lancement du serveur primaire (port $PRIMARY_PORT)...${NC}"
  echo ""
  cd test_servers
  
  export PORT="$PRIMARY_PORT"
  export ROLE="primary"
  export STREETPHARE_MASTER_KEY="${STREETPHARE_MASTER_KEY:-streetphare-dev-key-CHANGE_ME_IN_PROD}"
  export STREETPHARE_LOG="1"
  export NODE_ENV="development"
  
  node server_primary_v2.js &
  SERVER_PID=$!
  
  cd ..
  
  echo ""
  echo "--------------------------------------------"
  echo -e "  ${CYAN}Service StreetPhare :${NC}"
  echo "  • Primary   → http://localhost:${PRIMARY_PORT}/ping"
  echo "  • WebSocket → ws://localhost:${PRIMARY_PORT}"
  echo "--------------------------------------------"
  echo ""
  echo -e "  ${VERT}✅ PID du serveur : $SERVER_PID${NC}"
  echo "  Appuyez sur Ctrl+C pour arrêter le serveur."
  
  # Attente du processus
  wait $SERVER_PID 2>/dev/null || true
fi

echo ""
echo -e "${VERT}✅ Serveur backend arrêté.${NC}"

exit 0