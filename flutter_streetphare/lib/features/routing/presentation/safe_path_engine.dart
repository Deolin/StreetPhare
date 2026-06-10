// lib/features/routing/presentation/safe_path_engine.dart
//
// MOTEUR DE CHEMIN PIÉTON SÛR MULTI-CRITÈRES (Safe Path Engine).
//
// Implémentation locale d'un algorithme de DIJKSTRA sur une grille
// de coordonnées GPS, conçue pour calculer des itinéraires EXCLUSIVEMENT
// PIÉTONS — sans jamais tracer de ligne droite à travers des bâtiments.
//
// ROUTAGE PIÉTON — PRINCIPES D'IMPLÉMENTATION :
//   1. GRILLE À PAS RÉDUIT (20 m) : la résolution plus fine limite
//      les sauts de cellules à travers les bâtiments.
//   2. PÉNALITÉ DIAGONALE FORTE : les arêtes diagonales (NE, NW, SE, SW)
//      sont multipliées par `PedestrianConstraints.diagonalPenaltyFactor`
//      (défaut : 3.5 en zone urbaine). Cela force l'algorithme à préférer
//      les connexions orthogonales (N, S, E, W), supposées suivre la voirie.
//   3. POIDS INFINI sur les cellules qui intersectent un danger marqué
//      "à éviter" par l'utilisateur (bloquant absolu).
//   4. POIDS AUGMENTÉ (soft penalty) sur les cellules proches d'un danger
//      "accepté" — l'algorithme les contourne si possible.
//   5. ALTERNATIVES : 2 variantes supplémentaires avec bruit aléatoire
//      sur les poids d'arêtes (méthode "K-shortest paths" simplifiée).
//
// LIMITATION DU MODE LOCAL :
//   Sans réseau OSM réel (OSRM/GraphHopper profil "foot"), le moteur
//   reste une approximation. Pour une précision maximale (garantie de
//   suivre les trottoirs et passages piétons OSM), il faudra intégrer
//   l'interface `IPedestrianRouteService` avec un backend réseau.
//   Voir : lib/features/routing/domain/pedestrian_route_service.dart
//
// Le résultat est un ensemble de 1 à 3 `RouteResult` que l'UI
// affiche côte à côte pour laisser l'utilisateur choisir.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/alert_model.dart';
import '../../../database/alert_visibility_policy.dart';
import '../../../database/hive_alert_database.dart';
import '../../geofencing/presentation/geofencing_service.dart';
import '../domain/models/avoidance_filters.dart';
import '../domain/models/route_result.dart';
import '../domain/pedestrian_route_service.dart';

/// Moteur de calcul d'itinéraires "safe path".
class SafePathEngine {
  SafePathEngine._();

  /// Pas de la grille d'échantillonnage (en mètres).
  ///
  /// Réduit à 20 m (au lieu de 30 m) pour limiter les sauts de cellules
  /// à travers les bâtiments en zone urbaine dense (ex: Fleurus centre).
  /// À ajuster via [PedestrianConstraints.gridStepMeters] si besoin.
  static const double gridStepMeters = 20.0;

  /// Rayon d'influence (en mètres) d'un danger AUTOUR de son
  /// point central : le danger occupe un disque de ce rayon.
  static const double dangerRadiusMeters = 50.0;

  /// Rayon de "pénalité douce" (en mètres) pour les dangers
  /// que l'utilisateur accepte de traverser : on n'évite pas
  /// le danger, mais on s'en éloigne si possible.
  static const double softPenaltyRadiusMeters = 100.0;

  /// Pénalité (en mètres-équivalent) appliquée par cellule qui
  /// se trouve dans la zone douce d'un danger.
  static const double softPenaltyWeight = 200.0;

  /// Bruit aléatoire ajouté à chaque arête lors du calcul des
  /// ALTERNATIVES (pour produire des chemins distincts).
  static const double alternativesJitter = 0.4;

  /// Nombre maximum d'alternatives retournées.
  static const int maxAlternatives = 3;

