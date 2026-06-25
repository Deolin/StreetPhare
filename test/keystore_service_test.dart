// test/keystore_service_test.dart
//
// Tests unitaires pour KeyStoreService (P1.4).
//
// Couvre :
//   - loadOrCreateMasterKey() : génération premier lancement, relecture
//   - Résilience à la corruption : données invalides → régénération

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_streetphare/core/security/keystore_service.dart';

/// Mock de FlutterSecureStorage pour les tests.
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late KeyStoreService service;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    service = KeyStoreService.test(storage: mockStorage);

    // Stub delete pour qu'il retourne un Future<void> (pas null).
    when(() => mockStorage.delete(key: any(named: 'key')))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await service.deleteKey();
  });

  group('loadOrCreateMasterKey()', () {
    test('génère une clé de 32 octets au premier lancement', () async {
      // Simule un stockage vide (premier lancement).
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async => {});

      final key = await service.loadOrCreateMasterKey();

      // Vérifie que la clé est stockée.
      final captured = verify(() => mockStorage.write(
          key: captureAny(named: 'key'), value: captureAny(named: 'value')));
      final writtenValue = captured.captured[1] as String;
      final decoded = base64.decode(writtenValue);

      expect(decoded.length, 32); // 256 bits
      final keyBytes = await key.extractBytes();
      expect(keyBytes.length, 32);
    });

    test('relit la même clé au second lancement', () async {
      // Premier appel : aucune clé en stockage.
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async => {});

      final firstKey = await service.loadOrCreateMasterKey();
      final firstBytes = await firstKey.extractBytes();

      // Réinitialise le cache pour simuler un nouveau process.
      await service.deleteKey();

      // Second appel : la clé existe en stockage.
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => base64.encode(firstBytes));

      final secondKey = await service.loadOrCreateMasterKey();
      final secondBytes = await secondKey.extractBytes();

      expect(secondBytes, equals(firstBytes));
    });

    test('utilise le cache mémoire après le premier chargement', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async => {});

      await service.loadOrCreateMasterKey();

      // Deuxième appel sans reset du cache — ne doit pas rappeler read().
      await service.loadOrCreateMasterKey();

      // read() ne doit être appelé qu'une seule fois (la première fois).
      verify(() => mockStorage.read(key: any(named: 'key'))).called(1);
    });
  });

  group('Résilience à la corruption', () {
    test('détecte une clé corrompue (longueur invalide) et régénère',
        () async {
      // Stockage contient des données corrompues (mauvaise longueur).
      final corrupted = base64.encode([1, 2, 3]); // 3 octets au lieu de 32
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => corrupted);
      when(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async => {});

      final key = await service.loadOrCreateMasterKey();
      final bytes = await key.extractBytes();

      // Note : delete n'est pas appelé car base64.decode réussit
      // (la longueur est juste invalide, pas le format). La clé
      // est simplement écrasée par la nouvelle.
      // Vérifie qu'une nouvelle clé de 32 octets a été écrite.
      final captured = verify(() => mockStorage.write(
          key: captureAny(named: 'key'), value: captureAny(named: 'value')));
      final writtenValue = captured.captured[1] as String;
      final decoded = base64.decode(writtenValue);
      expect(decoded.length, 32);
      expect(bytes.length, 32);
    });

    test('détecte des données base64 invalides et régénère', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'ceci-n\'est-pas-du-base64!!!');
      when(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async => {});

      final key = await service.loadOrCreateMasterKey();

      // L'ancienne clé doit être supprimée.
      verify(() => mockStorage.delete(key: 'streetphare_master_key')).called(1);
      // Une nouvelle clé doit être écrite.
      verify(() => mockStorage.write(
          key: 'streetphare_master_key', value: any(named: 'value')))
          .called(1);

      final bytes = await key.extractBytes();
      expect(bytes.length, 32);
    });

    test('régénère si le storage lève une exception à la lecture', () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenThrow(Exception('Keystore inaccessible'));
      when(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async => {});

      final key = await service.loadOrCreateMasterKey();
      final bytes = await key.extractBytes();

      expect(bytes.length, 32);
    });
  });
}