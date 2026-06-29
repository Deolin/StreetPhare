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

    return SpgGraph(
      header: header,
      nodeLats: nodeLats,
      nodeLons: nodeLons,
      edgeStarts: edgeStarts,
      edgeCounts: edgeCounts,
      edgeTo: edgeTo,
      edgeWeights: edgeWeights,
      edgeSpeeds: edgeSpeeds,
      edgeFlags: edgeFlags,
      spatialCells: spatialCells,
      spatialNodeIds: spatialNodeIds,
      cellSizeDeg: cellSizeDeg,
      cellsX: cellsX,
      cellsY: cellsY,
    );
  }
}
