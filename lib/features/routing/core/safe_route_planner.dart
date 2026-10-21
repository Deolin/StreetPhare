// lib/features/routing/core/safe_route_planner.dart
//
// PLANIFICATEUR D'ITINÉRAIRES SÛRS (SafeRoutePlanner).
//
// Orchestration de haut niveau au-dessus du RoutingEngine :
//   1. MULTI-ITINÉRAIRES : jusqu'à 3 itinéraires simultanés max, triés par
//      risque puis distance.
//   2. GARANTIE « 0 RISQUE » : si le trajet direct traverse des zones à
//      risque, force au moins une alternative qui évite TOUS les dangers.
//   3. PORTIONS RESTREINTES : détecte les segments franchissant une zone
//      bloquée (barrage / zone filtrée / nasse) pour le mode voiture/urgence.

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/alert_model.dart';
import '../../../database/alert_visibility_policy.dart';
import '../../../database/hive_alert_database.dart';
import '../domain/models/avoidance_filters.dart';
import '../domain/models/route_result.dart';
import '../domain/pedestrian_route_service.dart';
import '../presentation/safe_path_engine.dart';
import 'graph/spg_types.dart';
import 'models/routing_profile.dart';
import 'risk_score.dart';
import 'routing_engine.dart';

/// Planificateur d'itinéraires sécurisés (multi-itinéraires + 0 risque).
class SafeRoutePlanner {
  SafeRoutePlanner._();
  static final SafeRoutePlanner instance = SafeRoutePlanner._();

  /// Nombre maximum d'itinéraires retournés.
  static const int maxRoutes = 3;

  /// Rayon (mètres) de détection d'une portion restreinte autour d'une
  /// alerte bloquante (barrage / zone filtrée / nasse).
  static const double restrictionThresholdMeters = 25.0;

  /// Calcule jusqu'à [maxRoutes] itinéraires, triés par risque puis distance.
  ///
  /// Garantit la présence d'une alternative « 0 risque » si le trajet
  /// principal comporte des risques/incidents.
  Future<RouteComputeResult> computeRoutes({
    required LatLng start,
    required LatLng end,
    RoutingProfile profile = RoutingProfile.pedestrian,
    AvoidanceFilters filters = const AvoidanceFilters(),
  }) async {
    // 1) Demande les alternatives au moteur central (cascade SPG → natif →
    //    serveur/OSRM → SafePathEngine).
    final result = await RoutingEngine.instance.computeRoute(
      start: start,
      end: end,
      profile: profile,
      flags: const RoutingFlags(includeAlternatives: true, maxAlternatives: 3),
      avoidFilters: filters,
    );

    var routes = List<RouteResult>.from(result.routes);

    // 2) Si la cascade a échoué et que le profil est piéton/vélo, on tente
    //    directement le moteur local (grille Dijkstra) pour produire 1..3
    //    itinéraires.
    if (routes.isEmpty &&
        profile != RoutingProfile.vehicle &&
        profile != RoutingProfile.emergency) {
      routes = SafePathEngine.computeRoutes(
        start: start,
        end: end,
        filters: filters,
        constraints: PedestrianConstraints.fromProfile(profile),
      );
    }

    // 3) Collecte les dangers visibles pour la garantie « 0 risque ».
    final dangers = _collectDangerPoints(filters);

    // 4) Trie + déduplique, puis tronque à 3.
    routes = _dedupeAndSort(routes);
    if (routes.length > maxRoutes) {
      routes = routes.sublist(0, maxRoutes);
    }

    // 5) Garantie « 0 risque ».
    final hasZeroRisk = routes.any((r) => r.totalRiskScore <= 0.001);
    if (!hasZeroRisk && dangers.isNotEmpty) {
      final zeroRisk = _computeZeroRiskRoute(start, end, filters, dangers);
      if (zeroRisk != null) {
        if (routes.length >= maxRoutes) routes.removeLast();
        routes.add(zeroRisk);
        routes = _dedupeAndSort(routes);
      }
    }

    return RouteComputeResult(
      routes: routes,
      source: result.source,
      errorMessage: result.errorMessage,
    );
  }

