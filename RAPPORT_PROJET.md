# Rapport d'Avancement du Projet — StreetPhare

> **Date de génération** : 10 octobre 2026
> **Périmètre** : analyse complète du workspace (client Flutter, serveur Node.js, proxy Caddy, MCP, site vitrine, CI/CD)
> **Méthode** : inspection de l'arborescence, des fichiers de configuration et du code source

---

## 1. Vue d'ensemble & Objectif

**StreetPhare** est une application **citoyenne de cartographie collaborative en temps réel**, pensée pour **sécuriser les déplacements piétons lors d'événements et de rassemblements publics** (manifestations, festivals, etc.).

### Objectif principal
- Permettre aux utilisateurs de **signaler des dangers** (barrages, policiers, nasses, autopompes, dangers, groupes de casseurs…) et de **recevoir les signalements validés par consensus**.
- Calculer des **itinéraires piétons « safe »** en évitant ou pondérant les zones dangereuses.
- Déclencher des **alertes PANIC** (individuelles et collectives) en cas d'urgence.
- Fonctionner en **offline-first / décentralisé** : mesh P2P (BLE, Wi-Fi Direct, WebSocket relay) prioritaire, serveur central **optionnel** (failover primary/backup).
- Garantir l'**anonymat et le respect du RGPD** (aucune donnée personnelle, UUID éphémères rotatifs, chiffrement de bout en bout, TTL stricts, droit à l'oubli, kill switch).

### Positionnement
Application open source sous **licence GPLv3**, multi-plateforme (Android, iOS, Windows, Linux, macOS, Web), accompagnée d'une **infrastructure serveur** légère, d'un **site vitrine** statique et d'un **serveur MCP** (Model Context Protocol).

---

## 2. Architecture & Stack Technique

### 2.1 Vue d'ensemble de l'arborescence

```text
StreetPhare/
├── lib/                         # Application Flutter (~115 fichiers Dart, ~37 000 lignes)
│   ├── main.dart                # Point d'entrée (bootstrap complet)
│   ├── core/                    # Cœur transverse (auth, cache, config, di, i18n,
│   │                            #   models, network, router, security, services, theme)
│   ├── features/                # Fonctionnalités métier (feature-first)
│   │   ├── splash/  start_screen/  tutorial/   # Onboarding
│   │   ├── map/                              # Carte (OSM) + couche « safe route »
│   │   ├── reports/                          # Signalements citoyens
│   │   ├── alerts/                           # Modèle + politiques TTL/visibilité
│   │   ├── panic/                            # Alerte PANIC (individuel/collectif)
│   │   ├── events/                           # Événements + QR + géorepérage
│   │   ├── geofencing/                       # Zones + validation de proximité
│   │   ├── messaging/                        # Messagerie (Hive) + blocage
│   │   ├── routing/                          # Routage A*/Dijkstra/SPG + OsmAnd/GraphHopper
│   │   ├── admin/                            # Dashboard administrateur
│   │   ├── bug_report/                       # Rapport de crash offline-first
│   │   ├── settings/                         # Préférences, contacts panic, thème
│   │   └── sandbox/                          # Contrôleur de test
│   ├── network/                 # Couche réseau P2P (bootstrap, failover, sync, transports)
│   ├── services/                # Services applicatifs (notifications, APK, version, tuiles…)
│   ├── database/                # Hive + crypto_utils (AES/HMAC) + TTL/visibilité
│   ├── debug/                   # ClientDebugLogger (génère status/CLIENT_DEBUG.md)
│   └── l10n/                    # Fichiers ARB générés (4 langues)
├── android/                     # Natif Android (Kotlin, GraphHopper embarqué)
│   ├── app/                     #   MainActivity, OsmAndBridgePlugin (GraphHopper)
│   └── mini_downloader/         #   Mini-installeur APK P2P (~80 ko)
├── ios/ linux/ macos/ windows/  # Plateformes supplémentaires
├── web/                         # Build web Flutter (favicon + manifest + icons)
├── web_vitrine/                 # Site vitrine statique (HTML/CSS/JS, 4 langues)
├── server/                      # Serveur Node.js (Express) v3.0.0
│   ├── src/                     #   primary.js, backup.js, sync.js, store.js, config.js
│   │   ├── middleware/auth.js   #   JWT + RBAC
│   │   └── routes/api.js        #   REST + WebSocket /mesh + /admin
│   ├── Caddyfile                #   Reverse proxy TLS (Let's Encrypt, HSTS)
│   ├── scripts/build-sea.js     #   Build Single Executable (Node SEA)
│   └── .env / .env.example      #   Configuration (MASTER_KEY, JWT_SECRET, ADMIN_HASH…)
├── mcp-server/                  # Serveur MCP TypeScript (intégration IA/Claude)
├── scripts/                     # Scripts shell/PowerShell (build, lint, test, orchestration)
├── test/                        # Tests unitaires (7 fichiers, ~1 900 lignes)
├── docs/audit_execution/        # Rapports d'audit & plans d'action
├── .github/workflows/           # CI/CD (6 workflows)
└── status/                      # Fichiers de statut générés (observabilité)
```

