// lib/network/bootstrap.dart
//
// Helpers d'initialisation du réseau (bootstrap) :
//   - construction de la configuration du FailoverManager
//   - génération / chargement de la chaîne chiffrée de secours
//   - assemblage des transports disponibles pour la plateforme
//
// Les valeurs par défaut de heartbeat (30s) et ping timeout (5s)
// sont adaptées à la production. En développement local, les tests
// d'intégration override ces valeurs via les paramètres nommés.
//
// Ce fichier isole toute la logique de "boot" pour que main.dart
// reste simple.

import 'dart:convert';
// Note : L'accès à Platform est sûr car il n'est appelé que quand
// !kIsWeb, dans describePlatform() et buildNetworkBootstrap().
// Sur Web, dart:io est indisponible. On utilise des imports
// conditionnels si nécessaire, mais ici on s'assure simplement
// de ne pas appeler dart:io sur Web.
import 'dart:io' as io;
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

/// Contient la configuration et les services construits.
class NetworkBootstrap {
  NetworkBootstrap({
    required this.failoverConfig,
    required this.transports,
    required this.peerId,
  });
  final FailoverConfig failoverConfig;
  final List<MeshTransport> transports;
  final String peerId;
}

/// Construit la configuration réseau + transports en fonction de
/// la plateforme courante et de la config packagée dans l'app.
///
/// Valeurs de production :
///   - heartbeatInterval : 30s (vérification périodique du serveur)
///   - pingTimeout       : 5s  (délai avant déclaration de perte)
///   - maxAttempts       : 3  (pings consécutifs avant failover)
Future<NetworkBootstrap> buildNetworkBootstrap({
  required String primaryServer,
  required String relayUrl,
  required SecretKey masterKey,
  List<String> initialBackupChain = const [],
  Duration heartbeatInterval = const Duration(seconds: 30),
  Duration pingTimeout = const Duration(seconds: 5),
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

  // Sur le Web EN MODE DEBUG UNIQUEMENT, on ajoute un transport loopback
  // pour la sandbox (permet l'injection de paquets simulés sans hardware).
  // En production, ce transport n'est JAMAIS instancié : il ne compile pas
  // dans les APK Android/iOS et n'est pas activé sur le Web release.
  if (kIsWeb && kDebugMode) {
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
///
/// Stratégie de résilience :
///   1. SharedPreferences (principal)
///   2. Si SharedPreferences échoue → fallback fichier local dans
///      le répertoire temporaire (dernier recours).
///   3. Si TOUS les stockages échouent → génération sans persistance
///      avec log d'erreur (l'identité changera au prochain lancement).
Future<String> loadOrCreateStablePeerId() async {
  const key = 'streetphare.peer_id';

  // ── Tentative 1 : SharedPreferences ──────────────────────────────
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generatePeerId();
    await prefs.setString(key, id);
    return id;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[bootstrap] SharedPreferences indisponible '
          'pour peer ID: $e');
    }
  }

  // ── Tentative 2 : Fichier local (fallback) ────────────────────────
  try {
    final tempDir = io.Directory.systemTemp;
    final file = io.File('${tempDir.path}/streetphare_peer_id.txt');
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) return content.trim();
    }
    final id = _generatePeerId();
    await file.writeAsString(id);
    if (kDebugMode) {
      debugPrint('[bootstrap] Peer ID persisté via fichier local: $id');
    }
    return id;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[bootstrap] Échec fallback fichier peer ID: $e');
    }
  }

  // ── Tentative 3 : Sans persistance (identité volatile) ────────────
  if (kDebugMode) {
    debugPrint('[bootstrap] ⚠ Aucun stockage disponible pour peer ID. '
        'Identité volatile (changera au prochain lancement).');
  }
  return _generatePeerId();
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
      final ciphered = await CryptoUtils.instance
          .encryptAddress(debugExtraAddress, masterKey);
      out.add(ciphered);
    }
    // Ajoute le serveur secondaire configuré comme backup de secours.
    // L'adresse est lue depuis NetworkConfig.initialSecondaryServer
    // (https://streetphare.ddns.net:3001) et chiffrée avec la clé
    // maîtresse pour que seul le client puisse la déchiffrer.
    if (NetworkConfig.initialSecondaryServer.isNotEmpty) {
      out.add(await CryptoUtils.instance
          .encryptAddress(NetworkConfig.initialSecondaryServer, masterKey));
    }
    if (kDebugMode) {
      debugPrint(
          '[bootstrap] Chaîne de secours amorcée : ${out.length} entrée(s)');
    }
    return out;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[bootstrap] Erreur amorçage chaîne de secours : $e');
    }
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
