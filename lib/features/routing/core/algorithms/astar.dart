// lib/features/routing/core/algorithms/astar.dart
//
// Implémentation de l'algorithme A* bidirectionnel pour la recherche
// de chemin dans un graphe de routage OSM.
//
// Principe :
//   - Recherche simultanée depuis le départ (forward) et l'arrivée (backward)
//   - Heuristique : distance Haversine au nœud opposé
//   - Arrêt : quand les deux fronts se rencontrent
//   - Complexité : O(b^(d/2)) vs O(b^d) pour A* unidirectionnel
//
// Utilisation :
// ```dart
// final result = Astar.compute(graph, startIdx, endIdx, profile: ProfileSettings.pedestrian);
// ```

import 'dart:math' as math;

import '../graph/spg_graph.dart';
import '../graph/spg_types.dart';
import '../models/routing_profile.dart';
import 'dijkstra.dart';

/// Résultat du calcul A*.
class AstarResult {
  const AstarResult({
    required this.path,
    required this.totalWeight,
    required this.totalDistanceMeters,
    required this.nodesExplored,
  });

  /// Chemin trouvé (vide si aucun chemin).
  final PathResult path;

  /// Poids total (secondes pour piéton).
  final double totalWeight;

  /// Distance totale en mètres.
  final double totalDistanceMeters;

  /// Nombre de nœuds explorés (forward + backward).
  final int nodesExplored;

  bool get found => path.found;
}

