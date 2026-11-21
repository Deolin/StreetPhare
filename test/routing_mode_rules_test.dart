// test/routing_mode_rules_test.dart
//
// Tests des RÈGLES MÉTIER PAR MODE appliquées par les algorithmes de
// routage (Dijkstra / A*) :
//   1. Sens unique : contre-sens autorisé (piéton/transit), refusé/contourné
//      (voiture).
//   2. Zone de danger (`dangerZone`) : contournée par piéton et voiture.
//   3. Transit : pas de restriction piéton/voiture (il refuse seulement les
//      autoroutes, réservées aux véhicules motorisés).

import 'dart:typed_data';

import 'package:flutter_streetphare/features/routing/core/algorithms/dijkstra.dart';
import 'package:flutter_streetphare/features/routing/core/graph/spg_graph.dart';
import 'package:flutter_streetphare/features/routing/core/graph/spg_types.dart';
import 'package:flutter_streetphare/features/routing/core/models/routing_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construit un [SpgGraph] en mémoire à partir d'une liste d'arêtes
/// `(source, destination, poidsEnMètres, flags)`.
SpgGraph buildFlaggedGraph(
  List<double> lats,
  List<double> lons,
  List<(int, int, double, int)> edges,
) {
  final n = lats.length;
  final bySource = <int, List<(int, int, double, int)>>{};
  for (final e in edges) {
    bySource.putIfAbsent(e.$1, () => <(int, int, double, int)>[]).add(e);
  }

  final edgeStarts = Uint32List(n);
  final edgeCounts = Uint8List(n);
  final edgeTo = <int>[];
  final edgeWeights = <int>[];
  final edgeSpeeds = <int>[];
  final edgeFlags = <int>[];

  for (int i = 0; i < n; i++) {
    edgeStarts[i] = edgeTo.length;
    final outs = bySource[i] ?? const <(int, int, double, int)>[];
    edgeCounts[i] = outs.length;
    for (final (_, to, w, flags) in outs) {
      edgeTo.add(to);
      edgeWeights.add((w * 1000).round()); // m → mm
      edgeSpeeds.add(3);
      edgeFlags.add(flags);
    }
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
  group('Règle par mode : sens unique (oneway)', () {
    // Rue à sens unique 0 → 1 :
    //   - 0 → 1 : sens légal (flag 0), 10 m.
    //   - 1 → 0 : contre-sens (flag oneway), 10 m.
    //   - 1 → 2 → 0 : détour légal (50 + 50 = 100 m).
    final graph = buildFlaggedGraph(
      const [50.0, 50.0, 50.0],
      const [4.000, 4.001, 4.002],
      const [
        (0, 1, 10.0, 0),
        (1, 0, 10.0, EdgeFlags.oneway),
        (1, 2, 50.0, 0),
        (2, 0, 50.0, 0),
      ],
    );

    test('piéton : contre-sens autorisé (1 → 0 en direct)', () {
      final r = Dijkstra.compute(graph, 1, 0,
          profile: ProfileSettings.pedestrian);
      expect(r.found, isTrue);
      expect(r.nodeIds, [1, 0]);
      expect(r.totalWeight, 10.0);
    });

    test('voiture : contre-sens refusé → contourne par le nœud 2', () {
      final r = Dijkstra.compute(graph, 1, 0,
          profile: ProfileSettings.vehicle);
      expect(r.found, isTrue);
      expect(r.nodeIds, [1, 2, 0]); // détour légal
      expect(r.totalWeight, 100.0);
    });

    test('voiture : sens légal autorisé (0 → 1)', () {
      final r = Dijkstra.compute(graph, 0, 1,
          profile: ProfileSettings.vehicle);
      expect(r.found, isTrue);
      expect(r.nodeIds, [0, 1]);
      expect(r.totalWeight, 10.0);
    });
  });

  group('Règle par mode : zone de danger (dangerZone)', () {
    // 0 → 1 → 2 : direct (20 m). 0 → 3 → 2 : détour sûr (40 m).
    final graph = buildFlaggedGraph(
      const [50.0, 50.0, 50.0, 50.0],
      const [4.000, 4.001, 4.002, 4.003],
      const [
        (0, 1, 10.0, 0),
        (1, 2, 10.0, 0),
        (0, 3, 20.0, 0),
        (3, 2, 20.0, 0),
      ],
    );

    test('sans danger : itinéraire direct (20 m)', () {
      final r = Dijkstra.compute(graph, 0, 2);
      expect(r.found, isTrue);
      expect(r.nodeIds, [0, 1, 2]);
      expect(r.totalWeight, 20.0);
    });

    test('danger sur le nœud intermédiaire → contournement par 3 (40 m)',
        () {
      final dangers = [
        const RoutingAvoidPoint(lat: 50.0, lon: 4.001, radiusMeters: 25.0),
      ];
      final r = Dijkstra.compute(graph, 0, 2, avoidPoints: dangers);
      expect(r.found, isTrue);
      expect(r.nodeIds, [0, 3, 2]);
      expect(r.totalWeight, 40.0);
    });
  });

  group('Règle par mode : transit (aucune restriction piéton/voiture)', () {
    test('transit autorise le contre-sens (comportement piéton)', () {
      final graph = buildFlaggedGraph(
        const [50.0, 50.0],
        const [4.0, 4.001],
        const [
          (0, 1, 10.0, 0),
          (1, 0, 10.0, EdgeFlags.oneway),
        ],
      );
      final r = Dijkstra.compute(graph, 1, 0,
          profile: ProfileSettings.transit);
      expect(r.found, isTrue);
      expect(r.nodeIds, [1, 0]);
    });

    test('transit refuse l\'autoroute (réservée aux véhicules)', () {
      final graph = buildFlaggedGraph(
        const [50.0, 50.0],
        const [4.0, 4.001],
        const [
          (0, 1, 100.0, EdgeFlags.highway),
        ],
      );
      final transit =
          Dijkstra.compute(graph, 0, 1, profile: ProfileSettings.transit);
      expect(transit.found, isFalse); // highway interdit aux modes doux
      final car =
          Dijkstra.compute(graph, 0, 1, profile: ProfileSettings.vehicle);
      expect(car.found, isTrue); // highway autorisé en voiture
    });
  });
}