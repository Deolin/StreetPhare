// lib/features/geofencing/presentation/geofencing_service.dart
//
// Service de GÉOFENCING continu.
//
// Responsabilités :
//   1. Suivre en continu la position GPS de l'utilisateur via
//      `geolocator` (mode "tâche de fond légère" – on écoute le
//      `getPositionStream` aussi longtemps que l'app est active).
//   2. À chaque nouvelle position, vérifier la distance à chacune
//      des alertes ACTIVES (>3 votes OU validated) provenant de la
//      base locale.
//   3. Si l'utilisateur entre dans un rayon [radiusMeters] (par
//      défaut 50 m) d'une alerte, émettre un `GeofenceEvent` sur
//      un `Stream` public que la couche UI peut écouter pour
//      afficher le BottomSheet de validation.
//
// DÉDUPLICATION : la détection d'entrée en zone est DÉDUPLIQUÉE
// par id d'alerte (un ping par alerte tant qu'elle est visible).
// Le COOLDOWN utilisateur de 5 minutes (anti-spam sur la question
// "est-il toujours là ?") est appliqué en aval par
// `ProximityValidationService`.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/alert_model.dart';
import '../../../database/alert_visibility_policy.dart';
import '../../../database/hive_alert_database.dart';
import '../domain/models/geofence_event.dart';

/// Service singleton de géofencing.
///
/// Implémente [WidgetsBindingObserver] pour détecter les transitions
/// app/background et arrêter/redémarrer proprement le flux GPS.
/// Cela évite le crash `Lost connection to device` quand l'activité
/// Android est détruite alors que le flux Geolocator est encore actif.
class GeofencingService extends WidgetsBindingObserver {
  GeofencingService._();
  static final GeofencingService instance = GeofencingService._();

  /// Rayon par défaut (en mètres) du ping de proximité.
  static const double defaultRadiusMeters = 50.0;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<Alert>>? _alertsSub;
  Timer? _recheckTimer;

  final _eventsController = StreamController<GeofenceEvent>.broadcast();
  Stream<GeofenceEvent> get events => _eventsController.stream;

  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;
  final Set<String> _alreadyTriggeredAlertIds = <String>{};

  double _radiusMeters = defaultRadiusMeters;
  bool _started = false;
  bool _observerRegistered = false;

