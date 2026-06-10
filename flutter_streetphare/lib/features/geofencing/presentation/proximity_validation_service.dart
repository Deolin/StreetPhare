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

import 'package:flutter/foundation.dart';

import '../../../database/hive_alert_database.dart';
import '../../../network/network_coordinator.dart';
import 'geofencing_service.dart';
import '../domain/models/geofence_event.dart';

/// Service singleton de validation de proximité.
class ProximityValidationService {
  ProximityValidationService._();
  static final ProximityValidationService instance =
      ProximityValidationService._();

  /// Cooldown anti-spam (5 minutes) entre deux questions posées
  /// au même utilisateur pour un même signalement.
  static const Duration antiSpamCooldown = Duration(minutes: 5);

  StreamSubscription<GeofenceEvent>? _geofenceSub;

  final _filteredEventsController =
      StreamController<GeofenceEvent>.broadcast();
  Stream<GeofenceEvent> get filteredEvents =>
      _filteredEventsController.stream;

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
      if (_isInCooldown(event.alert.id)) {
        if (kDebugMode) {
          debugPrint(
              '[ProximityValidation] anti-spam : skip ${event.alert.id}');
        }
        return;
      }
      _filteredEventsController.add(event);
    });
  }

  /// Enregistre un vote OUI : confirme que le danger est toujours là.
  ///
  /// Effets :
  ///   1. Ajoute une confirmation anonyme (mécanisme consensus).
  ///   2. Le re-broadcast associé relance le cycle de vie du
  ///      signalement (les pairs qui le reçoivent le maintiennent
  ///      "actif" et il continue à s'afficher).
  ///   3. Met à jour le cooldown anti-spam.
  Future<bool> castYes(GeofenceEvent event) async {
    _lastVoteTimestamps[event.alert.id] = DateTime.now().toUtc();
    final reached = await NetworkCoordinator.instance.confirmAlert(
      event.alert.id,
    );
    if (kDebugMode) {
      debugPrint(
          '[ProximityValidation] OUI pour ${event.alert.id} (consensus=$reached)');
    }
    return reached;
  }

  /// Enregistre un vote NON : invalide le danger.
  ///
  /// Effets :
  ///   1. Supprime l'alerte de la base locale (disparition
  ///      immédiate du marqueur).
  ///   2. Met à jour le cooldown anti-spam.
  Future<void> castNo(GeofenceEvent event) async {
    _lastVoteTimestamps[event.alert.id] = DateTime.now().toUtc();
    await HiveAlertDatabase.instance.delete(event.alert.id);
    if (kDebugMode) {
      debugPrint('[ProximityValidation] NON pour ${event.alert.id} '
          '(alerte supprimée)');
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
    final remaining = antiSpamCooldown -
        DateTime.now().toUtc().difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> dispose() async {
    await _geofenceSub?.cancel();
    await _filteredEventsController.close();
    _started = false;
  }
}
