// lib/features/routing/domain/pedestrian_route_service.dart
//
// Service de routage piéton MULTI-MODES avec intégration OSM.
//
// PRINCIPE FONDAMENTAL :
//   Un itinéraire "Route Safe" DOIT impérativement suivre les voiries
//   praticables à pied (rues, trottoirs, chemins, passages piétons).
//   Il est INTERDIT de tracer des lignes droites à travers des bâtiments,
//   des terrains privés, ou tout obstacle physique.
//
// TROIS MODES D'IMPLÉMENTATION (par ordre de priorité) :
//
//   1. RÉSEAU (en ligne, précis) — PRIORITAIRE :
//      Appel au serveur local POST /v1/events/:id/route qui utilise
//      le module events_manager.js (backend Node.js) avec un moteur
//      de routage OSM (GraphHopper/OSRM) profil "foot". Garantit que
//      le tracé suit exactement le réseau routier piéton OpenStreetMap.
//
//   2. LOCAL (hors-ligne, approximatif) :
//      Algorithme de Dijkstra sur grille GPS avec pénalité diagonale.
//      Efficace en mode dégradé / offline.
//
//   3. FALLBACK ULTIME :
//      Ligne droite A→B avec interpolation, utilisé si tout échoue.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../network/network_config.dart';
import 'models/avoidance_filters.dart';
import 'models/route_result.dart';
import '../presentation/safe_path_engine.dart';
import '../infrastructure/osmand_routing_service.dart';

// ============================================================================
// Mode de routage piéton
// ============================================================================

/// Stratégie de calcul du chemin piéton.
enum PedestrianRoutingMode {
  /// MODE 0 — OsmAnd Bridge (PRIORITAIRE) :
  /// GraphHopper local :8080 → OSRM public → SafePathEngine.
  /// Garantit un tracé 100% sur le réseau routier OSM.
  osmAndBridge,

  /// Calcul via API OSM (serveur local Node.js avec GraphHopper/OSRM).
  /// PRÉCIS : suit le réseau routier réel, idéal pour Fleurus.
  osmNetwork,

  /// Calcul local sur grille (offline, approximatif).
  /// Rapide, sans réseau, mais peut traverser des zones non-praticables.
  localGrid,

  /// Fallback ligne droite (aucun serveur ni grille disponibles).
  directLine,
}

// ============================================================================
// Contraintes piétonnes
// ============================================================================

/// Paramètres de contraintes spécifiques au routage piéton.
///
/// Ces contraintes sont appliquées lors du calcul d'itinéraire pour
/// garantir que le tracé correspond à ce qu'un piéton peut physiquement
/// parcourir (pas de passages à travers des bâtiments ou obstacles).
class PedestrianConstraints {
  const PedestrianConstraints({
    this.diagonalPenaltyFactor = 3.0,
    this.unknownTerrainPenalty = 150.0,
    this.gridStepMeters = 20.0,
  });

  final double diagonalPenaltyFactor;
  final double unknownTerrainPenalty;
  final double gridStepMeters;

  static const PedestrianConstraints urban = PedestrianConstraints(
    diagonalPenaltyFactor: 3.5,
    unknownTerrainPenalty: 200.0,
    gridStepMeters: 20.0,
  );

  static const PedestrianConstraints rural = PedestrianConstraints(
    diagonalPenaltyFactor: 2.0,
    unknownTerrainPenalty: 80.0,
    gridStepMeters: 30.0,
  );
}

// ============================================================================
// Service de routage — implémentation multi-modes
// ============================================================================

/// Service singleton de routage piéton.
///
/// Tente d'abord le routage OSM via le serveur local, puis la grille
/// Dijkstra locale, puis enfin la ligne droite directe.
class PedestrianRouteService {
  PedestrianRouteService._();
  static final PedestrianRouteService instance = PedestrianRouteService._();

  PedestrianRoutingMode _activeMode = PedestrianRoutingMode.osmAndBridge;
  PedestrianRoutingMode get activeMode => _activeMode;

