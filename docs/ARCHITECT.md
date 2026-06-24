# StreetPhare — Architecture Technique

> **Version** : 2.2.0+1  
> **Date** : 22/06/2026  

---

## 1. Vue d'Ensemble

StreetPhare est une application mobile citoyenne décentralisée d'alerte en temps réel. Elle fonctionne sur un maillage P2P (BLE, Wi-Fi Direct, WebSocket) sans dépendance à un serveur central. Les serveurs relais Node.js sont optionnels et servent de pont entre les appareils hors de portée directe.

### Empilement Technologique

| Couche                 | Technologie                                      |
|------------------------|--------------------------------------------------|
| Application mobile     | Flutter 3.27+ / Dart 3.6+                        |
| Base de données locale | Hive CE (NoSQL embarqué)                         |
| Chiffrement            | AES-256-CBC + HMAC-SHA256, Ed25519               |
| Mesh P2P               | BLE (flutter_blue_plus), Wi-Fi Direct, WebSocket |
| Serveurs relais        | Node.js 18+ (Express + ws)                       |
| Cartographie           | OpenStreetMap (flutter_map + latlong2)           |
| CI/CD                  | GitHub Actions                                   |

---

## 2. Cycle de Vie d'une Alerte

```text
┌──────────────────────────────────────────────────────────────────┐
│                   CYCLE DE VIE D'UNE ALERTE                      │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌─────────────┐ │
│  │ ÉMISSION │──▶│CHIFFREMENT│──▶│PROPAGATION│─▶│  CONSENSUS  │ │
│  │ (Appareil│    │AES-256   │    │Mesh P2P  │    │  ≥3 votes   │ │
│  │  source) │    │+ Ed25519 │    │BLE/WiFi/ │    │ indépendants│ │
│  └──────────┘    └──────────┘    │WebSocket │    └──────┬──────┘ │
│                                  └──────────┘           │        │
│                                                         ▼        │
│                                        ┌──────────────────────┐  │
│                      ┌─────────────────│  DISTRIBUTION CARTE  │  │
│                      │                 │  + NOTIFICATION      │  │
│                      │                 └──────────────────────┘  │
│                      ▼                                           │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │              EXPIRATION TTL                              │    │
│  │  • Types mobiles (barrage/casseurs/danger): 10 min       │    │
│  │  • Types statiques (policiers/autopompes/filtre): 1 min  │    │
│  │  • Panic individuel: 2 min                               │    │
│  │  • Danger collectif: 10 min                              │    │
│  │  • Limite RGPD absolue: 24h (purge Hive)                 │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### 2.1 Émission (Étape 1)

1. Un utilisateur signale un danger via l'interface Flutter.
2. L'appareil génère un UUID éphémère unique (`generateEphemeralUserId()`).
3. Une signature Ed25519 est calculée sur les métadonnées (id + type + position + timestamp).
4. L'alerte est stockée dans Hive avec le statut `pending`.
5. Un TTL strict est assigné selon le type d'alerte (via `AlertTtlPolicy`).

### 2.2 Chiffrement (Étape 2)

1. La charge utile JSON est compressée.
2. Chiffrement AES-256-CBC avec HMAC-SHA256 (via `CryptoUtils`).
3. Format de sortie : `base64Url( IV(16) || MAC(32) || CIPHER )`.
4. Le MAC est calculé sur le ciphertext seul (compatible `server_crypto.js`).

### 2.3 Propagation Mesh P2P (Étape 3)

Le service `P2pMeshService` orchestre la diffusion simultanée sur tous les transports disponibles :

1. **BLE** (`BleTransport`) — broadcast Bluetooth Low Energy dans un rayon ~100m.
2. **Wi-Fi Direct** (`WifiDirectTransport`) — multicast LAN entre appareils connectés au même réseau.
3. **WebSocket Relay** (`RelayTransport`) — pont Internet via `server/primary:3000/mesh`.

Chaque transport implémente l'interface `MeshTransport` :

```dart
abstract class MeshTransport {
  Future<void> broadcast(String payload);
  Stream<String> get incoming;
}
```

La propagation utilise un protocole gossip avec délai aléatoire (0.5–3s) pour éviter les tempêtes de broadcast.

### 2.4 Consensus (Étape 4)

1. Chaque appareil qui reçoit l'alerte exécute `addConfirmation(euid)`.
2. Le statut passe de `pending` à `active` lorsque ≥3 confirmations distinctes sont collectées.
3. Une alerte `active` devient visible sur la carte (`AlertVisibilityPolicy`).
4. Les confirmations en double sont ignorées (déduplication par `Set<String>`).

### 2.5 Expiration TTL (Étape 5)

1. `AlertTtlPolicy.isAlertAlive()` vérifie si le TTL spécifique au type est dépassé.
2. `AlertVisibilityPolicy.isVisible()` masque les alertes expirées de la carte.
3. La limite RGPD absolue (24h) est vérifiée par `Alert.isExpired()`.
4. Les alertes expirées sont purgées de Hive via `HiveAlertDatabase.purgeExpired()`.

---

## 3. Infrastructure Serveur (Node.js)

### 3.1 Serveur Primaire (port 3000)

- **REST API** : `/v1/reports`, `/v1/events`, `/v1/alerts/sync`, `/ping`, `/healthz`
- **WebSocket Relay** : `/mesh` — rediffusion broadcast entre clients
- **Live Monitor** : `/_monitor` — flux temps réel pour le dashboard admin
- **Failover** : expose l'adresse chiffrée du serveur secondaire

### 3.2 Serveur Secondaire (port 3001)

- **Heartbeat Monitor** : scrute le primaire toutes les 5 secondes
- **Failover automatique** : prend le relais si le primaire ne répond pas
- **Récupération** : rétrograde quand le primaire revient
- **Endpoints REST** identiques au primaire (miroir)

### 3.3 Dashboard Admin (port 3500)

- Interface web interactive (`server/admin_dashboard_v2.js`)
- Métriques temps réel, carte des alertes, contrôle sandbox
- Injection de scénarios de test

### 3.4 Sandbox

- Endpoint `/sandbox` pour injection d'alertes/événements
- Simulation d'utilisateurs GPS
- Kill Switch de test
- SSE stream pour tests automatisés

---

## 4. Schéma de Données

### 4.1 Alert (Contrat JSON)

```json
{
  "id": "uuid-v4",
  "reporter_id": "euid-base64-16",
  "type": "barrage|casseurs|danger|policiers|autopompes|filtre|panic|danger_collectif|density|autre",
  "lat": 50.4762,
  "lon": 4.5422,
  "description": "Description optionnelle",
  "density_value": null,
  "timestamp": "2026-07-14T10:00:00.000Z",
  "ttl_hours": 24,
  "status": "pending|active|rejected",
  "confirmations": ["euid-1", "euid-2", "euid-3"],
  "signature": "base64-ed25519"
}
```

### 4.2 Event (Contrat QR / JSON)

```json
{
  "code": "FLEURUS-TOUR",
  "title": "Le Tour de Fleurus",
  "startAt": "2026-07-14T10:00:00.000Z",
  "visibleAt": "2026-07-14T09:00:00.000Z",
  "route": "[[lng,lat],[lng,lat],...]",
  "destLat": 50.4891,
  "destLng": 4.5452,
  "waypoints": [{"label":"...","lat":...,"lng":...,"scheduledAt":"..."}],
  "pois": [{"label":"...","lat":...,"lng":...,"icon":"..."}],
  "careCenters": [{"label":"...","lat":...,"lng":...,"contact":"...","notes":"..."}],
  "exitPoints": [{"label":"...","lat":...,"lng":...,"direction":"..."}],
  "safeZones": [{"label":"...","lat":...,"lng":...,"radius":60.0}],
  "generalZone": "Fleurus"
}
```

---

## 5. Flux Réseau

```text
Appareil A                    Appareil B                    Serveur Primaire
    │                             │                               │
    │──── BLE broadcast ────────▶│                               │
    │◀─── BLE ACK + confirm ──── │                               │
    │                             │──── WS /mesh ───────────────▶│
    │                             │                               │── relay → C, D, E
    │                             │◀──── WS /mesh ───────────────│
    │                             │                               │
    │──── Wi-Fi Direct ─────────▶│ (même réseau local)           │
    │                             │                               │
    │                             │──── POST /v1/reports ───────▶│
    │                             │                               │── Panic Collectif ?
    │                             │                               │   (5 panic < 2min < 200m)
    │                             │                               │── danger_collectif auto
    │                             │◀──── GET /v1/reports ────────│
