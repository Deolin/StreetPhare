// lib/features/messaging/presentation/hive_messaging_service.dart
//
// Service de messagerie décentralisée basé sur l'infrastructure Hive P2P.
//
// [1] Architecture Réseau Hybride Asynchrone :
//     Le réseau local P2P (BLE Mesh / Wi-Fi Local) traite les données
//     en PRIORITÉ ABSOLUE. La propagation vers le serveur distant est
//     reléguée en arrière-plan via une tâche asynchrone non bloquante.
//
// [2] Messagerie filtrée & groupes temporaires :
//     - Blocage par UUID éphémère (filtre local invisible).
//     - Création de fils temporaires (30 min par défaut, configurable).
//     - Ajout de participants à un fil existant.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../network/network_coordinator.dart';
import '../../settings/data/app_preferences_store.dart';
import '../data/hive_block_service.dart';
import '../domain/models/hive_message.dart';

// ============================================================================
// Constants
// ============================================================================

/// Rayon de proximité pour le filtre "Messages proches uniquement" (mètres).
const double _kNearbyRadiusMeters = 300.0;

/// Durée de vie d'un message (purge automatique après ce délai).
const Duration _kMessageTtl = Duration(hours: 6);

/// Nombre maximum de messages en mémoire.
const int _kMaxMessages = 200;

// ============================================================================
// HiveMessagingService
// ============================================================================

/// Service singleton de messagerie P2P décentralisée.
///
/// Architecture réseau hybride :
///   PRIORITÉ 1 → Réseau local P2P (BLE Mesh / Wi-Fi Direct) — synchrone.
///   PRIORITÉ 2 → Serveur distant (192.168.31.18) — tâche d'arrière-plan.
class HiveMessagingService extends ValueNotifier<List<HiveMessage>> {
  HiveMessagingService._() : super(const []);

  static final HiveMessagingService instance = HiveMessagingService._();

  /// Identifiant éphémère de cet appareil pour la session en cours.
  final String _localEphemeralId = _generateEphemeralId();

  /// Tous les messages reçus (avant filtrage), par ID.
  final Map<String, HiveMessage> _allMessages = {};

  /// Timer de purge automatique des messages expirés.
  Timer? _purgeTimer;

  bool _started = false;

  // --------------------------------------------------------------------------
  // Démarrage / Arrêt
  // --------------------------------------------------------------------------

