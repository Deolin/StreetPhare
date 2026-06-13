// lib/network/network_coordinator.dart
//
// Coordinateur réseau global de StreetPhare.
//
// Orchestre l'ensemble de la ruche (Hive) :
//   1. La base locale `HiveAlertDatabase` (TTL 24h, purge auto).
//   2. Le service P2P `P2PMeshService` (BLE + Wi-Fi + Relay).
//   3. Le `FailoverManager` (basculement entre serveurs chiffrés).
//   4. La messagerie Hive P2P décentralisée (broadcast de messages).
//
// Responsabilités du coordinateur :
//   - À la CRÉATION d'une alerte, la signer, la stocker, la
//     broadcaster sur tous les transports.
//   - À la RÉCEPTION d'une alerte, vérifier sa signature, ajouter
//     la confirmation de l'utilisateur éphémère local, puis
//     re-propager.
//   - Lorsque le consensus des 3 validations est atteint, marquer
//     l'alerte `validated` et déclencher la synchronisation vers
//     le serveur central via le FailoverManager.
//   - Périodiquement, scanner la base pour purger les alertes
//     expirées (après dernière tentative d'upload).
//   - Diffuser (broadcast) les messages Hive P2P sur le maillage,
//     et recevoir les messages distants filtrés.
//
// Ce coordinateur est le SEUL point d'entrée public pour les
// couches UI / features. Les sous-services restent accessibles
// pour des usages avancés (debug, tests).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/alert_model.dart';
import '../database/alert_ttl_policy.dart';
import '../database/crypto_utils.dart';
import '../database/hive_alert_database.dart';
import '../features/geofencing/presentation/geofencing_service.dart';
import '../features/messaging/presentation/hive_messaging_service.dart';
import '../core/network/peer_counter_service.dart';
import 'collective_panic_service.dart';
import 'failover_manager.dart';
import 'p2p_mesh_service.dart';

/// Coordinateur réseau singleton.
class NetworkCoordinator {
  NetworkCoordinator._();
  static final NetworkCoordinator instance = NetworkCoordinator._();

  final HiveAlertDatabase _db = HiveAlertDatabase.instance;
  final FailoverManager _failover = FailoverManager.instance;
  P2PMeshService? _mesh;

  Timer? _purgeTimer;
  Timer? _uploadTimer;
  Timer? _serverCheckTimer;
  Timer? _densityReportTimer;
  final List<StreamSubscription> _subs = [];

  final String _ephemeralUserId = generateEphemeralUserId();
  bool _initialized = false;

  // [3] Mode dégradé : basculement Hive pur si TOUS les serveurs sont hors ligne.
  /// true = aucun serveur (3000 ni 3001) n'est joignable →
  ///  mode local décentralisé via Hive + pings espacés de 3 min.
  bool _hiveOnlyMode = false;

  /// Durée entre pings réseau en mode NORMAL (2 min).
  static const Duration _kNormalUploadInterval = Duration(minutes: 2);

  /// Durée entre pings réseau en mode DÉGRADÉ (3 min, économie batterie).
  static const Duration _kDegradedUploadInterval = Duration(minutes: 3);

  /// Expose l'état du mode Hive-uniquement (lecture seule pour l'UI).
  bool get isHiveOnlyMode => _hiveOnlyMode;

  /// Identifiant éphémère local (rotatif).
  String get ephemeralUserId => _ephemeralUserId;

  /// Stream d'alertes (utile pour la couche UI).
  Stream<List<Alert>> get alertsStream => _db.changes;

