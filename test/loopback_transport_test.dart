// test/loopback_transport_test.dart
//
// Tests du transport maillé en boucle locale (LoopbackMeshTransport),
// utilisé exclusivement en mode DEBUG Web pour simuler des paquets P2P
// depuis le panneau d'administration sandbox.

import 'package:flutter_streetphare/network/transports/loopback_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoopbackMeshTransport', () {
    test('injectPacket émet un paquet JSON sur incoming', () async {
      final transport = LoopbackMeshTransport(peerId: 'test-peer');

      // On écoute le premier événement AVANT d'injecter.
      final first = transport.incoming.first;
      transport.injectPacket({'kind': 'alert', 'id': 'a1'});

      final raw = await first;
      expect(raw, contains('"kind":"alert"'));
      expect(raw, contains('"id":"a1"'));

      transport.dispose();
    });

    test('name et peerId sont cohérents', () {
      final transport = LoopbackMeshTransport(peerId: 'peer-42');
      expect(transport.name, 'Loopback (Web Sandbox)');
      expect(transport.peerId, 'peer-42');
      transport.dispose();
    });

    test('isAvailable est true en mode debug (contexte de test)', () {
      final transport = LoopbackMeshTransport();
      expect(transport.isAvailable, isTrue);
      transport.dispose();
    });

    test('broadcast est un no-op silencieux (ne lève pas)', () async {
      final transport = LoopbackMeshTransport();
      await transport.broadcast('{"kind":"alert"}');
      await transport.start();
      await transport.stop();
      transport.dispose();
    });
  });
}
