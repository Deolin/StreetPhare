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

import '../../../debug/client_debug_logger.dart';
import '../domain/models/event_model.dart';
import '../fixtures_fleurus.dart';

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
  EventModel? get activeEvent => value.isEmpty ? null : value[activeIndex];

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
      if (kDebugMode) {
        debugPrint('[EventManager] JSON invalide : $e');
        ClientDebugLogger.instance.log('QR Code invalide ou incomplet: $e');
      }
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Suppression / navigation
  // --------------------------------------------------------------------------

  /// Supprime l'événement dont le code est [code].
  void removeByCode(String code) {
    final newList = value.where((e) => e.code != code).toList(growable: false);
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
  // Fixtures réelles — Fleurus (6220), Belgique
  // --------------------------------------------------------------------------

  // Coordonnées GPS extraites dans lib/features/events/fixtures_fleurus.dart.
  // Réutilise les constantes FleurusLocations, stMedicCareCenter et
  // FleurusPolylines pour le mapping des événements de démonstration.

  /// Résout un code en `EventModel` de démo. Retourne `null` si inconnu.
  EventModel? _decodeEvent(String code) {
    final now = DateTime.now().toUtc();
    switch (code) {
      // ── FLEURUS-TOUR : Le tour de Fleurus ─────────────────────────────────
      // Marche circulaire ~4 km suivant la voirie autour du centre de Fleurus.
      // Trajet : Place Albert 1er → Rue du Transvaal → Rue de la Station →
      //          Route de Wanfercée → Rue du Sart → Route de Gosselies →
      //          Rue de Namur → Place Albert 1er
      case 'FLEURUS-TOUR':
        return EventModel(
          code: code,
          title: 'Le tour de Fleurus',
          startAt: now.add(const Duration(hours: 1)),
          // Trajet révélé immédiatement (événement de démonstration actif)
          visibleAt: now.subtract(const Duration(minutes: 5)),
          routeGeoJson: FleurusPolylines.tourFleurus,
          waypoints: [
            EventWaypoint(
              label: 'Départ — Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              scheduledAt: now.add(const Duration(hours: 1)),
            ),
            EventWaypoint(
              label: 'Point eau — Rue de la Station',
              latitude: FleurusLocations.rueStationLat,
              longitude: FleurusLocations.rueStationLng,
              scheduledAt: now.add(const Duration(hours: 1, minutes: 30)),
            ),
            EventWaypoint(
              label: 'Étape — Route de Gosselies',
              latitude: FleurusLocations.routeGosseliesLat,
              longitude: FleurusLocations.routeGosseliesLng,
              scheduledAt: now.add(const Duration(hours: 2)),
            ),
            EventWaypoint(
              label: 'Arrivée — Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              scheduledAt: now.add(const Duration(hours: 2, minutes: 30)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Rue de la Station',
              latitude: FleurusLocations.rueStationLat,
              longitude: FleurusLocations.rueStationLng,
              icon: 'water',
            ),
          ],
          careCenters: const [stMedicCareCenter],
          exitPoints: const [
            EventExitPoint(
              label: 'Sortie nord — Rue du Transvaal',
              latitude: FleurusLocations.sortieNordLat,
              longitude: FleurusLocations.sortieNordLng,
              direction: 'Vers Heppignies / N29',
            ),
            EventExitPoint(
              label: 'Sortie sud — Route de Gosselies',
              latitude: FleurusLocations.routeGosseliesLat,
              longitude: FleurusLocations.routeGosseliesLng,
              direction: 'Vers Gosselies / E42',
            ),
          ],
          safeZones: const [
            EventSafeZone(
              label: 'Zone de repli — Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              radius: FleurusLocations.zoneRepliRadius,
            ),
          ],
          destinationLatitude: FleurusLocations.placeAlbertLat,
          destinationLongitude: FleurusLocations.placeAlbertLng,
        );

      // ── FLEURUS-ECOLES : La traversée des écoles ──────────────────────────
      // Itinéraire piéton de l'Institut Notre-Dame (Rue de la Station)
      // jusqu'à l'Athénée Royal Jourdan (Rue de la Digue).
      // Parcours ~1,2 km via la Place Albert 1er et Rue de Namur.
      case 'FLEURUS-ECOLES':
        return EventModel(
          code: code,
          title: 'La traversée des écoles',
          startAt: now.add(const Duration(minutes: 15)),
          // Trajet révélé dans 10 minutes (logique juste-à-temps)
          visibleAt: now.add(const Duration(minutes: 10)),
          routeGeoJson: FleurusPolylines.traverseeEcoles,
          waypoints: [
            EventWaypoint(
              label: 'Départ — Institut Notre-Dame',
              latitude: FleurusLocations.institutNotreDameLat,
              longitude: FleurusLocations.institutNotreDameLng,
              scheduledAt: now.add(const Duration(minutes: 15)),
            ),
            EventWaypoint(
              label: 'Étape — Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              scheduledAt: now.add(const Duration(minutes: 22)),
            ),
            EventWaypoint(
              label: 'Arrivée — Athénée Royal Jourdan',
              latitude: FleurusLocations.atheneeRoyalLat,
              longitude: FleurusLocations.atheneeRoyalLng,
              scheduledAt: now.add(const Duration(minutes: 35)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Institut Notre-Dame',
              latitude: FleurusLocations.institutNotreDameLat,
              longitude: FleurusLocations.institutNotreDameLng,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Athénée Royal Jourdan',
              latitude: FleurusLocations.atheneeRoyalLat,
              longitude: FleurusLocations.atheneeRoyalLng,
              icon: 'flag',
            ),
          ],
          careCenters: const [stMedicCareCenter],
          exitPoints: const [
            EventExitPoint(
              label: 'Sortie — Rue de Namur',
              latitude: FleurusLocations.sortieRueNamurLat,
              longitude: FleurusLocations.sortieRueNamurLng,
              direction: 'Vers Namur / N90',
            ),
          ],
          safeZones: const [
            EventSafeZone(
              label: 'Zone de repli — Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              radius: FleurusLocations.zoneRepliRadius,
            ),
          ],
          destinationLatitude: FleurusLocations.atheneeRoyalLat,
          destinationLongitude: FleurusLocations.atheneeRoyalLng,
        );

      // ── FLEURUS-CORTEGE : Le cortège de la police monté-démonté ───────────
      // Trajet du Poste de Police (Square de l'Europe) à la Piscine
      // de Fleurus (Rue Fleurjoux). ~2,1 km via la Rue de la Chaussée.
      case 'FLEURUS-CORTEGE':
        return EventModel(
          code: code,
          title: 'Le cortège de la police monté-démonté',
          // Événement en cours depuis 10 minutes
          startAt: now.subtract(const Duration(minutes: 10)),
          visibleAt: now.subtract(const Duration(minutes: 10)),
          routeGeoJson: FleurusPolylines.cortegePolice,
          waypoints: [
            EventWaypoint(
              label: 'Départ — Poste de Police',
              latitude: FleurusLocations.postePoliceLat,
              longitude: FleurusLocations.postePoliceLng,
              scheduledAt: now.subtract(const Duration(minutes: 10)),
            ),
            EventWaypoint(
              label: 'Étape — Rue de la Chaussée',
              latitude: FleurusLocations.rueChausseeLat,
              longitude: FleurusLocations.rueChausseeLng,
              scheduledAt: now.add(const Duration(minutes: 15)),
            ),
            EventWaypoint(
              label: 'Arrivée — Piscine de Fleurus',
              latitude: FleurusLocations.piscineLat,
              longitude: FleurusLocations.piscineLng,
              scheduledAt: now.add(const Duration(minutes: 35)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Poste de Police',
              latitude: FleurusLocations.postePoliceLat,
              longitude: FleurusLocations.postePoliceLng,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Piscine de Fleurus',
              latitude: FleurusLocations.piscineLat,
              longitude: FleurusLocations.piscineLng,
              icon: 'flag',
            ),
          ],
          careCenters: const [stMedicCareCenter],
          exitPoints: const [
            EventExitPoint(
              label: 'Sortie est — Rue Fleurjoux',
              latitude: FleurusLocations.piscineLat,
              longitude: FleurusLocations.piscineLng,
              direction: 'Vers Wanfercée-Baulet',
            ),
            EventExitPoint(
              label: 'Sortie ouest — Square de l\'Europe',
              latitude: FleurusLocations.postePoliceLat,
              longitude: FleurusLocations.postePoliceLng,
              direction: 'Vers centre-ville',
            ),
          ],
          safeZones: const [
            EventSafeZone(
              label: 'Zone de repli — Place Albert 1er',
              latitude: FleurusLocations.placeAlbertLat,
              longitude: FleurusLocations.placeAlbertLng,
              radius: FleurusLocations.zoneRepliRadius,
            ),
            EventSafeZone(
              label: 'Zone de repli — Piscine de Fleurus',
              latitude: FleurusLocations.piscineLat,
              longitude: FleurusLocations.piscineLng,
              radius: FleurusLocations.zoneRepliPiscineRadius,
            ),
          ],
          destinationLatitude: FleurusLocations.piscineLat,
          destinationLongitude: FleurusLocations.piscineLng,
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