  /// Démarre le service. Idempotent.
  void start({double radiusMeters = defaultRadiusMeters}) {
    if (_started) return;
    _started = true;
    _radiusMeters = radiusMeters;

    // Enregistre l'écouteur de cycle de vie pour gérer proprement
    // les transitions app/background (évite le crash `Lost connection`).
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    // Réabonne au flux de position (peut être appelé après un resume).
    _subscribeToPositionStream();

    // 2) À chaque mise à jour de la base d'alertes, on doit
    //    pouvoir nettoyer le cache `_alreadyTriggeredAlertIds` si
    //    une alerte disparaît / est invalidée.
    _alertsSub = HiveAlertDatabase.instance.changes.listen((alerts) {
      final liveIds = alerts.map((a) => a.id).toSet();
      _alreadyTriggeredAlertIds.retainAll(liveIds);
    });

    // 3) Timer de re-vérification périodique (toutes les 30 s)
    //    pour s'assurer qu'on n'a pas manqué une mise à jour
    //    (l'utilisateur peut être immobile, mais une nouvelle
    //    alerte peut apparaître autour de lui).
    _recheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        final pos = _lastPosition;
        if (pos != null) _checkProximity(pos);
      },
    );

    if (kDebugMode) {
      debugPrint('[Geofencing] démarré, rayon=$_radiusMeters m');
    }
  }

  /// Souscrit au flux de position GPS (extrait pour être réutilisable
  /// par [didChangeAppLifecycleState] lors du resume).
  void _subscribeToPositionStream() {
    // Annule d'abord tout abonnement existant pour éviter les doublons.
    _posSub?.cancel();
    _posSub = null;

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // mètres
      ),
    ).listen(
      (pos) => _onPositionUpdate(pos),
      onError: (e) {
        if (kDebugMode) {
          debugPrint('[Geofencing] erreur GPS : $e');
        }
      },
    );
  }

  // ── Cycle de vie de l'application ──────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint('[Geofencing] lifecycle → $state');
    }

    switch (state) {
      case AppLifecycleState.paused:
        // L'app passe en arrière-plan : on coupe le flux GPS pour
        // éviter le crash "Lost connection to device" quand l'activité
        // Android est détruite alors que le canal Geolocator est actif.
        _posSub?.cancel();
        _posSub = null;
        _alertsSub?.cancel();
        _alertsSub = null;
        _recheckTimer?.cancel();
        _recheckTimer = null;
        break;

      case AppLifecycleState.resumed:
        // L'app revient au premier plan : on réabonne le flux GPS.
        // On ne réinitialise pas `_started` pour que le service
        // reprenne exactement là où il s'était arrêté.
        if (_started) {
          _subscribeToPositionStream();

          // Réabonne aux changements de la base d'alertes.
          _alertsSub = HiveAlertDatabase.instance.changes.listen((alerts) {
            final liveIds = alerts.map((a) => a.id).toSet();
            _alreadyTriggeredAlertIds.retainAll(liveIds);
          });

          // Relance le timer périodique.
          _recheckTimer = Timer.periodic(
            const Duration(seconds: 30),
            (_) {
              final pos = _lastPosition;
              if (pos != null) _checkProximity(pos);
            },
          );

          if (kDebugMode) {
            debugPrint('[Geofencing] flux GPS réabonné (resume)');
          }
        }
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // L'app est en transition ou se ferme : on coupe tout.
        _posSub?.cancel();
        _posSub = null;
        break;

      case AppLifecycleState.hidden:
        // Flutter web uniquement — ignoré.
        break;
    }
  }

  /// Met à jour le rayon de détection.
  void setRadiusMeters(double meters) {
    _radiusMeters = meters;
  }

  /// Force une vérification ponctuelle (utile pour les tests).
  void checkNow() {
    final pos = _lastPosition;
    if (pos != null) _checkProximity(pos);
  }

  /// Injecte une position de manière programmatique (utile pour
  /// les tests unitaires ou le debug sans GPS).
  void injectPosition(Position pos) => _onPositionUpdate(pos);

  /// Réinitialise la déduplication (utile pour les tests ou si
  /// l'utilisateur force un nouveau cycle de validation).
  void resetDeduplication() => _alreadyTriggeredAlertIds.clear();

  void _onPositionUpdate(Position pos) {
    _lastPosition = pos;
    // ═══ Dispatch sur le thread principal via addPostFrameCallback ═══
    // Le callback natif de Geolocator (getPositionStream) peut arriver
    // depuis un thread secondaire (Kotlin/Native). Pour éviter les
    // conflits de threads et les crashs natifs, on force l'exécution
    // sur le prochain frame du thread UI.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkProximity(pos);
    });
  }

  void _checkProximity(Position pos) {
    // ═══ Garde-fou : Hive non initialisée ─══════════════════════════
    // Si l'init du NetworkCoordinator a échoué en amont, la base
    // Hive n'a jamais été ouverte. On évite d'appeler getAllValid()
    // qui lèverait un StateError en boucle (saturation des logs).
    if (!HiveAlertDatabase.instance.isInitialized) {
      return;
    }

    final alerts = HiveAlertDatabase.instance.getAllValid();
    final visible = AlertVisibilityPolicy.filterVisible(alerts);
    final user = LatLng(pos.latitude, pos.longitude);

    for (final alert in visible) {
      if (_alreadyTriggeredAlertIds.contains(alert.id)) continue;
      final dist = _distanceMeters(user, alert.position);
      if (dist <= _radiusMeters) {
        _alreadyTriggeredAlertIds.add(alert.id);
        _eventsController.add(
          GeofenceEvent(
            alert: alert,
            userPosition: user,
            distanceMeters: dist,
          ),
        );
        if (kDebugMode) {
          debugPrint(
              '[Geofencing] ping ! alerte=${alert.id} dist=${dist.toStringAsFixed(1)} m');
        }
      }
    }
  }

  /// Distance grand-cercle (Haversine) entre deux LatLng (en m).
  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;

  /// Renvoie la distance grand-cercle (en m) entre deux positions
  /// (utilitaire public pour d'autres services / tests).
  static double distanceBetween(LatLng a, LatLng b) => _distanceMeters(a, b);

  void stop() {
    _posSub?.cancel();
    _posSub = null;
    _alertsSub?.cancel();
    _alertsSub = null;
    _recheckTimer?.cancel();
    _recheckTimer = null;
    _alreadyTriggeredAlertIds.clear();
    _started = false;
  }

  /// Libère proprement les ressources (à appeler au shutdown de l'app).
  Future<void> dispose() async {
    stop();
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    await _eventsController.close();
  }
}
