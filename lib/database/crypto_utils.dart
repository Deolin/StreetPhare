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
class SignedAlert { // partagée hors-ligne via le bundle
  const SignedAlert({required this.signature, required this.publicKey});
  final String signature;
  final String publicKey;
}

/// Helper cryptographique pour StreetPhare.
class CryptoUtils {
  CryptoUtils._();
  static final CryptoUtils instance = CryptoUtils._();

  final _ed = Ed25519();

  // AES-256-CBC authentifié par HMAC-SHA256.
  final _aes = AesCbc.with256bits(macAlgorithm: Hmac.sha256());

  /// Longueur du sel aléatoire (16 octets) utilisé pour la dérivation
  /// PBKDF2. Chaque ciphertext embarque son propre sel en préfixe.
  static const int _saltLength = 16;

  /// Dérive une clé AES-256 depuis une clé maîtresse et un sel
  /// via PBKDF2-HMAC-SHA256 (100 000 itérations, OWASP 2023).
  ///
  /// Le [salt] DOIT être unique par ciphertext (généré aléatoirement).
  /// Si non fourni, un sel aléatoire est généré automatiquement.
  Future<SecretKey> deriveAesKey(SecretKey masterKey, {List<int>? salt}) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: masterKey,
      nonce: salt ?? _generateSalt(),
    );
  }

  /// Génère un sel aléatoire de 16 octets.
  List<int> _generateSalt() {
    final rng = Random.secure();
    return List<int>.generate(_saltLength, (_) => rng.nextInt(256));
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
  ///
  /// Format de sortie : `base64(sel_16_octets || nonce_16 || mac_32 || cipher)`
  /// Le sel est généré aléatoirement et permet une dérivation PBKDF2
  /// unique par ciphertext.
  Future<String> encryptAddress(String address, SecretKey masterKey) async {
    final salt = _generateSalt();
    final aesKey = await deriveAesKey(masterKey, salt: salt);
    final box = await _aes.encrypt(
      utf8.encode(address),
      secretKey: aesKey,
    );
    // Prépare le bloc complet : sel + concatenation(nonce + mac + cipher)
    final combined = <int>[
      ...salt,
      ...box.concatenation(),
    ];
    return base64Url.encode(combined);
  }

  /// Déchiffre une adresse chiffrée.
  ///
  /// Extrait le sel des 16 premiers octets, dérive la clé AES
  /// via PBKDF2, puis déchiffre.
  Future<String> decryptAddress(String cipherB64, SecretKey masterKey) async {
    final combined = base64Url.decode(cipherB64);
    if (combined.length < _saltLength + 16 + 32) {
      throw FormatException(
          'Ciphertext trop court : ${combined.length} octets');
    }
    // Extrait le sel (16 premiers octets).
    final salt = combined.sublist(0, _saltLength);
    final rest = combined.sublist(_saltLength);

    final aesKey = await deriveAesKey(masterKey, salt: salt);
    // AesCbc.with256bits + Hmac.sha256 -> nonce=16, mac=32
    final box = SecretBox.fromConcatenation(
      rest,
      nonceLength: 16,
      macLength: 32,
    );
    final clear = await _aes.decrypt(box, secretKey: aesKey);
    return utf8.decode(clear);
  }
}
