// lib/features/events/domain/models/event_model.dart
//
// Modèle de données d'un ÉVÉNEMENT "StreetPhare" (manifestation
// ou autre rassemblement pré-organisé) chargé via un code
// d'invitation chiffré ou un QR Code.
//
// Champs clés :
//   * `code`          : identifiant public saisi par l'utilisateur.
//   * `title`         : titre lisible de l'événement.
//   * `startAt`       : DateTime UTC du début officiel de l'événement.
//   * `visibleAt`     : DateTime UTC à partir de laquelle le trajet
//                      et les points d'intérêt peuvent être dessinés.
//   * `routeGeoJson`  : polyline encodée du trajet (format GeoJSON
//                      simplifié : [[lng,lat],[lng,lat],...]).
//   * `waypoints`     : étapes ordonnées avec heure prévue (points
//                      de rassemblement "juste-à-temps" dynamiques).
//   * `pois`          : points d'intérêt officiels (compat. legacy).
//   * `destination`   : point d'arrivée B.

import 'package:latlong2/latlong.dart';

// ============================================================================
// EventWaypoint — Étape planifiée avec heure de passage prévue
// ============================================================================

/// Une étape planifiée du trajet de l'événement.
///
/// Logique "juste-à-temps" : une étape est considérée comme PASSÉE si :
///   1. `DateTime.now()` dépasse `scheduledAt` de plus de 5 minutes, OU
///   2. La position GPS de l'utilisateur est à moins de 30 mètres du point.
///
/// Dès qu'une étape est passée, la suivante est automatiquement révélée.
class EventWaypoint {
  const EventWaypoint({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.scheduledAt,
  });

  final String label;
  final double latitude;
  final double longitude;

  /// Heure prévue de passage (UTC).
  final DateTime scheduledAt;

  LatLng get position => LatLng(latitude, longitude);

  /// Retourne `true` si cette étape est considérée comme PASSÉE.
  bool isPassed(DateTime now, LatLng? userPos) {
    // Critère 1 : heure dépassée de plus de 5 minutes.
    final timePassed = now.toUtc().isAfter(
      scheduledAt.toUtc().add(const Duration(minutes: 5)),
    );
    if (timePassed) return true;

    // Critère 2 : position GPS à moins de 30 mètres.
    if (userPos != null) {
      const d = Distance();
      final meters = d.as(LengthUnit.Meter, userPos, position);
      if (meters < 30) return true;
    }
    return false;
  }

  /// Heure locale formatée "HHhMM" pour l'affichage sur la carte.
  String get formattedTime {
    final local = scheduledAt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${h}h$m';
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      };

  factory EventWaypoint.fromJson(Map<String, dynamic> json) {
    return EventWaypoint(
      label: json['label'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      scheduledAt:
          DateTime.parse(json['scheduledAt'] as String).toUtc(),
    );
  }
}

// ============================================================================
// EventPoi — Point d'intérêt (rétrocompatibilité)
// ============================================================================

/// Un point d'intérêt (POI) officiel de l'événement.
class EventPoi {
  const EventPoi({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.icon = 'flag',
  });

  final String label;
  final double latitude;
  final double longitude;
  final String icon;

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'icon': icon,
      };

  factory EventPoi.fromJson(Map<String, dynamic> json) {
    return EventPoi(
      label: json['label'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      icon: (json['icon'] as String?) ?? 'flag',
    );
  }
}

// ============================================================================
// EventModel — Événement complet
// ============================================================================

/// Un événement chargé via code d'invitation ou QR Code.
class EventModel {
  const EventModel({
    required this.code,
    required this.title,
    required this.startAt,
    required this.visibleAt,
    required this.routeGeoJson,
    required this.pois,
    required this.destinationLatitude,
    required this.destinationLongitude,
    this.waypoints = const [],
  });

  /// Code d'invitation (ex: "MANIF-123").
  final String code;

  /// Titre lisible.
  final String title;

  /// Date/heure officielle du début.
  final DateTime startAt;

  /// Date/heure à partir de laquelle l'itinéraire devient visible.
  final DateTime visibleAt;

  /// Polyline du trajet complet au format GeoJSON LineString.
  /// Format : `[[lng,lat],[lng,lat],...]`.
  final String routeGeoJson;

  /// Étapes ordonnées avec heure prévue (logique juste-à-temps dynamique).
  final List<EventWaypoint> waypoints;

  /// Points d'intérêt officiels (compat. legacy).
  final List<EventPoi> pois;

  /// Coordonnées du point d'arrivée B.
  final double destinationLatitude;
  final double destinationLongitude;

  LatLng get destination =>
      LatLng(destinationLatitude, destinationLongitude);

