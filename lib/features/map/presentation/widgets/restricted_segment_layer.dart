// lib/features/map/presentation/widgets/restricted_segment_layer.dart
//
// Couche de surbrillance des PORTIONS RESTREINTES d'un itinéraire
// (sens interdit / zone piétonne / barrage / zone filtrée / nasse).
//
// En mode voiture/urgence, ces portions sont tracées en rouge pointillé
// au-dessus de la route pour avertir visuellement le conducteur.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../../core/theme/streetphare_theme.dart';
import '../../../routing/domain/models/route_result.dart';

/// Couche carte affichant les portions restreintes en rouge pointillé.
class RestrictedSegmentLayer extends StatelessWidget {
  const RestrictedSegmentLayer({
    super.key,
    required this.segments,
  });

  /// Portions restreintes à mettre en surbrillance.
  final List<RestrictedSegment> segments;

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];
    for (final seg in segments) {
      if (seg.points.length < 2) continue;
      // Halo sombre pour isoler le trait rouge du fond de carte.
      polylines.add(
        Polyline(
          points: seg.points,
          color: Colors.black.withValues(alpha: 0.55),
          strokeWidth: 9,
        ),
      );
      polylines.add(
        Polyline(
          points: seg.points,
          color: StreetPhareTheme.danger,
          strokeWidth: 6,
          pattern: StrokePattern.dashed(segments: const [8.0, 6.0]),
        ),
      );
    }

    if (polylines.isEmpty) return const SizedBox.shrink();
    return PolylineLayer(polylines: polylines);
  }
}
