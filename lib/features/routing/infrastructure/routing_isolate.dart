// lib/features/routing/infrastructure/routing_isolate.dart
//
// Bridge entre l'UI Isolate et le moteur de routage (dans un Isolate
// séparé). Permet de calculer des itinéraires sans bloquer le thread UI.
//
// Architecture :
//   Isolate principal (UI)              Isolate de routage
//   ┌────────────────────┐              ┌─────────────────────┐
//   │ RoutingIsolate     │──send()────→│ SpawnComputeMessage  │
//   │ .computeRoute()    │              │ 1. Copie SpgGraph   │
//   │                    │←─receive────│ 2. A* / CH / Dijkstra│
//   └────────────────────┘              │ 3. Reconstruit path │
//                                       └─────────────────────┘
//
// Avantage clé : SpgGraph utilise des TypedData (Float64List, Uint32List)
// qui sont transférables entre Isolates via SendPort sans sérialisation.

import 'dart:isolate';

import 'package:latlong2/latlong.dart';

import '../core/algorithms/astar.dart';
import '../core/algorithms/dijkstra.dart';
import '../core/graph/spg_graph.dart';
import '../core/graph/spg_loader.dart';
import '../core/graph/spg_types.dart';
import '../core/models/routing_profile.dart';

/// Message envoyé à l'Isolate de routage.
class _ComputeMessage {
  _ComputeMessage({
    required this.sendPort,
    required this.graph,
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.profile,
    required this.flags,
  });

  final SendPort sendPort;
  final SpgGraph graph;
  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
  final ProfileSettings profile;
  final RoutingFlags flags;
}

/// Résultat du calcul dans l'Isolate.
class ComputeResult {
  const ComputeResult({
    required this.nodeIds,
    required this.points,
    required this.totalDistanceMeters,
    required this.totalWeight,
    required this.nodesExplored,
    required this.success,
    this.errorMessage,
  });

  /// IDs des nœuds du chemin.
  final List<int> nodeIds;

  /// Points LatLng du chemin (pour l'affichage).
  final List<LatLng> points;

  /// Distance totale en mètres.
  final double totalDistanceMeters;

  /// Poids total (temps si piéton, distance si véhicule).
  final double totalWeight;

  /// Nombre de nœuds explorés.
  final int nodesExplored;

  /// true si le calcul a réussi.
  final bool success;

  /// Message d'erreur (si échec).
  final String? errorMessage;

  static const empty = ComputeResult(
    nodeIds: [],
    points: [],
    totalDistanceMeters: 0,
    totalWeight: 0,
    nodesExplored: 0,
    success: false,
  );
}

/// Résultat intermédiaire unifié entre A* et Dijkstra.
class _AstarOrDijkstraResult {
  const _AstarOrDijkstraResult({
    required this.nodeIds,
    required this.distanceMeters,
    required this.weight,
    required this.explored,
    required this.found,
  });

  final List<int> nodeIds;
  final double distanceMeters;
  final double weight;
  final int explored;
  final bool found;
}

/// Bridge Isolate pour le calcul d'itinéraire.
class RoutingIsolate {
  /// Calcule un itinéraire dans un Isolate séparé.
  ///
  /// [graph] : graphe de routage (.spg chargé).
  /// [start], [end] : points de départ et d'arrivée.
  /// [profile] : profil de déplacement (piéton, vélo, etc.).
  /// [flags] : options de routage (alternatives, avoid points).
  ///
  /// Retourne un [ComputeResult] avec le chemin et les métriques.
  static Future<ComputeResult> computeRoute({
    required SpgGraph graph,
    required LatLng start,
    required LatLng end,
    ProfileSettings profile = ProfileSettings.pedestrian,
    RoutingFlags flags = const RoutingFlags(),
  }) async {
    // Recherche des nœuds start/end dans le graphe.
    final nearest = graph.findStartEndNodes(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );

    if (nearest.startDistanceMeters > 500) {
      return ComputeResult(
        nodeIds: [],
        points: [],
        totalDistanceMeters: 0,
        totalWeight: 0,
        nodesExplored: 0,
        success: false,
        errorMessage: 'Point de départ trop éloigné du réseau routier '
            '(${nearest.startDistanceMeters.round()} m)',
      );
    }

    // Création du port de réception.
    final receivePort = ReceivePort();

    // Lancement de l'Isolate.
    await Isolate.spawn(
      _computeInIsolate,
      _ComputeMessage(
        sendPort: receivePort.sendPort,
        graph: graph,
        startLat: start.latitude,
        startLon: start.longitude,
        endLat: end.latitude,
        endLon: end.longitude,
        profile: profile,
        flags: flags,
      ),
    );

    // Récupération du résultat.
    final result = await receivePort.first as ComputeResult;
    receivePort.close();
    return result;
  }

  /// Charge un graphe .spg depuis le disque dans un Isolate.
  static Future<SpgGraph> loadGraph(String path) async {
    return SpgLoader.loadFile(path);
  }

  /// Fonction exécutée dans l'Isolate séparé.
  static void _computeInIsolate(_ComputeMessage msg) {
    try {
      final graph = msg.graph;
      final nearest = graph.findStartEndNodes(
        msg.startLat,
        msg.startLon,
        msg.endLat,
        msg.endLon,
      );

      final startIdx = nearest.startNodeIndex;
      final endIdx = nearest.endNodeIndex;

      _AstarOrDijkstraResult algoResult;

      if (msg.profile.useContractionHierarchies) {
        // Pour le MVP, on utilise A* bidirectionnel même si CH n'est pas
        // encore pré-calculé. La structure CH est réservée pour la V2.
        final astarResult = Astar.compute(
          graph,
          startIdx,
          endIdx,
          profile: msg.profile,
          maxNodes: 20000,
        );
        algoResult = _AstarOrDijkstraResult(
          nodeIds: astarResult.path.nodeIds,
          distanceMeters: astarResult.totalDistanceMeters,
          weight: astarResult.totalWeight,
          explored: astarResult.nodesExplored,
          found: astarResult.found,
        );
      } else {
        // Fallback Dijkstra si CH désactivé.
        final dijkstraResult = Dijkstra.compute(
          graph,
          startIdx,
          endIdx,
          maxIterations: 50000,
        );
        algoResult = _AstarOrDijkstraResult(
          nodeIds: dijkstraResult.nodeIds,
          distanceMeters: dijkstraResult.totalDistanceMeters,
          weight: dijkstraResult.totalWeight,
          explored: dijkstraResult.iterations,
          found: dijkstraResult.found,
        );
      }

      final points = algoResult.nodeIds
          .map((id) => LatLng(
                graph.nodeLat(id),
                graph.nodeLon(id),
              ))
          .toList();

      msg.sendPort.send(ComputeResult(
        nodeIds: algoResult.nodeIds,
        points: points,
        totalDistanceMeters: algoResult.distanceMeters,
        totalWeight: algoResult.weight,
        nodesExplored: algoResult.explored,
        success: algoResult.found,
      ));
    } catch (e) {
      msg.sendPort.send(ComputeResult(
        nodeIds: [],
        points: [],
        totalDistanceMeters: 0,
        totalWeight: 0,
        nodesExplored: 0,
        success: false,
        errorMessage: e.toString(),
      ));
    }
  }
}
