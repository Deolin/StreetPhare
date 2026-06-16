// lib/features/routing/core/graph/spg_graph.dart
//
// Graphe de routage chargé en mémoire (format .spg).
//
// Utilise des TypedData (Float64List, Uint32List, etc.) pour une
// compacité maximale et une transférabilité entre Isolates via
// SendPort (les TypedData sont des messages transferrables).
//
// Exemple d'utilisation :
// ```dart
// final graph = SpgGraph.load('regions/belgique.spg');
// final nearest = graph.findNearestNodes(start, end);
// final route = Astar.compute(graph, nearest.startNodeIndex, nearest.endNodeIndex);
// ```

import 'dart:typed_data';

import 'spg_types.dart';

/// Graphe de routage en mémoire.
class SpgGraph {
  SpgGraph({
    required this.header,
    required this.nodeLats,
    required this.nodeLons,
    required this.edgeStarts,
    required this.edgeCounts,
    required this.edgeTo,
    required this.edgeWeights,
    required this.edgeSpeeds,
    required this.edgeFlags,
    required this.spatialCells,
    required this.spatialNodeIds,
    required this.cellSizeDeg,
    required this.cellsX,
    required this.cellsY,
  });

  // ── Données du graphe ─────────────────────────────────────────────────

  /// Header du fichier .spg.
  final SpgHeader header;

  /// Latitudes des nœuds (Float64List, en degrés).
  final Float64List nodeLats;

  /// Longitudes des nœuds (Float64List, en degrés).
  final Float64List nodeLons;

  /// Pour chaque nœud, index de début dans edgeTo (Uint32List).
  final Uint32List edgeStarts;

  /// Pour chaque nœud, nombre d'arêtes (Uint8List).
  final Uint8List edgeCounts;

  /// Tableau plat des index destinations des arêtes (Uint32List).
  final Uint32List edgeTo;

  /// Tableau plat des poids des arêtes en mm (Uint16List).
  final Uint16List edgeWeights;

  /// Tableau plat des vitesses / 2 (Uint8List).
  final Uint8List edgeSpeeds;

  /// Tableau plat des flags (Uint8List).
  final Uint8List edgeFlags;

  // ── Index spatial (maillage fixe) ──────────────────────────────────────

  /// Cellules de l'index spatial : offset début dans spatialNodeIds.
  final Uint32List spatialCells;

  /// IDs des nœuds par cellule (concaténés).
  final Uint32List spatialNodeIds;

  /// Taille d'une cellule en degrés (~500 m).
  final double cellSizeDeg;

  /// Nombre de cellules en longitude.
  final int cellsX;

  /// Nombre de cellules en latitude.
  final int cellsY;

  // ── Accès aux nœuds ────────────────────────────────────────────────────

  int get nodeCount => header.nodeCount;
  int get edgeCount => header.edgeCount;

  /// Retourne la position LatLng d'un nœud.
  double nodeLat(int index) => nodeLats[index];
  double nodeLon(int index) => nodeLons[index];

  // ── Accès aux arêtes ───────────────────────────────────────────────────

  /// Itère sur les arêtes sortantes d'un nœud.
  void forEachEdge(int nodeIdx, void Function(int to, double weightMeters, int flags, int speedKmh) callback) {
    final start = edgeStarts[nodeIdx];
    final count = edgeCounts[nodeIdx];
    for (int i = 0; i < count; i++) {
      final idx = start + i;
      callback(
        edgeTo[idx],
        edgeWeights[idx] / 1000.0,
        edgeFlags[idx],
        edgeSpeeds[idx] * 2,
      );
    }
  }

  /// Retourne le poids en mètres d'une arête.
  double edgeWeightMeters(int edgeIdx) => edgeWeights[edgeIdx] / 1000.0;

  /// Retourne la vitesse en km/h d'une arête.
  int edgeSpeedKmh(int edgeIdx) => edgeSpeeds[edgeIdx] * 2;

  /// Vérifie si une arête a un flag spécifique.
  bool edgeHasFlag(int edgeIdx, int flag) => EdgeFlags.has(edgeFlags[edgeIdx], flag);

  // ── Calcul mémoire ────────────────────────────────────────────────────

  /// Empreinte mémoire estimée en octets.
  int get memoryBytes {
    return nodeLats.lengthInBytes +
        nodeLons.lengthInBytes +
        edgeStarts.lengthInBytes +
        edgeCounts.lengthInBytes +
        edgeTo.lengthInBytes +
        edgeWeights.lengthInBytes +
        edgeSpeeds.lengthInBytes +
        edgeFlags.lengthInBytes +
        spatialCells.lengthInBytes +
        spatialNodeIds.lengthInBytes;
  }

