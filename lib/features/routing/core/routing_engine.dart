// lib/features/routing/core/routing_engine.dart
//
// Moteur de routage central (Singleton).
//
// Point d'entrée unique pour tous les calculs d'itinéraire.
// Gère le chargement du graphe .spg, la cascade de priorité
// et l'agrégation des résultats.
//
// Cascade de priorité :
//   0. Graphe .spg + Isolate → A* bidirectionnel → ~50 ms   ← MVP
//   1. MethodChannel Android (GraphHopper embarqué)  → ~200 ms ← Legacy
//   2. GraphHopper HTTP local                        → ~500 ms ← Legacy
//   3. OSRM public                                   → ~2 s    ← Legacy
//   4. SafePathEngine (grille Dijkstra)              → ~100 ms ← Fallback
//   5. Ligne droite                                  → ~1 ms   ← Ultime

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../domain/pedestrian_route_service.dart';
import '../domain/models/route_result.dart' as legacy;
import '../domain/models/avoidance_filters.dart';
import '../infrastructure/osmand_native_channel.dart';
import '../infrastructure/osmand_routing_service.dart';
import '../infrastructure/routing_isolate.dart';
import '../presentation/safe_path_engine.dart';
import '../presentation/route_notifier.dart';
import 'graph/spg_graph.dart';
import 'graph/spg_loader.dart';
import 'graph/spg_types.dart';
import 'models/routing_profile.dart';

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

/// Étape atteinte dans la cascade de routage.
enum CascadeStep {
  spg, // Nouveau moteur .spg
  nativeAndroid, // MethodChannel Android
  graphHopper, // GraphHopper HTTP local
  osrmPublic, // OSRM public
  safePath, // SafePathEngine (grille)
}

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

  /// Calcule un itinéraire avec cascade de priorité.
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
    List<LatLng> avoidPoints = const [],
  }) async {
    // Met à jour le profil courant pour le label.
    _lastProfile = profile;
    // ── TENTATIVE 0 : Graphe .spg (nouveau moteur) ─────────────────────
    if (_state == EngineState.ready && _graph != null) {
      try {
        final profileSettings = ProfileSettings.from(profile);
        final result = await RoutingIsolate.computeRoute(
          graph: _graph!,
          start: start,
          end: end,
          profile: profileSettings,
          flags: flags,
        );
        if (result.success) {
          onCascadeStep?.call(CascadeStep.spg);
          if (kDebugMode) {
            debugPrint('[RoutingEngine] ✅ SPG (${result.nodesExplored} nœuds, '
                '${result.totalDistanceMeters.round()} m)');
          }
          return _toRouteComputeResult(result);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[RoutingEngine] SPG failed: $e');
      }
    }

    // ── TENTATIVE 1 : MethodChannel Android (GraphHopper embarqué) ─────
    final nativeChannel = OsmAndNativeChannel.instance;
    if (nativeChannel.isSupported) {
      try {
        final nativeResult = await nativeChannel.computeRoute(
          start: start,
          end: end,
          profile: profile,
          avoidPoints: avoidPoints
              .map((p) => AvoidPoint(lat: p.latitude, lon: p.longitude))
              .toList(),
        );
        if (!nativeResult.isEmpty) {
          onCascadeStep?.call(CascadeStep.nativeAndroid);
          return RouteComputeResult(
            routes: nativeResult.routes,
            source: nativeResult.source,
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[RoutingEngine] Native failed: $e');
      }
    }

    // ── TENTATIVE 2 : GraphHopper HTTP local ───────────────────────────
    try {
      final legacyResult = await OsmAndRoutingService.instance.computeRoutes(
        start: start,
        end: end,
        profile: profile,
        filters: avoidFilters,
        avoidPoints: avoidPoints,
      );
      if (!legacyResult.isEmpty) {
        onCascadeStep?.call(CascadeStep.graphHopper);
        return RouteComputeResult(
          routes: legacyResult.routes,
          source: legacyResult.source,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RoutingEngine] GraphHopper failed: $e');
    }

    // ── TENTATIVE 3 : OSRM public ──────────────────────────────────────
    try {
      final legacyResult = await OsmAndRoutingService.instance.computeRoutes(
        start: start,
        end: end,
        profile: profile,
        filters: avoidFilters,
        avoidPoints: avoidPoints,
      );
      if (!legacyResult.isEmpty && legacyResult.source == 'osrm_public') {
        onCascadeStep?.call(CascadeStep.osrmPublic);
        return RouteComputeResult(
          routes: legacyResult.routes,
          source: legacyResult.source,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RoutingEngine] OSRM failed: $e');
    }

    // ── TENTATIVE 4 : SafePathEngine (grille Dijkstra) ─────────────────
    try {
      onCascadeStep?.call(CascadeStep.safePath);
      final paths = SafePathEngine.computePrimaryOnly(
        start: start,
        end: end,
        filters: avoidFilters,
        constraints: PedestrianConstraints.fromProfile(profile),
      );
      if (paths.isNotEmpty) {
        return RouteComputeResult(
          routes: paths,
          source: 'safe_path_engine',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RoutingEngine] SafePath failed: $e');
    }

    // ── ÉCHEC TOTAL ─────────────────────────────────────────────────────
    return RouteComputeResult(
      routes: const [],
      source: 'all_failed',
      errorMessage: 'Aucun moteur de routage disponible. '
          'Vérifiez la connexion réseau ou les fichiers de carte.',
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
      source: 'spg_graph',
    );
  }

  String get profileLabel {
    if (_lastProfile == RoutingProfile.pedestrian) return 'piéton';
    if (_lastProfile == RoutingProfile.bicycle) return 'vélo';
    if (_lastProfile == RoutingProfile.vehicle) return 'véhicule';
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
  });

  /// Liste des itinéraires calculés.
  final List<legacy.RouteResult> routes;

  /// Source du calcul.
  final String source;

  /// Message d'erreur (si échec).
  final String? errorMessage;

  bool get hasError => errorMessage != null;
  bool get isEmpty => routes.isEmpty;
  bool get isNotEmpty => routes.isNotEmpty;
}
