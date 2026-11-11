// lib/features/map/local_first_tile_provider.dart
//
// [TileProvider] flutter_map appliquant, pour CHAQUE tuile, la priorité :
//
//   1. Cache mémoire (session courante) ;
//   2. Cache local PERSISTANT (`getTileCacheDir`/`z/x/y.png`) ;
//   3. Serveur StreetPhare — `TileLayer.urlTemplate` ;
//   4. Internet OpenStreetMap — `TileLayer.fallbackUrl`, en dernier recours.
//
// Tout téléchargement réseau (3 ou 4) est ensuite PERSISTÉ dans le cache
// local : la tuile n'est donc demandée au serveur qu'UNE SEULE fois tant
// qu'elle reste dans le cache, ce qui soulage le serveur StreetPhare.
// En cas de 429 (limite de tuiles), on stoppe et on prévient l'utilisateur
// (voir [onTileRateLimited]) au lieu de contourner la limite.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../../services/map_tile_download_service.dart';

class LocalFirstTileProvider extends TileProvider {
  LocalFirstTileProvider({
    super.headers,
    MapTileDownloadService? downloadService,
    this.onTileRateLimited,
  }) : _downloadService = downloadService ?? MapTileDownloadService.instance;

  final MapTileDownloadService _downloadService;

  /// Appelé (au plus une fois toutes les [_notifyThrottle]) quand le serveur
  /// signale que la limite de tuiles est atteinte pour cet utilisateur.
  final void Function(Duration? waitFor)? onTileRateLimited;

  /// Évite de spammer l'utilisateur : une notification au plus toutes les
  /// 30 secondes, même si plusieurs tuiles retombent en 429.
  static const Duration _notifyThrottle = Duration(seconds: 30);
  DateTime? _lastNotify;

  /// Client HTTP partagé (réutilise les connexions).
  final http.Client _httpClient = http.Client();

  /// Cache mémoire de session : évite de relire le disque (ou le réseau) à
  /// chaque mouvement de carte. Borné pour ne pas croître indéfiniment.
  static const int _maxMemoryTiles = 512;
  final Map<String, Uint8List> _memoryTiles = <String, Uint8List>{};

  /// Chemin du répertoire de cache PERSISTANT (résolu une seule fois).
  String? _tileCacheDir;

  Uint8List? _memoryGet(TileCoordinates c) =>
      _memoryTiles['${c.z}/${c.x}/${c.y}'];

  void _memoryPut(TileCoordinates c, Uint8List bytes) {
    if (_memoryTiles.length >= _maxMemoryTiles) _memoryTiles.clear();
    _memoryTiles['${c.z}/${c.x}/${c.y}'] = bytes;
  }

  Future<String?> _tileCacheDirPath() async {
    if (_tileCacheDir != null) return _tileCacheDir;
    _tileCacheDir = await _downloadService.getTileCacheDir();
    return _tileCacheDir;
  }

  @override
  bool get supportsCancelLoading => false;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _LocalFirstTileImageProvider(
      coordinates: coordinates,
      options: options,
      downloadService: _downloadService,
      owner: this,
    );
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  void _notifyRateLimit(Duration? waitFor) {
    final DateTime now = DateTime.now();
    if (_lastNotify != null &&
        now.difference(_lastNotify!) < _notifyThrottle) {
      return;
    }
    _lastNotify = now;
    onTileRateLimited?.call(waitFor);
  }
}

