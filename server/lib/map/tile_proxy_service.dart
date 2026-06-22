/// Service proxy de tuiles OSM avec cache local (30 jours, validation
/// différentielle via `If-Modified-Since`).
///
/// Intercepte les requêtes de l'application StreetPhare vers la carte
/// (flutter_map / OpenStreetMap) et agit comme un middleware HTTP Shelf :
///
///   1. Si la tuile demandée est dans le cache local ET a moins de 30 jours,
///      la sert directement (sans appel à OSM).
///   2. Si la tuile est en cache mais a plus de 30 jours, interroge OSM
///      avec l'en-tête `If-Modified-Since`. Si OSM répond 304, réarme le
///      cache local. Sinon, met à jour le cache avec le nouveau contenu.
///   3. Si la tuile n'est pas en cache, la télécharge depuis OSM et la
///      stocke localement.
///
/// Utilisation dans server/bin/server.dart :
///
/// ```dart
/// import 'package:streetphare_server/map/tile_proxy_service.dart';
///
/// // Dans main() :
/// final tileProxy = TileProxyService(
///   cacheDir: 'tiles_cache',
///   userAgent: 'StreetPhare/2.2.0',
/// );
/// await tileProxy.init();
/// router.get('/tiles/<zoom>/<x>/<y>', tileProxy.handler);
/// ```

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

final _log = Logger('TileProxy');

/// Service proxy de tuiles OSM avec cache différentiel.
class TileProxyService {
  /// Répertoire racine du cache local.
  final String cacheDir;

  /// User-Agent à envoyer aux serveurs OSM (requis par la politique OSM).
  final String userAgent;

  /// Durée de validité du cache (30 jours par défaut).
  final Duration maxCacheAge;

  /// Timeout de connexion au serveur OSM.
  final Duration osmTimeout;

  /// URL du serveur de tuiles OSM.
  final String osmTileUrl;

  /// Compteur pour les statistiques.
  int _hits = 0;
  int _misses = 0;
  int _notModified = 0;

