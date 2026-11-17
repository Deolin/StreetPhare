// lib/services/streetphare_foreground_task.dart
//
// Service avant-plan StreetPhare (flutter_foreground_task).
//
// Maintient le processus de l'application vivant en arrière-plan (ex. quand
// l'app est minimisée ou fermée) grâce à une notification persistante
// obligatoire (« 🔦 StreetPhare — surveillance active »), et reçoit/relaie
// les alertes pour les afficher même si l'interface n'est pas au premier plan.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notification_service.dart';

/// Point d'entrée exécuté dans l'isolate d'arrière-plan au démarrage du
/// service. Doit rester une fonction top-level (contrainte du plugin).
@pragma('vm:entry-point')
void startStreetPhareService() {
  FlutterForegroundTask.setTaskHandler(StreetPhareTaskHandler());
}

/// Gère le cycle de vie du service avant-plan dans l'isolate d'arrière-plan.
class StreetPhareTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (kDebugMode) {
      debugPrint('[FgService] démarrage (starter=${starter.name})');
    }
    // Rend le service de notifications utilisable depuis cet isolate
    // (flutter_local_notifications est enregistré sur le moteur du service).
    try {
      await NotificationService.instance.init();
    } catch (e) {
      if (kDebugMode) debugPrint('[FgService] init notif: $e');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Rappel périodique : maintient l'isolate d'arrière-plan éveillé et
    // rafraîchit la notification (retour de vie visible pour l'utilisateur).
    unawaited(
      FlutterForegroundTask.updateService(
        notificationTitle: '🔦 StreetPhare — surveillance active',
        notificationText:
            'Dernière activité : ${_hhmm(timestamp)}. Vous restez prévenu(e).',
      ),
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (kDebugMode) debugPrint('[FgService] arrêt (timeout=$isTimeout)');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onReceiveData(Object data) {
    // Pont depuis l'isolate principal : `FlutterForegroundTask.sendDataToTask`.
    if (data is Map && data['type'] == 'alert') {
      unawaited(
        NotificationService.instance.showAlertNotification(
          title: '${data['title'] ?? 'Alerte StreetPhare'}',
          body: '${data['body'] ?? ''}',
          id: (data['id'] as num?)?.toInt() ?? 0,
        ),
      );
    }
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// Enveloppe des appels `FlutterForegroundTask` utilisés par l'UI.
class StreetPhareForegroundTask {
  StreetPhareForegroundTask._();

  static bool _initialized = false;

  /// Le service avant-plan n'existe que sur Android/iOS.
  static bool get _isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// À appeler une fois au démarrage de l'app (avant `runApp`) : ouvre le
  /// port de communication isolat principal ⇄ isolat de service + enregistre
  /// les options.
  static void initCommunication() {
    FlutterForegroundTask.initCommunicationPort();
    init();
  }

  /// Enregistre les options (notification + service) du service avant-plan.
  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'streetphare_foreground_service',
        channelName: 'Surveillance StreetPhare',
        channelDescription:
            'Notification affichée tant que la surveillance en arrière-plan '
            'est active.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
        // On conserve le service même quand l'utilisateur ferme l'app.
        stopWithTask: false,
      ),
    );
  }

  /// Démarre le service avant-plan (lève une exception en cas d'échec).
  static Future<void> start() async {
    if (!_isSupported) return; // indisponible sur cette plateforme
    init();
    await _ensureNotificationPermission();

    if (await FlutterForegroundTask.isRunningService) return; // déjà actif

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '🔦 StreetPhare — surveillance active',
      notificationText: 'Vous serez prévenu(e) des alertes à proximité.',
      callback: startStreetPhareService,
    );
    if (result is ServiceRequestFailure) {
      throw Exception('Échec du service avant-plan : ${result.error}');
    }
  }

  /// Arrête le service avant-plan.
  static Future<void> stop() async {
    if (!_isSupported) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  /// `true` si le service avant-plan tourne actuellement.
  static Future<bool> get isRunning =>
      _isSupported ? FlutterForegroundTask.isRunningService : Future.value(false);

  static Future<void> _ensureNotificationPermission() async {
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }
}
