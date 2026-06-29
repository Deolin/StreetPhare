// lib/core/auth/identity_service.dart
//
// Service d'identité anonyme — façade pour la gestion des identifiants
// éphémères et des signatures Ed25519.
//
// État de la migration depuis database/crypto_utils.dart :
//   ✅ Façade créée (ce fichier)
//   ⏳ Migration complète prévue en Phase 3 (cf. roadmap v2.2.0)
//
// Ce service expose des wrappers qui délèguent aux fonctions de
// `lib/database/crypto_utils.dart`, permettant aux appelants de ne pas
// dépendre directement de `database/` pour les opérations d'identité.

import 'package:cryptography/cryptography.dart';

import '../../database/crypto_utils.dart' as crypto;

/// Service d'identité anonyme StreetPhare.
///
/// Centralise toutes les opérations cryptographiques liées à
/// l'identité des utilisateurs et des appareils.
class IdentityService {
  IdentityService._();
  static final IdentityService instance = IdentityService._();

  final crypto.CryptoUtils _crypto = crypto.CryptoUtils.instance;

  /// Génère un identifiant utilisateur éphémère (euid).
  String generateEphemeralUserId() => crypto.generateEphemeralUserId();

  /// Génère un identifiant aléatoire court (pour usage interne).
  String randomId([int bytes = 16]) => crypto.randomId(bytes);

  /// Signe les métadonnées d'une alerte avec Ed25519.
  Future<crypto.SignedAlert> signAlert({
    required String alertId,
    required String type,
    required double lat,
    required double lng,
    required DateTime createdAt,
  }) =>
      _crypto.signAlert(
        alertId: alertId,
        type: type,
        lat: lat,
        lng: lng,
        createdAt: createdAt,
      );

  /// Vérifie la signature Ed25519 d'une alerte.
  Future<bool> verifyAlert({
    required String alertId,
    required String type,
    required double lat,
    required double lng,
    required DateTime createdAt,
    required String signatureB64,
    required String publicKeyB64,
  }) =>
      _crypto.verifyAlert(
        alertId: alertId,
        type: type,
        lat: lat,
        lng: lng,
        createdAt: createdAt,
        signatureB64: signatureB64,
        publicKeyB64: publicKeyB64,
      );

  /// Chiffre une adresse de serveur avec AES-256-CBC + HMAC-SHA256.
  Future<String> encryptAddress(String address, SecretKey masterKey) =>
      _crypto.encryptAddress(address, masterKey);

  /// Déchiffre une adresse de serveur.
  Future<String> decryptAddress(String cipher, SecretKey masterKey) =>
      _crypto.decryptAddress(cipher, masterKey);

  /// Dérive une clé AES-256 via PBKDF2 (100k itérations).
  Future<SecretKey> deriveAesKey(SecretKey masterKey, {List<int>? salt}) =>
      _crypto.deriveAesKey(masterKey, salt: salt);
}