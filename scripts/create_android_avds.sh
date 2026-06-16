#!/bin/bash
# ============================================================================
#  scripts/create_android_avds.sh
#  StreetPhare — Création des émulateurs Android API 34 et API 36
#
#  Actions :
#    - Vérifie la présence d'Android SDK, sdkmanager, avdmanager
#    - Crée un AVD (Android Virtual Device) pour API 36 (Android 16 Baklava)
#    - Crée un AVD pour API 34 (Android 15) — rétrocompatibilité
#    - Évite les doublons en vérifiant l'existence avant création
#    - Utilise les images système x86_64 avec Google APIs
#
#  Usage :
#    bash scripts/create_android_avds.sh [--delete] [--list]
#      --delete   Supprime les AVD existants avant recréation
#      --list     Liste uniquement les AVD existants
#
#  Prérequis :
#    - Android SDK installé (via Android Studio ou sdkmanager seul)
#    - Variables d'environnement ANDROID_HOME ou ANDROID_SDK_ROOT définies
#    - Java JDK 17+ pour sdkmanager
# ============================================================================

set -e

VERT="\033[0;32m"
JAUNE="\033[1;33m"
ROUGE="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

DELETE_EXISTING=false
LIST_ONLY=false

# ── Parsing des arguments ────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --delete) DELETE_EXISTING=true ;;
    --list)   LIST_ONLY=true ;;
    --help|-h)
      echo "Usage : bash scripts/create_android_avds.sh [--delete] [--list]"
      echo ""
      echo "  --delete   Supprime les AVD existants avant recréation"
      echo "  --list     Liste uniquement les AVD existants"
      exit 0
      ;;
    *) echo -e "${JAUNE}⚠ Argument inconnu : $arg${NC}" ;;
  esac
done

echo ""
echo "============================================"
echo "  StreetPhare — Émulateurs Android"
echo "============================================"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# 1. Détection de l'Android SDK
# ═══════════════════════════════════════════════════════════════════════════
echo -e "${VERT}▶ Détection de l'Android SDK...${NC}"

# Recherche de ANDROID_HOME / ANDROID_SDK_ROOT
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
  # Chemins par défaut selon l'OS
  if [ -d "$HOME/AppData/Local/Android/Sdk" ]; then
    export ANDROID_HOME="$HOME/AppData/Local/Android/Sdk"
  elif [ -d "$HOME/Android/Sdk" ]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
  elif [ -d "/usr/local/share/android-sdk" ]; then
    export ANDROID_HOME="/usr/local/share/android-sdk"
  fi
fi

ANDROID_SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"

if [ -z "$ANDROID_SDK" ]; then
  echo -e "${ROUGE}❌ Android SDK introuvable.${NC}"
  echo ""
  echo "   Définissez ANDROID_HOME ou ANDROID_SDK_ROOT, par exemple :"
  echo "     export ANDROID_HOME=\$HOME/AppData/Local/Android/Sdk"
  echo ""
  echo "   Ou installez Android Studio : https://developer.android.com/studio"
  exit 1
fi

if [ ! -d "$ANDROID_SDK" ]; then
  echo -e "${ROUGE}❌ Le dossier Android SDK n'existe pas : $ANDROID_SDK${NC}"
  exit 1
fi

echo -e "  ${VERT}✅ Android SDK : $ANDROID_SDK${NC}"

# ── Vérification de sdkmanager ───────────────────────────────────────────
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -f "$SDKMANAGER" ]; then
  # Fallback : ancien chemin
  SDKMANAGER="$ANDROID_SDK/tools/bin/sdkmanager"
fi

if [ ! -f "$SDKMANAGER" ]; then
  echo -e "${ROUGE}❌ sdkmanager introuvable dans le SDK.${NC}"
  echo "   Vérifiez que les cmdline-tools sont installés :"
  echo "     Android Studio → SDK Manager → SDK Tools → Android SDK Command-line Tools"
  exit 1
fi
echo -e "  ${VERT}✅ sdkmanager : $SDKMANAGER${NC}"

# ── Vérification de avdmanager ───────────────────────────────────────────
AVDMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/avdmanager"
if [ ! -f "$AVDMANAGER" ]; then
  AVDMANAGER="$ANDROID_SDK/tools/bin/avdmanager"
