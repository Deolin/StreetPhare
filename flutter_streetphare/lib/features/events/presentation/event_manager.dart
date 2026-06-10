// lib/features/events/presentation/event_manager.dart
//
// Gestionnaire MULTI-ÉVÉNEMENTS "StreetPhare".
//
// Responsabilités :
//   1. Stocker jusqu'à 3 événements simultanés.
//   2. Exposer l'état via `ValueListenable<List<EventModel>>`.
//   3. Charger un événement par code d'invitation (fixtures locales).
//   4. Charger un événement depuis un JSON QR Code scanné.
//   5. Gérer la sélection de l'événement "actif" (index).
//   6. Ticker 1 s pour mettre à jour les countdowns et la logique
//      d'étapes éphémères (juste-à-temps).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../domain/models/event_model.dart';

/// Manager singleton des événements — supporte jusqu'à [maxEvents] en parallèle.
class EventManager extends ValueNotifier<List<EventModel>> {
  EventManager._() : super(const []);
  static final EventManager instance = EventManager._();

  /// Nombre maximal d'événements simultanés.
  static const int maxEvents = 3;

  Timer? _ticker;
  int _activeIndex = 0;

  // --------------------------------------------------------------------------
  // Accès rapide
  // --------------------------------------------------------------------------

  /// Index de l'événement "actif" (celui mis en avant dans l'UI).
  int get activeIndex =>
      value.isEmpty ? 0 : _activeIndex.clamp(0, value.length - 1);

  /// Événement actif courant, ou `null` si aucun.
  EventModel? get activeEvent =>
      value.isEmpty ? null : value[activeIndex];

  /// Nombre d'événements chargés.
  int get count => value.length;

  // --------------------------------------------------------------------------
  // Cycle de vie
  // --------------------------------------------------------------------------

