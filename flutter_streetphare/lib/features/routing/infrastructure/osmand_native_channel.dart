// lib/features/routing/infrastructure/osmand_native_channel.dart
//
// Canal Dart ↔ Android pour le moteur GraphHopper embarqué.
// StreetPhare v1.3 · 2026-06-11
//
// Ce fichier est le côté Dart du MethodChannel "com.streetphare/routing".
// Il communique avec [OsmAndBridgePlugin.kt] (Android) pour calculer
// des itinéraires piétons 100% offline via GraphHopper Core.
//
// Cascade de priorité :
//   1. MethodChannel Android (GraphHopper embarqué + OSM data local)
//   2. HTTP GraphHopper local (192.168.31.18:8080) — si moteur non prêt
//   3. OSRM public (internet) — fallback ultime

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../domain/models/route_result.dart';

// ════════════════════════════════════════════════════════════════════════════
// OsmAndNativeChannel
// ════════════════════════════════════════════════════════════════════════════

/// Pont Dart vers le moteur GraphHopper natif Android.
///
/// Sur les plateformes non-Android (Windows, iOS, macOS), retourne
/// immédiatement [NativeRouteResult.platformUnsupported].
///
/// Usage :
/// ```dart
/// final ch = OsmAndNativeChannel();
/// final result = await ch.computeRoute(
///   start: LatLng(50.4818, 4.5492),
///   end:   LatLng(50.4849, 4.5468),
///   avoidPoints: validatedDangerList,
/// );
/// if (!result.isEmpty) {
///   // résultat.routes disponibles
/// }
/// ```
class OsmAndNativeChannel {
  OsmAndNativeChannel._();
  static final OsmAndNativeChannel instance = OsmAndNativeChannel._();

  static const _channel = MethodChannel('com.streetphare/routing');

  // ── Platform guard ───────────────────────────────────────────────────────

  /// Retourne true si le canal natif est disponible (Android seulement).
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  // ── Vérification de l'état du moteur ─────────────────────────────────────

  /// Vérifie si le moteur GraphHopper est initialisé et prêt.
  ///
  /// Retourne `false` si non-Android ou si le fichier OSM est manquant.
  Future<bool> isEngineReady() async {
    if (!isSupported) return false;
    try {
      final ready = await _channel.invokeMethod<bool>('isEngineReady');
      return ready ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Déclenche l'initialisation du moteur en arrière-plan.
  ///
  /// Appeler au démarrage de l'app (dans `main.dart`) pour préparer
  /// le graphe avant la première demande de route.
  Future<void> initEngine() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('initEngine');
      if (kDebugMode) debugPrint('[NativeChannel] initEngine → OK');
    } catch (e) {
      if (kDebugMode) debugPrint('[NativeChannel] initEngine error: $e');
    }
  }

  // ── Calcul d'itinéraire principal ─────────────────────────────────────────

  /// Calcule l'itinéraire piéton principal (route recommandée).
  ///
  /// [avoidPoints] : zones de danger validées par le réseau P2P
  ///   (≥3 votes, <30 m) — transmises comme `block_area` à GraphHopper.
  Future<NativeRouteResult> computeRoute({
    required LatLng start,
    required LatLng end,
    List<AvoidPoint> avoidPoints = const [],
  }) async {
    if (!isSupported) return NativeRouteResult.platformUnsupported;

    try {
      final rawResult = await _channel.invokeMapMethod<String, dynamic>(
        'computeRoute',
        {
          'startLat': start.latitude,
          'startLon': start.longitude,
          'endLat':   end.latitude,
          'endLon':   end.longitude,
          'avoidPoints': avoidPoints
              .map((p) => {
                    'lat':    p.lat,
                    'lon':    p.lon,
                    'radius': p.radiusMeters,
                  })
              .toList(),
        },
      );

      if (rawResult == null) return NativeRouteResult.empty;
      return NativeRouteResult.fromMap(rawResult);

    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[NativeChannel] PlatformException: $e');
      return NativeRouteResult.withError(e.message ?? 'Erreur native inconnue');
    } catch (e) {
      if (kDebugMode) debugPrint('[NativeChannel] Error: $e');
      return NativeRouteResult.withError(e.toString());
    }
  }

  // ── Calcul avec alternatives (JIT) ───────────────────────────────────────

