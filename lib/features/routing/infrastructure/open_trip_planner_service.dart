// lib/features/routing/infrastructure/open_trip_planner_service.dart
//
// Connecteur OpenTripPlanner (OTP) — profil « transports en commun ».
//
// OpenTripPlanner est le moteur de référence pour les itinéraires
// multi-paliers (marche + bus/métro/tram/train). Ce service interroge
// l'API REST d'une instance OTP2 (endpoint `/plan`) et convertit les
// itinéraires retournés (qui combinent plusieurs "legs") en une liste de
// `RouteResult` directement traçable par SafeRouteLayer :
//   * les géométries de chaque leg (GeoJSON OU polyline encodée) sont
//     concaténées dans l'ordre du trajet ;
//   * la distance est déduite de la somme des legs ;
//   * la durée réelle (avec correspondances/attente) est conservée dans
//     `RouteResult.duration` afin que l'UI n'affiche pas une estimation
//     "à pied" erronée.
//
// Configuration :
//   L'URL du router est fournie par `NetworkConfig.otpBaseUrl`, surchargeable
//   via `--dart-define=STREETPHARE_OTP_URL=...`. Si OTP est indisponible ou
//   non configuré, `plan()` retourne une liste vide et l'appelant retombe
//   sur un profil piéton de rabattement (cascade habituelle du RoutingEngine).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../network/network_config.dart';
import '../domain/models/route_result.dart';

/// Service de calcul d'itinéraires en transports en commun via OpenTripPlanner.
class OpenTripPlannerService {
  OpenTripPlannerService._();
  static final OpenTripPlannerService instance = OpenTripPlannerService._();

  /// Timeout HTTP — OTP peut être lent lors de la première requête.
  static const Duration _kHttpTimeout = Duration(seconds: 20);

  /// Précision de l'encodage polyline (Google/OTP) : 1e5.
  static const double _kPolylinePrecision = 1e5;

  /// Vrai si une URL OTP est configurée (le service est alors actif).
  bool get isConfigured => NetworkConfig.otpBaseUrl.isNotEmpty;

