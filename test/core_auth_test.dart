// test/core_auth_test.dart
//
// Tests de la couche d'authenticité et d'identité éphémère.
//
// Vérifie :
//   - La rotation d'UUID éphémères
//   - La validation du cycle de vie des alertes (TTL, consensus,
//     statuts pending/active/rejected)
//   - La sérialisation/désérialisation JSON conforme au contrat
//     serveur Node.js

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/database/alert_ttl_policy.dart';
import 'package:flutter_streetphare/database/alert_visibility_policy.dart';

void main() {
  group('AlertModel — Cycle de vie', () {
    late Alert baseAlert;

    setUp(() {
      baseAlert = Alert(
        id: 'a-001',
        ephemeralUserId: 'euid-abc',
        signature: 'sig-xyz',
        type: AlertType.barrage,
        latitude: 50.4762,
        longitude: 4.5422,
        description: 'Barrage filtrant Place Albert 1er',
      );
    });

    test('statut initial = pending', () {
      expect(baseAlert.status, AlertStatus.pending);
    });

    test('TTL par défaut = 24 heures', () {
      expect(baseAlert.ttlHours, 24);
      final expectedExpiry =
          baseAlert.createdAt.add(const Duration(hours: 24));
      expect(baseAlert.expiresAt, expectedExpiry);
    });

    test('isExpired renvoie false pour une alerte fraîche', () {
      expect(baseAlert.isExpired(), isFalse);
    });

    test('isExpired renvoie true 25h plus tard', () {
      final future = baseAlert.createdAt.add(const Duration(hours: 25));
      expect(baseAlert.isExpired(future), isTrue);
    });

    test('consensus nécessite ≥3 confirmations', () {
      expect(baseAlert.isValidatedByConsensus, isFalse);
      baseAlert.addConfirmation('peer-1');
      baseAlert.addConfirmation('peer-2');
      // 2 confirmations → pas encore actif
      expect(baseAlert.isValidatedByConsensus, isFalse);
      expect(baseAlert.status, AlertStatus.pending);
    });

    test('3 confirmations passent l\'alerte à active', () {
      baseAlert.addConfirmation('peer-1');
      baseAlert.addConfirmation('peer-2');
      final becameActive = baseAlert.addConfirmation('peer-3');
      expect(becameActive, isTrue);
      expect(baseAlert.isValidatedByConsensus, isTrue);
      expect(baseAlert.status, AlertStatus.active);
    });

    test('confirmation en double ne compte pas', () {
      baseAlert.addConfirmation('peer-1');
      baseAlert.addConfirmation('peer-1'); // doublon
      baseAlert.addConfirmation('peer-2');
      expect(baseAlert.isValidatedByConsensus, isFalse);
      expect(baseAlert.confirmations.length, 2);
    });

    test('rejet explicite change le statut en rejected', () {
      baseAlert.status = AlertStatus.rejected;
      expect(baseAlert.status, AlertStatus.rejected);
    });

    test('toJson() produit les clés du contrat serveur', () {
      final json = baseAlert.toJson();
      expect(json['id'], 'a-001');
      expect(json['reporter_id'], 'euid-abc');
      expect(json['type'], 'barrage');
      expect(json['lat'], 50.4762);
      expect(json['lon'], 4.5422);
      expect(json['description'], 'Barrage filtrant Place Albert 1er');
      expect(json['status'], 'pending');
      expect(json['confirmations'], isEmpty);
      expect(json.containsKey('timestamp'), isTrue);
      expect(json.containsKey('ttl_hours'), isTrue);
      expect(json.containsKey('signature'), isTrue);
    });

    test('fromJson() reconstruit l\'alerte depuis le format serveur', () {
      final json = {
        'id': 'a-001',
        'reporter_id': 'euid-abc',
        'type': 'barrage',
        'lat': 50.4762,
        'lon': 4.5422,
        'status': 'active',
        'confirmations': ['peer-1', 'peer-2', 'peer-3'],
        'timestamp': '2026-07-14T10:00:00.000Z',
        'description': 'Test',
        'signature': 'sig-xyz',
      };
      final alert = Alert.fromJson(json);
      expect(alert.id, 'a-001');
      expect(alert.ephemeralUserId, 'euid-abc');
      expect(alert.type, AlertType.barrage);
      expect(alert.latitude, 50.4762);
      expect(alert.longitude, 4.5422);
      expect(alert.status, AlertStatus.active);
      expect(alert.confirmations.length, 3);
      expect(alert.isValidatedByConsensus, isTrue);
    });

    test('fromJson() tolère un champ type inconnu → autre', () {
      final json = {
        'id': 'x',
        'reporter_id': 'x',
        'type': 'type_inconnu_zzz',
        'lat': 0.0,
        'lon': 0.0,
        'timestamp': '2026-07-14T10:00:00.000Z',
      };
      final alert = Alert.fromJson(json);
      expect(alert.type, AlertType.autre);
    });

    test('toCompact + fromCompact = identité', () {
      baseAlert.addConfirmation('peer-1');
      final compact = baseAlert.toCompact();
      final restored = Alert.fromCompact(compact);
      expect(restored.id, baseAlert.id);
      expect(restored.type, baseAlert.type);
      expect(restored.latitude, baseAlert.latitude);
      expect(restored.confirmations.length, 1);
    });
  });

  group('AlertTtlPolicy — Politique de TTL', () {
    test('types mobiles (barrage, casseurs, danger) → 10 min', () {
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.barrage), isTrue);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.casseurs), isTrue);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.danger), isTrue);
    });

    test('types statiques (policiers, autopompes, filtre) → 1 min', () {
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.policiers), isFalse);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.autopompes), isFalse);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.filtre), isFalse);
    });

    test('ttlForAlertType retourne la bonne Duration', () {
      expect(
        AlertTtlPolicy.ttlForAlertType(AlertType.barrage),
        const Duration(minutes: 10),
      );
      expect(
        AlertTtlPolicy.ttlForAlertType(AlertType.policiers),
        const Duration(minutes: 1),
      );
    });
  });

  group('AlertVisibilityPolicy — Visibilité', () {
    test('alerte active + non expirée = visible', () {
      final alert = Alert(
        id: 'v-001',
        ephemeralUserId: 'e',
        signature: 's',
        type: AlertType.barrage,
        latitude: 50.0,
        longitude: 4.0,
      );
      alert.addConfirmation('p1');
      alert.addConfirmation('p2');
      alert.addConfirmation('p3');
      expect(alert.status, AlertStatus.active);

      final visible = AlertVisibilityPolicy.isVisible(alert);
      expect(visible, isTrue);
    });

    test('alerte pending = invisible', () {
      final alert = Alert(
        id: 'v-002',
        ephemeralUserId: 'e',
        signature: 's',
        type: AlertType.danger,
        latitude: 50.0,
        longitude: 4.0,
      );
      expect(alert.status, AlertStatus.pending);
      final visible = AlertVisibilityPolicy.isVisible(alert);
      expect(visible, isFalse);
    });

    test('alerte rejected = invisible', () {
      final alert = Alert(
        id: 'v-003',
        ephemeralUserId: 'e',
        signature: 's',
        type: AlertType.barrage,
        latitude: 50.0,
        longitude: 4.0,
        status: AlertStatus.rejected,
      );
      final visible = AlertVisibilityPolicy.isVisible(alert);
      expect(visible, isFalse);
    });
  });
}