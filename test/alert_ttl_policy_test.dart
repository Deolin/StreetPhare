// test/alert_ttl_policy_test.dart
//
// Tests complémentaires de la politique de TTL différenciée (Phase 2).
// Couvre les cas limites (vivant/expiré, instant d'expiration) et les
// chemins non couverts par core_auth_test.dart (isAlertAlive, expiryInstant,
// ttlForReport, isMobileAlertType).

import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/database/alert_ttl_policy.dart';
import 'package:flutter_test/flutter_test.dart';

Alert _alert(AlertType type, DateTime createdAt) => Alert(
      id: 'alert-1',
      ephemeralUserId: 'ephemeral-1',
      signature: 'sig',
      type: type,
      latitude: 50.0,
      longitude: 4.0,
      createdAt: createdAt,
    );

void main() {
  group('AlertTtlPolicy — TTL par identifiant ReportType', () {
    test('types mobiles → 10 min', () {
      expect(
          AlertTtlPolicy.ttlForReport('barrages'), const Duration(minutes: 10));
      expect(AlertTtlPolicy.ttlForReport('groupes_casseurs'),
          const Duration(minutes: 10));
      expect(
          AlertTtlPolicy.ttlForReport('dangers'), const Duration(minutes: 10));
    });

    test('types statiques → 1 min', () {
      expect(
          AlertTtlPolicy.ttlForReport('policiers'), const Duration(minutes: 1));
      expect(AlertTtlPolicy.ttlForReport('autopompes'),
          const Duration(minutes: 1));
      expect(AlertTtlPolicy.ttlForReport('nasses'), const Duration(minutes: 1));
    });

    test('identifiant inconnu → fallback mobile (10 min)', () {
      expect(
          AlertTtlPolicy.ttlForReport('inconnu'), const Duration(minutes: 10));
    });
  });

  group('AlertTtlPolicy — classification AlertType', () {
    test('isMobileAlertType pour les types mobiles', () {
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.barrage), isTrue);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.casseurs), isTrue);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.danger), isTrue);
    });

    test('isMobileAlertType → false pour statiques, panic, density', () {
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.policiers), isFalse);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.autopompes), isFalse);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.panic), isFalse);
      expect(AlertTtlPolicy.isMobileAlertType(AlertType.density), isFalse);
    });
  });

  group('AlertTtlPolicy — vivacité et expiration', () {
    final createdAt = DateTime.utc(2026, 1, 1, 12, 0);

    test('alerte mobile vivante jusqu\'à 10 min (exclus)', () {
      final alert = _alert(AlertType.barrage, createdAt);
      expect(
        AlertTtlPolicy.isAlertAlive(alert,
            now: DateTime.utc(2026, 1, 1, 12, 9, 59)),
        isTrue,
      );
      expect(
        AlertTtlPolicy.isAlertAlive(alert,
            now: DateTime.utc(2026, 1, 1, 12, 10, 0)),
        isFalse,
      );
    });

    test('alerte statique expire après 1 min', () {
      final alert = _alert(AlertType.policiers, createdAt);
      expect(
        AlertTtlPolicy.isAlertAlive(alert,
            now: DateTime.utc(2026, 1, 1, 12, 0, 59)),
        isTrue,
      );
      expect(
        AlertTtlPolicy.isAlertAlive(alert,
            now: DateTime.utc(2026, 1, 1, 12, 1, 1)),
        isFalse,
      );
    });

    test('expiryInstant = createdAt + ttl du type', () {
      final alert = _alert(AlertType.policiers, createdAt);
      expect(
        AlertTtlPolicy.expiryInstant(alert),
        createdAt.add(const Duration(minutes: 1)),
      );
    });
  });
}