  /// Empreinte en mégaoctets.
  double get memoryMb => memoryBytes / (1024 * 1024);

  // ── Recherche spatiale ─────────────────────────────────────────────────

  /// Convertit une coordonnée en coordonnées de cellule.
  int _cellX(double lon) =>
      ((lon - header.minLon) / cellSizeDeg).floor().clamp(0, cellsX - 1);
  int _cellY(double lat) =>
      ((lat - header.minLat) / cellSizeDeg).floor().clamp(0, cellsY - 1);

  /// Index de cellule dans le tableau spatialCells.
  int _cellIndex(int cx, int cy) => cy * cellsX + cx;

  /// Trouve les k nœuds les plus proches d'une position.
  List<int> findNearestNodes(double lat, double lon, {int k = 5, double radiusMeters = 50.0}) {
    final cx = _cellX(lon);
    final cy = _cellY(lat);

    final results = <_Candidate>[];

    // Parcourt les cellules voisines (3×3).
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx < 0 || nx >= cellsX || ny < 0 || ny >= cellsY) continue;

        final cellStart = spatialCells[_cellIndex(nx, ny)];
        final cellEnd = (ny * cellsX + nx + 1 < spatialCells.length)
            ? spatialCells[ny * cellsX + nx + 1]
            : spatialNodeIds.length;

        for (int i = cellStart; i < cellEnd; i++) {
          final nodeIdx = spatialNodeIds[i];
          final dLat = nodeLats[nodeIdx] - lat;
          final dLon = nodeLons[nodeIdx] - lon;
          final dist = _approxDistance(dLat, dLon, lat);
          if (dist <= radiusMeters) {
            results.add(_Candidate(nodeIdx, dist));
          }
        }
      }
    }

    results.sort((a, b) => a.distance.compareTo(b.distance));
    return results.take(k).map((c) => c.nodeIdx).toList();
  }

  /// Distance Haversine approximative pour les courtes distances.
  static double _approxDistance(double dLatDeg, double dLonDeg, double refLatDeg) {
    const double metersPerDeg = 111320.0;
    final midLat = refLatDeg * 3.141592653589793 / 180.0;
    final lonScale = metersPerDeg * _fastCos(midLat);
    final dLat = dLatDeg * metersPerDeg;
    final dLon = dLonDeg * lonScale;
    return _fastSqrt(dLat * dLat + dLon * dLon);
  }

  /// Cosinus approximatif (polynôme de Taylor, précision 0.001).
  static double _fastCos(double x) {
    final x2 = x * x;
    return 1.0 - x2 / 2.0 + x2 * x2 / 24.0;
  }

  /// Racine carrée rapide (Newton-Raphson, 2 itérations).
  static double _fastSqrt(double x) {
    if (x <= 0) return 0;
    double guess = x;
    for (int i = 0; i < 3; i++) {
      guess = (guess + x / guess) * 0.5;
    }
    return guess;
  }

  /// Trouve le nœud le plus proche d'une position.
  NearestNodesResult findStartEndNodes(double startLat, double startLon, double endLat, double endLon) {
    final startNodes = findNearestNodes(startLat, startLon, k: 1, radiusMeters: 200);
    final endNodes = findNearestNodes(endLat, endLon, k: 1, radiusMeters: 200);

    return NearestNodesResult(
      startNodeIndex: startNodes.isNotEmpty ? startNodes.first : 0,
      endNodeIndex: endNodes.isNotEmpty ? endNodes.first : header.nodeCount - 1,
      startDistanceMeters: startNodes.isNotEmpty
          ? _approxDistance(nodeLats[startNodes.first] - startLat, nodeLons[startNodes.first] - startLon, startLat)
          : double.infinity,
      endDistanceMeters: endNodes.isNotEmpty
          ? _approxDistance(nodeLats[endNodes.first] - endLat, nodeLons[endNodes.first] - endLon, endLat)
          : double.infinity,
    );
  }

  // ── Utilitaires (profils) ──────────────────────────────────────────────

  /// Calcule le poids d'une arête selon un profil.
  double edgeWeightForProfile(int edgeIdx, double walkSpeedMs, double penaltyFactorDiagonal) {
    final weight = edgeWeights[edgeIdx] / 1000.0; // mètres
    final speed = edgeSpeeds[edgeIdx] * 2; // km/h

    // Si la vitesse de marche est définie, on utilise le temps comme poids.
    if (walkSpeedMs > 0 && speed < 30) {
      return weight / walkSpeedMs; // temps en secondes
    }

    return weight * penaltyFactorDiagonal;
  }
}

// ── Classe utilitaire interne ─────────────────────────────────────────────

class _Candidate {
  final int nodeIdx;
  final double distance;
  _Candidate(this.nodeIdx, this.distance);
}