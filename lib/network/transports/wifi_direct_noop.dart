// lib/network/transports/wifi_direct_noop.dart
import '../p2p_mesh_service.dart';

class WifiDirectMeshTransport implements MeshTransport {
  WifiDirectMeshTransport({String? peerId});

  @override
  String get name => 'wifi_noop';
  @override
  bool get isAvailable => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> broadcast(String payload) async {}
  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {}
  @override
  Stream<String> get incoming => const Stream.empty();
  @override
  void dispose() {}
}
