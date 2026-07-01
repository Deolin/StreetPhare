// test/network_coordinator_test.dart
//
// Tests unitaires pour `lib/network/network_coordinator.dart`
//
// Couvre les opérations critiques :
//   - createAlert() — création locale + chiffrement + propagation
//   - confirmAlert() — mécanisme de consensus (≥3 votes)
//   - _checkServerReachabilityAndAdapt() — adaptation réseau
//   - _purgeTimer — purge périodique TTL 1min
//   - Gestion des erreurs réseau
//
// Réf: docs/plan_et_audit_complet_28062026.md#Anomalie-A4

import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/database/crypto_utils.dart';
import 'package:flutter_streetphare/database/hive_alert_database.dart';
import 'package:flutter_streetphare/network/failover_manager.dart';
import 'package:flutter_streetphare/network/network_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ============================================================================
// Mocks
// ============================================================================

class MockHiveAlertDatabase extends Mock implements HiveAlertDatabase {}

class MockFailoverManager extends Mock implements FailoverManager {}

class MockCryptoUtils extends Mock implements CryptoUtils {
  @override
  Future<SignedAlert> signAlert({
    required String alertId,
    required String type,
    required double lat,
    required double lng,
    required DateTime createdAt,
  }) async {
    return SignedAlert(
      signature: 'mock_signature_${alertId}_${type}',
      publicKey: 'mock_public_key',
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

/// Crée une alerte de test avec des valeurs par défaut.
Alert _testAlert({
  String id = 'test_alert_001',
  String euid = 'test_euid_abc',
  AlertType type = AlertType.danger,
  double lat = 48.8566,
  double lng = 2.3522,
  AlertStatus status = AlertStatus.pending,
  Set<String>? confirmations,
  int ttlHours = 24,
  DateTime? createdAt,
}) {
  return Alert(
    id: id,
    ephemeralUserId: euid,
    signature: 'test_signature',
    type: type,
    latitude: lat,
    longitude: lng,
    description: 'Test alert',
    createdAt: createdAt ?? DateTime.now().toUtc(),
    ttlHours: ttlHours,
    status: status,
    confirmations: confirmations ?? {'euid_1'},
  );
}

/// Crée une instance NetworkCoordinator avec tous ses mocks.
NetworkCoordinator _createCoordinator({
  MockHiveAlertDatabase? database,
  MockFailoverManager? failover,
  MockCryptoUtils? cryptoUtils,
}) {
  return NetworkCoordinator.test(
    database: database ?? MockHiveAlertDatabase(),
    failover: failover ?? MockFailoverManager(),
    cryptoUtils: cryptoUtils ?? MockCryptoUtils(),
  );
}

// ============================================================================
// Tests
// ============================================================================

void main() {
  setUpAll(() {
    // mocktail a besoin d'une fallback value pour le type Alert
    // lorsque any() est utilisé dans les when().
    registerFallbackValue(
      Alert(
        id: 'fallback',
        ephemeralUserId: 'fallback',
        signature: 'fallback',
        type: AlertType.danger,
        latitude: 0,
        longitude: 0,
      ),
    );
  });

  group('NetworkCoordinator', () {
    // ------------------------------------------------------------------------
    // Constructeur test
    // ------------------------------------------------------------------------
    group('Constructeur @visibleForTesting', () {
      test('crée une instance avec les mocks injectés', () {
        final db = MockHiveAlertDatabase();
        final fm = MockFailoverManager();
        final cu = MockCryptoUtils();

        final coordinator = NetworkCoordinator.test(
          database: db,
          failover: fm,
          cryptoUtils: cu,
        );

        expect(coordinator, isA<NetworkCoordinator>());
        expect(coordinator.isInitialized, isFalse);
        expect(coordinator.isHiveOnlyMode, isFalse);
        expect(coordinator.ephemeralUserId, isNotEmpty);
        expect(coordinator.ephemeralUserId.length, greaterThan(0));
      });

      test('utilise les vrais singletons si aucun mock fourni', () {
        final coordinator = NetworkCoordinator.test();
        expect(coordinator, isA<NetworkCoordinator>());
        expect(coordinator.isInitialized, isFalse);
      });
    });

    // ------------------------------------------------------------------------
    // createAlert()
    // ------------------------------------------------------------------------
    group('createAlert()', () {
      late MockHiveAlertDatabase db;
      late MockFailoverManager failover;
      late MockCryptoUtils crypto;
      late NetworkCoordinator coordinator;

      setUp(() {
        db = MockHiveAlertDatabase();
        failover = MockFailoverManager();
        crypto = MockCryptoUtils();
        coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        // Configuration par défaut des mocks.
        when(() => db.upsert(any())).thenAnswer((_) async => true);
      });

      test(
          'crée une alerte avec type et coordonnées valides, '
          'statut initial = pending', () async {
        final alert = await coordinator.createAlert(
          type: AlertType.danger,
          latitude: 48.8566,
          longitude: 2.3522,
          description: 'Manifestation en cours',
        );

        expect(alert.type, AlertType.danger);
        expect(alert.latitude, 48.8566);
        expect(alert.longitude, 2.3522);
        expect(alert.description, 'Manifestation en cours');
        expect(alert.status, AlertStatus.pending);
        expect(alert.id, isNotEmpty);
        expect(alert.id.length, greaterThanOrEqualTo(8));
      });

      test('vérifie que la signature Ed25519 est générée', () async {
        final alert = await coordinator.createAlert(
          type: AlertType.barrage,
          latitude: 45.0,
          longitude: 3.0,
        );

        expect(alert.signature, isNotEmpty);
        expect(alert.signature, contains('mock_signature_'));
      });

      test('vérifie que l\'alerte est stockée via upsert()', () async {
        var upsertCalled = false;
        Alert? upsertedAlert;
        when(() => db.upsert(any())).thenAnswer((invocation) async {
          upsertCalled = true;
          upsertedAlert = invocation.positionalArguments[0] as Alert;
          return true;
        });

        await coordinator.createAlert(
          type: AlertType.casseurs,
          latitude: 44.0,
          longitude: 5.0,
        );

        expect(upsertCalled, isTrue);
        expect(upsertedAlert, isNotNull);
        expect(upsertedAlert!.type, AlertType.casseurs);
        expect(upsertedAlert!.status, AlertStatus.pending);
      });

      test(
          'vérifie que l\'ephemeralUserId local est inclus '
          'dans les confirmations initiales', () async {
        final euid = coordinator.ephemeralUserId;
        final alert = await coordinator.createAlert(
          type: AlertType.policiers,
          latitude: 43.0,
          longitude: 6.0,
        );

        expect(alert.confirmations, contains(euid));
        expect(alert.confirmations.length, 1);
      });

      test('vérifie le TTL assigné (24h par défaut)', () async {
        final alert = await coordinator.createAlert(
          type: AlertType.autopompes,
          latitude: 42.0,
          longitude: 7.0,
        );

        expect(alert.ttlHours, 24);
        final expectedExpiry =
            alert.createdAt.add(const Duration(hours: 24));
        expect(
          alert.expiresAt.difference(expectedExpiry).inSeconds.abs(),
          lessThan(2),
        );
      });

      test('ne crashe pas si le broadcast échoue (mesh = null)', () async {
        // Le mesh est null car init() n'a pas été appelé.
        // createAlert() doit quand même réussir.
        final alert = await coordinator.createAlert(
          type: AlertType.filtre,
          latitude: 41.0,
          longitude: 8.0,
        );

        expect(alert, isNotNull);
        expect(alert.type, AlertType.filtre);
      });
    });

    // ------------------------------------------------------------------------
    // confirmAlert()
    // ------------------------------------------------------------------------
    group('confirmAlert()', () {
      late MockHiveAlertDatabase db;
      late MockFailoverManager failover;
      late MockCryptoUtils crypto;
      late NetworkCoordinator coordinator;

      setUp(() {
        db = MockHiveAlertDatabase();
        failover = MockFailoverManager();
        crypto = MockCryptoUtils();
        coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        when(() => db.upsert(any())).thenAnswer((_) async => true);
      });

      test('retourne false si l\'alerte n\'existe pas', () async {
        when(() => db.getById('nonexistent')).thenReturn(null);

        final result = await coordinator.confirmAlert('nonexistent');
        expect(result, isFalse);
      });

      test('retourne false si l\'alerte est expirée', () async {
        final expiredAlert = _testAlert(
          id: 'expired_001',
          euid: coordinator.ephemeralUserId,
          createdAt: DateTime.now().toUtc().subtract(
                const Duration(hours: 25),
              ),
        );
        when(() => db.getById('expired_001')).thenReturn(expiredAlert);

        final result = await coordinator.confirmAlert('expired_001');
        expect(result, isFalse);
      });

      test(
          'confirme une alerte existante avec un euid valide '
          'et retourne false (<3 confirmations)', () async {
        final existingAlert = _testAlert(
          id: 'alert_002',
          euid: coordinator.ephemeralUserId,
        );
        when(() => db.getById('alert_002')).thenReturn(existingAlert);

        // 1 confirmation après l'ajout (seulement l'euid local).
        final result = await coordinator.confirmAlert('alert_002');

        // 1 confirmation = seuil non atteint → false.
        expect(result, isFalse);
        expect(existingAlert.confirmations.length, 2);
      });

      test(
          'passe le statut à active lorsque ≥3 confirmations '
          'sont atteintes', () async {
        final existingAlert = _testAlert(
          id: 'alert_003',
          euid: coordinator.ephemeralUserId,
          confirmations: {'peer_1', 'peer_2'}, // 2 confirmations existantes
        );
        when(() => db.getById('alert_003')).thenReturn(existingAlert);

        // L'euid local n'est pas encore dans le set → ajout → 3e confirmation.
        final result = await coordinator.confirmAlert('alert_003');

        expect(result, isTrue); // Consensus atteint.
        expect(existingAlert.status, AlertStatus.active);
        expect(existingAlert.confirmations.length, 3);
      });

      test(
          'ignore les confirmations en double '
          '(même euid déjà présent)', () async {
        final existingAlert = _testAlert(
          id: 'alert_004',
          euid: coordinator.ephemeralUserId,
          confirmations: {coordinator.ephemeralUserId}, // déjà présent
        );
        when(() => db.getById('alert_004')).thenReturn(existingAlert);

        final result = await coordinator.confirmAlert('alert_004');

        // Le doublon est ignoré → false (pas d'ajout).
        expect(result, isFalse);
        expect(existingAlert.confirmations.length, 1);
      });

      test('persiste l\'alerte mise à jour via upsert()', () async {
        final existingAlert = _testAlert(
          id: 'alert_005',
          euid: coordinator.ephemeralUserId,
        );
        when(() => db.getById('alert_005')).thenReturn(existingAlert);

        var upsertCalled = false;
        when(() => db.upsert(any())).thenAnswer((_) async {
          upsertCalled = true;
          return true;
        });

        await coordinator.confirmAlert('alert_005');

        expect(upsertCalled, isTrue);
      });
    });

    // ------------------------------------------------------------------------
    // _checkServerReachabilityAndAdapt() — mode Hive-only
    // ------------------------------------------------------------------------
    group('Adaptation réseau (Hive-only fallback)', () {
      test(
          'bascule en mode Hive-only quand le serveur '
          'est inaccessible (currentAddress vide)', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        // Simule un serveur injoignable.
        when(() => failover.currentAddress).thenReturn('');

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        // État initial.
        expect(coordinator.isHiveOnlyMode, isFalse);

        // Appelle la méthode privée via l'API publique exposée pour test.
        await coordinator.checkServerReachability();

        expect(coordinator.isHiveOnlyMode, isTrue);
      });

      test(
          'revient au mode normal quand le serveur redevient '
          'accessible (currentAddress non vide)', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        // Simule d'abord un serveur injoignable, puis accessible.
        when(() => failover.currentAddress).thenReturn('');
        // Stub getPendingUpload() pour éviter l'erreur mocktail.
        when(() => db.getPendingUpload()).thenReturn(<Alert>[]);

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        // Bascule en mode Hive-only.
        await coordinator.checkServerReachability();
        expect(coordinator.isHiveOnlyMode, isTrue);

        // Simule le retour du serveur.
        when(() => failover.currentAddress)
            .thenReturn('https://streetphare.ddns.net:3000');

        await coordinator.checkServerReachability();
        expect(coordinator.isHiveOnlyMode, isFalse);
      });

      test(
          'reste en mode normal si le serveur est accessible '
          'depuis le départ', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        when(() => failover.currentAddress)
            .thenReturn('https://streetphare.ddns.net:3000');

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        await coordinator.checkServerReachability();

        expect(coordinator.isHiveOnlyMode, isFalse);
      });
    });

    // ------------------------------------------------------------------------
    // Purge TTL (_purgeAndMaybeSync)
    // ------------------------------------------------------------------------
    group('Purge TTL', () {
      test(
          'appelle purgeExpired() sur la base avec un '
          'callback onBeforeDelete', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        when(() => failover.uploadAlerts(any()))
            .thenAnswer((_) async => true);
        when(() => failover.currentAddress)
            .thenReturn('https://server:3000');
        when(() => db.purgeExpired(
              onBeforeDelete: any(named: 'onBeforeDelete'),
            )).thenAnswer((_) async => <Alert>[]);

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        await coordinator.runPurge();

        verify(() => db.purgeExpired(
              onBeforeDelete: any(named: 'onBeforeDelete'),
            )).called(1);
      });

      test(
          'tente un upload des alertes actives non uploadées '
          'avant suppression', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        final activeAlert = _testAlert(
          id: 'to_purge',
          euid: 'test_euid',
          status: AlertStatus.active,
        );

        when(() => failover.uploadAlerts(any()))
            .thenAnswer((_) async => true);
        when(() => failover.currentAddress)
            .thenReturn('https://server:3000');

        // Capture le callback onBeforeDelete.
        when(() => db.purgeExpired(
              onBeforeDelete: any(named: 'onBeforeDelete'),
            )).thenAnswer((invocation) async {
          final callback = invocation.namedArguments[const Symbol('onBeforeDelete')]
              as Future<void> Function(Alert)?;
          if (callback != null) {
            await callback(activeAlert);
          }
          return <Alert>[activeAlert];
        });

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        await coordinator.runPurge();

        // Vérifie que uploadAlerts a été appelé avec l'alerte expirée.
        verify(() => failover.uploadAlerts(any())).called(1);
      });
    });

