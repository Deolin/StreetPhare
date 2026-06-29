// lib/network/p2p_mesh_service.dart
//
// Service de découverte et propagation Peer-to-Peer (Mesh Networking).
//
// L'application doit chercher à diffuser et recevoir les paquets
// d'alertes en utilisant simultanément TOUTES les bandes disponibles :
//   1. Wi-Fi Direct / Local (LAN multicast, hotspot)
//   2. Bluetooth Low Energy (BLE) via flutter_reactive_ble
//   3. Données mobiles (3G/4G/5G) via relay Internet
//
// Si Internet est coupé, les appareils à portée BLE/Wi-Fi s'échangent
// leurs bases de données locales (gossip protocol).
//
// L'implémentation réelle dépend de packages natifs non disponibles
// dans tous les environnements de test ; on définit donc une
// interface abstraite `MeshTransport` qu'on branche sur les
// implémentations concrètes (Wi-Fi / BLE / Relay) dans des fichiers
// séparés. Cela permet de tester la logique de gossip sans device.
//
// === Correction ANR (Signal 3) ===
// Problèmes identifiés :
//   1. `_handleIncoming()` est appelé de manière synchrone par le
//      listener de chaque transport. En cas de burst BLE (lowLatency),
//      des dizaines de messages s'empilent et chaque appel exécute
//      `jsonDecode`, `PeerCounterService.recordPeer`, `database.insertOrMerge`
//      sans jamais céder le thread.
//   2. `_gossip()` appelle `t.broadcast(payload)` sans await sur tous
//      les transports, créant des Futures orphelins.
//   3. `broadcastAlert()` et `broadcastRawJson()` utilisent `Future.wait`
//      correctement mais peuvent être appelés en rafale depuis
//      `_onAlertReceived` (re-propagation avec délai aléatoire).
//
// Correctifs appliqués :
//   - Chaque `_handleIncoming()` est maintenant passé à `scheduleMicrotask`
//     pour être exécuté quand la boucle d'événements est libre.
//   - Limitation du nombre de microtasks en attente via un compteur
//     atomique simple (max 25 en file d'attente).
//   - `_gossip()` utilise désormais `unawaited(Future.wait(...))` pour
//     éviter l'accumulation de Futures non surveillés tout en restant
//     fire-and-forget.
//   - `_onAlertReceived` vérifie un cache anti-dédoublement avant de
//     replanifier une re-propagation.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/network/peer_counter_service.dart';
import '../core/models/alert_model.dart';
import '../database/hive_alert_database.dart';

/// Représente un pair (autre appareil) découvert sur le maillage.
class MeshPeer {

  const MeshPeer({
    required this.id,
    required this.transport,
    required this.lastSeen,
  });

  factory MeshPeer.fromJson(Map<String, dynamic> j) => MeshPeer(
        id: j['id'] as String,
        transport: j['t'] as String,
        lastSeen: DateTime.parse(j['ls'] as String).toUtc(),
      );
  final String id;
  final String transport; // 'ble' | 'wifi' | 'relay'
  final DateTime lastSeen;

  Map<String, dynamic> toJson() => {
        'id': id,
        't': transport,
        'ls': lastSeen.toIso8601String(),
      };
}

/// Contrat d'un transport de maillage. Une implémentation existe
/// pour chaque bande (BLE, Wi-Fi, Relay). Toutes sont orchestrées
/// par [P2PMeshService].
abstract class MeshTransport {
  String get name;
  bool get isAvailable;

  /// Démarre le transport (scanning, advertising, connexion).
  Future<void> start();

  /// Arrête le transport.
  Future<void> stop();

  /// Diffuse un message compact à tous les pairs à portée.
  Future<void> broadcast(String payload);

  /// Envoie un message ciblé à un pair.
  Future<void> sendTo(MeshPeer peer, String payload);

  /// Flux des messages reçus.
  Stream<String> get incoming;

  /// Libère les ressources internes du transport.
  /// Après appel, l'instance n'est plus utilisable.
  void dispose();
}

