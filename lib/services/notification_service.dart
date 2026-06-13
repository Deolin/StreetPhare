// lib/services/notification_service.dart
//
// Service de notifications locales pour StreetPhare.
//
// Fonctionnalités :
//   1. Notification persistante "StreetPhare actif" avec bouton "Quitter".
//   2. Notifications d'alerte critique (danger à proximité en arrière-plan).
//   3. Dialogue pédagogique d'autorisation arrière-plan.
//   4. Multiplateforme : Android, iOS, Windows (graceful fallback).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================================
// IDs de notifications
// ============================================================================

const int _kPersistentNotifId = 1001;
const int _kAlertNotifBaseId = 2000;

// ============================================================================
// NotificationService
// ============================================================================

/// Service singleton de notifications locales pour StreetPhare.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // --------------------------------------------------------------------------
  // Initialisation
  // --------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;

    // ── Graceful fallback pour Desktop & Web ──────────────────────────────
    // Sur Windows, macOS et Linux, flutter_local_notifications requiert
    // des réglages spécifiques. On les fournit ici ; en cas d'échec
    // (runtime non supporté) on dégrade proprement.
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        const windowsSettings = WindowsInitializationSettings(
          appName: 'StreetPhare',
          appUserModelId: 'com.streetphare.streetphare',
          guid: 'a4b2c3d4-e5f6-7890-abcd-ef1234567890',
        );
        final linuxSettings = LinuxInitializationSettings(
          defaultActionName: 'Open StreetPhare',
          defaultIcon: AssetsLinuxIcon('assets/icons/app_icon.png'),
        );
        const darwinSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        await _plugin.initialize(
          settings: InitializationSettings(
            windows: windowsSettings,
            linux: linuxSettings,
            macOS: darwinSettings,
          ),
          onDidReceiveNotificationResponse: _onNotificationTap,
        );
        _initialized = true;
        if (kDebugMode) {
          debugPrint('[NotificationService] initialisé (Desktop)');
        }
        return;
      } catch (e) {
        _initialized = true;
        if (kDebugMode) {
          debugPrint('[NotificationService] Desktop fallback: $e');
        }
        return;
      }
    }

    // ── Android + iOS ──────────────────────────────────────────────────────
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _initialized = true;
    if (kDebugMode) debugPrint('[NotificationService] initialisé');
  }

  // --------------------------------------------------------------------------
  // Notification persistante "StreetPhare actif"
  // --------------------------------------------------------------------------

  Future<void> showPersistentNotification() async {
    if (!_initialized) await init();
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;

    const androidDetails = AndroidNotificationDetails(
      'streetphare_persistent',
      'StreetPhare Actif',
      channelDescription:
          'Indique que StreetPhare surveille activement votre zone.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      color: Color(0xFFFFB300),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_quit',
          'Quitter',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      categoryIdentifier: 'streetphare_persistent',
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: _kPersistentNotifId,
      title: '🔦 StreetPhare est actif',
      body: 'Surveillance de votre zone en cours. Appuyez pour ouvrir.',
      notificationDetails: details,
      payload: 'bring_to_foreground',
    );

    if (kDebugMode) {
      debugPrint('[NotificationService] notification persistante affichée');
    }
  }

  Future<void> dismissPersistentNotification() async {
    await _plugin.cancel(id: _kPersistentNotifId);
  }

  // --------------------------------------------------------------------------
  // Notification d'alerte critique
  // --------------------------------------------------------------------------

  Future<void> showAlertNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (!_initialized) await init();
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    final notifId = _kAlertNotifBaseId + (id % 100);

    const androidDetails = AndroidNotificationDetails(
      'streetphare_alerts',
      'Alertes StreetPhare',
      channelDescription: 'Alertes critiques de danger à proximité.',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFE53935),
      autoCancel: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: notifId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: 'alert_tap',
    );
    if (kDebugMode) debugPrint('[NotificationService] alerte: $title');
  }

  // --------------------------------------------------------------------------
  // Taps
  // --------------------------------------------------------------------------

  void _onNotificationTap(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('[NotificationService] tap: payload=${response.payload}, '
          'action=${response.actionId}');
    }
    if (response.actionId == 'action_quit') {
      dismissPersistentNotification();
    }
  }

  // --------------------------------------------------------------------------
  // Permissions
  // --------------------------------------------------------------------------

  Future<bool> requestPermissions() async {
    if (!_initialized) await init();

    if (Platform.isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await impl?.requestNotificationsPermission();
      return granted ?? false;
    }

    if (Platform.isIOS) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await impl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }
}

// ============================================================================
// Dialogue pédagogique d'autorisation arrière-plan
// ============================================================================

Future<void> showBackgroundPermissionDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.battery_saver, color: Color(0xFFFFB300), size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Autorisation arrière-plan',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pour vous alerter même quand StreetPhare n\'est pas à '
              'l\'écran, l\'application a besoin de fonctionner '
              'en arrière-plan.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            _buildPermStep(ctx, '1', 'Autoriser les notifications',
                'Une notification persistante "StreetPhare actif" '
                    'sera affichée. Vous pouvez la réduire.'),
            const SizedBox(height: 10),
            _buildPermStep(ctx, '2', 'Désactiver l\'optimisation batterie',
                'Dans Paramètres → Batterie → StreetPhare → '
                    '"Sans restriction" (Android) ou '
                    '"Activité en arrière-plan" (iOS).'),
            const SizedBox(height: 10),
            _buildPermStep(ctx, '3', 'Pourquoi c\'est important',
                'Sans cette autorisation, les alertes de danger '
                    'à proximité ne seront pas reçues en veille.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Plus tard',
            style: TextStyle(
              color: Theme.of(ctx)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB300),
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Autoriser'),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.showPersistentNotification();
  }
}

Widget _buildPermStep(
    BuildContext ctx, String num, String title, String desc) {
  final onSurface = Theme.of(ctx).colorScheme.onSurface;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: Color(0xFFFFB300),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            num,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