  /// Calcule l'itinéraire principal + jusqu'à 2 alternatives.
  ///
  /// À appeler uniquement sur action utilisateur (bouton "Voir les alternatives")
  /// car ce calcul désactive les Contraction Hierarchies (plus lent).
  Future<NativeRouteResult> computeRouteWithAlternatives({
    required LatLng start,
    required LatLng end,
    List<AvoidPoint> avoidPoints = const [],
  }) async {
    if (!isSupported) return NativeRouteResult.platformUnsupported;

    try {
      final rawResult = await _channel.invokeMapMethod<String, dynamic>(
        'computeRouteWithAlternatives',
        {
          'startLat': start.latitude,
          'startLon': start.longitude,
          'endLat':   end.latitude,
          'endLon':   end.longitude,
          'avoidPoints': avoidPoints
              .map((p) => {
                    'lat':    p.lat,
                    'lon':    p.lon,
                    'radius': p.radiusMeters,
                  })
              .toList(),
        },
      );

      if (rawResult == null) return NativeRouteResult.empty;
      return NativeRouteResult.fromMap(rawResult);

    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[NativeChannel] Alternatives error: $e');
      return NativeRouteResult.withError(e.message ?? 'Erreur native inconnue');
    } catch (e) {
      if (kDebugMode) debugPrint('[NativeChannel] Error: $e');
      return NativeRouteResult.withError(e.toString());
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// AvoidPoint
// ════════════════════════════════════════════════════════════════════════════

/// Zone à éviter lors du calcul d'itinéraire.
///
/// Correspond à un signalement validé par le réseau P2P
/// (≥3 votes, <30 m de l'événement signalé).
class AvoidPoint {
  const AvoidPoint({
    required this.lat,
    required this.lon,
    this.radiusMeters = 30.0,
  });

  final double lat;
  final double lon;

  /// Rayon de la zone interdite en mètres (défaut : 30 m).
  final double radiusMeters;

  LatLng get latLng => LatLng(lat, lon);

  @override
  String toString() => 'AvoidPoint($lat, $lon, r=${radiusMeters}m)';
}

// ════════════════════════════════════════════════════════════════════════════
// NativeRouteResult
// ════════════════════════════════════════════════════════════════════════════

/// Résultat renvoyé par [OsmAndNativeChannel].
class NativeRouteResult {
  const NativeRouteResult({
    required this.routes,
    required this.source,
    this.errorMessage,
  });

  /// Liste d'itinéraires calculés.
  final List<RouteResult> routes;

  /// Source du calcul :
  ///   'graphhopper_embedded' | 'engine_not_ready' | 'platform_unsupported' | 'error'
  final String source;

  /// Message d'erreur si échec (null si succès).
  final String? errorMessage;

  bool get hasError => errorMessage != null;
  bool get isEmpty  => routes.isEmpty;

  static const platformUnsupported = NativeRouteResult(
    routes: [],
    source: 'platform_unsupported',
  );

  static const empty = NativeRouteResult(
    routes: [],
    source: 'empty',
  );

  static NativeRouteResult withError(String msg) => NativeRouteResult(
        routes: [],
        source: 'error',
        errorMessage: msg,
      );

  /// Parse la réponse brute du MethodChannel.
  ///
  /// Format attendu (de OsmAndBridgePlugin.kt) :
  /// ```
  /// {
  ///   "source": "graphhopper_embedded",
  ///   "routes": [
  ///     {
  ///       "id": "gh_embedded_0",
  ///       "label": "...",
  ///       "distanceMeters": 1234.5,
  ///       "points": [[lat, lon], ...]
  ///     }
  ///   ],
  ///   "error": "..." (optionnel)
  /// }
  /// ```
  factory NativeRouteResult.fromMap(Map<String, dynamic> map) {
    final source = map['source'] as String? ?? 'unknown';
    final error  = map['error']  as String?;

    final rawRoutes = map['routes'] as List<dynamic>? ?? [];
    final routes = <RouteResult>[];

    for (int i = 0; i < rawRoutes.length; i++) {
      final r = rawRoutes[i] as Map<dynamic, dynamic>;

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

      routes.add(RouteResult(
        id:                   r['id']             as String? ?? 'gh_$i',
        label:                r['label']          as String? ?? 'Itinéraire $i',
        totalDistanceMeters: (r['distanceMeters'] as num?)?.toDouble() ?? 0,
        totalRiskScore:       0,
        pois:                 const [],
        points:               points,
      ));
    }

    if (kDebugMode) {
      debugPrint('[NativeChannel] ← source=$source '
          'routes=${routes.length} '
          'pts=${routes.firstOrNull?.points.length ?? 0} '
          '${error != null ? "error=$error" : ""}');
    }

    return NativeRouteResult(
      routes: routes,
      source: source,
      errorMessage: error,
    );
  }
}
