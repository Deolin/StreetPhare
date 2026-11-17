// lib/features/routing/core/graph/spg_loader.dart
//
// Parseur binaire du format .spg (StreetPhare Graph).
//
// Charge un fichier .spg depuis le disque et construit un SpgGraph
// en mémoire en utilisant des TypedData pour une compacité extrême.
//
// Utilisation :
// ```dart
// final graph = SpgLoader.loadFile('regions/fleurus.spg');
// print('Graphe chargé : ${graph.nodeCount} nœuds, ${graph.edgeCount} arêtes');
// print('Mémoire : ${graph.memoryMb.toStringAsFixed(1)} Mo');
// ```

import 'dart:io';
import 'dart:typed_data';

import 'spg_graph.dart';
import 'spg_types.dart';

/// Parseur de fichiers .spg.
class SpgLoader {
  /// Charge un fichier .spg depuis le chemin donné.
  static Future<SpgGraph> loadFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return loadBytes(bytes);
  }

  /// Charge un fichier .spg depuis un buffer en mémoire.
  static SpgGraph loadBytes(Uint8List bytes) {
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);

    // 1) Parse le header
    final header = SpgHeader.fromByteData(data);

    // Validation du magic number
    if (header.magic != kSpgMagic) {
      throw FormatException(
          'Magic number invalide: ${header.magic.toRadixString(16)}');
    }
    if (header.version != kSpgVersion) {
      throw FormatException('Version .spg non supportée: ${header.version}');
    }

    // 2) Parse les nœuds
    int offset = header.nodesOffset;
    final nodeLats = Float64List(header.nodeCount);
    final nodeLons = Float64List(header.nodeCount);
    final edgeStarts = Uint32List(header.nodeCount);
    final edgeCounts = Uint8List(header.nodeCount);

    for (int i = 0; i < header.nodeCount; i++) {
      final deltaLat = data.getInt32(offset, Endian.little);
      final deltaLon = data.getInt32(offset + 4, Endian.little);
      final edgeStart = data.getUint32(offset + 8, Endian.little);
      final edgeCount = data.getUint8(offset + 12);

      nodeLats[i] = header.minLat + deltaLat / 10_000_000.0;
      nodeLons[i] = header.minLon + deltaLon / 10_000_000.0;
      edgeStarts[i] = edgeStart;
      edgeCounts[i] = edgeCount;

      offset += 13; // 4 + 4 + 4 + 1 = 13 octets par nœud
    }

    // 3) Parse les arêtes
    offset = header.edgesOffset;
    // Calcul du nombre total d'arêtes = somme des edgeCounts
    int totalEdges = 0;
    for (int i = 0; i < header.nodeCount; i++) {
      totalEdges += edgeCounts[i];
    }

    final edgeTo = Uint32List(totalEdges);
    final edgeWeights = Uint16List(totalEdges);
    final edgeSpeeds = Uint8List(totalEdges);
    final edgeFlags = Uint8List(totalEdges);

    for (int i = 0; i < totalEdges; i++) {
      edgeTo[i] = data.getUint32(offset, Endian.little);
      edgeWeights[i] = data.getUint16(offset + 4, Endian.little);
      edgeSpeeds[i] = data.getUint8(offset + 6);
      edgeFlags[i] = data.getUint8(offset + 7);
      offset += 8; // 4 + 2 + 1 + 1 = 8 octets par arête
    }

    // 4) Construit l'index spatial (maillage fixe ~500 m)
    const cellSizeDeg = 0.0045; // ~500 m à 50°N
    final cellsX =
        ((header.maxLon - header.minLon) / cellSizeDeg).ceil().clamp(1, 500);
    final cellsY =
        ((header.maxLat - header.minLat) / cellSizeDeg).ceil().clamp(1, 500);

    // Compte les nœuds par cellule
    final cellCounts = Uint32List(cellsX * cellsY);
    for (int i = 0; i < header.nodeCount; i++) {
      final cx = ((nodeLons[i] - header.minLon) / cellSizeDeg)
          .floor()
          .clamp(0, cellsX - 1);
      final cy = ((nodeLats[i] - header.minLat) / cellSizeDeg)
          .floor()
          .clamp(0, cellsY - 1);
      cellCounts[cy * cellsX + cx]++;
    }

    // Construit les offsets de cellule (parallel prefix sum)
    final spatialCells = Uint32List(cellsX * cellsY);
    int runningOffset = 0;
    for (int i = 0; i < cellsX * cellsY; i++) {
      spatialCells[i] = runningOffset;
      runningOffset += cellCounts[i];
    }

    // Remplit les IDs de nœuds par cellule
    final spatialNodeIds = Uint32List(runningOffset);
    final tempOffsets = Uint32List(cellsX * cellsY);
    for (int i = 0; i < cellsX * cellsY; i++) {
      tempOffsets[i] = spatialCells[i];
    }

    for (int i = 0; i < header.nodeCount; i++) {
      final cx = ((nodeLons[i] - header.minLon) / cellSizeDeg)
          .floor()
          .clamp(0, cellsX - 1);
      final cy = ((nodeLats[i] - header.minLat) / cellSizeDeg)
          .floor()
          .clamp(0, cellsY - 1);
      final cellIdx = cy * cellsX + cx;
      spatialNodeIds[tempOffsets[cellIdx]] = i;
      tempOffsets[cellIdx]++;
    }

    // 5) Parse les données CH (si présentes)
    // Pour le MVP, on ignore les CH (chOffset == 0 signifie pas de CH)

    // 3b) Expansion « sens interdits » pour le piéton/vélo (contre-sens).
    //
    // Le graphe .spg est ORIENTÉ : une arête marquée `oneway` (A→B) n'existe
    // que dans le sens légal. Pour permettre au piéton/vélo de franchir les
    // sens uniques à contre-sens, on ajoute une arête inverse (B→A) portant le
    // flag `oneway` (= contre-sens : interdite aux véhicules, autorisée aux
    // modes doux), et on retire ce flag de l'arête aller (sens légal, ouverte
    // à tous).
    //
    // Protection « anti-duplication » : si l'arête inverse (B→A) existe DÉJÀ
    // (convention bidirectionnelle), on considère que `oneway` marque déjà le
    // contre-sens et on ne touche à rien — on évite de dupliquer l'arête ou
    // d'autoriser les véhicules à contre-sens.
    bool hasEdge(int from, int to) {
      for (int e = edgeStarts[from];
          e < edgeStarts[from] + edgeCounts[from];
          e++) {
        if (edgeTo[e] == to) return true;
      }
      return false;
    }

    var outEdgeStarts = edgeStarts;
    var outEdgeCounts = edgeCounts;
    var outEdgeTo = edgeTo;
    var outEdgeWeights = edgeWeights;
    var outEdgeSpeeds = edgeSpeeds;
    var outEdgeFlags = edgeFlags;

    final n = header.nodeCount;
    final expandEdge = Uint8List(totalEdges); // 1 = arête à dédoubler
    int onewayCount = 0;
    for (int s = 0; s < n; s++) {
      for (int e = edgeStarts[s]; e < edgeStarts[s] + edgeCounts[s]; e++) {
        if (!EdgeFlags.has(edgeFlags[e], EdgeFlags.oneway)) continue;
        if (hasEdge(edgeTo[e], s)) continue; // arête inverse déjà présente
        expandEdge[e] = 1;
        onewayCount++;
      }
    }

    if (onewayCount > 0) {
      // Pour chaque nœud destination, collecte les arêtes oneway à dédoubler
      // (source, index arête d'origine).
      final incomingOneway =
          List<List<(int, int)>>.generate(n, (_) => <(int, int)>[]);
      for (int s = 0; s < n; s++) {
        for (int e = edgeStarts[s]; e < edgeStarts[s] + edgeCounts[s]; e++) {
          if (expandEdge[e] == 1) {
            incomingOneway[edgeTo[e]].add((s, e));
          }
        }
      }

      // Nouveaux comptes d'arêtes sortantes par nœud.
      final newEdgeCounts = Uint8List(n);
      for (int s = 0; s < n; s++) {
        newEdgeCounts[s] =
            (edgeCounts[s] + incomingOneway[s].length).clamp(0, 255);
      }

      // Nouveaux offsets (somme préfixe).
      final newEdgeStarts = Uint32List(n);
      int cursor = 0;
      for (int s = 0; s < n; s++) {
        newEdgeStarts[s] = cursor;
        cursor += newEdgeCounts[s];
      }

      final newTotal = cursor;
      final newEdgeTo = Uint32List(newTotal);
      final newEdgeWeights = Uint16List(newTotal);
      final newEdgeSpeeds = Uint8List(newTotal);
      final newEdgeFlags = Uint8List(newTotal);
      final fillPos = Uint32List.fromList(newEdgeStarts);

      // Arêtes aller : copie ; on retire le flag oneway des arêtes dédoublées
      // (sens légal), on le conserve sur les autres (contre-sens déjà présent).
      for (int s = 0; s < n; s++) {
        for (int e = edgeStarts[s]; e < edgeStarts[s] + edgeCounts[s]; e++) {
          final pos = fillPos[s]++;
          newEdgeTo[pos] = edgeTo[e];
          newEdgeWeights[pos] = edgeWeights[e];
          newEdgeSpeeds[pos] = edgeSpeeds[e];
          newEdgeFlags[pos] = (expandEdge[e] == 1)
              ? (edgeFlags[e] & ~EdgeFlags.oneway)
              : edgeFlags[e];
        }
      }

      // Arêtes inverses (contre-sens) : flag oneway (modes doux uniquement).
      for (int s = 0; s < n; s++) {
        for (final (src, edgeIdx) in incomingOneway[s]) {
          final pos = fillPos[s]++;
          newEdgeTo[pos] = src;
          newEdgeWeights[pos] = edgeWeights[edgeIdx];
          newEdgeSpeeds[pos] = edgeSpeeds[edgeIdx];
          newEdgeFlags[pos] = EdgeFlags.oneway;
        }
      }

      outEdgeStarts = newEdgeStarts;
      outEdgeCounts = newEdgeCounts;
      outEdgeTo = newEdgeTo;
      outEdgeWeights = newEdgeWeights;
      outEdgeSpeeds = newEdgeSpeeds;
      outEdgeFlags = newEdgeFlags;
    }

    return SpgGraph(
      header: header,
      nodeLats: nodeLats,
      nodeLons: nodeLons,
      edgeStarts: outEdgeStarts,
      edgeCounts: outEdgeCounts,
      edgeTo: outEdgeTo,
      edgeWeights: outEdgeWeights,
      edgeSpeeds: outEdgeSpeeds,
      edgeFlags: outEdgeFlags,
      spatialCells: spatialCells,
      spatialNodeIds: spatialNodeIds,
      cellSizeDeg: cellSizeDeg,
      cellsX: cellsX,
      cellsY: cellsY,
    );
  }
}