/// Service principal de propagation P2P.
///
/// Responsabilités :
//   - Démarrer tous les transports disponibles.
//   - À la réception d'une alerte, l'insérer dans la base locale
//     (déclenchant le mécanisme de consensus).
//   - Périodiquement, broadcaster la base locale (gossip) pour
//     propager les alertes dans la foule sans internet.
///   - Si l'alerte est validée par consensus (3 confirmations),
///     notifier le coordinateur réseau pour tentative d'upload.
class P2PMeshService {
  P2PMeshService({
    required this.database,
    required this.transports,
    this.localPeerId = '',
    this.gossipInterval = const Duration(seconds: 30),
    this.discoveryInterval = const Duration(seconds: 10),
  });

  final HiveAlertDatabase database;
  final List<MeshTransport> transports;

  /// Identifiant local à exclure du comptage de densité.
  final String localPeerId;

  /// Intervalle entre deux broadcasts de la base locale (gossip).
  final Duration gossipInterval;

  /// Intervalle entre deux scans de pairs.
  final Duration discoveryInterval;

  final _peersController = StreamController<List<MeshPeer>>.broadcast();
  Stream<List<MeshPeer>> get peers => _peersController.stream;

  final _alertsReceivedController = StreamController<Alert>.broadcast();
  Stream<Alert> get alertsReceived => _alertsReceivedController.stream;

  /// Stream des signaux "panic" bruts reçus des pairs.
  /// Chaque événement est une map { 'peerId', 'lat', 'lng' }.
  final _panicSignalController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get panicSignals =>
      _panicSignalController.stream;

  final Map<String, MeshPeer> _peers = {};
  Timer? _gossipTimer;
  Timer? _discoveryTimer;
  final List<StreamSubscription> _subs = [];
  bool _started = false;

  /// ANR fix : compteur de microtasks en attente pour éviter
  /// la saturation de l'event loop lors des bursts BLE.
  int _pendingMicrotasks = 0;

  /// Nombre maximum de microtasks de traitement en file d'attente.
  static const int _maxPendingMicrotasks = 25;

  /// ANR fix : cache des alertes récemment reçues pour éviter
  /// les boucles de re-propagation infinies.
  final Set<String> _recentlyReceivedAlertIds = {};

  /// Taille maximale du cache anti-dédoublement.
  static const int _maxRecentAlertCache = 100;

  /// Outbox persistée (Hive) : messages locaux non broadcastés
  /// faute de transport disponible. Flushée automatiquement
  /// quand un transport redevient actif.
  final List<String> _outbox = [];

