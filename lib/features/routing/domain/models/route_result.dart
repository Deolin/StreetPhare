// lib/features/routing/domain/models/route_result.dart
//
// Modèle de données décrivant un itinéraire calculé par le moteur
// de routage "Safe Path" de StreetPhare.
//
// Un itinéraire est une POLYLINE (suite ordonnée de LatLng) tracée
// sur la carte entre un point de départ A et un point d'arrivée B.
// Il porte également un score de risque agrégé (somme des poids
// d'arêtes traversées) pour permettre à l'UI de comparer plusieurs
// alternatives et de recommander la moins dangereuse.

import 'package:latlong2/latlong.dart';

/// Un point d'intérêt (POI) rencontré le long d'un itinéraire
/// (point de rassemblement, point d'eau, sortie de métro, etc.).
class RoutePoi {
  const RoutePoi({
    required this.label,
    required this.position,
    this.icon = 'flag',
  });

  final String label;
  final LatLng position;
  final String icon;
}

/// Une portion restreinte d'un itinéraire (sens interdit, zone piétonne,
/// barrage, zone filtrée, nasse, etc.) que le conducteur devrait éviter.
///
/// En mode voiture/urgence, ces portions sont mises en surbrillance sur la
/// carte et déclenchent un avertissement visuel + sonore.
class RestrictedSegment {
  const RestrictedSegment({
    required this.points,
    required this.reason,
  });

  /// Suite ordonnée de points formant la sous-polyline restreinte.
  final List<LatLng> points;

  /// Raison lisible : "Barrage", "Zone filtrée", "Nasse", etc.
  final String reason;
}

/// Un résultat de calcul d'itinéraire.
class RouteResult {
  const RouteResult({
    required this.id,
    required this.points,
    required this.totalDistanceMeters,
    required this.totalRiskScore,
    required this.pois,
    this.duration,
    this.label = '',
    this.restrictedSegments = const [],
  });

  /// Identifiant unique de l'itinéraire (utilisé pour les
  /// distinctions dans la liste d'alternatives).
  final String id;

  /// Suite ordonnée de coordonnées formant la polyline.
  final List<LatLng> points;

  /// Distance cumulée en mètres.
  final double totalDistanceMeters;

  /// Score de risque agrégé (somme des poids d'arêtes).
  /// Plus il est BAS, plus l'itinéraire est "safe".
  final double totalRiskScore;

  /// Points d'intérêt traversés.
  final List<RoutePoi> pois;

  /// Durée réelle du trajet fournie par le moteur de routage (ex: OTP pour
  /// les transports en commun). `null` = non fournie → on retombe sur une
  /// estimation à pied (`estimatedWalkDuration`).
  final Duration? duration;

  /// Libellé optionnel (ex: "Chemin rapide", "Contourne le centre").
  final String label;

  /// Portions restreintes identifiées le long de l'itinéraire
  /// (sens interdit / zone piétonne / barrage…). Vide si aucune.
  final List<RestrictedSegment> restrictedSegments;

  /// Vrai si l'itinéraire franchit au moins une portion restreinte.
  bool get hasViolations => restrictedSegments.isNotEmpty;

  /// Durée estimée à pied (3 km/h ≈ 0.83 m/s).
  Duration get estimatedWalkDuration {
    final secs = (totalDistanceMeters / 0.83).round();
    return Duration(seconds: secs);
  }

  /// Durée effective : la durée réelle du moteur si fournie (OTP/TC),
  /// sinon l'estimation à pied.
  Duration get effectiveDuration => duration ?? estimatedWalkDuration;

  /// Qualifie la durée affichée : "à pied" quand c'est une estimation de
  /// marche, vide quand la durée est fournie par un moteur (ex: TC via OTP).
  String get durationQualifier => duration == null ? 'à pied' : '';

  /// Format lisible de la distance : "1.2 km" / "850 m".
  String get distanceLabel {
    if (totalDistanceMeters < 1000) {
      return '${totalDistanceMeters.round()} m';
    }
    return '${(totalDistanceMeters / 1000).toStringAsFixed(2)} km';
  }

  /// Format lisible de la durée estimée : "12 min", "1h05".
  String get durationLabel {
    final d = effectiveDuration;
    if (d.inMinutes < 1) return '1 min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  /// Copie de l'itinéraire avec des champs mis à jour.
  RouteResult copyWith({
    double? totalRiskScore,
    List<RestrictedSegment>? restrictedSegments,
    Duration? duration,
  }) {
    return RouteResult(
      id: id,
      points: points,
      totalDistanceMeters: totalDistanceMeters,
      totalRiskScore: totalRiskScore ?? this.totalRiskScore,
      pois: pois,
      duration: duration ?? this.duration,
      label: label,
      restrictedSegments: restrictedSegments ?? this.restrictedSegments,
    );
  }
}
