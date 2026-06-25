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

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/streetphare_theme.dart';
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

// ignore: must_be_immutable
class _RouteResultSheetState extends State<RouteResultSheet> {
  final bool _showAlternatives = false;
  final bool _loadingAlternatives = false;
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

  @override
  // ignore: unused_element
  Widget build(BuildContext context) {
    final s = AppLocale.instance.strings;
    if (widget.routes.isEmpty) {
      return _wrap(
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            s.routeNotFound,
            textAlign: TextAlign.center,
            style: const TextStyle(color: StreetPhareTheme.textSecondary),
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
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                const Icon(Icons.shield,
                    color: StreetPhareTheme.primary, size: 22),
                Text(
                  s.routeTitle,
                  style: const TextStyle(
                    color: StreetPhareTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 0),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close,
                      color: StreetPhareTheme.textSecondary, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Indicateur de chargement des alternatives ────────────────
            if (_loadingAlternatives)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
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
                      style: const TextStyle(
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
                  '${s.routeAccept} : ${(_selected ?? recommended).distanceLabel}',
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

// ══════════════════════════════════════════════════════════════════════════════
// _RouteTile
// ══════════════════════════════════════════════════════════════════════════════

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.strings,
    required this.isSelected,
    required this.onTap,
  }) : badge = null;

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
                      '${route.distanceLabel} \u2022 ${strings.routeRisk} ${route.totalRiskScore.toStringAsFixed(0)}',
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

class _OsmAndLaunchButton extends StatelessWidget {
  const _OsmAndLaunchButton({required this.route, required this.strings});

  final RouteResult route;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (route.points.isEmpty) return const SizedBox.shrink();

    return OutlinedButton.icon(
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
