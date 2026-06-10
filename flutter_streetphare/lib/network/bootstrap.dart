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
import 'dart:math' as math;

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
  final String peerId;

  NetworkBootstrap({
    required this.failoverConfig,
    required this.transports,
    required this.peerId,
  });
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

  // Identifiant de session anonyme STABLE. Utilisé comme peerId
  // par les transports pour que les pairs distants puissent
  // dédupliquer nos pings dans leur fenêtre glissante (cf.
  // contrat anti-double-comptage du PeerCounterService).
  // Persisté dans SharedPreferences pour rester stable d'un
  // lancement de l'app à l'autre.
  final sharedPeerId = await loadOrCreateStablePeerId();

  final transports = <MeshTransport>[];

  // Wi-Fi Direct / LAN multicast
  if (!kIsWeb) {
    transports.add(
      WifiDirectMeshTransport(peerId: sharedPeerId),
    );
  }

  // BLE : peerId stable = clé de déduplication du compteur HIVE.
  transports.add(
    BleMeshTransport(peerId: sharedPeerId),
  );

  // Relay via WebSocket
  transports.add(
    RelayMeshTransport(relayUrl: relayUrl, peerId: sharedPeerId),
  );

  return NetworkBootstrap(
    failoverConfig: cfg,
    transports: transports,
    peerId: sharedPeerId,
  );
}

/// Charge (ou génère + persiste) un identifiant de session
/// anonyme STABLE d'un lancement de l'app à l'autre. C'est la
/// clé qui permet aux pairs distants de dédupliquer nos pings
/// dans leur fenêtre glissante de 60 secondes.
///
/// L'ID est stocké sous la clé `streetphare.peer_id` dans
/// SharedPreferences. Tant qu'il existe, on le réutilise tel
/// quel (pas de rotation pendant la durée de vie de l'app).
Future<String> loadOrCreateStablePeerId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const key = 'streetphare.peer_id';
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    // Génère un nouvel ID anonyme (16 octets hex → 32 caractères).
    final id = _generatePeerId();
    await prefs.setString(key, id);
    return id;
  } catch (_) {
    // Fallback non persistant : moins idéal, mais évite de crasher.
    return _generatePeerId();
  }
}

/// Génère un identifiant de session anonyme. Format : `sp-XXXXXXXX`
/// (préfixe lisible + 16 octets hex). Utilise un générateur
/// cryptographique si disponible (web), `Random.secure()` sinon.
String _generatePeerId() {
  final bytes = List<int>.generate(8, (_) => _secureNextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'sp-$hex';
}

int _secureNextInt(int max) {
  try {
    return math.Random.secure().nextInt(max);
  } catch (_) {
    return math.Random().nextInt(max);
  }
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
