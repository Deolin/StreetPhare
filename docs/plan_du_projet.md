# StreetPhare — Plan du Projet

> **Version** : 2.2.0+1  
> **Licence** : GPLv3  
> **Date du document** : 22/06/2026  

---

## 1. Vision et Objectifs

StreetPhare est une **application mobile citoyenne décentralisée** d'alerte en temps réel. Elle permet aux usagers de la route (piétons, cyclistes, conducteurs) de signaler et recevoir des alertes de dangers (contrôles policiers, barricades, accidents, attroupements, pièges, etc.) **sans dépendre d'un serveur central**.

### Principes Fondateurs

- **Décentralisation totale** — Aucun serveur central obligatoire. Les données transitent en P2P.
- **Anonymat** — UUIDs éphémères, rotation régulière, aucune collecte de données personnelles.
- **RGPD by design** — Données exclusivement sur l'appareil, TTL strict, chiffrement de bout en bout.
- **Résilience** — Fonctionne même sans Internet (BLE, Wi-Fi Direct). Les serveurs relais sont optionnels.
- **Open Source** — GPLv3, données cartographiques OpenStreetMap via OsmAnd BV.

---

## 2. Architecture Générale

```text
┌──────────────────────────────────────────────────────────────────┐
│                     APPLICATION FLUTTER (Dart)                   │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Features │  │  Core    │  │ Services │  │ Database (Hive)  │  │
│  │          │  │          │  │          │  │                  │  │
│  │ • Events │  │ • Theme  │  │ • Audio  │  │ • AlertModel     │  │
│  │ • Map    │  │ • i18n   │  │ • Haptic │  │ • CryptoUtils    │  │
│  │ • Admin  │  │ • Router │  │ • Geo    │  │ • TTL Policy     │  │
│  │ • Alerts │  │ • Auth   │  │ • BLE    │  │ • Visibility     │  │
│  │ • BugRpt │  │ • DI     │  │ • WiFi   │  │                  │  │
│  │ • GeoFen │  │ • Config │  │ • Mesh   │  └──────────────────┘  │
│  │ • Panic  │  │ • Utils  │  │ • Notif  │                        │
│  └──────────┘  └──────────┘  └──────────┘   ┌──────────────────┐ │
│                                             │ Network          │ │
│  ┌──────────────────────────┐               │ • P2P Manager    │ │
│  │        main.dart         │               │ • WS Client      │ │
│  │   MaterialApp + i18n     │               │ • Relay Client   │ │
│  └──────────────────────────┘               └──────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────┐   ┌──────────────────┐   ┌──────────────────┐
│  BLE Mesh   │   │  Wi-Fi Direct    │   │  WebSocket Relay │
│  (Proximité)│   │  (Local)         │   │  (Internet)      │
└─────────────┘   └──────────────────┘   └──────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌─────────────────────┐   ┌──────────────────────┐
│ Test Server Primary │   │ Test Server Secondary│
│ (Node.js :3000)     │◄──┤ (Node.js :3001)      │
│ • API REST          │   │ • Heartbeat Monitor  │
│ • WS Mesh Relay     │   │ • Failover Auto      │
│ • Admin Dashboard   │   │ • Replication        │
│ • Live Monitor      │   │ • Recovery           │
└─────────────────────┘   └──────────────────────┘
         │
         ▼
┌───────────────────────────────────────────────────┐
│              Server Dart (optionnel)              │
│  • bin/server.dart — HTTP + WebSocket             │
│  • Admin Dashboard Web                            │
│  • Gestionnaire d'événements                      │
│  • Générateur QR Codes                            │
│  • Proxy de tuiles cartographiques                │
│  • Authentification                               │
└───────────────────────────────────────────────────┘
```

---

## 3. Structure des Répertoires

