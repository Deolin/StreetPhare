// test/routing_algorithms_test.dart
//
// Tests unitaires des moteurs de calcul de routage (Dijkstra + A*)
// sur un petit graphe SpgGraph construit en mémoire.
//
// Le graphe de test (4 nœuds) :
//   0 → 1 (10 m) ; 1 → 2 (20 m) ; 0 → 2 (50 m) ; 2 → 3 (10 m)
// Chemin le plus court 0 → 3 : 0 → 1 → 2 → 3 = 40 m.

import 'dart:typed_data';

import 'package:flutter_streetphare/features/routing/core/algorithms/astar.dart';
import 'package:flutter_streetphare/features/routing/core/algorithms/dijkstra.dart';
import 'package:flutter_streetphare/features/routing/core/graph/spg_graph.dart';
import 'package:flutter_streetphare/features/routing/core/graph/spg_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construit un graphe SpgGraph simple depuis une liste d'adjacence
/// `source -> {destination: poidsEnMètres}`. Les poids sont stockés en
/// millimètres (format .spg) via `Uint16List`.
SpgGraph buildTestGraph(
  List<double> lats,
  List<double> lons,
  Map<int, Map<int, double>> adjacency,
) {
  final n = lats.length;
  final edgeStarts = Uint32List(n);
  final edgeCounts = Uint8List(n);
  final edgeTo = <int>[];
  final edgeWeights = <int>[];
  final edgeSpeeds = <int>[];
  final edgeFlags = <int>[];

  for (int i = 0; i < n; i++) {
    edgeStarts[i] = edgeTo.length;
    final outs = adjacency[i] ?? const <int, double>{};
    edgeCounts[i] = outs.length;
    outs.forEach((to, weightMeters) {
      edgeTo.add(to);
      edgeWeights.add((weightMeters * 1000).round()); // m → mm
      edgeSpeeds.add(3); // ~6 km/h / 2
      edgeFlags.add(0);
    });
  }

  final header = SpgHeader(
    magic: kSpgMagic,
    version: kSpgVersion,
    nodeCount: n,
    edgeCount: edgeTo.length,
    minLat: 0,
    maxLat: 1,
    minLon: 0,
    maxLon: 1,
    nodesOffset: 0,
    edgesOffset: 0,
    chOffset: 0,
    indexOffset: 0,
  );

  return SpgGraph(
    header: header,
    nodeLats: Float64List.fromList(lats),
    nodeLons: Float64List.fromList(lons),
    edgeStarts: edgeStarts,
    edgeCounts: edgeCounts,
    edgeTo: Uint32List.fromList(edgeTo),
    edgeWeights: Uint16List.fromList(edgeWeights),
    edgeSpeeds: Uint8List.fromList(edgeSpeeds),
    edgeFlags: Uint8List.fromList(edgeFlags),
    spatialCells: Uint32List(0),
    spatialNodeIds: Uint32List(0),
    cellSizeDeg: 0.01,
    cellsX: 1,
    cellsY: 1,
  );
}

void main() {
  // Graphe : 4 nœuds alignés.
  final graph = buildTestGraph(
    [50.0, 50.0, 50.0, 50.0],
    [4.000, 4.001, 4.002, 4.003],
    {
      0: {1: 10.0, 2: 50.0},
      1: {2: 20.0},
      2: {3: 10.0},
    },
  );

  group('Dijkstra — plus court chemin', () {
    test('trouve le chemin optimal 0 → 3 (40 m)', () {
      final r = Dijkstra.compute(graph, 0, 3);
      expect(r.found, isTrue);
      expect(r.nodeIds, [0, 1, 2, 3]);
      expect(r.totalWeight, 40.0);
    });

    test('start == end → chemin trivial (1 nœud)', () {
      final r = Dijkstra.compute(graph, 1, 1);
      expect(r.found, isTrue);
      expect(r.nodeIds, [1]);
      expect(r.totalWeight, 0.0);
    });

    test('nœuds déconnectés → aucun chemin', () {
      final isolated = buildTestGraph(
        [50.0, 50.0],
        [4.0, 4.001],
        {0: const {}}, // aucun edge sortant
      );
      final r = Dijkstra.compute(isolated, 0, 1);
      expect(r.found, isFalse);
      expect(r.nodeIds, isEmpty);
    });

    test('respecte maxWeight (abandon au-delà du plafond)', () {
      final r = Dijkstra.compute(graph, 0, 3, maxWeight: 15.0);
      // Le chemin optimal vaut 40 m > 15 m → non trouvé.
      expect(r.found, isFalse);
    });
  });

  group('Astar — recherche heuristique', () {
    test('trouve un chemin entre 0 et 3', () {
      final r = Astar.compute(graph, 0, 3);
      expect(r.found, isTrue);
      expect(r.path.nodeIds, isNotEmpty);
      expect(r.path.nodeIds, contains(0));
      expect(r.path.nodeIds, contains(3));
    });

    test('start == end → chemin trivial', () {
      final r = Astar.compute(graph, 2, 2);
      expect(r.found, isTrue);
      expect(r.path.nodeIds, [2]);
      expect(r.totalWeight, 0);
    });
  });
}
