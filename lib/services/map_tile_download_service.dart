// lib/services/map_tile_download_service.dart
//
// Service de téléchargement résilient de tuiles cartographiques.
//
// Architecture :
//   Dart (ce service) → MethodChannel "streetphare/map_tiles"        → Android DownloadManager
//                      → EventChannel  "streetphare/map_tiles_status" ← BroadcastReceiver
//
// Stratégie de fallback (implémentée côté natif dans MapTileDownloadPlugin.kt) :
//   1. Priorité 1 : https://streetphare.ddns.net/tiles/{z}/{x}/{y}.png  (serveur privé)
//   2. Priorité 2 : https://tile.openstreetmap.org/{z}/{x}/{y}.png       (OSM public)
//
// Le DownloadManager Android gère :
//   - Reprise automatique sur perte de connectivité
//   - Gestion optimisée de la batterie (batch scheduling)
//   - TLS/HTTPS via le trust store Android natif

import 'dart:async';
import 'dart:math' show pi, tan, cos, log;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Événement de statut d'un téléchargement de tuile.
class TileDownloadEvent {
  const TileDownloadEvent({
    required this.path,
    required this.status,
    this.error,
    this.attempt,
  });

  final String path;
  final String status;
  final String? error;
  final int? attempt;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed' || status == 'error';
  bool get isDownloading => status == 'downloading';

  String get source {
    if (attempt == null) return 'unknown';
    return attempt == 0 ? 'private' : 'osm_fallback';
  }

  @override
  String toString() =>
      'TileDownloadEvent(path: $path, status: $status, source: $source'
      '${error != null ? ', error: $error' : ''})';
}

/// Configuration des URLs de téléchargement.
class TileUrlConfig {
  const TileUrlConfig({
    this.privateBase = 'https://streetphare.ddns.net/tiles',
    this.osmBase = 'https://tile.openstreetmap.org',
    this.defaultExtension = 'png',
  });

  final String privateBase;
  final String osmBase;
  final String defaultExtension;

  Uri privateTileUrl(int z, int x, int y, [String? ext]) =>
      Uri.parse('$privateBase/$z/$x/$y.${ext ?? defaultExtension}');

  Uri osmTileUrl(int z, int x, int y, [String? ext]) =>
      Uri.parse('$osmBase/$z/$x/$y.${ext ?? defaultExtension}');
}

/// Service singleton de téléchargement résilient de tuiles via
/// le DownloadManager natif Android.
class MapTileDownloadService {
  MapTileDownloadService._();
  static final MapTileDownloadService instance = MapTileDownloadService._();

  static const _methodChannel = MethodChannel('streetphare/map_tiles');
  static const _eventChannel = EventChannel('streetphare/map_tiles_status');

  TileUrlConfig urlConfig = const TileUrlConfig();

  // ── Stream ───────────────────────────────────────────────────────────────

  Stream<TileDownloadEvent>? _statusStream;
  StreamSubscription<dynamic>? _eventSub;

  Stream<TileDownloadEvent> get statusStream {
    _statusStream ??= _eventChannel.receiveBroadcastStream().map((data) {
      final map = Map<String, dynamic>.from(data as Map);
      return TileDownloadEvent(
        path: map['path'] as String? ?? '',
        status: map['status'] as String? ?? 'error',
        error: map['error'] as String?,
        attempt: map['attempt'] as int?,
      );
    });
    return _statusStream!;
  }

  // ── Compteurs ────────────────────────────────────────────────────────────

  int _downloadCount = 0;
  int _successCount = 0;
  int _failCount = 0;
  int _osmFallbackCount = 0;

  int get totalDownloads => _downloadCount;
  int get successfulDownloads => _successCount;
  int get failedDownloads => _failCount;
  int get osmFallbackCount => _osmFallbackCount;

  // ── Téléchargement unitaire ──────────────────────────────────────────────

