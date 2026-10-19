// lib/features/routing/core/risk_score.dart
//
// Calcul du score de risque d'un itinéraire par rapport aux zones de danger.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Rayon d'influence d'un danger pour le score de risque (mètres).
const double kRiskRadiusMeters = 50.0;

/// Calcule le score de risque agrégé d'un itinéraire.
///
/// Pour chaque danger dont la polyligne passe à moins de [radiusMeters],
/// on ajoute une contribution décroissante : 1.0 si la route traverse le
/// centre, 0.0 au bord du rayon. Plus le score est ÉLEVÉ, plus la route
/// est dangereuse.
double computeRiskScore(
  List<LatLng> points,
  List<LatLng> dangers, {
  double radiusMeters = kRiskRadiusMeters,
}) {
  if (dangers.isEmpty || points.length < 2) return 0;
  double score = 0;
  for (final danger in dangers) {
    final dist = _minDistanceToPolyline(danger, points);
    if (dist <= radiusMeters) {
      score += 1.0 - (dist / radiusMeters);
    }
  }
  return score;
}

/// Distance minimale (mètres) entre un point et une polyligne.
double _minDistanceToPolyline(LatLng p, List<LatLng> polyline) {
  double best = double.infinity;
  for (int i = 0; i + 1 < polyline.length; i++) {
    final d = _distanceToSegment(p, polyline[i], polyline[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

/// Distance (mètres) entre un point et un segment [a, b].
double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
  // Projection équirectangulaire locale (précision suffisante sur < ~1 km).
  const metersPerDegLat = 111320.0;
  final cosLat = math.cos(a.latitude * math.pi / 180.0);
  final metersPerDegLon = metersPerDegLat * cosLat;

  final px = p.longitude * metersPerDegLon;
  final py = p.latitude * metersPerDegLat;
  final ax = a.longitude * metersPerDegLon;
  final ay = a.latitude * metersPerDegLat;
  final bx = b.longitude * metersPerDegLon;
  final by = b.latitude * metersPerDegLat;

  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) {
    return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  }

  double t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}
