# 🏮 StreetPhare

**Application citoyenne de cartographie collaborative en temps réel**, pensée pour **sécuriser les déplacements piétons** lors d'événements et de rassemblements publics (manifestations, festivals, etc.).

Open source (GPLv3) · Multi-plateforme (Android, iOS, Windows, Linux, macOS, Web).

Soutenez-moi via [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L8X321888R)

---

## 🎯 Objectif

StreetPhare permet aux participants d'un événement de :

- **Signaler des dangers** (barrages, policiers, nasses, autopompes, dangers, groupes de casseurs…) et recevoir les signalements **validés par consensus**.
- Calculer des **itinéraires piétons « safe »** en évitant ou pondérant les zones dangereuses.
- Déclencher des **alertes PANIC** individuelles ou collectives.
- Fonctionner en **offline-first / décentralisé** : mesh P2P (BLE, Wi-Fi Direct, WebSocket relay) prioritaire, serveur central **optionnel**.
- Garantir l'**anonymat et le respect du RGPD** (aucune donnée personnelle, UUID éphémères rotatifs, chiffrement de bout en bout, TTL stricts, droit à l'oubli, kill switch).

---

## 🏗️ Architecture

Le client suit une architecture **feature-first**, organisée en couches :

```text
lib/
├── core/          # auth, cache, config, di, i18n, models, network, router,
│                  #   security, services, theme, utils
├── features/      # splash, start_screen, tutorial, map, reports, alerts,
│                  #   panic, events, geofencing, messaging, routing, admin,
│                  #   bug_report, settings, sandbox
├── network/       # P2P (BLE, WebSocket, Wi-Fi Direct, relay), failover, sync
├── services/      # notifications, APK, version, tuiles, permissions
├── database/      # Hive + crypto (AES/HMAC) + politiques TTL/visibilité
├── debug/         # ClientDebugLogger (observabilité locale)
└── l10n/          # fr, en, nl, de (fichiers ARB générés)
```

### Stack technique

| Couche | Technologie |
|---|---|
| **Client** | Flutter / Dart (SDK ≥ 3.6.0) |
| **Cartographie** | `flutter_map` + `latlong2` (tuiles OpenStreetMap, cache hors-ligne) |
| **Routage** | GraphHopper 7.0 embarqué (Android) + A*/Dijkstra/SPG (Dart) + OsmAnd |
| **Réseau P2P** | BLE (`flutter_reactive_ble`), WebSocket (`ws`), Wi-Fi Direct |
| **Stockage local** | Hive CE, `shared_preferences` |
| **Sécurité client** | `cryptography` (AES-256-CBC, Ed25519), `flutter_secure_storage` (Keystore/Keychain OS) |
| **Notifications** | `flutter_local_notifications`, `flutter_foreground_task` |
| **Scan QR** | `mobile_scanner` (MLKit) |
| **Serveur** | Node.js + Express 4 (primary/backup, JWT, rate-limiting) |
| **Reverse proxy** | Caddy (TLS Let's Encrypt, HSTS) |
| **Packaging serveur** | `esbuild` + Node SEA (exécutable autonome) |
| **CI/CD** | GitHub Actions (analyse, tests, builds Android/iOS/Windows/server) |

### Infrastructure réseau

```text
[Client Flutter Android]
    ├──▶ wss://streetphare.ddns.net/mesh      (WebSocket mesh → Caddy → Node.js :3000)
    ├──▶ https://streetphare.ddns.net/api/*   (API REST → Caddy → Node.js :3000)
    └──▶ https://streetphare.ddns.net:3001/*  (Backup → Caddy → Node.js :3001)

[Caddy — TLS termination, HSTS]
    ├── :443   → 127.0.0.1:3000  (Primary Node.js)
    ├── :3001  → 127.0.0.1:3001  (Backup Node.js)
    └── :4000  → 127.0.0.1:4000  (Dashboard admin)

[Mesh P2P hors-ligne]  BLE / Wi-Fi Direct / relay WebSocket (serveur optionnel)
```

## ✨ Fonctionnalités

| Domaine | Fonctionnalités |
|---|---|
| **Onboarding** | Splash + cache 24 h, écran d'accueil, tutoriel pas-à-pas |
| **Carte** | Carte OSM interactive, couche « safe route », marqueur de cap, tuiles hors-ligne |
| **Signalements** | 7 types de dangers, alertes avec TTL, validation par consensus (anti-spam) |
| **Panic** | Alerte PANIC individuelle & collective (agrégation par proximité), contacts d'urgence |
| **Événements** | Catalogue d'événements, scan QR d'entrée, géorepérage |
| **Messagerie** | Messagerie P2P (Hive), fils de discussion, blocage d'utilisateurs |
| **Routage** | A*/Dijkstra, graphe SPG, map matching, GraphHopper embarqué, OsmAnd, zones d'évitement |
| **Admin** | Dashboard + carte administrateur (validation des signalements) |
| **Divers** | Rapport de crash offline-first, paramètres, thème clair/sombre, accessibilité, 4 langues |

---

## 🚀 Démarrage

### Client Flutter

```bash
flutter pub get
flutter run          # ou : flutter build apk --release
```

### Serveur Node.js

```bash
cd server
cp .env.example .env          # puis renseignez MASTER_KEY, JWT_SECRET, ADMIN_HASH
npm install
npm run dev:primary           # primary sur :3000
npm run dev:backup            # backup sur :3001
```

> ⚠️ En production, le serveur **refuse de démarrer** avec les clés par défaut
> (voir `server/src/config.js`). Générez des secrets forts :
> `openssl rand -hex 32`.

### Build serveur autonome (Node SEA)

```bash
cd server
npm run build:all             # produit streetphare-primary.exe / -backup.exe
```

---

## 🔒 Sécurité & vie privée

- **Anonymat** : UUID éphémères rotatifs (`Random.secure`), aucune donnée personnelle.
- **Confidentialité** : chiffrement de bout en bout AES-256-CBC + HMAC-SHA256.
- **Intégrité** : signatures Ed25519, vérification HMAC.
- **Durée limitée** : TTL stricts par type d'alerte (1 min → 24 h), droit à l'oubli (purge Hive).
- **Kill switch** : désactivation à distance en cas de compromission.
- **Serveur** : `helmet`, `express-rate-limit`, JWT + RBAC, TLS/HSTS via Caddy.

> 📄 Voir `SECURITY.md` pour la politique de sécurité détaillée.

---

## 📦 Plateformes

| Plateforme | Statut |
|---|---|
| Android | ✅ (routage GraphHopper embarqué, P2P BLE) |
| iOS | ✅ |
| Windows / Linux / macOS | ✅ (cartographie en ligne) |
| Web | ✅ (build Flutter web) |

---

## 📜 Licence

Application open source — voir le fichier `LICENSE` (GPLv3).

> GraphHopper Core et les composants tiers sont distribués sous leurs licences respectives (Apache 2.0, ODbL pour les données OSM).

