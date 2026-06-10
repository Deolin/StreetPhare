// lib/features/map/presentation/widgets/safe_route_layer.dart
//
// Couche d'affichage de la "Route Safe" directionnelle sur FlutterMap.
//
// Fonctionnalités :
//   1. Tracé de la polyline de l'itinéraire safe (couleur primaire,
//      épaisseur renforcée, trait en pointillés).
//   2. Mini-flèches directionnelles (Icons.keyboard_arrow_up) orientées
//      selon le gisement (bearing) calculé entre les points successifs,
//      espacées régulièrement le long du tracé.
//   3. Marqueurs de départ (point d'origine) et d'arrivée (destination).
//
// Utilisation dans FlutterMap :
//   ```dart
//   FlutterMap(
//     children: [
//       TileLayer(...),
//       if (_safeRoutePoints != null)
//         SafeRouteLayer(routePoints: _safeRoutePoints!),
//       MarkerLayer(...),
//     ],
//   )
//   ```

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/streetphare_theme.dart';

/// Couche carte affichant un itinéraire "Route Safe" avec :
///   - une polyline stylisée
///   - des flèches directionnelles espacées régulièrement
///   - un marqueur de départ et un marqueur d'arrivée
class SafeRouteLayer extends StatelessWidget {
  const SafeRouteLayer({
    super.key,
    required this.routePoints,
    this.arrowStepCount = 6,
    this.routeColor = StreetPhareTheme.primary,
    this.strokeWidth = 4.5,
  });

  /// Liste ordonnée des coordonnées de la Route Safe.
  final List<LatLng> routePoints;

  /// Nombre de points entre chaque flèche directionnelle.
  /// Une valeur de 6 signifie 1 flèche tous les 6 points du tableau.
  final int arrowStepCount;

  /// Couleur du tracé (et des flèches).
  final Color routeColor;

  /// Épaisseur du trait de la polyline.
  final double strokeWidth;

  // --------------------------------------------------------------------------
  // Calcul du gisement (bearing) entre deux points GPS
  // --------------------------------------------------------------------------

  /// Retourne le bearing en RADIANS entre [from] et [to]
  /// (0 = Nord, π/2 = Est, sens horaire).
  static double _bearingRad(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final dLng = (to.longitude - from.longitude) * math.pi / 180.0;

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    return math.atan2(y, x); // radians, peut être négatif
  }

  // --------------------------------------------------------------------------
  // Construction des marqueurs de flèches directionnelles
  // --------------------------------------------------------------------------

  List<Marker> _buildArrowMarkers() {
    final n = routePoints.length;
    if (n < 2) return const [];

    final markers = <Marker>[];
    // On démarre à arrowStepCount pour avoir un segment from→to valide,
    // et on s'arrête avant le dernier point pour éviter le marqueur
    // d'arrivée (géré séparément).
    for (int i = arrowStepCount; i < n - 1; i += arrowStepCount) {
      final bearing = _bearingRad(routePoints[i - 1], routePoints[i]);
      markers.add(
        Marker(
          point: routePoints[i],
          width: 28,
          height: 28,
          child: _DirectionArrow(
            bearingRad: bearing,
            color: routeColor,
          ),
        ),
      );
    }
    return markers;
  }

  // --------------------------------------------------------------------------
  // Marqueurs de départ / arrivée
  // --------------------------------------------------------------------------

  List<Marker> _buildEndpointMarkers() {
    if (routePoints.isEmpty) return const [];

    final markers = <Marker>[
      // Départ
      Marker(
        point: routePoints.first,
        width: 32,
        height: 32,
        child: _EndpointDot(
          color: routeColor,
          icon: Icons.trip_origin,
          size: 20,
        ),
      ),
    ];

    if (routePoints.length >= 2) {
      // Arrivée
      markers.add(
        Marker(
          point: routePoints.last,
          width: 38,
          height: 38,
          child: _EndpointDot(
            color: StreetPhareTheme.accent,
            icon: Icons.location_on,
            size: 24,
          ),
        ),
      );
    }

    return markers;
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (routePoints.length < 2) return const SizedBox.shrink();

    final allMarkers = [
      ..._buildArrowMarkers(),
      ..._buildEndpointMarkers(),
    ];

    return Stack(
      children: [
        // ── Trait de la Route Safe ────────────────────────────────
        PolylineLayer(
          polylines: [
            // Trait de fond (halo sombre pour la lisibilité)
            Polyline(
              points: routePoints,
              color: Colors.black.withValues(alpha: 0.20),
              strokeWidth: strokeWidth + 3.0,
            ),
            // Trait principal coloré
            Polyline(
              points: routePoints,
              color: routeColor,
              strokeWidth: strokeWidth,
            ),
          ],
        ),

        // ── Flèches directionnelles + marqueurs de bornes ─────────
        MarkerLayer(markers: allMarkers),
      ],
    );
  }
}

// ============================================================================
// Widgets internes
// ============================================================================

/// Flèche directionnelle orientée selon le bearing calculé.
class _DirectionArrow extends StatelessWidget {
  const _DirectionArrow({
    required this.bearingRad,
    required this.color,
  });

  final double bearingRad;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: bearingRad,
      child: Icon(
        Icons.keyboard_arrow_up,
        color: color,
        size: 22,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// Marqueur de départ ou d'arrivée.
class _EndpointDot extends StatelessWidget {
  const _EndpointDot({
    required this.color,
    required this.icon,
    required this.size,
  });

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Icon(icon, color: color, size: size),
    );
  }
}
