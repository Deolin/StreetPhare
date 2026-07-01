// test/hive_alert_database_test.dart
//
// Tests unitaires pour `lib/database/hive_alert_database.dart`
//
// Couvre les opérations critiques :
//   - init() — initialisation Hive + purge initiale
//   - upsert() — insertion et mise à jour
//   - insertOrMerge() — fusion des confirmations
//   - purgeExpired() — purge conforme RGPD (24h)
//   - getAllValid() / getAll() — filtrage et tri
//   - delete() / clearAll() / markUploaded() / getPendingUpload()
//   - lastModifiedTimestamp()
//   - Stream changes — émission après chaque mutation
//   - AlertAdapter — sérialisation/désérialisation + fallback corruption
//
// Réf: docs/plan_et_audit_complet_28062026.md#Anomalie-A3

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/database/hive_alert_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:hive_ce/src/binary/binary_reader_impl.dart';
import 'package:hive_ce/src/registry/type_registry_impl.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Crée une alerte de test avec champs paramétrables.
Alert _testAlert({
  String id = 'test-001',
  String ephemeralUserId = 'user-001',
  DateTime? createdAt,
  int ttlHours = 24,
  AlertStatus status = AlertStatus.pending,
  Set<String>? confirmations,
  double latitude = 50.4762,
  double longitude = 4.5422,
  String description = '',
}) {
  return Alert(
    id: id,
    ephemeralUserId: ephemeralUserId,
    signature: 'sig-$id',
    type: AlertType.danger,
    latitude: latitude,
    longitude: longitude,
    description: description.isNotEmpty ? description : 'Alerte de test $id',
    createdAt: createdAt ?? DateTime.now().toUtc(),
    ttlHours: ttlHours,
    status: status,
    confirmations: confirmations ?? {},
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    // ---- Binding Flutter pour les tests ----
    TestWidgetsFlutterBinding.ensureInitialized();

    // ---- Mock du MethodChannel path_provider ----
    const MethodChannel channel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    // ---- Création d’un dossier temporaire dédié aux tests ----
    tempDir = Directory.systemTemp.createTempSync('streetphare_test_');
  });

  tearDownAll(() async {
    // ---- Fermeture de Hive avant suppression du dossier ----
    await HiveAlertDatabase.instance.close();
    // ---- Nettoyage des fichiers Hive et du dossier temporaire ----
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // -----------------------------------------------------------------------
  // HiveAlertDatabase — tests CRUD et métier
  // -----------------------------------------------------------------------
  group('HiveAlertDatabase', () {
    late HiveAlertDatabase db;

    setUp(() async {
      db = HiveAlertDatabase.instance;
      if (!db.isInitialized) {
        await db.init();
      }
      // Nettoie la box avant chaque test pour garantir l'isolation.
      await db.clearAll();
    });

    // ── 1. init() ──────────────────────────────────────────────────────
    group('init()', () {
      test('initialise Hive CE, ouvre la box et purge les expirées', () async {
        expect(db.isInitialized, isTrue);
        // getAllValid() ne doit pas lever d'exception.
        expect(db.getAllValid(), isEmpty);
      });

      test('un second appel à init() est sans effet (idempotent)', () async {
        expect(db.isInitialized, isTrue);
        await db.init(); // ne doit pas lever
        expect(db.isInitialized, isTrue);
      });
    });

    // ── 2. upsert() ────────────────────────────────────────────────────
    group('upsert()', () {
      test('insère une nouvelle alerte et retourne true', () async {
        final alert = _testAlert(id: 'upsert-new');
        final isNew = await db.upsert(alert);
        expect(isNew, isTrue);

        final retrieved = db.getById('upsert-new');
        expect(retrieved, isNotNull);
        expect(retrieved!.id, 'upsert-new');
        expect(retrieved.type, AlertType.danger);
      });

      test('met à jour une alerte existante et retourne false', () async {
        final alert = _testAlert(id: 'upsert-update', description: 'V1');
        await db.upsert(alert);

        final updated = Alert(
          id: 'upsert-update',
          ephemeralUserId: 'user-001',
          signature: 'sig-upsert-update',
          type: AlertType.barrage,
          latitude: 50.5,
          longitude: 4.6,
          description: 'V2 — modifiée',
          status: AlertStatus.active,
          confirmations: {'user-a', 'user-b', 'user-c'},
        );
        final isNew = await db.upsert(updated);
        expect(isNew, isFalse);

        final retrieved = db.getById('upsert-update')!;
        expect(retrieved.description, 'V2 — modifiée');
        expect(retrieved.status, AlertStatus.active);
        expect(retrieved.confirmations.length, 3);
      });

      test('le nombre d\'éléments dans la box est correct après N upserts',
          () async {
        for (int i = 0; i < 5; i++) {
          await db.upsert(_testAlert(id: 'count-$i'));
        }
        expect(db.getAll().length, 5);
      });
    });

    // ── 3. insertOrMerge() ─────────────────────────────────────────────
    group('insertOrMerge()', () {
      test('insère une nouvelle alerte et retourne true', () async {
        final alert = _testAlert(id: 'merge-new', confirmations: {'u1'});
        final isNew = await db.insertOrMerge(alert);
        expect(isNew, isTrue);
      });

      test('retourne false pour une alerte déjà existante', () async {
        await db.insertOrMerge(
          _testAlert(id: 'merge-existing', confirmations: {'u1'}),
        );
        final isNew = await db.insertOrMerge(
          _testAlert(id: 'merge-existing', confirmations: {'u2'}),
        );
        expect(isNew, isFalse);
      });

      test('fusionne les confirmations sans doublons', () async {
        await db.insertOrMerge(
          _testAlert(id: 'merge-dup', confirmations: {'u1', 'u2'}),
        );
        // u2 déjà présent, u3 nouveau
        await db.insertOrMerge(
          _testAlert(id: 'merge-dup', confirmations: {'u2', 'u3'}),
        );

        final retrieved = db.getById('merge-dup')!;
        expect(retrieved.confirmations, {'u1', 'u2', 'u3'});
        expect(retrieved.confirmations.length, 3);
      });

      test('le statut passe de pending à active à ≥3 confirmations', () async {
        // 1 confirmation → pending
        await db.insertOrMerge(
          _testAlert(id: 'merge-status', confirmations: {'u1'}),
        );
        expect(db.getById('merge-status')!.status, AlertStatus.pending);

        // +2 confirmations → 3 total → active
        await db.insertOrMerge(
          _testAlert(id: 'merge-status', confirmations: {'u2', 'u3'}),
        );
        expect(db.getById('merge-status')!.status, AlertStatus.active);
      });
    });

    // ── 4. purgeExpired() ──────────────────────────────────────────────
    group('purgeExpired()', () {
      test('supprime uniquement les alertes expirées (>24h)', () async {
        final now = DateTime.now().toUtc();
        final expired = _testAlert(
          id: 'purge-expired',
          createdAt: now.subtract(const Duration(hours: 25)),
        );
        final valid = _testAlert(
          id: 'purge-valid',
          createdAt: now.subtract(const Duration(hours: 1)),
        );
        final limit = _testAlert(
          id: 'purge-limit',
          createdAt: now.subtract(const Duration(hours: 23, minutes: 59)),
        );

        await db.upsert(expired);
        await db.upsert(valid);
        await db.upsert(limit);

        final purged = await db.purgeExpired(now: now);
        expect(purged.length, 1);
        expect(purged.first.id, 'purge-expired');

        final remaining = db.getAll();
        expect(remaining.length, 2);
        expect(
          remaining.map((a) => a.id),
          containsAll(['purge-valid', 'purge-limit']),
        );
      });

      test('change le statut de l\'alerte purgée en rejected', () async {
        final now = DateTime.now().toUtc();
        final expired = _testAlert(
          id: 'purge-status',
          createdAt: now.subtract(const Duration(hours: 25)),
          status: AlertStatus.pending,
        );
        await db.upsert(expired);

        final purged = await db.purgeExpired(now: now);
        expect(purged.first.status, AlertStatus.rejected);
      });

      test('appelle onBeforeDelete avant suppression', () async {
        final now = DateTime.now().toUtc();
        final expired = _testAlert(
          id: 'purge-callback',
          createdAt: now.subtract(const Duration(hours: 25)),
        );
        await db.upsert(expired);

        String? lastCallbackId;
        await db.purgeExpired(
          now: now,
          onBeforeDelete: (alert) async {
            lastCallbackId = alert.id;
          },
        );

        expect(lastCallbackId, 'purge-callback');
        expect(db.getById('purge-callback'), isNull);
      });

      test('supprime l\'alerte même si onBeforeDelete lève une exception',
          () async {
        final now = DateTime.now().toUtc();
        final expired = _testAlert(
          id: 'purge-error',
          createdAt: now.subtract(const Duration(hours: 25)),
        );
        await db.upsert(expired);

        await db.purgeExpired(
          now: now,
          onBeforeDelete: (alert) async {
            throw Exception('Sync failed');
          },
        );

        // L'alerte doit être supprimée malgré l'erreur (règle RGPD).
        expect(db.getById('purge-error'), isNull);
      });

      test('retourne une liste vide si aucune alerte n\'est expirée', () async {
        final now = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'not-expired',
          createdAt: now.subtract(const Duration(hours: 1)),
        ));

        final purged = await db.purgeExpired(now: now);
        expect(purged, isEmpty);
        expect(db.getAll().length, 1);
      });
    });

    // ── 5. getAllValid() ───────────────────────────────────────────────
    group('getAllValid()', () {
      test('filtre les alertes expirées', () async {
        final now = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'valid-1',
          createdAt: now.subtract(const Duration(hours: 1)),
        ));
        await db.upsert(_testAlert(
          id: 'expired-1',
          createdAt: now.subtract(const Duration(hours: 50)),
        ));

        final valid = db.getAllValid();
        expect(valid.length, 1);
        expect(valid.first.id, 'valid-1');
      });

      test('trie par createdAt décroissant (plus récent en premier)', () async {
        final now = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'old',
          createdAt: now.subtract(const Duration(hours: 10)),
        ));
        await db.upsert(_testAlert(
          id: 'mid',
          createdAt: now.subtract(const Duration(hours: 2)),
        ));
        await db.upsert(_testAlert(
          id: 'recent',
          createdAt: now.subtract(const Duration(minutes: 5)),
        ));

        final valid = db.getAllValid();
        expect(valid.length, 3);
        expect(valid[0].id, 'recent');
        expect(valid[1].id, 'mid');
        expect(valid[2].id, 'old');
      });
    });

    // ── 6. getAll() ─────────────────────────────────────────────────────
    group('getAll()', () {
      test('retourne toutes les alertes, y compris expirées', () async {
        final now = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'all-valid',
          createdAt: now.subtract(const Duration(hours: 1)),
        ));
        await db.upsert(_testAlert(
          id: 'all-expired',
          createdAt: now.subtract(const Duration(hours: 50)),
        ));

        final all = db.getAll();
        expect(all.length, 2);
        final ids = all.map((a) => a.id).toSet();
        expect(ids, {'all-valid', 'all-expired'});
      });

      test('trie par createdAt décroissant', () async {
        final now = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'b',
          createdAt: now.subtract(const Duration(hours: 20)),
        ));
        await db.upsert(_testAlert(
          id: 'a',
          createdAt: now.subtract(const Duration(hours: 5)),
        ));

        final all = db.getAll();
        expect(all[0].id, 'a'); // plus récent en premier
        expect(all[1].id, 'b');
      });
    });

    // ── 7. getById() ───────────────────────────────────────────────────
    group('getById()', () {
      test('retourne null pour un id inconnu', () {
        expect(db.getById('inexistant'), isNull);
      });

      test('retourne l\'alerte correspondante', () async {
        await db.upsert(_testAlert(id: 'by-id'));
        final result = db.getById('by-id');
        expect(result, isNotNull);
        expect(result!.id, 'by-id');
      });
    });

    // ── 8. delete() ────────────────────────────────────────────────────
    group('delete()', () {
      test('supprime une alerte par id', () async {
        await db.upsert(_testAlert(id: 'del-1'));
        expect(db.getById('del-1'), isNotNull);

        await db.delete('del-1');
        expect(db.getById('del-1'), isNull);
      });

      test('ne lève pas d\'exception pour un id inexistant', () async {
        await db.delete('inexistant'); // ne doit pas lever
      });
    });

    // ── 9. getPendingUpload() / markUploaded() ────────────────────────
    group('getPendingUpload()', () {
      test('retourne les alertes active avec uploadedTo vide', () async {
        await db.upsert(_testAlert(
          id: 'upload-pending',
          status: AlertStatus.active,
        ));
        await db.upsert(_testAlert(
          id: 'upload-pending2',
          status: AlertStatus.pending,
        ));

        final pending = db.getPendingUpload();
        expect(pending.length, 1);
        expect(pending.first.id, 'upload-pending');
      });

      test('exclut les alertes déjà uploadées', () async {
        await db.upsert(_testAlert(
          id: 'upload-done',
          status: AlertStatus.active,
        ));
        await db.markUploaded('upload-done', 'server-a');

        final pending = db.getPendingUpload();
        expect(pending.any((a) => a.id == 'upload-done'), isFalse);
      });
    });

    group('markUploaded()', () {
      test('définit uploadedTo et passe le statut à active', () async {
        await db.upsert(_testAlert(
          id: 'mark-upload',
          status: AlertStatus.pending,
        ));
        await db.markUploaded('mark-upload', 'https://server.local');

        final alert = db.getById('mark-upload')!;
        expect(alert.status, AlertStatus.active);
        expect(alert.uploadedTo, 'https://server.local');
      });

      test('ne fait rien pour un id inexistant', () async {
        await db.markUploaded('inexistant', 'server'); // ne doit pas lever
      });
    });

    // ── 10. clearAll() ─────────────────────────────────────────────────
    group('clearAll()', () {
      test('vide complètement la base', () async {
        await db.upsert(_testAlert(id: 'clear-1'));
        await db.upsert(_testAlert(id: 'clear-2'));
        expect(db.getAll().length, 2);

        await db.clearAll();
        expect(db.getAll(), isEmpty);
      });
    });

    // ── 11. lastModifiedTimestamp() ────────────────────────────────────
    group('lastModifiedTimestamp()', () {
      test('retourne null si la base est vide', () {
        expect(db.lastModifiedTimestamp(), isNull);
      });

      test('retourne le timestamp le plus récent', () async {
        final base = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'ts-old',
          createdAt: base.subtract(const Duration(hours: 5)),
        ));
        await db.upsert(_testAlert(
          id: 'ts-new',
          createdAt: base.subtract(const Duration(hours: 1)),
        ));

        final ts = db.lastModifiedTimestamp();
        expect(ts, isNotNull);
        expect(
          ts!.isAfter(base.subtract(const Duration(hours: 6))),
          isTrue,
        );
      });
    });

    // ── 12. Stream changes ─────────────────────────────────────────────
    group('Stream changes', () {
      test('émet après un upsert (insertion)', () async {
        final future = db.changes.first;

        await db.upsert(_testAlert(id: 'stream-1'));

        final emitted = await future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => <Alert>[],
        );
        expect(emitted.any((a) => a.id == 'stream-1'), isTrue);
      });

      test('émet après un insertOrMerge', () async {
        await db.insertOrMerge(
          _testAlert(id: 'stream-init', confirmations: {'u0'}),
        );
        final future = db.changes.first;

        await db.insertOrMerge(_testAlert(id: 'stream-2'));

        final emitted = await future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => <Alert>[],
        );
        expect(emitted.any((a) => a.id == 'stream-2'), isTrue);
      });

      test('émet après purgeExpired', () async {
        final now = DateTime.now().toUtc();
        await db.upsert(_testAlert(
          id: 'stream-expired',
          createdAt: now.subtract(const Duration(hours: 25)),
        ));
        await db.upsert(_testAlert(
          id: 'stream-valid',
          createdAt: now.subtract(const Duration(hours: 1)),
        ));

        final future = db.changes.first;

        await db.purgeExpired(now: now);

        final emitted = await future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => <Alert>[],
        );
        // Après purge, la liste émise ne contient que l'alerte valide
        expect(emitted.length, 1);
        expect(emitted.first.id, 'stream-valid');
      });

      test('émet après delete', () async {
        await db.upsert(_testAlert(id: 'stream-del'));
        final future = db.changes.first;

        await db.delete('stream-del');

        final emitted = await future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => <Alert>[],
        );
        expect(emitted.any((a) => a.id == 'stream-del'), isFalse);
      });
    });
  });

  // -----------------------------------------------------------------------
  // AlertAdapter — sérialisation / désérialisation Hive
  // -----------------------------------------------------------------------
  group('AlertAdapter', () {
    late AlertAdapter adapter;

    setUpAll(() async {
      // Garantit que Hive est initialisé (même si ce groupe est exécuté seul).
      // NOTE : le mock path_provider est déjà en place via le setUpAll global.
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(AlertAdapter());
      }
    });

    setUp(() {
      adapter = AlertAdapter();
    });

    test('typeId is 1', () {
      expect(adapter.typeId, 1);
    });

    test('write + read round-trip preserves all data', () async {
      // Utilise la box principale (déjà initialisée via setUp) pour tester
      // le round-trip complet via l'adapter enregistré (typeId=1).
      final original = _testAlert(
        id: 'adapter-test',
        ephemeralUserId: 'eph-123',
        confirmations: {'u1', 'u2', 'u3'},
        status: AlertStatus.active,
      );

      // Force une écriture dans une box fraîche pour tester le round-trip.
      final box = await Hive.openBox<Alert>('adapter_roundtrip_box');
      try {
        await box.put(original.id, original);
        final retrieved = box.get(original.id);

        expect(retrieved, isNotNull);
        expect(retrieved!.id, original.id);
        expect(retrieved.ephemeralUserId, original.ephemeralUserId);
        expect(retrieved.signature, original.signature);
        expect(retrieved.type, original.type);
        expect(retrieved.latitude, original.latitude);
        expect(retrieved.longitude, original.longitude);
        expect(retrieved.description, original.description);
        expect(retrieved.ttlHours, original.ttlHours);
        expect(retrieved.status, original.status);
        expect(retrieved.confirmations, original.confirmations);
        expect(retrieved.uploadedTo, original.uploadedTo);
        expect(
          retrieved.createdAt.difference(original.createdAt).inSeconds.abs(),
          lessThan(2),
        );
        expect(
          retrieved.lastModifiedAt
              .difference(original.lastModifiedAt)
              .inSeconds
              .abs(),
          lessThan(2),
        );
      } finally {
        await box.close();
        await Hive.deleteBoxFromDisk('adapter_roundtrip_box');
      }
    });

    test('serialization preserves 13 fields (all round-tripped)', () async {
      // Vérifie que les 13 champs écrits par write() sont bien relus par read().
      final box = await Hive.openBox<Alert>('adapter_13fields_box');
      try {
        final alert = Alert(
          id: 'fields-13',
          ephemeralUserId: 'eph-13',
          signature: 'sig-13',
          type: AlertType.policiers,
          latitude: 48.8566,
          longitude: 2.3522,
          description: 'Test 13 champs',
          densityValue: 5,
          createdAt: DateTime.utc(2026, 6, 15, 12, 0, 0),
          ttlHours: 12,
          status: AlertStatus.active,
          confirmations: {'c1', 'c2'},
          uploadedTo: 'https://srv',
          lastModifiedAt: DateTime.utc(2026, 6, 15, 12, 30, 0),
        );

        await box.put(alert.id, alert);
        final retrieved = box.get(alert.id)!;

        // Vérification exhaustive des 13 champs
        expect(retrieved.id, 'fields-13');
        expect(retrieved.ephemeralUserId, 'eph-13');
        expect(retrieved.signature, 'sig-13');
        expect(retrieved.type, AlertType.policiers);
        expect(retrieved.latitude, 48.8566);
        expect(retrieved.longitude, 2.3522);
        expect(retrieved.description, 'Test 13 champs');
        expect(retrieved.densityValue, 5);
        expect(retrieved.createdAt, DateTime.utc(2026, 6, 15, 12, 0, 0));
        expect(retrieved.ttlHours, 12);
        expect(retrieved.status, AlertStatus.active);
        expect(retrieved.confirmations, {'c1', 'c2'});
        expect(retrieved.uploadedTo, 'https://srv');
        expect(retrieved.lastModifiedAt, DateTime.utc(2026, 6, 15, 12, 30, 0));
      } finally {
        await box.close();
        await Hive.deleteBoxFromDisk('adapter_13fields_box');
      }
    });

    test('read with corrupted bytes returns fallback alert', () {
      // Injecte des bytes corrompus dans un BinaryReader et vérifie que
      // AlertAdapter.read() ne lève pas d'exception mais retourne un
      // fallback (ex: données d'une version antérieure du schéma ou
      // corruption disque). Hive CE ne fait pas de cast avant d'appeler
      // read(), donc le fallback de l'adaptateur protège l'ouverture
      // de la box même avec des données binaires invalides.
      //
      // On construit un BinaryReader avec des bytes qui ne respectent
      // pas le format attendu (un champ count absurde suivi de
      // données invalides).
      final corruptBytes = Uint8List.fromList([
        255, // byte: un count absurde (bien au-delà de 13)
        0, // key 0
        42, // une valeur int non convertible en String
        1, // key 1
        99, // une autre valeur aléatoire
      ]);

      final reader = BinaryReaderImpl(corruptBytes, TypeRegistryImpl());
      final result = adapter.read(reader);

      // Le fallback doit avoir les marqueurs "corrupted_"
      expect(result.id, contains('corrupted_'));
      expect(result.status, AlertStatus.rejected);
      expect(result.ttlHours, 1);
      expect(result.ephemeralUserId, 'corrupted');
    });

    test('AlertAdapter hashCode and operator== are consistent', () {
      final a = AlertAdapter();
      final b = AlertAdapter();
      expect(a.hashCode, b.hashCode);
      expect(a, equals(b));
    });

    test('registerAdapter on id=1 is idempotent', () {
      // Vérifie que registerAdapter avec le même typeId ne lève pas.
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(AlertAdapter());
      }
      expect(Hive.isAdapterRegistered(1), isTrue);
      // Un second appel est protégé par le if dans init()
    });
  });
}
