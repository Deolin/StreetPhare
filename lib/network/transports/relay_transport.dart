// lib/network/transports/relay_transport.dart
//
// Implémentation "Relay" (données mobiles 3G/4G/5G) du contrat
// MeshTransport.
//
// v3.4.0 — WEBSOCKET CHANNEL STANDARD
//   Abandon du hack de handshake manuel (HttpClient + detachSocket +
//   WebSocket.fromUpgradedSocket) qui brisait le décodage TLS via
//   le reverse-proxy Caddy (code 1006 sur le WAN).
//   Utilisation de WebSocketChannel.connect() du package standard
//   web_socket_channel v3.x, qui gère nativement et de manière robuste
//   le handshake TLS/WebSocket sur toutes les plateformes.
//   Le heartbeat applicatif envoie des pings JSON dans le flux normal
//   du channel, sans toucher au socket TCP sous-jacent.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network_config.dart';
import '../p2p_mesh_service.dart';

/// Transport relay sur Internet (WebSocket).
class RelayMeshTransport implements MeshTransport {
  RelayMeshTransport({
    required this.relayUrl,
    this.heartbeat = const Duration(seconds: 15),
    String? peerId,
  }) : _peerId = peerId ?? _generateRandomPeerId();

  /// URL WebSocket du relay (ex: wss://relay.streetphare.org/mesh).
  final String relayUrl;

  /// Identifiant de session anonyme stable.
  final String _peerId;

  String get peerId => _peerId;

  /// Intervalle du heartbeat applicatif (ping de présence permettant
  /// aux autres clients du relay de compter ce pair). 0 = désactivé.
  final Duration heartbeat;

  WebSocketChannel? _channel;
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

  /// Établit la connexion WebSocket via [WebSocketChannel.connect].
  ///
  /// Le package web_socket_channel v3.x gère nativement le handshake
  /// TLS et la négociation WebSocket, y compris à travers les
  /// reverse-proxies comme Caddy. Aucun hack manuel de socket.
  Future<void> _connect() async {
    if (_disposed) return;

    // FIX v3.3.4 : Si le DNS WAN échoue, bascule vers l'adresse locale.
    final urlsToTry = <String>[relayUrl];
    final localFallback = NetworkConfig.localhostRelayUrl;
    if (localFallback != relayUrl) {
      urlsToTry.add(localFallback);
    }

    WebSocketChannel? channel;
    String? connectedUrl;

    for (final url in urlsToTry) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Relay] → tentative connexion à $url');

      try {
        final uri = Uri.parse(url);
        channel = WebSocketChannel.connect(uri);

        // Attendre que le handshake soit terminé avant de continuer.
        await channel.ready;

        connectedUrl = url;
        break;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Relay] → échec connexion à $url: $e');
        }
        // Nettoyer le channel en échec.
        try {
          await channel?.sink.close();
        } catch (_) {}
        channel = null;
      }
    }

    if (channel == null || connectedUrl == null) {
      if (kDebugMode) {
        debugPrint('[Relay] → tous les URLs ont échoué');
      }
      _scheduleReconnect();
      return;
    }

    if (_disposed || !_started) {
      try {
        await channel.sink.close();
      } catch (_) {}
      return;
    }

    _channel = channel;
    _reconnectAttempts = 0;
    _reconnecting = false;

    if (kDebugMode) {
      debugPrint('[Relay] → ws connecté (WebSocketChannel standard v3.x)');
    }

    // ── Écoute du stream WebSocketChannel ────────────────────────────
    _sub = _channel!.stream.listen(
      (data) {
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
            debugPrint('[Relay] ⚠ exception interceptée: $e\n$st');
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
        if (kDebugMode) {
          debugPrint('[Relay] ⚠ ws fermé');
        }
        _cleanupAndReconnect();
      },
      cancelOnError: false,
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
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

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
        _channel?.sink.add(jsonEncode({
          'kind': 'ping',
          'id': _peerId,
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
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

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
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  Future<void> broadcast(String payload) async {
    if (_channel == null) return;
    try {
      _channel!.sink.add(payload);
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
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _reconnectAttempts = 0;
    _incomingController.close();
  }

  static String _generateRandomPeerId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'relay-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
