# 🐝 StreetPhare — Architecture Réseau (la "Ruche")

## Vue d'ensemble

StreetPhare fonctionne comme une **ruche (Hive) décentralisée** :

```
┌──────────────┐    BLE / Wi-Fi / 4G/5G     ┌──────────────┐
│  Appareil A  │ ◀──────────────────────▶  │  Appareil B  │
│  (base Hive) │                            │  (base Hive) │
└──────┬───────┘                            └──────┬───────┘
       │                                           │
       │   consensus (3 validations anonymes)     │
       │                                           │
       ▼                                           ▼
   Internet disponible ? ──── OUI ────▶  ┌──────────────────┐
                                         │ Serveur Principal│
                                         │   (ou backup     │
                                         │    chiffré AES)  │
                                         └──────────────────┘
```

## Fichiers livrés (`lib/network/` + `lib/database/`)

| Fichier | Rôle |
|---|---|
| `database/alert_model.dart` | Modèle d'alerte (id, euid, signature, type, position, **TTL 24h**) |
| `database/hive_alert_database.dart` | Wrapper Hive (box locale, purge TTL automatique) |
| `database/crypto_utils.dart` | Signatures Ed25519 + chiffrement AES-CBC des serveurs |
| `network/p2p_mesh_service.dart` | Orchestrateur P2P (interface `MeshTransport` + gossip) |
| `network/transports/ble_transport.dart` | Transport Bluetooth Low Energy |
| `network/transports/wifi_direct_transport.dart` | Transport Wi-Fi LAN multicast |
| `network/transports/relay_transport.dart` | Transport WebSocket (3G/4G/5G) |
| `network/failover_manager.dart` | Heartbeat + basculement serveur chiffré |
| `network/network_coordinator.dart` | Coordinateur global (singleton) |
| `network/bootstrap.dart` | Construction de la config au boot |

## 1. Base de données locale éphémère (modèle "Hive")

* **Stockage** : package `hive` (NoSQL clé/valeur léger, multiplateforme).
* **TTL strict de 24h** : chaque alerte porte `createdAt` + `ttlHours: 24`.
* **Purge automatique** : la méthode `purgeExpired()` est appelée :
  * au démarrage (`init()`),
  * toutes les **5 minutes** par le `NetworkCoordinator`,
  * AVANT suppression, une dernière tentative d'upload est faite
    via le `FailoverManager` (`onBeforeDelete` callback).

```dart
await HiveAlertDatabase.instance.init();   // au boot
await HiveAlertDatabase.instance.upsert(alert);
```

## 2. Propagation P2P et maillage (Mesh Networking)

Toutes les bandes disponibles sont utilisées **simultanément** :

| Bande | Transport | Cas d'usage |
|---|---|---|
| BLE (`flutter_reactive_ble`) | `BleMeshTransport` | < 50 m, sans internet |
| Wi-Fi Direct / LAN multicast | `WifiDirectMeshTransport` | < 200 m, même réseau |
| 3G/4G/5G / WebSocket | `RelayMeshTransport` | Couverture Internet, longue distance |

**Gossip protocol** : toutes les 30 s, chaque appareil broadcast la
liste de ses IDs d'alertes. Les pairs qui détectent un ID manquant
demandent le payload complet (flooding contrôlé avec TTL réseau).

**Re-broadcast** : à chaque réception, l'alerte est rediffusée
avec un délai aléatoire (anti-storm).

## 3. Consensus des 3 validations

* Chaque alerte embarque un set `confirmations: Set<String>`.
* À la création, l'utilisateur local compte comme confirmation #1.
* À chaque réception via P2P, **chaque pair ajoute son identifiant
  éphémère** (`generateEphemeralUserId()`) dans le set.
* Quand `confirmations.length >= 3` → statut = `validated`.
* Une alerte validée est immédiatement candidate à l'upload.

```dart
await NetworkCoordinator.instance.confirmAlert(alertId);
```

## 4. Résilience du serveur central et rotation chiffrée

* **Serveur Principal** : `primaryAddress` (constante dans l'app).
* **Chaîne de secours** : `List<String> encryptedBackupChain`,
  stockée chiffrée AES-256-CBC. Chaque entrée contient
  `IV ‖ ciphertext`.
* **Heartbeat** : `Timer.periodic(30s)` → ping `/healthz`.
* **Défaillance** : après `maxAttempts: 3` échecs consécutifs, le
  serveur est ajouté à `_deadForSession` (jamais retenté).
* **Basculement** : la 1re entrée de la chaîne est déchiffrée
  puis devient le nouveau Principal.
* **Rotation auto-entretenue** : après un upload réussi, le
  serveur peut renvoyer un `next_backup` chiffré dans sa réponse,
  automatiquement enfilé en queue de chaîne.

```dart
await FailoverManager.instance.heartbeat();  // manuel ou auto
```

## Démarrage

```bash
flutter pub get
flutter run \
  --dart-define=STREETPHARE_PRIMARY=https://api.streetphare.org \
  --dart-define=STREETPHARE_RELAY=wss://relay.streetphare.org/mesh \
  --dart-define=STREETPHARE_MASTER_KEY=<clé maître signée par CI>
```

## Utilisation depuis une feature

```dart
import 'package:flutter_streetphare/network/network_coordinator.dart';

// Créer une alerte (signature + stockage + broadcast automatique)
final alert = await NetworkCoordinator.instance.createAlert(
  type: AlertType.barrage,
  latitude: 50.8503,
  longitude: 4.3517,
  description: 'Barrage policier av. Louise',
);

// Écouter le flux
NetworkCoordinator.instance.alertsStream.listen((alerts) {
  print('${alerts.length} alertes actives');
});

// Confirmer manuellement (compte pour le consensus)
await NetworkCoordinator.instance.confirmAlert(alertId);
```

## Permissions à ajouter (déjà documenté dans `INSTALLATION_DEPENDANCES.md`)

### Android (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>StreetPhare a besoin de votre position pour vous localiser sur la carte.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>StreetPhare utilise votre position pour signaler et recevoir des alertes en temps réel.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>StreetPhare utilise le Bluetooth pour échanger des alertes avec les appareils à proximité sans internet.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>StreetPhare utilise le réseau local pour échanger des alertes via Wi-Fi.</string>
<key>NSBonjourServices</key>
<array>
  <string>_streetphare._tcp</string>
  <string>_streetphare._udp</string>
</array>
```

## Notes de sécurité

* Les **clés privées Ed25519 ne sont jamais persistées** : chaque
  signature est one-shot, garantissant l'anonymat.
* Les **adresses de secours sont chiffrées au build** par la CI
  (master key injectée via `--dart-define`).
* La **clé maître ne doit PAS être embarquée** en prod : à terme,
  elle doit provenir d'un secure storage natif (Keychain iOS /
  Keystore Android) ou être dérivée d'un serveur de clés.
* Les **données locales sont systématiquement purgées à 24h**, ce
  qui limite la surface d'analyse en cas de saisie de l'appareil.
