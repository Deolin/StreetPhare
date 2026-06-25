// lib/features/routing/presentation/route_notifier.dart
//
// ValueNotifier thread-safe pour la polyline de l'itinéraire.
//
// Reçoit les positions recalées du MapMatcher (via Isolate) et
// notifie l'UI FlutterMap sans bloquer le thread principal.
//
// Utilisation :
// ```dart
// final notifier = RouteNotifier();
//
// // Dans le widget :
// ListenableBuilder(
//   listenable: notifier,
//   builder: (ctx, _) => PolylineLayer(
//     polylines: [Polyline(points: notifier.value)],
//   ),
// )
// ```

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Notifie l'UI des mises à jour de la polyline de l'itinéraire.
///
/// Règles pour ne pas bloquer l'UI :
///   1. Toujours remplacer la liste, jamais la modifier in-place
///   2. Garder un nombre de points raisonnable (downsample à 1pt/10m)
///   3. Les mises à jour viennent d'un Isolate séparé
class RouteNotifier extends ValueNotifier<List<LatLng>> {
  RouteNotifier() : super(const []);

  /// Nombre maximum de points dans la polyline.
  /// Au-delà, on downsample pour garder l'UI fluide.
  static const int maxPoints = 2000;

  /// Distance minimum entre deux points consécutifs (mètres).
  /// En dessous, on ignore le nouveau point pour éviter le bruit.
  static const double minPointSpacingMeters = 3.0;

  /// Remplace complètement la polyline.
  void updateRoute(List<LatLng> newPoints) {
    final points = newPoints.length > maxPoints
        ? _downsample(newPoints, maxPoints)
        : newPoints;
    value = points;
  }

  /// Ajoute un point à la fin de la polyline.
  void appendPoint(LatLng point) {
    final current = value;
    // Vérifie l'espacement minimum.
    if (current.isNotEmpty) {
      final last = current.last;
      final dist = _haversine(last, point);
      if (dist < minPointSpacingMeters) return;
    }

    final updated = [...current, point];
    if (updated.length > maxPoints) {
      // Supprime le premier point pour garder la taille max.
      updated.removeAt(0);
    }
    value = updated;
  }

  /// Vide la polyline.
  void clear() {
    value = const [];
  }

  /// Downsample une liste de points à [targetCount] points maximum.
  static List<LatLng> _downsample(List<LatLng> points, int targetCount) {
    if (points.length <= targetCount) return points;
    final step = points.length / targetCount;
    final result = <LatLng>[];
    for (double i = 0; i < points.length; i += step) {
      result.add(points[i.floor()]);
    }
    if (result.length > targetCount) {
      result.removeRange(targetCount, result.length);
    }
    // Assure qu'on a au moins le dernier point.
    if (result.last != points.last) {
      result.add(points.last);
    }
    return result;
  }

  static double _haversine(LatLng a, LatLng b) {
    const double r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * 3.141592653589793 / 180.0;
    final dLon = (b.longitude - a.longitude) * 3.141592653589793 / 180.0;
    final sinDLat = dLat / 2;
    final sinDLon = dLon / 2;
    final aVal = sinDLat * sinDLat +
        _fastCos(a.latitude * 3.141592653589793 / 180.0) *
            _fastCos(b.latitude * 3.141592653589793 / 180.0) *
            sinDLon *
            sinDLon;
    return r * 2 * _fastAtan2(_fastSqrt(aVal), _fastSqrt(1 - aVal));
  }

  static double _fastCos(double x) {
    final x2 = x * x;
    return 1.0 - x2 / 2.0 + x2 * x2 / 24.0;
  }

  static double _fastSqrt(double x) {
    if (x <= 0) return 0;
    double guess = x;
    for (int i = 0; i < 3; i++) {
      guess = (guess + x / guess) * 0.5;
    }
    return guess;
  }

  static double _fastAtan2(double y, double x) {
    if (x == 0) {
      if (y > 0) return 1.5707963267948966;
      if (y < 0) return -1.5707963267948966;
      return 0;
    }
    final z = y / x;
    if (z.abs() < 1) {
      return z / (1 + 0.28 * z * z);
    }
    return 1.5707963267948966 - z / (z * z + 0.28);
  }
}
