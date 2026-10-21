// lib/features/geofencing/domain/models/geofence_event.dart
//
// Modèle d'événement de proximité (geofence) déclenché quand
// l'utilisateur entre dans un rayon donné autour d'un signalement
// actif, ou lors d'une demande dynamique de validation :
//   a) Aucun vote/confirmation enregistré depuis ≥ 5 minutes.
//   b) Signalement contradictoire/différent émis au même endroit.

import 'package:latlong2/latlong.dart';

import '../../../../core/models/alert_model.dart';

/// Raison ayant déclenché la sollicitation de validation auprès de l'utilisateur proche.
enum ValidationTriggerReason {
  /// Entrée standard dans le périmètre de proximité du signalement.
  proximityEntry,

  /// Aucun vote/confirmation n'a été enregistré depuis au moins 5 minutes.
  staleNoVote5Min,

  /// Un signalement contradictoire/différent a été émis au même endroit.
  contradictoryReport,
}

/// Événement émis par le GeofencingService quand l'utilisateur
/// est sollicité pour valider ou infirmer un signalement proche.
class GeofenceEvent {
  const GeofenceEvent({
    required this.alert,
    required this.userPosition,
    required this.distanceMeters,
    this.reason = ValidationTriggerReason.proximityEntry,
    this.conflictingAlertType,
  });

  /// Le signalement à valider ou infirmer.
  final Alert alert;

  /// Position de l'utilisateur au moment du déclenchement.
  final LatLng userPosition;

  /// Distance utilisateur → centre du signalement (en mètres).
  final double distanceMeters;

  /// Raison de la demande de validation dynamique.
  final ValidationTriggerReason reason;

  /// Type du signalement contradictoire éventuel détecté au même endroit.
  final AlertType? conflictingAlertType;
}