  /// Calcule 1 à 3 itinéraires PIÉTONS sûrs entre [start] et [end].
  ///
  /// Les itinéraires sont calculés en évitant :
  ///   - les signalements actifs marqués "à éviter" par [filters] ;
  ///   - les traversées diagonales (pénalisées pour limiter les coupes
  ///     à travers les bâtiments — voir [PedestrianConstraints.urban]).
  ///
  /// [constraints] : paramètres piétons (pénalité diagonale, pas grille).
  ///   Par défaut : [PedestrianConstraints.urban] (zone urbaine dense).
  static List<RouteResult> computeRoutes({
    required LatLng start,
    required LatLng end,
    required AvoidanceFilters filters,
    PedestrianConstraints constraints = PedestrianConstraints.urban,
  }) {
    // 1) Récupère les signalements ACTIFS et VISIBLES (>3 votes).
    final alerts = AlertVisibilityPolicy.filterVisible(
      HiveAlertDatabase.instance.getAllValid(),
    );

    // 2) Construit la grille de cellules + leurs poids.
    //    La grille utilise les contraintes piétonnes pour pénaliser
    //    les arêtes diagonales (anti-traversée de bâtiments).
    final grid = _Grid.build(
      start: start,
      end: end,
      alerts: alerts,
      filters: filters,
      constraints: constraints,
    );

    // 3) Calcule l'itinéraire principal (Dijkstra).
    final primary = _dijkstra(grid, grid.startIdx, grid.endIdx, jitter: 0.0);
    if (primary == null || primary.points.isEmpty) {
      return const <RouteResult>[];
    }

    final results = <RouteResult>[
      RouteResult(
        id: 'primary',
        points: primary.points,
        totalDistanceMeters: primary.distance,
        totalRiskScore: primary.risk,
        pois: const <RoutePoi>[],
        // Étiquette précisant le mode de routage piéton
        label: 'Itinéraire piéton recommandé',
      ),
    ];

    // 4) Génère des alternatives en perturbant les poids.
    int altIndex = 1;
    final seen = <String>{_signature(primary.points)};
    final random = math.Random(42); // graine stable = reproductibilité
    for (int attempt = 0;
        altIndex < maxAlternatives && attempt < 6;
        attempt++) {
      final jitter =
          1.0 + alternativesJitter * (random.nextDouble() - 0.5) * 2;
      final alt =
          _dijkstra(grid, grid.startIdx, grid.endIdx, jitter: jitter);
      if (alt == null || alt.points.isEmpty) continue;
      final sig = _signature(alt.points);
      if (seen.contains(sig)) continue;
      seen.add(sig);
      results.add(
        RouteResult(
          id: 'alt$altIndex',
          points: alt.points,
          totalDistanceMeters: alt.distance,
          totalRiskScore: alt.risk,
          pois: const <RoutePoi>[],
          label: 'Alternative $altIndex',
        ),
      );
      altIndex++;
    }

    if (kDebugMode) {
      debugPrint(
          '[SafePathEngine] ${results.length} itinéraire(s) calculé(s)');
      for (final r in results) {
        debugPrint(
            '  - ${r.label}: ${r.distanceLabel} risk=${r.totalRiskScore.toStringAsFixed(0)}');
      }
    }

    return results;
  }

  // ============================================================================
  // Algorithme de Dijkstra
  // ============================================================================

  static _DijkstraResult? _dijkstra(
    _Grid grid,
    int startIdx,
    int endIdx, {
    required double jitter,
  }) {
    final n = grid.cells.length;
    final dist = List<double>.filled(n, double.infinity);
    final prev = List<int?>.filled(n, null);
    final visited = List<bool>.filled(n, false);
    dist[startIdx] = 0;

    final edgeRandom = math.Random(7);
    for (int iter = 0; iter < n; iter++) {
      // Trouve l'indice non-visité de plus petite distance.
      int? u;
      double best = double.infinity;
      for (int i = 0; i < n; i++) {
        if (!visited[i] && dist[i] < best) {
          best = dist[i];
          u = i;
        }
      }
      if (u == null) break;
      if (u == endIdx) break;
      visited[u] = true;

      // Relaxation des voisins.
      for (final edge in grid.adjacency[u]) {
        final v = edge.to;
        if (visited[v]) continue;
        final w = edge.weight;
        final noisy = jitter > 0
            ? w * (1.0 + (edgeRandom.nextDouble() - 0.5) * jitter)
            : w;
        final alt = dist[u] + noisy;
        if (alt < dist[v]) {
          dist[v] = alt;
          prev[v] = u;
        }
      }
    }

    if (dist[endIdx] == double.infinity) return null;

    // Reconstruit le chemin.
    final path = <int>[];
    int? cur = endIdx;
    while (cur != null) {
      path.insert(0, cur);
      cur = prev[cur];
    }
    final points = path.map((i) => grid.cells[i].point).toList();
    double totalDist = 0;
    double totalRisk = 0;
    for (int i = 1; i < path.length; i++) {
      final a = grid.cells[path[i - 1]].point;
      final b = grid.cells[path[i]].point;
      totalDist += GeofencingService.distanceBetween(a, b);
      totalRisk += grid.cells[path[i - 1]].riskWeight;
    }
    return _DijkstraResult(
      points: points,
      distance: totalDist,
      risk: totalRisk,
    );
  }

