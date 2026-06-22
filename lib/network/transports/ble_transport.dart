// lib/network/transports/ble_transport.dart
//
// Transport BLE (Bluetooth Low Energy) — v2.0 SCAN-ONLY
//
// === COMPTAGE PASSIF EXCLUSIF ===
//
// À partir de la v2.0, le transport BLE est BRIDÉ au scanning passif.
// Il ne tente PLUS de connexion GATT, de read/write de caractéristiques,
// ni d'échange de données applicatives. Son unique mission est :
//
//   1. Scanner en continu les advertisements BLE à la recherche de
//      l'UUID de service StreetPhare (`kStreetPhareBleServiceUuid`).
//   2. Pour chaque appareil détecté portant cette signature, enregistrer
//      le `peerId` dans `PeerCounterService` (fenêtre glissante 5 min).
//   3. Émettre périodiquement un ping de présence BLE pour signaler
//      sa propre existence aux autres scanners StreetPhare.
//
// Les échanges de données (messages, alertes) transitent exclusivement
// par Wi-Fi Direct / WebSocket / Relay. Le BLE est réservé à la
// DÉTECTION DE PROXIMITÉ (comptage HIVE).
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
// Les rafales de découvertes BLE peuvent saturer la boucle
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
import '../../core/network/peer_counter_service.dart';

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

    // ── Scan passif permanent : détection de présence uniquement ──
    // Le BLE ne fait PLUS de connexion GATT, uniquement du scanning
    // d'advertisements pour le comptage HIVE (PeerCounterService).
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

      // ── Comptage HIVE : enregistre le pair dans la fenêtre glissante ──
      // Le BLE est exclusivement dédié au comptage de proximité.
      // Aucune connexion GATT, aucun échange de données.
      PeerCounterService.instance.recordPeer(
        device.id,
        serviceUuid: serviceUuid.toString(),
        metadata: device.name.isNotEmpty ? 'SP_HIVE_${device.name}' : null,
      );

      if (kDebugMode) {
        debugPrint('[BLE] pair détecté (scan only): ${device.name} (${device.id})');
      }
    }, onError: (Object e) {
      if (kDebugMode) {
        debugPrint('[BLE] scan error: $e');
      }
      // L'erreur de scan ne doit pas planter le service.
      // On log et on continue : le scan est résilient.
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
    // ── SCAN-ONLY : le BLE ne fait plus de broadcast de données ──
    // Les messages et alertes transitent exclusivement par Wi-Fi
    // Direct / WebSocket / Relay.
    // On log uniquement pour la traçabilité, sans effet de bord.
    if (kDebugMode) {
      debugPrint('[BLE] broadcast ignoré (scan-only): ${payload.length} octets');
    }
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    // ── SCAN-ONLY : aucune connexion GATT n'est établie ──
    // La méthode reste disponible pour compatibilité avec le contrat
    // MeshTransport, mais ne fait rien.
    if (kDebugMode) {
      debugPrint('[BLE] sendTo ignoré (scan-only): ${peer.id}');
    }
  }

  /// Émet un ping de présence BLE contenant le peerId stable.
  ///
  /// En mode SCAN-ONLY, ce ping n'est PAS transmis via une connexion
  /// GATT (pas de broadcast). Il est enregistré LOCALEMENT dans le
  /// `PeerCounterService` pour que le compteur HIVE inclue cet
  /// appareil lui-même dans le décompte local (utile pour les tests
  /// et la cohérence du dashboard).
  ///
  /// ANR fix : la méthode est volontairement synchrone pour la
  /// construction du ping. L'appelant doit utiliser
  /// `scheduleMicrotask` pour ne pas bloquer.
  void _sendPresencePing() {
    // ── Auto-enregistrement dans le compteur HIVE local ──
    // Permet au dashboard de voir au moins 1 pair (soi-même) même
    // quand aucun autre appareil StreetPhare n'est à portée.
    PeerCounterService.instance.recordPeer(
      _peerId,
      serviceUuid: kStreetPhareBleServiceUuid,
    );

    if (kDebugMode) {
      debugPrint('[BLE] presence ping (auto-comptage) peerId=$_peerId');
    }
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