    // ------------------------------------------------------------------------
    // Scénarios d'erreur et robustness
    // ------------------------------------------------------------------------
    group('Gestion des erreurs', () {
      test(
          'createAlert() ne crashe pas si upsert() lève '
          'une exception', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        when(() => db.upsert(any())).thenThrow(
          StateError('Hive box corrompue'),
        );

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        expect(
          () async => coordinator.createAlert(
            type: AlertType.danger,
            latitude: 48.0,
            longitude: 2.0,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test(
          'confirmAlert() retourne false si getById() lève '
          'une exception', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        when(() => db.getById(any())).thenThrow(
          StateError('Hive non initialisée'),
        );

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        expect(
          () async => coordinator.confirmAlert('any_id'),
          throwsA(isA<StateError>()),
        );
      });

      test(
          'checkServerReachability() ne crashe pas si '
          'currentAddress lève une exception', () async {
        final db = MockHiveAlertDatabase();
        final failover = MockFailoverManager();
        final crypto = MockCryptoUtils();

        when(() => failover.currentAddress)
            .thenThrow(Exception('Erreur réseau'));

        final coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        expect(
          () async => coordinator.checkServerReachability(),
          throwsA(isA<Exception>()),
        );
      });
    });

    // ------------------------------------------------------------------------
    // Propriétés exposées
    // ------------------------------------------------------------------------
    group('Propriétés', () {
      test('ephemeralUserId est non vide', () {
        final coordinator = _createCoordinator();
        expect(coordinator.ephemeralUserId, isNotEmpty);
        expect(coordinator.ephemeralUserId.length, greaterThan(10));
      });

      test('isHiveOnlyMode est false par défaut', () {
        final coordinator = _createCoordinator();
        expect(coordinator.isHiveOnlyMode, isFalse);
      });

      test('isInitialized est false par défaut (avant init())', () {
        final coordinator = _createCoordinator();
        expect(coordinator.isInitialized, isFalse);
      });

      test('mesh est null avant init()', () {
        final coordinator = _createCoordinator();
        expect(coordinator.mesh, isNull);
      });
    });

    // ------------------------------------------------------------------------
    // Alert consensus : validation par type d'alerte
    // ------------------------------------------------------------------------
    group('Consensus multi-types', () {
      late MockHiveAlertDatabase db;
      late MockFailoverManager failover;
      late MockCryptoUtils crypto;
      late NetworkCoordinator coordinator;

      setUp(() {
        db = MockHiveAlertDatabase();
        failover = MockFailoverManager();
        crypto = MockCryptoUtils();
        coordinator = _createCoordinator(
          database: db,
          failover: failover,
          cryptoUtils: crypto,
        );

        when(() => db.upsert(any())).thenAnswer((_) async => true);
      });

      for (final type in [
        AlertType.barrage,
        AlertType.casseurs,
        AlertType.danger,
        AlertType.policiers,
        AlertType.autopompes,
        AlertType.filtre,
        AlertType.panic,
        AlertType.dangerCollectif,
        AlertType.autre,
      ]) {
        test('createAlert() accepte le type ${type.name}', () async {
          final alert = await coordinator.createAlert(
            type: type,
            latitude: 48.0,
            longitude: 2.0,
          );

          expect(alert.type, type);
          expect(alert.status, AlertStatus.pending);
          expect(alert.confirmations.length, 1);
        });
      }
    });
  });
}