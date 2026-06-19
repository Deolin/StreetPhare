// lib/features/sandbox/sandbox_controller.dart
//
// Contrôleur sandbox – pont entre l'UI d'administration Flutter Web
// et le backend Node.js (test_servers/sandbox.js + admin_dashboard_v2.js).
//
// Responsabilités :
//   1. Gérer la connexion WebSocket vers le serveur sandbox
//      (ws://localhost:4000/sandbox par défaut).
//   2. Mode "offline" : si aucun backend n'est disponible, génère des
//      paquets simulés localement et les injecte directement via le
//      LoopbackMeshTransport (pas de crash, pas d'erreur bloquante).
//   3. Exposer des métriques ValueNotifier pour le dashboard admin :
//      - `userCount`    : nombre d'utilisateurs simulés actifs
//      - `alertCount`   : nombre d'alertes injectées
//      - `messageCount` : nombre de messages Hive échangés
//      - `eventCount`   : nombre d'événements simulés
//      - `cooldownSec`  : cooldown restant avant prochaine injection
//      - `connectionState` : état de la connexion sandbox
//   4. Permettre l'injection de paquets simulés via `injectAlerts()`,
//      `injectEvents()`, `injectMessages()`, `simulateUsers()`.
//
// Architecture :
//   Flutter Web (ce contrôleur) ←→ WebSocket ←→ Node.js sandbox
//               ↕ (mode offline : injection directe)
//         LoopbackMeshTransport
//               ↕
//         P2PMeshService → NetworkCoordinator
//               ↕
//         flutter_map (Dashboard Admin)

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../database/alert_model.dart';
import '../../network/network_coordinator.dart';
import '../../network/transports/loopback_transport.dart';

/// État de la connexion sandbox.
enum SandboxConnectionState { disconnected, connecting, connected, error }

/// Contrôleur singleton de la sandbox.
class SandboxController {
  SandboxController._();
  static final SandboxController instance = SandboxController._();

  // ── Configuration ────────────────────────────────────────────────────────

  /// URL du WebSocket sandbox (port 4000 = admin_dashboard_v2.js).
  static const String defaultWsUrl = 'ws://localhost:4000/sandbox';

  /// Durée du cooldown entre deux injections (anti-spam).
  static const Duration cooldownDuration = Duration(seconds: 3);

  // ── Métriques ValueNotifier (liées au Dashboard Admin) ───────────────────

  final ValueNotifier<int> userCount = ValueNotifier<int>(0);
  final ValueNotifier<int> alertCount = ValueNotifier<int>(0);
  final ValueNotifier<int> messageCount = ValueNotifier<int>(0);
  final ValueNotifier<int> eventCount = ValueNotifier<int>(0);
  final ValueNotifier<int> cooldownSec = ValueNotifier<int>(0);
  final ValueNotifier<SandboxConnectionState> connectionState =
      ValueNotifier<SandboxConnectionState>(SandboxConnectionState.disconnected);

  // ── État interne ─────────────────────────────────────────────────────────

  WebSocketChannel? _channel;
  Timer? _cooldownTimer;
  DateTime? _lastInjection;

  /// Transport loopback pour injection directe en mode offline.
  LoopbackMeshTransport? _loopback;

  /// Indique si le backend sandbox est joignable.
  bool get isBackendConnected =>
      connectionState.value == SandboxConnectionState.connected;

  // ── Initialisation / destruction ─────────────────────────────────────────

