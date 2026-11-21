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
//     1. Serveur StreetPhare   → {apiUrl}/route (moteur Dijkstra serveur)
//     2. OSRM public (fallback) → https://routing.openstreetmap.de/routed-foot
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
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../network/network_config.dart';
import '../core/danger_point.dart';
import '../core/models/routing_profile.dart';
import '../core/risk_score.dart';
import '../domain/models/route_result.dart';

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

// ══════════════════════════════════════════════════════════════════════════════
// OsmAndRoutingService
// ══════════════════════════════════════════════════════════════════════════════

/// Connecteurs réseau du routage (serveur StreetPhare + OsmAnd/OSRM).
///
/// Singleton accessible via [OsmAndRoutingService.instance].
///
/// Ces méthodes constituent les « tiers » réseau de la cascade de
/// connectivité orchestrée par le moteur central :
///   - [computeViaServer] : niveau 1 — Serveur StreetPhare (`/api/route`).
///   - [computeViaOsrm]   : dernier recours — OsmAnd / OSRM public.
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
  static const _kFDroidUrl = 'https://f-droid.org/packages/net.osmand.plus/';

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
  // ── Serveur StreetPhare ───────────────────────────────────────────────────

  /// Appel HTTP vers le moteur de routage du serveur StreetPhare.
  ///
  /// API : GET {apiUrl}/route?fromLat=..&fromLon=..&toLat=..&toLon=..
  ///
  /// Niveau 1 de la cascade de connectivité (avant le calcul local et OSRM).
  /// [timeout] (défaut : [_kHttpTimeout]) permet d'abaisser le délai en mode
  /// cascade rapide (ex: 2 s).
  Future<List<RouteResult>> computeViaServer({
    required LatLng start,
    required LatLng end,
    RoutingProfile profile = RoutingProfile.pedestrian,
    List<DangerPoint> avoidPoints = const [],
    Duration? timeout,
  }) async {
    final params = <String, String>{
      'fromLat': start.latitude.toString(),
      'fromLon': start.longitude.toString(),
      'toLat': end.latitude.toString(),
      'toLon': end.longitude.toString(),
      // Profil demandé au serveur : 'car' pour voiture/urgence, 'foot' sinon.
      'profile': (profile == RoutingProfile.vehicle ||
              profile == RoutingProfile.emergency)
          ? 'car'
          : 'foot',
    };
    if (avoidPoints.isNotEmpty) {
      // Chaque danger est envoyé avec son rayon ET son poids : les barrages
      // (poids quasi-infini) deviennent infranchissables côté serveur, les
      // autres dangers (poids ~1e6) sont fortement évités mais franchissables.
      params['avoid'] = avoidPoints
          .map((p) =>
              '${p.lat},${p.lon},${p.radiusMeters.round()},${p.weight.round()}')
          .join('|');
    }
    final uri = Uri.parse('${NetworkConfig.apiUrl}/route').replace(
      queryParameters: params,
    );

    try {
      final resp = await http.get(uri, headers: {
        'X-StreetPhare-Client': 'OsmAndBridge/1.3',
      }).timeout(timeout ?? _kHttpTimeout);

      if (resp.statusCode != 200) {
        debugPrint('[OsmAnd] ⚠ Serveur StreetPhare HTTP ${resp.statusCode}');
        return [];
      }

      return _parseServerResponse(resp.body, profile);
    } catch (e) {
      debugPrint('[OsmAnd] ❌ Serveur StreetPhare exception: $e');
      return [];
    }
  }

  /// Parse la réponse JSON du serveur StreetPhare.
  ///
  /// Format attendu :
  /// ```json
  /// {"source":"streetphare_server",
  ///  "routes":[{"points":[[lat,lon],...],"distanceMeters":1234,
  ///            "durationSeconds":890}]}
  /// ```
  List<RouteResult> _parseServerResponse(String body, RoutingProfile profile) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final routes = json['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) return [];

    final isVehicle = profile == RoutingProfile.vehicle ||
        profile == RoutingProfile.emergency;
    final results = <RouteResult>[];
    for (int i = 0; i < routes.length; i++) {
      final r = routes[i] as Map<String, dynamic>;
      final rawPoints = r['points'] as List<dynamic>? ?? [];
      final points = <LatLng>[];
      for (final pt in rawPoints) {
        if (pt is List && pt.length >= 2) {
          final lat = (pt[0] as num).toDouble();
          final lon = (pt[1] as num).toDouble();
          if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
            points.add(LatLng(lat, lon));
          }
        }
      }
      if (points.length < 2) continue;

      final distM = (r['distanceMeters'] as num?)?.toDouble() ?? 0;

      results.add(RouteResult(
        id: i == 0 ? 'sp_server_primary' : 'sp_server_alt$i',
        points: points,
        totalDistanceMeters: distM,
        totalRiskScore: 0,
        pois: const [],
        label: i == 0
            ? '🏠 Itinéraire ${isVehicle ? 'voiture' : 'piéton'} (serveur StreetPhare)'
            : '🛤 Alternative StreetPhare $i',
      ));
    }
    return results;
  }

  // ── OSRM public ──────────────────────────────────────────────────────────

  /// Appel HTTP vers OSRM public.
  ///
  /// Endpoint OSRM public : GET https://router.project-osrm.org/route/v1/{profile}/...
  /// Le démo public Project OSRM expose un graphe européen pour les profils
  /// 'driving' **et** 'foot'. L'ancienne instance
  /// `routing.openstreetmap.de/routed-foot` est fermée depuis 2020.
  ///
  /// Dernier recours de la cascade (OsmAnd) : OSRM ne peut PAS éviter les
  /// zones de danger, on filtre donc ici les itinéraires qui en traversent une.
  Future<List<RouteResult>> computeViaOsrm({
    required LatLng start,
    required LatLng end,
    RoutingProfile profile = RoutingProfile.pedestrian,
    List<DangerPoint> avoidPoints = const [],
  }) async {
    final isVehicle = profile == RoutingProfile.vehicle ||
        profile == RoutingProfile.emergency;
    final osrmProfile = isVehicle ? 'driving' : 'foot';

    // router.project-osrm.org sert les deux profils (driving + foot).
    const baseUrl = 'https://router.project-osrm.org/route/v1';

    final uri = Uri.parse(
      '$baseUrl/$osrmProfile/'
      '${start.longitude.toStringAsFixed(6)},${start.latitude.toStringAsFixed(6)};'
      '${end.longitude.toStringAsFixed(6)},${end.latitude.toStringAsFixed(6)}'
      '?overview=full&geometries=geojson&alternatives=true',
    );

    final profileLabel = isVehicle ? 'car' : 'foot';

    if (kDebugMode) {
      debugPrint('[OsmAnd] 🔗 OSRM $profileLabel URL: $uri');
    }

    try {
      final resp = await http.get(uri, headers: {
        'User-Agent': 'StreetPhare/1.3 OsmAndBridge',
      }).timeout(_kHttpTimeout);

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[OsmAnd] ❌ OSRM HTTP ${resp.statusCode}: ${resp.body}');
        }
        return [];
      }

      final routes = _parseOsrmResponse(resp.body, profile);
      // OSRM ne sait pas éviter les zones de danger : on rejette ici les
      // itinéraires qui en traversent une (sinon on proposerait un tracé
      // dangereux). Si tout est rejeté, l'appelant retombe sur l'échec.
      if (avoidPoints.isNotEmpty) {
        final dangerLatLngs = avoidPoints.map((p) => p.latLng).toList();
        final safeRoutes = routes
            .where((r) => !routeCrossesDanger(r.points, dangerLatLngs))
            .toList();
        if (kDebugMode) {
          debugPrint('[OsmAnd] ✅ OSRM $profileLabel → ${safeRoutes.length} '
              'route(s) sûre(s) sur ${routes.length}');
        }
        return safeRoutes;
      }
      if (kDebugMode) {
        debugPrint('[OsmAnd] ✅ OSRM $profileLabel → ${routes.length} route(s)');
      }
      return routes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OsmAnd] ❌ OSRM exception: $e');
      }
      return [];
    }
  }

  /// Parse la réponse JSON OSRM de manière robuste.
  ///
  /// En cas de format JSON inattendu, retourne une liste vide
  /// plutôt que de crasher l'application.
  List<RouteResult> _parseOsrmResponse(String body, RoutingProfile profile) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final status = json['code'] as String? ?? '';
      if (status != 'Ok') {
        if (kDebugMode) {
          debugPrint('[OsmAnd] OSRM status non-Ok: $status');
        }
        return [];
      }

      final routes = json['routes'] as List<dynamic>? ?? [];
      final results = <RouteResult>[];

      for (int i = 0; i < routes.length; i++) {
        try {
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
                ? '🌍 Itinéraire ${profile == RoutingProfile.vehicle || profile == RoutingProfile.emergency ? 'voiture' : 'piéton'} OSM (OSRM)'
                : '🛤 Alternative OSRM $i',
          ));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[OsmAnd] Erreur parsing route $i: $e');
          }
          // Continue avec les autres routes.
        }
      }
      return results;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OsmAnd] ❌ Erreur parsing JSON OSRM: $e');
      }
      return [];
    }
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
}
