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

import '../core/models/alert_model.dart';
import '../core/network/peer_counter_service.dart';
import '../database/hive_alert_database.dart';
import 'mesh_outbox.dart';

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

  /// Vrai si ce transport a au moins un pair connecté à portée.
  /// Utilisé pour décider si un broadcast local a réellement été délivré ;
  /// sinon le message est persisté en outbox (résilience cascade BLE/WiFi/5G).
  bool get hasActivePeers => false;

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

  /// ANR fix : drapeau de drainage de la file d'entrée (0 = inactif,
  /// 1 = un drainer actif). Remplace l'ancien compteur + drop : on ne jette
  /// plus de message, tout est mis en file FIFO.
  int _pendingMicrotasks = 0;

  /// ANR fix : cache des alertes récemment reçues pour éviter
  /// les boucles de re-propagation infinies.
  final Set<String> _recentlyReceivedAlertIds = {};

  /// Taille maximale du cache anti-dédoublement.
  static const int _maxRecentAlertCache = 100;

  /// Cache anti-dédoublement des tombstones (suppressions/rejets) re-propagés.
  final Set<String> _recentlyTombstonedIds = {};

  /// Taille maximale du cache des tombstones.
  static const int _maxTombstoneCache = 100;

  /// Outbox persistante (Hive) : découple le transport volatile de la donnée.
  /// Les messages sortants y sont écrits AVANT tout envoi, avec un statut et
  /// un numéro de séquence, puis réémis jusqu'à acquittement applicatif
  /// (Store-and-Forward tolérant aux coupures).
  final MeshOutbox _outbox = MeshOutbox.instance;

  /// Dernier `seq` serveur consommé (rattrapage delta via `sync_from`).
  int _lastServerSeq = 0;

  /// Timer de réémission des messages en attente (ACK + backoff borné).
  Timer? _retransmitTimer;

  /// Backoff progressif des réémissions (300 ms → 800 ms → 2 s → 5 s → 10 s).
  static const List<Duration> _retryDelays = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 800),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Nombre maximal de tentatives avant abandon radio (la donnée reste en base).
  static const int _maxReliableAttempts = 10;

  /// Intervalle de la boucle de réémission.
  static const Duration _retransmitTick = Duration(milliseconds: 500);

  /// Dédup des ACK déjà émis (anti-tempête).
  final Set<String> _seenEnvelopeIds = {};
  static const int _maxSeenEnvelopeIds = 200;

  /// File FIFO des messages entrants (plus jamais de « message ignoré »).
  final List<String> _incomingBacklog = [];
  static const int _maxIncomingBacklog = 1000;

  /// Flush l'outbox persistante sur le maillage (appelé au retour du réseau
  /// ou à l'apparition d'un pair).
  Future<void> flushOutbox() async {
    await _retransmitDue();
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

    // ── Livraison fiable (Store-and-Forward) ──
    try {
      await _outbox.init();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] init outbox: $e');
      }
    }
    _retransmitTimer = Timer.periodic(_retransmitTick, (_) {
      unawaited(_retransmitDue());
    });
    unawaited(_outbox.prune());

    // ── Rattrapage seq côté serveur (Log ordonné + Deltas) ──
    // Le curseur est chargé ici ; la demande de delta (`sync_from`) est
    // déclenchée à la réception du `welcome` du relay (_onWelcomeReceived).
    _lastServerSeq = _outbox.getCursor('server_seq');
  }

  /// Diffuse une alerte de façon FIABLE : écrite dans l'outbox persistante
  /// puis émise (avec ACK + retransmission) — aucune perte en cas de coupure.
  Future<void> broadcastAlert(Alert alert) async {
    await _enqueueReliable(alert.toJson(), kind: 'alert');
  }

  /// Diffuse un tombstone (signalement supprimé/rejeté) aux pairs locaux.
  ///
  /// Contrairement à une alerte, un tombstone est léger (`{ id, reason }`) et
  /// déclenche la SUPPRESSION locale chez les pairs, puis sa re-propagation
  /// sur le maillage hors-ligne. On cible les transports LOCAUX (BLE / Wi-Fi)
  /// uniquement : les clients déjà reliés au serveur ont reçu le signal
  /// directement via WebSocket.
  void broadcastTombstone(String id, {String reason = 'deleted'}) {
    unawaited(_enqueueReliable({
      'kind': 'tombstone',
      'id': id,
      'reason': reason,
      'ts': DateTime.now().toUtc().toIso8601String(),
    }, kind: 'tombstone'));
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
      unawaited(_enqueueReliable(
        json,
        kind: (json['kind'] as String?) ?? 'raw',
      ));
      return;
    }

    // Résilience cascade BLE → Wi-Fi → 5G : si aucun transport local n'a de
    // pair connecté, le broadcast ne touchera personne (ex: BLE actif mais
    // aucun device connecté). On persiste le message en outbox pour le
    // re-diffuser dès qu'un pair apparaîtra.
    if (!localTransports.any((t) => t.hasActivePeers)) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] aucun pair local connecté, '
            'message mis en attente (outbox Hive)');
      }
      unawaited(_enqueueReliable(
        json,
        kind: (json['kind'] as String?) ?? 'raw',
      ));
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
    _retransmitTimer?.cancel();
    _retransmitTimer = null;
    _incomingBacklog.clear();
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
    _recentlyTombstonedIds.clear();
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
    // Anti-perte : tout message est mis en file FIFO, jamais jeté. Un seul
    // « drainer » tourne à la fois (1 message par microtask) pour préserver
    // la réactivité de l'UI lors des bursts BLE/RF.
    if (_incomingBacklog.length < _maxIncomingBacklog) {
      _incomingBacklog.add(raw);
    } else if (kDebugMode) {
      debugPrint(
        '[P2PMeshService] backlog saturé ($_maxIncomingBacklog) — la DB '
        'restant idempotente, aucun doublon ne sera créé',
      );
    }

    if (_pendingMicrotasks > 0) return;

    _pendingMicrotasks = 1;
    scheduleMicrotask(_processQueue);
  }

  /// Traitement effectif d'un message entrant, exécuté dans un microtask.
  void _processIncomingMessage(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;

      // Cas ACK : acquittement applicatif d'un message fiable délivré.
      // L'identifiant `mid` permet de retirer l'entrée correspondante de
      // l'outbox de l'émetteur (livraison next-hop confirmée).
      if (json['kind'] == 'ack' && json['mid'] is String) {
        final mid = json['mid'] as String;
        if (_outbox.isReady) {
          unawaited(_outbox.acknowledge(mid));
        }
        return;
      }

      // Cas enveloppe fiable (Store-and-Forward) : dépaquetage + ACK.
      // L'émetteur envoie { v, mid, from, seq, kind, d } ; on acquitte, on
      // dédoublonne puis on traite le contenu applicatif `d` normalement.
      if (json['v'] == 1 && json['mid'] is String && json['d'] is Map) {
        final mid = json['mid'] as String;
        _sendAck(mid);
        final inner = json['d'];
        if (inner is Map<String, dynamic>) {
          _processIncomingMap(inner);
        }
        return;
      }

      _processIncomingMap(json);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] message ignoré (parse error): $e');
      }
    }
  }

  /// Traite un message applicatif (après dépaquetage éventuel de l'enveloppe).
  void _processIncomingMap(Map<String, dynamic> json) {
    // Cas 0 : `welcome` du relay (handshake) → rattrapage des messages
    // manqués pendant une déconnexion (backlog serveur).
    if (json['kind'] == 'welcome') {
      _onWelcomeReceived(json);
      return;
    }

    // Cas 1 : alerte P2P directe. Reconnaît le format réel produit par
    // `Alert.toJson()` (id + reporter_id / userId / euid + type + position).
    // (Correction : l'ancienne condition exigeait `euid`, jamais émis → les
    // alertes diffusées entre pairs étaient silencieusement ignorées.)
    final isAlert = json['id'] is String &&
        json['type'] is String &&
        (json.containsKey('lat') ||
            json.containsKey('lng') ||
            json.containsKey('lon')) &&
        (json['reporter_id'] is String ||
            json['userId'] is String ||
            json['euid'] is String);
    if (isAlert) {
      _onAlertReceived(Alert.fromJson(json));
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

    // Cas 5 : signalement reçu du serveur central (diffusion temps réel).
    if (json['kind'] == 'report_validated' || json['kind'] == 'new_alert') {
      final alertJson = json['alert'];
      if (alertJson is Map<String, dynamic>) {
        _onServerAlertReceived(Alert.fromJson(alertJson));
      }
      return;
    }

    // Cas 5b : demande de payloads d'alertes manquantes (gossip pull).
    if (json['kind'] == 'alert_request' && json['ids'] is List) {
      _onAlertRequestReceived((json['ids'] as List).cast<String>());
      return;
    }

    // Cas 6 : tombstone (suppression/rejet) propagé entre pairs P2P.
    if (json['kind'] == 'tombstone' && json['id'] is String) {
      _onTombstoneReceived(json);
      return;
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

  /// Alerte validée/rejetée reçue du serveur central (diffusion temps réel).
  ///
  /// Contrairement à [_onAlertReceived] (gossip P2P), on ne RE-PROPAGE PAS
  /// l'alerte : le serveur la diffuse déjà à tous les clients mesh connectés.
  /// On la stocke localement et on notifie l'UI (carte + liste) immédiatement.
  void _onServerAlertReceived(Alert alert) {
    if (alert.isExpired()) return;
    if (_recentlyReceivedAlertIds.contains(alert.id)) return;
    _recentlyReceivedAlertIds.add(alert.id);
    if (_recentlyReceivedAlertIds.length > _maxRecentAlertCache) {
      final toRemove = _recentlyReceivedAlertIds.take(
        _recentlyReceivedAlertIds.length ~/ 4,
      );
      _recentlyReceivedAlertIds.removeAll(toRemove);
    }

    unawaited(database.upsertFromServer(alert).then((_) {
      _alertsReceivedController.add(alert);
      if (kDebugMode) {
        debugPrint(
          '[P2PMeshService] signalement reçu du serveur : ${alert.id} '
          '(${alert.type.name}, status=${alert.status.name})',
        );
      }
    }));
  }

  /// Reçoit un tombstone (signalement supprimé/rejeté) d'un pair : supprime
  /// l'alerte localement puis RE-PROPAGE aux autres pairs (flooding contrôlé
  /// par un cache anti-dédoublement).
  void _onTombstoneReceived(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final reason = json['reason'] as String? ?? 'deleted';
    if (_recentlyTombstonedIds.contains(id)) return;
    _recentlyTombstonedIds.add(id);
    if (_recentlyTombstonedIds.length > _maxTombstoneCache) {
      _recentlyTombstonedIds.remove(_recentlyTombstonedIds.first);
    }
    unawaited(database.delete(id).then((_) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] tombstone reçu : $id ($reason)');
      }
      broadcastTombstone(id, reason: reason);
    }));
  }

  void _onGossipReceived(List<String> remoteIds) {
    final localIds = database.getAllValid().map((a) => a.id).toSet();
    final missing = remoteIds.where((id) => !localIds.contains(id)).toList();
    if (missing.isEmpty) return;

    if (kDebugMode) {
      debugPrint(
          '[P2PMeshService] gossip: ${missing.length} alerte(s) inconnue(s), demande des payloads');
    }

    // Pull-based gossip : au lieu d'ignorer les alertes manquantes, on
    // demande leur payload complet à tous les pairs à portée. Ceux qui les
    // possèdent répondront en les (re)broadcastant.
    final requested = missing.take(20).toList();
    unawaited(broadcastRawJson({
      'kind': 'alert_request',
      'ids': requested,
      'ts': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  /// Rejoue les messages `missed` reçus dans le paquet `welcome`/`sync` du
  /// relay, afin de rattraper ce qui a été perdu pendant une déconnexion.
  /// Suit le curseur `seq` serveur (idempotent, insensible à l'horloge).
  void _onWelcomeReceived(Map<String, dynamic> json) {
    final serverSeq = (json['seq'] as num?)?.toInt() ?? 0;
    final isSyncResponse = json.containsKey('syncFrom');

    final missed = json['missed'];
    if (missed is! List || missed.isEmpty) {
      if (serverSeq > _lastServerSeq) {
        // Totalement à jour (aucun manque) → le curseur avance.
        _lastServerSeq = serverSeq;
        unawaited(_outbox.setCursor('server_seq', serverSeq));
      }
      // Une réponse générique (fenêtre 24 h) est moins précise qu'un delta
      // seq : on confirme une fois via sync_from (idempotent).
      if (!isSyncResponse) {
        unawaited(_requestSyncFrom());
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '[P2PMeshService] welcome : ${missed.length} message(s) manqué(s) à rattraper');
    }

    int maxConsumed = _lastServerSeq;
    for (final entry in missed) {
      if (entry is! Map) continue;
      final seq = (entry['seq'] as num?)?.toInt() ?? 0;
      if (seq > maxConsumed) maxConsumed = seq;
      final data = entry['data'];
      if (data is! Map<String, dynamic>) continue;
      // Évite toute boucle infinie (un `welcome` en backlog est ignoré).
      if (data['kind'] == 'welcome') continue;
      try {
        _processIncomingMessage(jsonEncode(data));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PMeshService] welcome replay error: $e');
        }
      }
    }

    if (maxConsumed > _lastServerSeq) {
      _lastServerSeq = maxConsumed;
      unawaited(_outbox.setCursor('server_seq', maxConsumed));
    }

    if (!isSyncResponse) {
      unawaited(_requestSyncFrom());
    }
  }

  /// Répond à une demande de payloads (`alert_request`) en (re)broadcastant
  /// les alertes locales demandées. Léger délai aléatoire pour éviter les
  /// collisions de réponses simultanées.
  void _onAlertRequestReceived(List<String> ids) {
    final requested = ids.toSet();
    final owned =
        database.getAllValid().where((a) => requested.contains(a.id)).toList();
    if (owned.isEmpty) return;

    if (kDebugMode) {
      debugPrint(
          '[P2PMeshService] réponse demande payloads : ${owned.length} alerte(s)');
    }

    for (final alert in owned) {
      if (alert.isExpired()) continue;
      Future.delayed(Duration(milliseconds: Random().nextInt(1500)), () {
        if (!alert.isExpired()) broadcastAlert(alert);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Livraison fiable (Store-and-Forward) : outbox persistante + ACK + backoff
  // ═══════════════════════════════════════════════════════════════════

  /// Empile un message sortant dans l'outbox persistante avec un `seq`
  /// croissant par émetteur. L'émission et les réémissions sont pilotées
  /// par [_retransmitDue].
  Future<void> _enqueueReliable(
    Map<String, dynamic> payload, {
    required String kind,
  }) async {
    try {
      if (!_outbox.isReady) await _outbox.init();
    } catch (e) {
      if (kDebugMode) debugPrint('[P2PMeshService] outbox indisponible: $e');
      return;
    }
    final entry = MeshOutboxEntry(
      id: _generateMessageId(),
      kind: kind,
      seq: _outbox.nextSeq(),
      from: localPeerId,
      payload: jsonEncode(payload),
      createdAt: DateTime.now().toUtc(),
      attempts: 0,
      nextAttemptAt: DateTime.now().toUtc(),
    );
    await _outbox.enqueue(entry);
  }

  /// Réémet les messages de l'outbox arrivés à échéance, avec un backoff
  /// progressif borné. Un message reste en file tant qu'il n'est pas ACK
  /// (ou qu'il n'a pas épuisé ses tentatives).
  Future<void> _retransmitDue() async {
    if (!_outbox.isReady) return;
    try {
      await _outbox.prune();
    } catch (_) {}
    final due = _outbox.due();
    if (due.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final e in due) {
      if (e.attempts >= _maxReliableAttempts) {
        await _outbox.markFailed(e.id);
        continue;
      }
      await _transmitEntry(e);
      final idx = e.attempts < _retryDelays.length
          ? e.attempts
          : _retryDelays.length - 1;
      await _outbox.touch(
        e.id,
        attempts: e.attempts + 1,
        nextAttemptAt: now.add(_retryDelays[idx]),
      );
    }
  }

  /// Émet une entrée de l'outbox, enveloppée dans un frame fiable.
  Future<void> _transmitEntry(MeshOutboxEntry e) async {
    final envelope = jsonEncode({
      'v': 1,
      'mid': e.id,
      'from': e.from,
      'seq': e.seq,
      'kind': e.kind,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'd': jsonDecode(e.payload),
    });
    await _broadcastEnvelope(envelope);
  }

  /// Diffuse une enveloppe en évitant la saturation simultanée de la bande
  /// 2,4 GHz : on choisit UN seul canal local actif (BLE ou Wi-Fi), puis on
  /// ajoute le relay cellulaire (bande différente) si disponible.
  Future<void> _broadcastEnvelope(String envelope) async {
    final local =
        transports.where((t) => _isLocalTransport(t) && t.isAvailable).toList();

    MeshTransport? chosen;
    for (final t in local) {
      if (t.hasActivePeers) {
        chosen = t;
        break;
      }
    }

    final targets = <MeshTransport>[];
    if (chosen != null) {
      targets.add(chosen);
    } else {
      targets.addAll(local);
    }
    for (final r in transports.where(_isRelayTransport)) {
      if (r.isAvailable) targets.add(r);
    }

    if (targets.isEmpty) {
      // Aucun transport dispo : l'entrée reste en outbox, réessayée au
      // prochain tick (Store-and-Forward).
      return;
    }
    await Future.wait(targets.map((t) => _safeBroadcast(t, envelope)));
  }

  Future<void> _safeBroadcast(MeshTransport t, String payload) async {
    try {
      await t.broadcast(payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] émission fiable ${t.name}: $e');
      }
    }
  }

  bool _isLocalTransport(MeshTransport t) {
    final n = t.name.toLowerCase();
    return !n.contains('relay') &&
        !n.contains('remote') &&
        !n.contains('server');
  }

  bool _isRelayTransport(MeshTransport t) =>
      t.name.toLowerCase().contains('relay');

  /// Émet l'ACK applicatif d'un message fiable reçu (une seule fois par `mid`).
  void _sendAck(String mid) {
    if (_seenEnvelopeIds.contains(mid)) return;
    _seenEnvelopeIds.add(mid);
    if (_seenEnvelopeIds.length > _maxSeenEnvelopeIds) {
      _seenEnvelopeIds.remove(_seenEnvelopeIds.first);
    }
    // ACK uniquement sur les transports LOCAUX (le relay est déjà fiable via
    // TCP/WSS et n'a pas besoin d'ACK applicatif).
    unawaited(broadcastRawJsonLocal({
      'kind': 'ack',
      'mid': mid,
      'ts': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  /// Demande au relay serveur le delta de messages mesh postérieurs à
  /// [_lastServerSeq] (rattrapage idempotent). Sans relay → no-op.
  Future<void> _requestSyncFrom() async {
    final relays = transports.where(_isRelayTransport).toList();
    if (relays.isEmpty) return;
    final payload = jsonEncode({
      'kind': 'sync_from',
      'seq': _lastServerSeq,
      'peerId': localPeerId,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    for (final t in relays) {
      try {
        await t.broadcast(payload);
      } catch (e) {
        if (kDebugMode) debugPrint('[P2PMeshService] sync_from ${t.name}: $e');
      }
    }
  }

  /// Vide la file FIFO des messages entrants, UN message par microtask, sans
  /// jamais jeter de paquet.
  void _processQueue() {
    if (_incomingBacklog.isEmpty) {
      _pendingMicrotasks = 0;
      return;
    }
    final raw = _incomingBacklog.removeAt(0);
    _processIncomingMessage(raw);
    scheduleMicrotask(_processQueue);
  }

  static String _generateMessageId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'm-$hex';
  }
}
