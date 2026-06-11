// lib/features/messaging/presentation/hive_messaging_service.dart
//
// Service de messagerie décentralisée basé sur l'infrastructure Hive P2P.
//
// Fonctionnalités :
//   1. Diffusion (broadcast) de messages textuels sur le réseau maillé.
//   2. Réception et déduplication des messages entrants.
//   3. Filtrage configurable (tous / proches / admin / alertes).
//   4. Identification éphémère par UUID de session (anonymat garanti).
//   5. TTL des messages : 6 heures (purge automatique).

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../settings/data/app_preferences_store.dart';
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
/// Usage :
/// ```dart
/// // Broadcaster un message
/// HiveMessagingService.instance.broadcast(
///   content: 'RAS côté Nord',
///   userPosition: LatLng(50.47, 4.55),
/// );
///
/// // Écouter les messages filtrés
/// ValueListenableBuilder<List<HiveMessage>>(
///   valueListenable: HiveMessagingService.instance,
///   builder: (_, messages, __) => ...,
/// );
/// ```
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
    debugPrint('[HiveMessaging] service démarré — id=$_localEphemeralId');
  }

  /// Arrête le service et libère les ressources.
  void stop() {
    _purgeTimer?.cancel();
    _purgeTimer = null;
    _started = false;
  }

  // --------------------------------------------------------------------------
  // Diffusion d'un message
  // --------------------------------------------------------------------------

  /// Diffuse un message textuel sur le réseau Hive P2P.
  ///
  /// [content] : texte du message (max 500 caractères).
  /// [userPosition] : position GPS de l'émetteur (optionnel).
  /// [type] : type du message (défaut : [HiveMessageType.text]).
  void broadcast({
    required String content,
    LatLng? userPosition,
    HiveMessageType type = HiveMessageType.text,
  }) {
    if (content.trim().isEmpty) return;
    final trimmed = content.trim().substring(0, min(content.trim().length, 500));

    final msg = HiveMessage(
      id: _generateMessageId(),
      senderEphemeralId: _localEphemeralId,
      content: trimmed,
      type: type,
      sentAt: DateTime.now().toUtc(),
      latitude: userPosition?.latitude,
      longitude: userPosition?.longitude,
      isFromAdmin: false,
    );

    // Le message de l'utilisateur local est toujours visible (pas de filtre).
    _allMessages[msg.id] = msg;
    _trimToLimit();
    _emitFiltered(userPosition: userPosition);

    // TODO : diffuser msg.toJson() sur le réseau maillé (BLE/Relay).
    // NetworkCoordinator.instance.broadcastMessage(msg.toJson());
    debugPrint('[HiveMessaging] message diffusé: ${msg.id}');
  }

  // --------------------------------------------------------------------------
  // Réception d'un message distant
  // --------------------------------------------------------------------------

  /// Appelé par le transport P2P lorsqu'un message est reçu d'un pair.
  ///
  /// [json] : payload JSON du message reçu.
  /// [localPosition] : position GPS locale (pour le filtre "proches").
  void receiveRemote(
    Map<String, dynamic> json, {
    LatLng? localPosition,
  }) {
    try {
      final msg = HiveMessage.fromJson(json);
      if (msg.id.isEmpty) return;

      // Déduplication : on ignore les messages déjà reçus.
      if (_allMessages.containsKey(msg.id)) {
        debugPrint('[HiveMessaging] message dupliqué ignoré: ${msg.id}');
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
          // Filtre TTL (messages expirés).
          if (now.difference(msg.sentAt) > _kMessageTtl) return false;

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
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt)); // Plus récent en premier

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
    debugPrint('[HiveMessaging] purge — ${_allMessages.length} messages conservés');
  }

  void _trimToLimit() {
    if (_allMessages.length <= _kMaxMessages) return;
    // Supprime les plus anciens messages.
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
