// lib/core/security/keystore_service.dart
//
// Service de stockage sécurisé de la clé maîtresse.
//
// Génère une clé aléatoire de 32 octets au premier lancement et la
// persiste dans le keystore sécurisé de l'OS (Android Keystore /
// iOS Keychain). Les lancements suivants récupèrent la clé existante.
//
// Remplace l'approche précédente qui utilisait
// `String.fromEnvironment('STREETPHARE_MASTER_KEY')` (compilée en
// dur dans le binaire, non rotative, sans protection keystore).
//
// Fallback Web : sur le Web, `flutter_secure_storage` utilise
// localStorage avec chiffrement logiciel. Pour le développement
// uniquement, une clé déterministe est générée.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service de gestion de la clé maîtresse dans le keystore OS.
class KeyStoreService {
  KeyStoreService._();
  static final KeyStoreService instance = KeyStoreService._();

  static const _keyName = 'streetphare_master_key';
  static const _keyLength = 32; // 256 bits pour AES-256

  final _storage = FlutterSecureStorage(
    aOptions: const AndroidOptions(
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  SecretKey? _cachedKey;

  /// Récupère ou génère la clé maîtresse depuis le keystore sécurisé.
  ///
  /// Au premier lancement, une clé aléatoire de 32 octets (256 bits)
  /// est générée et stockée. Les lancements suivants la récupèrent.
  Future<SecretKey> loadOrCreateMasterKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final existing = await _storage.read(key: _keyName);

    if (existing != null && existing.isNotEmpty) {
      try {
        final bytes = base64.decode(existing);
        if (bytes.length == _keyLength) {
          _cachedKey = SecretKey(bytes);
          return _cachedKey!;
        }
      } catch (_) {
        // Clé corrompue → régénération.
        if (kDebugMode) {
          debugPrint('[KeyStoreService] clé corrompue détectée, régénération');
        }
        await _storage.delete(key: _keyName);
      }
    }

    // Génération d'une nouvelle clé aléatoire.
    final newKey = _generateRandomKey();
    final encoded = base64.encode(newKey);
    await _storage.write(key: _keyName, value: encoded);
    _cachedKey = SecretKey(newKey);

    if (kDebugMode) {
      debugPrint('[KeyStoreService] nouvelle clé maîtresse générée et stockée');
    }

    return _cachedKey!;
  }

  /// Génère une clé aléatoire de 32 octets (256 bits).
  List<int> _generateRandomKey() {
    final rng = Random.secure();
    return List<int>.generate(_keyLength, (_) => rng.nextInt(256));
  }

  /// Supprime la clé du keystore (utile pour les tests).
  Future<void> deleteKey() async {
    _cachedKey = null;
    await _storage.delete(key: _keyName);
  }
}