class _LocalFirstTileImageProvider
    extends ImageProvider<_LocalFirstTileImageProvider> {
  _LocalFirstTileImageProvider({
    required this.coordinates,
    required this.options,
    required this.downloadService,
    required this.owner,
  });

  final TileCoordinates coordinates;
  final TileLayer options;
  final MapTileDownloadService downloadService;
  final LocalFirstTileProvider owner;

  @override
  Future<_LocalFirstTileImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _LocalFirstTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadImageInfo(decode));
  }

  /// Résout la source réelle de la tuile dans l'ordre
  /// mémoire → cache local → serveur → OSM, et PERSISTE tout téléchargement
  /// réseau dans le cache local pour soulager le serveur.
  Future<ImageInfo> _loadImageInfo(ImageDecoderCallback decode) async {
    // 1) Cache mémoire (session courante).
    final Uint8List? cached = owner._memoryGet(coordinates);
    if (cached != null) return _decode(cached, decode);

    // 2) Cache local persistant.
    final String? localPath = await downloadService.getLocalTilePath(
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
    if (localPath != null && localPath.isNotEmpty) {
      final File file = File(localPath);
      if (file.existsSync()) {
        final Uint8List bytes = await file.readAsBytes();
        owner._memoryPut(coordinates, bytes);
        return _decode(bytes, decode);
      }
    }

    // 3) Serveur StreetPhare (puis persistance locale).
    try {
      final Uint8List bytes = await _fetch(
        owner.getTileUrl(coordinates, options),
        isServer: true,
      );
      owner._memoryPut(coordinates, bytes);
      await _persistToDisk(bytes);
      return await _decode(bytes, decode);
    } on _RateLimitException catch (error) {
      // 429 : on informe l'utilisateur et on NE bascule PAS vers OSM,
      // par respect de la limite demandée par le serveur.
      owner._notifyRateLimit(error.waitFor);
      return _decode(TileProvider.transparentImage, decode);
    } on Exception catch (_) {
      // Serveur injoignable/en erreur → on tente le fallback OSM.
    }

    // 4) Internet OpenStreetMap (uniquement si le serveur est indisponible).
    final String? osmUrl = owner.getTileFallbackUrl(coordinates, options);
    if (osmUrl != null) {
      try {
        final Uint8List bytes = await _fetch(osmUrl, isServer: false);
        owner._memoryPut(coordinates, bytes);
        await _persistToDisk(bytes);
        return await _decode(bytes, decode);
      } on Exception catch (_) {
        // OSM indisponible également.
      }
    }

    // Échec total → tuile transparente (pas de crash).
    return _decode(TileProvider.transparentImage, decode);
  }

  /// Récupère la tuile HTTP ; lève [_RateLimitException] sur un 429 serveur.
  Future<Uint8List> _fetch(String url, {required bool isServer}) async {
    final http.Response response;
    try {
      response =
          await owner._httpClient.get(Uri.parse(url), headers: owner.headers);
    } catch (_) {
      throw const _FetchException();
    }

    if (response.statusCode == 200) return response.bodyBytes;

    if (isServer && response.statusCode == 429) {
      throw _RateLimitException(_parseRetryAfter(response));
    }
    throw const _FetchException();
  }

  Duration? _parseRetryAfter(http.Response response) {
    final String? raw = response.headers['retry-after'];
    if (raw == null) return null;
    final int? seconds = int.tryParse(raw.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// Copie la tuile téléchargée dans le cache local PERSISTANT
  /// (`getTileCacheDir`/z/x/y.png) pour qu'elle soit servie en local lors
  /// des prochains mouvements de carte, sans re-solliciter le serveur.
  Future<void> _persistToDisk(Uint8List bytes) async {
    try {
      final String? cacheDir = await owner._tileCacheDirPath();
      if (cacheDir == null || cacheDir.isEmpty) return;
      final Directory dir =
          Directory('$cacheDir/${coordinates.z}/${coordinates.x}');
      await dir.create(recursive: true);
      final File file = File('${dir.path}/${coordinates.y}.png');
      if (!file.existsSync()) {
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {
      // Persistance best-effort : ne doit jamais casser l'affichage.
    }
  }

  Future<ImageInfo> _decode(
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async {
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.Codec codec = await decode(buffer);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }
}

class _RateLimitException implements Exception {
  _RateLimitException(this.waitFor);
  final Duration? waitFor;
}

class _FetchException implements Exception {
  const _FetchException();
}