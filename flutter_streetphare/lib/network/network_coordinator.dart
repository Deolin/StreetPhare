// lib/network/network_coordinator.dart
//
// Coordinateur réseau global de StreetPhare.
//
// Orchestre l'ensemble de la ruche (Hive) :
//   1. La base locale `HiveAlertDatabase` (TTL 24h, purge auto).
//   2. Le service P2P `P2PMeshService` (BLE + Wi-Fi + Relay).
//   3. Le `FailoverManager` (basculement entre serveurs chiffrés).
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
//
// Ce coordinateur est le SEUL point d'entrée public pour les
// couches UI / features. Les sous-services restent accessibles
// pour des usages avancés (debug, tests).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/alert_model.dart';
import '../database/alert_ttl_policy.dart';
import '../database/crypto_utils.dart';
import '../database/hive_alert_database.dart';
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
  final List<StreamSubscription> _subs = [];

  final String _ephemeralUserId = generateEphemeralUserId();
  bool _initialized = false;

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
  }) async {
    if (_initialized) return;

    await _db.init();
    await _failover.init(failoverConfig);
    await _failover.start();

    _mesh = P2PMeshService(database: _db, transports: transports);

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

    await _mesh!.start();

    // Tâches périodiques : purge TTL et tentative d'upload.
    _purgeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _purgeAndMaybeSync(),
    );
    _uploadTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _uploadValidatedAlerts(),
    );

    _initialized = true;
    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] initialisé. euid=$_ephemeralUserId');
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
      // Le TTL "24h" reste la limite dure (RGPD / purge Hive).
      // La politique de TTL Phase 2 (10min / 1min) est appliquée
      // par `AlertTtlPolicy.isAlertAlive()` et `AlertVisibilityPolicy`.
      ttlHours: 24,
      status: AlertStatus.pending,
      confirmations: {_ephemeralUserId},
    );

    if (kDebugMode) {
      debugPrint(
          '[NetworkCoordinator] TTL Phase 2 pour type=${type.name} : '
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

  /// Confirme manuellement une alerte (par ex. si l'utilisateur
  /// appuie sur "Je confirme" sur la carte).
  Future<bool> confirmAlert(String alertId) async {
    final alert = _db.getById(alertId);
    if (alert == null) return false;
    if (alert.isExpired()) return false;
    final reached = alert.addConfirmation(_ephemeralUserId);
    // Force la mise à jour en BDD.
    await _db.upsert(alert);
    if (reached) {
      // Consensus atteint : on re-broadcast et on force l'upload.
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
      // On tente l'upload immédiatement, sans attendre le timer.
      unawaited(_uploadValidatedAlerts());
    }
  }

  /// Appelé quand une alerte arrive du maillage. On l'a déjà
  /// insérée dans la base (via le mesh service). On ajoute la
  /// confirmation locale (consensus anonyme).
  void _onAlertReceivedViaMesh(Alert alert) {
    final local = _db.getById(alert.id);
    if (local == null) return;
    if (local.isExpired()) return;
    if (local.confirmations.contains(_ephemeralUserId)) return;
    // Ajoute ma confirmation anonyme.
    local.addConfirmation(_ephemeralUserId);
    _db.upsert(local);
  }

  /// Purge les alertes expirées. AVANT suppression, tente une
  /// dernière sync vers le serveur central pour ne rien perdre.
  Future<void> _purgeAndMaybeSync() async {
    await _db.purgeExpired(onBeforeDelete: (alert) async {
      // Tente une dernière sync (best-effort).
      if (alert.status == AlertStatus.validated &&
          alert.uploadedTo.isEmpty) {
        await _failover.uploadAlerts([alert.toJson()]);
      }
    });
  }

  /// Tente de téléverser toutes les alertes validées non encore
  /// uploadées vers le serveur central (via le FailoverManager).
  Future<int> _uploadValidatedAlerts() async {
    final pending = _db.getPendingUpload();
    if (pending.isEmpty) return 0;
    int uploaded = 0;
    for (final alert in pending) {
      final ok = await _failover.uploadAlerts([alert.toJson()]);
      if (ok) {
        await _db.markUploaded(alert.id, _failover.currentAddress);
        uploaded++;
      } else {
        // Échec : on retentera au prochain tick. Si l'alerte est
        // sur le point d'expirer, la purge s'en chargera.
        break;
      }
    }
    return uploaded;
  }

  Future<void> dispose() async {
    _purgeTimer?.cancel();
    _uploadTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _mesh?.stop();
    await _failover.stop();
    _initialized = false;
  }
}
