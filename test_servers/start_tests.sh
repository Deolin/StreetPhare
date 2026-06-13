#!/usr/bin/env bash
# ============================================================
#  start_tests.sh
#  Lance les deux serveurs Node.js de test StreetPhare
#  (principal sur 3000 + secondaire sur 3001) en parallele.
#
#  Usage :
#     ./test_servers/start_tests.sh
#  (rendre executable au premier lancement : chmod +x)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Verification Node
if ! command -v node >/dev/null 2>&1; then
  echo "[ERREUR] Node.js introuvable. Installez-le depuis https://nodejs.org/"
  exit 1
fi

# Installation des dependances si necessaire
if [ ! -d "$SCRIPT_DIR/node_modules/express" ]; then
  echo "[*] Installation des dependances (express)..."
  npm install --no-audit --no-fund --loglevel=error
fi

# Cleanup propre
cleanup() {
  echo
  echo "[orchestrator] arret des serveurs..."
  kill "${PID_PRIMARY:-0}" "${PID_SECONDARY:-0}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup INT TERM

echo "============================================"
echo "  StreetPhare - serveurs de test locaux"
echo "============================================"
echo " - Serveur PRINCIPAL   : http://localhost:3000"
echo " - Serveur SECONDAIRE  : http://localhost:3001"
echo " (Ctrl+C pour tout arreter)"
echo "============================================"
echo

PORT=3000 ROLE=primary NEXT_BACKUP_URL=http://localhost:3001 \
  node server_primary.js &
PID_PRIMARY=$!

sleep 1

PORT=3001 ROLE=secondary NEXT_BACKUP_URL=http://localhost:3002 \
  node server_secondary.js &
PID_SECONDARY=$!

wait
