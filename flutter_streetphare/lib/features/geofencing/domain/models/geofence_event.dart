// lib/features/geofencing/domain/models/geofence_event.dart
//
// Modèle d'événement de proximité (geofence) déclenché quand
// l'utilisateur entre dans un rayon donné autour d'un signalement
// actif. Sert d'input au système de validation collaborative.

import 'package:latlong2/latlong.dart';

import '../../../../database/alert_model.dart';

/// Événement émis par le GeofencingService quand l'utilisateur
/// entre dans la zone de proximité d'un signalement.
class GeofenceEvent {
  const GeofenceEvent({
    required this.alert,
    required this.userPosition,
    required this.distanceMeters,
  });

  /// Le signalement qui a déclenché l'entrée en zone.
  final Alert alert;

  /// Position de l'utilisateur au moment du déclenchement.
  final LatLng userPosition;

  /// Distance utilisateur → centre du signalement (en mètres).
  final double distanceMeters;
}
