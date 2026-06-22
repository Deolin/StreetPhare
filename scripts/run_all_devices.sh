#!/bin/bash
# ============================================================================
#  scripts/run_all_devices.sh
#  StreetPhare — Déploiement Tout-en-Un multi-appareils + iOS Appetize.io
#
#  Actions :
#    A. Détecte dynamiquement :
#       - Le(s) téléphone(s) Android connecté(s) en USB
#       - La/les tablette(s) Android connectée(s) en USB
#       - La cible Windows (desktop natif)
#    B. Lance 'flutter run -d <id>' en parallèle sur chaque appareil détecté
#    C. Compile le build iOS en mode simulateur ET le déploie sur Appetize.io
#       (⚠ nécessite macOS avec Xcode — ignoré sous Windows/Linux)
#    D. Ouvre automatiquement le navigateur sur l'URL Appetize.io
#
#  Usage :
#    bash scripts/run_all_devices.sh [--no-ios] [--no-windows] [--debug]
#
#  Prérequis :
#    - Flutter 3.44+ avec Android SDK 36, Windows build tools
#    - Appareils Android en mode développeur + débogage USB activé
#    - Variables d'environnement (optionnelles) :
#        APPETIZE_TOKEN   Token d'API Appetize.io
#        APPETIZE_APP_KEY Clé publique de l'application (pour mise à jour)
#    - curl, zip (pour l'envoi iOS vers Appetize)
#
#  Exemples :
#    bash scripts/run_all_devices.sh
#    bash scripts/run_all_devices.sh --no-ios
#    APPETIZE_TOKEN="tok_xxx" bash scripts/run_all_devices.sh
# ============================================================================

set -e

# ── Couleurs ────────────────────────────────────────────────────────────
VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m"

# ── Configuration par défaut ─────────────────────────────────────────────
SKIP_IOS=true
SKIP_WINDOWS=true
DEBUG_MODE=false

# Token et clé Appetize (variables d'environnement)
APPETIZE_TOKEN="${APPETIZE_TOKEN:-tok_koo2pg5fquzsaw6d7cgyhtr6ge}"
APPETIZE_APP_KEY="${APPETIZE_APP_KEY:-}"  # Si vide, crée une nouvelle app

# ── Parsing des arguments ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-ios)     SKIP_IOS=true; shift ;;
    --no-windows) SKIP_WINDOWS=true; shift ;;
    --debug)      DEBUG_MODE=true; shift ;;
    --help|-h)
      echo "Usage : bash scripts/run_all_devices.sh [--no-ios] [--no-windows] [--debug]"
      echo ""
      echo "  --no-ios       Ne pas compiler/déployer la version iOS sur Appetize.io"
      echo "  --no-windows   Ne pas lancer la version Windows native"
      echo "  --debug        Mode verbeux (affiche toutes les commandes)"
      exit 0
      ;;
    *)
      echo -e "${ROUGE}❌ Argument inconnu : $1${NC}"
      exit 1
      ;;
  esac
done

# ── Debug mode ───────────────────────────────────────────────────────────
if [ "$DEBUG_MODE" = true ]; then
  set -x
fi

echo ""
echo "============================================"
echo "  StreetPhare — Déploiement Tout-en-Un"
echo "============================================"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# FONCTIONS UTILITAIRES
# ═══════════════════════════════════════════════════════════════════════════

# Tableau pour stocker les PIDs des processus lancés
declare -a PIDS=()
LOGDIR="logs/run_logs_$(date +%Y%m%d_%H%M%S)"

# Fonction de nettoyage en cas d'interruption
cleanup() {
  echo ""
  echo -e "${JAUNE}⚠ Interruption détectée. Arrêt de tous les processus...${NC}"
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "  • Processus $pid arrêté."
    fi
  done
  echo -e "${VERT}✅ Nettoyage terminé.${NC}"
  exit 130
}
trap cleanup SIGINT SIGTERM

# ── Vérification des prérequis ───────────────────────────────────────────
echo -e "${VERT}▶ Vérification des prérequis...${NC}"

