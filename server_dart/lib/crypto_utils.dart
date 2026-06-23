// server_dart/lib/crypto_utils.dart
//
// Module cryptographique du serveur StreetPhare — portage 100% Dart
// du module Node.js `server_crypto.js`.
//
// Compatible avec le client Flutter `lib/database/crypto_utils.dart` :
//   - AES-256-CBC + HMAC-SHA256 (via `package:cryptography`)
//   - Format de sortie : base64Url paddé (nonce || ciphertext || mac)
//   - Dérivation de clé : SHA-256(passphrase) → 32 octets
//
// Le format de concaténation `SecretBox.concatenation()` du package
// `cryptography` est : nonce(16) || ciphertext || mac(32).
// C'est exactement ce que le client Flutter attend dans `decryptAddress`.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Dérive une clé AES-256 (32 octets) à partir d'une passphrase
/// via SHA-256. Identique à `CryptoUtils.deriveAesKey` côté client.
Future<SecretKey> deriveAesKey(String passphrase) async {
  final bytes = utf8.encode(passphrase);
  final hash = await Sha256().hash(bytes);
  return SecretKey(hash.bytes);
}

/// Chiffre une adresse avec AES-256-CBC + HMAC-SHA256.
///
/// Retourne une chaîne base64Url paddée au format :
///   nonce(16) || ciphertext || mac(32)
///
/// Strictement compatible avec `CryptoUtils.encryptAddress` côté client.
Future<String> encryptAddress(String address, SecretKey aesKey) async {
  final aes = AesCbc.with256bits(macAlgorithm: Hmac.sha256());
  final box = await aes.encrypt(
    utf8.encode(address),
    secretKey: aesKey,
  );
  return base64Url.encode(box.concatenation());
}

/// Déchiffre une adresse chiffrée avec AES-256-CBC + HMAC-SHA256.
///
/// Attend une chaîne base64Url paddée au format :
///   nonce(16) || ciphertext || mac(32)
///
/// Strictement compatible avec `CryptoUtils.decryptAddress` côté client.
Future<String> decryptAddress(String cipherB64, SecretKey aesKey) async {
  final aes = AesCbc.with256bits(macAlgorithm: Hmac.sha256());
  final combined = base64Url.decode(cipherB64);
  final box = SecretBox.fromConcatenation(
    combined,
    nonceLength: 16,
    macLength: 32,
  );
  final clear = await aes.decrypt(box, secretKey: aesKey);
  return utf8.decode(clear);
}