### 2.2 Stack technique complète

| Couche | Technologie | Détails |
|---|---|---|
| **Client mobile** | Flutter / Dart (SDK ≥ 3.6.0) | Architecture feature-first, ~37 kLOC |
| **Cartographie** | `flutter_map` + `latlong2` | Tuiles OpenStreetMap, cache hors-ligne |
| **Routage** | GraphHopper 7.0 (natif Android) + A*/Dijkstra/SPG (Dart) | Calcul « safe route » embarqué, offline |
| **Réseau P2P** | BLE (`flutter_reactive_ble`), WebSocket (`ws`), Wi-Fi Direct | Mesh maillé + relay serveur |
| **Stockage local** | Hive CE (`hive_ce`), `shared_preferences` | Alertes, messages, préférences |
| **Sécurité client** | `cryptography` (AES-256-CBC, Ed25519), `flutter_secure_storage` | Clé maîtresse dans Keystore/Keychain OS |
| **Notifications** | `flutter_local_notifications`, `flutter_foreground_task` | Notifications + tâche de fond |
| **Scan QR** | `mobile_scanner` (MLKit) | Lecture QR événement |
| **Serveur** | Node.js + Express 4 | v3.0.0, ~2 300 lignes |
| **Auth serveur** | JWT (`jsonwebtoken`) + `bcryptjs` + RBAC | Dashboard admin |
| **Sécurité serveur** | `helmet`, `express-rate-limit`, `cors` | Durcissement HTTP + rate limiting |
| **Temps réel** | `ws` (WebSocket) | `/mesh` (propagation alertes), `/admin` |
| **Synchronisation** | `node-cron` + sync HTTP | Primary ↔ Backup (30 s) |
| **Reverse proxy** | Caddy | TLS Let's Encrypt, HSTS, routage `/mesh` |
| **Packaging serveur** | `esbuild` + Node SEA | Exécutable autonome |
| **MCP** | `@modelcontextprotocol/sdk` + `zod` (TypeScript) | Intégration assistant IA |
| **Site vitrine** | HTML/CSS/JS vanilla + i18n | 4 langues (fr, en, nl, de) |
| **CI/CD** | GitHub Actions | analyse + tests + builds Android/iOS/Windows/server |

### 2.3 Topologie réseau

```text
[Client Flutter Android]
    ├──▶ wss://streetphare.ddns.net/mesh      (WebSocket mesh → Caddy → Node.js :3000)
    ├──▶ https://streetphare.ddns.net/api/*   (API REST → Caddy → Node.js :3000)
    └──▶ https://streetphare.ddns.net:3001/*  (Backup → Caddy → Node.js :3001)

[Caddy (TLS termination, HSTS)]
    ├── :443   → 127.0.0.1:3000  (Primary Node.js)
    ├── :3001  → 127.0.0.1:3001  (Backup Node.js)
    └── :4000  → 127.0.0.1:4000  (Dashboard admin)

[Mesh P2P hors-ligne]  BLE / Wi-Fi Direct / relay WebSocket (serveur optionnel)
```