if ! command -v flutter &>/dev/null; then
  echo -e "${ROUGE}❌ Flutter introuvable.${NC}"
  exit 1
fi
echo -e "  ${VERT}✅ Flutter OK${NC}"

if ! command -v python3 &>/dev/null; then
  echo -e "${JAUNE}⚠ python3 non trouvé — la détection avancée des appareils est limitée.${NC}"
else
  echo -e "  ${VERT}✅ python3 OK${NC}"
fi

# ── Création du dossier de logs ──────────────────────────────────────────
mkdir -p "$LOGDIR"
echo -e "  ${VERT}✅ Logs → $LOGDIR/${NC}"

# ═══════════════════════════════════════════════════════════════════════════
# ÉTAPE 0 : Synchronisation des dépendances
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${VERT}▶ Synchronisation des dépendances Flutter...${NC}"
flutter pub get 2>&1 | tail -3

# ═══════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 : Détection des appareils Android
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================"
echo -e "  ${CYAN}📱 DÉTECTION DES APPAREILS${NC}"
echo "============================================"
echo ""

# Récupération de la liste complète des appareils en JSON
DEVICES_JSON=$(flutter devices --machine 2>/dev/null || echo "[]")

if [ "$DEBUG_MODE" = true ]; then
  echo "Sortie brute de flutter devices --machine :"
  echo "$DEVICES_JSON" | python3 -m json.tool 2>/dev/null || echo "$DEVICES_JSON"
  echo ""
fi

# ── Détection intelligente avec Python ───────────────────────────────────
parse_devices() {
  echo "$DEVICES_JSON" | python3 -c "
import json, sys

try:
    devices = json.load(sys.stdin)
except:
    print('[]')
    sys.exit(0)

phones = []
tablets = []
windows_devices = []
others = []

for d in devices:
    did = d.get('id', '')
    name = d.get('name', '')
    platform = d.get('targetPlatform', '')
    emulator = d.get('emulator', False)
    
    # Windows desktop
    if platform.startswith('windows'):
        windows_devices.append({'id': did, 'name': name})
        continue
    
    # Android uniquement
    if not platform.startswith('android'):
        continue
    
    # Classification téléphone vs tablette
    # Une tablette a généralement un ID ou nom contenant 'tab', 'tablet',
    # ou l'API indique 'android-arm64'/'android-x64' sans distinction.
    # On utilise une heuristique basée sur le nom.
    name_lower = name.lower()
    is_tablet = any(kw in name_lower for kw in ['tab', 'tablet', 'pad', 'large', 'pixel c', 'nexus 9', 'nexus 10', 'galaxy tab', 'mediapad'])
    
    if is_tablet:
        tablets.append({'id': did, 'name': name, 'emulator': emulator})
    else:
        phones.append({'id': did, 'name': name, 'emulator': emulator})

# Si on a plusieurs appareils Android mais aucun classifié comme tablette,
# le deuxième+ est probablement une tablette (cas USB-C double)
if len(phones) >= 2 and not tablets:
    # Le premier reste téléphone, les suivants passent en tablette
    tablets = phones[1:]
    phones = phones[:1]

result = {
    'phones': phones,
    'tablets': tablets,
    'windows': windows_devices,
    'total': len(phones) + len(tablets) + len(windows_devices)
}

print(json.dumps(result))
"
}

PARSED=$(parse_devices)

if [ "$DEBUG_MODE" = true ]; then
  echo "Résultat du parsing :"
  echo "$PARSED" | python3 -m json.tool 2>/dev/null || echo "$PARSED"
  echo ""
fi

# Extraction des IDs par catégorie
PHONE_IDS=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print('\n'.join([p['id'] for p in d.get('phones',[])]))" 2>/dev/null || echo "")
TABLET_IDS=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print('\n'.join([t['id'] for t in d.get('tablets',[])]))" 2>/dev/null || echo "")
WINDOWS_IDS=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print('\n'.join([w['id'] for w in d.get('windows',[])]))" 2>/dev/null || echo "")

