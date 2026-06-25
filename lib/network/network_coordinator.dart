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
import 'package:flutter/widgets.dart';

import '../core/models/alert_model.dart';
import '../database/alert_ttl_policy.dart';
import '../database/crypto_utils.dart';
import '../database/hive_alert_database.dart';
import '../features/geofencing/presentation/geofencing_service.dart';
import '../features/messaging/presentation/hive_messaging_service.dart';
import '../core/network/peer_counter_service.dart';
import 'collective_panic_service.dart';
import 'failover_manager.dart';
import 'network_manager.dart';
import 'p2p_mesh_service.dart';
import 'sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';

/// Coordinateur réseau singleton.
///
/// Implémente [WidgetsBindingObserver] pour réagir aux changements de
/// cycle de vie de l'application (arrière-plan / premier plan).
/// Sauvegarde proprement l'état réseau lors de la mise en pause et
/// restaure les connexions au retour au premier plan.
class NetworkCoordinator with WidgetsBindingObserver {
  NetworkCoordinator._();
  static final NetworkCoordinator instance = NetworkCoordinator._();

  final HiveAlertDatabase _db = HiveAlertDatabase.instance;
  final FailoverManager _failover = FailoverManager.instance;
  P2PMeshService? _mesh;

  Timer? _purgeTimer;
  Timer? _uploadTimer;
  Timer? _serverCheckTimer;
  Timer? _densityReportTimer;
  Timer? _peerHealthCheckTimer;
  final List<StreamSubscription> _subs = [];

  final String _ephemeralUserId = generateEphemeralUserId();
  bool _initialized = false;

  /// État gelé des timers lors du passage en arrière-plan.
  bool _lifecyclePaused = false;
  DateTime? _lastBackgroundTimestamp;

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

    // Enregistre l'identifiant local auprès du compteur de pairs
    // pour qu'il soit systématiquement exclu du décompte HIVE.
    PeerCounterService.instance
        .setLocalPeerId(localPeerId ?? _ephemeralUserId);

    // Démarre la machine d'état de basculement réseau.
    NetworkManager.instance.start();

    // Démarre la synchronisation différentielle Hive ↔ Serveur.
    SyncService.instance.start();

    // ── Priorité de découverte P2P : BLE → Wi-Fi → WebSocket ──────
    await _discoverPeersInPriorityOrder(transports);

    // Notifie ConnectivityService que les transports sont initialisés.
    ConnectivityService.instance.updateLayerState(
        'websocket', TransportLayerState.active);
    ConnectivityService.instance.updateLayerState(
        'wifi', TransportLayerState.active);
    ConnectivityService.instance.updateLayerState(
        'ble', TransportLayerState.active);

