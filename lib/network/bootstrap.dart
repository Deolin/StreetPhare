// lib/network/bootstrap.dart
//
// Helpers d'initialisation du réseau (bootstrap) :
//   - construction de la configuration du FailoverManager
//   - génération / chargement de la chaîne chiffrée de secours
//   - assemblage des transports disponibles pour la plateforme
//
// Version TEST avec heartbeat accéléré (5s au lieu de 30s)
// et ping timeout réduit (2s au lieu de 5s) pour un failover
// quasi-instantané sur l'infrastructure locale.
//
// Ce fichier isole toute la logique de "boot" pour que main.dart
// reste simple.

import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/crypto_utils.dart';
import 'failover_manager.dart';
import 'network_config.dart';
import 'p2p_mesh_service.dart';
import 'transports/ble_transport.dart';
import 'transports/loopback_transport.dart';
import 'transports/relay_transport.dart';
import 'transports/wifi_direct_transport_selector.dart';

// Note : L'accès à Platform est sûr car il n'est appelé que quand
// !kIsWeb, dans describePlatform() et buildNetworkBootstrap().
// Sur Web, dart:io est indisponible. On utilise des imports
// conditionnels si nécessaire, mais ici on s'assure simplement
// de ne pas appeler dart:io sur Web.
import 'dart:io' as io;

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
  required SecretKey masterKey,
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
      masterKey,
      debugExtraAddress: NetworkConfig.initialSecondaryServer,
    ));
  }

  final cfg = FailoverConfig(
    primaryAddress: primaryServer,
    encryptedBackupChain: chain,
    maxAttempts: 3,
    heartbeatInterval: heartbeatInterval,
    pingTimeout: pingTimeout,
    masterKey: masterKey,
  );

  // Identifiant de session anonyme STABLE.
  final sharedPeerId = await loadOrCreateStablePeerId();

  final transports = <MeshTransport>[];

  // ── Transports P2P physiques UNIQUEMENT sur plateformes natives ─────
  // Sur le Web, les API BLE/Wi-Fi Direct ne sont pas disponibles ou sont
  // instables. On ne les instancie PAS du tout pour éviter tout crash
  // natif (UnimplementedError, MissingPluginException, etc.).
  //
  // Le Web s'appuie exclusivement sur :
  //   1. Le Relay WebSocket (relais centralisé pour le mesh virtuel)
  //   2. Le LoopbackTransport (sandbox locale pour les tests hors-ligne)
  //
  // Les plateformes desktop (Windows/Linux) n'ont pas de BLE natif non plus
  // mais conservent le Wi-Fi Direct multicast.

  if (!kIsWeb) {
    // Wi-Fi Direct / LAN multicast — natif uniquement
    transports.add(
      WifiDirectMeshTransport(peerId: sharedPeerId),
    );

    // BLE — Android, iOS, macOS uniquement (pas Windows/Linux desktop)
    if (!io.Platform.isWindows && !io.Platform.isLinux) {
      transports.add(BleMeshTransport(peerId: sharedPeerId));
    }
  }

  // Relay via WebSocket (cross-platform, y compris Web)
  transports.add(
    RelayMeshTransport(relayUrl: relayUrl, peerId: sharedPeerId),
  );

  // Sur le Web, on ajoute un transport loopback pour la sandbox
  // (permet l'injection de paquets simulés sans hardware physique).
  if (kIsWeb) {
    // Import dynamique pour éviter la compilation conditionnelle
    // Le fichier loopback_transport.dart n'importe aucune dépendance native.
    transports.add(LoopbackMeshTransport(peerId: sharedPeerId));
  }

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
  SecretKey masterKey, {
  String debugExtraAddress = '',
}) async {
  try {
    final out = <String>[];
    if (debugExtraAddress.isNotEmpty) {
      out.add(await CryptoUtils.instance
          .encryptAddress(debugExtraAddress, masterKey));
    }
    out.add(await CryptoUtils.instance
        .encryptAddress('https://backup1.streetphare.local', masterKey));
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

String serializeBackupChain(List<String> ciphered) => jsonEncode(ciphered);

List<String> deserializeBackupChain(String raw) {
  final list = jsonDecode(raw) as List;
  return list.map((e) => e.toString()).toList();
}

String describePlatform() {
  if (kIsWeb) return 'web';
  try {
    return io.Platform.operatingSystem;
  } catch (_) {
    return 'unknown';
  }
}
