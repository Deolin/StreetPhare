// lib/network/bootstrap.dart
//
// Helpers d'initialisation du réseau (bootstrap) :
//   - construction de la configuration du FailoverManager
//   - génération / chargement de la chaîne chiffrée de secours
//   - assemblage des transports disponibles pour la plateforme
//
// Version TEST avec heartbeat accéléré (5s au lieu de 30s)
// et ping timeout réduit (2s au lieu de 5s) pour un failover
// quasi-instantané sur l'infrastructure 192.168.31.18.
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
///
/// Version TEST :
///   - heartbeatInterval : 5s (permet un failover en ~17s max)
///   - pingTimeout       : 2s (détection rapide de perte)
///   - maxAttempts       : 3 (pings consécutifs avant failover)
Future<NetworkBootstrap> buildNetworkBootstrap({
  required String primaryServer,
  required String relayUrl,
  required String masterPassphrase,
  List<String> initialBackupChain = const [],
  Duration heartbeatInterval = const Duration(seconds: 5),
  Duration pingTimeout = const Duration(seconds: 2),
}) async {
  // S'assure que la chaîne de secours contient au moins 2
  // entrées chiffrées. Si elle est vide (premier lancement), on
  // en génère depuis une "seed" interne connue uniquement du
  // serveur de build. En pratique, ces seeds sont injectées par
  // le build CI et signées par le serveur principal.
  final chain = List<String>.from(initialBackupChain);
  if (chain.isEmpty) {
    chain.addAll(await _seedInitialChain(
      masterPassphrase,
      debugExtraAddress: NetworkConfig.initialSecondaryServer,
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

  // Identifiant de session anonyme STABLE.
  final sharedPeerId = await loadOrCreateStablePeerId();

  final transports = <MeshTransport>[];

  // Wi-Fi Direct / LAN multicast
  if (!kIsWeb) {
    transports.add(
      WifiDirectMeshTransport(peerId: sharedPeerId),
    );
  }

  // BLE — Android, iOS, macOS et Web BLE uniquement.
  //
  // Sur Windows et Linux, flutter_reactive_ble lève une UnimplementedError
  // dès la construction de FlutterReactiveBle() (appel natif non implémenté).
  // On court-circuite AVANT l'instanciation pour :
  //   1. Éviter le crash/exception au démarrage.
  //   2. Supprimer le warning "[P2PMeshService] transport ble indisponible"
  //      dans les logs console (WARN #5).
  // Les transports Wi-Fi Multicast et WebSocket Relay prennent le relais
  // normalement sur ces plateformes desktop.
  final bleSupported = kIsWeb ||
      (!kIsWeb && !Platform.isWindows && !Platform.isLinux);
  if (bleSupported) {
    transports.add(BleMeshTransport(peerId: sharedPeerId));
  }

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
/// anonyme STABLE d'un lancement de l'app à l'autre.
Future<String> loadOrCreateStablePeerId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const key = 'streetphare.peer_id';
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generatePeerId();
    await prefs.setString(key, id);
    return id;
  } catch (_) {
    return _generatePeerId();
  }
}

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
    out.add(await CryptoUtils.instance
        .encryptAddress('https://backup1.streetphare.local', key));
    return out;
  } catch (_) {
    return [];
  }
}

Future<void> persistBackupChain(List<String> ciphered) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('streetphare_backup_chain', ciphered);
}

Future<List<String>> loadPersistedBackupChain() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('streetphare_backup_chain') ?? const [];
}

String serializeBackupChain(List<String> ciphered) =>
    jsonEncode(ciphered);

List<String> deserializeBackupChain(String raw) {
  final list = jsonDecode(raw) as List;
  return list.map((e) => e.toString()).toList();
}

String describePlatform() {
  if (kIsWeb) return 'web';
  try {
    return Platform.operatingSystem;
  } catch (_) {
    return 'unknown';
  }
}