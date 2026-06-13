// lib/features/routing/presentation/route_result_sheet.dart
//
// Feuille d'ancrage présentant le(s) itinéraire(s) calculé(s) par
// le moteur "Safe Path".
//
// Comportement UI v2.1 (Juste-à-Temps / Lazy Loading) :
//   * Affiche UNIQUEMENT le chemin RECOMMANDÉ dès le premier calcul.
//   * Un bouton "Routes alternatives" est présent MAIS les alternatives
//     ne sont calculées QUE lorsque l'utilisateur appuie sur ce bouton.
//   * Pendant le calcul des alternatives : overlay de chargement.
//   * Les alternatives calculées remplacent le bouton et affichent
//     la liste des 2 autres itinéraires.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/route_result.dart';
import '../infrastructure/osmand_routing_service.dart';
import 'widgets/route_calculation_overlay.dart';

/// Callback asynchrone pour charger les alternatives à la demande.
typedef AlternativesLoader = Future<List<RouteResult>> Function();

class RouteResultSheet extends StatefulWidget {
  const RouteResultSheet({
    super.key,
    required this.routes,
    this.onRequestAlternatives,
  });

  /// Liste des itinéraires (le premier = recommandé, les suivants = alternatives
  /// pré-calculées). Si [onRequestAlternatives] est fourni, les alternatives
  /// ne sont chargées que sur demande (JIT).
  final List<RouteResult> routes;

  /// Callback appelé quand l'utilisateur demande les alternatives.
  /// Si null, les alternatives de [routes] sont affichées directement.
  final AlternativesLoader? onRequestAlternatives;

  /// Affiche la feuille d'ancrage modale.
  ///
  /// [routes] : itinéraires pré-calculés (ou [primary only]).
  /// [onRequestAlternatives] : callback JIT pour les alternatives.
  static Future<RouteResult?> show(
    BuildContext context, {
    required List<RouteResult> routes,
    AlternativesLoader? onRequestAlternatives,
  }) {
    return showModalBottomSheet<RouteResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RouteResultSheet(
        routes: routes,
        onRequestAlternatives: onRequestAlternatives,
      ),
    );
  }

  @override
  State<RouteResultSheet> createState() => _RouteResultSheetState();
}

class _RouteResultSheetState extends State<RouteResultSheet> {
  bool _showAlternatives = false;
  bool _loadingAlternatives = false;
  RouteResult? _selected;
  List<RouteResult> _alternatives = const [];

  @override
  void initState() {
    super.initState();
    if (widget.routes.isNotEmpty) _selected = widget.routes.first;
    // Si des alternatives sont déjà dans routes (pas de JIT), on les stocke.
    if (widget.onRequestAlternatives == null && widget.routes.length > 1) {
      _alternatives = widget.routes.skip(1).toList();
    }
  }

  /// Charge les alternatives à la demande (JIT) lorsque l'utilisateur
  /// appuie sur "Routes alternatives".
  Future<void> _loadAlternatives() async {
    if (_loadingAlternatives) return;

    final loader = widget.onRequestAlternatives;
    if (loader == null) {
      // Alternatives déjà disponibles dans routes.
      setState(() {
        _alternatives = widget.routes.skip(1).toList();
        _showAlternatives = true;
      });
      return;
    }

    setState(() => _loadingAlternatives = true);

    try {
      final alts = await loader();
      if (!mounted) return;
      setState(() {
        _alternatives = alts;
        _showAlternatives = true;
        _loadingAlternatives = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingAlternatives = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de calculer les alternatives.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

    return _wrap(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── En-tête ─────────────────────────────────────────────────
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

            // ── Mini-carte ───────────────────────────────────────────────
            _MiniRouteMap(route: _selected ?? recommended),
            const SizedBox(height: 12),

            // ── Itinéraire recommandé ────────────────────────────────────
            _RouteTile(
              route: recommended,
              isSelected: _selected?.id == recommended.id,
              onTap: () => setState(() => _selected = recommended),
              badge: 'Recommandé',
            ),
            const SizedBox(height: 8),

            // ── Bouton "Routes alternatives" (JIT) ───────────────────────
            if (!_showAlternatives && !_loadingAlternatives) ...[
              // Affiche le bouton si des alternatives peuvent être chargées.
              if (widget.onRequestAlternatives != null ||
                  widget.routes.length > 1)
                TextButton.icon(
                  onPressed: _loadAlternatives,
                  icon: const Icon(Icons.alt_route,
                      color: StreetPhareTheme.primary),
                  label: const Text(
                    'Voir les routes alternatives',
                    style: TextStyle(color: StreetPhareTheme.primary),
                  ),
                ),
            ],

            // ── Indicateur de chargement des alternatives ────────────────
            if (_loadingAlternatives)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            StreetPhareTheme.primary),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Calcul des alternatives en cours…',
                      style: TextStyle(
                        color: StreetPhareTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Liste des alternatives chargées ──────────────────────────
            if (_showAlternatives)
              ..._alternatives.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _RouteTile(
                    route: r,
                    isSelected: _selected?.id == r.id,
                    onTap: () => setState(() => _selected = r),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // ── Bouton "Ouvrir dans OsmAnd" (Mode Externe) ───────────────
            _OsmAndLaunchButton(route: _selected ?? recommended),

            const SizedBox(height: 12),

            // ── Bouton "Accepter" ─────────────────────────────────────────
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
                : StreetPhareTheme.darkSurfaceVariant.withValues(alpha: 0.5),
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
                            route.label.isEmpty ? 'Itinéraire' : route.label,
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

// ══════════════════════════════════════════════════════════════════════════════
// _OsmAndLaunchButton — Bouton "Ouvrir dans OsmAnd"
// ══════════════════════════════════════════════════════════════════════════════

/// Bouton secondaire qui propose à l'utilisateur d'ouvrir l'itinéraire
/// directement dans OsmAnd (Mode Externe — navigation guidée vocale).
///
/// Si OsmAnd n'est pas installé, affiche [OsmAndNotInstalledDialog].
class _OsmAndLaunchButton extends StatelessWidget {
  const _OsmAndLaunchButton({required this.route});

  final RouteResult route;

  @override
  Widget build(BuildContext context) {
    if (route.points.isEmpty) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => _launch(context),
      icon: const Icon(Icons.map_outlined, size: 18),
      label: const Text('Ouvrir dans OsmAnd'),
      style: OutlinedButton.styleFrom(
        foregroundColor: StreetPhareTheme.primary,
        side: BorderSide(
          color: StreetPhareTheme.primary.withValues(alpha: 0.6),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final svc = OsmAndRoutingService.instance;
    final start = route.points.first;
    final end = route.points.last;
    final destName = route.label.isNotEmpty ? route.label : 'Destination';

    final success = await svc.launchExternalNavigation(
      start: start,
      end: end,
      destinationName: destName,
      onNotInstalled: () {
        if (context.mounted) {
          OsmAndNotInstalledDialog.show(
            context,
            onInstall: () => svc.openInstallPage(),
            onUseFallback: () {
              // Ferme la feuille et laisse le routage interne (déjà affiché).
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Itinéraire calculé via OSM — affiché sur la carte.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
          );
        }
      },
    );

    if (!success && context.mounted) {
      // Feedback si le lancement a échoué pour une autre raison
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de lancer OsmAnd.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _MiniRouteMap
// ══════════════════════════════════════════════════════════════════════════════

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
