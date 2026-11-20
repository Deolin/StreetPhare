#!/usr/bin/env bash
#
# scripts/patch_reactive_blemobile.sh
#
# Correctif CI : force compileSdk/targetSdk 36 sur reactive_ble_mobile 5.5.0.
#
# Le plugin upstream (pub.dev) déclare `compileSdkVersion 33`, ce qui fait
# échouer `:reactive_ble_mobile:checkReleaseAarMetadata` car ses dépendances
# AndroidX transitives (core 1.13+, lifecycle 2.7+, fragment 1.7+, …) exigent
# compileSdk >= 34.
#
# Ce script reproduit, sur le runner CI, le patch déjà appliqué manuellement
# dans le cache pub local du développeur (voir le bloc « PATCH STREETPHARE »
# du build.gradle patché). Sur pub.dev, la 5.5.0 reste en compileSdk 33 et la
# 5.6.0 impose le Built-in Kotlin (incompatible avec android.builtInKotlin=false),
# d'où ce correctif ciblé.
#
# Usage : bash scripts/patch_reactive_blemobile.sh

set -euo pipefail

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
BLE_DIR="$PUB_CACHE/hosted/pub.dev/reactive_ble_mobile-5.5.0"
GRADLE_FILE="$BLE_DIR/android/build.gradle"

if [ ! -f "$GRADLE_FILE" ]; then
    echo "::warning::reactive_ble_mobile 5.5.0 introuvable sous $BLE_DIR — patch ignoré."
    exit 0
fi

sed -i -e 's/compileSdkVersion 33/compileSdkVersion 36/' -e 's/targetSdkVersion 33/targetSdkVersion 36/' "$GRADLE_FILE"

echo "Patch appliqué : compileSdk/targetSdk 33 -> 36 dans $GRADLE_FILE"
grep -nE 'compileSdkVersion|targetSdkVersion' "$GRADLE_FILE" || true