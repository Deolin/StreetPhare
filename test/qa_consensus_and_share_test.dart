// test/qa_consensus_and_share_test.dart
//
// Tests QA / Full-Stack :
//   1. Consensus & Demandes de Validation Dynamiques (staleNoVote5Min & contradictoryReport)
//   2. Partage d'Application, QR Code, Deep Linking & Redirection Play Store

import 'dart:convert';

import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/features/events/domain/models/event_model.dart';
import 'package:flutter_streetphare/features/events/presentation/event_manager.dart';
import 'package:flutter_streetphare/features/geofencing/domain/models/geofence_event.dart';
import 'package:flutter_streetphare/features/geofencing/presentation/geofencing_service.dart';
import 'package:flutter_streetphare/services/app_share_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Consensus & Demandes de Validation Dynamiques', () {
    test('GeofenceEvent expose staleNoVote5Min et contradictoryReport', () {
      final now = DateTime.now().toUtc();
      final alert = Alert(
        id: 'alert_stale_1',
        ephemeralUserId: 'user_1',
        signature: 'sig',
        type: AlertType.policiers,
        latitude: 50.4762,
        longitude: 4.5422,
        createdAt: now.subtract(const Duration(minutes: 6)),
        lastModifiedAt: now.subtract(const Duration(minutes: 6)),
        status: AlertStatus.active,
        confirmations: const {'u1', 'u2', 'u3'},
      );

      final staleEvent = GeofenceEvent(
        alert: alert,
        userPosition: const LatLng(50.4762, 4.5422),
        distanceMeters: 12.0,
        reason: ValidationTriggerReason.staleNoVote5Min,
      );
      expect(staleEvent.reason, ValidationTriggerReason.staleNoVote5Min);

      final conflictEvent = GeofenceEvent(
        alert: alert,
        userPosition: const LatLng(50.4762, 4.5422),
        distanceMeters: 8.0,
        reason: ValidationTriggerReason.contradictoryReport,
        conflictingAlertType: AlertType.autopompes,
      );
      expect(conflictEvent.reason, ValidationTriggerReason.contradictoryReport);
      expect(conflictEvent.conflictingAlertType, AlertType.autopompes);
    });

    test('Seuil staleNoVoteThreshold est fixé à 5 minutes', () {
      expect(
        GeofencingService.staleNoVoteThreshold,
        const Duration(minutes: 5),
      );
    });
  });

  group('2. Audit & Vérification du Partage (Deep Link, QR Code & Play Store)', () {
    late EventModel sampleEvent;

    setUp(() {
      EventManager.instance.value = const [];
      final now = DateTime.now().toUtc();
      sampleEvent = EventModel(
        code: 'SHARE-QA-01',
        title: 'Cortège Test QA',
        startAt: now.add(const Duration(hours: 1)),
        visibleAt: now,
        routeGeoJson: '[[50.4762,4.5422],[50.4780,4.5450]]',
        pois: const [],
        destinationLatitude: 50.4780,
        destinationLongitude: 4.5450,
      );
    });

    test('buildEventShareUrl et buildEventDeepLink transmettent événement et session', () {
      final shareUrl = AppShareService.instance.buildEventShareUrl(
        sampleEvent,
        sessionId: 'sess_42',
        baseUrlOverride: 'https://streetphare.ddns.net',
      );
      expect(shareUrl, startsWith('https://streetphare.ddns.net/invite?'));
      expect(shareUrl, contains('code=SHARE-QA-01'));
      expect(shareUrl, contains('session=sess_42'));
      expect(shareUrl, contains('data='));

      final parsedHttps =
          AppShareService.instance.parseSharedLinkOrPayload(shareUrl);
      expect(parsedHttps, isNotNull);
      expect(parsedHttps!.code, 'SHARE-QA-01');
      expect(parsedHttps.session, 'sess_42');
      expect(parsedHttps.eventData!['title'], 'Cortège Test QA');

      final deepLink = AppShareService.instance.buildEventDeepLink(
        sampleEvent,
        sessionId: 'sess_42',
      );
      expect(deepLink, startsWith('streetphare://invite?'));
      final parsedDl =
          AppShareService.instance.parseSharedLinkOrPayload(deepLink);
      expect(parsedDl, isNotNull);
      expect(parsedDl!.code, 'SHARE-QA-01');
      expect(parsedDl.session, 'sess_42');
      expect(parsedDl.eventData!['destLat'], 50.4780);
    });

    test('parseSharedLinkOrPayload décode aussi un QR Code JSON brut', () {
      final rawJson = jsonEncode(sampleEvent.toJson());
      final parsed = AppShareService.instance.parseSharedLinkOrPayload(rawJson);
      expect(parsed, isNotNull);
      expect(parsed!.code, 'SHARE-QA-01');
      expect(parsed.eventData!['title'], 'Cortège Test QA');
    });

    test('handleIncomingDeepLink charge automatiquement l\'événement dans EventManager', () async {
      final deepLink = AppShareService.instance.buildEventDeepLink(
        sampleEvent,
        sessionId: 'sess_99',
      );
      final ok = await AppShareService.instance.handleIncomingDeepLink(deepLink);
      expect(ok, isTrue);
      expect(EventManager.instance.count, 1);
      expect(EventManager.instance.activeEvent?.code, 'SHARE-QA-01');
    });

    test('buildPlayStoreFallbackUrl génère un lien Play Store avec referrer complet', () {
      final fallbackUrl = AppShareService.instance.buildPlayStoreFallbackUrl(
        eventCode: 'SHARE-QA-01',
        sessionId: 'sess_42',
      );
      expect(
        fallbackUrl,
        startsWith(
          'https://play.google.com/store/apps/details?id=com.example.flutter_streetphare&referrer=',
        ),
      );
      expect(fallbackUrl, contains('code%3DSHARE-QA-01'));
      expect(fallbackUrl, contains('session%3Dsess_42'));
    });
  });
}
