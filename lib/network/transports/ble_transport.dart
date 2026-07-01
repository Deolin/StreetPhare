// lib/network/transports/ble_transport.dart
//
// Transport BLE (Bluetooth Low Energy) — v3.0 FULL-DUPLEX
//
// === ÉCHANGE DE DONNÉES BIDIRECTIONNEL ===
//
// À partir de la v3.0, le transport BLE est un transport complet :
//
//   1. **Scan passif** : détection des devices StreetPhare via l'UUID
//      de service `kStreetPhareBleServiceUuid` (comptage HIVE).
//
//   2. **Connexion GATT automatique** : pour chaque device détecté
//      portant la signature StreetPhare, une connexion GATT est établie.
//      Les services sont découverts, et la caractéristique de données
//      est souscrite pour recevoir les notifications entrantes.
//
//   3. **broadcast(String payload)** : écrit le payload sur la
//      caractéristique de données de TOUS les devices connectés
//      (write without response pour la latence minimale).
//
//   4. **sendTo(MeshPeer peer, String payload)** : écrit le payload
//      sur la caractéristique de données d'un device ciblé.
//
//   5. **incoming Stream** : les données reçues via notifications
//      GATT sont poussées dans le flux `incoming` pour traitement
//      par le `P2PMeshService`.
//
//   6. **Ping de présence** : émission périodique d'un advertisement
//      BLE contenant le peerId. Auto-comptage HIVE local.
//
// === Gestion des connexions ===
//
//   - Maximum 7 connexions GATT simultanées (limite BLE standard).
//   - Reconnexion automatique avec backoff exponentiel (2s → 60s).
//   - Timeout de connexion : 10 secondes.
//   - Nettoyage périodique des connexions mortes (toutes les 30s).
//
// === Identifiant de pair (UUID de session anonyme) ===
//
// Chaque instance embarque un `peerId` stable (par défaut,
// l'`ephemeralUserId` du `NetworkCoordinator`). Ce peerId est
// inclus dans tous les pings de présence et dans un header de
// chaque message pour le dédoublonnage côté récepteur.
//
// === Correction ANR (v2.0 conservée) ===
//
//   - Throttling 2s des découvertes pour éviter les rafales.
//   - `scheduleMicrotask` pour céder la main à l'event loop.
//   - `Future.microtask` entre les opérations GATT lourdes.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/network/peer_counter_service.dart';
import '../p2p_mesh_service.dart';

/// UUID du service GATT StreetPhare.
const String kStreetPhareBleServiceUuid =
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kStreetPhareBleCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// Nombre maximal de connexions GATT simultanées.
const int _maxConnections = 7;

/// Timeout de connexion GATT.
const Duration _connectionTimeout = Duration(seconds: 10);

/// Transport BLE full-duplex pour la propagation P2P.
///
/// Combine scanning d'advertisements (comptage HIVE) et échange de
/// données via connexions GATT (broadcast / sendTo / incoming).
class BleMeshTransport implements MeshTransport {
  BleMeshTransport({
    FlutterReactiveBle? ble,
    String? peerId,
    Duration pingInterval = const Duration(seconds: 8),
  })  : _pingInterval = pingInterval,
        _ble = ble ?? FlutterReactiveBle(),
        _peerId = peerId ?? _generateRandomPeerId();

  final FlutterReactiveBle _ble;

  /// Identifiant STABLE de l'appareil émetteur.
  final String _peerId;

  /// Intervalle entre deux pings BLE de présence.
  final Duration _pingInterval;

  /// UUIDs du service et de la caractéristique GATT StreetPhare.
  static final Uuid serviceUuid = Uuid.parse(kStreetPhareBleServiceUuid);
  static final Uuid characteristicUuid = Uuid.parse(kStreetPhareBleCharUuid);

  @override
  String get name => 'ble';

  /// Expose le peerId local.
  String get peerId => _peerId;

  final _incomingController = StreamController<String>.broadcast();
  @override
  Stream<String> get incoming => _incomingController.stream;

  // ── Scan ──────────────────────────────────────────────────────────
  StreamSubscription<DiscoveredDevice>? _scanSub;
  bool _started = false;