  /// Calcule uniquement la route principale (JIT).
  ///
  /// Ordre de priorité :
  ///   0. OsmAnd Bridge  (GraphHopper local :8080 → OSRM public)  ← NOUVEAU
  ///   1. Serveur local  (/v1/events/:id/route)
  ///   2. Grille Dijkstra locale (offline)
  Future<List<RouteResult>> computePrimaryOnly({
    required LatLng start,
    required LatLng end,
    required AvoidanceFilters filters,
    PedestrianConstraints constraints = PedestrianConstraints.urban,
    String? eventId,
    List<LatLng> avoidPoints = const [],
  }) async {
    // ── MODE 0 : OsmAnd Bridge (GraphHopper local → OSRM public) ────────────
    try {
      final osmAndResult = await OsmAndRoutingService.instance.computeRoutes(
        start: start,
        end: end,
        filters: filters,
        avoidPoints: avoidPoints,
        eventId: eventId,
      );
      if (!osmAndResult.isEmpty) {
        _activeMode = PedestrianRoutingMode.osmAndBridge;
        if (kDebugMode) {
          debugPrint('[PedestrianRoute] ✅ Mode 0 OsmAnd Bridge '
              '(${osmAndResult.source}) → '
              '${osmAndResult.routes.first.points.length} pts');
        }
        return osmAndResult.routes;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PedestrianRoute] OsmAnd Bridge failed: $e');
    }

    // ── MODE 1 : Serveur local Node.js (/v1/events/:id/route) ───────────────
    if (eventId != null) {
      try {
        final osmRoutes = await _computeViaServer(
          start: start,
          end: end,
          eventId: eventId,
          filters: filters,
        );
        if (osmRoutes.isNotEmpty) {
          _activeMode = PedestrianRoutingMode.osmNetwork;
          return osmRoutes;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[PedestrianRoute] OSM failed: $e');
      }
    }

    // ── MODE 2 : Grille Dijkstra locale (offline) ────────────────────────────
    _activeMode = PedestrianRoutingMode.localGrid;
    return SafePathEngine.computePrimaryOnly(
      start: start,
      end: end,
      filters: filters,
      constraints: constraints,
    );
  }

  /// Calcule uniquement les alternatives (JIT), appelé après computePrimaryOnly.
  Future<List<RouteResult>> computeAlternatives({
    required LatLng start,
    required LatLng end,
    required AvoidanceFilters filters,
    PedestrianConstraints constraints = PedestrianConstraints.urban,
  }) async {
    return SafePathEngine.computeAlternatives(
      start: start,
      end: end,
      filters: filters,
      constraints: constraints,
    );
  }

  /// Route complète (primaires + alternatives en une passe).
  ///
  /// Ordre de priorité :
  ///   0. OsmAnd Bridge  (GraphHopper local :8080 → OSRM public)
  ///   1. Serveur local  (/v1/events/:id/route)
  ///   2. Grille Dijkstra locale (offline)
  Future<List<RouteResult>> computeRoutes({
    required LatLng start,
    required LatLng end,
    required AvoidanceFilters filters,
    PedestrianConstraints constraints = PedestrianConstraints.urban,
    String? eventId,
    List<LatLng> avoidPoints = const [],
  }) async {
    // ── MODE 0 : OsmAnd Bridge ───────────────────────────────────────────────
    try {
      final osmAndResult = await OsmAndRoutingService.instance.computeRoutes(
        start: start,
        end: end,
        filters: filters,
        avoidPoints: avoidPoints,
        eventId: eventId,
      );
      if (!osmAndResult.isEmpty) {
        _activeMode = PedestrianRoutingMode.osmAndBridge;
        if (kDebugMode) {
          debugPrint('[PedestrianRoute] ✅ computeRoutes OsmAnd Bridge '
              '(${osmAndResult.source})');
        }
        return osmAndResult.routes;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PedestrianRoute] computeRoutes OsmAnd: $e');
    }

    // ── MODE 1 : Serveur local ───────────────────────────────────────────────
    if (eventId != null) {
      try {
        final osmRoutes = await _computeViaServer(
          start: start, end: end, eventId: eventId, filters: filters,
        );
        if (osmRoutes.isNotEmpty) {
          _activeMode = PedestrianRoutingMode.osmNetwork;
          return osmRoutes;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[PedestrianRoute] OSM fail: $e');
      }
    }

    // ── MODE 2 : Grille Dijkstra locale ─────────────────────────────────────
    _activeMode = PedestrianRoutingMode.localGrid;
    return SafePathEngine.computeRoutes(
      start: start, end: end, filters: filters, constraints: constraints,
    );
  }

  /// Calcule la route via le serveur local (POST /v1/events/:id/route).
  Future<List<RouteResult>> _computeViaServer({
    required LatLng start,
    required LatLng end,
    required String eventId,
    required AvoidanceFilters filters,
  }) async {
    final serverUrl = NetworkConfig.primaryServer;
    final uri = Uri.parse('$serverUrl/v1/events/$eventId/route');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-StreetPhare-Route', 'pedestrian');
      req.add(utf8.encode(jsonEncode({
        'from': {'lat': start.latitude, 'lon': start.longitude},
        'to': {'lat': end.latitude, 'lon': end.longitude},
        'avoid_filters': {
          'barrage': filters.avoidBarrages,
          'nasse': filters.avoidNasses,
          'controle': filters.avoidControles,
          'accident': filters.avoidAccidents,
          'manifestation': filters.avoidManifestations,
          'autres': filters.avoidAutres,
        },
      })));

      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) return [];

      final parsed = jsonDecode(body) as Map<String, dynamic>;
      final routesJson = parsed['routes'] as List<dynamic>? ?? [];

      final results = <RouteResult>[];
      for (int i = 0; i < routesJson.length; i++) {
        final r = routesJson[i] as Map<String, dynamic>;
        final polylineRaw = r['polyline'] as List<dynamic>? ?? [];
        final points = polylineRaw.map((pt) {
          final p = pt as List<dynamic>;
          return LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
        }).toList();
        if (points.length < 2) continue;
        results.add(RouteResult(
          id: i == 0 ? 'primary' : 'alt$i',
          points: points,
          totalDistanceMeters: (r['distance_m'] as num?)?.toDouble() ?? 0,
          totalRiskScore: (r['safe_score'] as num?)?.toDouble() ?? 0,
          pois: const [],
          label: i == 0
              ? 'Itinéraire piéton OSM recommandé'
              : 'Alternative OSM $i',
        ));
      }
      return results;
    } catch (e) {
      return [];
    } finally {
      client.close(force: true);
    }
  }
}

// ============================================================================
// Utilitaires
// ============================================================================

Duration estimateWalkDuration(double distanceMeters) {
  const metersPerSecond = 4500.0 / 3600.0;
  return Duration(seconds: (distanceMeters / metersPerSecond).round());
}

String formatWalkDuration(Duration d) {
  final totalMin = d.inMinutes;
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}min';
}