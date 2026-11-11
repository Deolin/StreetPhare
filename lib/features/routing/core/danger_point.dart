// lib/features/routing/core/danger_point.dart
//
// Point de danger à éviter lors du routage, porteur de sa « sévérité ».
//
// Deux niveaux de sévérité :
//   - BLOCKING (barrage) : totalement infranchissable — poids quasi-infini.
//   - SOFT (filtre et tous les autres dangers) : fortement évité mais
//     franchissable si aucun autre chemin n'existe.

import 'package:latlong2/latlong.dart';

import '../../../core/models/alert_model.dart';

/// Rayon d'évitement par défaut d'un danger (mètres), cohérent avec
/// `SafePathEngine.dangerRadiusMeters` et `restrictionThresholdMeters`.
const double kDefaultDangerRadiusMeters = 25.0;

/// Poids (multiplicateur de coût) d'un danger « soft » : fortement évité
/// mais franchissable en dernier recours.
const double kSoftDangerWeight = 1e6;

/// Poids d'un danger « bloquant » (barrage) : quasi-infini → infranchissable.
const double kBlockingDangerWeight = 1e12;

/// Retourne le poids d'évitement à appliquer pour un type d'alerte.
///
/// Seul le `barrage` est « totalement infranchissable ». Les `filtre` et
/// tous les autres types restent évitables mais franchissables.
double dangerWeightFor(AlertType type) =>
    type == AlertType.barrage ? kBlockingDangerWeight : kSoftDangerWeight;

/// Point de danger à éviter, avec coordonnées, rayon et poids.
class DangerPoint {
  const DangerPoint({
    required this.lat,
    required this.lon,
    this.radiusMeters = kDefaultDangerRadiusMeters,
    this.weight = kSoftDangerWeight,
  });

  /// Construit un [DangerPoint] depuis une [Alert], en dérivant la sévérité
  /// (poids) de son type.
  factory DangerPoint.fromAlert(Alert alert) => DangerPoint(
        lat: alert.latitude,
        lon: alert.longitude,
        radiusMeters: kDefaultDangerRadiusMeters,
        weight: dangerWeightFor(alert.type),
      );

  final double lat;
  final double lon;

  /// Rayon de la zone d'évitement (mètres).
  final double radiusMeters;

  /// Poids d'évitement (multiplicateur de coût).
  final double weight;

  LatLng get latLng => LatLng(lat, lon);

  /// `true` si ce danger est « infranchissable » (barrage).
  bool get isBlocking => weight >= kBlockingDangerWeight;

  @override
  String toString() =>
      'DangerPoint($lat, $lon, r=${radiusMeters}m, w=$weight)';
}