  /// Indique si l'itinéraire est visible à l'instant présent.
  bool isRouteVisible([DateTime? now]) {
    final reference = now ?? DateTime.now().toUtc();
    return !reference.isBefore(visibleAt.toUtc());
  }

  /// Durée restante avant la révélation de l'itinéraire.
  Duration remainingBeforeReveal([DateTime? now]) {
    final reference = now ?? DateTime.now().toUtc();
    if (isRouteVisible(reference)) return Duration.zero;
    return visibleAt.toUtc().difference(reference);
  }

  // --------------------------------------------------------------------------
  // Logique "juste-à-temps" dynamique par étapes
  // --------------------------------------------------------------------------

  /// Retourne l'index de la première étape NON encore passée.
  /// Retourne `waypoints.length` si toutes les étapes sont passées.
  int activeStepIndex({DateTime? now, LatLng? userPos}) {
    final reference = now ?? DateTime.now().toUtc();
    for (int i = 0; i < waypoints.length; i++) {
      if (!waypoints[i].isPassed(reference, userPos)) return i;
    }
    return waypoints.length;
  }

  /// Retourne les points de la polyline pour le segment [stepIndex].
  ///
  /// Trouve le point de route le plus proche de chaque waypoint et
  /// retourne la tranche de `allPoints` entre waypoint[stepIndex]
  /// et waypoint[stepIndex+1] (ou la fin si c'est le dernier).
  List<LatLng> getSegmentPoints(int stepIndex, List<LatLng> allPoints) {
    if (waypoints.isEmpty || allPoints.isEmpty) return allPoints;
    if (stepIndex >= waypoints.length) return const [];

    final fromPos = waypoints[stepIndex].position;
    final toPos = stepIndex + 1 < waypoints.length
        ? waypoints[stepIndex + 1].position
        : null;

    final fromIdx = _nearestPointIndex(allPoints, fromPos);
    final toIdx = toPos != null
        ? _nearestPointIndex(allPoints, toPos)
        : allPoints.length - 1;

    if (fromIdx >= toIdx) {
      // Segment d'un seul point : retourne au moins 2 points pour
      // que PolylineLayer puisse tracer quelque chose.
      final end = (fromIdx + 1).clamp(0, allPoints.length - 1);
      return allPoints.sublist(fromIdx, end + 1);
    }
    return allPoints.sublist(fromIdx, toIdx + 1);
  }

  /// Retourne l'index du point de `points` le plus proche de `target`.
  int _nearestPointIndex(List<LatLng> points, LatLng target) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < points.length; i++) {
      final dLat = points[i].latitude - target.latitude;
      final dLng = points[i].longitude - target.longitude;
      final dist = dLat * dLat + dLng * dLng;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  // --------------------------------------------------------------------------
  // Décodage GeoJSON
  // --------------------------------------------------------------------------

  /// Décode la polyline GeoJSON `[[lng,lat],...]` en `List<LatLng>`.
  List<LatLng> decodeRoute() {
    final coords = <LatLng>[];
    final regex = RegExp(r'\[([^\]]+)\]');
    for (final match in regex.allMatches(routeGeoJson)) {
      final parts = match
          .group(1)!
          .split(',')
          .map((s) => double.tryParse(s.trim()))
          .whereType<double>()
          .toList();
      if (parts.length >= 2) {
        // GeoJSON : [lng, lat]
        coords.add(LatLng(parts[1], parts[0]));
      }
    }
    return coords;
  }

  // --------------------------------------------------------------------------
  // Sérialisation
  // --------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'startAt': startAt.toUtc().toIso8601String(),
        'visibleAt': visibleAt.toUtc().toIso8601String(),
        'route': routeGeoJson,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'pois': pois.map((p) => p.toJson()).toList(),
        'destLat': destinationLatitude,
        'destLng': destinationLongitude,
      };

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      code: json['code'] as String,
      title: json['title'] as String,
      startAt: DateTime.parse(json['startAt'] as String).toUtc(),
      visibleAt: DateTime.parse(json['visibleAt'] as String).toUtc(),
      routeGeoJson: json['route'] as String,
      waypoints: ((json['waypoints'] as List?) ?? const [])
          .map((w) =>
              EventWaypoint.fromJson(w as Map<String, dynamic>))
          .toList(),
      pois: ((json['pois'] as List?) ?? const [])
          .map((p) => EventPoi.fromJson(p as Map<String, dynamic>))
          .toList(),
      destinationLatitude: (json['destLat'] as num).toDouble(),
      destinationLongitude: (json['destLng'] as num).toDouble(),
    );
  }
}
