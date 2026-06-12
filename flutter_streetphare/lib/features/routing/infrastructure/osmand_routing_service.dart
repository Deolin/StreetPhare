// lib/features/routing/infrastructure/osmand_routing_service.dart
//
// Connecteur OsmAnd — Moteur de routage piéton strict sur rue.
// StreetPhare v1.3 · 2026-06-11
//
// ════════════════════════════════════════════════════════════════════════════
// DEUX MODES D'INTÉGRATION
// ════════════════════════════════════════════════════════════════════════════
//
//   MODE A — ExternalLaunch (navigation guidée dans OsmAnd)
//   ─────────────────────────────────────────────────────
//   Lance l'application OsmAnd installée sur l'appareil via le schéma
//   d'URL `osmand.api://navigate?...` avec le profil PEDESTRIAN.
//   Idéal pour :
//     • les malvoyants (guidage vocal intégré OsmAnd)
//     • la navigation hors-ligne (cartes OsmAnd hors réseau)
//   L'utilisateur voit l'itinéraire piéton complet dans OsmAnd.
//
//   MODE B — InternalPolyline (rendu dans flutter_map SafeRouteLayer)
//   ──────────────────────────────────────────────────────────────────
//   Appel HTTP au moteur de routage :
//     1. GraphHopper local     → http://192.168.31.18:8080 (profil foot)
//     2. OSRM public (fallback) → https://router.project-osrm.org   (foot)
//   Retourne une List<LatLng> strictement conforme au réseau routier
//   OpenStreetMap (trottoirs, chemins piétons, passages). Ces points
//   sont injectés dans `RouteResult.points` pour affichage dans la carte.
//
// ════════════════════════════════════════════════════════════════════════════
// SCÉNARIOS DE TEST — Fleurus 6220, Belgique
// ════════════════════════════════════════════════════════════════════════════
//
//   • "Tour de Fleurus"          : Place Communale → Château de Namur loop
//   • "Traversée des écoles"     : Institut Notre-Dame → Athénée R. Jourdan
//   • "Cortège de la police"     : Hôtel de Ville → Place Albert 1er
//
// Les zones de dangers validés (≥3 votes à <30 m) sont transmises
// comme `avoid_locations` à GraphHopper ou comme via-points interdits.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models/avoidance_filters.dart';
import '../domain/models/route_result.dart';
import '../../../network/network_config.dart';
import 'osmand_native_channel.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Enums & constantes
// ══════════════════════════════════════════════════════════════════════════════

/// Mode d'intégration OsmAnd.
enum OsmAndMode {
  /// Lance l'app OsmAnd sur l'appareil (guidage vocal, hors-ligne).
  externalLaunch,

  /// Calcule la polyline via HTTP et l'injecte dans flutter_map.
  internalPolyline,
}

/// Résultat du calcul OsmAnd interne.
class OsmAndResult {
  const OsmAndResult({
    required this.routes,
    required this.source,
    this.errorMessage,
  });

  /// Liste d'itinéraires calculés (points strictement sur rue).
  final List<RouteResult> routes;

  /// Source utilisée : 'graphhopper_local', 'osrm_public', ou 'fallback'.
  final String source;

  /// Message d'erreur si le calcul a échoué (null si succès).
  final String? errorMessage;

  bool get hasError => errorMessage != null;
  bool get isEmpty => routes.isEmpty;
}

// ══════════════════════════════════════════════════════════════════════════════
// OsmAndRoutingService
// ══════════════════════════════════════════════════════════════════════════════

/// Service de routage piéton via OsmAnd.
///
/// Singleton accessible via [OsmAndRoutingService.instance].
///
/// Usage typique (Mode Interne) :
/// ```dart
/// final result = await OsmAndRoutingService.instance.computeRoutes(
///   start: userPosition,
///   end: eventPosition,
///   filters: avoidanceFilters,
///   avoidPoints: validatedDangers,
/// );
/// if (!result.isEmpty) {
///   // Afficher result.routes dans SafeRouteLayer
/// }
/// ```
///
/// Usage typique (Mode Externe) :
/// ```dart
/// await OsmAndRoutingService.instance.launchExternalNavigation(
///   start: userPosition,
///   end: eventPosition,
///   onNotInstalled: () => OsmAndRoutingService.instance.openInstallPage(),
/// );
/// ```
class OsmAndRoutingService {
  OsmAndRoutingService._();
  static final OsmAndRoutingService instance = OsmAndRoutingService._();

