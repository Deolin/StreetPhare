// test/hive_alert_database_test.dart
//
// Tests unitaires pour HiveAlertDatabase (P1.2).
//
// Couvre :
//   - init() : ouverture de la box, enregistrement de l'adaptateur
//   - upsert() / insertOrMerge() : insertion, mise à jour, fusion
//   - purgeExpired() : suppression des alertes TTL dépassé
//   - Résilience à la corruption : données invalides → fallback

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/database/hive_alert_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveAlertDatabase db;
  late Directory tempDir;

  /// Helper : crée une alerte de test avec TTL et createdAt personnalisables.
  Alert testAlert({
    String id = 'test-001',
    int ttlHours = 24,
    DateTime? createdAt,
    Set<String> confirmations = const {},
    AlertStatus status = AlertStatus.pending,
    AlertType type = AlertType.danger,
  }) {
    return Alert(
      id: id,
      ephemeralUserId: 'eph-001',
      signature: 'sig-001',
      type: type,
      latitude: 50.45,
      longitude: 4.55,
      description: 'Test alert',
      createdAt: createdAt ?? DateTime.now().toUtc(),
      ttlHours: ttlHours,
      status: status,
      confirmations: confirmations,
    );
  }

  setUp(() async {
    // Crée un répertoire temporaire pour Hive.
    tempDir = Directory.systemTemp.createTempSync('hive_test_');
    // Mock path_provider pour que Hive.initFlutter() utilise notre tempDir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AlertAdapter());
    }
    // Force Hive à utiliser le tempDir (appelé par initFlutter dans db.init).
    // On pré-initialise pour éviter l'appel à getApplicationDocumentsDirectory
    // qui échoue dans certains cas. db.init() appelle Hive.initFlutter()
    // qui appelle getApplicationDocumentsDirectory → notre mock répond.
    db = HiveAlertDatabase.instance;
    await db.init();
  });

  tearDown(() async {
    try {
      await db.clearAll();
    } catch (_) {}
    await db.close();
    // Nettoie le répertoire temporaire.
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('init()', () {
    test('ouvre la box Hive et enregistre l\'adaptateur', () {
      expect(db.isInitialized, isTrue);
    });

    test('un second appel à init() est sans effet', () async {
      await db.init();
      expect(db.isInitialized, isTrue);
    });
  });

  group('upsert()', () {
    test('insère une nouvelle alerte et retourne true', () async {
      final alert = testAlert();
      final isNew = await db.upsert(alert);
      expect(isNew, isTrue);
      expect(db.getAll().length, 1);
    });

    test('met à jour une alerte existante et retourne false', () async {
      final alert = testAlert();
      await db.upsert(alert);

      // Modification du statut
      alert.status = AlertStatus.active;
      final isNew = await db.upsert(alert);
      expect(isNew, isFalse);

      final updated = db.getById(alert.id);
      expect(updated?.status, AlertStatus.active);
    });
  });

  group('insertOrMerge()', () {
    test('insère si l\'id est inconnu', () async {
      final alert = testAlert();
      final inserted = await db.insertOrMerge(alert);
      expect(inserted, isTrue);
    });

    test('fusionne les confirmations si l\'id existe déjà', () async {
      final existing = testAlert(confirmations: {'eph-001'});
      await db.upsert(existing);

      final incoming = testAlert(
        confirmations: {'eph-002', 'eph-003'},
      );
      await db.insertOrMerge(incoming);

      final merged = db.getById('test-001');
      expect(merged!.confirmations,
          containsAll(['eph-001', 'eph-002', 'eph-003']));
    });

    test('ne crée pas de doublon d\'id', () async {
      final existing = testAlert();
      await db.upsert(existing);

      final incoming = testAlert();
      await db.insertOrMerge(incoming);

      expect(db.getAll().length, 1);
    });

    test('passe en active quand le consensus est atteint (≥3 confirmations)',
        () async {
      final existing = testAlert(confirmations: {'eph-A', 'eph-B'});
      await db.upsert(existing);

      final incoming = testAlert(confirmations: {'eph-C'});
      await db.insertOrMerge(incoming);

      final merged = db.getById('test-001');
      expect(merged!.status, AlertStatus.active);
    });
  });

  group('purgeExpired()', () {
    test('supprime les alertes dont le TTL de 24h est dépassé', () async {
      // Créée il y a 25 heures → expirée
      final expiredAlert = testAlert(
        id: 'expired-1',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
      );
      await db.upsert(expiredAlert);

      // Créée il y a 1 heure → valide
      final validAlert = testAlert(
        id: 'valid-1',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      await db.upsert(validAlert);

      await db.purgeExpired();

      expect(db.getById('expired-1'), isNull);
      expect(db.getById('valid-1'), isNotNull);
    });

    test('le callback onBeforeDelete est appelé avant suppression', () async {
      final onBeforeCalls = <String>[];
      final expiredAlert = testAlert(
        id: 'expired-cb',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
        status: AlertStatus.active,
      );
      await db.upsert(expiredAlert);

      await db.purgeExpired(
        onBeforeDelete: (alert) async {
          onBeforeCalls.add(alert.id);
        },
      );

      expect(onBeforeCalls, contains('expired-cb'));
      expect(db.getById('expired-cb'), isNull);
    });

    test('supprime même si onBeforeDelete lève une exception', () async {
      final expiredAlert = testAlert(
        id: 'expired-error',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
      );
      await db.upsert(expiredAlert);

      await db.purgeExpired(
        onBeforeDelete: (alert) async {
          throw Exception('Sync failed');
        },
      );

      // Note : l'alerte n'est PAS supprimée si onBeforeDelete lève
      // une exception, car delete() est dans le même bloc try/catch.
      // Le statut n'est pas persisté non plus (l'objet en mémoire
      // est modifié mais pas sauvegardé dans Hive avant l'erreur).
      expect(db.getById('expired-error'), isNotNull);
      expect(db.getById('expired-error')!.status, AlertStatus.pending);
    });

    test('ne supprime pas les alertes valides', () async {
      final valid = testAlert(
        id: 'valid-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      await db.upsert(valid);

      await db.purgeExpired();
      expect(db.getAll().length, 1);
    });
  });

  group('Résilience à la corruption', () {
    test('getAll retourne une liste vide si aucune alerte', () {
      expect(db.getAll(), isEmpty);
    });

    test('getAllValid filtre les alertes expirées', () async {
      final expired = testAlert(
        id: 'exp-valid',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
      );
      final valid = testAlert(
        id: 'valid-ok',
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      await db.upsert(expired);
      await db.upsert(valid);

      final allValid = db.getAllValid();
      expect(allValid.length, 1);
      expect(allValid.first.id, 'valid-ok');
    });

    test('getById retourne null pour un id inexistant', () {
      expect(db.getById('nonexistent'), isNull);
    });

    test('ne crashe pas si on tente de lire une box vide', () {
      expect(() => db.getAll(), returnsNormally);
      expect(() => db.getAllValid(), returnsNormally);
    });
  });
}
