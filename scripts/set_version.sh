#!/usr/bin/env bash
#
# scripts/set_version.sh
#
# Grave la version cible dans `pubspec.yaml` AVANT de lancer `flutter build`,
# afin que les exécutables (Windows, Linux, Android) embarquent la bonne
# version lue par `package_info_plus` et utilisée par le gestionnaire de
# mises à jour (voir lib/services/github_update_service.dart).
#
# Sans cette étape, un build déclenché via `.github/workflows/release.yml`
# (tag `v*` ou dispatch manuel `version`) conserverait l'ancienne version de
# `pubspec.yaml`, ce qui provoquerait des messages « mise à jour disponible »
# en boucle alors que l'application est déjà à jour.
#
# Usage :
#   bash scripts/set_version.sh <version>
#
# <version> accepte `v0.5.0-alpha`, `0.5.0-alpha`, `v2.3.0`, `2.3.0`…
#   - le préfixe `v`/`V` est retiré ;
#   - le suffixe pré-release (`-alpha`, `-beta.1`) est conservé ;
#   - si vide, `0.0.0` ou `v0.0.0`, la version courante de pubspec.yaml est
#     réutilisée (cas d'un dispatch manuel sans version).
#
# Le numéro de build (`+N`) est incrémenté (+1) par rapport à la valeur
# courante pour garantir un versionCode Android croissant entre les releases.

set -euo pipefail

VERSION_IN="${1:-}"

# ── Version par défaut (dispatch manuel sans version) ───────────────────────
case "$VERSION_IN" in
  "" | "0.0.0" | "v0.0.0" | "V0.0.0")
    VERSION_IN="$(grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([^+]+).*/\1/')"
    ;;
esac

# ── Normalisation : retire un éventuel préfixe v/V (ex: v0.5.0-alpha) ───────
VERSION="$(printf '%s' "$VERSION_IN" | sed -E 's/^[vV]+//')"

# ── Numéro de build : incrémente la valeur existante de pubspec.yaml ────────
CURRENT_BUILD="$(grep -m1 '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+)[[:space:]]*$/\1/')"
if ! printf '%s' "$CURRENT_BUILD" | grep -Eq '^[0-9]+$'; then
  CURRENT_BUILD=0
fi
BUILD=$((CURRENT_BUILD + 1))

# ── Réécriture de la ligne `version:` (fins de ligne LF préservées) ─────────
sed -i -E "s/^version:.*/version: ${VERSION}+${BUILD}/" pubspec.yaml

echo "pubspec.yaml -> version: ${VERSION}+${BUILD}"