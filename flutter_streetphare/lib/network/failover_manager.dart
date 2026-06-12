// lib/network/failover_manager.dart
//
// Gestionnaire de basculement de serveur (Failover Manager).
//
// Responsabilités :
//   1. Conserver en mémoire l'adresse du Serveur Principal courant.
//   2. Conserver une chaîne (file) de secours d'adresses CHIFFREES
//      AES des Serveurs Secondaires.
//   3. Effectuer un heartbeat (ping) régulier sur le serveur courant.
//   4. Si le serveur courant ne répond pas après X tentatives,
//      il est marqué "Défaillant" et DEFINITIVEMENT OUBLIE pour la
//      session (jamais retenté avant la fin de session).
//   5. L'application déchiffre alors la première adresse de la
//      chaîne de secours, qui devient le nouveau Principal.
//   6. Après un basculement réussi, le nouveau serveur peut fournir
//      une nouvelle adresse cryptée de backup, qu'on insère en
//      queue de chaîne. La liste reste ainsi auto-entretenue.
//
// Le logger `ClientDebugLogger` (lib/debug/client_debug_logger.dart)
// est notifié à chaque étape clé pour produire un fichier
// `CLIENT_DEBUG.md` (cf. mode kDebugMode).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../database/crypto_utils.dart';
import '../debug/client_debug_logger.dart';

/// Statut d'un serveur connu du FailoverManager.
enum ServerStatus { active, failed, standby }

/// Représente un serveur (adresse en clair ou chiffrée).
class ServerEndpoint {
  final String address;
  final String encryptedAddress;
  final ServerStatus status;
  final int consecutiveFailures;
  final DateTime lastChecked;
  final DateTime markedFailedAt;

  const ServerEndpoint({
    required this.address,
    required this.encryptedAddress,
    required this.status,
    required this.consecutiveFailures,
    required this.lastChecked,
    required this.markedFailedAt,
  });

  ServerEndpoint copyWith({
    String? address,
    String? encryptedAddress,
    ServerStatus? status,
    int? consecutiveFailures,
    DateTime? lastChecked,
    DateTime? markedFailedAt,
  }) {
    return ServerEndpoint(
      address: address ?? this.address,
      encryptedAddress: encryptedAddress ?? this.encryptedAddress,
      status: status ?? this.status,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastChecked: lastChecked ?? this.lastChecked,
      markedFailedAt: markedFailedAt ?? this.markedFailedAt,
    );
  }
}

/// Réponse du serveur central après un appel de synchronisation.
/// Le serveur peut renvoyer un nouvel endpoint chiffré pour
/// étendre la chaîne de secours.
class SyncResponse {
  final bool success;
  final String serverAddress;
  final String nextBackupCipher;

  const SyncResponse({
    required this.success,
    required this.serverAddress,
    required this.nextBackupCipher,
  });

  factory SyncResponse.fromJson(Map<String, dynamic> j) => SyncResponse(
        success: (j['ok'] as bool?) ?? false,
        serverAddress: (j['server'] as String?) ?? '',
        nextBackupCipher: (j['next_backup'] as String?) ?? '',
      );
}

  /// Configuration du FailoverManager.
  ///
  /// Version TEST avec heartbeat accéléré :
  ///   - heartbeatInterval : 5s (au lieu de 30s)
  ///   - pingTimeout       : 2s (au lieu de 5s)
  ///   - maxAttempts       : 3 pings consécutifs
  ///
  /// Basculement théorique le plus rapide : 3 × 5s + 2s = ~17s max
  /// En pratique, le premier ping KO est détecté en 2s.
  /// Dès le 3ème KO consécutif (15s écoulées), le failover est
  /// déclenché instantanément.
  class FailoverConfig {
    /// URL du serveur principal initial (intégré dans l'app, peut
    /// être mis à jour via OTA / build flags).
    final String primaryAddress;

    /// Liste des adresses de secours chiffrées (AES).
    /// La première est utilisée en premier lors d'un basculement.
    final List<String> encryptedBackupChain;

    /// Nombre de tentatives avant de marquer un serveur défaillant.
    final int maxAttempts;

    /// Délai entre deux heartbeats.
    final Duration heartbeatInterval;

    /// Timeout d'une tentative individuelle de ping.
    final Duration pingTimeout;

    /// Master passphrase pour dériver la clé AES. En production,
    /// ce devrait être une clé issue du secure-storage iOS/Android
    /// ou d'un serveur de clés distant.
    final String masterPassphrase;

    const FailoverConfig({
      required this.primaryAddress,
      required this.encryptedBackupChain,
      this.maxAttempts = 3,
      this.heartbeatInterval = const Duration(seconds: 5),
      this.pingTimeout = const Duration(seconds: 2),
      required this.masterPassphrase,
    });
  }