  // ── Constantes ──────────────────────────────────────────────────────────────

  // Packages Android déclarés dans AndroidManifest.xml <queries> :
  //   net.osmand      → OsmAnd Free
  //   net.osmand.plus → OsmAnd+
  // La détection d'installation utilise le schéma d'URL ci-dessous.

  /// Schéma d'URL pour l'API OsmAnd.
  static const _kOsmAndScheme = 'osmand.api';

  /// URL Play Store pour OsmAnd.
  static const _kPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=net.osmand';

  /// URL F-Droid pour OsmAnd (alternative libre).
  static const _kFDroidUrl =
      'https://f-droid.org/packages/net.osmand.plus/';

  /// Port du serveur GraphHopper local.
  static const int _kGraphHopperPort = 8080;

  /// Timeout HTTP pour les requêtes de routage.
  static const Duration _kHttpTimeout = Duration(seconds: 12);

  // ── État ────────────────────────────────────────────────────────────────────

  OsmAndMode _mode = OsmAndMode.internalPolyline;

  OsmAndMode get currentMode => _mode;

  void setMode(OsmAndMode mode) {
    _mode = mode;
    if (kDebugMode) debugPrint('[OsmAnd] Mode → $mode');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODE A — EXTERNAL LAUNCH
  // ══════════════════════════════════════════════════════════════════════════

  /// Vérifie si OsmAnd (libre ou +) est installé sur l'appareil.
  ///
  /// Sur Android, requiert `<queries>` dans AndroidManifest.xml.
  /// Sur d'autres plateformes, retourne toujours `false`.
  Future<bool> isOsmAndInstalled() async {
    if (!Platform.isAndroid) return false;
    // OsmAnd Free (net.osmand) et OsmAnd+ (net.osmand.plus) partagent
    // le même schéma d'URL osmand.api:// — un seul appel suffit.
    // La distinction Free/Plus n'est possible qu'en interrogeant le
    // PackageManager Android, ce qui n'est pas nécessaire ici.
    final osmAndUri = Uri.parse('$_kOsmAndScheme://navigate?');
    try {
      return await canLaunchUrl(osmAndUri);
    } catch (_) {
      return false;
    }
  }

  /// Lance la navigation piétonne dans l'application OsmAnd.
  ///
  /// Si OsmAnd n'est pas installé, appelle [onNotInstalled].
  ///
  /// Paramètres OsmAnd :
  ///   - `start_lat / start_lon` : position de départ
  ///   - `dest_lat / dest_lon`   : destination
  ///   - `profile`               : `pedestrian` (piéton)
  ///   - `route`                 : `PEDESTRIAN`
  Future<bool> launchExternalNavigation({
    required LatLng start,
    required LatLng end,
    String destinationName = 'Destination',
    VoidCallback? onNotInstalled,
  }) async {
    if (!Platform.isAndroid) {
      // Sur iOS / Desktop : ouvrir dans le navigateur web OsmAnd
      return _launchWebOsmAnd(end: end, name: destinationName);
    }

    final installed = await isOsmAndInstalled();
    if (!installed) {
      if (kDebugMode) debugPrint('[OsmAnd] Not installed — calling fallback');
      onNotInstalled?.call();
      return false;
    }

    // Construction de l'URI OsmAnd navigate
    // Ref: https://osmand.net/docs/technical/osmand-api-protocol/navigate
    final uri = Uri(
      scheme: _kOsmAndScheme,
      host: 'navigate',
      queryParameters: {
        'start_lat': start.latitude.toStringAsFixed(6),
        'start_lon': start.longitude.toStringAsFixed(6),
        'dest_lat': end.latitude.toStringAsFixed(6),
        'dest_lon': end.longitude.toStringAsFixed(6),
        'dest_name': Uri.encodeComponent(destinationName),
        'profile': 'pedestrian',
        'route': 'PEDESTRIAN',
      },
    );

    if (kDebugMode) debugPrint('[OsmAnd] Launching: $uri');

    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[OsmAnd] Launch error: $e');
      return false;
    }
  }

