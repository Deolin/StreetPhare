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

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../p2p_mesh_service.dart';

/// Transport relay sur Internet (WebSocket).
class RelayMeshTransport implements MeshTransport {
  RelayMeshTransport({
    required this.relayUrl,
    this.heartbeat = const Duration(seconds: 20),
    String? peerId,
  }) : _peerId = peerId ?? _generateRandomPeerId();

  /// URL WebSocket du relay (ex: wss://relay.streetphare.org/mesh).
  final String relayUrl;

  /// Identifiant de session anonyme stable, inclus dans les
  /// pings pour permettre la déduplication côté serveur/pairs.
  final String _peerId;

  String get peerId => _peerId;

  final Duration heartbeat;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  /// Backoff exponentiel plafonné à 60s (identique à WebSocketTransport).
  Duration get _nextRetryDelay {
    final seconds = (1 << _reconnectAttempts).clamp(2, 60);
    return Duration(seconds: seconds);
  }

  final _incomingController = StreamController<String>.broadcast();

  @override
  String get name => 'relay';

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  bool get isAvailable {
    // dépend d'Internet, géré en interne
    return true;
  }

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));

      // web_socket_channel ≥ 3.0 : les erreurs de handshake (ex. serveur
      // absent, upgrade HTTP refusé) arrivent sur le Future `ready` et NON
      // sur le stream. Sans ce catchError, elles deviennent une
      // "Unhandled Exception" qui fait crasher la zone Dart.
      _channel!.ready.then<void>((_) {
        // ✅ Reset du backoff UNIQUEMENT si le handshake réussit.
        //    Avant ce fix, _reconnectAttempts était remis à 0 trop tôt
        //    dans start(), ce qui annulait le backoff exponentiel et
        //    provoquait une boucle de reconnexion à 2s fixes.
        _reconnectAttempts = 0;
        if (kDebugMode) debugPrint('[Relay] ws connecté à $relayUrl');
      }).catchError((Object err, StackTrace st) {
        if (kDebugMode) debugPrint('[Relay] ws handshake error: $err');
        _scheduleReconnect();
      });

      _sub = _channel!.stream.listen(
        (data) {
          if (data is String) {
            _incomingController.add(data);
          } else if (data is List<int>) {
            _incomingController.add(utf8.decode(data));
          }
        },
        onError: (Object err) {
          if (kDebugMode) debugPrint('[Relay] ws stream error: $err');
          _scheduleReconnect();
        },
        onDone: () {
          if (kDebugMode) debugPrint('[Relay] ws fermé');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
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
          // Si le ping échoue, la connexion est probablement morte.
          // On planifie une reconnexion.
          _scheduleReconnect();
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Relay] connect error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (!_started || _disposed) return;
    // Évite la planification multiple si un timer est déjà actif.
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;
    final delay = _nextRetryDelay;
    if (kDebugMode) {
      debugPrint(
          '[Relay] reconnexion dans ${delay.inSeconds}s (essai #$_reconnectAttempts)');
    }
    _reconnectTimer = Timer(delay, _connect);
  }

  @override
  Future<void> stop() async {
    _started = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
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
    // Le relay distribue à tous → broadcast.
    await broadcast(payload);
  }

  /// Libère les ressources internes : timers, WebSocket, StreamController.
  ///
  /// Après appel à [dispose], l'instance est inutilisable.
  @override
  void dispose() {
    _disposed = true;
    _started = false;
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

  /// Génère un peerId anonyme stable. En pratique, on injecte
  /// l'`ephemeralUserId` du `NetworkCoordinator` (cf. bootstrap).
  static String _generateRandomPeerId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'relay-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
