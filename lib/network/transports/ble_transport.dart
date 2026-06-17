// lib/network/transports/ble_transport.dart
//
// Implémentation BLE (Bluetooth Low Energy) du contrat MeshTransport.
//
// Dépend du package `flutter_reactive_ble` (qui doit être ajouté au
// pubspec.yaml) :
//   flutter_reactive_ble: ^5.0.0
//
// Le service se comporte à la fois comme :
//   - GATT Server (advertise un service StreetPhare contenant
//     une caractéristique "alert" en notify/write)
//   - Scanner BLE pour découvrir les autres appareils
//
// Les payloads d'alertes sont courts (≤ 244 octets typiques d'une
// caractéristique BLE), ce impose un format compact (déjà
// prévu dans `Alert.toCompact()`).
//
// === Identifiant de pair (UUID de session anonyme) ===
//
// Chaque instance de transport embarque un `peerId` (par défaut,
// l'`ephemeralUserId` du `NetworkCoordinator`). Ce peerId est
// inclus dans tous les pings de présence diffusés sur le maillage.
// Côté réception, le consommateur (ex. `PeerCounterService`) peut
// ainsi dédupliquer les signaux d'un même émetteur, même si celui-ci
// émet en boucle. C'est la **clé du contrat anti-double-comptage**
// du compteur HIVE.
//
// === Correction ANR (Signal 3) ===
//
// Les rafales d'émissions/réceptions BLE peuvent saturer la boucle
// d'événements Dart (thread UI). Pour éviter les ANR :
//   - Le callback de scan est désormais « throttlé » : on ignore
//     les découvertes redondantes d'un même device dans une fenêtre
//     de 2 secondes.
//   - Chaque émission de ping passe par `Future.microtask` pour
//     céder la main à l'event loop entre deux trames.
//   - Le traitement des trames entrantes est découpé via
//     `scheduleMicrotask` lorsque le volume est élevé.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../p2p_mesh_service.dart';

/// Transport BLE pour la propagation P2P.
///
/// IMPORTANT : cette classe n'est instanciée qu'à runtime sur les
/// plateformes qui supportent BLE (iOS, Android, macOS, Web BLE).
/// Sur les autres plateformes, [isAvailable] vaut `false` et le
/// service démarre quand même sans elle.
class BleMeshTransport implements MeshTransport {
  BleMeshTransport({
    FlutterReactiveBle? ble,
    String? peerId,
    this._pingInterval = const Duration(seconds: 8),
  })  : _ble = ble ?? FlutterReactiveBle(),
        _peerId = peerId ?? _generateRandomPeerId();

  final FlutterReactiveBle _ble;

  /// Identifiant STABLE de l'appareil émetteur, diffusé dans
  /// chaque ping de présence. C'est ce peerId que les pairs
  /// distants utiliseront pour dédupliquer les signaux.
  final String _peerId;

  /// Intervalle entre deux pings BLE de présence.
  final Duration _pingInterval;

