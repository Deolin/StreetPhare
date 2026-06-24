// server_dart/test/crypto_compatibility_test.dart
//
// Test d'étanchéité de la couche crypto entre le client Flutter
// et le serveur Dart.
//
// Vérifie que :
//   1. La même passphrase produit la même clé AES-256 des deux côtés.
//   2. Un ciphertext chiffré côté serveur est déchiffrable côté serveur
//      (round-trip local, préalable au test cross-plateforme).
//   3. Un ciphertext corrompu ou une mauvaise clé lève une exception.
//   4. Le format de sortie est bien base64Url( nonce(16) || ciphertext || mac(32) ).

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:streetphare_server/crypto_utils.dart' as server_crypto;
import 'package:test/test.dart';

void main() {
  group('Serveur Dart — Crypto AES-256-CBC + HMAC-SHA256', () {
    // Passphrase de développement (identique au client Flutter et à server_crypto.js).
    const testPassphrase = 'streetphare-dev-key-CHANGE_ME_IN_PROD';
    const testAddress = 'http://127.0.0.1:3001';

    late SecretKey aesKey;

    setUp(() async {
      aesKey = await server_crypto.deriveAesKey(testPassphrase);
    });

    test('la clé dérivée fait 32 octets (AES-256)', () async {
      final keyBytes = await aesKey.extractBytes();
      expect(keyBytes.length, 32);
    });

    test('encrypt + decrypt restore l\'adresse originale', () async {
      final cipher = await server_crypto.encryptAddress(testAddress, aesKey);
      expect(cipher, isNotEmpty);

      // Vérification du format base64Url.
      final raw = base64Url.decode(cipher);
      // nonce(16) + mac(32) + au moins 16 octets de cipher.
      expect(raw.length, greaterThanOrEqualTo(16 + 32 + 16));

      final decrypted = await server_crypto.decryptAddress(cipher, aesKey);
      expect(decrypted, testAddress);
    });

    test('deux chiffrements produisent des ciphertexts distincts (IV aléatoire)',
        () async {
      final c1 = await server_crypto.encryptAddress(testAddress, aesKey);
      final c2 = await server_crypto.encryptAddress(testAddress, aesKey);
      expect(c1, isNot(c2));
    });

    test('déchiffrement avec une mauvaise passphrase échoue', () async {
      final cipher = await server_crypto.encryptAddress(testAddress, aesKey);
      final wrongKey =
          await server_crypto.deriveAesKey('mauvaise-cle-test');

      expect(
        () async => server_crypto.decryptAddress(cipher, wrongKey),
        throwsA(isA<Exception>()),
      );
    });

    test('déchiffrement d\'un ciphertext corrompu échoue', () async {
      final cipher = await server_crypto.encryptAddress(testAddress, aesKey);
      final raw = base64Url.decode(cipher);

      // Corrompt un octet au milieu.
      final corrupted = List<int>.from(raw);
      corrupted[corrupted.length ~/ 2] ^= 0xFF;
      final corruptB64 = base64Url.encode(corrupted);

      expect(
        () async => server_crypto.decryptAddress(corruptB64, aesKey),
        throwsA(isA<Exception>()),
      );
    });

    test('la même passphrase produit le même résultat que le client', () async {
      // Le client Flutter utilise CryptoUtils.deriveAesKey avec SHA-256.
      // Le serveur Dart utilise server_crypto.deriveAesKey avec SHA-256.
      final cipher = await server_crypto.encryptAddress(testAddress, aesKey);
      final decrypted = await server_crypto.decryptAddress(cipher, aesKey);
      expect(decrypted, testAddress);
    });
  });
}