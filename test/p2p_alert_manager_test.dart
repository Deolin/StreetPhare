// test/p2p_alert_manager_test.dart
//
// Tests de la couche de gestion des alertes P2P.
// Vérifie la création, la propagation et la réception d'alertes
// via le transport loopback (sans matériel BLE/Wi-Fi).

import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2P Alert — Création et propagation', () {
    test('une alerte créée localement doit avoir le statut pending', () {
      final alert = Alert(
        id: 'p2p-001',
        ephemeralUserId: 'euid-local',
        signature: 'sig-local',
        type: AlertType.danger,
        latitude: 50.4891,
        longitude: 4.5452,
      );
      expect(alert.status, AlertStatus.pending);
    });

    test(
        'une alerte reçue d\'un pair doit être désérialisable '
        'depuis le format compact', () {
      final sender = Alert(
        id: 'p2p-002',
        ephemeralUserId: 'euid-peer',
        signature: 'sig-peer',
        type: AlertType.casseurs,
        latitude: 50.4905,
        longitude: 4.5420,
      );
      sender.addConfirmation('peer-a');
      sender.addConfirmation('peer-b');

      final compact = sender.toCompact();
      final received = Alert.fromCompact(compact);

      expect(received.id, 'p2p-002');
      expect(received.type, AlertType.casseurs);
      expect(received.confirmations.length, 2);
      expect(received.status, AlertStatus.pending);
    });

    test('fusion des confirmations à la réception', () {
      final local = Alert(
        id: 'p2p-003',
        ephemeralUserId: 'euid-local',
        signature: 'sig-local',
        type: AlertType.barrage,
        latitude: 50.4742,
        longitude: 4.5349,
      );
      local.addConfirmation('peer-x');

      // Simule la réception d'une version avec 2 confirmations supplémentaires
      final remote = Alert(
        id: 'p2p-003',
        ephemeralUserId: 'euid-local',
        signature: 'sig-local',
        type: AlertType.barrage,
        latitude: 50.4742,
        longitude: 4.5349,
      );
      remote.addConfirmation('peer-y');
      remote.addConfirmation('peer-z');

      // Fusion : ajouter les confirmations du remote dans le local
      for (final c in remote.confirmations) {
        local.addConfirmation(c);
      }

      expect(local.confirmations.length, 3);
      expect(local.isValidatedByConsensus, isTrue);
      expect(local.status, AlertStatus.active);
    });

    test('consensus atteint via propagation P2P', () {
      final alert = Alert(
        id: 'p2p-004',
        ephemeralUserId: 'origin',
        signature: 'sig-origin',
        type: AlertType.policiers,
        latitude: 50.4752,
        longitude: 4.5418,
      );

      // Simulation de 3 pairs distincts qui confirment
      final peers = ['peer-1', 'peer-2', 'peer-3'];
      for (final p in peers) {
        alert.addConfirmation(p);
      }

      expect(alert.status, AlertStatus.active);
      expect(alert.isValidatedByConsensus, isTrue);
    });

    test('une alerte reçue déjà active ne change pas de statut', () {
      final alert = Alert(
        id: 'p2p-005',
        ephemeralUserId: 'origin',
        signature: 'sig-origin',
        type: AlertType.dangerCollectif,
        latitude: 50.4707,
        longitude: 4.5553,
        status: AlertStatus.active,
      );
      alert.addConfirmation('peer-extra');
      expect(alert.status, AlertStatus.active);
    });
  });

  group('P2P Alert — Sérialisation compacte', () {
    test('toCompact produit un JSON valide et minimal', () {
      final alert = Alert(
        id: 'compact-1',
        ephemeralUserId: 'eu-c1',
        signature: 'sig-c1',
        type: AlertType.danger,
        latitude: 50.0,
        longitude: 4.0,
      );
      final json = alert.toCompact();
      expect(json, contains('"id":"compact-1"'));
      expect(json, contains('"type":"danger"'));
    });

    test('fromCompact avec JSON invalide lance une exception', () {
      expect(
        () => Alert.fromCompact('{json invalide'),
        throwsA(isA<FormatException>()),
      );
    });

    test('aller-retour préserve tous les champs', () {
      final original = Alert(
        id: 'roundtrip',
        ephemeralUserId: 'eu-rt',
        signature: 'sig-rt',
        type: AlertType.panic,
        latitude: 50.4762,
        longitude: 4.5422,
        description: 'Test P2P roundtrip',
        densityValue: 42,
        ttlHours: 12,
      );
      original.addConfirmation('c1');
      original.addConfirmation('c2');

      final roundtrip = Alert.fromCompact(original.toCompact());

      expect(roundtrip.id, original.id);
      expect(roundtrip.ephemeralUserId, original.ephemeralUserId);
      expect(roundtrip.type, original.type);
      expect(roundtrip.latitude, original.latitude);
      expect(roundtrip.longitude, original.longitude);
      expect(roundtrip.description, original.description);
      expect(roundtrip.densityValue, original.densityValue);
      expect(roundtrip.ttlHours, original.ttlHours);
      expect(roundtrip.confirmations.length, original.confirmations.length);
    });
  });
}
