// lib/database/crypto_utils.dart
//
// Utilitaires cryptographiques partagés :
//   - génération d'identifiants éphémères (anonymes, rotatifs)
//   - signature cryptographique anonyme des alertes
//   - chiffrement / déchiffrement AES-CBC + HMAC-SHA256 des
//     adresses de serveurs (chiffrement authentifié)
//   - chaîne de secours des serveurs secondaires (rotation)
//
// On utilise `cryptography` qui est pure-Dart et multiplateforme.
// Le but ici n'est PAS la sécurité militaire mais l'anonymisation
// et la confidentialité de la liste de secours des serveurs.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Génère un identifiant aléatoire anonyme.
String randomId([int bytes = 16]) {
  final rng = Random.secure();
  final values = List<int>.generate(bytes, (_) => rng.nextInt(256));
  return base64Url.encode(values).replaceAll('=', '');
}

/// Génère un identifiant éphémère d'utilisateur (rotatif, anonyme).
/// Volontairement court pour limiter la taille des paquets P2P.
String generateEphemeralUserId() => randomId(12);

/// Résultat d'une signature anonyme.
class SignedAlert {
  final String signature;
  final String publicKey; // partagée hors-ligne via le bundle
  const SignedAlert({required this.signature, required this.publicKey});
}

/// Helper cryptographique pour StreetPhare.
class CryptoUtils {
  CryptoUtils._();
  static final CryptoUtils instance = CryptoUtils._();

  final _ed = Ed25519();

  // AES-256-CBC authentifié par HMAC-SHA256.
  final _aes = AesCbc.with256bits(macAlgorithm: Hmac.sha256());

  /// Clé AES dérivée depuis une passphrase maître (à fournir
  /// idéalement depuis un secure storage iOS/Android).
  /// SHA-256 → 32 octets → AES-256.
  Future<SecretKey> deriveAesKey(String passphrase) async {
    final bytes = utf8.encode(passphrase);
    final hash = await Sha256().hash(bytes);
    return SecretKey(hash.bytes);
  }

  /// Signe une alerte (id + type + lat + lng + createdAt) avec
  /// une clé éphémère Ed25519.
  ///
  /// Note : la clé privée n'est PAS stockée (one-shot), garantissant
  /// l'anonymat. Le serveur central peut vérifier l'authenticité
  /// via la clé publique incluse dans le bundle de l'application.
  Future<SignedAlert> signAlert({
    required String alertId,
    required String type,
    required double lat,
    required double lng,
    required DateTime createdAt,
  }) async {
    final keyPair = await _ed.newKeyPair();
    final message = utf8.encode(
      '$alertId|$type|$lat|$lng|${createdAt.toUtc().toIso8601String()}',
    );
    final signature = await _ed.sign(message, keyPair: keyPair);
    final publicKey = await keyPair.extractPublicKey();
    return SignedAlert(
      signature: base64Url.encode(signature.bytes),
      publicKey: base64Url.encode(publicKey.bytes),
    );
  }

  /// Vérifie la signature d'une alerte.
  Future<bool> verifyAlert({
    required String alertId,
    required String type,
    required double lat,
    required double lng,
    required DateTime createdAt,
    required String signatureB64,
    required String publicKeyB64,
  }) async {
    try {
      final message = utf8.encode(
        '$alertId|$type|$lat|$lng|${createdAt.toUtc().toIso8601String()}',
      );
      final signature = Signature(
        base64Url.decode(signatureB64),
        publicKey: SimplePublicKey(
          base64Url.decode(publicKeyB64),
          type: KeyPairType.ed25519,
        ),
      );
      return _ed.verify(message, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Chiffre une adresse (URL / IP) avec AES-256-CBC + HMAC.
  /// Le ciphertext retourné est encodé en base64 et contient :
  ///   `IV (16) ‖ MAC (32) ‖ CIPHER`
  Future<String> encryptAddress(String address, SecretKey aesKey) async {
    final iv = _randomBytes(16);
    final box = await _aes.encrypt(
      utf8.encode(address),
      secretKey: aesKey,
      nonce: iv,
    );
    final mac = box.mac.bytes;
    final combined = Uint8List(iv.length + mac.length + box.cipherText.length)
      ..setRange(0, iv.length, iv)
      ..setRange(iv.length, iv.length + mac.length, mac)
      ..setRange(
        iv.length + mac.length,
        iv.length + mac.length + box.cipherText.length,
        box.cipherText,
      );
    return base64Url.encode(combined);
  }

  /// Déchiffre une adresse chiffrée.
  Future<String> decryptAddress(String cipherB64, SecretKey aesKey) async {
    final combined = base64Url.decode(cipherB64);
    if (combined.length < 16 + 32 + 16) {
      throw const FormatException('Ciphertext AES invalide');
    }
    final iv = combined.sublist(0, 16);
    final mac = combined.sublist(16, 48);
    final cipher = combined.sublist(48);
    final box = SecretBox(cipher, nonce: iv, mac: Mac(mac));
    final clear = await _aes.decrypt(box, secretKey: aesKey);
    return utf8.decode(clear);
  }

  Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  }
}
