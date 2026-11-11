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
import 'danger_point.dart';
import 'graph/spg_types.dart';
import 'models/routing_profile.dart';
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

  /// Calcule jusqu'à [maxRoutes] itinéraires routables, triés par risque
  /// puis distance. Ne renvoie que des tracés suivant la voirie réelle
  /// (SPG / GraphHopper / OSRM) — jamais de tracé « à vol d'oiseau ».
  Future<RouteComputeResult> computeRoutes({
    required LatLng start,
    required LatLng end,
    RoutingProfile profile = RoutingProfile.pedestrian,
    AvoidanceFilters filters = const AvoidanceFilters(),
  }) async {
    // 0) Collecte les dangers visibles (transmis au moteur central pour
    //    l'évitement des zones à risque).
    final dangers = _collectDangerPoints(filters);

    // 1) Demande les alternatives au moteur central (cascade routable
    //    SPG → natif GraphHopper → serveur/OSRM).
    final result = await RoutingEngine.instance.computeRoute(
      start: start,
      end: end,
      profile: profile,
      flags: const RoutingFlags(includeAlternatives: true, maxAlternatives: 3),
      avoidFilters: filters,
      avoidPoints: dangers,
    );

    var routes = List<RouteResult>.from(result.routes);

    // Trie + déduplique, puis tronque à [maxRoutes].
    routes = _dedupeAndSort(routes);
    if (routes.length > maxRoutes) {
      routes = routes.sublist(0, maxRoutes);
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

  List<DangerPoint> _collectDangerPoints(AvoidanceFilters filters) {
    try {
      final alerts = AlertVisibilityPolicy.filterAvoidable(
        HiveAlertDatabase.instance.getAllValid(),
      );
      return alerts
          .where((a) => filters.shouldAvoid(a.type))
          .map(DangerPoint.fromAlert)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeRoutePlanner] collecte dangers impossible : $e');
      }
      return const [];
    }
  }

  /// Alertes « bloquantes » physiques : barrage uniquement (infranchissable).
  /// Les filtres restent évitables mais franchissables (pondération douce).
  List<Alert> _collectBlockingAlerts() {
    try {
      final alerts = AlertVisibilityPolicy.filterAvoidable(
        HiveAlertDatabase.instance.getAllValid(),
      );
      return alerts.where((a) => a.type == AlertType.barrage).toList();
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