  /// Détecte les segments de [points] qui franchissent une zone bloquée
  /// (barrage / zone filtrée / nasse) à moins de [thresholdMeters].
  List<RestrictedSegment> detectRestrictedSegments(
    List<LatLng> points, {
    double thresholdMeters = restrictionThresholdMeters,
  }) {
    final blocking = _collectBlockingAlerts();
    if (blocking.isEmpty || points.length < 2) return const [];

    final segments = <RestrictedSegment>[];
    for (final alert in blocking) {
      final run = <LatLng>[];
      for (final p in points) {
        final d = const Distance().distance(p, alert.position);
        if (d <= thresholdMeters) {
          run.add(p);
        } else {
          if (run.length >= 2) {
            segments.add(
              RestrictedSegment(
                points: List<LatLng>.from(run),
                reason: _restrictionReason(alert.type),
              ),
            );
          }
          run.clear();
        }
      }
      if (run.length >= 2) {
        segments.add(
          RestrictedSegment(
            points: List<LatLng>.from(run),
            reason: _restrictionReason(alert.type),
          ),
        );
      }
    }
    return segments;
  }

  List<LatLng> _collectDangerPoints(AvoidanceFilters filters) {
    try {
      final alerts = AlertVisibilityPolicy.filterAvoidable(
        HiveAlertDatabase.instance.getAllValid(),
      );
      return alerts
          .where((a) => filters.shouldAvoid(a.type))
          .map((a) => LatLng(a.latitude, a.longitude))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeRoutePlanner] collecte dangers impossible : $e');
      }
      return const [];
    }
  }

  /// Alertes « bloquantes » physiques : barrage, zone filtrée/nasse.
  List<Alert> _collectBlockingAlerts() {
    try {
      final alerts = AlertVisibilityPolicy.filterAvoidable(
        HiveAlertDatabase.instance.getAllValid(),
      );
      return alerts
          .where((a) =>
              a.type == AlertType.barrage || a.type == AlertType.filtre)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeRoutePlanner] collecte blocages impossible : $e');
      }
      return const [];
    }
  }

  String _restrictionReason(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return 'Barrage';
      case AlertType.filtre:
        return 'Zone filtrée / nasse';
      default:
        return 'Zone restreinte';
    }
  }

  RouteResult? _computeZeroRiskRoute(
    LatLng start,
    LatLng end,
    AvoidanceFilters filters,
    List<LatLng> dangers,
  ) {
    if (dangers.isEmpty) return null;
    RouteResult? best;
    double bestRisk = double.infinity;

    for (final radius in const [30.0, 60.0, 100.0]) {
      final routes = SafePathEngine.computePrimaryOnly(
        start: start,
        end: end,
        filters: filters,
        dangerRadiusMeters: radius,
      );
      if (routes.isEmpty) continue;

      final scored = _withScore(routes.first, dangers);
      if (scored.totalRiskScore <= 0.001) {
        return _withLabel(scored, '🛡 0 risque (contournement)');
      }
      if (scored.totalRiskScore < bestRisk) {
        bestRisk = scored.totalRiskScore;
        best = scored;
      }
    }

    return best == null
        ? null
        : _withLabel(best, '🛡 Contournement (risque min.)');
  }

  RouteResult _withScore(RouteResult r, List<LatLng> dangers) =>
      r.copyWith(totalRiskScore: computeRiskScore(r.points, dangers));

  RouteResult _withLabel(RouteResult r, String label) => RouteResult(
        id: r.id,
        points: r.points,
        totalDistanceMeters: r.totalDistanceMeters,
        totalRiskScore: r.totalRiskScore,
        pois: r.pois,
        label: label,
        restrictedSegments: r.restrictedSegments,
      );

  List<RouteResult> _dedupeAndSort(List<RouteResult> routes) {
    final sorted = List<RouteResult>.from(routes)
      ..sort((a, b) {
        final riskCompare = a.totalRiskScore.compareTo(b.totalRiskScore);
        if (riskCompare != 0) return riskCompare;
        return a.totalDistanceMeters.compareTo(b.totalDistanceMeters);
      });

    final seen = <String>{};
    final out = <RouteResult>[];
    for (final r in sorted) {
      final sig = _signature(r.points);
      if (seen.contains(sig)) continue;
      seen.add(sig);
      out.add(r);
    }
    return out;
  }

  static String _signature(List<LatLng> pts) {
    if (pts.isEmpty) return '';
    final n = pts.length;
    final idxs = <int>[
      0,
      n ~/ 5,
      (2 * n) ~/ 5,
      (3 * n) ~/ 5,
      (4 * n) ~/ 5,
      n - 1,
    ];
    return idxs
        .where((i) => i >= 0 && i < n)
        .map((i) =>
            '${pts[i].latitude.toStringAsFixed(3)},${pts[i].longitude.toStringAsFixed(3)}')
        .join('|');
  }
}