  /// Démarre le ticker qui force un rebuild toutes les secondes pour les
  /// countdowns et la logique d'étapes éphémères.
  void start() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (value.isNotEmpty) notifyListeners();
    });
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  // --------------------------------------------------------------------------
  // Chargement / ajout
  // --------------------------------------------------------------------------

  /// Charge un événement à partir d'un code d'invitation.
  ///
  /// Retourne `true` si l'événement a été trouvé et ajouté (ou était déjà
  /// présent), `false` si le code est inconnu ou la limite atteinte.
  Future<bool> loadByCode(String code) async {
    final upper = code.trim().toUpperCase();

    // Déjà chargé → succès silencieux.
    if (value.any((e) => e.code == upper)) return true;

    // Limite de 3 événements.
    if (value.length >= maxEvents) return false;

    final event = _decodeEvent(upper);
    if (event == null) {
      if (kDebugMode) debugPrint('[EventManager] code inconnu : $upper');
      return false;
    }

    value = [...value, event];
    if (kDebugMode) {
      debugPrint(
        '[EventManager] chargé "${event.title}" '
        '(route visible=${event.isRouteVisible()})',
      );
    }
    return true;
  }

  /// Ajoute un événement décodé depuis un QR Code (JSON brut ou Map).
  ///
  /// [source] peut être :
  ///   - un `Map<String, dynamic>` déjà parsé,
  ///   - ou une `String` JSON brute.
  ///
  /// Retourne `true` si ajouté avec succès.
  Future<bool> addFromSource(Object source) async {
    try {
      final Map<String, dynamic> json;
      if (source is String) {
        json = jsonDecode(source) as Map<String, dynamic>;
      } else if (source is Map<String, dynamic>) {
        json = source;
      } else {
        return false;
      }

      final event = EventModel.fromJson(json);

      // Déjà présent → succès silencieux.
      if (value.any((e) => e.code == event.code)) return true;

      // Limite de 3 événements.
      if (value.length >= maxEvents) return false;

      value = [...value, event];
      if (kDebugMode) {
        debugPrint('[EventManager] QR chargé : "${event.title}"');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[EventManager] JSON invalide : $e');
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Suppression / navigation
  // --------------------------------------------------------------------------

  /// Supprime l'événement dont le code est [code].
  void removeByCode(String code) {
    final newList =
        value.where((e) => e.code != code).toList(growable: false);
    value = newList;
    if (_activeIndex >= value.length) {
      _activeIndex = value.isEmpty ? 0 : value.length - 1;
    }
  }

  /// Change l'index de l'événement actif (pour les tabs de l'UI).
  void setActiveIndex(int index) {
    if (index >= 0 && index < value.length && index != _activeIndex) {
      _activeIndex = index;
      notifyListeners();
    }
  }

  /// Efface tous les événements.
  void clear() {
    _activeIndex = 0;
    value = const [];
  }

  // --------------------------------------------------------------------------
  // Fixtures de démonstration
  // --------------------------------------------------------------------------

  /// Résout un code en `EventModel` de démo. Retourne `null` si inconnu.
  EventModel? _decodeEvent(String code) {
    final now = DateTime.now().toUtc();
    switch (code) {
      // ── MANIF-123 : visible dans 5 min, avec étapes planifiées ────────────
      case 'MANIF-123':
        return EventModel(
          code: code,
          title: 'Marche pour le climat',
          startAt: now.add(const Duration(hours: 2)),
          visibleAt: now.add(const Duration(minutes: 5)),
          routeGeoJson:
              '[[2.3522,48.8566],[2.3535,48.8580],[2.3550,48.8600],'
              '[2.3565,48.8625],[2.3580,48.8650],[2.3610,48.8680],'
              '[2.3620,48.8700],[2.3640,48.8710],[2.3660,48.8720]]',
          waypoints: [
            EventWaypoint(
              label: 'Départ — Nation',
              latitude: 48.8566,
              longitude: 2.3522,
              scheduledAt: now.add(const Duration(minutes: 5)),
            ),
            EventWaypoint(
              label: 'Point eau — Châtelet',
              latitude: 48.8600,
              longitude: 2.3550,
              scheduledAt: now.add(const Duration(minutes: 30)),
            ),
            EventWaypoint(
              label: 'Arrivée — Trocadéro',
              latitude: 48.8720,
              longitude: 2.3660,
              scheduledAt: now.add(const Duration(hours: 2)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Point de rassemblement',
              latitude: 48.8566,
              longitude: 2.3522,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Point d\'eau',
              latitude: 48.8600,
              longitude: 2.3550,
              icon: 'water',
            ),
            EventPoi(
              label: 'Sortie de secours',
              latitude: 48.8720,
              longitude: 2.3660,
              icon: 'exit',
            ),
          ],
          destinationLatitude: 48.8720,
          destinationLongitude: 2.3660,
        );

      // ── MANIF-456 : déjà visible, 1re étape déjà passée ──────────────────
      case 'MANIF-456':
        return EventModel(
          code: code,
          title: 'Rassemblement République',
          startAt: now.subtract(const Duration(minutes: 10)),
          visibleAt: now.subtract(const Duration(hours: 1)),
          routeGeoJson:
              '[[2.3630,48.8670],[2.3645,48.8680],[2.3660,48.8690],'
              '[2.3675,48.8705],[2.3685,48.8715],[2.3700,48.8730]]',
          waypoints: [
            EventWaypoint(
              label: 'Départ — République',
              latitude: 48.8670,
              longitude: 2.3630,
              // Déjà passée depuis 15 min → étape 0 sera sautée auto.
              scheduledAt: now.subtract(const Duration(minutes: 15)),
            ),
            EventWaypoint(
              label: 'Étape — Bastille',
              latitude: 48.8690,
              longitude: 2.3660,
              scheduledAt: now.add(const Duration(minutes: 20)),
            ),
            EventWaypoint(
              label: 'Arrivée — Vincennes',
              latitude: 48.8730,
              longitude: 2.3700,
              scheduledAt: now.add(const Duration(hours: 1)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Place de la République',
              latitude: 48.8670,
              longitude: 2.3630,
              icon: 'flag',
            ),
          ],
          destinationLatitude: 48.8730,
          destinationLongitude: 2.3700,
        );

      // ── MANIF-789 : future, trajet masqué ─────────────────────────────────
      case 'MANIF-789':
        return EventModel(
          code: code,
          title: 'Grande marche de demain',
          startAt: now.add(const Duration(hours: 24)),
          visibleAt: now.add(const Duration(hours: 23, minutes: 30)),
          routeGeoJson:
              '[[2.2945,48.8584],[2.2980,48.8600],[2.3050,48.8610],'
              '[2.3100,48.8620],[2.3150,48.8635],[2.3200,48.8650]]',
          waypoints: [
            EventWaypoint(
              label: 'Départ — Tour Eiffel',
              latitude: 48.8584,
              longitude: 2.2945,
              scheduledAt: now.add(const Duration(hours: 24)),
            ),
            EventWaypoint(
              label: 'Arrivée — Châtelet',
              latitude: 48.8650,
              longitude: 2.3200,
              scheduledAt: now.add(const Duration(hours: 26)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Départ',
              latitude: 48.8584,
              longitude: 2.2945,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Arrivée',
              latitude: 48.8650,
              longitude: 2.3200,
              icon: 'flag',
            ),
          ],
          destinationLatitude: 48.8650,
          destinationLongitude: 2.3200,
        );

      default:
        return null;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

// ============================================================================
// Utilitaires
// ============================================================================

/// Formate une `Duration` en "HH:MM:SS" pour les countdowns.
String formatCountdown(Duration d) {
  if (d.isNegative || d == Duration.zero) return '00:00:00';
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Calcule le centroïde d'un ensemble de `LatLng`.
LatLng centroidOfPoints(List<LatLng> pts) {
  if (pts.isEmpty) return const LatLng(48.8566, 2.3522);
  double lat = 0, lng = 0;
  for (final p in pts) {
    lat += p.latitude;
    lng += p.longitude;
  }
  return LatLng(lat / pts.length, lng / pts.length);
}
