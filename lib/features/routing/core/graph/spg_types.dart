// lib/features/routing/core/graph/spg_types.dart
//
// Types et constantes du format binaire .spg (StreetPhare Graph).
//
// Conventions d'encodage :
//   - Les coordonnées sont stockées en delta par rapport au min de la région
//     (int32 × 1e7, soit ~1 cm de précision)
//   - Les poids sont en mm (millimètres) pour éviter les floats
//   - Les flags sont packed sur 8 bits
//   - Varint encoding pour les index (Base 128)

import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════════════════
// Constantes du format
// ═══════════════════════════════════════════════════════════════════════════

/// Magic number du format .spg : "SPG\1" en little-endian.
const int kSpgMagic = 0x01504753; // 0x53 0x47 0x50 0x01

/// Version actuelle du format.
const int kSpgVersion = 1;

/// Taille du header en octets.
const int kSpgHeaderSize = 64;

// ═══════════════════════════════════════════════════════════════════════════
// Header du fichier .spg
// ═══════════════════════════════════════════════════════════════════════════

/// Header binaire du fichier .spg (64 octets).
class SpgHeader {
  const SpgHeader({
    required this.magic,
    required this.version,
    required this.nodeCount,
    required this.edgeCount,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.nodesOffset,
    required this.edgesOffset,
    required this.chOffset,
    required this.indexOffset,
  });

  final int magic;
  final int version;
  final int nodeCount;
  final int edgeCount;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final int nodesOffset;
  final int edgesOffset;
  final int chOffset;
  final int indexOffset;

  double get latRange => maxLat - minLat;
  double get lonRange => maxLon - minLon;

  /// Parse le header depuis un ByteData (64 octets).
  static SpgHeader fromByteData(ByteData data) {
    return SpgHeader(
      magic: data.getUint32(0, Endian.little),
      version: data.getUint32(4, Endian.little),
      nodeCount: data.getUint32(8, Endian.little),
      edgeCount: data.getUint32(12, Endian.little),
      minLat: data.getFloat64(16, Endian.little),
      maxLat: data.getFloat64(24, Endian.little),
      minLon: data.getFloat64(32, Endian.little),
      maxLon: data.getFloat64(40, Endian.little),
      nodesOffset: data.getUint64(48, Endian.little),
      edgesOffset: data.getUint64(56, Endian.little),
      chOffset: data.getUint64(64, Endian.little),
      indexOffset: data.getUint64(72, Endian.little),
    );
  }

