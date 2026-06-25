// lib/network/sync_service.dart
//
// Service de synchronisation différentielle Hive ↔ Serveur Node.js.
//
// Responsabilités :
//   1. Surveiller le transport réseau actif via [NetworkManager].
//   2. Lorsque le transport passe sur `cellular` (Internet dispo),
//      lancer un timer périodique de synchronisation (2–5 min).
//   3. Envoyer le dernier timestamp local connu au serveur
//      (GET /api/v2/sync-check?since=ISO8601).
//   4. Recevoir les deltas (alertes plus récentes), les fusionner
//      dans la base Hive locale, puis re-propager vers le mesh P2P.
//   5. Lorsque le transport quitte `cellular`, arrêter le timer.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models/alert_model.dart';
import '../database/hive_alert_database.dart';
import 'failover_manager.dart';
import 'network_manager.dart';

/// Service de synchronisation différentielle.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final HiveAlertDatabase _db = HiveAlertDatabase.instance;
  final FailoverManager _failover = FailoverManager.instance;

  Timer? _syncTimer;
  bool _started = false;
  StreamSubscription? _serverSub;

  /// Intervalle de synchronisation (3 minutes).
  static const Duration syncInterval = Duration(minutes: 3);

  /// Démarre la surveillance. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    // Écoute les basculements réseau pour activer/désactiver
    // la synchronisation selon le transport actif.
    NetworkManager.instance.addListener(_onNetworkChanged);

    // Écoute aussi le serveur primaire pour l'URL de sync.
    _serverSub = _failover.activeServer.listen((_) => _onServerChanged());

    // Vérifie l'état initial.
    _onNetworkChanged();
  }

  /// Arrêt propre.
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _serverSub?.cancel();
    NetworkManager.instance.removeListener(_onNetworkChanged);
    _started = false;
  }

  // ── Callbacks ─────────────────────────────────────────────────────────────

  void _onNetworkChanged() {
    final transport = NetworkManager.instance.currentTransport;
    if (transport == NetworkTransport.cellular) {
      _startSyncTimer();
    } else {
      _stopSyncTimer();
    }
  }

  void _onServerChanged() {
    // Si on est déjà en cellular, relance immédiatement une sync.
    if (NetworkManager.instance.currentTransport == NetworkTransport.cellular) {
      _startSyncTimer();
    }
  }

  // ── Timer de synchronisation ──────────────────────────────────────────────

  void _startSyncTimer() {
    _stopSyncTimer();
    // Sync immédiate, puis périodique.
    unawaited(_performSync());
    _syncTimer = Timer.periodic(syncInterval, (_) => _performSync());
    if (kDebugMode) {
      debugPrint('[SyncService] Timer démarré (intervalle=${syncInterval.inMinutes} min)');
    }
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // ── Logique de synchronisation ─────────────────────────────────────────────

  /// Effectue une synchronisation différentielle avec le serveur.
  ///
  /// 1. Récupère le dernier `lastModifiedAt` parmi les alertes locales.
  /// 2. Envoie GET /api/v2/sync-check?since=`timestamp`.
  /// 3. Le serveur répond avec les alertes modifiées depuis ce timestamp.
  /// 4. Fusionne les deltas dans Hive (upsert si plus récent).
  /// 5. Re-propagation vers le mesh (si des pairs réapparaissent).
  Future<void> _performSync() async {
    try {
      final serverBase = _failover.currentAddress;
      if (serverBase.isEmpty) return;

      // 1. Dernier timestamp local.
      final lastTs = _db.lastModifiedTimestamp();
      final since = lastTs?.toUtc().toIso8601String() ?? '';

      // 2. Requête de sync.
      final uri = Uri.parse('$serverBase/api/v2/sync-check')
          .replace(queryParameters: {'since': since});

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return;

      // 3. Fusion des deltas.
      int merged = 0;
      for (final item in items) {
        final remoteAlert = Alert.fromJson(item as Map<String, dynamic>);
        final localAlert = _db.getById(remoteAlert.id);

        if (localAlert == null) {
          // Nouvelle alerte → insérer.
          await _db.upsert(remoteAlert);
          merged++;
        } else if (remoteAlert.lastModifiedAt.isAfter(localAlert.lastModifiedAt)) {
          // Alerte distante plus récente → mettre à jour.
          await _db.upsert(remoteAlert);
          merged++;
        }
        // Sinon, la version locale est plus récente → ne rien faire.
      }

      if (kDebugMode && merged > 0) {
        debugPrint('[SyncService] $merged alerte(s) fusionnée(s) depuis le serveur');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SyncService] Erreur sync (non fatale): $e');
      }
    }
  }
}