  /// Initialise le coordinateur. À appeler UNE SEULE FOIS au
  /// démarrage, après `WidgetsFlutterBinding.ensureInitialized()`
  /// et avant `runApp`.
  Future<void> init({
    required FailoverConfig failoverConfig,
    required List<MeshTransport> transports,
    String? localPeerId,
  }) async {
    if (_initialized) return;

    // Initialise la base et le failover en parallèle.
    await Future.wait([
      _db.init(),
      _failover.init(failoverConfig),
    ]);
    
    // Démarre le failover (heartbeat).
    await _failover.start();

    _mesh = P2PMeshService(
      database: _db,
      transports: transports,
      localPeerId: localPeerId ?? _ephemeralUserId,
    );

    // À chaque mutation locale, on tente l'upload si l'alerte
    // vient d'être validée par consensus.
    _subs.add(_db.changes.listen(_onDatabaseChanged));

    // À chaque réception d'alerte P2P, on incrémente le consensus.
    _subs.add(_mesh!.alertsReceived.listen(_onAlertReceivedViaMesh));

    // Brancher le service de panic collectif.
    CollectivePanicService.instance.setCreateAlertCallback(createAlert);
    _subs.add(_mesh!.panicSignals.listen((signal) {
      CollectivePanicService.instance.recordPanicSignal(
        peerId: signal['peerId'] as String,
        lat: signal['lat'] as double,
        lng: signal['lng'] as double,
      );
    }));

    // === Branchement Hive P2P Messaging ===
    // On écoute le flux de données brutes du maillage.
    // Les messages Hive sont préfixés par "hive_msg:" dans le payload.
    _subs.add(_mesh!.alertsReceived.listen((alert) {
      // Ignorer les alertes, ce sont des messages structurés
    }));

    // On écoute TOUS les payloads bruts entrants via les transports
    // pour détecter les messages Hive P2P.
    for (final transport in transports) {
      _subs.add(transport.incoming.listen((raw) {
        _handleIncomingRaw(raw);
      }));
    }

    await _mesh!.start();

    // Tâches périodiques : purge TTL et tentative d'upload.
    _purgeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _purgeAndMaybeSync(),
    );
    _uploadTimer = Timer.periodic(
      _kNormalUploadInterval,
      (_) => _uploadValidatedAlerts(),
    );

