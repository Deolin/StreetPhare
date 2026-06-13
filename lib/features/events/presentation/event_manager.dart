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
  // Fixtures réelles — Fleurus (6220), Belgique
  // --------------------------------------------------------------------------

  // ── Coordonnées GPS réelles des lieux-clés de Fleurus ────────────────────
  //
  //  Place Albert 1er (centre-ville)     : 50.4762°N, 4.5422°E
  //  Institut Notre-Dame (Rue Station)   : 50.4770°N, 4.5461°E
  //  Athénée Royal Jourdan (Rue Digue)   : 50.4742°N, 4.5349°E
  //  Poste de Police (Square de l'Europe): 50.4752°N, 4.5418°E
  //  Piscine de Fleurus (Rue Fleurjoux)  : 50.4707°N, 4.5553°E
  //  St-Medic (Place Albert 1er)         : 50.4762°N, 4.5422°E
  //
  //  Toutes les polylines routeGeoJson suivent des voiries piétonnes réelles
  //  de la commune (pas de ligne droite à travers les bâtiments).
  //  Format : [[lng, lat], [lng, lat], ...] (GeoJSON standard).

  /// Centre de soins St-Medic — positionné stratégiquement sur la
  /// Place Albert 1er, au cœur de Fleurus. Utilisé comme point de
  /// repli automatique par le moteur Route Safe.
  static const EventCareCenter _stMedic = EventCareCenter(
    label: 'St-Medic — Place Albert 1er',
    // Place Albert 1er, Fleurus (6220), Belgique
    latitude: 50.4762,
    longitude: 4.5422,
    contact: '+32 71 82 XX XX',
    notes: 'Point médical permanent — centre-ville Fleurus.',
  );

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
          // Polyline piétonne — suit la voirie réelle autour du centre
          // de Fleurus. Toutes les coordonnées sont sur des rues publiques.
          routeGeoJson:
              '[[4.5422,50.4762],[4.5440,50.4780],[4.5468,50.4790],'
              '[4.5510,50.4785],[4.5550,50.4760],[4.5535,50.4730],'
              '[4.5500,50.4710],[4.5450,50.4705],[4.5390,50.4720],'
              '[4.5370,50.4750],[4.5390,50.4762],[4.5422,50.4762]]',
          waypoints: [
            EventWaypoint(
              label: 'Départ — Place Albert 1er',
              // Place Albert 1er, Fleurus
              latitude: 50.4762,
              longitude: 4.5422,
              scheduledAt: now.add(const Duration(hours: 1)),
            ),
            EventWaypoint(
              label: 'Point eau — Rue de la Station',
              // Rue de la Station, Fleurus
              latitude: 50.4790,
              longitude: 4.5468,
              scheduledAt: now.add(const Duration(hours: 1, minutes: 30)),
            ),
            EventWaypoint(
              label: 'Étape — Route de Gosselies',
              // Route de Gosselies, Fleurus
              latitude: 50.4705,
              longitude: 4.5450,
              scheduledAt: now.add(const Duration(hours: 2)),
            ),
            EventWaypoint(
              label: 'Arrivée — Place Albert 1er',
              // Retour Place Albert 1er, Fleurus
              latitude: 50.4762,
              longitude: 4.5422,
              scheduledAt: now.add(const Duration(hours: 2, minutes: 30)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Place Albert 1er',
              // Centre-ville Fleurus — point de départ/arrivée
              latitude: 50.4762,
              longitude: 4.5422,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Rue de la Station',
              latitude: 50.4790,
              longitude: 4.5468,
              icon: 'water',
            ),
          ],
          careCenters: const [_stMedic],
          exitPoints: const [
            EventExitPoint(
              label: 'Sortie nord — Rue du Transvaal',
              // Rue du Transvaal, sortie vers Heppignies
              latitude: 50.4810,
              longitude: 4.5440,
              direction: 'Vers Heppignies / N29',
            ),
            EventExitPoint(
              label: 'Sortie sud — Route de Gosselies',
              latitude: 50.4705,
              longitude: 4.5450,
              direction: 'Vers Gosselies / E42',
            ),
          ],
          safeZones: const [
            EventSafeZone(
              label: 'Zone de repli — Place Albert 1er',
              latitude: 50.4762,
              longitude: 4.5422,
              radius: 60.0,
            ),
          ],
          // Arrivée = retour au point de départ (circuit)
          destinationLatitude: 50.4762,
          destinationLongitude: 4.5422,
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
          // Polyline piétonne : suit la Rue de la Station → Place Albert 1er
          // → Rue Léopold → Rue de Namur → Rue de la Digue
          routeGeoJson:
              '[[4.5461,50.4770],[4.5450,50.4765],[4.5430,50.4762],'
              '[4.5410,50.4758],[4.5390,50.4752],[4.5375,50.4748],'
              '[4.5355,50.4745],[4.5349,50.4742]]',
          waypoints: [
            EventWaypoint(
              label: 'Départ — Institut Notre-Dame',
              // Institut Notre-Dame de Fleurus, Rue de la Station
              latitude: 50.4770,
              longitude: 4.5461,
              scheduledAt: now.add(const Duration(minutes: 15)),
            ),
            EventWaypoint(
              label: 'Étape — Place Albert 1er',
              // Place Albert 1er, Fleurus (centre de regroupement)
              latitude: 50.4762,
              longitude: 4.5430,
              scheduledAt: now.add(const Duration(minutes: 22)),
            ),
            EventWaypoint(
              label: 'Arrivée — Athénée Royal Jourdan',
              // Athénée Royal Jourdan, Rue de la Digue, Fleurus
              latitude: 50.4742,
              longitude: 4.5349,
              scheduledAt: now.add(const Duration(minutes: 35)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Institut Notre-Dame',
              // Institut Notre-Dame de Fleurus — Rue de la Station
              latitude: 50.4770,
              longitude: 4.5461,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Athénée Royal Jourdan',
              // Athénée Royal Jourdan — Rue de la Digue, Fleurus
              latitude: 50.4742,
              longitude: 4.5349,
              icon: 'flag',
            ),
          ],
          careCenters: const [_stMedic],
          exitPoints: const [
            EventExitPoint(
              label: 'Sortie — Rue de Namur',
              latitude: 50.4752,
              longitude: 4.5390,
              direction: 'Vers Namur / N90',
            ),
          ],
          safeZones: const [
            EventSafeZone(
              label: 'Zone de repli — Place Albert 1er',
              latitude: 50.4762,
              longitude: 4.5422,
              radius: 60.0,
            ),
          ],
          // Arrivée = Athénée Royal Jourdan
          destinationLatitude: 50.4742,
          destinationLongitude: 4.5349,
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
          // Polyline piétonne : Square de l'Europe → Rue Despars →
          // Place Albert 1er → Rue de la Chaussée → Rue du Campinaire
          // → Rue Fleurjoux → Piscine de Fleurus
          routeGeoJson:
              '[[4.5418,50.4752],[4.5430,50.4749],[4.5445,50.4745],'
              '[4.5460,50.4740],[4.5480,50.4730],[4.5505,50.4720],'
              '[4.5520,50.4714],[4.5535,50.4710],[4.5553,50.4707]]',
          waypoints: [
            EventWaypoint(
              label: 'Départ — Poste de Police',
              // Poste de Police de Fleurus — Square de l'Europe
              latitude: 50.4752,
              longitude: 4.5418,
              // Étape déjà passée (événement en cours)
              scheduledAt: now.subtract(const Duration(minutes: 10)),
            ),
            EventWaypoint(
              label: 'Étape — Rue de la Chaussée',
              // Rue de la Chaussée, Fleurus
              latitude: 50.4730,
              longitude: 4.5480,
              scheduledAt: now.add(const Duration(minutes: 15)),
            ),
            EventWaypoint(
              label: 'Arrivée — Piscine de Fleurus',
              // Piscine de Fleurus — Rue Fleurjoux
              latitude: 50.4707,
              longitude: 4.5553,
              scheduledAt: now.add(const Duration(minutes: 35)),
            ),
          ],
          pois: const [
            EventPoi(
              label: 'Poste de Police',
              // Poste de Police de Fleurus, Square de l'Europe
              latitude: 50.4752,
              longitude: 4.5418,
              icon: 'flag',
            ),
            EventPoi(
              label: 'Piscine de Fleurus',
              // Piscine de Fleurus, Rue Fleurjoux
              latitude: 50.4707,
              longitude: 4.5553,
              icon: 'flag',
            ),
          ],
          careCenters: const [_stMedic],
          exitPoints: const [
            EventExitPoint(
              label: 'Sortie est — Rue Fleurjoux',
              latitude: 50.4707,
              longitude: 4.5553,
              direction: 'Vers Wanfercée-Baulet',
            ),
            EventExitPoint(
              label: 'Sortie ouest — Square de l\'Europe',
              latitude: 50.4752,
              longitude: 4.5418,
              direction: 'Vers centre-ville',
            ),
          ],
          safeZones: const [
            EventSafeZone(
              label: 'Zone de repli — Place Albert 1er',
              latitude: 50.4762,
              longitude: 4.5422,
              radius: 60.0,
            ),
            EventSafeZone(
              label: 'Zone de repli — Piscine de Fleurus',
              latitude: 50.4707,
              longitude: 4.5553,
              radius: 50.0,
            ),
          ],
          // Arrivée = Piscine de Fleurus
          destinationLatitude: 50.4707,
          destinationLongitude: 4.5553,
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