  TileProxyService({
    required this.cacheDir,
    this.userAgent = 'StreetPhare/2.2.0',
    this.maxCacheAge = const Duration(days: 30),
    this.osmTimeout = const Duration(seconds: 10),
    this.osmTileUrl = 'https://tile.openstreetmap.org',
  });

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Crée le répertoire de cache s'il n'existe pas.
  Future<void> init() async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      _log.info('Répertoire de cache créé : $cacheDir');
    }

    // Compte les tuiles déjà en cache
    final existing = await _countCachedFiles();
    _log.info('Cache initialisé : $existing tuiles existantes dans $cacheDir');
  }

  /// Retourne le nombre de fichiers dans le cache.
  Future<int> _countCachedFiles() async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;
    final contents = await dir.list(recursive: true).toList();
    return contents.whereType<File>().length;
  }

  // ---------------------------------------------------------------------------
  // Gestionnaire Shelf
  // ---------------------------------------------------------------------------

  /// Handler Shelf à monter dans le routeur.
  ///
  /// Exemple de route : `/tiles/<zoom>/<x>/<y>`.
  Future<Response> handler(Request request) async {
    final zoom = request.params['zoom'];
    final x = request.params['x'];
    final yRaw = request.params['y'];

    if (zoom == null || x == null || yRaw == null) {
      return Response.notFound('Paramètres zoom/x/y requis');
    }

    // Nettoyer l'extension .png si présente
    final y = yRaw.endsWith('.png') ? yRaw.substring(0, yRaw.length - 4) : yRaw;

    _log.fine('Tuile demandée : $zoom/$x/$y');

    try {
      return await _serveTile(
        zoom: zoom,
        x: x,
        y: y,
        ifModifiedSince: request.headers['if-modified-since'],
      );
    } catch (e, st) {
      _log.warning('Erreur tuile $zoom/$x/$y : $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Échec récupération tuile'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Logique de cache
  // ---------------------------------------------------------------------------

  /// Chemin du fichier de cache pour une tuile donnée.
  String _cachePath({required String zoom, required String x, required String y}) {
    return p.join(cacheDir, zoom, x, '$y.png');
  }

  /// Sert une tuile : cache → OSM (avec validation différentielle).
  Future<Response> _serveTile({
    required String zoom,
    required String x,
    required String y,
    String? ifModifiedSince,
  }) async {
    final cacheFile = File(_cachePath(zoom: zoom, x: x, y: y));

    // Étape 1 : Tuile déjà en cache ?
    if (await cacheFile.exists()) {
      final stat = await cacheFile.stat();
      final age = DateTime.now().difference(stat.modified);

      if (age < maxCacheAge) {
        // Cache FRESH → servir directement
        _hits++;
        _log.finest('HIT  $zoom/$x/$y (age=${age.inDays}j)');
        final bytes = await cacheFile.readAsBytes();
        return Response.ok(
          bytes,
          headers: _tileHeaders(bytes.length, stat.modified),
        );
      }

      // Cache EXPIRÉ → validation différentielle via If-Modified-Since
      _log.fine('EXPIRED $zoom/$x/$y (age=${age.inDays}j), validation OSM...');

      final osmResponse = await _fetchFromOsm(
        zoom: zoom,
        x: x,
        y: y,
        ifModifiedSince: _httpDate(stat.modified),
      );

      if (osmResponse.statusCode == 304) {
        // Non modifié → réarmer le cache
        _notModified++;
        _log.finest('304  $zoom/$x/$y (cache réarmé)');
        await cacheFile.setLastModified(DateTime.now());
        final bytes = await cacheFile.readAsBytes();
        return Response.ok(
          bytes,
          headers: _tileHeaders(bytes.length, DateTime.now()),
        );
      }

      // Modifié → mettre à jour le cache
      if (osmResponse.statusCode == 200) {
        _misses++;
        final body = await osmResponse.bodyBytes;
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsBytes(body);
        _log.fine('UPD  $zoom/$x/$y (${body.length} octets)');
        return Response.ok(
          body,
          headers: _tileHeaders(body.length, DateTime.now()),
        );
      }

      // Erreur OSM → servir le cache périmé (best-effort)
      _log.warning('OSM $zoom/$x/$y → HTTP ${osmResponse.statusCode}, sert cache périmé');
      final bytes = await cacheFile.readAsBytes();
      return Response.ok(
        bytes,
        headers: _tileHeaders(bytes.length, stat.modified),
      );
    }

    // Étape 2 : Pas de cache → télécharger depuis OSM
    _misses++;
    _log.fine('MISS $zoom/$x/$y → téléchargement OSM');

    final osmResponse = await _fetchFromOsm(
      zoom: zoom,
      x: x,
      y: y,
      ifModifiedSince: ifModifiedSince,
    );

    if (osmResponse.statusCode == 200) {
      final body = await osmResponse.bodyBytes;
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(body);
      return Response.ok(
        body,
        headers: _tileHeaders(body.length, DateTime.now()),
      );
    }

    // Tuile non disponible (404, 403, etc.)
    return Response(
      osmResponse.statusCode,
      headers: {
        'Content-Type': 'image/png',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Communication OSM
  // ---------------------------------------------------------------------------

  /// Récupère une tuile depuis le serveur OSM.
  Future<_OsmResponse> _fetchFromOsm({
    required String zoom,
    required String x,
    required String y,
    String? ifModifiedSince,
  }) async {
    final url = '$osmTileUrl/$zoom/$x/$y.png';
    final client = HttpClient();
    client.connectionTimeout = osmTimeout;

    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', userAgent);
      if (ifModifiedSince != null) {
        request.headers.set('If-Modified-Since', ifModifiedSince);
      }

      final response = await request.close().timeout(osmTimeout);
      final body = await response.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );

      return _OsmResponse(
        statusCode: response.statusCode,
        bodyBytes: body,
      );
    } catch (e) {
      _log.warning('OSM fetch $zoom/$x/$y : $e');
      return _OsmResponse(statusCode: 502, bodyBytes: []);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// En-têtes de réponse standard pour les tuiles.
  Map<String, String> _tileHeaders(int contentLength, DateTime lastModified) {
    return {
      'Content-Type': 'image/png',
      'Content-Length': contentLength.toString(),
      'Last-Modified': _httpDate(lastModified),
      'Cache-Control': 'public, max-age=${maxCacheAge.inSeconds}',
      'Access-Control-Allow-Origin': '*',
      'X-Tile-Cache': 'HIT',
    };
  }

  /// Formate une date selon le format HTTP (RFC 1123).
  String _httpDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[dt.weekday - 1]}, ${dt.day.toString().padLeft(2, '0')} '
        '${months[dt.month - 1]} ${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')} GMT';
  }

  /// Retourne les statistiques du cache.
  Map<String, dynamic> get stats => {
        'hits': _hits,
        'misses': _misses,
        'not_modified': _notModified,
        'total': _hits + _misses + _notModified,
      };
}

/// Réponse simplifiée d'une requête HTTP OSM.
class _OsmResponse {
  final int statusCode;
  final List<int> bodyBytes;

  _OsmResponse({required this.statusCode, required List<int> bodyBytes})
      : bodyBytes = List<int>.unmodifiable(bodyBytes);
}