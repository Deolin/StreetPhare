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
// [1] Couleurs contrastées pour la carte sombre (lisibilité forte luminosité)
/// Couleur de la Route Safe en mode clair (vert vif StreetPhare).
const Color _kRouteColorLight = StreetPhareTheme.primary;

/// Couleur de la Route Safe en mode sombre : jaune néon haute visibilité,
/// lisible même en plein soleil sur fond de carte sombre CartoDB.
const Color _kRouteColorDark = Color(0xFFFFEB3B); // Jaune Material 500

/// Largeur renforcée du trait en mode sombre pour la lisibilité.
const double _kStrokeWidthDark = 6.0;
const double _kStrokeWidthLight = 4.5;

class SafeRouteLayer extends StatelessWidget {
  const SafeRouteLayer({
    super.key,
    required this.routePoints,
    this.arrowStepCount = 6,
    this.routeColor,         // null = auto-détection selon le thème
    this.strokeWidth,        // null = auto selon le thème
    this.isDarkMap = false,  // injecté depuis MapScreen
  });

  /// Liste ordonnée des coordonnées de la Route Safe.
  final List<LatLng> routePoints;

  /// Nombre de points entre chaque flèche directionnelle.
  final int arrowStepCount;

  /// Couleur du tracé (null = auto selon isDarkMap).
  final Color? routeColor;

  /// Épaisseur du trait (null = auto selon isDarkMap).
  final double? strokeWidth;

  /// Si true, utilise les couleurs haute-visibilité pour la carte sombre.
  final bool isDarkMap;

  /// Résout la couleur effective selon le thème.
  Color get _effectiveColor =>
      routeColor ?? (isDarkMap ? _kRouteColorDark : _kRouteColorLight);

  /// Résout l'épaisseur effective selon le thème.
  double get _effectiveStroke =>
      strokeWidth ?? (isDarkMap ? _kStrokeWidthDark : _kStrokeWidthLight);

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
            color: _effectiveColor,
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
          color: _effectiveColor,
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
            // Halo contrasté : noir en clair, blanc en sombre pour isolation
            Polyline(
              points: routePoints,
              color: isDarkMap
                  ? Colors.black.withValues(alpha: 0.70)
                  : Colors.black.withValues(alpha: 0.20),
              strokeWidth: _effectiveStroke + 4.0,
            ),
            // Trait principal haute-visibilité
            Polyline(
              points: routePoints,
              color: _effectiveColor,
              strokeWidth: _effectiveStroke,
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
