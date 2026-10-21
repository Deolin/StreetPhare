// lib/features/geofencing/presentation/proximity_validation_service.dart
//
// Service de VALIDATION DE PROXIMITÉ.
//
// C'est l'orchestrateur du "ping de proximité" :
//   1. Il écoute le flux de `GeofenceEvent` émis par
//      `GeofencingService`.
//   2. Pour chaque event entrant, il vérifie la RÈGLE ANTI-SPAM :
//      un même utilisateur ne peut pas se voir re-proposer la
//      question pour le MÊME signalement (id) avant un délai
//      de COOLDOWN de 5 minutes.
//   3. Si l'event passe le filtre anti-spam, il le réémet sur
//      un `Stream<GeofenceEvent>` dédié à l'UI pour affichage
//      du BottomSheet.
//   4. Lorsque l'utilisateur clique OUI ou NON, on l'enregistre
//      via [castYes] / [castNo] qui :
//        - OUI : ajoute une confirmation anonyme (consensus) et
//          prolonge le TTL (le `confirmAlert` rebroadcast le
//          signalement, ce qui le maintient vivant).
//        - NON : supprime l'alerte de la base locale (disparition
//          immédiate du marqueur).
//        - Met à jour le timestamp de dernier vote pour le
//          cooldown anti-spam.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/report_service.dart';
import '../../../database/hive_alert_database.dart';
import '../../../network/network_coordinator.dart';
import '../../../services/notification_service.dart';
import '../domain/models/geofence_event.dart';
import 'geofencing_service.dart';

const String _validationApiBase = String.fromEnvironment(
  'STREETPHARE_API_BASE',
  defaultValue: 'http://10.0.2.2:3000',
);

/// Service singleton de validation de proximité.
class ProximityValidationService {
  ProximityValidationService._();
  static final ProximityValidationService instance =
      ProximityValidationService._();

  /// Cooldown anti-spam (5 minutes) entre deux questions posées
  /// au même utilisateur pour un même signalement.
  static const Duration antiSpamCooldown = Duration(minutes: 5);

  StreamSubscription<GeofenceEvent>? _geofenceSub;

  final _filteredEventsController = StreamController<GeofenceEvent>.broadcast();
  Stream<GeofenceEvent> get filteredEvents => _filteredEventsController.stream;

  /// Map id d'alerte → timestamp du dernier vote OUI/NON posé.
  final Map<String, DateTime> _lastVoteTimestamps = <String, DateTime>{};

  bool _started = false;

  /// Démarre le service. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    // On s'abonne au flux de GeofencingService et on applique
    // le filtre anti-spam.
    _geofenceSub = GeofencingService.instance.events.listen((event) {
      // Un signalement contradictoire contourne le cooldown standard si c'est un nouveau conflit
      final bypassCooldown =
          event.reason == ValidationTriggerReason.contradictoryReport;
      if (!bypassCooldown && _isInCooldown(event.alert.id)) {
        if (kDebugMode) {
          debugPrint(
              '[ProximityValidation] anti-spam : skip ${event.alert.id}');
        }
        return;
      }
      _notifyUserForValidation(event);
      _filteredEventsController.add(event);
    });
  }

  void _notifyUserForValidation(GeofenceEvent event) {
    try {
      final String title;
      switch (event.reason) {
        case ValidationTriggerReason.contradictoryReport:
          title = '⚡ Signalement contradictoire à proximité';
        case ValidationTriggerReason.staleNoVote5Min:
          title = '⏱ Vérification d\'un signalement (sans vote > 5 min)';
        case ValidationTriggerReason.proximityEntry:
          title = '📍 Confirmez-vous ce signalement proche ?';
      }
      unawaited(
        NotificationService.instance.showAlertNotification(
          title: title,
          body:
              'Un signalement (${event.alert.type.name}) est à ${event.distanceMeters.toStringAsFixed(0)} m. Ouvrez StreetPhare pour confirmer ou infirmer.',
        ),
      );
    } catch (_) {}
  }

  /// Enregistre un vote OUI : confirme que le danger est toujours là.
  ///
  /// Effets :
  ///   1. Ajoute une confirmation anonyme (mécanisme consensus).
  ///   2. Envoie la confirmation au serveur (`POST /api/alerts/:id/verify`)
  ///      pour rafraîchir `lastVoteAt`.
  ///   3. Met à jour le cooldown anti-spam.
  Future<bool> castYes(GeofenceEvent event) async {
    _lastVoteTimestamps[event.alert.id] = DateTime.now().toUtc();
    final reached = await NetworkCoordinator.instance.confirmAlert(
      event.alert.id,
    );
    unawaited(_sendServerVerification(event.alert.id, confirmed: true));
    if (kDebugMode) {
      debugPrint(
          '[ProximityValidation] OUI pour ${event.alert.id} (consensus=$reached)');
    }
    return reached;
  }

  /// Enregistre un vote NON : invalide le danger et purge la donnée erronée.
  ///
  /// Effets :
  ///   1. Supprime l'alerte de la base locale (disparition immédiate du marqueur).
  ///   2. Envoie l'infirmation au serveur (`POST /api/alerts/:id/verify` avec `vote: 'refute'`)
  ///      pour purger le signalement erroné auprès de tous les utilisateurs.
  ///   3. Met à jour le cooldown anti-spam.
  Future<void> castNo(GeofenceEvent event) async {
    _lastVoteTimestamps[event.alert.id] = DateTime.now().toUtc();
    await HiveAlertDatabase.instance.delete(event.alert.id);
    unawaited(_sendServerVerification(event.alert.id, confirmed: false));
    if (kDebugMode) {
      debugPrint('[ProximityValidation] NON pour ${event.alert.id} '
          '(alerte purgée localement + serveur notifié)');
    }
  }

  Future<void> _sendServerVerification(
    String alertId, {
    required bool confirmed,
  }) async {
    try {
      final uid = currentUserId ?? 'anon_peer';
      final uri = Uri.parse('$_validationApiBase/api/alerts/$alertId/verify');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': uid,
              'vote': confirmed ? 'confirm' : 'refute',
              'confirmed': confirmed,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Silencieux en mode hors-ligne / P2P pur.
    }
  }

  /// Indique si une alerte est en cooldown pour cet utilisateur.
  bool _isInCooldown(String alertId) {
    final last = _lastVoteTimestamps[alertId];
    if (last == null) return false;
    return DateTime.now().toUtc().difference(last) < antiSpamCooldown;
  }

  /// Renvoie le temps restant avant la fin du cooldown (ou
  /// `Duration.zero` si aucun cooldown actif).
  Duration cooldownRemainingFor(String alertId) {
    final last = _lastVoteTimestamps[alertId];
    if (last == null) return Duration.zero;
    final remaining =
        antiSpamCooldown - DateTime.now().toUtc().difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> dispose() async {
    await _geofenceSub?.cancel();
    await _filteredEventsController.close();
    _started = false;
  }
}