  /// Signature grossière d'un chemin (utilisée pour dédupliquer
  /// les alternatives trop similaires).
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

// ============================================================================
// Structures internes
// ============================================================================

class _DijkstraResult {
  _DijkstraResult({
    required this.points,
    required this.distance,
    required this.risk,
  });
  final List<LatLng> points;
  final double distance;
  final double risk;
}

class _GridCell {
  _GridCell(this.point, this.riskWeight);
  final LatLng point;
  final double riskWeight;
}

class _Edge {
  _Edge(this.to, this.weight, this.seed);
  final int to;
  final double weight;
  final int seed;
}

class _Grid {
  _Grid({
    required this.cells,
    required this.adjacency,
    required this.startIdx,
    required this.endIdx,
  });

  final List<_GridCell> cells;
  final List<List<_Edge>> adjacency;
  final int startIdx;
  final int endIdx;

  /// Padding (en degrés) ajouté à la BBox pour ne pas coller
  /// le calcul sur les bords de la zone A-B.
  static double _bboxPaddingDeg(LatLng a, LatLng b) {
    final dist = GeofencingService.distanceBetween(a, b);
    final degPad = (dist * 0.15) / 111320.0;
    return degPad < 0.0005 ? 0.0005 : degPad;
  }

  /// Renvoie le POIDS DE RISQUE associé à un point de la grille.
  /// * valeur élevée (> 1e10) → cellule bloquante (on n'émettra
  ///   pas d'arête vers/depuis cette cellule).
  /// * `> 0` mais raisonnable → pénalité douce (on s'en éloigne).
  /// * `0` → pas de risque.
  static double _riskAt(
    LatLng point,
    List<Alert> alerts,
    AvoidanceFilters filters,
  ) {
    double penalty = 0;
    for (final a in alerts) {
      final dist = GeofencingService.distanceBetween(
        point,
        LatLng(a.latitude, a.longitude),
      );
      if (!filters.shouldAvoid(a.type)) {
        // Danger accepté → pénalité douce (on s'éloigne si possible).
        if (dist < SafePathEngine.softPenaltyRadiusMeters) {
          final factor =
              1.0 - (dist / SafePathEngine.softPenaltyRadiusMeters);
          penalty += SafePathEngine.softPenaltyWeight * factor;
        }
      } else {
        // Danger à éviter → bloquant dans le rayon d'influence.
        if (dist < SafePathEngine.dangerRadiusMeters) {
          return 1.0e12;
        }
      }
    }
    return penalty;
  }

