# ============================================================================
#  Makefile — StreetPhare
#  Commandes unifiées pour le développement, les tests et le build.
#
#  Usage :
#    make help          Affiche cette aide
#    make deps          Installe les dépendances Flutter + Node.js
#    make analyze       Lance l'analyse statique Dart
#    make test          Lance les tests unitaires Dart
#    make test:core     Lance uniquement le test core StreetPhare
#    make build:debug   Build APK debug (Android)
#    make build:release Build APK release (Android)
#    make clean         Nettoie les artefacts de build
#    make server        Lance le serveur de test (primary + backup)
#    make server:dev    Lance uniquement le serveur primaire
#    make dashboard     Lance le NOC Dashboard v5.0
#    make sim           Lance la CLI de simulation
# ============================================================================

.PHONY: help deps analyze test test:core build:debug build:release clean \
        server server:dev backup dashboard sim

# ── Aide ────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  🔦 StreetPhare — Commandes de développement"
	@echo "  ============================================="
	@echo ""
	@echo "  Développement Flutter :"
	@echo "    make deps            Installe les dépendances (Flutter + Node.js)"
	@echo "    make analyze         Lance l'analyse statique Dart"
	@echo "    make format          Formate le code Dart"
	@echo "    make test            Lance les tests unitaires Dart"
	@echo "    make test:core       Lance uniquement le test core StreetPhare"
	@echo ""
	@echo "  Build Android :"
	@echo "    make build:debug     Build APK debug"
	@echo "    make build:release   Build APK release"
	@echo "    make clean           Nettoie les artefacts de build"
	@echo ""
	@echo "  Serveurs de test (Node.js) :"
	@echo "    make server          Lance TOUS les serveurs (primary + backup + dashboard)"
	@echo "    make server:dev      Lance uniquement le serveur primaire"
	@echo "    make backup          Lance uniquement le serveur backup"
	@echo "    make dashboard       Lance le NOC Dashboard v5.0 (port 4000)"
	@echo "    make sim             Lance la CLI de simulation interactive"
	@echo ""
	@echo "  Commandes rapides Node.js :"
	@echo "    npm --prefix test_servers run <script>"
	@echo ""
	@echo "  Scripts npm disponibles dans test_servers/ :"
	@echo "    start, dev:server, dev:backup, dev:dashboard, dev:all,"
	@echo "    sim, sim:reset, test:ping, test:status, test:events,"
	@echo "    test:route, test:report, test:failover, test:debug"
	@echo ""

# ── Dépendances ─────────────────────────────────────────────────────────
deps:
	@echo "[*] Installation des dépendances Flutter…"
	flutter pub get
	@echo "[*] Installation des dépendances Node.js (serveurs de test)…"
	cd test_servers && npm install
	@echo "✅ Dépendances installées."

# ── Analyse & Format ────────────────────────────────────────────────────
analyze:
	flutter analyze

format:
	flutter format lib/

# ── Tests ───────────────────────────────────────────────────────────────
test:
	flutter test

test:core:
	flutter test test/streetphare_core_test.dart

# ── Build Android ───────────────────────────────────────────────────────
build:debug:
	cd android && gradlew.bat assembleDebug
	@echo "✅ APK debug généré : build/app/outputs/flutter-apk/app-debug.apk"

build:release:
	cd android && gradlew.bat assembleRelease
	@echo "✅ APK release généré : build/app/outputs/flutter-apk/app-release.apk"

# ── Nettoyage ───────────────────────────────────────────────────────────
clean:
	flutter clean
	cd android && gradlew.bat clean
	@echo "✅ Nettoyage terminé."

# ── Serveurs de test ────────────────────────────────────────────────────
server:
	@echo "▶ Lancement de TOUS les serveurs (primary + backup + dashboard)…"
	cd test_servers && node launch_all.js

server:dev:
	@echo "▶ Lancement du serveur primaire uniquement…"
	cd test_servers && node server_primary_v2.js

backup:
	@echo "▶ Lancement du serveur backup uniquement…"
	cd test_servers && node server_secondary_v2.js

dashboard:
	@echo "▶ Lancement du NOC Dashboard v5.0 (http://localhost:4000)…"
	cd test_servers && node admin_dashboard_v2.js

sim:
	@echo "▶ Lancement de la CLI de simulation…"
	cd test_servers && node sim.js