// lib/network/collective_panic_service.dart
//
// Service d'Intelligence Collective — Alerte Panic Réseau.
//
// Logique :
//   Si 5 appareils DISTINCTS connectés au maillage P2P local ont
//   activé leur bouton "Panic" dans une même fenêtre de 2 minutes,
//   le service :
//     1. Calcule le centre géographique de ces 5 signaux.
//     2. Crée AUTOMATIQUEMENT une alerte de type `panicCollectif`
//        au centre calculé.
//     3. Notifie l'UI via le stream `collectivePanicEvents`.
//
// Chaque message de type "panic" diffusé sur le maillage contient :
//   { "kind": "panic", "peerId": "<id>", "lat": x, "lng": y, "ts": "..." }
//
// Ce service est instancié par `NetworkCoordinator` et branché sur
// le stream de messages entrants du `P2PMeshService`.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../database/alert_model.dart';

// ============================================================================
// Modèle d'un signal panic reçu d'un pair
// ============================================================================

class _PanicSignal {
  _PanicSignal({
    required this.peerId,
    required this.lat,
    required this.lng,
    required this.receivedAt,
  });

  final String peerId;
  final double lat;
  final double lng;
  final DateTime receivedAt;
}

// ============================================================================
// Événement d'alerte panic collective (envoyé à l'UI)
// ============================================================================

class CollectivePanicEvent {
  const CollectivePanicEvent({
    required this.alert,
    required this.peerCount,
    required this.center,
  });

  /// L'alerte créée automatiquement.
  final Alert alert;

  /// Nombre de pairs qui ont déclenché le panic.
  final int peerCount;

  /// Centre géographique calculé.
  final LatLng center;
}

// ============================================================================
// Service
// ============================================================================

/// Seuil de pairs déclenchant l'alerte collective.
const int kPanicCollectifThreshold = 5;

/// Fenêtre de temps (2 minutes) dans laquelle les signals sont comptés.
const Duration kPanicTimeWindow = Duration(minutes: 2);

class CollectivePanicService {
  CollectivePanicService._();
  static final CollectivePanicService instance = CollectivePanicService._();

  /// Callback appelé par le coordinateur pour créer une alerte.
  /// Injecté par `NetworkCoordinator.init()`.
  Future<Alert> Function({
    required AlertType type,
    required double latitude,
    required double longitude,
    String description,
  })? _createAlertCallback;

  final _collectivePanicController =
      StreamController<CollectivePanicEvent>.broadcast();

  /// Stream d'alertes panic collectives automatiques.
  Stream<CollectivePanicEvent> get collectivePanicEvents =>
      _collectivePanicController.stream;

  /// Historique des signaux panic reçus, indexés par peerId.
  final Map<String, _PanicSignal> _signals = {};

  /// Timestamp de la dernière alerte collective créée (anti-spam : on
  /// évite de recréer une alerte si on vient d'en créer une récemment).
  DateTime? _lastCollectiveAlert;

  /// Durée minimale entre deux alertes collectives successives.
  static const Duration _cooldown = Duration(minutes: 3);

  /// Injecte le callback de création d'alerte.
  void setCreateAlertCallback(
    Future<Alert> Function({
      required AlertType type,
      required double latitude,
      required double longitude,
      String description,
    }) callback,
  ) {
    _createAlertCallback = callback;
  }

  /// Enregistre un signal panic reçu d'un pair.
  ///
  /// Appelé par `NetworkCoordinator._handleIncoming()` pour chaque
  /// message de type `"panic"` reçu du maillage P2P.
  Future<void> recordPanicSignal({
    required String peerId,
    required double lat,
    required double lng,
  }) async {
    final now = DateTime.now().toUtc();

    // Purge les signaux hors fenêtre temporelle.
    _purgeOldSignals(now);

    // Enregistre (ou met à jour) le signal de ce pair.
    _signals[peerId] = _PanicSignal(
      peerId: peerId,
      lat: lat,
      lng: lng,
      receivedAt: now,
    );

    if (kDebugMode) {
      debugPrint(
        '[CollectivePanicService] signal panic de $peerId '
        '(${_signals.length}/$kPanicCollectifThreshold)',
      );
    }

    // Vérifie si le seuil est atteint.
    if (_signals.length >= kPanicCollectifThreshold) {
      await _triggerCollectiveAlert(now);
    }
  }

  /// Diffuse le signal panic local de cet appareil sur le réseau.
  /// Retourne le payload JSON à broadcaster.
  Map<String, dynamic> buildLocalPanicPayload({
    required String localPeerId,
    required double lat,
    required double lng,
  }) {
    return {
      'kind': 'panic',
      'peerId': localPeerId,
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // --------------------------------------------------------------------------
  // Privé
  // --------------------------------------------------------------------------

  void _purgeOldSignals(DateTime now) {
    _signals.removeWhere((_, signal) =>
        now.difference(signal.receivedAt) > kPanicTimeWindow);
  }

  Future<void> _triggerCollectiveAlert(DateTime now) async {
    // Anti-spam : pas d'alerte si on en a déjà créé une récemment.
    if (_lastCollectiveAlert != null &&
        now.difference(_lastCollectiveAlert!) < _cooldown) {
      return;
    }

    final cb = _createAlertCallback;
    if (cb == null) return;

    // Calcule le centre géographique (barycentre).
    final signals = List<_PanicSignal>.from(_signals.values);
    final center = _computeCenter(signals);

    if (kDebugMode) {
      debugPrint(
        '[CollectivePanicService] SEUIL ATTEINT (${signals.length} pairs) ! '
        'Centre : ${center.latitude}, ${center.longitude}',
      );
    }

    _lastCollectiveAlert = now;

    // Vide les signaux pour éviter les déclenchements multiples
    // pour le même groupe.
    _signals.clear();

    // Crée l'alerte via le coordinator.
    try {
      final alert = await cb(
        type: AlertType.panicCollectif,
        latitude: center.latitude,
        longitude: center.longitude,
        description:
            '⚠️ Alerte Panic Collective — Tension importante détectée '
            '(${signals.length} appareils)',
      );

      _collectivePanicController.add(CollectivePanicEvent(
        alert: alert,
        peerCount: signals.length,
        center: center,
      ));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[CollectivePanicService] erreur création alerte : $e');
      }
    }
  }

  /// Calcule le barycentre géographique des signaux.
  LatLng _computeCenter(List<_PanicSignal> signals) {
    if (signals.isEmpty) return const LatLng(0, 0);
    // Conversion en radians puis moyennage sur les cosinus/sinus
    // pour gérer correctement le wrapping ±180°.
    double x = 0, y = 0, z = 0;
    for (final s in signals) {
      final lat = s.lat * pi / 180;
      final lng = s.lng * pi / 180;
      x += cos(lat) * cos(lng);
      y += cos(lat) * sin(lng);
      z += sin(lat);
    }
    final n = signals.length.toDouble();
    x /= n;
    y /= n;
    z /= n;
    final centralLng = atan2(y, x) * 180 / pi;
    final centralSqrt = sqrt(x * x + y * y);
    final centralLat = atan2(z, centralSqrt) * 180 / pi;
    return LatLng(centralLat, centralLng);
  }

  void dispose() {
    _collectivePanicController.close();
  }
}