/// Implémentation de l'A* bidirectionnel.
class Astar {
  /// Calcule le plus court chemin entre [startNode] et [endNode].
  ///
  /// Utilise l'heuristique Haversine pour guider la recherche.
  /// [profile] définit les poids des arêtes (piéton, vélo, etc.).
  /// [maxNodes] limite le nombre de nœuds explorés (défaut : 20 000).
  static AstarResult compute(
    SpgGraph graph,
    int startNode,
    int endNode, {
    ProfileSettings profile = ProfileSettings.pedestrian,
    int maxNodes = 20000,
    List<RoutingAvoidPoint> avoidPoints = const [],
  }) {
    if (startNode == endNode) {
      final path = PathResult(
        nodeIds: [startNode],
        totalWeight: 0,
        totalDistanceMeters: 0,
        iterations: 0,
      );
      return AstarResult(
        path: path,
        totalWeight: 0,
        totalDistanceMeters: 0,
        nodesExplored: 0,
      );
    }

    final n = graph.nodeCount;

    // Données forward (depuis start)
    final fDist = List<double>.filled(n, double.infinity);
    final fHeuristic = List<double>.filled(n, double.infinity);
    final fPrev = List<int>.filled(n, -1);
    final fVisited = List<bool>.filled(n, false);

    // Données backward (depuis end)
    final bDist = List<double>.filled(n, double.infinity);
    final bHeuristic = List<double>.filled(n, double.infinity);
    final bPrev = List<int>.filled(n, -1);
    final bVisited = List<bool>.filled(n, false);

    fDist[startNode] = 0;
    fHeuristic[startNode] = _haversineHeuristic(graph, startNode, endNode);
    bDist[endNode] = 0;
    bHeuristic[endNode] = _haversineHeuristic(graph, endNode, startNode);

    int nodesExplored = 0;
    double bestPathWeight = double.infinity;
    int meetingNode = -1;

    // Boucle principale : alterne forward et backward.
    for (int iter = 0; iter < maxNodes && iter < n; iter++) {
      // Phase forward : choisir le nœud forward non visité avec la meilleure
      // valeur f = g + h.
      final fU =
          _selectNode(fDist, fHeuristic, fVisited, bestPathWeight);
      if (fU != -1) {
        fVisited[fU] = true;
        nodesExplored++;

        // Vérifie si fU a été visité en backward
        if (bVisited[fU]) {
          final candidateWeight = fDist[fU] + bDist[fU];
          if (candidateWeight < bestPathWeight) {
            bestPathWeight = candidateWeight;
            meetingNode = fU;
          }
        }

        // Relaxation des arêtes sortantes depuis fU.
        graph.forEachEdge(fU, (to, weightMeters, flags, speedKmh) {
          if (fVisited[to]) return;
          if (!_edgeAllowed(flags, profile)) return;
          final w = _edgeCost(weightMeters, speedKmh, profile);
          final alt = fDist[fU] + w + _avoidPenalty(graph, to, avoidPoints);
          if (alt < fDist[to]) {
            fDist[to] = alt;
            fHeuristic[to] = alt +
                _haversineHeuristic(graph, to, endNode) *
                    profile.heuristicWeight;
            fPrev[to] = fU;
          }
        });
      }

      // Phase backward : choisir le nœud backward non visité avec la meilleure
      // valeur f = g + h.
      final bU =
          _selectNode(bDist, bHeuristic, bVisited, bestPathWeight);
      if (bU != -1) {
        bVisited[bU] = true;
        nodesExplored++;

        if (fVisited[bU]) {
          final candidateWeight = fDist[bU] + bDist[bU];
          if (candidateWeight < bestPathWeight) {
            bestPathWeight = candidateWeight;
            meetingNode = bU;
          }
        }

        // Relaxation des arêtes entrantes vers bU (on itère tous les nœuds).
        for (int v = 0; v < n; v++) {
          if (bVisited[v]) continue;
          graph.forEachEdge(v, (to, weightMeters, flags, speedKmh) {
            if (to != bU) return;
            if (!_edgeAllowed(flags, profile)) return;
            final w = _edgeCost(weightMeters, speedKmh, profile);
            final alt = bDist[bU] + w + _avoidPenalty(graph, v, avoidPoints);
            if (alt < bDist[v]) {
              bDist[v] = alt;
              bHeuristic[v] = alt +
                  _haversineHeuristic(graph, v, startNode) *
                      profile.heuristicWeight;
              bPrev[v] = bU;
            }
          });
        }
      }

      // Condition d'arrêt : les deux fronts ont dépassé le meilleur chemin.
      final fMin = _minHeuristic(fHeuristic, fVisited);
      final bMin = _minHeuristic(bHeuristic, bVisited);
      if (fMin + bMin >= bestPathWeight && meetingNode != -1) {
        break;
      }

      if (fU == -1 && bU == -1) break;
    }

    // Reconstruit le chemin complet.
    if (meetingNode == -1) {
      // Fallback : Dijkstra unidirectionnel.
      final dijkstraResult = Dijkstra.compute(
        graph,
        startNode,
        endNode,
        maxIterations: maxNodes,
        avoidPoints: avoidPoints,
      );
      return AstarResult(
        path: dijkstraResult,
        totalWeight: dijkstraResult.totalWeight,
        totalDistanceMeters: dijkstraResult.totalDistanceMeters,
        nodesExplored: nodesExplored,
      );
    }

    // Chemin forward : startNode → meetingNode.
    final forwardPath = <int>[];
    int cur = meetingNode;
    while (cur != -1) {
      forwardPath.insert(0, cur);
      cur = fPrev[cur];
    }

    // Chemin backward : meetingNode → endNode (sans le doublon).
    final backwardPath = <int>[];
    cur = bPrev[meetingNode];
    while (cur != -1) {
      backwardPath.add(cur);
      cur = bPrev[cur];
    }

    final fullPath = [...forwardPath, ...backwardPath];

    double totalDistance = 0;
    for (int i = 1; i < fullPath.length; i++) {
      final aIdx = fullPath[i - 1];
      final bIdx = fullPath[i];
      final dLat = graph.nodeLat(bIdx) - graph.nodeLat(aIdx);
      final dLon = graph.nodeLon(bIdx) - graph.nodeLon(aIdx);
      totalDistance += _approxDistance(
          dLat, dLon, (graph.nodeLat(aIdx) + graph.nodeLat(bIdx)) / 2);
    }

    final pathResult = PathResult(
      nodeIds: fullPath,
      totalWeight: bestPathWeight,
      totalDistanceMeters: totalDistance,
      iterations: nodesExplored,
    );

    return AstarResult(
      path: pathResult,
      totalWeight: bestPathWeight,
      totalDistanceMeters: totalDistance,
      nodesExplored: nodesExplored,
    );
  }

