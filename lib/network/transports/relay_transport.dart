// lib/network/transports/relay_transport.dart
//
// Implémentation "Relay" (données mobiles 3G/4G/5G) du contrat
// MeshTransport.
//
// Quand Internet est disponible, on relaie les alertes à un serveur
// de relay (différent du serveur central de synchronisation), qui
// les rediffuse à TOUS les appareils StreetPhare connectés.
//
// Le serveur relay agit comme un "super-pair" qui couvre la zone
// non couverte par BLE / Wi-Fi. Le transport utilise WebSocket
// (full-duplex) avec reconnexion automatique.
//
// FIX v3.3.0 — Bypass GuaranteeChannel via dart:io WebSocket direct
//
//   web_socket_channel 3.x introduit deux couches de wrapping sur Android :
//     1. AdapterWebSocketChannel  (adapte package:web_socket → dart:io sink)
//     2. GuaranteeChannel         (stream_channel — garantit l'ordre des events)
//
//   Sur Android, le handshake TCP/TLS/WS produit parfois des Ping frames
//   RFC 6455 (opcode 0x9) émis par le serveur Node.js/ws ou par Caddy.
//   Ces frames de contrôle traversent AdapterWebSocketChannel, qui les
//   traite comme données, déclenchant _GuaranteeSink.close() → onDone
//   immédiat (code 1006) exactement 2ms après le message "welcome".
//
//   Solution : utiliser dart:io WebSocket.connect() DIRECTEMENT, enveloppé
//   dans IOWebSocketChannel (web_socket_channel/io.dart). Ce chemin court-
//   circuite complètement GuaranteeChannel et AdapterWebSocketChannel. La
//   gestion native des Ping/Pong/Close frames est assurée par dart:io, qui
//   répond automatiquement aux Pings avec des Pongs sans les exposer comme
//   données applicatives.
//
//   Avantages de cette approche vs downgrade 2.4.0 :
//     - Compatibilité avec web_socket_channel 3.x conservée.
//     - API sink.add() / stream.listen() identique.
//     - Pas besoin de .ready (WebSocket.connect() est un Future — le
//       handshake est terminé quand le Future se résout).
//     - pingInterval: null désactive les pings automatiques dart:io pour
//       éviter toute interférence avec les pings applicatifs du serveur.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

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

  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;
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
    // _connect() est async — on ne l'await pas pour ne pas bloquer
    // le démarrage des autres transports.
    unawaited(_connect());
  }

  /// Établit la connexion WebSocket via dart:io WebSocket directement.
  ///
  /// FIX v3.3.0 — Court-circuit de GuaranteeChannel/AdapterWebSocketChannel :
  ///   `WebSocket.connect()` est un Future qui se résout APRÈS completion du
  ///   handshake TCP+TLS+WS (code 101 Switching Protocols reçu). À ce stade,
  ///   la connexion est pleinement établie et les Ping frames de contrôle sont
  ///   gérés nativement par dart:io (réponse Pong automatique, invisible pour
  ///   le code applicatif). On enveloppe ensuite dans IOWebSocketChannel pour
  ///   garder l'API sink/stream standard.
  Future<void> _connect() async {
    if (_disposed) return;
    if (kDebugMode) debugPrint('[Relay] → tentative connexion à $relayUrl');

    WebSocket? socket;
    try {
      // WebSocket.connect() complète SEULEMENT quand le handshake 101 est reçu.
      // pingInterval: null = pas de pings automatiques dart:io (on évite toute
      // interférence entre les pings natifs RFC 6455 et les heartbeats applicatifs).
      socket = await WebSocket.connect(
        relayUrl,
        // ignore: avoid_redundant_argument_values
        headers: const <String, dynamic>{},
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Relay] → connect error: $e\n$st');
      }
      _scheduleReconnect();
      return;
    }

    // Vérifie que le transport n'a pas été disposé pendant le await.
    if (_disposed || !_started) {
      try {
        await socket.close();
      } catch (_) {}
      return;
    }

    // Désactiver les pings automatiques dart:io (ils peuvent causer
    // des interférences si le serveur envoie ses propres pings RFC 6455).
    // Sur dart:io, la propriété pingInterval est accessible après connect().
    try {
      socket.pingInterval = null;
    } catch (_) {
      // Ignoré : certaines versions de dart:io ne supportent pas
      // la modification après connexion — ce n'est pas bloquant.
    }

    // Enveloppe dans IOWebSocketChannel pour l'API sink/stream standard.
    // IOWebSocketChannel utilise dart:io WebSocket directement, sans
    // GuaranteeChannel ni AdapterWebSocketChannel.
    _channel = IOWebSocketChannel(socket);
    _reconnectAttempts = 0;
    _reconnecting = false;

    if (kDebugMode) {
      debugPrint(
          '[Relay] → ws connecté à $relayUrl (via dart:io WebSocket direct)');
    }

    // Écoute du stream — sûr car le handshake est déjà terminé
    // (WebSocket.connect() est un Future qui attend le 101).
    _sub = _channel!.stream.listen(
      (data) {
        // ═══ PROTOCOL ERROR GUARD (Bug fix: code 1002) ═══════════════
        // Si un listener du _incomingController (ex: NetworkCoordinator)
        // throw une exception non attrapée, elle remonte comme erreur
        // sur le stream WebSocket natif → dart:io ferme la connexion avec
        // le code 1002 (Protocol Error). On wrappe l'intégralité du
        // listener pour intercepter TOUTE exception avant qu'elle
        // n'atteigne la couche dart:io.
        try {
          if (kDebugMode) {
            debugPrint('[Relay] ← ws message reçu (${data.runtimeType})');
          }
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
          } else {
            if (kDebugMode) {
              debugPrint(
                  '[Relay] ← type inattendu ignoré: ${data.runtimeType}');
            }
          }

          if (heartbeat > Duration.zero) {
            _heartbeatTimer?.cancel();
            _startHeartbeat();
          }
        } catch (e, st) {
          // On intercepte toute exception pour éviter le code 1002.
          // L'erreur est loggée mais ne remonte PAS vers dart:io WebSocket.
          if (kDebugMode) {
            debugPrint('[Relay] ⚠ exception interceptée dans le listener '
                '(protégée du code 1002): $e\n$st');
          }
        }
      },
      onError: (Object err) {
        if (kDebugMode) {
          debugPrint(
              '[Relay] ⚠ ws stream error: $err (type: ${err.runtimeType})');
        }
        // L'erreur sera suivie de onDone — on laisse onDone gérer
        // la reconnexion.
      },
      onDone: () {
        final code = socket?.closeCode;
        final reason = socket?.closeReason;
        if (kDebugMode) {
          debugPrint('[Relay] ⚠ ws fermé (code=$code, reason=$reason)');
        } else {
          debugPrint('[Relay] ws fermé (code=$code)');
        }
        _cleanupAndReconnect();
      },
    );

    if (heartbeat > Duration.zero) {
      _startHeartbeat();
    }
  }

  /// Planifie une reconnexion (utilisé après échec connect ET après onDone).
  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sub?.cancel();
    _sub = null;
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
    _sub?.cancel();
    _sub = null;
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
    await _channel?.sink.close();
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
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Relay] Erreur close channel (dispose): $e');
      }
    }
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