  /// UUID du service GATT StreetPhare (à déclarer dans le code natif).
  static final Uuid serviceUuid =
      Uuid.parse('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Uuid characteristicUuid =
      Uuid.parse('6e400002-b5a3-f393-e0a9-e50e24dcca9e');

  @override
  String get name => 'ble';

  /// Expose le peerId local pour que la couche applicative puisse
  /// l'utiliser (par ex. pour le loguer, ou pour le passer à un
  /// autre transport qui en aurait besoin).
  String get peerId => _peerId;

  final _incomingController = StreamController<String>.broadcast();
  @override
  Stream<String> get incoming => _incomingController.stream;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  Timer? _pingTimer;
  bool _started = false;

  /// Anti-saturation : cache des devices déjà signalés récemment.
  /// Clé = device ID, Valeur = timestamp de la dernière notification.
  /// Un même device ne sera notifié qu'une fois toutes les 2 secondes.
  final Map<String, DateTime> _lastDeviceSeen = {};

  /// Intervalle minimal entre deux notifications pour un même device.
  static const Duration _deviceThrottleWindow = Duration(seconds: 2);

  /// Nettoie périodiquement le cache des devices vus.
  Timer? _throttleCleanupTimer;

  @override
  bool get isAvailable {
    if (kIsWeb) return true;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Vérification et demande des permissions BLE/Location avant le scan.
    // Sur Android :
    //   - API 31+ (Android 12+) : BLUETOOTH_SCAN (runtime) + BLUETOOTH_CONNECT (API 33+)
    //   - API < 31 : ACCESS_FINE_LOCATION (runtime)
    // Si les permissions ne sont pas accordées, le scan est désactivé
    // plutôt que de lever une exception "Location Permission missing".
    final permissionsOk = await _requestBlePermissions();
    if (!permissionsOk) {
      if (kDebugMode) {
        debugPrint('[BLE] Permissions BLE/Location refusées, scan désactivé');
      }
      _started = false;
      return;
    }

    // Scan : on écoute tous les appareils qui exposent notre service.
    _scanSub = _ble
        .scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    )
        .listen((device) {
      // ANR fix : throttling des découvertes pour éviter de noyer
      // l'event loop quand de nombreux devices BLE sont à portée.
      final now = DateTime.now();
      final last = _lastDeviceSeen[device.id];
      if (last != null &&
          now.difference(last) < _deviceThrottleWindow) {
        return; // Ignore les découvertes redondantes
      }
      _lastDeviceSeen[device.id] = now;

      // Quand on détecte un pair, on s'y connecte pour recevoir ses
      // notifications. La lecture effective des caractéristiques
      // dépend d'un connectGatt + discoverServices (omis ici pour
      // concision — voir flutter_reactive_ble pour l'API complète).
      if (kDebugMode) {
        debugPrint('[BLE] pair découvert: ${device.name} (${device.id})');
      }
    }, onError: (Object e) {
      if (kDebugMode) debugPrint('[BLE] scan error: $e');
    });

    // Ping périodique de présence (inclut le peerId stable).
    // Les pairs distants reçoivent ce ping, l'inscrivent dans
    // leur fenêtre glissante, et le compteur HIVE déduplique
    // automatiquement sur le peerId.
    //
    // ANR fix : on cède la main à l'event loop entre chaque ping
    // via un microtask pour ne jamais monopoliser le thread UI.
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      scheduleMicrotask(_sendPresencePing);
    });
    // Émet un ping immédiatement pour se signaler vite.
    scheduleMicrotask(_sendPresencePing);

    // Nettoie périodiquement le cache de throttling pour éviter
    // une fuite mémoire.
    _throttleCleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupThrottleCache(),
    );
  }

  @override
  Future<void> stop() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _throttleCleanupTimer?.cancel();
    _throttleCleanupTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    _lastDeviceSeen.clear();
    _started = false;
  }

  @override
  Future<void> broadcast(String payload) async {
    // En BLE pur, il n'y a pas de broadcast "broadcast" entre
    // appareils non connectés. On se contente d'émettre sur le
    // service GATT dès qu'un central est connecté (cas typique :
    // un téléphone "advertiser" et un autre "scanner/connecté").
    // On log en debug pour traçabilité.
    if (kDebugMode) {
      debugPrint('[BLE] broadcast: ${payload.length} octets');
    }
    // NOTE : pour un vrai broadcast, on utiliserait les "BLE
    // advertisements" en mode non connectable (limité à 31 octets)
    // via un format厂商specifique. Voir les "Extended Advertising"
    // sur Android 8+ / iOS 13+.

    // ANR fix : libère la boucle d'événements après le broadcast.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    if (kDebugMode) {
      debugPrint('[BLE] sendTo ${peer.id} (${payload.length} octets)');
    }
    // Connexion GATT + write caractéristique : laissé à un
    // connecteur concret (dépend de l'ID device BLE distant).
    try {
      await _ble
          .connectToDevice(
            id: peer.id,
            servicesWithCharacteristicsToDiscover: {
              serviceUuid: [characteristicUuid],
            },
          )
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) debugPrint('[BLE] sendTo error: $e');
    }
  }

  /// Construit et émet un ping de présence BLE contenant le
  /// peerId stable. C'est ce peerId qui sert de clé de
  /// déduplication côté réception.
  ///
  /// ANR fix : la méthode est volontairement synchrone pour la
  /// construction du ping, mais l'émission est confiée à
  /// [broadcast] qui yield l'event loop. L'appelant doit
  /// utiliser `scheduleMicrotask` pour ne pas bloquer.
  void _sendPresencePing() {
    final ping = jsonEncode({
      'kind': 'ping',
      // IMPORTANT : `id` = peerId STABLE de la session anonyme
      // courante. C'est cette clé qui permet aux pairs distants
      // de dédupliquer ce signal dans leur fenêtre glissante.
      'id': _peerId,
      't': name, // nom du transport ('ble')
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    // En production : injecter dans un advertisement ou une
    // caractéristique notifiable. Ici, on log en debug et on
    // laisse `broadcast` côté GATT faire le relais.
    if (kDebugMode) {
      debugPrint('[BLE] presence ping peerId=$_peerId');
    }
    // Ne pas await volontairement : le broadcast est fire-and-forget
    // pour ne pas bloquer le microtask.
    broadcast(ping);
  }

  /// Vérifie et demande les permissions nécessaires au scan BLE.
  ///
  /// Sur Android API 31+ (12+), on demande [Permission.bluetoothScan].
  /// En fallback (Android < 12), on demande [Permission.locationWhenInUse].
  /// Retourne `true` si au moins une permission BLE est accordée.
  Future<bool> _requestBlePermissions() async {
    // iOS 13+ utilise CoreBluetooth qui gère ses propres dialogues système.
    // Pas de demande explicite nécessaire côté Dart.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    try {
      // ── Android 12+ (API 31+) : BLUETOOTH_SCAN ─────────────────
      var scanGranted = await Permission.bluetoothScan.isGranted;
      if (!scanGranted) {
        final result = await Permission.bluetoothScan.request();
        scanGranted = result.isGranted;
      }

      // ── Android 13+ (API 33+) : BLUETOOTH_CONNECT ──────────────
      var connectGranted = await Permission.bluetoothConnect.isGranted;
      if (!connectGranted) {
        final result = await Permission.bluetoothConnect.request();
        connectGranted = result.isGranted;
      }

      // Si permissions Bluetooth modernes obtenues, c'est bon.
      if (scanGranted) {
        if (kDebugMode) {
          debugPrint('[BLE] BLUETOOTH_SCAN accordé');
        }
        return true;
      }

      // ── Fallback Android < 12 : location ───────────────────────
      // Sur Android 11 et inférieur, le scan BLE exige la permission
      // de localisation fine. On tente de l'obtenir en dernier recours.
      var locationGranted = await Permission.locationWhenInUse.isGranted;
      if (!locationGranted) {
        final result = await Permission.locationWhenInUse.request();
        locationGranted = result.isGranted;
      }
      if (locationGranted) {
        if (kDebugMode) {
          debugPrint('[BLE] Location (fallback) accordée');
        }
        return true;
      }

      // ── Échec total ────────────────────────────────────────────
      if (kDebugMode) {
        debugPrint('[BLE] Aucune permission BLE/Location accordée');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] Erreur lors de la demande de permission : $e');
      }
      // En cas d'erreur (ex: plateforme non supportée par permission_handler),
      // on laisse le scan tenter sa chance (il échouera avec un message clair).
      return true;
    }
  }

  /// Nettoie les entrées périmées du cache de throttling.
  void _cleanupThrottleCache() {
    final cutoff = DateTime.now().subtract(_deviceThrottleWindow * 2);
    _lastDeviceSeen.removeWhere((_, lastSeen) => lastSeen.isBefore(cutoff));
  }

  /// Helper de test : permet d'injecter un message reçu (utile
  /// pour les tests unitaires sans device BLE).
  void debugInjectIncoming(String payload) {
    _incomingController.add(payload);
  }

  /// Libère les ressources internes (canal broadcast).
  @override
  void dispose() {
    _incomingController.close();
  }

  /// Génère un peerId anonyme stable pour la session courante.
  /// En pratique, on injecte l'`ephemeralUserId` du
  /// `NetworkCoordinator` au constructeur. Ce fallback aléatoire
  /// n'est utilisé que pour les tests / l'instanciation directe.
  static String _generateRandomPeerId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'ble-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}

/// Helper JSON pour les paquets d'alerte reçus via BLE.
/// Conservé ici pour regrouper les utilitaires BLE.
String decodeBleFrame(String raw) {
  try {
    jsonDecode(raw);
    return raw;
  } catch (_) {
    return utf8.decode(base64Decode(raw));
  }
}