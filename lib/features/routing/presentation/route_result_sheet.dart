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

import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/osm_tile_headers.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../../network/network_config.dart';
import '../../map/local_first_tile_provider.dart';
import '../domain/models/route_result.dart';
import '../infrastructure/osmand_routing_service.dart';
import 'widgets/route_calculation_overlay.dart';

/// Callback asynchrone pour charger les alternatives à la demande.
typedef AlternativesLoader = Future<List<RouteResult>> Function();

/// Mode de transport pour le calcul d'itinéraire.
enum TransportMode {
  pedestrian,
  car,
  transit;

  IconData get icon {
    switch (this) {
      case TransportMode.pedestrian:
        return Icons.directions_walk;
      case TransportMode.car:
        return Icons.directions_car;
      case TransportMode.transit:
        return Icons.directions_bus;
    }
  }

  String label(AppStrings s) {
    switch (this) {
      case TransportMode.pedestrian:
        return s.transportModePedestrian;
      case TransportMode.car:
        return s.transportModeCar;
      case TransportMode.transit:
        return s.transportModeTransit;
    }
  }
}

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
    final s = AppLocale.instance.strings;
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
        SnackBar(
          content: Text(s.routeAlternativesError),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocale.instance.strings;
    if (widget.routes.isEmpty) {
      return _wrap(
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            s.routeNotFound,
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
                Icon(Icons.shield, color: StreetPhareTheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  s.routeTitle,
                  style: TextStyle(
                    color: StreetPhareTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon:
                      Icon(Icons.close, color: StreetPhareTheme.textSecondary),
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
              strings: s,
              isSelected: _selected?.id == recommended.id,
              onTap: () => setState(() => _selected = recommended),
              badge: s.routeRecommended,
            ),
            const SizedBox(height: 8),

            // ── Bouton "Routes alternatives" (JIT) ───────────────────────
            if (!_showAlternatives && !_loadingAlternatives) ...[
              // Affiche le bouton si des alternatives peuvent être chargées.
              if (widget.onRequestAlternatives != null ||
                  widget.routes.length > 1)
                TextButton.icon(
                  onPressed: _loadAlternatives,
                  icon: Icon(Icons.alt_route, color: StreetPhareTheme.primary),
                  label: Text(
                    s.routeShowAlternatives,
                    style: TextStyle(color: StreetPhareTheme.primary),
                  ),
                ),
            ],

            // ── Indicateur de chargement des alternatives ────────────────
            if (_loadingAlternatives)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    const SizedBox(width: 10),
                    Text(
                      s.routeCalculatingAlternatives,
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
                    strings: s,
                    isSelected: _selected?.id == r.id,
                    onTap: () => setState(() => _selected = r),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // ── Bouton "Ouvrir dans OsmAnd" (Mode Externe) ───────────────
            _OsmAndLaunchButton(route: _selected ?? recommended, strings: s),

            const SizedBox(height: 12),

            // ── Bouton "Accepter" ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_selected ?? recommended),
                icon: const Icon(Icons.check, color: Colors.black),
                label: Text(
                  '${s.routeAccept} : ${(_selected ?? recommended).distanceLabel}'
                  ' \u2022 ${(_selected ?? recommended).durationLabel}',
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
      decoration: BoxDecoration(
        color: StreetPhareTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _RouteTile
// ══════════════════════════════════════════════════════════════════════════════

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.strings,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final RouteResult route;
  final AppStrings strings;
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
                            route.label.isEmpty
                                ? strings.routeItinerary
                                : route.label,
                            style: TextStyle(
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
                        if (route.totalRiskScore <= 0.001) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '0 risque',
                              style: TextStyle(
                                color: Colors.white,
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
                      '${route.distanceLabel} \u2022 '
                      '${route.durationLabel}${route.durationQualifier.isEmpty ? '' : ' ${route.durationQualifier}'} \u2022 '
                      '${strings.routeRisk} ${route.totalRiskScore.toStringAsFixed(0)}',
                      style: TextStyle(
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

class _OsmAndLaunchButton extends StatelessWidget {
  const _OsmAndLaunchButton({required this.route, required this.strings});

  final RouteResult route;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    // Structure stable (Offstage) pour éviter l'assertion framework
    // « !semantics.parentDataDirty » (Flutter 3.41+).
    return Offstage(
      offstage: route.points.isEmpty,
      child: OutlinedButton.icon(
        onPressed: () => _launch(context),
        icon: const Icon(Icons.map_outlined, size: 18),
        label: Text(strings.routeOpenInOsmAnd),
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
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final svc = OsmAndRoutingService.instance;
    final start = route.points.first;
    final end = route.points.last;
    final destName =
        route.label.isNotEmpty ? route.label : strings.routeDestination;

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
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(strings.routeOsmAndSuccess),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          );
        }
      },
    );

    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.routeOsmAndError),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _MiniRouteMap
// ══════════════════════════════════════════════════════════════════════════════

class _MiniRouteMap extends StatefulWidget {
  const _MiniRouteMap({required this.route});
  final RouteResult route;

  @override
  State<_MiniRouteMap> createState() => _MiniRouteMapState();
}

class _MiniRouteMapState extends State<_MiniRouteMap> {
  final MapController _controller = MapController();

  /// Fournisseur de tuiles « local d'abord » (cache disque → serveur
  /// StreetPhare → OSM en dernier recours), identique à la carte principale.
  /// Évite de s'appuyer sur un accès direct à tile.openstreetmap.org, qui peut
  /// être bloqué et laisser l'aperçu sur fond gris.
  late final LocalFirstTileProvider _tileProvider =
      LocalFirstTileProvider(headers: kStreetPhareTileHeaders);

  @override
  void dispose() {
    _tileProvider.dispose();
    _controller.dispose();
    super.dispose();
  }

  static const double _earthRadiusM = 6378137.0;

  static LatLng _center(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(48.8566, 2.3522);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  /// Projection Mercator (x est, y nord, en mètres), cohérente avec la
  /// projection de la carte, pour calculer un angle sans distorsion.
  static double _mercatorY(double latDeg) {
    final latRad = latDeg * math.pi / 180;
    final sinLat = math.sin(latRad);
    return _earthRadiusM / 2 * math.log((1 + sinLat) / (1 - sinLat));
  }

  /// Rotation (en degrés) qui aligne la plus grande longueur de l'itinéraire
  /// à l'horizontale, afin d'exploiter au mieux la fenêtre rectangulaire
  /// (plus large que haute) de l'aperçu.
  ///
  /// L'axe principal (direction de plus grande variance des points projetés)
  /// est obtenu par ACP (analyse en composantes principales). On calcule
  /// l'azimut géographique de cet axe puis la rotation de carte qui le rend
  /// horizontal.
  static double _bestBearing(List<LatLng> pts) {
    if (pts.length < 2) return 0;

    var meanX = 0.0, meanY = 0.0;
    final xs = <double>[];
    final ys = <double>[];
    for (final p in pts) {
      final x = _earthRadiusM * p.longitude * math.pi / 180;
      final y = _mercatorY(p.latitude);
      xs.add(x);
      ys.add(y);
      meanX += x;
      meanY += y;
    }
    meanX /= pts.length;
    meanY /= pts.length;

    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }

    // Angle de l'axe principal par rapport à l'axe Est (sens trigonométrique,
    // y vers le nord).
    final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);

    // Azimut géographique (0° = Nord, sens horaire) de cet axe.
    final azimuth =
        math.atan2(math.cos(theta), math.sin(theta)) * 180 / math.pi;

    // Pour que cet axe soit horizontal à l'écran : rotation = azimut - 90°.
    var bearing = azimuth - 90.0;
    bearing = ((bearing % 360) + 360) % 360;
    return bearing;
  }

  /// Recadre la mini-carte pour afficher la totalité de l'itinéraire.
  void _fitRoute() {
    final pts = widget.route.points;
    if (pts.length < 2) return;
    try {
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.all(16),
          maxZoom: 18,
        ),
      );
    } catch (_) {
      // La carte n'est pas encore prête : on conserve le cadrage initial.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.route.points;
    return SizedBox(
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _center(pts),
            initialZoom: 14,
            initialRotation: _bestBearing(pts),
            onMapReady: _fitRoute,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: '${NetworkConfig.baseUrl}/tiles/{z}/{x}/{y}.png',
              fallbackUrl: kStreetPhareOsmTileUrlTemplate,
              userAgentPackageName: 'com.streetphare.app',
              tileProvider: _tileProvider,
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
                    rotate: true,
                    width: 16,
                    height: 16,
                    child: Icon(Icons.trip_origin,
                        color: StreetPhareTheme.primary, size: 16),
                  ),
                if (pts.length >= 2)
                  Marker(
                    point: pts.last,
                    rotate: true,
                    width: 16,
                    height: 16,
                    child: Icon(Icons.location_on,
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