  /// Démarre le service (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    _purgeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _purgeExpired(),
    );
    // Charge les préférences de blocage.
    HiveBlockService.instance.load();
    debugPrint('[HiveMessaging] service démarré — id=$_localEphemeralId');
  }

  /// Arrête le service et libère les ressources.
  void stop() {
    _purgeTimer?.cancel();
    _purgeTimer = null;
    _started = false;
  }

  // --------------------------------------------------------------------------
  // Diffusion d'un message — [1] PRIORITÉ LOCALE P2P
  // --------------------------------------------------------------------------

  /// Diffuse un message textuel sur le réseau Hive P2P.
  ///
  /// Ordre de priorité strict :
  ///   1. Affichage local immédiat (UI non bloquante).
  ///   2. Propagation P2P locale (BLE Mesh / Wi-Fi Direct) — synchrone.
  ///   3. Propagation vers le serveur distant — tâche d'arrière-plan.
  void broadcast({
    required String content,
    LatLng? userPosition,
    HiveMessageType type = HiveMessageType.text,
    String? threadId,
  }) {
    if (content.trim().isEmpty) return;
    final trimmed =
        content.trim().substring(0, min(content.trim().length, 500));

    final msg = HiveMessage(
      id: _generateMessageId(),
      senderEphemeralId: _localEphemeralId,
      content: trimmed,
      type: type,
      sentAt: DateTime.now().toUtc(),
      latitude: userPosition?.latitude,
      longitude: userPosition?.longitude,
      isFromAdmin: false,
      threadId: threadId,
    );

    // PRIORITÉ 1 : Affichage local immédiat.
    _allMessages[msg.id] = msg;
    _trimToLimit();
    _emitFiltered(userPosition: userPosition);

    // PRIORITÉ 2 : Diffusion P2P locale + propagation serveur distant
    // dans une tâche d'arrière-plan (unawaited = non bloquant pour l'UI).
    unawaited(_broadcastWithPriority(msg));
    debugPrint('[HiveMessaging] message diffusé localement: ${msg.id}');
  }

  /// Pipeline de broadcast hiérarchique :
  ///   1. Réseau local P2P (BLE Mesh / Wi-Fi) — prioritaire.
  ///   2. Serveur distant — tâche d'arrière-plan non bloquante.
  Future<void> _broadcastWithPriority(HiveMessage msg) async {
    // Étape 1 : broadcast P2P local via NetworkCoordinator.
    try {
      await NetworkCoordinator.instance.broadcastHiveMessage(
        msg.toJson(),
        localPriorityOnly: true, // Signale au coordinator : réseau local ONLY.
      );
    } catch (e) {
      debugPrint('[HiveMessaging] échec broadcast P2P local: $e');
    }

    // Étape 2 (arrière-plan) : propagation vers le serveur distant.
    // Complètement détaché de l'UI.
    unawaited(_propagateToRemoteServer(msg));
  }

  /// Propagation asynchrone (background) vers le serveur distant.
  Future<void> _propagateToRemoteServer(HiveMessage msg) async {
    try {
      await NetworkCoordinator.instance.broadcastHiveMessage(
        msg.toJson(),
        localPriorityOnly: false, // Toutes les destinations.
      );
    } catch (e) {
      debugPrint('[HiveMessaging] échec propagation serveur distant: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Réception d'un message distant
  // --------------------------------------------------------------------------

  /// Appelé par le transport P2P lorsqu'un message est reçu d'un pair.
  void receiveRemote(
    Map<String, dynamic> json, {
    LatLng? localPosition,
  }) {
    try {
      final msg = HiveMessage.fromJson(json);
      if (msg.id.isEmpty) return;

      // Déduplication.
      if (_allMessages.containsKey(msg.id)) {
        debugPrint('[HiveMessaging] message dupliqué ignoré: ${msg.id}');
        return;
      }

      // [2] Filtrage des utilisateurs bloqués.
      if (HiveBlockService.instance.isBlocked(msg.senderEphemeralId)) {
        debugPrint('[HiveMessaging] message filtré (user bloqué): ${msg.senderEphemeralId}');
        return;
      }

      _allMessages[msg.id] = msg;
      _trimToLimit();
      _emitFiltered(userPosition: localPosition);
    } catch (e) {
      debugPrint('[HiveMessaging] erreur réception: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Filtrage
  // --------------------------------------------------------------------------

  /// Applique le filtre de messagerie configuré dans [AppPreferencesStore]
  /// et émet la liste filtrée via le [ValueNotifier].
  void _emitFiltered({LatLng? userPosition}) {
    final filter = AppPreferencesStore.instance.value.messageFilter;
    final now = DateTime.now().toUtc();

    final filtered = _allMessages.values
        .where((msg) {
          // Filtre : messages expirés.
          if (now.difference(msg.sentAt) > _kMessageTtl) return false;

          // [2] Filtre : utilisateurs bloqués (filtrage en temps réel).
          if (HiveBlockService.instance.isBlocked(msg.senderEphemeralId)) {
            return false;
          }

          // Filtre par type configuré dans les préférences.
          switch (filter) {
            case MessageFilter.all:
              return true;

            case MessageFilter.nearbyOnly:
              if (userPosition == null || msg.position == null) return true;
              final dist = _haversineMeters(userPosition, msg.position!);
              return dist <= _kNearbyRadiusMeters;

            case MessageFilter.adminOnly:
              return msg.isFromAdmin;

            case MessageFilter.alertOnly:
              return msg.type == HiveMessageType.alert;
          }
        })
        .toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt)); // Plus récent en premier.

    value = filtered;
  }

  /// Rafraîchit la liste filtrée avec la position actuelle.
  void refreshFilter({LatLng? userPosition}) {
    _emitFiltered(userPosition: userPosition);
  }

  // --------------------------------------------------------------------------
  // Purge des messages expirés
  // --------------------------------------------------------------------------

  void _purgeExpired() {
    final now = DateTime.now().toUtc();
    _allMessages.removeWhere(
      (_, msg) => now.difference(msg.sentAt) > _kMessageTtl,
    );
    _emitFiltered();
    debugPrint(
        '[HiveMessaging] purge — ${_allMessages.length} messages conservés');
  }

  void _trimToLimit() {
    if (_allMessages.length <= _kMaxMessages) return;
    final sorted = _allMessages.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final toRemove = sorted.take(_allMessages.length - _kMaxMessages);
    for (final msg in toRemove) {
      _allMessages.remove(msg.id);
    }
  }

  // --------------------------------------------------------------------------
  // Utilitaires
  // --------------------------------------------------------------------------

  static String _generateEphemeralId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generateMessageId() {
    final rng = Random.secure();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final rand = List<int>.generate(4, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$ts-$rand';
  }

  /// Distance Haversine approchée entre deux points GPS (en mètres).
  static double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180.0;
    final dLng = (b.longitude - a.longitude) * pi / 180.0;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final cosA = cos(a.latitude * pi / 180.0);
    final cosB = cos(b.latitude * pi / 180.0);
    final h = sinDLat * sinDLat + cosA * cosB * sinDLng * sinDLng;
    return 2.0 * r * asin(sqrt(h));
  }

  /// Identifiant éphémère de cet appareil (lecture seule).
  String get localEphemeralId => _localEphemeralId;
}