  /// Connecte le contrôleur au backend sandbox.
  ///
  /// [wsUrl] : URL du WebSocket sandbox.
  /// [loopback] : transport loopback (requis sur le Web).
  Future<void> connect({
    String wsUrl = defaultWsUrl,
    LoopbackMeshTransport? loopback,
  }) async {
    if (_channel != null) return;

    _loopback = loopback;
    connectionState.value = SandboxConnectionState.connecting;

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      connectionState.value = SandboxConnectionState.connected;

      _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          if (kDebugMode) {
            debugPrint('[SandboxController] erreur WebSocket : $error');
          }
          _fallbackToOffline();
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('[SandboxController] WebSocket fermé');
          }
          _fallbackToOffline();
        },
      );

      if (kDebugMode) {
        debugPrint('[SandboxController] connecté à $wsUrl');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SandboxController] backend indisponible → mode offline '
            '($e)');
      }
      _fallbackToOffline();
    }
  }

  /// Bascule en mode offline (injection locale sans backend).
  void _fallbackToOffline() {
    _channel?.sink.close();
    _channel = null;
    // En mode offline, on reste "connected" car les injections locales
    // fonctionnent sans backend.
    connectionState.value = SandboxConnectionState.connected;
  }

  /// Déconnecte le WebSocket.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _cooldownTimer?.cancel();
    connectionState.value = SandboxConnectionState.disconnected;
  }

  /// Libère toutes les ressources.
  void dispose() {
    disconnect();
    userCount.dispose();
    alertCount.dispose();
    messageCount.dispose();
    eventCount.dispose();
    cooldownSec.dispose();
    connectionState.dispose();
  }

  // ── API d'injection (appelée depuis l'UI admin) ──────────────────────────

  /// Injecte [count] alertes simulées autour de [centerLat]/[centerLng].
  ///
  /// En mode backend connecté : envoie via WebSocket.
  /// En mode offline : génère localement et injecte via le loopback.
  Future<void> injectAlerts({
    int count = 3,
    double centerLat = 50.4762,
    double centerLng = 4.5422,
  }) async {
    if (!_canInject()) return;
    _startCooldown();

    if (_channel != null) {
      // Mode backend connecté
      final payload = jsonEncode({
        'action': 'inject-alerts',
        'count': count,
        'lat': centerLat,
        'lng': centerLng,
      });
      _channel!.sink.add(payload);
    } else {
      // Mode offline : injection locale directe
      _injectAlertsLocally(count: count, centerLat: centerLat, centerLng: centerLng);
    }

    alertCount.value += count;

    if (kDebugMode) {
      debugPrint('[SandboxController] injection de $count alertes');
    }
  }

  /// Injecte [count] événements simulés.
  Future<void> injectEvents({int count = 1}) async {
    if (!_canInject()) return;
    _startCooldown();

    if (_channel != null) {
      final payload = jsonEncode({
        'action': 'inject-events',
        'count': count,
      });
      _channel!.sink.add(payload);
    }

    eventCount.value += count;

    if (kDebugMode) {
      debugPrint('[SandboxController] injection de $count événements');
    }
  }

  /// Injecte [count] messages Hive P2P simulés.
  Future<void> injectMessages({int count = 5}) async {
    if (!_canInject()) return;
    _startCooldown();

    if (_channel != null) {
      final payload = jsonEncode({
        'action': 'send-hive-messages',
        'count': count,
      });
      _channel!.sink.add(payload);
    } else {
      // Mode offline : injection locale
      _injectMessagesLocally(count: count);
    }

    messageCount.value += count;

    if (kDebugMode) {
      debugPrint('[SandboxController] injection de $count messages Hive');
    }
  }

  /// Démarre / arrête [count] utilisateurs simulés.
  Future<void> simulateUsers({int count = 5}) async {
    if (!_canInject()) return;
    _startCooldown();

    final isActive = userCount.value > 0;

    if (_channel != null) {
      final action = isActive ? 'stop-users' : 'start-users';
      final payload = jsonEncode({
        'action': action,
        'count': count,
      });
      _channel!.sink.add(payload);
    }

    if (isActive) {
      userCount.value = 0;
    } else {
      userCount.value = count;
    }

    if (kDebugMode) {
      debugPrint('[SandboxController] $count utilisateurs simulés : '
          '${isActive ? "stoppés" : "démarrés"}');
    }
  }

  // ── Injection locale offline ─────────────────────────────────────────────

  /// Génère et injecte localement des alertes simulées.
  ///
  /// Utilise [NetworkCoordinator.instance.createAlert] pour créer de
  /// vraies alertes dans HiveAlertDatabase, ce qui garantit qu'elles
  /// apparaissent immédiatement dans :
  ///   - HiveAlertDatabase → alertsStream → AdminMapWidget (carte)
  ///   - LoopbackMeshTransport → P2PMeshService (mesh virtuel)
  void _injectAlertsLocally({
    required int count,
    required double centerLat,
    required double centerLng,
  }) {
    final types = AlertType.values;
    final rng = math.Random();
    final coordinator = NetworkCoordinator.instance;

    for (int i = 0; i < count; i++) {
      // Position aléatoire ~500m autour du centre
      final offsetLat = (rng.nextDouble() - 0.5) * 0.01;
      final offsetLng = (rng.nextDouble() - 0.5) * 0.01;
      final lat = centerLat + offsetLat;
      final lng = centerLng + offsetLng;

      final type = types[rng.nextInt(types.length)];

      // Crée une VRAIE alerte via le NetworkCoordinator.
      // Cela l'insère dans HiveAlertDatabase, la signe, et la
      // diffuse sur tous les transports (dont le loopback).
      unawaited(
        coordinator.createAlert(
          type: type,
          latitude: lat,
          longitude: lng,
          description: '[SANDBOX] Alerte de test #${i + 1}',
        ),
      );
    }
  }

  /// Génère et injecte localement des messages Hive P2P via le loopback.
  void _injectMessagesLocally({required int count}) {
    if (_loopback == null) return;

    for (int i = 0; i < count; i++) {
      final packet = <String, dynamic>{
        'kind': 'hive_p2p_message',
        'payload': {
          'id': 'msg_${DateTime.now().millisecondsSinceEpoch}_$i',
          'threadId': 'sandbox_thread_offline',
          'senderId': 'sandbox_user_offline',
          'content': '[SANDBOX OFFLINE] Message Hive #$i à ${DateTime.now().toIso8601String()}',
          'type': 'TEXT',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        'ts': DateTime.now().toUtc().toIso8601String(),
        'sender_id': 'sandbox_offline',
        'local_only': false,
      };

      _loopback!.injectPacket(packet);
    }
  }

  // ── Réception des messages backend ───────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final kind = data['kind'] as String? ?? data['type'] as String?;

      // Injection directe dans le transport loopback pour un
      // traitement immédiat par le P2PMeshService.
      if (_loopback != null && kind != null) {
        _loopback!.injectPacket(data);
      }

      // Met à jour les compteurs.
      switch (kind) {
        case 'alert_inject':
        case 'alert_trigger':
          alertCount.value++;
          break;
        case 'event_inject':
          eventCount.value++;
          break;
        case 'hive_inject':
        case 'hive_message':
          messageCount.value++;
          break;
        case 'user_move':
          if (userCount.value == 0) userCount.value = 1;
          break;
      }

      if (kDebugMode) {
        debugPrint('[SandboxController] backend event: $kind');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SandboxController] erreur parsing : $e');
      }
    }
  }

  // ── Cooldown anti-spam ───────────────────────────────────────────────────

  bool _canInject() {
    if (_lastInjection == null) return true;
    final elapsed = DateTime.now().difference(_lastInjection!);
    return elapsed >= cooldownDuration;
  }

  void _startCooldown() {
    _lastInjection = DateTime.now();
    cooldownSec.value = cooldownDuration.inSeconds;

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = cooldownSec.value - 1;
      if (remaining <= 0) {
        cooldownSec.value = 0;
        timer.cancel();
      } else {
        cooldownSec.value = remaining;
      }
    });
  }
}