  Future<int> downloadTile({
    required int z,
    required int x,
    required int y,
    String ext = 'png',
  }) async {
    _downloadCount++;

    try {
      final downloadId = await _methodChannel.invokeMethod<int>(
        'downloadTile',
        {'z': z, 'x': x, 'y': y, 'ext': ext},
      );

      if (kDebugMode) {
        debugPrint(
            '[MapTileDownload] Tuile $z/$x/$y.$ext → downloadId=$downloadId');
      }

      return downloadId ?? -1;
    } on MissingPluginException {
      return -1;
    } catch (e) {
      if (kDebugMode) debugPrint('[MapTileDownload] Erreur downloadTile: $e');
      return -1;
    }
  }

  Future<void> cancelTile(int downloadId) async {
    try {
      await _methodChannel.invokeMethod('cancelTile', {'downloadId': downloadId});
    } catch (e) {
      if (kDebugMode) debugPrint('[MapTileDownload] Erreur cancelTile: $e');
    }
  }

  Future<String?> getLocalTilePath({
    required int z,
    required int x,
    required int y,
    String ext = 'png',
  }) async {
    try {
      return await _methodChannel.invokeMethod<String>(
        'getTilePath',
        {'z': z, 'x': x, 'y': y, 'ext': ext},
      );
    } on MissingPluginException {
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[MapTileDownload] Erreur getLocalTilePath: $e');
      return null;
    }
  }

  // ── Téléchargement par lot ───────────────────────────────────────────────

  Future<List<int>> downloadTileBatch({
    required int minZ,
    required int maxZ,
    required int minX,
    required int maxX,
    required int minY,
    required int maxY,
    String ext = 'png',
  }) async {
    final ids = <int>[];
    for (var z = minZ; z <= maxZ; z++) {
      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          final id = await downloadTile(z: z, x: x, y: y, ext: ext);
          if (id != -1) ids.add(id);
        }
      }
    }
    if (kDebugMode) {
      debugPrint('[MapTileDownload] Batch planifié : ${ids.length} tuiles');
    }
    return ids;
  }

  void startTracking() {
    _eventSub?.cancel();
    _eventSub = statusStream.listen((event) {
      switch (event.status) {
        case 'completed':
          _successCount++;
          if (event.attempt == 1) _osmFallbackCount++;
        case 'failed':
        case 'error':
          _failCount++;
      }
    });
  }

  void stopTracking() {
    _eventSub?.cancel();
    _eventSub = null;
  }

  void resetCounters() {
    _downloadCount = 0;
    _successCount = 0;
    _failCount = 0;
    _osmFallbackCount = 0;
  }

  // ── Projection Web Mercator → coordonnées de tuile ──────────────────────

  /// Convertit une coordonnée géographique en coordonnée de tuile (z/x/y).
  ///
  /// Formule standard Slippy Map (EPSG:3857 → XYZ).
  static ({int x, int y}) latLngToTile({
    required double lat,
    required double lng,
    required int z,
  }) {
    final n = 1 << z;
    final x = ((lng + 180.0) / 360.0 * n).floor();

    final latRad = lat * pi / 180.0;
    // y = floor( (1 - ln(tan(φ) + 1/cos(φ)) / π) / 2 * 2^z )
    final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n)
        .floor();

    return (x: x.clamp(0, n - 1), y: y.clamp(0, n - 1));
  }

  /// Calcule la plage de tuiles couvrant un rectangle géographique.
  static ({int minX, int maxX, int minY, int maxY}) tileBoundsForArea({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int z,
  }) {
    final sw = latLngToTile(lat: swLat, lng: swLng, z: z);
    final ne = latLngToTile(lat: neLat, lng: neLng, z: z);
    final limit = (1 << z) - 1;
    return (
      minX: sw.x.clamp(0, limit),
      maxX: ne.x.clamp(0, limit),
      minY: ne.y.clamp(0, limit),
      maxY: sw.y.clamp(0, limit),
    );
  }
}