    // À chaque mutation locale, on tente l'upload si l'alerte
    // vient d'être validée par consensus.
    // Enveloppé dans un try/catch : un crash dans le listener ne doit
    // jamais faire planter l'app entière (ex. corruption Hive locale).
    _subs.add(
      _db.changes.listen((alerts) {
        try {
          _onDatabaseChanged(alerts);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[NetworkCoordinator] erreur _onDatabaseChanged: $e\n$st');
          }
        }
      }),
    );

    // À chaque réception d'alerte P2P, on incrémente le consensus.
    _subs.add(
      _mesh!.alertsReceived.listen((alert) {
        try {
          _onAlertReceivedViaMesh(alert);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[NetworkCoordinator] erreur _onAlertReceivedViaMesh: $e\n$st');
          }
        }
      }),
    );

    // Brancher le service de panic collectif.
    CollectivePanicService.instance.setCreateAlertCallback(createAlert);
    _subs.add(_mesh!.panicSignals.listen((signal) {
      try {
        CollectivePanicService.instance.recordPanicSignal(
          peerId: signal['peerId'] as String,
          lat: signal['lat'] as double,
          lng: signal['lng'] as double,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[NetworkCoordinator] erreur panicSignal: $e\n$st');
        }
      }
    }));

    // === Branchement Hive P2P Messaging ===
    // On écoute TOUS les payloads bruts entrants via les transports
    // pour détecter les messages Hive P2P.
    for (final transport in transports) {
      _subs.add(
        transport.incoming.listen((raw) {
          try {
            _handleIncomingRaw(raw);
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('[NetworkCoordinator] erreur incoming raw: $e\n$st');
            }
          }
        }),
      );
    }

    await _mesh!.start();

    // Tâches périodiques : purge TTL et tentative d'upload.
    _purgeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _purgeAndMaybeSync(),
    );
    _uploadTimer = Timer.periodic(
      _kNormalUploadInterval,
      (_) => unawaited(_uploadValidatedAlerts()),
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

    // ── Santé des pairs : purge périodique des pairs inactifs ──
    _peerHealthCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkPeerHealth(),
    );

    // ── Observer le cycle de vie de l'application ──
    WidgetsBinding.instance.addObserver(this);

    _initialized = true;
    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] initialisé. euid=$_ephemeralUserId');
      debugPrint('[NetworkCoordinator] Messagerie Hive P2P branchée '
          'sur ${transports.length} transport(s)');
    }
  }

  // ==========================================================================
  // Cycle de vie de l'application
  // ==========================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _onAppBackgrounded();
      case AppLifecycleState.resumed:
        _onAppForegrounded();
      case AppLifecycleState.detached:
        _onAppDetached();
      case AppLifecycleState.hidden:
        // Pas d'action spécifique pour 'hidden' sur mobile.
        break;
    }
  }

  /// L'application passe en arrière-plan ou est masquée.
  /// Sauvegarde l'état et gèle les timers sans fermer les sockets.
  void _onAppBackgrounded() {
    if (_lifecyclePaused) return;
    _lifecyclePaused = true;
    _lastBackgroundTimestamp = DateTime.now().toUtc();

    // Gèle les timers pour économiser la batterie.
    _uploadTimer?.cancel();
    _purgeTimer?.cancel();
    _serverCheckTimer?.cancel();
    _densityReportTimer?.cancel();
    _peerHealthCheckTimer?.cancel();

    // Les transports P2P restent ouverts mais en écoute passive.
    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] App en arrière-plan — timers gelés, '
          'transports en écoute passive');
    }
  }

  /// L'application revient au premier plan.
  /// Restaure les timers et déclenche une synchronisation immédiate.
  void _onAppForegrounded() {
    if (!_lifecyclePaused) return;
    _lifecyclePaused = false;

    final downtime = _lastBackgroundTimestamp != null
        ? DateTime.now().toUtc().difference(_lastBackgroundTimestamp!)
        : Duration.zero;

    // Restaure les timers.
    _purgeTimer?.cancel();
    _purgeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _purgeAndMaybeSync(),
    );
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(
      _hiveOnlyMode ? _kDegradedUploadInterval : _kNormalUploadInterval,
      (_) => unawaited(_uploadValidatedAlerts()),
    );
    _serverCheckTimer?.cancel();
    _serverCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkServerReachabilityAndAdapt(),
    );
    _peerHealthCheckTimer?.cancel();
    _peerHealthCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkPeerHealth(),
    );

    // Déclenche une synchronisation immédiate après un retour au
    // premier plan (récupération des messages admin et alertes critiques).
    unawaited(_syncOnForeground());

    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] App au premier plan '
          '(après ${downtime.inSeconds}s d\'arrêt) — timers restaurés, '
          'sync déclenchée');
    }
  }

  /// L'application est détachée (fermeture imminente).
  /// Sauvegarde l'état et ferme proprement les connexions.
  void _onAppDetached() {
    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] App détachée — nettoyage…');
    }
    unawaited(dispose());
  }

  /// Synchronisation au retour au premier plan : récupère les messages
  /// admin et les alertes critiques encore valides.
  Future<void> _syncOnForeground() async {
    try {
      // Tente un upload immédiat des alertes en attente.
      await _uploadValidatedAlerts();

      // Notifie le HiveMessagingService pour qu'il flush son outbox.
      if (!ConnectivityService.instance.isIsolated) {
        HiveMessagingService.instance.syncOnForeground();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] erreur sync foreground: $e');
      }
    }
  }

  /// Vérifie la santé des pairs P2P : force une purge des entrées
  /// expirées dans le [PeerCounterService] (fenêtre glissante).
  void _checkPeerHealth() {
    try {
      // Le PeerCounterService purge automatiquement via son ticker
      // interne toutes les secondes. On force simplement un notify
      // pour que l'UI reflète l'état réel.
      PeerCounterService.instance.forceRefresh();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] erreur checkPeerHealth: $e');
      }
    }
  }

  /// Découvre les pairs dans l'ordre de priorité défini :
  /// 1. BLE (Bluetooth Low Energy) — priorité absolue, décentralisé.
  /// 2. Wi-Fi Direct / LAN — réseau local sans Internet.
  /// 3. WebSocket / Relay — connexion au serveur distant.
  ///
  /// Si un transport échoue, le suivant est activé automatiquement.
  /// L'état de chaque couche est notifié via [ConnectivityService].
  Future<void> _discoverPeersInPriorityOrder(
      List<MeshTransport> transports) async {
    if (kDebugMode) {
      debugPrint('[NetworkCoordinator] Découverte P2P : BLE → Wi-Fi → Web');
    }

    // Étape 1 : Tente le BLE (priorité absolue).
    bool bleOk = false;
    try {
      final bleTransport = transports.firstWhere(
        (t) => t.name == 'ble',
        orElse: () => transports.first,
      );
      if (bleTransport.name == 'ble') {
        bleOk = bleTransport.isAvailable;
        if (kDebugMode) {
          debugPrint('[NetworkCoordinator] BLE disponible : $bleOk');
        }
      }
    } catch (_) {
      bleOk = false;
    }

    if (!bleOk) {
      ConnectivityService.instance.updateLayerState(
          'ble', TransportLayerState.disabled);
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] BLE indisponible → Wi-Fi Direct');
      }

      // Étape 2 : Bascule sur Wi-Fi Direct.
      bool wifiOk = false;
      try {
        final wifiTransport = transports.firstWhere(
          (t) => t.name == 'wifi',
          orElse: () => transports.first,
        );
        if (wifiTransport.name == 'wifi') {
          wifiOk = wifiTransport.isAvailable;
          if (kDebugMode) {
            debugPrint('[NetworkCoordinator] Wi-Fi Direct disponible : $wifiOk');
          }
        }
      } catch (_) {
        wifiOk = false;
      }

      if (!wifiOk) {
        ConnectivityService.instance.updateLayerState(
            'wifi', TransportLayerState.disabled);
        if (kDebugMode) {
          debugPrint('[NetworkCoordinator] Wi-Fi Direct indisponible → WebSocket');
        }

        // Étape 3 : Bascule sur le serveur Web (dernier recours).
        ConnectivityService.instance.updateLayerState(
            'websocket', TransportLayerState.active);
      } else {
        ConnectivityService.instance.updateLayerState(
            'wifi', TransportLayerState.active);
      }
    } else {
      ConnectivityService.instance.updateLayerState(
          'ble', TransportLayerState.active);
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

    try {
      if (localPriorityOnly) {
        // PRIORITÉ LOCALE : diffusion uniquement sur BLE/Wi-Fi local.
        await _mesh!.broadcastRawJsonLocal(wrapper);
      } else {
        // ARRIÈRE-PLAN : tous les transports (y compris relay distant).
        await _mesh!.broadcastRawJson(wrapper);
      }
    } catch (e, st) {
      // Capture les pertes de connexion, timeouts, fermetures de socket.
      // Le message est conservé localement, le HiveMessagingService
      // dispose d'une file outbox pour retenter plus tard.
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] échec broadcast Hive (non fatal) : $e\n$st');
      }
      // Relance silencieuse : ne pas crasher l'UI ni le service.
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        if (localPriorityOnly) {
          await _mesh?.broadcastRawJsonLocal(wrapper);
        } else {
          await _mesh?.broadcastRawJson(wrapper);
        }
      } catch (_) {
        if (kDebugMode) {
          debugPrint('[NetworkCoordinator] échec définitif broadcast Hive');
        }
      }
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
    try {
      await _mesh?.broadcastAlert(alert);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] échec broadcastAlert (non fatal): $e\n$st');
      }
    }

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
    try {
      await _mesh?.broadcastRawJson(payload);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] échec broadcast panic (non fatal): $e\n$st');
      }
    }
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
      status: AlertStatus.active, // La densité est valide par défaut
    );

    // Diffusion prioritaire HIVE (BLE/Wi-Fi)
    try {
      await _mesh?.broadcastAlert(alert);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[NetworkCoordinator] échec broadcast densité (non fatal): $e\n$st');
      }
    }
    
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
            a.status == AlertStatus.active && a.uploadedTo.isEmpty)
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

    // Déclenche une notification native immédiate pour
    // l'utilisateur, même si l'application est en arrière-plan.
    NotificationService.instance.showAlertNotification(
      title: 'Alerte StreetPhare',
      body: '${_describeAlertType(alert.type)} signalé à proximité.',
      id: alert.id.hashCode,
    );
  }

  /// Retourne une description lisible du type d'alerte.
  String _describeAlertType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return 'Barrage';
      case AlertType.casseurs:
        return 'Casseurs';
      case AlertType.danger:
        return 'Danger';
      case AlertType.policiers:
        return 'Police';
      case AlertType.autopompes:
        return 'Autopompes';
      case AlertType.filtre:
        return 'Filtre';
      case AlertType.panic:
        return 'Panic';
      case AlertType.dangerCollectif:
        return 'Alerte Panic Collective';
      case AlertType.density:
        return 'Densité';
      case AlertType.autre:
        return 'Autre danger';
    }
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
        (_) => unawaited(_uploadValidatedAlerts()),
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
        (_) => unawaited(_uploadValidatedAlerts()),
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
      if (alert.status == AlertStatus.active &&
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
    WidgetsBinding.instance.removeObserver(this);
    _purgeTimer?.cancel();
    _uploadTimer?.cancel();
    _serverCheckTimer?.cancel();
    _densityReportTimer?.cancel();
    _peerHealthCheckTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _mesh?.stop();
    await _failover.stop();
    _hiveOnlyMode = false;
    _initialized = false;
    _lifecyclePaused = false;
  }
}
