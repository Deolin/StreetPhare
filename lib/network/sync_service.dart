// lib/network/sync_service.dart
//
// Service de synchronisation bidirectionnelle Hive ↔ Serveur Node.js.
//
// Responsabilités :
//   1. Surveiller le transport réseau actif via [NetworkManager].
//   2. Lorsque le transport passe sur `cellular` (Internet dispo),
//      lancer un timer périodique de synchronisation (3 min).
//   3. PUSH : Envoyer les alertes locales modifiées depuis la dernière
//      synchronisation vers le serveur (POST /api/sync-push).
//   4. PULL : Recevoir les deltas (alertes plus récentes côté serveur),
//      les fusionner dans la base Hive locale.
//   5. Re-propager les alertes reçues vers le mesh P2P.
//   6. Lorsque le transport quitte `cellular`, arrêter le timer.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/models/alert_model.dart';
import '../core/network/peer_counter_service.dart';
import '../database/hive_alert_database.dart';
import 'failover_manager.dart';
import 'network_manager.dart';

/// Résultat d'une opération de synchronisation.
enum _SyncResult { success, failed, rateLimited }

/// Service de synchronisation bidirectionnelle (push + pull).
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final HiveAlertDatabase _db = HiveAlertDatabase.instance;
  final FailoverManager _failover = FailoverManager.instance;

  Timer? _syncTimer;
  bool _started = false;
  StreamSubscription? _serverSub;

  /// Dernier timestamp de synchronisation réussie (pull).
  /// Initialisé à null → première sync = full pull.
  DateTime? _lastPullTs;

  /// Dernier timestamp de push réussi.
  /// Les alertes modifiées après cette date seront poussées.
  DateTime? _lastPushTs;

  /// Intervalle de synchronisation (3 minutes).
  static const Duration syncInterval = Duration(minutes: 3);

  /// Timeout HTTP pour les requêtes de sync.
  static const Duration syncTimeout = Duration(seconds: 15);

  /// Nombre maximal d'alertes locales à pousser par cycle.
  static const int maxPushBatchSize = 200;

  /// Backoff rate-limit : timestamp jusqu'auquel toute sync est suspendue.
  /// Sert à éviter les boucles de retry quand le serveur répond 429.
  DateTime? _rateLimitedUntil;
  static const Duration _maxRateLimitBackoff = Duration(minutes: 5);

  /// Démarre la surveillance. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    // Écoute les basculements réseau pour activer/désactiver
    // la synchronisation selon le transport actif.
    NetworkManager.instance.addListener(_onNetworkChanged);

    // Écoute aussi le serveur primaire pour l'URL de sync.
    _serverSub = _failover.activeServer.listen((_) => _onServerChanged());

    // Surveille le compteur de pairs BLE : dès qu'un pair apparaît,
    // flush l'outbox des messages en attente.
    PeerCounterService.instance.addListener(_onPeersChanged);

    // Vérifie l'état initial.
    _onNetworkChanged();
  }

  /// Déclenché quand le nombre de pairs BLE change.
  /// Si un pair apparaît (0 → >0), vide l'outbox pour envoyer
  /// tous les signalements en attente vers le nouveau pair.
  void _onPeersChanged() {
    final count = PeerCounterService.instance.value;
    if (count > 0) {
      // Un pair StreetPhare est à portée → flush immédiat.
      if (kDebugMode) {
        debugPrint('[SyncService] $count pair(s) BLE détecté(s) → '
            'flush outbox');
      }
      // Le flush est géré par P2PMeshService via NetworkCoordinator.
      // On force un upload immédiat des alertes validées + flush outbox.
      unawaited(_failover.currentAddress.isNotEmpty
          ? Future.wait([
              _pushAndPull(),
            ])
          : Future.value());
    }
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
    unawaited(_pushAndPull());
    _syncTimer = Timer.periodic(syncInterval, (_) => _pushAndPull());
    if (kDebugMode) {
      debugPrint(
          '[SyncService] Timer démarré (intervalle=${syncInterval.inMinutes} min)');
    }
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // ── Backoff rate-limit ─────────────────────────────────────────────────────

  /// Vérifie si la sync est actuellement en backoff rate-limit (429).
  bool _isRateLimited() {
    final until = _rateLimitedUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _rateLimitedUntil = null; // Backoff expiré.
      return false;
    }
    return true;
  }

  /// Active un backoff rate-limit pour la durée indiquée (plafonnée).
  void _setRateLimitBackoff(int retryAfterMs) {
    final delay = Duration(
      milliseconds: retryAfterMs.clamp(0, _maxRateLimitBackoff.inMilliseconds),
    );
    _rateLimitedUntil = DateTime.now().add(delay);
  }

  /// Tente d'extraire retryAfterMs du corps de la réponse 429,
  /// ou estime un délai par défaut via les headers RateLimit.
  int _parseRateLimitRetry(http.Response response) {
    // Priorité : retryAfterMs dans le corps JSON.
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['retryAfterMs'] is int) {
        return body['retryAfterMs'] as int;
      }
    } catch (_) {}

    // Fallback : délai par défaut (1 minute).
    return 60000;
  }

  // ── Logique de synchronisation bidirectionnelle ───────────────────────────

  /// Synchronisation bidirectionnelle complète (push + pull) avec le serveur.
  ///
  /// Phase PUSH :
  ///   1. Récupère les alertes locales modifiées depuis [_lastPushTs].
  ///   2. POST /api/sync-push avec le batch + peerId + since=_lastPullTs.
  ///
  /// Phase PULL (intégrée dans la réponse du push) :
  ///   3. Le serveur répond avec { upserted, deltas, serverTs }.
  ///   4. Fusionne les `deltas` dans Hive (upsert si plus récent).
  ///
  /// Fallback PULL-only (si le push échoue SANS 429) :
  ///   5. GET /api/sync-check?since=_lastPullTs
  ///   6. Fusionne les items reçus.
  Future<void> _pushAndPull() async {
    try {
      final serverBase = _failover.currentAddress;
      if (serverBase.isEmpty) return;

      // Vérifie si on est en backoff rate-limit.
      if (_isRateLimited()) {
        if (kDebugMode) {
          debugPrint('[SyncService] ⏸ Sync suspendue (backoff rate-limit)');
        }
        return;
      }

      // Phase 1 : PUSH — envoyer les alertes locales modifiées.
      final pushResult = await _pushLocalAlerts(serverBase);

      if (pushResult == _SyncResult.success) {
        // Le push a réussi et a déjà fusionné les deltas (push-pull).
        if (kDebugMode) {
          debugPrint('[SyncService] Push-pull bidirectionnel réussi');
        }
        return;
      }

      if (pushResult == _SyncResult.rateLimited) {
        // 429 reçu : ne PAS faire de pull (il serait aussi 429).
        // Le backoff est déjà configuré dans _pushBatch.
        return;
      }

      // Phase 2 (fallback) : PULL-only si le push a échoué
      // ou s'il n'y avait rien à pousser.
      if (!_isRateLimited()) {
        await _pullFromServer(serverBase);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SyncService] Erreur sync (non fatale): $e');
      }
    }
  }

  /// PUSH : Envoie les alertes locales au serveur.
  /// Retourne [_SyncResult] pour indiquer le résultat.
  Future<_SyncResult> _pushLocalAlerts(String serverBase) async {
    try {
      // Récupérer les alertes locales modifiées depuis le dernier push.
      final allLocal = _db.getAll();
      final modified = allLocal
          .where((a) {
            if (_lastPushTs == null) return true; // premier push → tout envoyer
            return a.lastModifiedAt.isAfter(_lastPushTs!);
          })
          .take(maxPushBatchSize)
          .toList();

      if (modified.isEmpty && _lastPushTs != null) {
        // Rien à pousser, mais on peut quand même pull.
        // On appelle le serveur avec un batch vide pour recevoir les deltas.
        return await _pushBatch(serverBase, [], allLocal);
      }

      return await _pushBatch(serverBase, modified, allLocal);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SyncService] Erreur push local: $e');
      }
      return _SyncResult.failed;
    }
  }

  /// Envoie un batch d'alertes au serveur et fusionne la réponse.
  Future<_SyncResult> _pushBatch(
    String serverBase,
    List<Alert> alerts,
    List<Alert> allLocal,
  ) async {
    final now = DateTime.now().toUtc();
    final since = _lastPullTs?.toUtc().toIso8601String() ?? '';

    final body = <String, dynamic>{
      'alerts': alerts.map((a) => a.toJson()).toList(),
      'peerId': PeerCounterService.instance.localPeerId ?? '',
      'since': since,
    };

    final uri = Uri.parse('$serverBase/api/sync-push');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(syncTimeout);

    // Gestion du 429 (Rate Limit) avec backoff.
    if (response.statusCode == 429) {
      final retryAfterMs = _parseRateLimitRetry(response);
      _setRateLimitBackoff(retryAfterMs);
      if (kDebugMode) {
        debugPrint(
            '[SyncService] ⛔ Rate-limité — backoff ${retryAfterMs ~/ 1000}s');
      }
      return _SyncResult.rateLimited;
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      if (kDebugMode) {
        debugPrint('[SyncService] Push rejeté (HTTP ${response.statusCode})');
      }
      return _SyncResult.failed;
    }

    final respBody = jsonDecode(response.body) as Map<String, dynamic>;

    // Mettre à jour les timestamps de tracking.
    _lastPushTs = now;
    if (respBody['serverTs'] != null) {
      _lastPullTs = DateTime.tryParse(respBody['serverTs'] as String) ?? now;
    } else {
      _lastPullTs = now;
    }

    // Fusionner les deltas reçus du serveur.
    final deltas = respBody['deltas'] as List<dynamic>?;
    if (deltas != null && deltas.isNotEmpty) {
      await _mergeDeltas(deltas);
    }

    if (kDebugMode) {
      final upserted = respBody['upserted'] ?? alerts.length;
      debugPrint('[SyncService] Push OK → $upserted alertes envoyées, '
          '${deltas?.length ?? 0} deltas reçus');
    }

    return _SyncResult.success;
  }

  /// PULL-only : fallback si le push a échoué.
  Future<void> _pullFromServer(String serverBase) async {
    try {
      final since = _lastPullTs?.toUtc().toIso8601String() ?? '';

      final uri = Uri.parse('$serverBase/api/sync-check')
          .replace(queryParameters: {'since': since});

      final response = await http.get(uri).timeout(syncTimeout);

      // Gestion du 429 côté pull aussi.
      if (response.statusCode == 429) {
        final retryAfterMs = _parseRateLimitRetry(response);
        _setRateLimitBackoff(retryAfterMs);
        if (kDebugMode) {
          debugPrint('[SyncService] ⛔ Pull rate-limité — backoff ${retryAfterMs ~/ 1000}s');
        }
        return;
      }

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return;

      await _mergeDeltas(items);

      if (body['serverTs'] != null) {
        _lastPullTs =
            DateTime.tryParse(body['serverTs'] as String) ?? _lastPullTs;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SyncService] Erreur pull: $e');
      }
    }
  }

  /// Fusionne les deltas (liste JSON) dans la base Hive locale.
  Future<void> _mergeDeltas(List<dynamic> items) async {
    int merged = 0;
    for (final item in items) {
      try {
        final remoteAlert = Alert.fromJson(item as Map<String, dynamic>);
        final localAlert = _db.getById(remoteAlert.id);

        if (localAlert == null) {
          // Nouvelle alerte → insérer.
          await _db.upsert(remoteAlert);
          merged++;
        } else if (remoteAlert.lastModifiedAt
            .isAfter(localAlert.lastModifiedAt)) {
          // Alerte distante plus récente → mettre à jour.
          await _db.upsert(remoteAlert);
          merged++;
        }
        // Sinon, la version locale est plus récente → ne rien faire.
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SyncService] Erreur fusion delta: $e');
        }
      }
    }

    if (kDebugMode && merged > 0) {
      debugPrint('[SyncService] $merged alerte(s) fusionnée(s)');
    }
  }
}