```

---

## 6. Structure des Répertoires (code source)

```text
lib/
├── main.dart                     # Point d'entrée Flutter
├── core/                         # Fondations
│   ├── cache/                    # Cache de tuiles carto
│   ├── config/                   # Fixtures, constantes
│   ├── i18n/                     # Localisation
│   ├── network/                  # Peer counter, transport failover
│   └── theme/                    # Thème Material 3
├── database/                     # Persistance Hive
│   ├── alert_model.dart          # Modèle Alert + sérialisation
│   ├── alert_ttl_policy.dart     # TTL par type
│   ├── alert_visibility_policy.dart # Règles de visibilité
│   ├── crypto_utils.dart         # AES-256 + Ed25519
│   └── hive_alert_database.dart # DAO Hive
├── features/                     # Modules fonctionnels
│   ├── admin/                    # Sandbox de débogage
│   ├── bug_report/               # Signalement de bugs
│   ├── events/                   # Gestion événements + QR
│   ├── geofencing/               # Géorepérage
│   ├── map/                      # Carte OpenStreetMap
│   ├── messaging/                # Messagerie Hive P2P
│   ├── reports/                  # Formulaire de signalement
│   ├── routing/                  # Moteur de routage piéton
│   ├── sandbox/                  # Contrôleur sandbox
│   ├── settings/                 # Paramètres utilisateur
│   ├── splash/                   # Écran de démarrage
│   └── tutorial/                 # Tutoriel
├── l10n/                         # Fichiers ARB multilingues
├── network/                      # Couche réseau P2P
│   ├── p2p_mesh_service.dart     # Orchestrateur mesh
│   ├── network_coordinator.dart  # Coordinateur réseau
│   ├── failover_manager.dart     # Basculement serveur
│   └── transports/              # Transports concrets
│       ├── ble_transport.dart
│       ├── wifi_direct_transport.dart
│       ├── web_socket_transport.dart
│       ├── relay_transport.dart
│       └── loopback_transport.dart
└── services/                     # Services transversaux
    ├── notification_service.dart
    ├── permission_service.dart
    └── connectivity_service.dart
```

---

## 7. Workflow de Développement

```bash
# Analyse complète + tests
node scripts/orchestrate.js ci

# Démarrer les serveurs d'infrastructure
node scripts/orchestrate.js start

# Pipeline complet (CI + serveurs)
node scripts/orchestrate.js all