### 2.4 Indicateurs de taille

| Mesure | Valeur |
|---|---|
| Code client Dart (`lib/`) | ~115 fichiers, ~37 000 lignes |
| Serveur Node.js (`server/src/`) | 7 fichiers, ~2 300 lignes |
| Tests unitaires (`test/`) | 7 fichiers, ~1 900 lignes |
| Site vitrine (`web_vitrine/`) | 9 fichiers, ~5 300 lignes |
| Langues supportées (i18n) | 4 (fr, en, nl, de) |
| Workflows CI | 6 |
| Marqueurs TODO/FIXME | ~45 |

## 3. État des Fonctionnalités

> Légende : ✅ Complété · 🟡 En cours / partiel · ⬜ À faire / non confirmé

| Domaine | Fonctionnalité | Statut | Observations |
|---|---|---|---|
| **Onboarding** | Écran de démarrage (splash) + gestion cache 24 h | ✅ | `splash_screen.dart` + `cache_manager.dart` |
| | Écran d'accueil (start screen) | ✅ | `start_screen.dart` + store dédié |
| | Tutoriel pas-à-pas | ✅ | `tutorial_screen.dart` + persistance |
| **Carte** | Carte interactive OpenStreetMap | ✅ | `map_screen.dart`, `flutter_map` |
| | Couche « safe route » + marqueur de cap | ✅ | `safe_route_layer.dart`, `user_heading_marker.dart` |
| | Cache de tuiles hors-ligne | ✅ | `map_tile_download_service.dart` |
| **Signalements** | Feuille de signalement (7 types de dangers) | ✅ | `report_bottom_sheet.dart`, `report_type.dart` |
| | Alertes avec TTL + politiques de visibilité | ✅ | `alert_ttl_policy.dart`, `alert_visibility_policy.dart` |
| | Consensus multi-votes (anti-spam) | ✅ | Seuil de validation serveur (`CONSENSUS_THRESHOLD`) |
| **Panic** | Alerte PANIC individuelle | ✅ | `features/panic/` + `collective_panic_service.dart` |
| | PANIC collectif (agrégation proximité) | ✅ | Serveur : 5 pings < 50 m en 2 min |
| | Contacts d'urgence (panic contacts) | ✅ | `panic_contact_store.dart` |
| **Événements** | Gestion + catalogue d'événements | 🟡 | `event_manager.dart`, `events_screen.dart` (13 TODO dans le modèle) |
| | Scan QR d'entrée d'événement | ✅ | `qr_scanner_screen.dart`, `mobile_scanner` |
| | Fixtures (zone de Fleurus) | ✅ | `fixtures_fleurus.dart` |
| **Géorepérage** | Zones + validation de proximité | ✅ | `geofencing_service.dart`, `proximity_validation_service.dart` |
| **Messagerie** | Messagerie P2P (Hive) + fils | ✅ | `hive_messaging_service.dart`, `hive_messaging_screen.dart` |
| | Blocage d'utilisateurs | ✅ | `hive_block_service.dart` |
| **Routage** | Moteur A*/Dijkstra + graphe SPG | ✅ | `astar.dart`, `dijkstra.dart`, `spg_graph.dart` |
| | Map matching | ✅ | `map_matcher.dart` |
| | Routage OsmAnd (AIDL) | 🟡 | `osmand_routing_service.dart` (8 TODO, fichier dupliqué) |
| | Routage GraphHopper embarqué (Android) | ✅ | `OsmAndBridgePlugin.kt` (Kotlin) |
| | Évitement/pondération de zones (custom model) | 🟡 | `avoidance_filter_store.dart`, dépend de JTS |
| **Admin** | Dashboard + carte administrateur | ✅ | `admin_dashboard_screen.dart`, `admin_map_widget.dart` |
| **Bug report** | Capture de crash offline-first | ✅ | `bug_report_service.dart`, `bug_report_fab.dart` |
| **Paramètres** | Préférences, thème clair/sombre, accessibilité | ✅ | `settings_screen.dart`, `theme_controller.dart` |
| | Internationalisation (fr, en, nl, de) | ✅ | 4 locales ARB + générés |
| **Réseau P2P** | Transports BLE / WebSocket / Wi-Fi Direct / relay | ✅ | `network/transports/*` |
| | Failover primary/backup + heartbeat | ✅ | `failover_manager.dart`, `server_heartbeat_service.dart` |
| | Synchronisation push-pull | ✅ | `sync_service.dart` |
| **Serveur** | REST + WebSocket mesh + sync primary↔backup | ✅ | `api.js`, `sync.js`, `primary.js`, `backup.js` |
| | Auth JWT + RBAC admin | ✅ | `middleware/auth.js` |
| | Build exécutable autonome (Node SEA) | ✅ | `scripts/build-sea.js` |
| **MCP** | Serveur MCP (intégration IA) | 🟡 | `mcp-server/src/server.ts` (135 lignes, minimal) |
| **Sandbox** | Contrôleur de test/playground | ✅ | `sandbox_controller.dart` |
| **Tests** | Tests unitaires | 🟡 | 7 fichiers (~1 900 lignes) — couverture faible vs ~37 kLOC |
| **Documentation** | README racine | 🟡 | Obsolète (décrit une app basique antérieure) |