/// FailoverManager singleton.
class FailoverManager {
  FailoverManager._();
  static final FailoverManager instance = FailoverManager._();

  FailoverConfig? _config;
  ServerEndpoint? _current;

  /// File des endpoints de secours (chiffrés) en attente.
  final List<ServerEndpoint> _standbys = [];

  /// Cache des serveurs définitivement marqués défaillants
  /// pour la session (jamais retentés).
  final Set<String> _deadForSession = {};

  SecretKey? _aesKey;
  Timer? _heartbeatTimer;

  final _activeServerController = StreamController<ServerEndpoint>.broadcast();
  Stream<ServerEndpoint> get activeServer => _activeServerController.stream;

  bool _started = false;

  /// Initialise le gestionnaire avec la configuration de l'app.
  Future<void> init(FailoverConfig config) async {
    if (_started) return;
    _config = config;

    _aesKey = await CryptoUtils.instance.deriveAesKey(config.masterPassphrase);

    _current = ServerEndpoint(
      address: config.primaryAddress,
      encryptedAddress: '',
      status: ServerStatus.active,
      consecutiveFailures: 0,
      lastChecked: DateTime.now().toUtc(),
      markedFailedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );

    // Pré-décrypte et charge la chaîne de secours en mémoire
    // (mais reste en standby tant qu'on n'en a pas besoin).
    final decryptedAddrs = <String>[];
    for (final cipher in config.encryptedBackupChain) {
      try {
        final clear = await CryptoUtils.instance
            .decryptAddress(cipher, _aesKey!);
        _standbys.add(ServerEndpoint(
          address: clear,
          encryptedAddress: cipher,
          status: ServerStatus.standby,
          consecutiveFailures: 0,
          lastChecked: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          markedFailedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));
        decryptedAddrs.add(clear);
        ClientDebugLogger.instance.backupDecrypted(
          cipher: cipher,
          clear: clear,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FailoverManager] déchiffrement backup échoué: $e');
        }
      }
    }

    // Notifie le logger client : bootstrap terminé, on connaît
    // le principal et la chaîne de secours déchiffrée.
    ClientDebugLogger.instance.bootstrapReady(
      primaryAddress: config.primaryAddress,
      decryptedBackupChain: decryptedAddrs,
    );

