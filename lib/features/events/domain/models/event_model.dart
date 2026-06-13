// lib/features/events/domain/models/event_model.dart
//
// Modèle de données d'un ÉVÉNEMENT "StreetPhare" (rassemblement
// public ou autre événement pré-organisé) chargé via un code
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
//   * `careCenters`   : centres de soins / street-medics (NOUVEAU).
//   * `exitPoints`    : zones d'évacuation / sorties de secours (NOUVEAU).
//   * `safezones`     : zones de repli identifiées (NOUVEAU).
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
// EventCareCenter — Centre de soins / street-medics (NOUVEAU)
// ============================================================================

/// Un centre de soins de rue (street-medics, secours de proximité)
/// défini dans le JSON de l'événement. Sert de point de repli
/// pour l'algorithme de routage "Route Safe".
class EventCareCenter {
  const EventCareCenter({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.contact = '',
    this.notes = '',
  });

  final String label;
  final double latitude;
  final double longitude;

  /// Numéro de téléphone ou canal radio (optionnel).
  final String contact;

  /// Notes complémentaires (spécialisation, capacité, etc.).
  final String notes;

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'contact': contact,
        'notes': notes,
      };

  factory EventCareCenter.fromJson(Map<String, dynamic> json) {
    return EventCareCenter(
      label: json['label'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      contact: (json['contact'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
    );
  }
}

// ============================================================================
// EventExitPoint — Point de sortie / zone d'évacuation (NOUVEAU)
// ============================================================================

/// Un point de sortie ou zone d'évacuation défini dans le JSON
/// de l'événement. Utilisé comme destination de repli par
/// l'algorithme de routage en cas de blocage.
class EventExitPoint {
  const EventExitPoint({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.direction = '',
  });

  final String label;
  final double latitude;
  final double longitude;

  /// Direction ou indication textuelle vers la sortie.
  final String direction;

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'direction': direction,
      };

  factory EventExitPoint.fromJson(Map<String, dynamic> json) {
    return EventExitPoint(
      label: json['label'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      direction: (json['direction'] as String?) ?? '',
    );
  }
}

// ============================================================================
// EventSafeZone — Zone de repli sûre (NOUVEAU)
// ============================================================================

/// Une zone de repli identifiée dans le JSON de l'événement.
/// Sert aussi de destination de secours pour l'algorithme
/// de routage ("failover").
class EventSafeZone {
  const EventSafeZone({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.radius = 50.0,
  });

  final String label;
  final double latitude;
  final double longitude;

  /// Rayon de la zone sûre en mètres.
  final double radius;

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': latitude,
        'lng': longitude,
        'radius': radius,
      };

  factory EventSafeZone.fromJson(Map<String, dynamic> json) {
    return EventSafeZone(
      label: json['label'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      radius: (json['radius'] as num?)?.toDouble() ?? 50.0,
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
    this.careCenters = const [],
    this.exitPoints = const [],
    this.safeZones = const [],
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

  /// Centres de soins de rue / street-medics (NOUVEAU).
  final List<EventCareCenter> careCenters;

  /// Points de sortie / zones d'évacuation (NOUVEAU).
  final List<EventExitPoint> exitPoints;

  /// Zones de repli sûres (NOUVEAU).
  final List<EventSafeZone> safeZones;

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

  // --------------------------------------------------------------------------
  // Utilitaires : cherche le point le plus proche d'une position
  // --------------------------------------------------------------------------

  /// Retourne le centre de soins le plus proche de [userPos].
  /// Retourne `null` si la liste est vide.
  EventCareCenter? nearestCareCenter(LatLng userPos) {
    if (careCenters.isEmpty) return null;
    const d = Distance();
    EventCareCenter? best;
    double bestDist = double.infinity;
    for (final c in careCenters) {
      final dist = d.as(LengthUnit.Meter, userPos, c.position);
      if (dist < bestDist) {
        bestDist = dist;
        best = c;
      }
    }
    return best;
  }

  /// Retourne le point de sortie le plus proche de [userPos].
  /// Retourne `null` si la liste est vide.
  EventExitPoint? nearestExitPoint(LatLng userPos) {
    if (exitPoints.isEmpty) return null;
    const d = Distance();
    EventExitPoint? best;
    double bestDist = double.infinity;
    for (final e in exitPoints) {
      final dist = d.as(LengthUnit.Meter, userPos, e.position);
      if (dist < bestDist) {
        bestDist = dist;
        best = e;
      }
    }
    return best;
  }

  /// Retourne la zone safe la plus proche de [userPos].
  /// Retourne `null` si la liste est vide.
  EventSafeZone? nearestSafeZone(LatLng userPos) {
    if (safeZones.isEmpty) return null;
    const d = Distance();
    EventSafeZone? best;
    double bestDist = double.infinity;
    for (final z in safeZones) {
      final dist = d.as(LengthUnit.Meter, userPos, z.position);
      if (dist < bestDist) {
        bestDist = dist;
        best = z;
      }
    }
    return best;
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
        'careCenters': careCenters.map((c) => c.toJson()).toList(),
        'exitPoints': exitPoints.map((e) => e.toJson()).toList(),
        'safeZones': safeZones.map((z) => z.toJson()).toList(),
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
      careCenters: ((json['careCenters'] as List?) ?? const [])
          .map((c) => EventCareCenter.fromJson(c as Map<String, dynamic>))
          .toList(),
      exitPoints: ((json['exitPoints'] as List?) ?? const [])
          .map((e) => EventExitPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      safeZones: ((json['safeZones'] as List?) ?? const [])
          .map((z) => EventSafeZone.fromJson(z as Map<String, dynamic>))
          .toList(),
      destinationLatitude: (json['destLat'] as num).toDouble(),
      destinationLongitude: (json['destLng'] as num).toDouble(),
    );
  }
}
