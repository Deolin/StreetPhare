// lib/features/routing/presentation/route_result_sheet.dart
//
// Feuille d'ancrage présentant le(s) itinéraire(s) calculé(s) par
// le moteur "Safe Path".
//
// Comportement UI :
//   * Affiche d'abord le chemin RECOMMANDÉ (le moins risqué) avec
//     un bouton "Accepter" et un bouton "Voir les alternatives".
//   * Si l'utilisateur clique sur "Voir les alternatives",
//     déplie la liste des 2 autres itinéraires calculés en
//     parallèle, que l'utilisateur peut comparer et choisir.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/route_result.dart';

class RouteResultSheet extends StatefulWidget {
  const RouteResultSheet({super.key, required this.routes});
  final List<RouteResult> routes;

  static Future<RouteResult?> show(
    BuildContext context, {
    required List<RouteResult> routes,
  }) {
    return showModalBottomSheet<RouteResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RouteResultSheet(routes: routes),
    );
  }

  @override
  State<RouteResultSheet> createState() => _RouteResultSheetState();
}

class _RouteResultSheetState extends State<RouteResultSheet> {
  bool _showAlternatives = false;
  RouteResult? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.routes.isNotEmpty) _selected = widget.routes.first;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.routes.isEmpty) {
      return _wrap(
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Aucun itinéraire trouvé.\n'
            'Les blocages actifs empêchent tout passage, ou '
            'la position est trop proche de la destination.',
            textAlign: TextAlign.center,
            style: TextStyle(color: StreetPhareTheme.textSecondary),
          ),
        ),
      );
    }
    final recommended = widget.routes.first;
    final alternatives = widget.routes.skip(1).toList();

    return _wrap(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.shield,
                    color: StreetPhareTheme.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Route Safe',
                  style: TextStyle(
                    color: StreetPhareTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: StreetPhareTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MiniRouteMap(route: _selected ?? recommended),
            const SizedBox(height: 12),
            _RouteTile(
              route: recommended,
              isSelected: _selected?.id == recommended.id,
              onTap: () => setState(() => _selected = recommended),
              badge: 'Recommandé',
            ),
            const SizedBox(height: 8),
            if (alternatives.isNotEmpty && !_showAlternatives)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showAlternatives = true),
                icon: const Icon(Icons.alt_route,
                    color: StreetPhareTheme.primary),
                label: Text(
                  'Voir les alternatives (${alternatives.length})',
                  style: const TextStyle(color: StreetPhareTheme.primary),
                ),
              ),
            if (_showAlternatives)
              ...alternatives.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _RouteTile(
                    route: r,
                    isSelected: _selected?.id == r.id,
                    onTap: () => setState(() => _selected = r),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_selected ?? recommended),
                icon: const Icon(Icons.check, color: Colors.black),
                label: Text(
                  'Accepter : ${(_selected ?? recommended).distanceLabel}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StreetPhareTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrap(Widget child) {
    return Container(
      decoration: const BoxDecoration(
        color: StreetPhareTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final RouteResult route;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? StreetPhareTheme.primary.withValues(alpha: 0.15)
                : StreetPhareTheme.darkSurfaceVariant
                    .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? StreetPhareTheme.primary
                  : StreetPhareTheme.textSecondary.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? StreetPhareTheme.primary
                    : StreetPhareTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            route.label.isEmpty
                                ? 'Itinéraire'
                                : route.label,
                            style: const TextStyle(
                              color: StreetPhareTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: StreetPhareTheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${route.distanceLabel} • risque ${route.totalRiskScore.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: StreetPhareTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniRouteMap extends StatelessWidget {
  const _MiniRouteMap({required this.route});
  final RouteResult route;

  static LatLng _center(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(48.8566, 2.3522);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  @override
  Widget build(BuildContext context) {
    final pts = route.points;
    return SizedBox(
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: _center(pts),
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.streetphare.app',
            ),
            if (pts.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: pts,
                    color: StreetPhareTheme.primary,
                    strokeWidth: 4,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (pts.isNotEmpty)
                  Marker(
                    point: pts.first,
                    width: 16,
                    height: 16,
                    child: const Icon(Icons.trip_origin,
                        color: StreetPhareTheme.primary, size: 16),
                  ),
                if (pts.length >= 2)
                  Marker(
                    point: pts.last,
                    width: 16,
                    height: 16,
                    child: const Icon(Icons.location_on,
                        color: StreetPhareTheme.accent, size: 16),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
