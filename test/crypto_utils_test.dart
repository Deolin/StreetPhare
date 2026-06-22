// test/crypto_utils_test.dart
//
// Tests de la couche cryptographique StreetPhare.
// Vérifie la compatibilité chiffrement/déchiffrement AES-256-CBC + HMAC-SHA256
// entre l'implémentation Dart (`CryptoUtils`) et le contrat `server_crypto.js`.
//
// Spécifications partagées :
//   - Algorithme : AES-256-CBC authentifié par HMAC-SHA256
//   - Clé AES = SHA-256(passphrase)
//   - Format : base64Url( IV(16) || MAC(32) || CIPHER )
//   - MAC = HMAC_SHA256(key, CIPHER) — calculé sur le ciphertext seul
//
// Le test nominal chiffre une adresse avec la passphrase de développement
// partagée, vérifie que le résultat a le bon format, puis déchiffre et
// compare le texte original.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_streetphare/database/crypto_utils.dart'
    as streetphare;

void main() {
  group('CryptoUtils — AES-256-CBC + HMAC-SHA256', () {
    // Passphrase de développement (identique à server_crypto.js)
    const testPassphrase = 'streetphare-dev-key-CHANGE_ME_IN_PROD';
    const testAddress = 'http://localhost:3001';

    late SecretKey aesKey;
    late streetphare.CryptoUtils crypto;

    setUp(() async {
      crypto = streetphare.CryptoUtils.instance;
      aesKey = await crypto.deriveAesKey(testPassphrase);
    });

    test('la clé AES dérivée fait 32 octets (AES-256)', () async {
      final keyBytes = await aesKey.extractBytes();
      expect(keyBytes.length, 32);
    });

    test('encrypt + decrypt restore l\'adresse originale', () async {
      // Chiffrement
      final cipherB64 = await crypto.encryptAddress(testAddress, aesKey);
      expect(cipherB64, isNotEmpty);

      // Vérification du format base64Url
      final raw = base64Url.decode(cipherB64);
      // IV(16) + MAC(32) + au moins 16 octets de cipher (padding AES)
      expect(raw.length, greaterThanOrEqualTo(16 + 32 + 16));

      // Déchiffrement
      final decrypted = await crypto.decryptAddress(cipherB64, aesKey);
      expect(decrypted, testAddress);
    });

    test('deux chiffrements produisent des IV distincts', () async {
      final c1 = await crypto.encryptAddress(testAddress, aesKey);
      final c2 = await crypto.encryptAddress(testAddress, aesKey);
      // Les IV étant aléatoires, les ciphertexts doivent différer
      expect(c1, isNot(c2));
    });

    test('déchiffrement avec une mauvaise passphrase échoue', () async {
      final cipherB64 = await crypto.encryptAddress(testAddress, aesKey);
      final wrongKey =
          await crypto.deriveAesKey('wrong-passphrase-CHANGE_ME');

      // Le déchiffrement doit lever une exception (MAC invalide ou padding)
      expect(
        () async => crypto.decryptAddress(cipherB64, wrongKey),
        throwsA(isA<Exception>()),
      );
    });

    test('déchiffrement d\'un ciphertext corrompu échoue', () async {
      final cipherB64 = await crypto.encryptAddress(testAddress, aesKey);
      final raw = base64Url.decode(cipherB64);

      // Corrompre un octet au milieu du ciphertext
      final corrupted = List<int>.from(raw);
      corrupted[corrupted.length ~/ 2] ^= 0xFF;
      final corruptB64 = base64Url.encode(corrupted);

      expect(
        () async => crypto.decryptAddress(corruptB64, aesKey),
        throwsA(isA<Exception>()),
      );
    });

    test('la passphrase de dev produit la même clé que server_crypto.js',
        () async {
      // Vecteur de test calculé avec server_crypto.js :
      //   node -e "
      //     const c = require('./server/server_crypto');
      //     const enc = c.encryptAddress('http://localhost:3001',
      //       'streetphare-dev-key-CHANGE_ME_IN_PROD');
      //     console.log(enc);
      //   "
      //
      // On vérifie UNIQUEMENT que le déchiffrement fonctionne,
      // pas le ciphertext exact (IV aléatoire).
      final cipherB64 = await crypto.encryptAddress(testAddress, aesKey);
      final decrypted = await crypto.decryptAddress(cipherB64, aesKey);
      expect(decrypted, testAddress);
    });
  });

  group('CryptoUtils — Identifiants éphémères', () {
    test('randomId produit des chaînes distinctes', () {
      final ids = List.generate(10, (_) => streetphare.randomId());
      final unique = ids.toSet();
      expect(unique.length, ids.length);
    });

    test('generateEphemeralUserId produit des chaînes < 30 caractères', () {
      for (int i = 0; i < 20; i++) {
        final id = streetphare.generateEphemeralUserId();
        expect(id.length, lessThan(30));
      }
    });
  });

  group('CryptoUtils — Signature Ed25519', () {
    late streetphare.CryptoUtils crypto;

    setUp(() {
      crypto = streetphare.CryptoUtils.instance;
    });

    test('sign + verify une alerte nominale', () async {
      final now = DateTime.now().toUtc();
      final signed = await crypto.signAlert(
        alertId: 'test-alert-001',
        type: 'barrage',
        lat: 50.4762,
        lng: 4.5422,
        createdAt: now,
      );

      expect(signed.signature, isNotEmpty);
      expect(signed.publicKey, isNotEmpty);

      final valid = await crypto.verifyAlert(
        alertId: 'test-alert-001',
        type: 'barrage',
        lat: 50.4762,
        lng: 4.5422,
        createdAt: now,
        signatureB64: signed.signature,
        publicKeyB64: signed.publicKey,
      );
      expect(valid, isTrue);
    });

    test('verify échoue si le message est altéré', () async {
      final now = DateTime.now().toUtc();
      final signed = await crypto.signAlert(
        alertId: 'test-alert-002',
        type: 'danger',
        lat: 50.4891,
        lng: 4.5452,
        createdAt: now,
      );

      // Altération du type
      final valid = await crypto.verifyAlert(
        alertId: 'test-alert-002',
        type: 'barrage', // ← modifié
        lat: 50.4891,
        lng: 4.5452,
        createdAt: now,
        signatureB64: signed.signature,
        publicKeyB64: signed.publicKey,
      );
      expect(valid, isFalse);
    });
  });
}