  /// Ouvre la page de destination dans un navigateur web OsmAnd
  /// (fallback iOS / Desktop).
  Future<bool> _launchWebOsmAnd({
    required LatLng end,
    String name = 'Destination',
  }) async {
    final uri = Uri.parse(
      'https://osmand.net/go?lat=${end.latitude.toStringAsFixed(6)}'
      '&lon=${end.longitude.toStringAsFixed(6)}&z=16',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Ouvre la page d'installation d'OsmAnd (Play Store → F-Droid).
  Future<bool> openInstallPage() async {
    final playUri = Uri.parse(_kPlayStoreUrl);
    if (await canLaunchUrl(playUri)) {
      return launchUrl(playUri, mode: LaunchMode.externalApplication);
    }
    final fdUri = Uri.parse(_kFDroidUrl);
    return launchUrl(fdUri, mode: LaunchMode.externalApplication);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODE B — INTERNAL POLYLINE (HTTP → LatLng list → SafeRouteLayer)
  // ══════════════════════════════════════════════════════════════════════════

  /// Calcule un itinéraire piéton strict sur rue.
  ///
  /// Ordre de priorité :
  ///   0. MethodChannel Android (GraphHopper embarqué + OSM offline) — PRIORITAIRE
  ///   1. GraphHopper HTTP local (`192.168.31.18:8080`) — profil foot
  ///   2. OSRM public demo  (`router.project-osrm.org`)  — foot
  ///   3. Retourne [OsmAndResult] vide (erreur remontée à l'appelant)
  ///
  /// [avoidPoints] : liste de LatLng à éviter (dangers validés ≥3 votes).
  Future<OsmAndResult> computeRoutes({
    required LatLng start,
    required LatLng end,
    required AvoidanceFilters filters,
    List<LatLng> avoidPoints = const [],
    String? eventId,
  }) async {
    // ── Tentative 0 (PRIORITAIRE) : MethodChannel Android (GraphHopper embarqué)
    final native = OsmAndNativeChannel.instance;
    if (native.isSupported) {
      try {
        final avoidPointsNative = avoidPoints
            .map((p) => AvoidPoint(lat: p.latitude, lon: p.longitude))
            .toList();

        final nativeResult = await native.computeRoute(
          start: start,
          end: end,
          avoidPoints: avoidPointsNative,
        );

        if (!nativeResult.isEmpty) {
          if (kDebugMode) {
            debugPrint('[OsmAnd] ✅ GraphHopper EMBARQUÉ (${nativeResult.source}) → '
                '${nativeResult.routes.first.points.length} points');
          }
          return OsmAndResult(
            routes: nativeResult.routes,
            source: nativeResult.source,
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[OsmAnd] Native channel failed: $e');
      }
    }

    // ── Tentative 1 : GraphHopper local (HTTP) ───────────────────────────────
    try {
      final ghRoutes = await _computeViaGraphHopper(
        start: start,
        end: end,
        avoidPoints: avoidPoints,
        filters: filters,
      );
      if (ghRoutes.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[OsmAnd] ✅ GraphHopper local → '
              '${ghRoutes.first.points.length} points');
        }
        return OsmAndResult(routes: ghRoutes, source: 'graphhopper_local');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[OsmAnd] GraphHopper failed: $e');
    }

    // ── Tentative 2 : OSRM public ─────────────────────────────────────────
    try {
      final osrmRoutes = await _computeViaOsrmPublic(
        start: start,
        end: end,
      );
      if (osrmRoutes.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[OsmAnd] ✅ OSRM public → '
              '${osrmRoutes.first.points.length} points');
        }
        return OsmAndResult(routes: osrmRoutes, source: 'osrm_public');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[OsmAnd] OSRM failed: $e');
    }

    // ── Échec total ──────────────────────────────────────────────────────────
    return const OsmAndResult(
      routes: [],
      source: 'fallback',
      errorMessage: 'Moteur de routage inaccessible. '
          'Vérifiez la connexion réseau ou activez le mode hors-ligne.',
    );
  }

  // ── GraphHopper local ─────────────────────────────────────────────────────

  /// Appel HTTP vers GraphHopper local sur port [_kGraphHopperPort].
  ///
  /// API : GET /route?point={lat,lon}&point={lat,lon}&profile=foot
  Future<List<RouteResult>> _computeViaGraphHopper({
    required LatLng start,
    required LatLng end,
    required AvoidanceFilters filters,
    List<LatLng> avoidPoints = const [],
  }) async {
    final host = NetworkConfig.primaryServer
        .replaceAll(RegExp(r':3000|:3001'), ':$_kGraphHopperPort');

    // Construit l'URL de base avec les deux points et le profil piéton.
    // Les zones à éviter (block_area) sont ajoutées conditionnellement
    // afin d'être réellement transmises à GraphHopper.
    final uriBuffer = StringBuffer(
      '$host/route'
      '?point=${start.latitude},${start.longitude}'
      '&point=${end.latitude},${end.longitude}'
      '&profile=foot'
      '&type=json'
      '&calc_points=true'
      '&instructions=false',
    );

    // Zones bloquées (dangers validés ≥ 3 votes, <30 m).
    // Format GraphHopper : "lat,lon|lat,lon|..."
    if (avoidPoints.isNotEmpty) {
      final blockArea = avoidPoints
          .map((p) => '${p.latitude},${p.longitude}')
          .join('|');
      uriBuffer.write('&block_area=${Uri.encodeComponent(blockArea)}');
    }

    final uri = Uri.parse(uriBuffer.toString());

    final client = HttpClient()
      ..connectionTimeout = _kHttpTimeout;

    try {
      final req = await client.getUrl(uri);
      req.headers.set('X-StreetPhare-Client', 'OsmAndBridge/1.3');
      final resp = await req.close().timeout(_kHttpTimeout);
      final body = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) return [];

      return _parseGraphHopperResponse(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Parse la réponse JSON GraphHopper.
  ///
  /// Format attendu :
  /// ```json
  /// {"paths":[{"points":{"coordinates":[[lon,lat],...]},
  ///            "distance":1234,"time":890000}]}
  /// ```
  List<RouteResult> _parseGraphHopperResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final paths = json['paths'] as List<dynamic>? ?? [];
    if (paths.isEmpty) return [];

    final results = <RouteResult>[];
    for (int i = 0; i < paths.length; i++) {
      final path = paths[i] as Map<String, dynamic>;
      final geometry = path['points'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      final coords = geometry['coordinates'] as List<dynamic>? ?? [];
      final points = _coordsToLatLng(coords);
      if (points.length < 2) continue;

      final distM = (path['distance'] as num?)?.toDouble() ?? 0;

      results.add(RouteResult(
        id: i == 0 ? 'osmand_gh_primary' : 'osmand_gh_alt$i',
        points: points,
        totalDistanceMeters: distM,
        totalRiskScore: 0,
        pois: const [],
        label: i == 0
            ? '🧭 Itinéraire piéton OsmAnd (GraphHopper)'
            : '🛤 Alternative OsmAnd $i',
      ));
    }
    return results;
  }

  // ── OSRM public ──────────────────────────────────────────────────────────

  /// Appel HTTP vers OSRM public demo en mode foot.
  ///
  /// Endpoint : GET /route/v1/foot/{lon1},{lat1};{lon2},{lat2}
  ///            ?overview=full&geometries=geojson
  Future<List<RouteResult>> _computeViaOsrmPublic({
    required LatLng start,
    required LatLng end,
  }) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/foot/'
      '${start.longitude.toStringAsFixed(6)},${start.latitude.toStringAsFixed(6)};'
      '${end.longitude.toStringAsFixed(6)},${end.latitude.toStringAsFixed(6)}'
      '?overview=full&geometries=geojson&alternatives=true',
    );

    final client = HttpClient()
      ..connectionTimeout = _kHttpTimeout;

    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'StreetPhare/1.3 OsmAndBridge');
      final resp = await req.close().timeout(_kHttpTimeout);
      final body = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) return [];

      return _parseOsrmResponse(body);
    } finally {
      client.close(force: true);
    }
  }