# Affichage du résumé
echo -e "${MAGENTA}📱 Téléphones Android détectés :${NC}"
if [ -n "$PHONE_IDS" ]; then
  echo "$PARSED" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('phones',[]):
    emu = ' (émulateur)' if p.get('emulator') else ''
    print(f'  • {p[\"name\"]} → ID: {p[\"id\"]}{emu}')
" 2>/dev/null || echo "$PHONE_IDS" | while read id; do echo "  • $id"; done
else
  echo -e "  ${JAUNE}⚠ Aucun téléphone Android détecté${NC}"
fi

echo -e "${MAGENTA}📋 Tablettes Android détectées :${NC}"
if [ -n "$TABLET_IDS" ]; then
  echo "$PARSED" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d.get('tablets',[]):
    emu = ' (émulateur)' if t.get('emulator') else ''
    print(f'  • {t[\"name\"]} → ID: {t[\"id\"]}{emu}')
" 2>/dev/null || echo "$TABLET_IDS" | while read id; do echo "  • $id"; done
else
  echo -e "  ${JAUNE}⚠ Aucune tablette Android détectée${NC}"
fi

echo -e "${MAGENTA}💻 Cibles Windows :${NC}"
if [ -n "$WINDOWS_IDS" ]; then
  echo "$PARSED" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for w in d.get('windows',[]):
    print(f'  • {w[\"name\"]} → ID: {w[\"id\"]}')
" 2>/dev/null || echo "$WINDOWS_IDS" | while read id; do echo "  • $id"; done
else
  echo -e "  ${JAUNE}⚠ Aucune cible Windows détectée (normal si Windows build tools non installés)${NC}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 : Build iOS Simulator + Déploiement Appetize.io
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================"
echo -e "  ${CYAN}🍎 BUILD iOS SIMULATOR + APPETIZE.IO${NC}"
echo "============================================"
echo ""

if [ "$SKIP_IOS" = true ]; then
  echo -e "${JAUNE}⚠ Partie iOS ignorée (--no-ios)${NC}"