## 4. Points de Vigilance & Dette Technique

### 4.1 Sécurité

| # | Constat | Gravité | Recommandation |
|---|---|---|---|
| 1 | **`server/.env` est versionné dans Git** (tracké). Il contient `MASTER_KEY`, `JWT_SECRET`, `ADMIN_HASH` (actuellement des *placeholders* de dev, mais le fichier est commité) | 🔴 **Élevée** | Retirer `.env` du suivi (`git rm --cached`), l'ajouter au `.gitignore`, ne conserver que `.env.example`. Régénérer des clés fortes en production. |
| 2 | **`server/data/store.json` est versionné** (données d'exécution, contient une IP LAN privée `192.168.31.63`) | 🟠 Moyenne | L'ignorer dans `.gitignore` (données runtime). |
| 3 | Clés par défaut acceptées hors production | 🟢 Faible (déjà bien géré) | `config.js` **refuse de démarrer** en production avec des clés par défaut (bonne pratique). Maintenir. |
| 4 | `sea-config-*.json` (root + server) commités | 🟢 Faible | Fichiers de build SEA sans secret — OK, mais à surveiller. |
| 5 | `package-lock.json` **ignoré** par `.gitignore` | 🟢 Faible | Réduit la reproductibilité des builds Node.js. Envisager de les versionner. |

**Points forts sécurité** : clé maîtresse dans le **Keystore/Keychain OS** (RSA-OAEP + AES-GCM, pas de clé codée en dur), **UUID éphémères rotatifs**, **AES-256-CBC + HMAC-SHA256** de bout en bout, signatures **Ed25519**, TTL stricts par type d'alerte, **kill switch**, `helmet` + `express-rate-limit` côté serveur, TLS/HSTS via Caddy.

### 4.2 Incohérences d'architecture & documentation

| # | Constat | Impact |
|---|---|---|
| 1 | **`README.md` racine obsolète** : décrit une app basique (3 FAB, map, splash) et référence `INSTALLATION_DEPENDANCES.md` (fichier inexistant). Ne reflète pas les ~15 fonctionnalités réelles. | Onboarding contributeur trompeur. |
| 2 | **`server/README.md` incohérent** : annonce un « Serveur Dart » (shelf, `bin/server.dart`) alors que le serveur réel est **Node.js/Express**. | Confusion sur la stack serveur. |
| 3 | **Dérive de version** : `pubspec.yaml` = `2.2.0+1`, `SECURITY.md` = `2.2.0+1`, docs d'audit = `v3.3.3/v3.3.4`, serveur = `3.0.0`, Caddyfile = `v3.3.3`. | Pas de source de vérité de version. |
| 4 | **Artefacts Dart dans `server/`** : `.dart_tool/`, `build/`, `web/`, `web_src/`, `devtools_options.yaml` coexistent avec le serveur Node.js. | Signe d'une migration Node↔Dart non aboutie / non nettoyée. |
| 5 | **Duplication probable** : `routing/osmand_routing_service.dart` et `routing/infrastructure/osmand_routing_service.dart` (même nom de fichier, deux emplacements). | Risque de divergence de logique. |

### 4.3 Dette technique & refactoring

- **Couverture de tests faible** : 7 fichiers de tests (~1 900 lignes) pour ~37 000 lignes de code client. Les couches réseau, routage et P2P sont peu couvertes.
- **~45 marqueurs TODO/FIXME** concentrés dans `event_model.dart` (13), `osmand_routing_service.dart` (8), `config.js` (6), `splash_screen.dart` (5).
- **Migration Kotlin « built-in » bloquée** : 7 plugins tiers (`cryptography_flutter`, `flutter_foreground_task`, `mobile_scanner`, `objectbox_flutter_libs`, `package_info_plus`, `reactive_ble_mobile`, `share_plus`) appliquent encore KGP manuellement → `android.builtInKotlin=false` maintenu. Documenté mais à surveiller (Flutter l'imposera à terme).
- **Dépendance GraphHopper** : `protobuf-java` et `jts-core` ont été **ré-inclus** récemment (lecture `.pbf` + custom model « zones »), avec exclusion de `protobuf-javalite` pour éviter les classes dupliquées (conflit avec MLKit). À valider sur le terrain.
- **Deux moteurs de routage cohabitent** (OsmAnd AIDL externe + GraphHopper embarqué + A*/Dijkstra Dart) : complexité de maintenance, logique de fallback à centraliser.

---

## 5. Recommandations & Prochaines Étapes (Roadmap priorisée)

### 🔴 Priorité 1 — Sécurité (immédiat)
1. **Sortir `server/.env` du versionnement** (`git rm --cached server/.env`, ajouter `.env` au `.gitignore`).
2. Ignorer `server/data/store.json` et autres données runtime.
3. En production, **régénérer** `MASTER_KEY`, `JWT_SECRET`, `ADMIN_HASH` (openssl + bcrypt 12 rounds) et vérifier que `NODE_ENV=production` est bien défini (le serveur refuse de démarrer sinon — comportement correct).

### 🟠 Priorité 2 — Documentation & cohérence
4. **Réécrire le `README.md` racine** pour refléter l'architecture réelle (features, P2P, serveur, CI).
5. **Corriger `server/README.md`** : remplacer la description « Serveur Dart » par la réalité Node.js/Express (ou documenter clairement les deux cibles).
6. **Unifier le versionnement** : adopter une source unique de version (ex. `pubspec.yaml` + tag Git cohérent entre client, serveur et docs).

### 🟡 Priorité 3 — Qualité & refactoring
7. **Dédupliquer** `osmand_routing_service.dart` (routing/ vs routing/infrastructure/).
8. **Nettoyer** les artefacts Dart résiduels dans `server/` (`.dart_tool`, `build`, `web_src`…) une fois la décision Node vs Dart tranchée.
9. **Augmenter la couverture de tests** sur les couches critiques : `network/` (failover, sync, transports), `routing/` (A*, Dijkstra, map matching), `database/` (crypto, TTL).
10. **Traiter les TODO** : finaliser `event_model.dart` et `osmand_routing_service.dart`.

### 🟢 Priorité 4 — Évolution
11. **Suivre la migration Kotlin built-in** (débloquer `android.builtInKotlin=true` quand les plugins tiers seront compatibles).
12. **Valider GraphHopper + protobuf-java + JTS** sur appareil physique (lecture `.pbf`, zones d'évitement).
13. **MCP server** : documenter son usage et l'intégrer à la CI si pertinent.
14. **Centraliser la logique de fallback routage** (GraphHopper → OsmAnd → OSRM/Dijkstra) dans un seul service.

---

*Rapport généré automatiquement après analyse complète du workspace (10/10/2026).*