fi
if [ ! -f "$AVDMANAGER" ]; then
  echo -e "${ROUGE}❌ avdmanager introuvable.${NC}"
  exit 1
fi
echo -e "  ${VERT}✅ avdmanager : $AVDMANAGER${NC}"

# ═══════════════════════════════════════════════════════════════════════════
# 2. Liste des AVD existants (ou mode --list)
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${VERT}▶ Émulateurs AVD existants :${NC}"
echo ""

"$AVDMANAGER" list avd 2>/dev/null | grep -E "Name:|Device:|API level|Target:" || echo "  Aucun AVD trouvé."

if [ "$LIST_ONLY" = true ]; then
  echo ""
  echo "============================================"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# 3. Suppression des anciens AVD (si --delete)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$DELETE_EXISTING" = true ]; then
  echo ""
  echo -e "${JAUNE}▶ Suppression des AVD StreetPhare existants...${NC}"
  
  # Récupération des noms d'AVD StreetPhare
  STREETPHARE_AVDS=$("$AVDMANAGER" list avd 2>/dev/null | grep "Name:" | grep -i "streetphare" | awk '{print $2}' || true)
  
  if [ -n "$STREETPHARE_AVDS" ]; then
    echo "$STREETPHARE_AVDS" | while read -r avd_name; do
      [ -z "$avd_name" ] && continue
      echo "   Suppression de $avd_name..."
      echo "no" | "$AVDMANAGER" delete avd -n "$avd_name" 2>/dev/null || true
    done
    echo -e "  ${VERT}✅ Anciens AVD supprimés.${NC}"
  else
    echo "  Aucun AVD StreetPhare à supprimer."
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 4. Installation des images système nécessaires
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${VERT}▶ Vérification et installation des images système...${NC}"

# Fonction pour accepter les licences
accept_licenses() {
  echo ""
  echo -e "${JAUNE}⚠ Acceptation des licences Android SDK...${NC}"
  yes | "$SDKMANAGER" --licenses 2>/dev/null || {
    echo -e "${JAUNE}⚠ Acceptation des licences partielle — certaines peuvent nécessiter une intervention manuelle.${NC}"
  }
}

accept_licenses

# ── Image API 36 (Android 16, Baklava) avec Google APIs ──────────────────
echo ""
echo "   Vérification de l'image système API 36..."
API36_IMAGE="system-images;android-36;google_apis;x86_64"
if "$SDKMANAGER" --list 2>/dev/null | grep -q "system-images;android-36;google_apis;x86_64"; then
  echo -e "  ${VERT}✅ Image API 36 disponible. Installation...${NC}"
  "$SDKMANAGER" --install "$API36_IMAGE" 2>&1 | tail -5
  echo -e "  ${VERT}✅ Image API 36 installée.${NC}"
else
  # Fallback : image sans Google APIs
  API36_IMAGE="system-images;android-36;default;x86_64"
  if "$SDKMANAGER" --list 2>/dev/null | grep -q "system-images;android-36;default;x86_64"; then
    echo -e "  ${JAUNE}⚠ Google APIs non disponible pour API 36. Utilisation de l'image standard.${NC}"
    "$SDKMANAGER" --install "$API36_IMAGE" 2>&1 | tail -5
  else
    echo -e "  ${ROUGE}❌ Aucune image système API 36 trouvée.${NC}"
    echo "   Vérifiez que le SDK Platform 36 est installé dans le SDK Manager."
  fi
fi

# ── Image API 34 (Android 15) avec Google APIs ───────────────────────────
echo ""
echo "   Vérification de l'image système API 34..."
API34_IMAGE="system-images;android-34;google_apis;x86_64"
if "$SDKMANAGER" --list 2>/dev/null | grep -q "system-images;android-34;google_apis;x86_64"; then
  echo -e "  ${VERT}✅ Image API 34 disponible. Installation...${NC}"
  "$SDKMANAGER" --install "$API34_IMAGE" 2>&1 | tail -5
  echo -e "  ${VERT}✅ Image API 34 installée.${NC}"