  /// Parse la réponse JSON OSRM.
  ///
  /// Format attendu :
  /// ```json
  /// {"routes":[{
  ///   "geometry":{"coordinates":[[lon,lat],...],"type":"LineString"},
  ///   "distance":1234.5,"duration":890
  /// }]}
  /// ```
  List<RouteResult> _parseOsrmResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final status = json['code'] as String? ?? '';
    if (status != 'Ok') return [];

    final routes = json['routes'] as List<dynamic>? ?? [];
    final results = <RouteResult>[];

    for (int i = 0; i < routes.length; i++) {
      final route = routes[i] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      final coords = geometry['coordinates'] as List<dynamic>? ?? [];
      final points = _coordsToLatLng(coords);
      if (points.length < 2) continue;

      final distM = (route['distance'] as num?)?.toDouble() ?? 0;

      results.add(RouteResult(
        id: i == 0 ? 'osmand_osrm_primary' : 'osmand_osrm_alt$i',
        points: points,
        totalDistanceMeters: distM,
        totalRiskScore: 0,
        pois: const [],
        label: i == 0
            ? '🌍 Itinéraire piéton OSM (OSRM public)'
            : '🛤 Alternative OSRM $i',
      ));
    }
    return results;
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  /// Convertit une liste GeoJSON coordinates `[[lon, lat], ...]`
  /// en liste `LatLng`.
  ///
  /// ⚠️ GeoJSON stocke [longitude, latitude] — on les inverse ici.
  List<LatLng> _coordsToLatLng(List<dynamic> coords) {
    final result = <LatLng>[];
    for (final c in coords) {
      if (c is! List || c.length < 2) continue;
      final lon = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      // Validation basique des coordonnées GPS
      if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
        result.add(LatLng(lat, lon));
      }
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCÉNARIOS FLEURUS (coordonnées de test)
  // ══════════════════════════════════════════════════════════════════════════

  /// Points de référence pour les tests à Fleurus, Belgique (6220).
  static const Map<String, LatLng> fleurusWaypoints = {
    // Scénario 1 : Tour de Fleurus
    'place_communale':       LatLng(50.4818, 4.5492),
    'chateau_namur':         LatLng(50.4802, 4.5448),

    // Scénario 2 : Traversée des écoles
    'institut_notre_dame':   LatLng(50.4835, 4.5512),
    'athenee_jourdan':       LatLng(50.4849, 4.5468),

    // Scénario 3 : Cortège de la police
    'hotel_de_ville':        LatLng(50.4820, 4.5490),
    'place_albert':          LatLng(50.4831, 4.5502),
  };

  /// Calcule l'itinéraire pour un scénario de test Fleurus.
  ///
  /// [scenarioKey] : clé dans [fleurusWaypoints] (ex: 'traversee_ecoles').
  Future<OsmAndResult> computeFleurusScenario(String scenarioKey) async {
    final scenarios = {
      'tour_fleurus': ('place_communale', 'chateau_namur'),
      'traversee_ecoles': ('institut_notre_dame', 'athenee_jourdan'),
      'cortege_police': ('hotel_de_ville', 'place_albert'),
    };

    final pair = scenarios[scenarioKey];
    if (pair == null) {
      return OsmAndResult(
        routes: const [],
        source: 'error',
        errorMessage: 'Scénario inconnu : $scenarioKey',
      );
    }

    final start = fleurusWaypoints[pair.$1]!;
    final end = fleurusWaypoints[pair.$2]!;

    if (kDebugMode) {
      debugPrint('[OsmAnd] 🗺 Test Fleurus "$scenarioKey": '
          '${start.latitude},${start.longitude} → '
          '${end.latitude},${end.longitude}');
    }

    return computeRoutes(
      start: start,
      end: end,
      filters: const AvoidanceFilters(),
    );
  }
}