```text
StreetPhare/
├── lib/                          # Code source Flutter/Dart
│   ├── main.dart                 # Point d'entrée, MaterialApp, i18n
│   ├── core/                     # Fondations (theme, i18n, router, auth, DI, config, utils)
│   ├── features/                 # Modules fonctionnels
│   │   ├── admin/                # Dashboard administrateur (sandbox, métriques)
│   │   ├── alerts/               # Signalement et visualisation d'alertes
│   │   ├── bug_report/           # Signalement de bugs (FAB + service)
│   │   ├── events/               # Gestion d'événements (création, QR, rejoindre)
│   │   ├── geofencing/           # Géorepérage et zones de notification
│   │   ├── maps/                 # Carte interactive (OpenStreetMap)
│   │   ├── panic/                # Alerte panique collective
│   │   ├── settings/             # Paramètres utilisateur
│   │   └── splash/               # Écran de démarrage
│   ├── services/                 # Services transversaux
│   │   ├── audio_service.dart    # Synthèse vocale et alertes sonores
│   │   ├── ble_service.dart      # Bluetooth Low Energy mesh
│   │   ├── geolocation_service.dart  # GPS et localisation
│   │   ├── haptic_service.dart   # Retour haptique
│   │   ├── language_service.dart # Gestion multilingue
│   │   ├── log_service.dart      # Journalisation
│   │   ├── mesh_service.dart     # Maillage P2P
│   │   ├── notification_service.dart # Notifications push locales
│   │   ├── permissions_service.dart  # Permissions Android/iOS
│   │   └── wifi_service.dart     # Wi-Fi Direct
│   ├── network/                  # Couche réseau
│   │   ├── p2p_alert_manager.dart
│   │   ├── relay_client.dart
│   │   └── websocket_client.dart
│   ├── database/                 # Persistance locale (Hive)
│   │   ├── alert_model.dart
│   │   ├── alert_ttl_policy.dart
│   │   ├── alert_visibility_policy.dart
│   │   ├── crypto_utils.dart
│   │   └── hive_alert_database.dart
│   ├── l10n/                     # Fichiers de localisation ARB
│   └── debug/                    # Outils de débogage
├── server/                       # Serveur Dart autonome
│   ├── bin/server.dart           # Point d'entrée serveur
│   └── lib/
│       ├── api/admin_handlers.dart
│       ├── core/auth_manager.dart
│       ├── core/command_router.dart
│       ├── event_manager.dart
│       ├── map/tile_proxy_service.dart
│       ├── models/alert.dart
│       ├── models/event.dart
│       └── web/admin_dashboard.dart
├── test_servers/                 # Serveurs de test Node.js
│   ├── server_primary_v2.js      # Primaire (port 3000)
│   ├── server_secondary_v2.js    # Secondaire (port 3001, failover)
│   ├── server_crypto.js          # Chiffrement AES-256 + HMAC
│   ├── sandbox.js                # Bac à sable développement
│   ├── admin_dashboard_v2.js     # Dashboard admin web
│   ├── start_servers_v2.js       # Lancement orchestré
│   ├── launch_all.js             # Lancement complet
│   └── modules/                  # Modules Node.js additionnels
├── test/                         # Tests Flutter
│   └── streetphare_core_test.dart
├── assets/                       # Ressources statiques
│   └── icon/                     # Icônes de l'application
├── web/                          # Build Flutter web (PWA)
├── web_vitrine/                  # Site vitrine marketing
├── windows/                      # Build Windows
├── linux/                        # Build Linux
├── macos/                        # Build macOS
├── ios/                          # Build iOS
├── android/                      # Build Android
├── scripts/                      # Scripts utilitaires
├── docs/                         # Documentation
├── status/                       # Fichiers d'état/rapports
├── pubspec.yaml                  # Configuration Dart/Flutter
├── pubspec.lock                  # Verrouillage dépendances
├── package.json                  # Configuration Node.js (test_servers)
├── analysis_options.yaml         # Règles d'analyse statique Dart
├── flutter_launcher_icons.yaml   # Configuration icônes de lancement
└── devtools_options.yaml         # Configuration DevTools
```

---

## 4. Modules Fonctionnels (Features)

### 4.1 Alerts (`features/alerts/`)