  /// Sérialise le header en ByteData (80 octets).
  ByteData toByteData() {
    final data = ByteData(80);
    data.setUint32(0, magic, Endian.little);
    data.setUint32(4, version, Endian.little);
    data.setUint32(8, nodeCount, Endian.little);
    data.setUint32(12, edgeCount, Endian.little);
    data.setFloat64(16, minLat, Endian.little);
    data.setFloat64(24, maxLat, Endian.little);
    data.setFloat64(32, minLon, Endian.little);
    data.setFloat64(40, maxLon, Endian.little);
    data.setUint64(48, nodesOffset, Endian.little);
    data.setUint64(56, edgesOffset, Endian.little);
    data.setUint64(64, chOffset, Endian.little);
    data.setUint64(72, indexOffset, Endian.little);
    return data;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EdgeFlags
// ═══════════════════════════════════════════════════════════════════════════

/// Flags d'arête (packed sur 8 bits).
class EdgeFlags {
  const EdgeFlags._();

  static const int oneway = 1 << 0;
  static const int stairs = 1 << 1;
  static const int tunnel = 1 << 2;
  static const int bridge = 1 << 3;
  static const int unpaved = 1 << 4;
  static const int highway = 1 << 5;
  static const int cycleway = 1 << 6;
  static const int private = 1 << 7;

  static bool has(int flags, int flag) => (flags & flag) != 0;

  static String describe(int flags) {
    final parts = <String>[];
    if (has(flags, oneway)) parts.add('oneway');
    if (has(flags, stairs)) parts.add('stairs');
    if (has(flags, tunnel)) parts.add('tunnel');
    if (has(flags, bridge)) parts.add('bridge');
    if (has(flags, unpaved)) parts.add('unpaved');
    if (has(flags, highway)) parts.add('highway');
    if (has(flags, cycleway)) parts.add('cycleway');
    if (has(flags, private)) parts.add('private');
    return parts.isEmpty ? 'normal' : parts.join('|');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Structures du graphe (temporaires pour le chargement)
// ═══════════════════════════════════════════════════════════════════════════

/// Structure d'un nœud dans le fichier .spg (avant chargement mémoire).
class SpgRawNode {
  const SpgRawNode({
    required this.deltaLat,
    required this.deltaLon,
    required this.edgeStart,
    required this.edgeCount,
  });

  /// Delta latitude × 1e7 par rapport à [SpgHeader.minLat].
  final int deltaLat;

  /// Delta longitude × 1e7 par rapport à [SpgHeader.minLon].
  final int deltaLon;

  /// Index de début dans le tableau edges plat.
  final int edgeStart;

  /// Nombre d'arêtes partant de ce nœud.
  final int edgeCount;
}

/// Structure d'une arête dans le fichier .spg.
class SpgRawEdge {
  const SpgRawEdge({
    required this.toNode,
    required this.weightMm,
    required this.speedKmh,
    required this.flags,
  });

  final int toNode;
  final int weightMm;
  final int speedKmh;
  final int flags;
}

/// Structure d'un shortcut CH (Contraction Hierarchy).
class ChEdge {
  const ChEdge({
    required this.viaNode,
    required this.toNode,
    required this.weightMm,
  });

  final int viaNode;
  final int toNode;
  final int weightMm;
}

/// Données CH pour un nœud.
class ChNodeData {
  const ChNodeData({
    required this.level,
    required this.shortcutStart,
    required this.shortcutCount,
  });

  final int level;
  final int shortcutStart;
  final int shortcutCount;
}

// ═══════════════════════════════════════════════════════════════════════════
// Résultat de snapping (map matching)
// ═══════════════════════════════════════════════════════════════════════════

/// Résultat de snapping (map matching).
class SnapResult {
  const SnapResult({
    required this.latLngIndex,
    required this.nodeIndex,
    required this.edgeIndex,
    required this.distanceMeters,
    required this.onRoad,
  });

  final int latLngIndex;
  final int nodeIndex;
  final int edgeIndex;
  final double distanceMeters;
  final bool onRoad;

  static const invalid = SnapResult(
    latLngIndex: -1,
    nodeIndex: -1,
    edgeIndex: -1,
    distanceMeters: double.infinity,
    onRoad: false,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Résultat de recherche des nœuds start/end
// ═══════════════════════════════════════════════════════════════════════════

/// Résultat de la recherche des nœuds start/end dans le graphe.
class NearestNodesResult {
  const NearestNodesResult({
    required this.startNodeIndex,
    required this.endNodeIndex,
    required this.startDistanceMeters,
    required this.endDistanceMeters,
  });

  final int startNodeIndex;
  final int endNodeIndex;
  final double startDistanceMeters;
  final double endDistanceMeters;
}

// ═══════════════════════════════════════════════════════════════════════════
// Options de routage
// ═══════════════════════════════════════════════════════════════════════════

/// Flags de routage pour le calcul d'itinéraire.
class RoutingFlags {
  const RoutingFlags({
    this.includeAlternatives = false,
    this.maxAlternatives = 3,
    this.avoidPoints = const [],
    this.timeoutMs = 5000,
  });

  final bool includeAlternatives;
  final int maxAlternatives;
  final List<RoutingAvoidPoint> avoidPoints;
  final int timeoutMs;
}

/// Point à éviter lors du routage.
class RoutingAvoidPoint {
  const RoutingAvoidPoint({
    required this.lat,
    required this.lon,
    this.radiusMeters = 30.0,
  });

  final double lat;
  final double lon;
  final double radiusMeters;
}
