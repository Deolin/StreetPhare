// test/event_model_test.dart
//
// Tests unitaires du modèle d'événement (EventWaypoint, EventModel) :
// logique "juste-à-temps" des étapes, décodage GeoJSON et visibilité.

import 'package:flutter_streetphare/features/events/domain/models/event_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('EventWaypoint — logique juste-à-temps', () {
    final scheduled = DateTime.utc(2026, 7, 10, 12, 0);
    final wp = EventWaypoint(
      label: 'Étape A',
      latitude: 50.0,
      longitude: 4.0,
      scheduledAt: scheduled,
    );

    test('non passée à l\'heure prévue exacte', () {
      expect(wp.isPassed(DateTime.utc(2026, 7, 10, 12, 0), null), isFalse);
    });

    test('passée après +5 minutes', () {
      expect(wp.isPassed(DateTime.utc(2026, 7, 10, 12, 6), null), isTrue);
    });

    test('passée si l\'utilisateur est à moins de 30 m', () {
      const userPos = LatLng(50.0, 4.0); // position exacte
      expect(wp.isPassed(DateTime.utc(2026, 7, 10, 12, 0), userPos), isTrue);
    });

    test('non passée si GPS éloigné et heure non dépassée', () {
      const farAway = LatLng(50.5, 4.5);
      expect(wp.isPassed(DateTime.utc(2026, 7, 10, 12, 0), farAway), isFalse);
    });

    test('formattedTime respecte le format HHhMM', () {
      expect(wp.formattedTime, matches(RegExp(r'^\d{2}h\d{2}$')));
    });

    test('fromJson/toJson round-trip', () {
      final g = EventWaypoint.fromJson(wp.toJson());
      expect(g.label, 'Étape A');
      expect(g.latitude, 50.0);
      expect(g.longitude, 4.0);
      expect(g.scheduledAt, scheduled);
    });
  });

  group('EventModel — décodage GeoJSON', () {
    EventModel buildEvent({required String route}) => EventModel(
          code: 'TEST-1',
          title: 'Test',
          startAt: DateTime.utc(2026, 7, 10, 10, 0),
          visibleAt: DateTime.utc(2026, 7, 10, 10, 0),
          routeGeoJson: route,
          pois: const [],
          destinationLatitude: 50.1,
          destinationLongitude: 4.1,
        );

    test('décode [[lng,lat],...] en List<LatLng>', () {
      final ev = buildEvent(route: '[[4.0,50.0],[4.001,50.001]]');
      final pts = ev.decodeRoute();
      expect(pts.length, 2);
      expect(pts[0].latitude, closeTo(50.0, 1e-9));
      expect(pts[0].longitude, closeTo(4.0, 1e-9));
      expect(pts[1].latitude, closeTo(50.001, 1e-9));
      expect(pts[1].longitude, closeTo(4.001, 1e-9));
    });

    test('route vide → liste vide', () {
      final ev = buildEvent(route: '[]');
      expect(ev.decodeRoute(), isEmpty);
    });

    test('routeGeoJson invalide → liste vide (pas de crash)', () {
      final ev = buildEvent(route: 'pas-du-json');
      expect(ev.decodeRoute(), isEmpty);
    });
  });

  group('EventModel — visibilité & destination', () {
    final visibleAt = DateTime.utc(2026, 7, 10, 12, 0);
    final ev = EventModel(
      code: 'TEST-2',
      title: 'Test',
      startAt: DateTime.utc(2026, 7, 10, 10, 0),
      visibleAt: visibleAt,
      routeGeoJson: '[]',
      pois: const [],
      destinationLatitude: 50.2,
      destinationLongitude: 4.2,
    );

    test('itinéraire invisible avant visibleAt', () {
      expect(ev.isRouteVisible(DateTime.utc(2026, 7, 10, 11, 59)), isFalse);
    });

    test('itinéraire visible à partir de visibleAt', () {
      expect(ev.isRouteVisible(DateTime.utc(2026, 7, 10, 12, 0)), isTrue);
    });

    test('destination expose un LatLng', () {
      expect(ev.destination.latitude, 50.2);
      expect(ev.destination.longitude, 4.2);
    });
  });
}