    if (kDebugMode) {
      debugPrint(
        '[FailoverManager] init ok. principal=${_current!.address} '
        'standbys=${_standbys.length}',
      );
    }
  }

  /// Démarre la boucle de heartbeat.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _heartbeatTimer =
        Timer.periodic(_config!.heartbeatInterval, (_) => heartbeat());
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _started = false;
  }

  /// Adresse du serveur central courant.
  String get currentAddress => _current?.address ?? '';

  /// Liste des serveurs définitivement défaillants dans la session.
  Set<String> get deadServersForSession => Set.unmodifiable(_deadForSession);

  /// Effectue un ping sur le serveur courant.
  /// En cas d'échec répété, bascule vers le premier standby.
  Future<bool> heartbeat() async {
    if (_config == null || _current == null) return false;
    final ok = await _ping(_current!.address);
    _current = _current!.copyWith(
      lastChecked: DateTime.now().toUtc(),
      consecutiveFailures: ok ? 0 : _current!.consecutiveFailures + 1,
    );
    ClientDebugLogger.instance.heartbeat(
      address: _current!.address,
      ok: ok,
    );
    if (ok) return true;

    if (kDebugMode) {
      debugPrint(
        '[FailoverManager] heartbeat KO '
        '(${_current!.consecutiveFailures}/${_config!.maxAttempts})',
      );
    }

    if (_current!.consecutiveFailures >= _config!.maxAttempts) {
      await _failover();
    }
    return false;
  }

  /// Marque le serveur courant comme défaillant et bascule sur
  /// le premier standby disponible.
  Future<void> _failover() async {
    if (_current == null) return;
    final dying = _current!.address;
    _deadForSession.add(dying);
    _current = _current!.copyWith(
      status: ServerStatus.failed,
      markedFailedAt: DateTime.now().toUtc(),
    );
    if (kDebugMode) {
      debugPrint('[FailoverManager] serveur $dying marqué DÉFAILLANT');
    }
    ClientDebugLogger.instance.serverMarkedDead(dying);

    while (_standbys.isNotEmpty) {
      final next = _standbys.removeAt(0);
      if (_deadForSession.contains(next.address)) continue;
      if (await _ping(next.address)) {
        _current = next.copyWith(
          status: ServerStatus.active,
          consecutiveFailures: 0,
          lastChecked: DateTime.now().toUtc(),
        );
        _activeServerController.add(_current!);
        if (kDebugMode) {
          debugPrint(
            '[FailoverManager] basculé vers ${_current!.address}',
          );
        }
        ClientDebugLogger.instance.failoverSucceeded(
          fromAddress: dying,
          toAddress: _current!.address,
        );
        return;
      } else {
        _deadForSession.add(next.address);
        ClientDebugLogger.instance.serverMarkedDead(next.address);
        if (kDebugMode) {
          debugPrint(
            '[FailoverManager] standby ${next.address} injoignable, '
            'marqué défaillant',
          );
        }
      }
    }

    if (kDebugMode) {
      debugPrint('[FailoverManager] AUCUN serveur de secours disponible !');
    }
    ClientDebugLogger.instance.failoverFailed(fromAddress: dying);
    _current = _current!.copyWith(
      status: ServerStatus.failed,
      markedFailedAt: DateTime.now().toUtc(),
    );
    _activeServerController.add(_current!);
  }

  /// Ping HTTP(S) minimaliste. Le serveur central doit exposer
  /// un endpoint /healthz (ou /ping) qui renvoie 2xx.
  Future<bool> _ping(String address) async {
    try {
      final uri = Uri.parse('$address/healthz');
      final client = HttpClient()..connectionTimeout = _config!.pingTimeout;
      final req = await client.getUrl(uri);
      req.headers.add('X-StreetPhare-Heartbeat', '1');
      final resp = await req.close().timeout(_config!.pingTimeout);
      await resp.drain<void>();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Tente un upload d'alerte sur le serveur courant. Si le
  /// serveur répond OK, on garde éventuellement un nouveau
  /// backup chiffré qu'il nous renvoie pour la chaîne suivante.
  Future<bool> uploadAlerts(List<dynamic> alerts) async {
    if (_current == null) return false;
    final targetAddress = _current!.address;
    if (_current!.status != ServerStatus.active) {
      // Tente un heartbeat frais avant d'envoyer.
      final ok = await heartbeat();
      if (!ok || _current!.status != ServerStatus.active) {
        ClientDebugLogger.instance.uploadAttempted(
          address: targetAddress,
          alertCount: alerts.length,
          success: false,
          error: 'serveur inactif',
        );
        return false;
      }
    }

    try {
      final uri = Uri.parse('${_current!.address}/v1/alerts/sync');
      final client = HttpClient()..connectionTimeout = _config!.pingTimeout;
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode(jsonEncode({'alerts': alerts})));
      final resp = await req.close().timeout(_config!.pingTimeout);
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // Tente d'extraire un nouveau backup que le serveur nous
        // communiquerait (rotation auto-entretenue).
        try {
          final parsed = jsonDecode(body) as Map<String, dynamic>;
          final next = SyncResponse.fromJson(parsed);
          if (next.nextBackupCipher.isNotEmpty) {
            await _enqueueNextBackup(next.nextBackupCipher);
          }
        } catch (_) {}
        ClientDebugLogger.instance.uploadAttempted(
          address: targetAddress,
          alertCount: alerts.length,
          success: true,
        );
        return true;
      }
      ClientDebugLogger.instance.uploadAttempted(
        address: targetAddress,
        alertCount: alerts.length,
        success: false,
        error: 'HTTP ${resp.statusCode}',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FailoverManager] upload échoué: $e');
      }
      ClientDebugLogger.instance.uploadAttempted(
        address: targetAddress,
        alertCount: alerts.length,
        success: false,
        error: e.toString(),
      );
    }
    return false;
  }

  /// Ajoute un nouveau backup à la queue de la chaîne de secours
  /// (en le déchiffrant pour vérifier son intégrité).
  Future<void> _enqueueNextBackup(String cipher) async {
    try {
      final clear = await CryptoUtils.instance
          .decryptAddress(cipher, _aesKey!);
      if (_deadForSession.contains(clear)) return;
      if (_current?.address == clear) return;
      _standbys.add(ServerEndpoint(
        address: clear,
        encryptedAddress: cipher,
        status: ServerStatus.standby,
        consecutiveFailures: 0,
        lastChecked: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        markedFailedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ));
      if (kDebugMode) {
        debugPrint(
          '[FailoverManager] nouveau backup en queue: $clear '
          '(total=${_standbys.length})',
        );
      }
      ClientDebugLogger.instance.backupEnqueued(cipher: cipher, clear: clear);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FailoverManager] backup reçu invalide: $e');
      }
    }
  }

  /// Pour tests : remet à zéro l'état (NE PAS utiliser en prod).
  void resetForTests() {
    _started = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _current = null;
    _standbys.clear();
    _deadForSession.clear();
    _aesKey = null;
    _config = null;
  }
}