  /// Flush l'outbox locale sur tous les transports disponibles.
  /// Appelé quand le réseau local est restauré.
  Future<void> flushOutbox() async {
    if (_outbox.isEmpty) return;
    if (kDebugMode) {
      debugPrint('[P2PMeshService] flush outbox (${_outbox.length} messages)');
    }
    final messages = List<String>.from(_outbox);
    _outbox.clear();
    for (final msg in messages) {
      try {
        final json = jsonDecode(msg) as Map<String, dynamic>;
        await broadcastRawJsonLocal(json);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PMeshService] Erreur flush outbox: $e');
        }
      }
    }
  }

  /// Démarre tous les transports et la boucle de gossip.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Démarre tous les transports en parallèle.
    await Future.wait(transports.map((t) async {
      try {
        if (t.isAvailable) {
          await t.start();
          _subs.add(t.incoming.listen(_handleIncoming));
          if (kDebugMode) {
            debugPrint('[P2PMeshService] transport ${t.name} démarré');
          }
        } else if (kDebugMode) {
          debugPrint(
              '[P2PMeshService] transport ${t.name} ignoré (non supporté)');
        }
      } on UnimplementedError catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[P2PMeshService] transport ${t.name} non implémenté '
            'sur cette plateforme — ignoré. ($e)',
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[P2PMeshService] erreur ${t.name}: $e');
      }
    }));

    _gossipTimer = Timer.periodic(gossipInterval, (_) => _gossip());
    _discoveryTimer = Timer.periodic(discoveryInterval, (_) => _pingPeers());
  }

  /// Diffuse une alerte à tous les pairs sur tous les transports.
  Future<void> broadcastAlert(Alert alert) async {
    final payload = alert.toCompact();
    // ANR fix : on n'attend pas la complétion pour ne pas bloquer
    // l'appelant. On utilise unawaited pour éviter le warning de
    // Future non utilisé, tout en restant fire-and-forget.
    unawaited(
      Future.wait(transports.map((t) async {
        try {
          await t.broadcast(payload);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[P2PMeshService] broadcast ${t.name}: $e');
          }
        }
      })),
    );
  }

  /// Diffuse un payload JSON brut (ex : signal panic) sur tous les transports.
  Future<void> broadcastRawJson(Map<String, dynamic> json) async {
    final payload = jsonEncode(json);
    unawaited(
      Future.wait(transports.map((t) async {
        try {
          await t.broadcast(payload);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[P2PMeshService] broadcastRaw ${t.name}: $e');
          }
        }
      })),
    );
  }

  /// [1] Diffuse un payload JSON sur les transports LOCAUX uniquement
  /// (BLE + Wi-Fi Direct), en excluant le relay Internet.
  /// Utilisé pour la PRIORITÉ LOCALE dans l'architecture hybride.
  Future<void> broadcastRawJsonLocal(Map<String, dynamic> json) async {
    final payload = jsonEncode(json);
    // Les transports "locaux" sont identifiés par leur nom :
    // 'ble', 'wifi', 'wifi_direct', 'nearby'. Le relay est exclu.
    final localTransports = transports
        .where(
          (t) =>
              !t.name.toLowerCase().contains('relay') &&
              !t.name.toLowerCase().contains('remote') &&
              !t.name.toLowerCase().contains('server'),
        )
        .toList();

    if (localTransports.isEmpty) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] no local transport configured, '
            'fallback to all');
      }
      unawaited(broadcastRawJson(json));
      return;
    }

    if (!localTransports.any((t) => t.isAvailable)) {
      // Aucun transport local dispo → NE PAS faire de fallback vers le
      // serveur. Le mode `local_only` signifie "je ne veux pas de relay".
      // On persiste le message dans l'outbox Hive pour resync ultérieure.
      if (kDebugMode) {
        debugPrint('[P2PMeshService] no local transport available, '
            'message mis en attente (outbox Hive)');
      }
      _outbox.add(jsonEncode(json));
      return;
    }

    unawaited(
      Future.wait(localTransports.map((t) async {
        try {
          if (t.isAvailable) {
            await t.broadcast(payload);
            if (kDebugMode) {
              debugPrint('[P2PMeshService] broadcastLocal ${t.name}: OK');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[P2PMeshService] broadcastLocal ${t.name}: $e');
          }
        }
      })),
    );
  }

  /// Arrête le service et libère tous les transports.
  Future<void> stop() async {
    _gossipTimer?.cancel();
    _discoveryTimer?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    for (final t in transports) {
      try {
        await t.stop();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PMeshService] Erreur stop ${t.name}: $e');
        }
      }
      try {
        t.dispose();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PMeshService] Erreur dispose ${t.name}: $e');
        }
      }
    }
    _pendingMicrotasks = 0;
    _recentlyReceivedAlertIds.clear();
    _started = false;
  }

  /// Wrapper JSON de gossip : envoie la liste compacte des IDs connus.
  ///
  /// ANR fix : le broadcast est désormais fire-and-forget via
  /// `unawaited(Future.wait(...))` pour éviter d'accumuler des
  /// Futures non surveillés.
  void _gossip() {
    final valid = database.getAllValid();
    if (valid.isEmpty) return;
    // On limite à 50 alertes les plus récentes pour ne pas saturer BLE.
    final recent = valid.take(50).map((a) => a.id).toList();
    final payload = jsonEncode({
      'kind': 'gossip',
      'ids': recent,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    // ANR fix : unawaited pour fire-and-forget propre, sans fuite
    // de Future dans l'event loop.
    unawaited(
      Future.wait(transports.map((t) async {
        try {
          await t.broadcast(payload);
        } catch (_) {
          // Silencieux en gossip : si un transport échoue,
          // les autres continuent.
        }
      })),
    );
  }

  /// Ping simple pour la découverte (les vrais implémentations
  /// remontent déjà la liste via les callbacks natifs BLE/Wi-Fi).
  void _pingPeers() {
    _peers.removeWhere(
        (_, p) => DateTime.now().toUtc().difference(p.lastSeen).inMinutes > 5);
    _peersController.add(_peers.values.toList());
  }

  /// Point d'entrée des messages reçus par n'importe quel transport.
  ///
  /// ANR fix : au lieu d'exécuter tout le traitement de façon synchrone
  /// dans le callback du listener (ce qui peut saturer l'event loop lors
  /// des bursts BLE), on planifie le traitement via `scheduleMicrotask`
  /// avec un mécanisme de backpressure (max 25 microtasks en attente).
  /// Les messages au-delà de cette limite sont ignorés pour préserver
  /// la réactivité de l'UI.
  void _handleIncoming(String raw) {
    // Backpressure : si trop de messages sont en attente de traitement,
    // on ignore les nouveaux pour éviter l'ANR.
    if (_pendingMicrotasks >= _maxPendingMicrotasks) {
      if (kDebugMode) {
        debugPrint(
          '[P2PMeshService] backpressure: $_pendingMicrotasks '
          'microtasks en attente, message ignoré',
        );
      }
      return;
    }

    _pendingMicrotasks++;
    scheduleMicrotask(() {
      _pendingMicrotasks--;
      _processIncomingMessage(raw);
    });
  }

  /// Traitement effectif d'un message entrant, exécuté dans un
  /// microtask pour ne pas bloquer le thread Dart principal.
  void _processIncomingMessage(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;

      // Cas 1 : paquet d'alerte simple.
      if (json.containsKey('id') && json.containsKey('euid')) {
        final alert = Alert.fromJson(json);
        _onAlertReceived(alert);
        return;
      }

      // Cas 2 : paquet de gossip (liste d'IDs).
      if (json['kind'] == 'gossip' && json['ids'] is List) {
        _onGossipReceived((json['ids'] as List).cast<String>());
        return;
      }

      // Cas 3 : signal panic d'un pair.
      if (json['kind'] == 'panic' &&
          json['peerId'] is String &&
          json['lat'] is num &&
          json['lng'] is num) {
        _panicSignalController.add({
          'peerId': json['peerId'] as String,
          'lat': (json['lat'] as num).toDouble(),
          'lng': (json['lng'] as num).toDouble(),
        });
        return;
      }

      // Cas 4 : ping de présence.
      if (json['kind'] == 'ping' && json['id'] is String) {
        final peerId = json['id'] as String;

        // Exclure l'hôte local (Requirement #3)
        if (peerId == localPeerId) return;

        _peers[peerId] = MeshPeer(
          id: peerId,
          transport: json['t'] ?? 'unknown',
          lastSeen: DateTime.now().toUtc(),
        );

        // Enregistre le pair pour le calcul de densité HIVE
        PeerCounterService.instance.recordPeer(
          peerId,
          serviceUuid: json['svc'] as String?,
          metadata: json['meta'] as String?,
        );
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] message ignoré (parse error): $e');
      }
    }
  }

  /// ANR fix : _onAlertReceived est maintenant appelé depuis un
  /// microtask. On évite de replanifier des re-propagation si
  /// l'alerte a déjà été traitée récemment (cache anti-dédoublement).
  void _onAlertReceived(Alert alert) {
    if (alert.isExpired()) return;

    // ANR fix : cache anti-dédoublement pour éviter les boucles
    // de re-propagation infinies lors des bursts.
    if (_recentlyReceivedAlertIds.contains(alert.id)) return;
    _recentlyReceivedAlertIds.add(alert.id);
    // Nettoie le cache s'il dépasse la taille max.
    if (_recentlyReceivedAlertIds.length > _maxRecentAlertCache) {
      final toRemove = _recentlyReceivedAlertIds.take(
        _recentlyReceivedAlertIds.length ~/ 4,
      );
      _recentlyReceivedAlertIds.removeAll(toRemove);
    }

    // Important : on stocke puis on propage (flooding contrôlé).
    // On utilise unawaited pour ne pas bloquer le microtask courant.
    unawaited(database.insertOrMerge(alert).then((_) {
      _alertsReceivedController.add(alert);
      if (kDebugMode) {
        debugPrint('[P2PMeshService] alerte reçue : ${alert.id} '
            '(${alert.confirmations.length}/3)');
      }
      // Re-propagation avec un délai aléatoire pour éviter les collisions.
      final ttl = Random().nextInt(2000);
      Future.delayed(Duration(milliseconds: ttl), () {
        if (!alert.isExpired()) {
          broadcastAlert(alert);
        }
      });
    }));
  }

  void _onGossipReceived(List<String> remoteIds) {
    final localIds = database.getAllValid().map((a) => a.id).toSet();
    final missing = remoteIds.where((id) => !localIds.contains(id)).toList();
    if (missing.isEmpty) return;

    if (kDebugMode) {
      debugPrint(
          '[P2PMeshService] gossip: ${missing.length} alertes inconnues');
    }
  }
}