  static _Grid build({
    required LatLng start,
    required LatLng end,
    required List<Alert> alerts,
    required AvoidanceFilters filters,
    PedestrianConstraints constraints = PedestrianConstraints.urban,
  }) {
    // 1) Calcule la BBox englobante (avec padding).
    final pad = _bboxPaddingDeg(start, end);
    final minLat = math.min(start.latitude, end.latitude) - pad;
    final maxLat = math.max(start.latitude, end.latitude) + pad;
    final minLng = math.min(start.longitude, end.longitude) - pad;
    final maxLng = math.max(start.longitude, end.longitude) + pad;

    // 2) Échantillonne à pas régulier (en mètres).
    //    On utilise le pas défini dans [constraints] (défaut 20 m),
    //    sauf si SafePathEngine.gridStepMeters est plus petit.
    final effectiveStep = math.min(
      SafePathEngine.gridStepMeters,
      constraints.gridStepMeters,
    );
    final midLat = (minLat + maxLat) / 2;
    final metersPerDegLat = 111320.0;
    final metersPerDegLng =
        111320.0 * math.cos(midLat * math.pi / 180.0);

    final stepLat = effectiveStep / metersPerDegLat;
    final stepLng = effectiveStep /
        (metersPerDegLng.abs().clamp(1000, 1e9).toDouble());

    final latCount = ((maxLat - minLat) / stepLat).ceil().clamp(2, 200);
    final lngCount = ((maxLng - minLng) / stepLng).ceil().clamp(2, 200);

    final cells = <_GridCell>[];

    for (int i = 0; i < latCount; i++) {
      for (int j = 0; j < lngCount; j++) {
        final lat = minLat + (i + 0.5) * stepLat;
        final lng = minLng + (j + 0.5) * stepLng;
        final point = LatLng(lat, lng);
        cells.add(_GridCell(point, _riskAt(point, alerts, filters)));
      }
    }

    int idx(int i, int j) => i * lngCount + j;
    int startIdx = -1;
    int endIdx = -1;
    double bestStart = double.infinity;
    double bestEnd = double.infinity;
    for (int i = 0; i < latCount; i++) {
      for (int j = 0; j < lngCount; j++) {
        final c = cells[idx(i, j)];
        final dS = GeofencingService.distanceBetween(c.point, start);
        final dE = GeofencingService.distanceBetween(c.point, end);
        if (dS < bestStart) {
          bestStart = dS;
          startIdx = idx(i, j);
        }
        if (dE < bestEnd) {
          bestEnd = dE;
          endIdx = idx(i, j);
        }
      }
    }

    if (startIdx < 0 || endIdx < 0) {
      return _Grid(
        cells: cells,
        adjacency: const [],
        startIdx: 0,
        endIdx: 0,
      );
    }

    // 3) Construit l'adjacence (8-voisinage) avec PÉNALITÉ PIÉTONNE.
    //
    //    ROUTAGE PIÉTON — ANTI-TRAVERSÉE DE BÂTIMENTS :
    //    Les arêtes DIAGONALES (NE, NW, SE, SW) sont multipliées par
    //    `constraints.diagonalPenaltyFactor` (défaut 3.5 en zone urbaine).
    //    Cela force l'algorithme à préférer les connexions orthogonales
    //    (N, S, E, W) qui suivent généralement la voirie.
    //
    //    Une arête diagonale coûte donc ~3.5× plus qu'une arête droite
    //    de même distance, ce qui dissuade fortement les coupes en biais
    //    à travers les pâtés de maisons.

    final adjacency = List<List<_Edge>>.generate(
      cells.length,
      (_) => <_Edge>[],
      growable: false,
    );

    // Voisins orthogonaux (Cardinal : N, S, E, W) — pas de pénalité piétonne.
    const cardinalNeighbors = [
      [0, 1],   // Est
      [1, 0],   // Sud
      [0, -1],  // Ouest
      [-1, 0],  // Nord
    ];

    // Voisins diagonaux (NE, SE, SW, NW) — pénalisés × diagonalPenaltyFactor.
    const diagonalNeighbors = [
      [1, 1],   // Sud-Est
      [1, -1],  // Sud-Ouest
      [-1, 1],  // Nord-Est
      [-1, -1], // Nord-Ouest
    ];

    int edgeSeed = 0;
    for (int i = 0; i < latCount; i++) {
      for (int j = 0; j < lngCount; j++) {
        final from = idx(i, j);
        // Si la cellule SOURCE est bloquante, on ignore ses arêtes.
        if (cells[from].riskWeight >= 1.0e10) continue;
        final cFrom = cells[from].point;

        // ── Arêtes orthogonales (poids normal) ────────────────────────────
        for (final d in cardinalNeighbors) {
          final ni = i + d[0];
          final nj = j + d[1];
          if (ni < 0 || ni >= latCount || nj < 0 || nj >= lngCount) continue;
          final to = idx(ni, nj);
          if (cells[to].riskWeight >= 1.0e10) continue;
          final cTo = cells[to].point;
          final baseDist = GeofencingService.distanceBetween(cFrom, cTo);
          // Poids = distance (m) + risque cellule destination.
          final w = baseDist + cells[to].riskWeight;
          adjacency[from].add(_Edge(to, w, edgeSeed++));
        }

        // ── Arêtes diagonales (pénalité piétonne × diagonalPenaltyFactor) ─
        // Ces arêtes sont autorisées mais coûteuses pour que l'algorithme
        // les évite sauf si aucune alternative orthogonale n'existe.
        for (final d in diagonalNeighbors) {
          final ni = i + d[0];
          final nj = j + d[1];
          if (ni < 0 || ni >= latCount || nj < 0 || nj >= lngCount) continue;
          final to = idx(ni, nj);
          if (cells[to].riskWeight >= 1.0e10) continue;
          final cTo = cells[to].point;
          final baseDist = GeofencingService.distanceBetween(cFrom, cTo);
          // Poids diagonal = distance physique × facteur de pénalité piétonne
          // + risque cellule destination.
          final w = baseDist * constraints.diagonalPenaltyFactor
              + cells[to].riskWeight;
          adjacency[from].add(_Edge(to, w, edgeSeed++));
        }
      }
    }

    return _Grid(
      cells: cells,
      adjacency: adjacency,
      startIdx: startIdx,
      endIdx: endIdx,
    );
  }
}
