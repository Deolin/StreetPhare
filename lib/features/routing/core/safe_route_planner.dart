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

    // Attache une durée réaliste selon le profil : seuls les moteurs TC (OTP)
    // fournissent une durée réelle ; sinon on estime à partir d'une vitesse
    // moyenne par mode (voiture ≈ 40 km/h, piéton ≈ 4.5 km/h, …). Sans cela,
    // un trajet voiture affichait un temps calculé comme à pied.
    routes = routes.map((r) => _withEstimatedDuration(r, profile)).toList();

    // Trie + déduplique, puis tronque à [maxRoutes].
    routes = _dedupeAndSort(routes);
    if (routes.length > maxRoutes) {
      routes = routes.sublist(0, maxRoutes);
    }

    // Avertissements non bloquants : origine/destination dans une zone de
    // danger, ou absence de contournement sans danger.
    final warnings = _computeWarnings(start, end, dangers, routes);

    return RouteComputeResult(
      routes: routes,
      source: result.source,
      errorMessage: result.errorMessage,
      warnings: warnings,
    );
  }

  /// Retourne une copie de [r] avec une durée estimée selon [profile],
  /// sauf si le moteur a déjà fourni une durée réelle (ex: OTP/OSRM).
  RouteResult _withEstimatedDuration(RouteResult r, RoutingProfile profile) {
    if (r.duration != null) return r;
    final seconds = (r.totalDistanceMeters / _averageSpeedMps(profile)).round();
    return r.copyWith(duration: Duration(seconds: seconds));
  }

  /// Vitesse moyenne (m/s) utilisée pour l'estimation de la durée de trajet.
  double _averageSpeedMps(RoutingProfile profile) {
    switch (profile) {
      case RoutingProfile.bicycle:
        return 4.17; // ~15 km/h
      case RoutingProfile.vehicle:
        return 11.11; // ~40 km/h urbain
      case RoutingProfile.emergency:
        return 13.89; // ~50 km/h
      case RoutingProfile.transit:
      case RoutingProfile.pedestrian:
        return 1.25; // ~4.5 km/h
    }
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

  /// Construit les avertissements non bloquants du plan d'itinéraire :
  /// origine/destination située dans une zone de danger, ou absence de
  /// contournement sans danger (toutes les routes traversent une zone bloquante).
  List<String> _computeWarnings(
    LatLng start,
    LatLng end,
    List<DangerPoint> dangers,
    List<RouteResult> routes,
  ) {
    final warnings = <String>[];
    final blocking = dangers.where((d) => d.isBlocking).toList();
    if (blocking.isEmpty) return warnings;

    const distance = Distance();
    final startBlocked = blocking.any(
      (d) => distance.distance(start, d.latLng) <= d.radiusMeters,
    );
    final endBlocked = blocking.any(
      (d) => distance.distance(end, d.latLng) <= d.radiusMeters,
    );
    if (startBlocked) {
      warnings.add('Point de départ situé dans une zone de danger.');
    }
    if (endBlocked) {
      warnings.add("Point d'arrivée situé dans une zone de danger.");
    }

    // Contournement impossible : toutes les routes traversent une zone
    // bloquante (aucune alternative « 0 risque » n'existe).
    if (routes.isNotEmpty &&
        routes.every((r) => _routeCrossesBlocking(r, blocking))) {
      warnings.add(
        'Aucun itinéraire sans danger trouvé : le tracé traverse des zones '
        'bloquées.',
      );
    }
    return warnings;
  }

  /// Vrai si au moins un point du [route] tombe dans une zone bloquante.
  bool _routeCrossesBlocking(RouteResult route, List<DangerPoint> blocking) {
    const distance = Distance();
    for (final p in route.points) {
      for (final d in blocking) {
        if (distance.distance(p, d.latLng) <= d.radiusMeters) return true;
      }
    }
    return false;
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
