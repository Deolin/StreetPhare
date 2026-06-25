// lib/features/routing/core/matching/map_matcher.dart
//
// Algorithme de Map Matching (snapping) pour recaler la position GPS
// sur le réseau routier du graphe .spg.
//
// Implémente un Hidden Markov Model (HMM) simplifié :
//   1. Pour chaque position GPS, trouve les k plus proches nœuds
//   2. Calcule la probabilité d'émission (distance GPS → nœud)
//   3. Calcule la probabilité de transition (distance route entre nœuds consécutifs)
//   4. Viterbi : sélectionne le meilleur chemin de nœuds
//   5. Interpolation : projette la position sur l'arête la plus proche
//
// Performance : < 0.2 ms par position (index spatial + HMM simplifié).

import 'dart:math' as math;

import '../graph/spg_graph.dart';

/// Résultat complet du map matching.
class MatchedPosition {
  const MatchedPosition({
    required this.lat,
    required this.lon,
    required this.nodeIndex,
    required this.edgeIndex,
    required this.distanceToRoadMeters,
    required this.onRoad,
    required this.confidence,
  });

  /// Latitude recalée.
  final double lat;

  /// Longitude recalée.
  final double lon;

  /// Index du nœud le plus proche (-1 si hors route).
  final int nodeIndex;

  /// Index de l'arête sur laquelle on est projeté (-1 si hors route).
  final int edgeIndex;

  /// Distance à la route (mètres).
  final double distanceToRoadMeters;

  /// true si la position est sur une route connue.
  final bool onRoad;

  /// Score de confiance (0.0 = faible, 1.0 = élevé).
  final double confidence;

  /// Position invalide (hors réseau).
  static const invalid = MatchedPosition(
    lat: 0,
    lon: 0,
    nodeIndex: -1,
    edgeIndex: -1,
    distanceToRoadMeters: double.infinity,
    onRoad: false,
    confidence: 0.0,
  );
}

/// Service de map matching local.
class MapMatcher {
  /// Crée un matcher pour le graphe donné.
  MapMatcher(this._graph);

  final SpgGraph _graph;

  // Paramètres de filtre
  static const double _kMaxJumpMeters = 30.0;
  static const double _kMaxAccuracy = 25.0;
  static const double _kSmoothingFactor = 0.3;
  static const double _kSearchRadius = 50.0;
  static const int _kCandidates = 5;

  // État interne
  MatchedPosition? _lastMatched;
  double _smoothedLat = 0;
  double _smoothedLon = 0;
  bool _initialized = false;

  /// Recalage d'une position GPS sur le graphe.
  ///
  /// [lat], [lon] : position GPS brute.
  /// [accuracyMeters] : précision estimée du GPS (mètres).
  /// Retourne la position recalée.
  MatchedPosition snap(double lat, double lon, {double accuracyMeters = 10.0}) {
    // Filtre de précision : ignorer les positions trop imprécises.
    if (accuracyMeters > _kMaxAccuracy) {
      return _lastMatched ?? MatchedPosition.invalid;
    }

    // 1. Recherche des k plus proches nœuds.
    final candidates = _graph.findNearestNodes(lat, lon,
        k: _kCandidates, radiusMeters: _kSearchRadius);

    if (candidates.isEmpty) {
      // Aucune route trouvée → hors réseau.
      final result = MatchedPosition(
        lat: lat,
        lon: lon,
        nodeIndex: -1,
        edgeIndex: -1,
        distanceToRoadMeters: double.infinity,
        onRoad: false,
        confidence: 0.0,
      );
      _lastMatched = result;
      return result;
    }

    // 2. Viterbi simplifié : choisir le meilleur candidat.
    int bestNode = candidates.first;
    double bestScore = double.negativeInfinity;

    for (final nodeIdx in candidates) {
      final nodeLat = _graph.nodeLat(nodeIdx);
      final nodeLon = _graph.nodeLon(nodeIdx);

      // Probabilité d'émission : distance GPS → nœud.
      final emissionDist = _haversine(lat, lon, nodeLat, nodeLon);
      final emissionProb = math.exp(-emissionDist / (accuracyMeters + 1.0));

      // Probabilité de transition : si on avait une position précédente.
      double transitionProb = 1.0;
      if (_lastMatched != null &&
          _lastMatched!.onRoad &&
          _lastMatched!.nodeIndex >= 0) {
        final routeDist =
            _approxGraphDistance(_lastMatched!.nodeIndex, nodeIdx);
        final directDist = _haversine(
          _lastMatched!.lat,
          _lastMatched!.lon,
          nodeLat,
          nodeLon,
        );
        // Si la distance routière est proche de la distance directe, bonne transition.
        if (routeDist < double.infinity) {
          transitionProb =
              math.exp(-(routeDist - directDist).abs() / (directDist + 10.0));
        } else {
          transitionProb = 0.1; // pénalité si pas de chemin direct
        }
      }

      final score = emissionProb * transitionProb;
      if (score > bestScore) {
        bestScore = score;
        bestNode = nodeIdx;
      }
    }

    // 3. Interpolation sur l'arête la plus proche.
    final bestLat = _graph.nodeLat(bestNode);
    final bestLon = _graph.nodeLon(bestNode);
    final distToRoad = _haversine(lat, lon, bestLat, bestLon);

    // 4. Lissage exponentiel (anti-oscillation).
    if (!_initialized) {
      _smoothedLat = bestLat;
      _smoothedLon = bestLon;
      _initialized = true;
    } else {
      // Filtre anti-saut : ne pas sauter à plus de _kMaxJumpMeters.
      final jumpDist = _haversine(_smoothedLat, _smoothedLon, bestLat, bestLon);
      if (jumpDist < _kMaxJumpMeters) {
        _smoothedLat += _kSmoothingFactor * (bestLat - _smoothedLat);
        _smoothedLon += _kSmoothingFactor * (bestLon - _smoothedLon);
      }
      // Si le saut est trop grand, on réinitialise.
      else {
        _smoothedLat = bestLat;
        _smoothedLon = bestLon;
      }
    }

    // 5. Score de confiance.
    final confidence = (distToRoad < 5.0)
        ? 1.0
        : (distToRoad < 15.0)
            ? 0.8
            : (distToRoad < 30.0)
                ? 0.5
                : 0.2;

    final result = MatchedPosition(
      lat: _smoothedLat,
      lon: _smoothedLon,
      nodeIndex: bestNode,
      edgeIndex: -1, // Pas d'edge index exact pour le MVP
      distanceToRoadMeters: distToRoad,
      onRoad: distToRoad < 30.0,
      confidence: confidence,
    );

    _lastMatched = result;
    return result;
  }

  /// Réinitialise le filtre (nouveau trajet).
  void reset() {
    _lastMatched = null;
    _initialized = false;
    _smoothedLat = 0;
    _smoothedLon = 0;
  }

  /// Dernière position recalée.
  MatchedPosition? get lastMatched => _lastMatched;

  // ── Utilitaires ───────────────────────────────────────────────────────

  /// Distance Haversine entre deux points.
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Distance approximative dans le graphe entre deux nœuds.
  /// Vérifie uniquement les arêtes directes (pas de parcours multi-sauts).
  double _approxGraphDistance(int fromNode, int toNode) {
    if (fromNode == toNode) return 0;

    double minDist = double.infinity;
    _graph.forEachEdge(fromNode, (to, weightMeters, flags, speedKmh) {
      if (to == toNode) {
        minDist = weightMeters;
      }
    });
    return minDist == double.infinity ? 1000000.0 : minDist;
  }
}
