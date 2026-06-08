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

import 'package:flutter/foundation.dart';

import '../p2p_mesh_service.dart';

/// Transport Wi-Fi (LAN multicast).
class WifiDirectMeshTransport implements MeshTransport {
  WifiDirectMeshTransport({
    this.multicastAddress = '239.255.42.42',
    this.port = 42424,
  });

  final String multicastAddress;
  final int port;

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
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux;
  }

  @override
  Future<void> start() async {
    if (_socket != null) return;

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
      debugPrint('[WiFi] multicast listening on $multicastAddress:$port');
    }
  }

  @override
  Future<void> stop() async {
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
    try {
      final bytes = utf8.encode(payload);
      _socket!.send(bytes, _mcastGroup!, port);
    } catch (e) {
      if (kDebugMode) debugPrint('[WiFi] send error: $e');
    }
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    // En multicast, "sendTo" ≡ broadcast (les pairs filtrent eux-mêmes).
    await broadcast(payload);
  }

  /// Libère les ressources internes (canal broadcast).
  void dispose() {
    _incomingController.close();
  }
}