else
  # Détection de l'OS
  OS_TYPE=$(uname -s 2>/dev/null || echo "Windows")
  
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    # ── macOS : build iOS natif ──────────────────────────────────────────
    echo -e "${VERT}▶ macOS détecté — Compilation iOS Simulator...${NC}"
    
    if flutter build ios --simulator --no-codesign 2>&1 | tee "$LOGDIR/ios_build.log"; then
      echo -e "  ${VERT}✅ Build iOS réussi.${NC}"
      
      # Vérification du .app généré
      APP_PATH="build/ios/iphonesimulator/Runner.app"
      if [ -d "$APP_PATH" ]; then
        echo -e "  ${VERT}✅ Runner.app trouvé : $APP_PATH${NC}"
        
        # Création du zip
        echo -e "${VERT}▶ Création de l'archive zip...${NC}"
        cd build/ios/iphonesimulator
        zip -r app.zip Runner.app 2>&1 | tail -3
        cd ../../..
        echo -e "  ${VERT}✅ Archive créée : build/ios/iphonesimulator/app.zip${NC}"
        
        # Envoi à Appetize.io
        echo ""
        echo -e "${VERT}▶ Envoi à Appetize.io...${NC}"
        
        APPETIZE_URL="https://${APPETIZE_TOKEN}@api.appetize.io/v1/apps"
        if [ -n "$APPETIZE_APP_KEY" ]; then
          APPETIZE_URL="${APPETIZE_URL}/${APPETIZE_APP_KEY}"
          echo "   Mise à jour de l'application existante : $APPETIZE_APP_KEY"
        else
          echo "   Création d'une nouvelle application sur Appetize.io"
        fi
        
        APPETIZE_RESPONSE=$(curl -s -X POST "$APPETIZE_URL" \
          -F "file=@build/ios/iphonesimulator/app.zip" \
          -F "platform=ios" \
          -w "\n%{http_code}" 2>&1)
        
        HTTP_CODE=$(echo "$APPETIZE_RESPONSE" | tail -1)
        RESPONSE_BODY=$(echo "$APPETIZE_RESPONSE" | sed '$d')
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
          PUBLIC_KEY=$(echo "$RESPONSE_BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('publicKey',''))" 2>/dev/null || echo "")
          
          echo -e "  ${VERT}✅ Déploiement Appetize.io réussi !${NC}"
          if [ -n "$PUBLIC_KEY" ]; then
            STREAM_URL="https://appetize.io/embed/${PUBLIC_KEY}?device=iphone15&autoplay=true"
            echo ""
            echo "  --------------------------------------------"
            echo -e "  ${CYAN}🔗 URL de streaming iOS :${NC}"
            echo "  $STREAM_URL"
            echo "  --------------------------------------------"
            
            # Ouverture dans le navigateur
            echo ""
            echo -e "${VERT}▶ Ouverture du navigateur sur le simulateur iOS...${NC}"
            if command -v start &>/dev/null; then
              start "$STREAM_URL" 2>/dev/null || true
            elif command -v open &>/dev/null; then
              open "$STREAM_URL" 2>/dev/null || true
            elif command -v xdg-open &>/dev/null; then
              xdg-open "$STREAM_URL" 2>/dev/null || true
            fi
            echo -e "  ${VERT}✅ Navigateur ouvert.${NC}"
          fi
        else
          echo -e "  ${ROUGE}❌ Erreur Appetize.io (HTTP $HTTP_CODE)${NC}"
          echo "  Réponse : $RESPONSE_BODY"
        fi
      else
        echo -e "  ${ROUGE}❌ Runner.app introuvable après le build.${NC}"
      fi
    else
      echo -e "  ${ROUGE}❌ Le build iOS a échoué. Vérifiez Xcode et les certificats.${NC}"
    fi
    
  elif [[ "$OS_TYPE" == "Linux" ]] || [[ "$OS_TYPE" == "MINGW"* ]] || [[ "$OS_TYPE" == "MSYS"* ]] || [[ "$OS_TYPE" == "Windows" ]]; then
    # ── Windows/Linux : pas de build iOS natif possible ─────────────────
    echo -e "${JAUNE}⚠ Build iOS non disponible sur $OS_TYPE.${NC}"
    echo ""
    echo "  Pour déployer sur Appetize.io depuis Windows/Linux :"
    echo "  1. Construisez le .app sur un Mac :"
    echo "       flutter build ios --simulator --no-codesign"
    echo "  2. Transférez build/ios/iphonesimulator/Runner.app sur cette machine"
    echo "  3. Placez-le dans build/ios/iphonesimulator/"
    echo "  4. Relancez ce script avec --no-android --no-windows"
    echo ""
    
    # Vérification si un .app existe déjà (importé manuellement)
    APP_PATH="build/ios/iphonesimulator/Runner.app"
    if [ -d "$APP_PATH" ]; then
      echo -e "  ${VERT}✅ Runner.app trouvé (importé manuellement).${NC}"
      echo -e "${JAUNE}▶ Tentative d'envoi à Appetize.io avec le .app existant...${NC}"
      
      cd build/ios/iphonesimulator
      rm -f app.zip
      zip -r app.zip Runner.app 2>&1 | tail -3
      cd ../../..
      
      APPETIZE_URL="https://${APPETIZE_TOKEN}@api.appetize.io/v1/apps"
      [ -n "$APPETIZE_APP_KEY" ] && APPETIZE_URL="${APPETIZE_URL}/${APPETIZE_APP_KEY}"
      
      echo "   Envoi à $APPETIZE_URL ..."
      curl -s -X POST "$APPETIZE_URL" \
        -F "file=@build/ios/iphonesimulator/app.zip" \
        -F "platform=ios" && echo ""
      
      echo -e "  ${VERT}✅ Envoi terminé. Vérifiez votre tableau de bord Appetize.io.${NC}"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 : Lancement parallèle sur tous les appareils
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================"
echo -e "  ${CYAN}🚀 LANCEMENT SUR LES APPAREILS${NC}"
echo "============================================"
echo ""

LAUNCH_COUNT=0

