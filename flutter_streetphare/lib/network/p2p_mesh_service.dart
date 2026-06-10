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

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../database/alert_model.dart';
import '../database/hive_alert_database.dart';

/// Représente un pair (autre appareil) découvert sur le maillage.
class MeshPeer {
  final String id;
  final String transport; // 'ble' | 'wifi' | 'relay'
  final DateTime lastSeen;

  const MeshPeer({
    required this.id,
    required this.transport,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        't': transport,
        'ls': lastSeen.toIso8601String(),
      };

  factory MeshPeer.fromJson(Map<String, dynamic> j) => MeshPeer(
        id: j['id'] as String,
        transport: j['t'] as String,
        lastSeen: DateTime.parse(j['ls'] as String).toUtc(),
      );
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
    this.gossipInterval = const Duration(seconds: 30),
    this.discoveryInterval = const Duration(seconds: 10),
  });

  final HiveAlertDatabase database;
  final List<MeshTransport> transports;

  /// Intervalle entre deux broadcasts de la base locale (gossip).
  final Duration gossipInterval;

  /// Intervalle entre deux scans de pairs.
  final Duration discoveryInterval;

  final _peersController = StreamController<List<MeshPeer>>.broadcast();
  Stream<List<MeshPeer>> get peers => _peersController.stream;

  final _alertsReceivedController =
      StreamController<Alert>.broadcast();
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

  /// Démarre tous les transports et la boucle de gossip.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    for (final t in transports) {
      try {
        if (t.isAvailable) {
          await t.start();
          _subs.add(t.incoming.listen(_handleIncoming));
          if (kDebugMode) {
            debugPrint('[P2PMeshService] transport ${t.name} démarré');
          }
        } else if (kDebugMode) {
          debugPrint('[P2PMeshService] transport ${t.name} indisponible');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[P2PMeshService] erreur ${t.name}: $e');
      }
    }

    _gossipTimer = Timer.periodic(gossipInterval, (_) => _gossip());
    _discoveryTimer = Timer.periodic(discoveryInterval, (_) => _pingPeers());
  }

  /// Diffuse une alerte à tous les pairs sur tous les transports.
  Future<void> broadcastAlert(Alert alert) async {
    final payload = alert.toCompact();
    for (final t in transports) {
      try {
        await t.broadcast(payload);
      } catch (e) {
        if (kDebugMode) debugPrint('[P2PMeshService] broadcast ${t.name}: $e');
      }
    }
  }

  /// Diffuse un payload JSON brut (ex : signal panic) sur tous les transports.
  Future<void> broadcastRawJson(Map<String, dynamic> json) async {
    final payload = jsonEncode(json);
    for (final t in transports) {
      try {
        await t.broadcast(payload);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[P2PMeshService] broadcastRaw ${t.name}: $e');
        }
      }
    }
  }

  /// Démarre le service.
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
      } catch (_) {}
    }
    _started = false;
  }

  /// Wrapper JSON de gossip : envoie la liste compacte des IDs connus.
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
    for (final t in transports) {
      t.broadcast(payload);
    }
  }

  /// Ping simple pour la découverte (les vrais implémentations
  /// remontent déjà la liste via les callbacks natifs BLE/Wi-Fi).
  void _pingPeers() {
    _peers.removeWhere((_, p) =>
        DateTime.now().toUtc().difference(p.lastSeen).inMinutes > 5);
    _peersController.add(_peers.values.toList());
  }

  /// Point d'entrée des messages reçus par n'importe quel transport.
  void _handleIncoming(String raw) {
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
        _peers[json['id']] = MeshPeer(
          id: json['id'],
          transport: json['t'] ?? 'unknown',
          lastSeen: DateTime.now().toUtc(),
        );
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[P2PMeshService] message ignoré (parse error): $e');
      }
    }
  }

  Future<void> _onAlertReceived(Alert alert) async {
    if (alert.isExpired()) return; // sécurité supplémentaire
    // Important : on stocke puis on propage (flooding contrôlé).
    await database.insertOrMerge(alert);
    _alertsReceivedController.add(alert);
    if (kDebugMode) {
      debugPrint('[P2PMeshService] alerte reçue : ${alert.id} '
          '(${alert.confirmations.length}/3)');
    }
    // Re-propagation avec une petite déduplication temporelle
    // (ici simplifiée : on rebroadcast directement, mais on
    // pourrait ajouter un cache de messages déjà vus).
    final ttl = Random().nextInt(2000);
    Future.delayed(Duration(milliseconds: ttl), () {
      broadcastAlert(alert);
    });
  }

  Future<void> _onGossipReceived(List<String> remoteIds) async {
    final localIds = database.getAllValid().map((a) => a.id).toSet();
    final missing = remoteIds.where((id) => !localIds.contains(id)).toList();
    if (missing.isEmpty) return;

    if (kDebugMode) {
      debugPrint('[P2PMeshService] gossip: ${missing.length} alertes inconnues');
    }
    // NOTE : dans un vrai système, on demanderait au pair distant
    // de nous renvoyer les payloads manquants. Ici, on déclenche
    // simplement un broadcast partiel.
  }
}
