// lib/network/transports/relay_transport.dart
//
// Implémentation "Relay" (données mobiles 3G/4G/5G) du contrat
// MeshTransport.
//
// v3.3.5 — BYPASS COMPLET de web_socket_channel
//   Le wrapper IOWebSocketChannel (même sans GuaranteeChannel) causait
//   des fermetures 1002 (Protocol Error) après chaque welcome.
//   Solution : utiliser dart:io WebSocket directement, sans AUCUN
//   wrapper. On gère nous-mêmes le sink via socket.add() et le
//   stream via socket.listen().

import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../network_config.dart';
import '../p2p_mesh_service.dart';

/// Transport relay sur Internet (WebSocket).
class RelayMeshTransport implements MeshTransport {
  RelayMeshTransport({
    required this.relayUrl,
    this.heartbeat = const Duration(seconds: 0),
    String? peerId,
  }) : _peerId = peerId ?? _generateRandomPeerId();

  /// URL WebSocket du relay (ex: wss://relay.streetphare.org/mesh).
  final String relayUrl;

  /// Identifiant de session anonyme stable.
  final String _peerId;

  String get peerId => _peerId;

  /// Intervalle du heartbeat applicatif. 0 = désactivé.
  final Duration heartbeat;

  // v3.3.5 : on utilise dart:io WebSocket directement, sans wrapper.
  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  bool _reconnecting = false;

  Duration get _nextRetryDelay {
    final seconds = (1 << _reconnectAttempts).clamp(5, 60);
    return Duration(seconds: seconds);
  }

  final _incomingController = StreamController<String>.broadcast();

  @override
  String get name => 'relay';

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  bool get isAvailable => true;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    unawaited(_connect());
  }

  /// Établit la connexion WebSocket via dart:io WebSocket DIRECTEMENT.
  /// AUCUN wrapper (IOWebSocketChannel, GuaranteeChannel, etc.).
  ///
  /// FIX v3.3.5 — Bypass total de web_socket_channel :
  ///   Même IOWebSocketChannel (qui wrap juste dart:io WebSocket sans
  ///   GuaranteeChannel) causait des fermetures 1002 après le welcome.
  ///   La cause exacte est subtile : IOWebSocketChannel écoute le stream
  ///   dart:io et peut fermer le socket si le stream émet une erreur
  ///   ou se ferme de façon inattendue. En utilisant dart:io WebSocket
  ///   directement, on garde le contrôle total.
  Future<void> _connect() async {
    if (_disposed) return;

    // FIX v3.3.4 : Si le DNS WAN échoue, bascule vers l'adresse locale.
    final urlsToTry = <String>[relayUrl];
    final localFallback = NetworkConfig.localhostRelayUrl;
    if (localFallback != relayUrl) {
      urlsToTry.add(localFallback);
    }

    WebSocket? socket;
    String? connectedUrl;

    for (final url in urlsToTry) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Relay] → tentative connexion à $url');

      try {
        socket = await WebSocket.connect(
          url,
          headers: <String, dynamic>{
            'Origin': 'https://streetphare.ddns.net',
          },
        );
        connectedUrl = url;
        break;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Relay] → échec connexion à $url: $e');
        }
      }
    }

    if (socket == null || connectedUrl == null) {
      if (kDebugMode) {
        debugPrint('[Relay] → tous les URLs ont échoué');
      }
      _scheduleReconnect();
      return;
    }

    if (_disposed || !_started) {
      try {
        await socket.close();
      } catch (_) {}
      return;
    }

    // Désactiver les pings automatiques dart:io.
    try {
      socket.pingInterval = null;
    } catch (_) {}

    _socket = socket;
    _reconnectAttempts = 0;
    _reconnecting = false;

    if (kDebugMode) {
      debugPrint('[Relay] → ws connecté (dart:io natif, sans wrapper)');
    }

    // ── Écoute DIRECTE du stream dart:io WebSocket ────────────────────
    // On écoute le socket natif. Les données arrivent comme String
    // (messages texte) ou List<int> (messages binaires).
    // Les frames de contrôle (ping/pong/close) sont gérées automatiquement
    // par dart:io et n'apparaissent PAS dans ce stream.
    _sub = _socket!.listen(
      (data) {
        // ═══ PROTOCOL ERROR GUARD ═══════════════════════════════════
        try {
          if (data is String) {
            if (kDebugMode) {
              final preview =
                  data.length > 200 ? '${data.substring(0, 200)}...' : data;
              debugPrint('[Relay] ← $preview');
            }
            _incomingController.add(data);
          } else if (data is List<int>) {
            final str = utf8.decode(data);
            if (kDebugMode) {
              final preview =
                  str.length > 200 ? '${str.substring(0, 200)}...' : str;
              debugPrint('[Relay] ← (binary) $preview');
            }
            _incomingController.add(str);
          }
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[Relay] ⚠ exception interceptée '
                '(protégée du code 1002): $e\n$st');
          }
        }
      },
      onError: (Object err) {
        if (kDebugMode) {
          debugPrint('[Relay] ⚠ ws stream error: $err');
        }
        _cleanupAndReconnect();
      },
      onDone: () {
        final code = _socket?.closeCode;
        final reason = _socket?.closeReason;
        if (kDebugMode) {
          debugPrint('[Relay] ⚠ ws fermé (code=$code, reason=$reason)');
        } else {
          debugPrint('[Relay] ws fermé (code=$code)');
        }
        _cleanupAndReconnect();
      },
      cancelOnError: false, // CRITIQUE : ne pas fermer le stream sur erreur.
    );

    if (heartbeat > Duration.zero) {
      _startHeartbeat();
    }
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    if (!_started || _disposed) return;
    if (_reconnecting) return;
    _reconnecting = true;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;
    final delay = _nextRetryDelay;
    if (kDebugMode) {
      debugPrint(
          '[Relay] reconnexion dans ${delay.inSeconds}s (essai #$_reconnectAttempts)');
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeat, (_) {
      try {
        _socket?.add(jsonEncode({
          'kind': 'ping',
          'ts': DateTime.now().toUtc().toIso8601String(),
        }));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Relay] Erreur ping heartbeat: $e');
        }
        _cleanupAndReconnect();
      }
    });
  }

  void _cleanupAndReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    if (!_started || _disposed) return;
    if (_reconnecting) return;
    _reconnecting = true;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;
    final delay = _nextRetryDelay;
    if (kDebugMode) {
      debugPrint(
          '[Relay] reconnexion dans ${delay.inSeconds}s (essai #$_reconnectAttempts)');
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  @override
  Future<void> stop() async {
    _started = false;
    _reconnecting = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  @override
  Future<void> broadcast(String payload) async {
    if (_socket == null) return;
    try {
      _socket!.add(payload);
    } catch (e) {
      if (kDebugMode) debugPrint('[Relay] send error: $e');
    }
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    await broadcast(payload);
  }

  @override
  void dispose() {
    _disposed = true;
    _started = false;
    _reconnecting = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _reconnectAttempts = 0;
    _incomingController.close();
  }

  static String _generateRandomPeerId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'relay-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}