else
  API34_IMAGE="system-images;android-34;default;x86_64"
  if "$SDKMANAGER" --list 2>/dev/null | grep -q "system-images;android-34;default;x86_64"; then
    echo -e "  ${JAUNE}⚠ Google APIs non disponible pour API 34. Utilisation de l'image standard.${NC}"
    "$SDKMANAGER" --install "$API34_IMAGE" 2>&1 | tail -5
  else
    echo -e "  ${ROUGE}❌ Aucune image système API 34 trouvée.${NC}"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 5. Création des AVD
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${VERT}▶ Création des émulateurs Android...${NC}"

# ── AVD API 36 ───────────────────────────────────────────────────────────
AVD_36_NAME="StreetPhare_API36"
AVD_36_DEVICE="pixel_8"  # Appareil moderne avec Play Store

echo ""
echo "   Création de l'AVD : $AVD_36_NAME (API 36, $AVD_36_DEVICE)"

# Vérifie si l'AVD existe déjà
if "$AVDMANAGER" list avd 2>/dev/null | grep -q "Name: $AVD_36_NAME"; then
  echo -e "  ${JAUNE}⚠ L'AVD '$AVD_36_NAME' existe déjà. Ignoré.${NC}"
  echo "   Utilisez --delete pour le recréer."
else
  echo "no" | "$AVDMANAGER" create avd \
    -n "$AVD_36_NAME" \
    -k "$API36_IMAGE" \
    -d "$AVD_36_DEVICE" \
    -f 2>&1 | tail -10
  
  if [ $? -eq 0 ]; then
    echo -e "  ${VERT}✅ AVD '$AVD_36_NAME' créé avec succès.${NC}"
    echo ""
    echo "   Pour le lancer :"
    echo "     \$ANDROID_HOME/emulator/emulator -avd $AVD_36_NAME -gpu host &"
  else
    echo -e "  ${ROUGE}❌ Échec de la création de l'AVD API 36.${NC}"
  fi
fi

# ── AVD API 34 ───────────────────────────────────────────────────────────
AVD_34_NAME="StreetPhare_API34"
AVD_34_DEVICE="pixel_6"  # Appareil de rétrocompatibilité

echo ""
echo "   Création de l'AVD : $AVD_34_NAME (API 34, $AVD_34_DEVICE)"

if "$AVDMANAGER" list avd 2>/dev/null | grep -q "Name: $AVD_34_NAME"; then
  echo -e "  ${JAUNE}⚠ L'AVD '$AVD_34_NAME' existe déjà. Ignoré.${NC}"
  echo "   Utilisez --delete pour le recréer."
else
  echo "no" | "$AVDMANAGER" create avd \
    -n "$AVD_34_NAME" \
    -k "$API34_IMAGE" \
    -d "$AVD_34_DEVICE" \
    -f 2>&1 | tail -10
  
  if [ $? -eq 0 ]; then
    echo -e "  ${VERT}✅ AVD '$AVD_34_NAME' créé avec succès.${NC}"
    echo ""
    echo "   Pour le lancer :"
    echo "     \$ANDROID_HOME/emulator/emulator -avd $AVD_34_NAME -gpu host &"
  else
    echo -e "  ${ROUGE}❌ Échec de la création de l'AVD API 34.${NC}"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# 6. Résumé final
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================"
echo -e "  ${CYAN}📋 RÉSUMÉ DES ÉMULATEURS${NC}"
echo "============================================"
echo ""

"$AVDMANAGER" list avd 2>/dev/null | grep -E "Name:|Device:|API level|Target:" | grep -A 3 -i "streetphare" || {
  echo -e "${JAUNE}⚠ Aucun AVD StreetPhare trouvé.${NC}"
}

echo ""
echo "============================================"
echo -e "  ${VERT}✅ Configuration des émulateurs terminée.${NC}"
echo ""
echo "  Commandes de lancement :"
echo "    \$ANDROID_HOME/emulator/emulator -avd StreetPhare_API36 &"
echo "    \$ANDROID_HOME/emulator/emulator -avd StreetPhare_API34 &"
echo ""
echo "  Pour les utiliser avec Flutter :"
echo "    1. Lancez l'émulateur avec la commande ci-dessus"
echo "    2. Vérifiez qu'il apparaît dans 'flutter devices'"
echo "    3. Lancez l'application : flutter run -d emulator-5554"
echo "============================================"

exit 0