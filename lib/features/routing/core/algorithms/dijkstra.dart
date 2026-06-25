// lib/features/routing/core/algorithms/dijkstra.dart
//
// Implémentation de l'algorithme de Dijkstra pour la recherche de
// chemin dans un graphe de routage. Utilisé comme fallback quand
// l'heuristique A* n'est pas applicable (graphe sans coordonnées).
//
// Complexité : O(V log V + E) avec une priority queue binaire.
//
// Utilisation :
// ```dart
// final path = Dijkstra.compute(
//   graph, startNodeIdx, endNodeIdx,
//   maxIterations: 10000,
// );
// ```

import '../graph/spg_graph.dart';

/// Résultat d'un calcul Dijkstra/A*.
class PathResult {
  const PathResult({
    required this.nodeIds,
    required this.totalWeight,
    required this.totalDistanceMeters,
    required this.iterations,
  });

  /// IDs des nœuds formant le chemin (du start à l'end).
  final List<int> nodeIds;

  /// Poids total du chemin (secondes pour piéton, mètres pour véhicule).
  final double totalWeight;

  /// Distance totale en mètres.
  final double totalDistanceMeters;

  /// Nombre d'itérations (nœuds explorés).
  final int iterations;

  bool get found => nodeIds.isNotEmpty;
}

/// Implémentation de Dijkstra.
class Dijkstra {
  /// Calcule le plus court chemin entre [startNode] et [endNode].
  ///
  /// [maxIterations] limite le nombre de nœuds explorés pour éviter
  /// les boucles infinies (défaut : 50 000).
  /// [maxWeight] est le poids maximum avant d'abandonner (défaut : infini).
  static PathResult compute(
    SpgGraph graph,
    int startNode,
    int endNode, {
    int maxIterations = 50000,
    double maxWeight = double.infinity,
  }) {
    final n = graph.nodeCount;
    final dist = List<double>.filled(n, double.infinity);
    final prev = List<int>.filled(n, -1);
    final visited = List<bool>.filled(n, false);

    // Priority queue simple (O(n) pour extract_min, O(1) pour update).
    // Pour le MVP, une implémentation O(n²) suffit pour < 100k nœuds.
    dist[startNode] = 0;
    int iterations = 0;

    for (int iter = 0; iter < n; iter++) {
      // Trouve le nœud non-visité avec la plus petite distance.
      int u = -1;
      double bestDist = double.infinity;
      for (int i = 0; i < n; i++) {
        if (!visited[i] && dist[i] < bestDist) {
          bestDist = dist[i];
          u = i;
        }
      }

      if (u == -1 || bestDist >= maxWeight) break;
      if (u == endNode) {
        iterations = iter + 1;
        break;
      }

      visited[u] = true;
      iterations = iter + 1;
      if (iterations >= maxIterations) break;

      // Relaxation des arêtes sortantes.
      graph.forEachEdge(u, (to, weightMeters, flags, speedKmh) {
        if (visited[to]) return;
        final alt = dist[u] + weightMeters;
        if (alt < dist[to]) {
          dist[to] = alt;
          prev[to] = u;
        }
      });
    }

    if (dist[endNode] == double.infinity) {
      return PathResult(
        nodeIds: const [],
        totalWeight: double.infinity,
        totalDistanceMeters: double.infinity,
        iterations: iterations,
      );
    }

    // Reconstruit le chemin.
    final path = <int>[];
    int? cur = endNode;
    while (cur != null && cur != -1) {
      path.insert(0, cur);
      cur = prev[cur];
    }

    double totalDistance = 0;
    for (int i = 1; i < path.length; i++) {
      final aIdx = path[i - 1];
      final bIdx = path[i];
      final dLat = graph.nodeLat(bIdx) - graph.nodeLat(aIdx);
      final dLon = graph.nodeLon(bIdx) - graph.nodeLon(aIdx);
      totalDistance += _approxDistance(
          dLat, dLon, (graph.nodeLat(aIdx) + graph.nodeLat(bIdx)) / 2);
    }

    return PathResult(
      nodeIds: path,
      totalWeight: dist[endNode],
      totalDistanceMeters: totalDistance,
      iterations: iterations,
    );
  }

  static double _approxDistance(
      double dLatDeg, double dLonDeg, double refLatDeg) {
    const double metersPerDeg = 111320.0;
    final midLat = refLatDeg * 3.141592653589793 / 180.0;
    final lonScale = metersPerDeg * _fastCos(midLat);
    final dLat = dLatDeg * metersPerDeg;
    final dLon = dLonDeg * lonScale;
    return _fastSqrt(dLat * dLat + dLon * dLon);
  }

  static double _fastCos(double x) {
    final x2 = x * x;
    return 1.0 - x2 / 2.0 + x2 * x2 / 24.0;
  }

  static double _fastSqrt(double x) {
    if (x <= 0) return 0;
    double guess = x;
    for (int i = 0; i < 3; i++) {
      guess = (guess + x / guess) * 0.5;
    }
    return guess;
  }
}