# ── Lancement sur téléphones Android ────────────────────────────────────
if [ -n "$PHONE_IDS" ]; then
  echo -e "${MAGENTA}▶ Lancement sur téléphone(s) Android...${NC}"
  while IFS= read -r device_id; do
    [ -z "$device_id" ] && continue
    LOGFILE="$LOGDIR/phone_${device_id//[^a-zA-Z0-9]/_}.log"
    echo "   • Déploiement sur $device_id (log: $LOGFILE)"
    flutter run -d "$device_id" --debug > "$LOGFILE" 2>&1 &
    PIDS+=($!)
    LAUNCH_COUNT=$((LAUNCH_COUNT + 1))
  done <<< "$PHONE_IDS"
else
  echo -e "  ${JAUNE}⚠ Aucun téléphone Android à déployer.${NC}"
fi

# ── Lancement sur tablettes Android ──────────────────────────────────────
if [ -n "$TABLET_IDS" ]; then
  echo -e "${MAGENTA}▶ Lancement sur tablette(s) Android...${NC}"
  while IFS= read -r device_id; do
    [ -z "$device_id" ] && continue
    LOGFILE="$LOGDIR/tablet_${device_id//[^a-zA-Z0-9]/_}.log"
    echo "   • Déploiement sur $device_id (log: $LOGFILE)"
    flutter run -d "$device_id" --debug > "$LOGFILE" 2>&1 &
    PIDS+=($!)
    LAUNCH_COUNT=$((LAUNCH_COUNT + 1))
  done <<< "$TABLET_IDS"
else
  echo -e "  ${JAUNE}⚠ Aucune tablette Android à déployer.${NC}"
fi

# ── Lancement sur Windows ────────────────────────────────────────────────
if [ "$SKIP_WINDOWS" = true ]; then
  echo -e "${JAUNE}⚠ Cible Windows ignorée (--no-windows)${NC}"
elif [ -n "$WINDOWS_IDS" ]; then
  echo -e "${MAGENTA}▶ Lancement sur Windows natif...${NC}"
  while IFS= read -r device_id; do
    [ -z "$device_id" ] && continue
    LOGFILE="$LOGDIR/windows_${device_id//[^a-zA-Z0-9]/_}.log"
    echo "   • Déploiement sur $device_id (log: $LOGFILE)"
    flutter run -d "$device_id" --debug > "$LOGFILE" 2>&1 &
    PIDS+=($!)
    LAUNCH_COUNT=$((LAUNCH_COUNT + 1))
  done <<< "$WINDOWS_IDS"
else
  echo -e "  ${JAUNE}⚠ Aucune cible Windows disponible (build tools manquants ?).${NC}"
  echo "   Exécutez 'flutter config --enable-windows-desktop' si nécessaire."
fi

# ── Vérification finale ──────────────────────────────────────────────────
echo ""
echo "--------------------------------------------"

if [ "$LAUNCH_COUNT" -eq 0 ]; then
  echo -e "${ROUGE}❌ Aucun appareil trouvé pour le déploiement.${NC}"
  echo ""
  echo "   Vérifiez :"
  echo "   1. Qu'un appareil Android est connecté en USB avec le débogage activé"
  echo "   2. Que 'flutter devices' liste bien vos appareils"
  echo "   3. D'avoir exécuté 'flutter config --enable-windows-desktop'"
  exit 1
fi

echo ""
echo "============================================"
echo -e "  ${VERT}✅ $LAUNCH_COUNT instance(s) StreetPhare lancée(s)${NC}"
echo ""
echo "  Logs disponibles dans : $LOGDIR/"
echo ""
echo "  Commandes utiles :"
echo "    tail -f $LOGDIR/*.log     # Suivre tous les logs"
echo "    kill ${PIDS[@]}            # Arrêter tous les processus"
echo "============================================"
echo ""
echo -e "  ${CYAN}Appuyez sur Ctrl+C pour arrêter tous les déploiements.${NC}"

# ── Attente des processus ────────────────────────────────────────────────
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done

echo ""
echo -e "${VERT}✅ Tous les processus sont terminés.${NC}"

exit 0