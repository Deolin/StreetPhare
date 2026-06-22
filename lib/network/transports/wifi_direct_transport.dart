// lib/network/transports/wifi_direct_transport.dart
//
// Implémentation Wi-Fi Direct / LAN du contrat MeshTransport.
//
// Stratégie principale : UDP multicast sur le réseau local.
//   - écoute sur 239.255.42.42:42424 (plage d'admin scoping)
//   - TTL = 1 (anti-storm, on ne déborde pas du LAN)
//   - les pairs sur le même LAN reçoivent les alertes et les
//     réémettent à leur tour (gossip)
//
// Une autre option (à venir) : `nearby_connections` pour le
// Wi-Fi Direct natif sur Android.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../p2p_mesh_service.dart';

/// Transport Wi-Fi (LAN multicast).
///
/// Implémente [WidgetsBindingObserver] pour suspendre la socket UDP
/// lorsque l'application passe en arrière-plan (Android 15+ coupe les
/// privilèges d'émission réseau → SocketException errno=1).
class WifiDirectMeshTransport with WidgetsBindingObserver implements MeshTransport {
  WifiDirectMeshTransport({
    this.multicastAddress = '239.255.42.42',
    this.port = 42424,
    String? peerId,
  }) : _peerId = peerId ?? _generateRandomPeerId();

  final String multicastAddress;
  final int port;

  /// Identifiant de session anonyme stable, inclus dans les
  /// pings multicast pour permettre la déduplication côté pairs.
  final String _peerId;

  String get peerId => _peerId;

  RawDatagramSocket? _socket;
  InternetAddress? _mcastGroup;
  StreamSubscription? _sub;
  final _incomingController = StreamController<String>.broadcast();

  @override
  String get name => 'wifi';

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  bool get isAvailable {
    if (kIsWeb) return false; // UDP multicast non dispo sur le web
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  @override
  Future<void> start() async {
    if (_socket != null) return;

    // ── Enregistrement comme observateur du cycle de vie ──────────
    // Permet de suspendre/reprendre la socket UDP lors des
    // transitions app en arrière-plan / premier plan.
    WidgetsBinding.instance.addObserver(this);

    _mcastGroup = InternetAddress(multicastAddress);
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _socket!.joinMulticast(_mcastGroup!);
    // TTL = 1 pour ne pas déborder du LAN (anti-storm).
    _socket!.multicastHops = 1;

    _sub = _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram == null) return;
        try {
          final str = utf8.decode(datagram.data);
          _incomingController.add(str);
        } catch (e) {
          if (kDebugMode) debugPrint('[WiFi] decode error: $e');
        }
      }
    });

    if (kDebugMode) {
      debugPrint('[WiFi] multicast listening on $multicastAddress:$port '
          '(peerId=$peerId TTL=1)');
      debugPrint('[WiFi] ✅ Recette P2P Multicast active — '
          'Windows ↔ Android sur le LAN local (port 42424). '
          'Priorité : BLE → Wi-Fi Direct → Relay Web.');
    }
  }

  @override
  Future<void> stop() async {
    // ── Désenregistrement de l'observateur du cycle de vie ────────
    WidgetsBinding.instance.removeObserver(this);

    if (_mcastGroup != null && _socket != null) {
      try {
        _socket!.leaveMulticast(_mcastGroup!);
      } catch (_) {}
    }
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
  }

  @override
  Future<void> broadcast(String payload) async {
    if (_socket == null) return;
    // ── Protection anti-crash arrière-plan ────────────────────────
    // Android 15+ coupe les privilèges d'émission réseau quand
    // l'app passe en arrière-plan. On intercepte SocketException
    // pour éviter que l'exception ne remonte et ne tue la boucle
    // de microtâches Dart (_startMicrotaskLoop).
    try {
      final bytes = utf8.encode(payload);
      _socket!.send(bytes, _mcastGroup!, port);
    } on SocketException catch (e) {
      // Socket coupée par l'OS (errno=1 Operation not permitted).
      // On ferme silencieusement : la socket sera recréée au retour
      // au premier plan via didChangeAppLifecycleState.
      if (kDebugMode) {
        debugPrint('[WiFi] SocketException (arrière-plan probable) : $e');
      }
      // Fermeture propre pour éviter les fuites
      await _sub?.cancel();
      _sub = null;
      try { _socket?.close(); } catch (_) {}
      _socket = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[WiFi] send error: $e');
    }
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    // En multicast, "sendTo" ≡ broadcast (les pairs filtrent eux-mêmes).
    await broadcast(payload);
  }

  // ── WidgetsBindingObserver : gestion du cycle de vie ──────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint('[WiFi] AppLifecycleState → $state');
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // ── Suspension de la socket UDP ────────────────────────────
      // Android 15+ coupe les privilèges réseau en arrière-plan.
      // On ferme la socket pour éviter SocketException errno=1.
      _suspendSocket();
    } else if (state == AppLifecycleState.resumed) {
      // ── Reprise de la socket UDP ───────────────────────────────
      // On recrée la socket multicast au retour au premier plan.
      _resumeSocket();
    }
  }

  /// Ferme la socket UDP proprement (appelé en arrière-plan).
  void _suspendSocket() {
    if (_socket == null) return;
    if (kDebugMode) {
      debugPrint('[WiFi] Suspension socket UDP (arrière-plan)');
    }
    _sub?.cancel();
    _sub = null;
    try { _socket?.close(); } catch (_) {}
    _socket = null;
  }

  /// Recrée la socket UDP (appelé au retour au premier plan).
  Future<void> _resumeSocket() async {
    if (_socket != null) return;
    if (kDebugMode) {
      debugPrint('[WiFi] Reprise socket UDP (premier plan)');
    }
    try {
      await start();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WiFi] Échec reprise socket : $e');
      }
    }
  }

  /// Libère les ressources internes (canal broadcast).
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingController.close();
  }

  /// Génère un peerId anonyme stable. En pratique, on injecte
  /// l'`ephemeralUserId` du `NetworkCoordinator` (cf. bootstrap).
  static String _generateRandomPeerId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return 'wifi-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}