    // [3] Vérification périodique de la disponibilité des serveurs.
    // Si les DEUX serveurs (3000 + 3001) sont inaccessibles :
    //   → bascule immédiatement en mode Hive pur (local/décentralisé).
    //   → espace les pings à 3 minutes pour économiser la batterie.
    // Si un serveur redevient disponible :
    //   → repasse en mode normal (ping toutes les 2 min).
    _serverCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkServerReachabilityAndAdapt(),
    );

    // [3] Rapport périodique de densité Bluetooth (HIVE)
    // Seuls les signalements avec une densité > 0 sont envoyés.
    _densityReportTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _reportLocalDensity(),
    );

    _initialized = true;
    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] initialisé. euid=$_ephemeralUserId');
      debugPrint('[NetworkCoordinator] Messagerie Hive P2P branchée '
          'sur ${transports.length} transport(s)');
    }
  }

  /// Traite un payload brut entrant depuis un transport P2P.
  /// Détecte les messages Hive P2P (préfixe "hive_p2p:") et les
  /// transmet au HiveMessagingService.
  void _handleIncomingRaw(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final kind = json['kind'] as String?;

      if (kind == 'hive_p2p_message') {
        final payload = json['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          HiveMessagingService.instance.receiveRemote(payload);
          if (kDebugMode) {
            debugPrint('[NetworkCoordinator] Message Hive P2P reçu');
          }
        }
      }
    } catch (e) {
      // Silence les payloads non-JSON (pings, etc.)
    }
  }

  /// Diffuse un message Hive P2P sur les transports disponibles.
  ///
  /// [messageJson] : message sérialisé (Map clé/valeur).
  /// [localPriorityOnly] :
  ///   - `true`  → réseau local P2P uniquement (BLE / Wi-Fi Direct).
  ///              Priorité absolue, non bloquant pour l'UI.
  ///   - `false` → tous les transports (y compris le relay serveur distant).
  ///              Utilisé en tâche d'arrière-plan.
  Future<void> broadcastHiveMessage(
    Map<String, dynamic> messageJson, {
    bool localPriorityOnly = false,
  }) async {
    if (_mesh == null) return;

    final wrapper = <String, dynamic>{
      'kind': 'hive_p2p_message',
      'payload': messageJson,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'sender_id': _ephemeralUserId,
      'local_only': localPriorityOnly,
    };

    if (localPriorityOnly) {
      // PRIORITÉ LOCALE : diffusion uniquement sur BLE/Wi-Fi local.
      await _mesh!.broadcastRawJsonLocal(wrapper);
    } else {
      // ARRIÈRE-PLAN : tous les transports (y compris relay distant).
      await _mesh!.broadcastRawJson(wrapper);
    }

    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] Message Hive P2P broadcasté '
          '(local_only=$localPriorityOnly)');
    }
  }

  /// Crée une nouvelle alerte, la signe, la stocke localement,
  /// puis la diffuse sur le maillage.
  Future<Alert> createAlert({
    required AlertType type,
    required double latitude,
    required double longitude,
    String description = '',
  }) async {
    final id = randomId(8);
    final createdAt = DateTime.now().toUtc();
    final signed = await CryptoUtils.instance.signAlert(
      alertId: id,
      type: type.name,
      lat: latitude,
      lng: longitude,
      createdAt: createdAt,
    );

    final alert = Alert(
      id: id,
      ephemeralUserId: _ephemeralUserId,
      signature: signed.signature,
      type: type,
      latitude: latitude,
      longitude: longitude,
      description: description,
      createdAt: createdAt,
      ttlHours: 24,
      status: AlertStatus.pending,
      confirmations: {_ephemeralUserId},
    );

    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] TTL Phase 2 pour type=${type.name} : '
          '${AlertTtlPolicy.ttlForAlertType(type).inMinutes} min');
    }

    await _db.upsert(alert);
    await _mesh?.broadcastAlert(alert);

    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] alerte créée : $alert');
    }
    return alert;
  }

  /// Diffuse le signal panic local sur le maillage P2P.
  /// Appelé par l'UI quand l'utilisateur active son bouton PANIC.
  Future<void> broadcastLocalPanic({
    required double latitude,
    required double longitude,
  }) async {
    final payload =
        CollectivePanicService.instance.buildLocalPanicPayload(
      localPeerId: _ephemeralUserId,
      lat: latitude,
      lng: longitude,
    );
    await _mesh?.broadcastRawJson(payload);
    if (kDebugMode) {
      debugPrint(
          '[NetworkCoordinator] signal panic local broadcasté ($latitude, $longitude)');
    }
  }

  /// [3] Rapport de densité locale HIVE.
  /// Envoie le nombre d'appareils uniques détectés au serveur et au mesh.
  Future<void> _reportLocalDensity() async {
    final pos = GeofencingService.instance.lastPosition;
    if (pos == null) return;
    
    final count = PeerCounterService.instance.value;
    if (count == 0) return; // Pas d'intérêt si vide

    final id = 'density_$_ephemeralUserId';
    final alert = Alert(
      id: id,
      ephemeralUserId: _ephemeralUserId,
      signature: 'local_density', // Pas besoin de signature lourde pour la densité
      type: AlertType.density,
      latitude: pos.latitude,
      longitude: pos.longitude,
      densityValue: count,
      description: 'Densité locale (Bluetooth)',
      createdAt: DateTime.now().toUtc(),
      ttlHours: 1, // Durée de vie courte
      status: AlertStatus.validated, // La densité est valide par défaut
    );

    // Diffusion prioritaire HIVE (BLE/Wi-Fi)
    await _mesh?.broadcastAlert(alert);
    
    // Upload asynchrone secondaire vers le serveur (Requirement #4)
    unawaited(_failover.uploadAlerts([alert.toJson()]));

    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] densité rapportée : $count à ${pos.latitude}, ${pos.longitude}');
    }
  }

  /// Confirme manuellement une alerte (par ex. si l'utilisateur
  /// appuie sur "Je confirme" sur la carte).
  Future<bool> confirmAlert(String alertId) async {
    final alert = _db.getById(alertId);
    if (alert == null) return false;
    if (alert.isExpired()) return false;
    final reached = alert.addConfirmation(_ephemeralUserId);
    await _db.upsert(alert);
    if (reached) {
      await _mesh?.broadcastAlert(alert);
    }
    return reached;
  }

  /// Appelé quand la base locale émet un changement. On déclenche
  /// l'upload pour les alertes validées.
  void _onDatabaseChanged(List<Alert> alerts) {
    final validated = alerts
        .where((a) =>
            a.status == AlertStatus.validated && a.uploadedTo.isEmpty)
        .toList();
    if (validated.isNotEmpty) {
      unawaited(_uploadValidatedAlerts());
    }
  }

  /// Appelé quand une alerte arrive du maillage.
  void _onAlertReceivedViaMesh(Alert alert) {
    final local = _db.getById(alert.id);
    if (local == null) return;
    if (local.isExpired()) return;
    if (local.confirmations.contains(_ephemeralUserId)) return;
    local.addConfirmation(_ephemeralUserId);
    _db.upsert(local);
  }

  // --------------------------------------------------------------------------
  // [3] Mode dégradé — Hive-only fallback
  // --------------------------------------------------------------------------

  /// Vérifie si au moins un serveur (3000 ou 3001) répond.
  /// Si aucun serveur n'est joignable, bascule en mode Hive pur et
  /// espace les pings réseau à [_kDegradedUploadInterval] pour économiser
  /// la batterie. Reprend le mode normal dès qu'un serveur répond.
  Future<void> _checkServerReachabilityAndAdapt() async {
    // currentAddress is empty string when no server is active (see FailoverManager)
    final isReachable = _failover.currentAddress.isNotEmpty;

    if (!isReachable && !_hiveOnlyMode) {
      // ── Basculement VERS le mode Hive pur ─────────────────────
      _hiveOnlyMode = true;
      _uploadTimer?.cancel();
      _uploadTimer = Timer.periodic(
        _kDegradedUploadInterval,
        (_) => _uploadValidatedAlerts(),
      );
      if (kDebugMode) {
        debugPrint(
          '[NetworkCoordinator] ⚠ Mode Hive-only activé : '
          'aucun serveur disponible. '
          'Pings espacés à ${_kDegradedUploadInterval.inMinutes} min '
          '(économie batterie).',
        );
      }
    } else if (isReachable && _hiveOnlyMode) {
      // ── Retour au mode normal ──────────────────────────────────
      _hiveOnlyMode = false;
      _uploadTimer?.cancel();
      _uploadTimer = Timer.periodic(
        _kNormalUploadInterval,
        (_) => _uploadValidatedAlerts(),
      );
      if (kDebugMode) {
        debugPrint(
          '[NetworkCoordinator] ✓ Mode normal rétabli : '
          'serveur ${_failover.currentAddress} disponible. '
          'Pings rétablis à ${_kNormalUploadInterval.inMinutes} min.',
        );
      }
      // Tente immédiatement d'uploader les alertes en attente.
      unawaited(_uploadValidatedAlerts());
    }
  }

  /// Purge les alertes expirées.
  Future<void> _purgeAndMaybeSync() async {
    await _db.purgeExpired(onBeforeDelete: (alert) async {
      if (alert.status == AlertStatus.validated &&
          alert.uploadedTo.isEmpty) {
        await _failover.uploadAlerts([alert.toJson()]);
      }
    });
  }

  /// Tente de téléverser toutes les alertes validées par lots.
  Future<int> _uploadValidatedAlerts() async {
    final pending = _db.getPendingUpload();
    if (pending.isEmpty) return 0;

    // On uploade par lots pour plus d'efficacité.
    final payloads = pending.map((a) => a.toJson()).toList();
    final ok = await _failover.uploadAlerts(payloads);

    if (ok) {
      // Marque toutes les alertes du lot comme uploadées en parallèle.
      await Future.wait(pending.map(
        (a) => _db.markUploaded(a.id, _failover.currentAddress),
      ));
      return pending.length;
    }
    return 0;
  }

  Future<void> dispose() async {
    _purgeTimer?.cancel();
    _uploadTimer?.cancel();
    _serverCheckTimer?.cancel();
    _densityReportTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _mesh?.stop();
    await _failover.stop();
    _hiveOnlyMode = false;
    _initialized = false;
  }
}