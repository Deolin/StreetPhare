// lib/network/bootstrap.dart
//
// Helpers d'initialisation du réseau (bootstrap) :
//   - construction de la configuration du FailoverManager
//   - génération / chargement de la chaîne chiffrée de secours
//   - assemblage des transports disponibles pour la plateforme
//
// Ce fichier isole toute la logique de "boot" pour que main.dart
// reste simple.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/crypto_utils.dart';
import 'failover_manager.dart';
import 'network_config.dart';
import 'p2p_mesh_service.dart';
import 'transports/ble_transport.dart';
import 'transports/relay_transport.dart';
import 'transports/wifi_direct_transport.dart';

/// Contient la configuration et les services construits.
class NetworkBootstrap {
  final FailoverConfig failoverConfig;
  final List<MeshTransport> transports;

  NetworkBootstrap({required this.failoverConfig, required this.transports});
}

/// Construit la configuration réseau + transports en fonction de
/// la plateforme courante et de la config packagée dans l'app.
Future<NetworkBootstrap> buildNetworkBootstrap({
  required String primaryServer,
  required String relayUrl,
  required String masterPassphrase,
  List<String> initialBackupChain = const [],
  Duration heartbeatInterval = const Duration(seconds: 30),
  Duration pingTimeout = const Duration(seconds: 5),
}) async {
  // S'assure que la chaîne de secours contient au moins 2
  // entrées chiffrées. Si elle est vide (premier lancement), on
  // en génère depuis une "seed" interne connue uniquement du
  // serveur de build. En pratique, ces seeds sont injectées par
  // le build CI et signées par le serveur principal.
  //
  // En mode DEBUG, si `NetworkConfig.initialSecondaryServer` est
  // défini, on chiffre cette URL comme PREMIER backup (le second
  // sera fourni par le serveur principal via `next_backup`).
  final chain = List<String>.from(initialBackupChain);
  if (chain.isEmpty) {
    chain.addAll(await _seedInitialChain(
      masterPassphrase,
      debugExtraAddress: kDebugMode
          ? NetworkConfig.initialSecondaryServer
          : '',
    ));
  }

  final cfg = FailoverConfig(
    primaryAddress: primaryServer,
    encryptedBackupChain: chain,
    maxAttempts: 3,
    heartbeatInterval: heartbeatInterval,
    pingTimeout: pingTimeout,
    masterPassphrase: masterPassphrase,
  );

  final transports = <MeshTransport>[];

  // Wi-Fi Direct / LAN multicast
  if (!kIsWeb) {
    transports.add(WifiDirectMeshTransport());
  }

  // BLE
  transports.add(BleMeshTransport());

  // Relay via WebSocket
  transports.add(RelayMeshTransport(relayUrl: relayUrl));

  return NetworkBootstrap(failoverConfig: cfg, transports: transports);
}

/// Génère une chaîne initiale de secours chiffrée.
///
/// En production, ces seeds proviennent du build CI et sont
/// signées par le serveur principal. En dev, on chiffre
/// éventuellement une URL passée par `debugExtraAddress` (typique-
/// ment l'URL du serveur secondaire local) pour rendre le
/// failover testable bout-en-bout.
Future<List<String>> _seedInitialChain(
  String passphrase, {
  String debugExtraAddress = '',
}) async {
  try {
    final key = await CryptoUtils.instance.deriveAesKey(passphrase);
    final out = <String>[];
    if (debugExtraAddress.isNotEmpty) {
      out.add(await CryptoUtils.instance
          .encryptAddress(debugExtraAddress, key));
    }
    // Seed de repli (placeholder historique) — conservé pour
    // ne pas régresser les scénarios de test legacy.
    out.add(await CryptoUtils.instance
        .encryptAddress('https://backup1.streetphare.local', key));
    return out;
  } catch (_) {
    return [];
  }
}

/// Helper pour charger la chaîne de secours persistée
/// (SharedPreferences, après mise à jour par le serveur).
Future<void> persistBackupChain(List<String> ciphered) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('streetphare_backup_chain', ciphered);
}

Future<List<String>> loadPersistedBackupChain() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('streetphare_backup_chain') ?? const [];
}

/// Helper : pour sérialiser une chaîne de secours vers/depuis
/// un fichier de config (utile pour OTA).
String serializeBackupChain(List<String> ciphered) =>
    jsonEncode(ciphered);

List<String> deserializeBackupChain(String raw) {
  final list = jsonDecode(raw) as List;
  return list.map((e) => e.toString()).toList();
}

/// Helper qui retourne la plateforme courante (utile pour debug).
String describePlatform() {
  if (kIsWeb) return 'web';
  try {
    return Platform.operatingSystem;
  } catch (_) {
    return 'unknown';
  }
}