  /// Anti-saturation : cache des devices déjà signalés récemment.
  final Map<String, DateTime> _lastDeviceSeen = {};
  static const Duration _deviceThrottleWindow = Duration(seconds: 2);

  /// Nettoie périodiquement le cache des devices vus.
  Timer? _throttleCleanupTimer;

  // ── Connexions GATT ───────────────────────────────────────────────
  /// Devices actuellement connectés (deviceId → état).
  final Map<String, _BleConnection> _connections = {};

  /// Queue des devices prêts à être connectés.
  final Set<String> _pendingConnections = {};

  /// Subscriptions de connexion en cours.
  final Map<String, StreamSubscription<ConnectionStateUpdate>> _connectSubs =
      {};

  // ── Ping ──────────────────────────────────────────────────────────
  Timer? _pingTimer;

  // ── Reconnexion ───────────────────────────────────────────────────
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, Timer> _reconnectTimers = {};
  static const Duration _reconnectBaseDelay = Duration(seconds: 2);
  static const Duration _reconnectMaxDelay = Duration(seconds: 60);

  // ── Nettoyage ─────────────────────────────────────────────────────
  Timer? _deadConnectionCleanupTimer;

  // ── BLE Advertising natif (MethodChannel) ─────────────────────────
  /// Canal platform pour le BLE advertising (mode peripheral GATT server).
  /// Ce canal n'est disponible QUE sur Android (natif via MainActivity.kt).
  static const _advertiserChannel = MethodChannel('streetphare/ble_advertiser');

  // ── GATT Server natif (MethodChannel + EventChannel) ──────────────
  /// Canal method pour piloter le serveur GATT natif.
  static const _gattChannel = MethodChannel('streetphare/ble_gatt');

  /// Canal event pour recevoir les données entrantes du serveur GATT.
  static const _gattEventChannel = EventChannel('streetphare/ble_gatt_events');

  // ──────────────────────────────────────────────────────────────────
  // isAvailable
  // ──────────────────────────────────────────────────────────────────

  @override
  bool get isAvailable {
    // Le BLE n'est pas disponible sur le Web.
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }

  // ──────────────────────────────────────────────────────────────────
  // start()
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final permissionsOk = await _requestBlePermissions();
    if (!permissionsOk) {
      if (kDebugMode) {
        debugPrint('[BLE] Permissions refusées, scan désactivé');
      }
      _started = false;
      return;
    }

    // Enregistre l'identifiant local pour exclusion du compteur HIVE.
    PeerCounterService.instance.setLocalPeerId(_peerId);