  /// Indique si une arête (décrite par ses [flags]) est traversable pour un
  /// [profile] donné. Différencie piéton/vélo et véhicule/urgence :
  ///   - Piéton/vélo : autorise escaliers, pistes cyclables et chemins, et
  ///     IGNORE les sens interdits (marche à contre-sens autorisée) ;
  ///     refuse seulement les autoroutes/voies rapides.
  ///   - Véhicule/urgence : refuse escaliers, pistes cyclables et chemins,
  ///     et RESPECTE les sens interdits.
  static bool _edgeAllowed(int flags, ProfileSettings profile) {
    final isMotorized = profile.walkSpeedMs <= 0;
    if (EdgeFlags.has(flags, EdgeFlags.stairs)) {
      if (isMotorized || profile.avoidStairs) return false;
    }
    if (EdgeFlags.has(flags, EdgeFlags.cycleway)) {
      if (isMotorized) return false;
    }
    if (EdgeFlags.has(flags, EdgeFlags.highway)) {
      if (!isMotorized) return false;
    }
    // Le flag `oneway` n'interdit PAS la traversée de l'arête : le sens
    // unique est déjà encodé par l'orientation du graphe .spg (une rue à
    // sens unique A→B ne possède PAS d'arête inverse B→A). Refuser
    // l'arête ici (comme avant) empêcherait les véhicules d'emprunter
    // toute rue à sens unique, même dans le bon sens.
    if (EdgeFlags.has(flags, EdgeFlags.unpaved)) {
      if (profile.avoidUnpaved) return false;
    }
    return true;
  }

  /// Coût de franchissement d'une arête pour un [profile] donné.
  ///
  /// - Piéton / vélo : temps de parcours (distance / vitesse de marche), avec
  ///   une forte pénalité sur les voies rapides (≥ 30 km/h) pour éviter les
  ///   grands axes.
  /// - Véhicule / urgence : temps de conduite (distance / vitesse réelle de la
  ///   voie), plafonné à [ProfileSettings.maxSpeedKmh].
  static double _edgeCost(
    double weightMeters,
    int speedKmh,
    ProfileSettings profile,
  ) {
    if (profile.walkSpeedMs > 0) {
      double cost = weightMeters / profile.walkSpeedMs;
      if (speedKmh >= 30) cost *= profile.penaltyFactorDiagonal;
      return cost;
    }
    final effectiveKmh = speedKmh > 0
        ? math.min(speedKmh.toDouble(), profile.maxSpeedKmh)
        : 30.0;
    return weightMeters / (effectiveKmh / 3.6);
  }

  /// Sélectionne le nœud non visité avec la meilleure valeur f = g + h.
  static int _selectNode(
    List<double> dist,
    List<double> heuristic,
    List<bool> visited,
    double bestPathWeight,
  ) {
    int best = -1;
    double bestVal = double.infinity;
    final n = dist.length;
    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;
      if (heuristic[i] >= bestPathWeight) continue;
      if (heuristic[i] < bestVal) {
        bestVal = heuristic[i];
        best = i;
      }
    }
    return best;
  }

  /// Calcule l'heuristique Haversine entre deux nœuds du graphe.
  static double _haversineHeuristic(SpgGraph graph, int fromIdx, int toIdx) {
    final lat1 = graph.nodeLat(fromIdx) * math.pi / 180.0;
    final lat2 = graph.nodeLat(toIdx) * math.pi / 180.0;
    final dLat =
        (graph.nodeLat(toIdx) - graph.nodeLat(fromIdx)) * math.pi / 180.0;
    final dLon =
        (graph.nodeLon(toIdx) - graph.nodeLon(fromIdx)) * math.pi / 180.0;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return 6371000.0 * c;
  }

  /// Minimum des valeurs heuristiques parmi les nœuds non visités.
  static double _minHeuristic(List<double> heuristic, List<bool> visited) {
    double minVal = double.infinity;
    for (int i = 0; i < heuristic.length; i++) {
      if (!visited[i] && heuristic[i] < minVal) {
        minVal = heuristic[i];
      }
    }
    return minVal;
  }

  /// Pénalité d'évitement appliquée à un nœud proche d'un point à éviter.
  /// Retourne une valeur très élevée (blocage quasi-total) si le nœud se
  /// trouve dans le rayon d'influence d'un danger.
  static double _avoidPenalty(
    SpgGraph graph,
    int nodeIdx,
    List<RoutingAvoidPoint> avoidPoints,
  ) {
    if (avoidPoints.isEmpty) return 0;
    final lat = graph.nodeLat(nodeIdx);
    final lon = graph.nodeLon(nodeIdx);
    double penalty = 0;
    for (final p in avoidPoints) {
      final dist = _approxDistance(lat - p.lat, lon - p.lon, (lat + p.lat) / 2);
      if (dist < p.radiusMeters) {
        penalty += 1.0e9;
      }
    }
    return penalty;
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
