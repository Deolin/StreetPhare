// lib/features/routing/core/routing_engine.dart
//
// Moteur de routage central (Singleton).
//
// Point d'entrée unique pour tous les calculs d'itinéraire.
// Gère le chargement du graphe .spg, la cascade de connectivité
// et l'agrégation des résultats.
//
// Cascade de connectivité (ordre STRICT) :
//   1. SERVEUR StreetPhare  → /api/route (Dijkstra embarqué)        ← niveau 1
//   2. LOCAL (offline)      → SPG A*/Dijkstra / GraphHopper natif   ← niveau 2
//   3. OSMAND / OSRM public → dernier recours réseau                ← niveau 3
//
// Chaque niveau renseigne `source` : `server` | `local` | `osmand`.
// NOTE : il n'y a PAS de fallback « grille Dijkstra / vol d'oiseau ».
//   Un itinéraire proposé doit suivre la voirie réelle. Si tous les moteurs
//   routables échouent, on renvoie un échec.

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/alert_visibility_policy.dart';
import '../../../database/hive_alert_database.dart';
import '../domain/models/avoidance_filters.dart';
import '../domain/models/route_result.dart' as legacy;
import '../infrastructure/open_trip_planner_service.dart';
import '../infrastructure/osmand_native_channel.dart';
import '../infrastructure/osmand_routing_service.dart';
import '../infrastructure/routing_isolate.dart';
import '../presentation/route_notifier.dart';
import 'danger_point.dart';
import 'graph/spg_graph.dart';
import 'graph/spg_loader.dart';
import 'graph/spg_types.dart';
import 'models/routing_profile.dart';
import 'risk_score.dart';

/// État du moteur de routage.
enum EngineState {
  /// Graphe non chargé.
  unloaded,

  /// Chargement en cours.
  loading,

  /// Graphe chargé et prêt.
  ready,

  /// Erreur de chargement.
  error,
}

/// Étape atteinte dans la cascade de connectivité.
enum CascadeStep {
  transit, // OpenTripPlanner (transports en commun — serveur)
  server, // serveur StreetPhare (Dijkstra embarqué)
  local, // moteur local (SPG A*/Dijkstra ou GraphHopper natif)
  osmand, // OsmAnd / OSRM public (dernier recours)
}

/// Timeout court pour le niveau 1 (serveur StreetPhare) de la cascade.
const Duration kServerRouteTimeout = Duration(seconds: 2);

/// Moteur de routage central.
class RoutingEngine {
  RoutingEngine._();
  static final RoutingEngine instance = RoutingEngine._();

  // ── État ───────────────────────────────────────────────────────────────

  EngineState _state = EngineState.unloaded;
  EngineState get state => _state;

  SpgGraph? _graph;
  String? _loadedRegionId;

  /// Région actuellement chargée (ex: "belgique", "fleurus").
  String? get loadedRegionId => _loadedRegionId;

  /// Notifieur de polyline pour l'UI.
  final RouteNotifier routeNotifier = RouteNotifier();

  // Callbacks
  ValueChanged<EngineState>? onStateChanged;
  ValueChanged<CascadeStep>? onCascadeStep;

  // ── Chargement du graphe ──────────────────────────────────────────────

  /// Charge un graphe .spg depuis le stockage local.
  ///
  /// [regionId] : identifiant de la région (ex: "belgique", "fleurus").
  /// Le fichier est cherché dans `regions/$regionId.spg`.
  Future<void> loadRegion(String regionId) async {
    _state = EngineState.loading;
    onStateChanged?.call(_state);

    try {
      _graph = await SpgLoader.loadFile('regions/$regionId.spg');
      _loadedRegionId = regionId;
      _state = EngineState.ready;
      if (kDebugMode) {
        debugPrint('[RoutingEngine] ✅ région "$regionId" chargée '
            '(${_graph!.nodeCount} nœuds, ${_graph!.edgeCount} arêtes, '
            '${_graph!.memoryMb.toStringAsFixed(1)} Mo)');
      }
    } catch (e) {
      _state = EngineState.error;
      if (kDebugMode) {
        debugPrint('[RoutingEngine] ❌ échec chargement "$regionId": $e');
      }
    }
    onStateChanged?.call(_state);
  }

  /// Vérifie si le graphe est chargé pour une région donnée.
  bool isRegionLoaded(String regionId) =>
      _state == EngineState.ready && _loadedRegionId == regionId;

  // ── Calcul d'itinéraire avec cascade ──────────────────────────────────