  /// Calcule jusqu'à [maxItineraries] itinéraires TC entre [start] et [end].
  ///
  /// Retourne une liste vide si OTP n'est pas configuré, est injoignable ou
  /// ne trouve aucun trajet (l'appelant doit alors dégrader en piéton).
  Future<List<RouteResult>> plan({
    required LatLng start,
    required LatLng end,
    int maxItineraries = 3,
  }) async {
    if (!isConfigured) {
      if (kDebugMode) {
        debugPrint('[OTP] OpenTripPlanner non configuré — repli piéton.');
      }
      return const [];
    }

    final now = DateTime.now();
    final uri = Uri.parse('${NetworkConfig.otpBaseUrl}/plan').replace(
      queryParameters: {
        'fromPlace': '${start.latitude},${start.longitude}',
        'toPlace': '${end.latitude},${end.longitude}',
        'mode': 'TRANSIT,WALK',
        'numItineraries': '$maxItineraries',
        'date': _formatDate(now),
        'time': _formatTime(now),
        'arriveBy': 'false',
        'locale': 'fr',
      },
    );

    if (kDebugMode) {
      debugPrint('[OTP] Requête TC → $uri');
    }

    try {
      final resp = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(_kHttpTimeout);

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[OTP] ⚠ HTTP ${resp.statusCode} — repli piéton.');
        }
        return const [];
      }
      return _parsePlan(resp.body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OTP] ❌ Échec OpenTripPlanner: $e — repli piéton.');
      }
      return const [];
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  List<RouteResult> _parsePlan(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];

      final plan = decoded['plan'];
      if (plan is! Map<String, dynamic>) {
        final error = decoded['error'];
        final message = error is Map<String, dynamic>
            ? (error['msg'] ?? error['message'])
            : error;
        if (kDebugMode) {
          debugPrint('[OTP] ⚠ Aucun plan : $message');
        }
        return const [];
      }

      final itineraries = plan['itineraries'];
      if (itineraries is! List) return const [];

      final results = <RouteResult>[];
      for (var i = 0; i < itineraries.length; i++) {
        final itin = itineraries[i];
        if (itin is! Map<String, dynamic>) continue;
        final route = _itineraryToRoute(itin, i);
        if (route != null) results.add(route);
      }
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('[OTP] ❌ Erreur parsing plan: $e');
      return const [];
    }
  }

  RouteResult? _itineraryToRoute(Map<String, dynamic> itin, int index) {
    final legs = itin['legs'];
    if (legs is! List) return null;

    final points = <LatLng>[];
    final transitModes = <String>{};
    double distanceM = 0;

    for (final rawLeg in legs) {
      if (rawLeg is! Map<String, dynamic>) continue;
      final mode = (rawLeg['mode'] as String? ?? 'WALK').toUpperCase();
      if (mode != 'WALK') transitModes.add(mode);

      final legDistance = (rawLeg['distance'] as num?)?.toDouble() ?? 0;
      distanceM += legDistance;

      // Concatène la géométrie du leg en évitant les doublons de jonction.
      for (final p in _decodeLegGeometry(rawLeg)) {
        if (points.isEmpty || const Distance().distance(points.last, p) > 0.5) {
          points.add(p);
        }
      }
    }

    if (points.length < 2) return null;

    // Distance de repli : si aucun leg ne fournit de distance, on mesure
    // la géométrie décodée (haversine cumulée).
    if (distanceM <= 0) {
      distanceM = _geometryDistance(points);
    }

    final durationSec = (itin['duration'] as num?)?.toDouble();

    return RouteResult(
      id: index == 0 ? 'otp_primary' : 'otp_alt$index',
      points: points,
      totalDistanceMeters: distanceM,
      totalRiskScore: 0,
      pois: const [],
      duration:
          durationSec == null ? null : Duration(seconds: durationSec.round()),
      label: _buildLabel(index, transitModes.length),
    );
  }

  /// Décode la géométrie d'un leg, en supportant indifféremment :
  ///   1. GeoJSON `legGeometry.coordinates` ([[lon, lat], ...])
  ///   2. Polyline encodée `legGeometry.points` (chaîne Google/OTP)
  ///
  /// L'ordre de coordonnées GeoJSON est [longitude, latitude] — inversé ici.
  List<LatLng> _decodeLegGeometry(Map<String, dynamic> leg) {
    final src = leg['legGeometry'];
    final geometry = src is Map<String, dynamic>
        ? src
        : (leg['geometry'] is Map<String, dynamic>
            ? leg['geometry'] as Map<String, dynamic>
            : null);
    if (geometry == null) return const [];

    // 1) GeoJSON LineString.
    final coords = geometry['coordinates'];
    if (coords is List) {
      final pts = <LatLng>[];
      for (final c in coords) {
        if (c is! List || c.length < 2) continue;
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        if (lat.isFinite && lon.isFinite) pts.add(LatLng(lat, lon));
      }
      if (pts.isNotEmpty) return pts;
    }

    // 2) Polyline encodée.
    final encoded = geometry['points'];
    if (encoded is String && encoded.isNotEmpty) {
      return _decodePolyline(encoded);
    }

    return const [];
  }

  /// Décode une polyline encodée (algorithme Google, ordre lat/lon).
  List<LatLng> _decodePolyline(String encoded) {
    final pts = <LatLng>[];
    var idx = 0;
    var lat = 0;
    var lng = 0;

    while (idx < encoded.length) {
      var shift = 0;
      var result = 0;
      var b = 0;
      do {
        b = encoded.codeUnitAt(idx++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(idx++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lng += dLng;

      pts.add(LatLng(lat / _kPolylinePrecision, lng / _kPolylinePrecision));
    }
    return pts;
  }

  double _geometryDistance(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += const Distance().distance(points[i - 1], points[i]);
    }
    return total;
  }

  String _buildLabel(int index, int transitLegCount) {
    if (index == 0) {
      return transitLegCount > 0
          ? '🚆 Itinéraire transports en commun (OTP)'
          : '🚶 Itinéraire piéton (OTP)';
    }
    return 'Alternative TC $index';
  }

  // ── Formatage datation ────────────────────────────────────────────────────

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}
