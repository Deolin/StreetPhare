#!/bin/bash
# ============================================================================
#  scripts/cleanup.sh
#  StreetPhare — Nettoyage complet de l'environnement de développement
# 
#  Actions :
#    - flutter clean               Nettoie le build Flutter
#    - flutter pub get             Réinstalle les dépendances Dart
#    - gradlew clean               Nettoie le cache Gradle Android
#    - gradlew --stop              Arrête le daemon Gradle
#    - flutter devices             Liste les appareils valides
#    - flutter doctor              Vérifie l'état de l'environnement
# 
#  Usage : bash scripts/cleanup.sh
# ============================================================================

set -e  # Arrêt immédiat en cas d'erreur

# Couleurs pour les logs
VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
NC="\033[0m" # Pas de couleur
LOGFILE="cleanup_$(date +%Y%m%d_%H%M%S).log"

# Fonction pour logger avec horodatage
log() {
  echo -e "[$(date +%H:%M:%S)] $1" | tee -a "$LOGFILE"
}

# Fonction pour exécuter une commande avec gestion d'erreur
run_step() {
  local description="$1"
  local cmd="$2"
  
  log "${VERT}▶ $description${NC}"
  if eval "$cmd" >> "$LOGFILE" 2>&1; then
    log "  ${VERT}✅ OK${NC} — $description"
    return 0
  else
    log "  ${ROUGE}❌ ÉCHEC${NC} — $description"
    return 1
  fi
}

echo ""
echo "============================================"
echo "  StreetPhare — Nettoyage de l'environnement"
echo "============================================"
echo "  Journal : $LOGFILE"
echo "============================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────
# 1. Flutter Clean
# ─────────────────────────────────────────────────────────────────────────
log "📦 Étape 1/7 : Flutter Clean..."
run_step "Flutter clean" "flutter clean" || {
  log "${ROUGE}Flutter clean a échoué. Vérifiez que Flutter est installé.${NC}"
}

# ─────────────────────────────────────────────────────────────────────────
# 2. Flutter Pub Get
# ─────────────────────────────────────────────────────────────────────────
log "📦 Étape 2/7 : Flutter Pub Get (réinstallation des dépendances)..."
run_step "Flutter pub get" "flutter pub get" || {
  log "${ROUGE}Flutter pub get a échoué. Vérifiez pubspec.yaml.${NC}"
}

# ─────────────────────────────────────────────────────────────────────────
# 3. Gradle Clean (Android)
# ─────────────────────────────────────────────────────────────────────────
log "📦 Étape 3/7 : Gradle Clean (Android)..."
if [ -f "android/gradlew" ]; then
  run_step "Gradle clean" "cd android && ./gradlew clean --no-daemon" || {
    log "${JAUNE}⚠ Gradle clean a échoué (peut être normal si premier build).${NC}"
  }
else
  log "${JAUNE}⚠ android/gradlew introuvable — génération via Flutter...${NC}"
  cd android && gradle wrapper --gradle-version 9.3.0 && cd ..
  run_step "Gradle clean (après génération)" "cd android && ./gradlew clean --no-daemon" || true
fi

# ─────────────────────────────────────────────────────────────────────────
# 4. Arrêt du Daemon Gradle
# ─────────────────────────────────────────────────────────────────────────
log "📦 Étape 4/7 : Arrêt du daemon Gradle..."
if [ -f "android/gradlew" ]; then
  run_step "Gradle daemon stop" "cd android && ./gradlew --stop" || {
    log "${JAUNE}⚠ Aucun daemon Gradle à arrêter.${NC}"
  }
fi

# ─────────────────────────────────────────────────────────────────────────
# 5. Suppression des caches additionnels
# ─────────────────────────────────────────────────────────────────────────
log "📦 Étape 5/7 : Nettoyage des caches résiduels..."
# Supprime les dossiers .dart_tool et build s'ils persistent
rm -rf .dart_tool build 2>/dev/null
log "  ${VERT}✅ Caches Dart et build supprimés.${NC}"

# ─────────────────────────────────────────────────────────────────────────
# 6. Liste des appareils disponibles
# ─────────────────────────────────────────────────────────────────────────
log "📱 Étape 6/7 : Détection des appareils connectés..."

echo ""
echo "--------------------------------------------"
echo "  Appareils détectés :"
echo "--------------------------------------------"

# Capture la sortie de flutter devices en JSON (--machine)
DEVICES_OUTPUT=$(flutter devices --machine 2>/dev/null || echo "[]")

# Parse le JSON avec python3 pour un affichage propre
if command -v python3 &>/dev/null; then
  echo "$DEVICES_OUTPUT" | python3 -c "
import json, sys
try:
    devices = json.load(sys.stdin)
    if not devices:
        print('  Aucun appareil détecté.')
    for d in devices:
        name = d.get('name', 'Inconnu')
        did = d.get('id', '?')
        platform = d.get('targetPlatform', '?')
        emulator = ' (émulateur)' if d.get('emulator', False) else ''
        status = ' ✅ valide' if d.get('supported', True) else ' ⚠ non supporté'
        print(f'  • {name} [{platform}] ID: {did}{emulator}{status}')
except:
    print('  Impossible de parser la sortie JSON.')
" 2>/dev/null || {
  # Fallback : affichage brut si python3 échoue
  flutter devices 2>/dev/null || log "${JAUNE}⚠ flutter devices indisponible.${NC}"
}
else
  flutter devices 2>/dev/null || log "${JAUNE}⚠ flutter devices indisponible.${NC}"
fi
echo "--------------------------------------------"
echo ""

# ─────────────────────────────────────────────────────────────────────────
# 7. Flutter Doctor
# ─────────────────────────────────────────────────────────────────────────
log "🩺 Étape 7/7 : Diagnostic Flutter (flutter doctor)..."
echo ""
flutter doctor -v 2>&1 | tee -a "$LOGFILE" || {
  log "${JAUNE}⚠ flutter doctor a rencontré des avertissements.${NC}"
}

# ─────────────────────────────────────────────────────────────────────────
# Résumé
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
log "${VERT}✅ Nettoyage terminé.${NC}"
echo "   Journal complet : $LOGFILE"
echo "============================================"

exit 0