  /// Calcule un itinéraire via la cascade de connectivité unifiée :
  ///
  ///   1. Serveur StreetPhare → /api/route (Dijkstra embarqué), timeout court.
  ///   2. Local (offline)      → SPG A*/Dijkstra puis GraphHopper natif.
  ///   3. OsmAnd / OSRM public → dernier recours réseau.
  ///
  /// [profile] : profil de déplacement.
  /// [flags] : options de routage.
  /// [avoidFilters] : filtres d'évitement (StreetPhare legacy).
  /// [avoidPoints] : points à éviter (dangers validés).
  Future<RouteComputeResult> computeRoute({
    required LatLng start,
    required LatLng end,
    RoutingProfile profile = RoutingProfile.pedestrian,
    RoutingFlags flags = const RoutingFlags(),
    AvoidanceFilters avoidFilters = const AvoidanceFilters(),
    List<DangerPoint> avoidPoints = const [],
  }) async {
    // Met à jour le profil courant pour le label.
    _lastProfile = profile;

    // Points de danger à éviter : construits à partir des signalements
    // visibles ET des préférences utilisateur (filtres d'évitement).
    // Si l'appelant fournit déjà des points, on les utilise tels quels.
    final dangerPoints = avoidPoints.isNotEmpty
        ? avoidPoints
        : _collectDangerPoints(avoidFilters);

    // ── TRANSIT : OpenTripPlanner (moteur serveur des transports en commun) ──
    // OTP est le moteur dédié aux trajets multi-paliers (marche + TC). S'il
    // échoue, on retombe sur la cascade ci-dessous (repli piéton de
    // rabattement : le profil transit est alors traité comme un piéton).
    if (profile == RoutingProfile.transit) {
      try {
        final otpRoutes = await OpenTripPlannerService.instance.plan(
          start: start,
          end: end,
        );
        if (otpRoutes.isNotEmpty) {
          onCascadeStep?.call(CascadeStep.transit);
          if (kDebugMode) {
            debugPrint(
                '[RoutingEngine] ✅ OTP → ${otpRoutes.length} itinéraire(s)');
          }
          return _applyRiskScore(
            RouteComputeResult(
              routes: otpRoutes,
              source: 'server',
            ),
            dangerPoints,
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[RoutingEngine] OTP failed: $e');
      }
    }

    // ── NIVEAU 1 : SERVEUR StreetPhare (Dijkstra embarqué) ────────────────
    // Timeout court : on ne bloque pas longtemps sur un serveur lent/absent.
    try {
      final serverRoutes = await OsmAndRoutingService.instance.computeViaServer(
        start: start,
        end: end,
        profile: profile,
        avoidPoints: dangerPoints,
        timeout: kServerRouteTimeout,
      );
      if (serverRoutes.isNotEmpty) {
        onCascadeStep?.call(CascadeStep.server);
        if (kDebugMode) {
          debugPrint('[RoutingEngine] ✅ Serveur StreetPhare → '
              '${serverRoutes.first.points.length} points');
        }
        return _applyRiskScore(
          RouteComputeResult(routes: serverRoutes, source: 'server'),
          dangerPoints,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RoutingEngine] Serveur StreetPhare: $e');
    }

    // ── NIVEAU 2 : LOCAL — Graphe .spg (A*/Dijkstra) ─────────────────────
    if (_state == EngineState.ready && _graph != null) {
      try {
        final profileSettings = ProfileSettings.from(profile);
        final result = await RoutingIsolate.computeRoute(
          graph: _graph!,
          start: start,
          end: end,
          profile: profileSettings,
          flags: RoutingFlags(
            includeAlternatives: flags.includeAlternatives,
            maxAlternatives: flags.maxAlternatives,
            avoidPoints: dangerPoints
                .map((p) => RoutingAvoidPoint(
                    lat: p.lat,
                    lon: p.lon,
                    radiusMeters: p.radiusMeters,
                    weight: p.weight))
                .toList(),
            timeoutMs: flags.timeoutMs,
          ),
        );
        if (result.success) {
          onCascadeStep?.call(CascadeStep.local);
          if (kDebugMode) {
            debugPrint('[RoutingEngine] ✅ SPG (${result.nodesExplored} nœuds, '
                '${result.totalDistanceMeters.round()} m)');
          }
          return _applyRiskScore(_toRouteComputeResult(result), dangerPoints);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[RoutingEngine] SPG failed: $e');
      }
    }

    // ── NIVEAU 2 : LOCAL — GraphHopper natif Android ─────────────────────
    final nativeChannel = OsmAndNativeChannel.instance;
    if (nativeChannel.isSupported) {
      try {
        final nativeResult = await nativeChannel.computeRoute(
          start: start,
          end: end,
          profile: profile,
          avoidPoints: dangerPoints
              .map((p) => AvoidPoint(
                  lat: p.lat,
                  lon: p.lon,
                  radiusMeters: p.radiusMeters,
                  weight: p.weight))
              .toList(),
        );
        if (!nativeResult.isEmpty) {
          onCascadeStep?.call(CascadeStep.local);
          return _applyRiskScore(
            RouteComputeResult(
              routes: nativeResult.routes,
              source: 'local',
            ),
            dangerPoints,
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[RoutingEngine] Native failed: $e');
      }
    }

    // ── NIVEAU 3 : OSMAND / OSRM public (dernier recours réseau) ─────────
    try {
      final osrmRoutes = await OsmAndRoutingService.instance.computeViaOsrm(
        start: start,
        end: end,
        profile: profile,
        avoidPoints: dangerPoints,
      );
      if (osrmRoutes.isNotEmpty) {
        onCascadeStep?.call(CascadeStep.osmand);
        return _applyRiskScore(
          RouteComputeResult(routes: osrmRoutes, source: 'osmand'),
          dangerPoints,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RoutingEngine] OSRM failed: $e');
    }

    // ── ÉCHEC TOTAL ─────────────────────────────────────────────────────
    return const RouteComputeResult(
      routes: [],
      source: 'all_failed',
      errorMessage: 'Aucun moteur de routage disponible. '
          'Vérifiez la connexion réseau ou les fichiers de carte.',
    );
  }

  /// Collecte les points de danger à éviter à partir des signalements
  /// visibles et des préférences utilisateur ([AvoidanceFilters]).
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
        debugPrint('[RoutingEngine] collecte dangers impossible : $e');
      }
      return const [];
    }
  }

  /// Applique le score de risque calculé aux itinéraires retournés.
  ///
  /// Le score est la somme des contributions des dangers traversés
  /// (1.0 au centre d'un danger, décroissant jusqu'à 0 au bord du rayon).
  RouteComputeResult _applyRiskScore(
    RouteComputeResult result,
    List<DangerPoint> dangerPoints,
  ) {
    if (dangerPoints.isEmpty || result.routes.isEmpty) return result;
    final dangerLatLngs = dangerPoints.map((p) => p.latLng).toList();
    final scored = result.routes
        .map((r) => r.copyWith(
              totalRiskScore: computeRiskScore(r.points, dangerLatLngs),
            ))
        .toList();
    return RouteComputeResult(
      routes: scored,
      source: result.source,
      errorMessage: result.errorMessage,
      warnings: result.warnings,
    );
  }

  /// Convertit un ComputeResult (Isolate) en RouteComputeResult.
  RouteComputeResult _toRouteComputeResult(ComputeResult result) {
    final routeResult = legacy.RouteResult(
      id: _loadedRegionId ?? 'spg_route',
      points: result.points,
      totalDistanceMeters: result.totalDistanceMeters,
      totalRiskScore: 0,
      pois: const [],
      label: 'Itinéraire $profileLabel',
    );

    return RouteComputeResult(
      routes: [routeResult],
      source: 'local',
    );
  }

  String get profileLabel {
    if (_lastProfile == RoutingProfile.pedestrian) return 'piéton';
    if (_lastProfile == RoutingProfile.bicycle) return 'vélo';
    if (_lastProfile == RoutingProfile.vehicle) return 'véhicule';
    if (_lastProfile == RoutingProfile.transit) return 'transports en commun';
    return 'urgence';
  }

  RoutingProfile _lastProfile = RoutingProfile.pedestrian;

  /// Libère le graphe de la mémoire.
  void unloadRegion() {
    _graph = null;
    _loadedRegionId = null;
    _state = EngineState.unloaded;
    routeNotifier.clear();
    onStateChanged?.call(_state);
  }
}

/// Résultat d'un calcul via [RoutingEngine].
class RouteComputeResult {
  const RouteComputeResult({
    required this.routes,
    required this.source,
    this.errorMessage,
    this.warnings = const [],
  });

  /// Liste des itinéraires calculés.
  final List<legacy.RouteResult> routes;

  /// Source du calcul.
  final String source;

  /// Message d'erreur (si échec).
  final String? errorMessage;

  /// Avertissements non bloquants (ex: départ/arrivée dans une zone de danger,
  /// contournement impossible). Vide si aucun.
  final List<String> warnings;

  bool get hasError => errorMessage != null;
  bool get isEmpty => routes.isEmpty;
  bool get isNotEmpty => routes.isNotEmpty;
}
