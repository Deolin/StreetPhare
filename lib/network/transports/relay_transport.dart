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
import 'dart:io' show HttpClient, WebSocket;
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

  // v3.3.6 : HttpClient réutilisé pour éviter les fuites de ressources.
  final HttpClient _httpClient = HttpClient();

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

  /// Établit la connexion WebSocket via HttpClient + WebSocketTransformer.
  ///
  /// FIX v3.3.6 — Upgrade manuel pour contrôle total du handshake :
  ///   L'API haut-niveau WebSocket.connect() de Dart SDK 3.2+ active
  ///   permessage-deflate par défaut. Même avec compression:
  ///   CompressionOptions.compressionOff, le handshake envoyait encore
  ///   l'en-tête Sec-WebSocket-Extensions. Le serveur (ws ^8.18.0) avec
  ///   perMessageDeflate: false ne le gère pas → 1002 Protocol Error
  ///   juste après le welcome.
  ///
  ///   Solution radicale : HttpClient + WebSocketTransformer.upgrade().
  ///   On contrôle chaque en-tête du handshake manuellement, SANS
  ///   Sec-WebSocket-Extensions. Aucune négociation de compression.
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
        final uri = Uri.parse(url);
        final request = await _httpClient.getUrl(uri);

        // ── En-têtes strictement contrôlés ──────────────────────────
        // PAS de Sec-WebSocket-Extensions → pas de permessage-deflate.
        request.headers.set('Connection', 'Upgrade');
        request.headers.set('Upgrade', 'websocket');
        request.headers.set(
          'Sec-WebSocket-Version',
          '13',
        );
        request.headers.set(
          'Sec-WebSocket-Key',
          _generateWebSocketKey(),
        );
        request.headers.set(
          'Origin',
          'https://streetphare.ddns.net',
        );
        // User-Agent personnalisé pour debugging serveur.
        request.headers.set(
          'User-Agent',
          'StreetPhare-Flutter/3.3.6',
        );

        // ignore: close_sinks — le sink est consommé par detachSocket()
        // dans le cas 101, ou par drain() dans le cas non-101.
        final response = await request.close();

        if (response.statusCode != 101) {
          if (kDebugMode) {
            debugPrint(
              '[Relay] → upgrade refusé: HTTP ${response.statusCode}',
            );
          }
          // Drainer la réponse HTTP pour fermer le sink sous-jacent
          // et éviter une fuite de ressource (close_sinks).
          await response.drain();
          continue;
        }

        // Upgrade manuel côté client :
        //   1. Détacher le socket TCP sous-jacent de la réponse HTTP.
        //   2. L'envelopper dans un WebSocket client sans compression.
        // (close_sinks supprimé via le commentaire ignore sur la déclaration
        //  de `response` plus haut ; detachSocket() consomme le sink.)
        final rawSocket = await response.detachSocket();
        socket = WebSocket.fromUpgradedSocket(
          rawSocket,
          serverSide: false,
        );
        // Désactiver les pings automatiques dart:io (on gère le
        // heartbeat nous-mêmes).
        try {
          socket.pingInterval = null;
        } catch (_) {}

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

    _socket = socket;
    _reconnectAttempts = 0;
    _reconnecting = false;

    if (kDebugMode) {
      debugPrint(
        '[Relay] → ws connecté '
        '(HttpClient+WebSocketTransformer, sans permessage-deflate)',
      );
    }

    // ── Écoute DIRECTE du stream dart:io WebSocket ────────────────────
    _sub = _socket!.listen(
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
            debugPrint(
              '[Relay] ⚠ exception interceptée '
              '(protégée du code 1002): $e\n$st',
            );
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
    try {
      _httpClient.close();
    } catch (_) {}
  }

  /// Génère une clé Sec-WebSocket-Key aléatoire (RFC 6455 §4.1).
  /// 16 octets aléatoires, encodés en base64.
  static String _generateWebSocketKey() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64.encode(bytes);
  }

  static String _generateRandomPeerId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'relay-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