- **Signalement** : Formulaire de création d'alerte (type, position, description, photo)
- **Visualisation** : Liste et carte des alertes actives à proximité
- **Validation par consensus** : ≥3 confirmations indépendantes requises avant publication
- **TTL** : Expiration automatique par type (contrôle: 30min, accident: 60min, etc.)
- **Domain** : Modèle Alert, AlertType enum, état (pending/active/rejected/expired)

### 4.2 Events (`features/events/`)

- **Création** : Événements avec waypoints, POIs, centres de soins, points de sortie, zones sûres
- **Partage** : QR codes pour rejoindre un événement
- **Gestion** : Multi-événements (max 3 simultanés), rejoindre/quitter/supprimer
- **Fixtures** : Données Fleurus avec coordonnées GPS réelles
- **Itinéraire adaptatif** : Recalcul selon positions en temps réel

### 4.3 Maps (`features/maps/`)

- Carte interactive OpenStreetMap (flutter_map + latlong2)
- Marqueurs d'alertes et d'événements
- Géolocalisation en temps réel
- Filtres visuels par type d'alerte

### 4.4 Admin (`features/admin/`)

- Dashboard administrateur avec métriques
- Contrôles sandbox (injection d'alertes, simulation GPS)
- Carte admin avec marqueurs

### 4.5 Panic (`features/panic/`)

- Alerte panique collective
- Déclenchement discret (bouton volume, geste, ou UI)
- Propagation mesh prioritaire

### 4.6 Geofencing (`features/geofencing/`)

- Zones de notification géographiques
- Proximité events (entrée/sortie de zone)
- Alertes contextuelles selon position

### 4.7 Bug Report (`features/bug_report/`)

- FAB discret pour signalement de bugs
- Service d'envoi au serveur admin
- Capture de contexte (position, logs, état)

### 4.8 Settings (`features/settings/`)

- Préférences utilisateur
- Configuration des alertes
- Gestion de la confidentialité

### 4.9 Splash (`features/splash/`)

- Écran de démarrage animé
- Vérification permissions
- Initialisation services

---

## 5. Couche Services

| Service                | Rôle                                   | État          |
|------------------------|----------------------------------------|---------------|
| `audio_service`        | Synthèse vocale, alertes sonores       | ✅ Implémenté |
| `ble_service`          | Bluetooth Low Energy mesh              | ✅ Implémenté |
| `geolocation_service`  | GPS, localisation continue             | ✅ Implémenté |
| `haptic_service`       | Retour haptique (vibrations)           | ✅ Implémenté |
| `language_service`     | Gestion multilingue (AR/EN/NL/DE)      | ✅ Implémenté |
| `log_service`          | Journalisation centralisée             | ✅ Implémenté |
| `mesh_service`         | Maillage P2P (BLE + Wi-Fi Direct + WS) | ✅ Implémenté |
| `notification_service` | Notifications push locales             | ✅ Implémenté |
| `permissions_service`  | Permissions Android/iOS                | ✅ Implémenté |
| `wifi_service`         | Wi-Fi Direct P2P                       | ✅ Implémenté |

---

## 6. Couche Réseau

| Composant           | Rôle                                                            |
|---------------------|-----------------------------------------------------------------|
| `p2p_alert_manager` | Gestion des alertes en P2P (broadcast, réception, validation)   |
| `relay_client`      | Client de relais WebSocket vers serveurs optionnels             |
| `websocket_client`  | Client WebSocket bas niveau (connexion, reconnexion, heartbeat) |

---

## 7. Base de Données (Hive)

| Fichier                        | Rôle                                          |
|--------------------------------|-----------------------------------------------|
| `alert_model.dart`             | Modèle de persistance Alert (Hive TypeAdapter)|
| `alert_ttl_policy.dart`        | Politique de durée de vie par type d'alerte   |
| `alert_visibility_policy.dart` | Politique de visibilité (distance, consensus) |
| `crypto_utils.dart`            | Chiffrement AES-256-CBC + HMAC-SHA256         |
| `hive_alert_database.dart`     | DAO Hive pour les alertes                     |

---

## 8. Core

| Composant  | Rôle                                       |
|------------|--------------------------------------------|
| `theme/`   | Thème Material 3 (clair/sombre)            |
| `i18n/`    | Internationalisation (ARB → .dart)         |
| `router/`  | Routage GoRouter                           |
| `auth/`    | Gestion d'identité éphémère (UUID rotatif) |
| `di/`      | Injection de dépendances                   |
| `config/`  | Configuration compile-time                 |
| `utils/`   | Utilitaires transversaux                   |

---

## 9. Infrastructure Serveur

### 9.1 Serveur Dart (`server/`)

- **HTTP** : API REST pour alertes, événements, admin
- **WebSocket** : Relais mesh entre clients
- **Admin Dashboard** : Interface web d'administration
- **Event Manager** : Gestion des événements côté serveur
- **QR Generator** : Génération de QR codes
- **Tile Proxy** : Proxy de tuiles OpenStreetMap
- **Auth Manager** : Authentification admin

### 9.2 Serveurs de Test Node.js (`test_servers/`)

- **Primary (port 3000)** : API REST, WebSocket mesh relay, LiveMonitor
- **Secondary (port 3001)** : Backup avec HeartbeatMonitor, failover automatique
- **Crypto** : Chiffrement compatible Dart (AES-256-CBC + HMAC-SHA256)
- **Sandbox** : Injection alertes/événements, simulation GPS, Kill Switch, SSE stream
- **Admin Dashboard** : Dashboard web interactif
- **Orchestrator** : Lancement coordonné des serveurs

---

## 10. Plateformes Cibles

| Plateforme | État               |
|------------|--------------------|
| Android    | ✅ Build configuré |
| iOS        | ✅ Build configuré |
| Web (PWA)  | ✅ Build configuré |
| Windows    | ✅ Build configuré |
| Linux      | ✅ Build configuré |
| macOS      | ✅ Build configuré |

---

## 11. Internationalisation (i18n)

Langues supportées : **Français** (par défaut), **Anglais**, **Néerlandais**, **Allemand**.

Fichiers ARB dans `lib/l10n/`. Site vitrine multilingue.

---

## 12. Sécurité

- **Chiffrement de bout en bout** : AES-256-CBC + HMAC-SHA256
- **Anonymat** : UUIDs éphémères avec rotation
- **Consensus** : ≥3 confirmations avant publication d'alerte
- **TTL strict** : Expiration automatique des données
- **Aucune collecte** : Zéro données personnelles, zéro télémétrie
- **Kill Switch** : Désactivation à distance si compromission

---

## 13. Tests

- **Tests unitaires** : `test/streetphare_core_test.dart` (couverture basique)
- **Serveurs de test** : Environnement isolé avec scénarios simulés
- **Sandbox** : Interface développeur pour tests manuels et automatisés
- **Scripts** : `scripts/test_unit.sh`, `scripts/test_integration.sh`, `scripts/test_orchestrator.ps1`

---

## 14. Dépendances Majeures

### Flutter/Dart (pubspec.yaml)

- `flutter_map` + `latlong2` : Cartographie OpenStreetMap
- `geolocator` : Géolocalisation
- `hive` + `hive_flutter` : Base de données locale
- `flutter_blue_plus` : Bluetooth Low Energy
- `wifi_direct` : Wi-Fi Direct
- `web_socket_channel` : WebSocket
- `qr_flutter` + `mobile_scanner` : QR codes
- `go_router` : Routage
- `flutter_local_notifications` : Notifications
- `vibration` : Retour haptique
- `path_provider` : Chemins système

### Node.js (test_servers/package.json)

- `express` : Serveur HTTP
- `ws` : WebSocket
- `node-fetch` : Requêtes HTTP
- `crypto` : Chiffrement

---

## 15. Workflow de Développement

1. **Analyse statique** : `dart analyze`
2. **Génération de code** : `dart run build_runner build` (Hive TypeAdapters, i18n)
3. **Tests unitaires** : `flutter test`
4. **Tests d'intégration** : Serveurs Node.js + app Flutter
5. **Lancement** : `flutter run` par plateforme
6. **Build** : `flutter build apk/ios/web/linux/windows/macos`