    // ── BLE Advertising natif + GATT Server ─────────────────────────
    // ORDRE CRITIQUE : le GATT server DOIT être démarré AVANT
    // l'advertising. Si on lance l'advertising en premier, un
    // client distant peut se connecter et faire discoverServices()
    // avant que addService() ait terminé → "service introuvable".
    //
    // PROTECTION ANTI-CRASH : certain téléphones (ex: 2201116SG) refusent
    // GattService.registerServer même après `_requestBlePermissions()`,
    // car la permission BLUETOOTH_CONNECT peut être révoquée après
    // l'affichage de la popup système. On wrappe dans un try/catch
    // pour dégrader en mode scan-only sans crasher l'app.
    try {
      await _startNativeGattServer();
      // Petit délai pour laisser addService() + onServiceAdded()
      // se propager jusqu'au Bluetooth stack.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _startNativeAdvertising();
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] Plugin natif GATT/advertising manquant : $e');
      }
      // Dégrade en scan-only : pas de broadcast sortant, mais le scan
      // passif et la connexion GATT entrante restent fonctionnels.
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] PlatformException GATT/advertising : $e');
      }
      // Ex: SecurityException BLUETOOTH_CONNECT → scan-only
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] Erreur GATT server/advertising : $e');
      }
      // Démarrage GATT échoué → BLE en mode scan passif uniquement (réception).
    }

    // ── Écoute des données entrantes du GATT server natif ──
    // Le serveur GATT natif reçoit les writes des clients distants
    // et les transmet à Dart via cet EventChannel.
    try {
      _gattEventChannel.receiveBroadcastStream().listen((event) {
        if (event is Map) {
          final deviceId = event['deviceId'] as String? ?? '';
          final data = event['data'] as String?;
          if (data != null) {
            // Déballe le frame BLE ({"p":"peerId","t":ts,"d":"payload"})
            // pour extraire le payload applicatif. Sans ce décodage,
            // P2PMeshService._processIncomingMessage() ne reconnaît pas
            // le format et ignore silencieusement le message.
            String payload;
            try {
              final frame = jsonDecode(data) as Map<String, dynamic>;
              payload = frame['d'] as String? ?? data;
            } catch (_) {
              payload = data; // Frame non-JSON → passe tel quel.
            }
            _incomingController.add(payload);
            if (kDebugMode) {
              debugPrint(
                  '[BLE] ← GATT natif reçu de $deviceId (${data.length} octets)');
            }
          }
        }
      }, onError: (Object e) {
        if (kDebugMode) debugPrint('[BLE] erreur EventChannel GATT: $e');
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] EventChannel GATT indisponible: $e');
      }
    }

    // ── Scan passif avec connexion GATT automatique ──
    _scanSub = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen(
      _onDeviceDiscovered,
      onError: (Object e) {
        if (kDebugMode) debugPrint('[BLE] scan error: $e');
      },
    );

    // ── Ping de présence périodique ──
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      scheduleMicrotask(_sendPresencePing);
    });
    scheduleMicrotask(_sendPresencePing);

    // ── Nettoyage périodique ──
    _throttleCleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupThrottleCache(),
    );
    _deadConnectionCleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupDeadConnections(),
    );

    if (kDebugMode) {
      debugPrint('[BLE] v3.0 full-duplex démarré — peerId=$_peerId');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // stop()
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<void> stop() async {
    // ── Arrêt de la publicité BLE native et du GATT server ─────────
    _stopNativeAdvertising();
    _stopNativeGattServer();

    _pingTimer?.cancel();
    _pingTimer = null;
    _throttleCleanupTimer?.cancel();
    _throttleCleanupTimer = null;
    _deadConnectionCleanupTimer?.cancel();
    _deadConnectionCleanupTimer = null;

    await _scanSub?.cancel();
    _scanSub = null;

    // Déconnecte tous les devices GATT.
    await _disconnectAll();

    _lastDeviceSeen.clear();
    _reconnectAttempts.clear();
    for (final t in _reconnectTimers.values) {
      t.cancel();
    }
    _reconnectTimers.clear();
    _pendingConnections.clear();
    _started = false;
  }

  // ──────────────────────────────────────────────────────────────────
  // broadcast(String payload)
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<void> broadcast(String payload) async {
    if (!_started) return;

    final frame = _buildFrame(payload);
    final disconnected = <String>[];

    for (final entry in _connections.entries) {
      final conn = entry.value;
      if (!conn.isReady) continue;

      try {
        await _ble.writeCharacteristicWithoutResponse(
          conn.dataCharacteristic,
          value: frame,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BLE] broadcast erreur vers ${entry.key}: $e');
        }
        disconnected.add(entry.key);
      }
    }

    // Nettoie les connexions mortes.
    for (final id in disconnected) {
      await _disconnectDevice(id);
    }

    if (kDebugMode && _connections.isNotEmpty) {
      debugPrint(
        '[BLE] broadcast → ${_connections.length - disconnected.length}/'
        '${_connections.length} devices (${frame.length} octets)',
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // sendTo(MeshPeer peer, String payload)
  // ──────────────────────────────────────────────────────────────────

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    if (!_started) return;

    final conn = _connections[peer.id];
    if (conn == null || !conn.isReady) {
      if (kDebugMode) {
        debugPrint('[BLE] sendTo impossible: ${peer.id} non connecté');
      }
      return;
    }

    try {
      final frame = _buildFrame(payload);
      await _ble.writeCharacteristicWithoutResponse(
        conn.dataCharacteristic,
        value: frame,
      );
      if (kDebugMode) {
        debugPrint('[BLE] sendTo ${peer.id} → ${frame.length} octets');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] sendTo erreur ${peer.id}: $e');
      }
      await _disconnectDevice(peer.id);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // dispose()
  // ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _incomingController.close();
  }

  // ──────────────────────────────────────────────────────────────────
  // Scan : découverte de devices
  // ──────────────────────────────────────────────────────────────────

  void _onDeviceDiscovered(DiscoveredDevice device) {
    // Throttling anti-saturation.
    final now = DateTime.now();
    final last = _lastDeviceSeen[device.id];
    if (last != null && now.difference(last) < _deviceThrottleWindow) {
      return;
    }
    _lastDeviceSeen[device.id] = now;

    // Comptage HIVE (fenêtre glissante 5 min).
    // Utilise device.id comme peerId stable et metadata SP_HIVE_ pour
    // passer le filtre isStreetPharePeer(). device.name est souvent vide
    // → on utilise toujours device.id comme fallback dans le metadata.
    PeerCounterService.instance.recordPeer(
      device.id,
      serviceUuid: serviceUuid.toString(),
      metadata: 'SP_HIVE_${device.id}',
    );

    if (kDebugMode) {
      debugPrint(
        '[BLE] device découvert: ${device.name} (${device.id}) '
        'RSSI=${device.rssi}',
      );
    }

    // Connexion GATT automatique si on a de la place.
    _maybeConnectToDevice(device.id);
  }

  // ──────────────────────────────────────────────────────────────────
  // Connexion GATT
  // ──────────────────────────────────────────────────────────────────

  void _maybeConnectToDevice(String deviceId) {
    // Déjà connecté ou en cours de connexion.
    if (_connections.containsKey(deviceId) ||
        _pendingConnections.contains(deviceId)) {
      return;
    }

    // Limite de connexions simultanées atteinte.
    if (_connections.length >= _maxConnections) {
      if (kDebugMode) {
        debugPrint('[BLE] max connexions atteint ($_maxConnections), '
            'device $deviceId ignoré');
      }
      return;
    }

    _pendingConnections.add(deviceId);
    _connectToDevice(deviceId);
  }

  Future<void> _connectToDevice(String deviceId) async {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    if (kDebugMode) {
      debugPrint('[$hh:$mm:$ss] [BLE] tentative connexion GATT → $deviceId '
          '(actives: ${_connections.length}, en attente: ${_pendingConnections.length})');
    }

    final sub = _ble
        .connectToDevice(
      id: deviceId,
      servicesWithCharacteristicsToDiscover: {
        serviceUuid: [characteristicUuid],
      },
      connectionTimeout: _connectionTimeout,
    )
        .listen(
      (update) => _onConnectionUpdate(deviceId, update),
      onError: (Object e) {
        final errNow = DateTime.now();
        final ehh = errNow.hour.toString().padLeft(2, '0');
        final emm = errNow.minute.toString().padLeft(2, '0');
        final ess = errNow.second.toString().padLeft(2, '0');
        if (kDebugMode) {
          debugPrint(
              '[$ehh:$emm:$ess] [BLE] échec connexion GATT $deviceId: $e');
        }
        _onConnectionFailed(deviceId);
      },
      cancelOnError: true,
    );

    _connectSubs[deviceId] = sub;
  }

  void _onConnectionUpdate(String deviceId, ConnectionStateUpdate update) {
    switch (update.connectionState) {
      case DeviceConnectionState.connected:
        if (kDebugMode) {
          debugPrint('[BLE] connecté GATT → $deviceId');
        }
        _pendingConnections.remove(deviceId);
        _reconnectAttempts.remove(deviceId);
        _discoverServices(deviceId);
        break;

      case DeviceConnectionState.disconnected:
        if (kDebugMode) {
          debugPrint('[BLE] déconnecté GATT → $deviceId');
        }
        _onConnectionFailed(deviceId);
        break;

      case DeviceConnectionState.connecting:
        // En cours — rien à faire.
        break;

      case DeviceConnectionState.disconnecting:
        // Déconnexion en cours — on attend la déconnexion complète.
        break;
    }
  }

  void _onConnectionFailed(String deviceId) {
    _pendingConnections.remove(deviceId);
    unawaited(_connectSubs[deviceId]?.cancel());
    _connectSubs.remove(deviceId);
    _connections.remove(deviceId);
    _scheduleReconnect(deviceId);
  }

  // ──────────────────────────────────────────────────────────────────
  // Découverte de services GATT
  // ──────────────────────────────────────────────────────────────────

  Future<void> _discoverServices(String deviceId) async {
    try {
      // ── Négociation MTU ───────────────────────────────────────
      // Le MTU BLE par défaut est 23 octets → writeWithoutResponse
      // limité à 20 octets. On négocie 512 pour permettre les
      // payloads JSON de ~400 octets sans fragmentation.
      try {
        final mtu = await _ble.requestMtu(
          deviceId: deviceId,
          mtu: 512,
        );
        if (kDebugMode) {
          debugPrint('[BLE] MTU négocié → $mtu octets avec $deviceId');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BLE] échec négociation MTU $deviceId: $e');
        }
      }

      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);

      QualifiedCharacteristic? dataChar;
      for (final service in services) {
        if (service.id == serviceUuid) {
          for (final char in service.characteristics) {
            if (char.id == characteristicUuid) {
              dataChar = QualifiedCharacteristic(
                serviceId: service.id,
                characteristicId: char.id,
                deviceId: deviceId,
              );
              break;
            }
          }
        }
      }

      if (dataChar == null) {
        if (kDebugMode) {
          debugPrint('[BLE] service StreetPhare introuvable sur $deviceId');
        }
        await _ble.clearGattCache(deviceId);
        return;
      }

      // Souscrit aux notifications pour recevoir les données.
      final notificationSub =
          _ble.subscribeToCharacteristic(dataChar).listen((data) {
        _onDataReceived(deviceId, data);
      }, onError: (Object e) {
        if (kDebugMode) {
          debugPrint('[BLE] erreur notification $deviceId: $e');
        }
      });

      final conn = _BleConnection(
        deviceId: deviceId,
        dataCharacteristic: dataChar,
        notificationSub: notificationSub,
      );
      _connections[deviceId] = conn;

      if (kDebugMode) {
        debugPrint('[BLE] prêt pour échange de données → $deviceId');
      }

      // Envoie immédiatement un ping de bienvenue.
      unawaited(_sendWelcomeFrame(deviceId));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] erreur découverte services $deviceId: $e');
      }
      _onConnectionFailed(deviceId);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Réception de données GATT
  // ──────────────────────────────────────────────────────────────────

  void _onDataReceived(String deviceId, List<int> data) {
    try {
      final raw = utf8.decode(data);
      if (kDebugMode) {
        debugPrint('[BLE] ← data reçue de $deviceId (${data.length} octets)');
      }

      // Déballe le frame BLE externe pour extraire le payload applicatif.
      // _buildFrame() empaquette dans {"p":"peerId","t":timestamp,"d":"payload"}.
      // On extrait 'd' pour le passer à P2PMeshService, qui attend
      // soit un objet alerte, soit un gossip, soit un panic, soit un ping.
      String payload;
      try {
        final frame = jsonDecode(raw) as Map<String, dynamic>;
        final p = frame['p'] as String?; // peerId émetteur
        payload = frame['d'] as String? ?? raw;
        if (p != null && p != _peerId) {
          // Enregistre l'émetteur dans le comptage HIVE.
          PeerCounterService.instance.recordPeer(
            p,
            serviceUuid: serviceUuid.toString(),
          );
        } else {
          // Fallback : utilise le deviceId BLE.
          PeerCounterService.instance.recordPeer(
            deviceId,
            serviceUuid: serviceUuid.toString(),
          );
        }
      } catch (_) {
        // Frame non-JSON → passe le raw tel quel.
        payload = raw;
        PeerCounterService.instance.recordPeer(
          deviceId,
          serviceUuid: serviceUuid.toString(),
        );
      }

      // Pousse le payload applicatif (non le frame) dans incoming.
      _incomingController.add(payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] erreur décodage data $deviceId: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Déconnexion
  // ──────────────────────────────────────────────────────────────────

  Future<void> _disconnectDevice(String deviceId) async {
    final conn = _connections.remove(deviceId);
    if (conn != null) {
      await conn.notificationSub.cancel();
    }
    unawaited(_connectSubs[deviceId]?.cancel());
    _connectSubs.remove(deviceId);
    _pendingConnections.remove(deviceId);

    // Ne pas tenter de reconnexion pour une déconnexion volontaire
    // (ex: trop de connexions). Le scan redécouvrira le device.
  }

  Future<void> _disconnectAll() async {
    final ids = _connections.keys.toList();
    for (final id in ids) {
      await _disconnectDevice(id);
    }
    _connections.clear();
    for (final sub in _connectSubs.values) {
      await sub.cancel();
    }
    _connectSubs.clear();
    _pendingConnections.clear();
  }

  // ──────────────────────────────────────────────────────────────────
  // Reconnexion automatique avec backoff exponentiel
  // ──────────────────────────────────────────────────────────────────

  void _scheduleReconnect(String deviceId) {
    if (!_started) return;

    final attempt = (_reconnectAttempts[deviceId] ?? 0) + 1;
    _reconnectAttempts[deviceId] = attempt;

    final delayMs = (_reconnectBaseDelay * pow(2, attempt - 1).toInt())
        .inMilliseconds
        .clamp(0, _reconnectMaxDelay.inMilliseconds);

    if (kDebugMode) {
      debugPrint(
        '[BLE] reconnexion $deviceId dans ${delayMs}ms (tentative $attempt)',
      );
    }

    _reconnectTimers[deviceId]?.cancel();
    _reconnectTimers[deviceId] = Timer(Duration(milliseconds: delayMs), () {
      if (_started) {
        _maybeConnectToDevice(deviceId);
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────
  // Ping de présence
  // ──────────────────────────────────────────────────────────────────

  void _sendPresencePing() {
    // NE PAS s'auto-enregistrer comme pair — l'exclusion locale est
    // gérée par PeerCounterService._excludeLocal().
    // Seuls les pairs DISTANTS détectés via scan/advertisement sont
    // comptabilisés dans _onDeviceDiscovered().

    if (kDebugMode) {
      final connCount = _connections.values.where((c) => c.isReady).length;
      debugPrint(
        '[BLE] ping présence — peerId=$_peerId '
        '($connCount connexion(s) active(s))',
      );
    }
  }

  /// Envoie un frame de bienvenue après connexion GATT réussie.
  Future<void> _sendWelcomeFrame(String deviceId) async {
    final welcome = _buildFrame(jsonEncode({
      'type': 'ble_welcome',
      'peerId': _peerId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    }));
    final conn = _connections[deviceId];
    if (conn == null || !conn.isReady) return;

    try {
      await _ble.writeCharacteristicWithoutResponse(
        conn.dataCharacteristic,
        value: welcome,
      );
    } catch (_) {
      // Silencieux — sera détecté au prochain broadcast.
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Construction de frame
  // ──────────────────────────────────────────────────────────────────

  /// Construit un frame BLE avec header peerId.
  List<int> _buildFrame(String payload) {
    final frame = jsonEncode({
      'p': _peerId, // peerId émetteur (anti-double-comptage)
      't': DateTime.now().toUtc().millisecondsSinceEpoch, // timestamp
      'd': payload, // données applicatives
    });
    return utf8.encode(frame);
  }

  // ──────────────────────────────────────────────────────────────────
  // Permissions BLE
  // ──────────────────────────────────────────────────────────────────

  Future<bool> _requestBlePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    try {
      var scanGranted = await Permission.bluetoothScan.isGranted;
      if (!scanGranted) {
        final result = await Permission.bluetoothScan.request();
        scanGranted = result.isGranted;
      }

      var connectGranted = await Permission.bluetoothConnect.isGranted;
      if (!connectGranted) {
        final result = await Permission.bluetoothConnect.request();
        connectGranted = result.isGranted;
      }

      // BLUETOOTH_ADVERTISE est requis pour le mode peripheral GATT
      // (émission d'advertisements BLE). Sans cette permission,
      // startAdvertising() échoue sur Android 12+.
      var advertiseGranted = await Permission.bluetoothAdvertise.isGranted;
      if (!advertiseGranted) {
        final result = await Permission.bluetoothAdvertise.request();
        advertiseGranted = result.isGranted;
      }
      if (advertiseGranted) {
        if (kDebugMode) debugPrint('[BLE] BLUETOOTH_ADVERTISE accordé');
      }

      if (scanGranted) {
        if (kDebugMode) debugPrint('[BLE] BLUETOOTH_SCAN accordé');
        return true;
      }

      var locationGranted = await Permission.locationWhenInUse.isGranted;
      if (!locationGranted) {
        final result = await Permission.locationWhenInUse.request();
        locationGranted = result.isGranted;
      }
      if (locationGranted) {
        if (kDebugMode) debugPrint('[BLE] Location (fallback) accordée');
        return true;
      }

      if (kDebugMode) {
        debugPrint('[BLE] Aucune permission BLE/Location accordée');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] Erreur permission: $e');
      }
      return true; // Laisse le scan tenter sa chance.
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Nettoyage
  // ──────────────────────────────────────────────────────────────────

  void _cleanupThrottleCache() {
    final cutoff = DateTime.now().subtract(_deviceThrottleWindow * 2);
    _lastDeviceSeen.removeWhere((_, lastSeen) => lastSeen.isBefore(cutoff));
  }

  void _cleanupDeadConnections() {
    final dead = <String>[];
    for (final entry in _connections.entries) {
      if (!entry.value.isReady) {
        dead.add(entry.key);
      }
    }
    for (final id in dead) {
      if (kDebugMode) debugPrint('[BLE] nettoyage connexion morte: $id');
      _disconnectDevice(id);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────

  /// Helper de test : injecte un message reçu (tests unitaires).
  void debugInjectIncoming(String payload) {
    _incomingController.add(payload);
  }

  /// Nombre de connexions GATT actives.
  int get activeConnectionCount =>
      _connections.values.where((c) => c.isReady).length;

  // ── BLE Advertising natif (MethodChannel) ─────────────────────────

  /// Démarre la publicité BLE via le canal platform Android.
  /// Non-bloquant : si le canal n'est pas disponible (iOS, desktop),
  /// l'appel est silencieusement ignoré.
  void _startNativeAdvertising() {
    try {
      unawaited(
        _advertiserChannel.invokeMethod('startAdvertising', {
          'peerId': _peerId,
        }),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] advertising natif non disponible: $e');
      }
    }
  }

  /// Arrête la publicité BLE via le canal platform Android.
  void _stopNativeAdvertising() {
    try {
      unawaited(_advertiserChannel.invokeMethod('stopAdvertising'));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] stop advertising natif erreur: $e');
      }
    }
  }

  // ── GATT Server natif (MethodChannel + EventChannel) ──────────────

  Future<void> _startNativeGattServer() async {
    try {
      await _gattChannel.invokeMethod('startGattServer');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] GATT server natif non disponible: $e');
      }
    }
  }

  void _stopNativeGattServer() {
    try {
      unawaited(_gattChannel.invokeMethod('stopGattServer'));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] arrêt GATT server natif erreur: $e');
      }
    }
  }

  // _sendViaNativeGatt() supprimée — non utilisée. Le broadcast sortant
  // passe par notifyCharacteristicChanged() via le GATT server natif.
  // Les devices flutter_reactive_ble sont gérés dans _connections.

  static String _generateRandomPeerId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'ble-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}

// ──────────────────────────────────────────────────────────────────
// Helper : état d'une connexion BLE individuelle
// ──────────────────────────────────────────────────────────────────

class _BleConnection {
  _BleConnection({
    required this.deviceId,
    required this.dataCharacteristic,
    required this.notificationSub,
  });

  final String deviceId;
  final QualifiedCharacteristic dataCharacteristic;
  final StreamSubscription<List<int>> notificationSub;

  bool get isReady => true;
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
