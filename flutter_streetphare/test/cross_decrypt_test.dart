// test/cross_decrypt_test.dart
//
// TEST DE COMPATIBILITÉ CROISÉE Node.js -> Dart
//
// 1. Chiffre une URL avec server_crypto.js (Node)
// 2. Déchiffre le résultat avec CryptoUtils (Dart) — celui utilisé
//    par FailoverManager pour déchiffrer les `next_backup` reçus
//    du serveur.
//
// Si ce test passe, alors le failover bout-en-bout fonctionne
// pour de vrai dans l'environnement de test local.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_streetphare/database/crypto_utils.dart';

void main() {
  test('Dart déchiffre ce que Node a chiffré (AES-CBC+HMAC)', () async {
    // 1) On demande à Node de chiffrer l'URL du secondaire.
    final result = await Process.run('node', [
      '-e',
      "const c=require('./test_servers/server_crypto');"
      "const enc=c.encryptAddress('http://localhost:3001','streetphare-dev-key-CHANGE_ME_IN_PROD');"
      "console.log(enc);",
    ], workingDirectory: Directory.current.path);

    if (result.exitCode != 0) {
      fail('échec node: ${result.stderr}');
    }
    final cipher = (result.stdout as String).trim();
    expect(cipher, isNotEmpty);

    // 2) On déchiffre côté Dart.
    final key = await CryptoUtils.instance
        .deriveAesKey('streetphare-dev-key-CHANGE_ME_IN_PROD');
    final clear = await CryptoUtils.instance.decryptAddress(cipher, key);

    // 3) On compare.
    expect(clear, 'http://localhost:3001');
  });
}
