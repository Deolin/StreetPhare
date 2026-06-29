// lib/core/config/app_config.dart
//
// Configuration centralisée de l'application StreetPhare.
//
// Ce module unifie les constantes auparavant éparpillées entre :
//   - `lib/constants/app_constants.dart` (adminServerUrl)
//   - `lib/network/network_config.dart` (productionHost, ports, URLs)
//
// Support par environnement (dev / staging / prod) via `--dart-define` :
//   flutter run --dart-define=STREETPHARE_ENV=staging
//   flutter run --dart-define=STREETPHARE_ENV=production
//
// Si aucun flag n'est défini, l'environnement par défaut est 'production'.

import 'package:flutter/foundation.dart';

/// Environnement d'exécution de l'application.
enum AppEnvironment {
  development,
  staging,
  production;

  bool get isProduction => this == AppEnvironment.production;
  bool get isStaging => this == AppEnvironment.staging;
  bool get isDevelopment => this == AppEnvironment.development;
}

/// Configuration centralisée de l'application.
///
/// Remplace l'usage direct de `AppStrings.adminServerUrl` et
/// `NetworkConfig.*` par une façade unique. Les anciennes classes
/// restent disponibles pour la rétrocompatibilité.
class AppConfig {
  AppConfig._();

  // ═════════════════════════════════════════════════════════════════════
  // Environnement
  // ═════════════════════════════════════════════════════════════════════

  /// Environnement courant, déterminé par `--dart-define=STREETPHARE_ENV`.
  static final AppEnvironment environment = _resolveEnvironment();

  static AppEnvironment _resolveEnvironment() {
    const env = String.fromEnvironment('STREETPHARE_ENV', defaultValue: 'production');
    switch (env.toLowerCase()) {
      case 'development':
      case 'dev':
        return AppEnvironment.development;
      case 'staging':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
      default:
        return AppEnvironment.production;
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // Serveur
  // ═════════════════════════════════════════════════════════════════════

  /// Host du serveur de production.
  static const String productionHost = 'streetphare.ddns.net';

   /// Host du serveur de production backup.
  static const String backupHost = 'streetphare-backup.myddns.me';

  /// Port du serveur principal.
  static const int primaryPort = 3000;

  /// Port du serveur secondaire (backup).
  static const int secondaryPort = 3001;

  /// URL du serveur principal (HTTPS).
  static String get primaryServer => 'https://$productionHost:$primaryPort';

  /// URL du serveur secondaire (HTTPS).
  static String get secondaryServer => 'https://$backupHost:$secondaryPort';

  /// URL du relay WebSocket (WSS).
  static String get relayUrl => 'wss://$productionHost:$primaryPort/mesh';

  /// URL de l'interface d'administration.
  static String get adminUrl => 'https://$productionHost';

  // ═════════════════════════════════════════════════════════════════════
  // Fallback local (développement / loopback)
  // ═════════════════════════════════════════════════════════════════════

  static String get _localFallbackHost {
    if (kIsWeb) return '127.0.0.1';
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return '10.0.2.2'; // Android emulator gateway
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  static String get localhostPrimaryServer =>
      'http://$_localFallbackHost:$primaryPort';
  static String get localhostSecondaryServer =>
      'http://$_localFallbackHost:$secondaryPort';
  static String get localhostRelayUrl =>
      'ws://$_localFallbackHost:$primaryPort/mesh';

  // ═════════════════════════════════════════════════════════════════════
  // Feature Flags
  // ═════════════════════════════════════════════════════════════════════

  static const bool enableAdvancedRouting =
      bool.fromEnvironment('FEATURE_ADVANCED_ROUTING', defaultValue: false);

  static const bool enableMeshAutonome =
      bool.fromEnvironment('FEATURE_MESH_AUTONOME', defaultValue: true);

  static const bool enableApkShare =
      bool.fromEnvironment('FEATURE_APK_SHARE', defaultValue: true);

  // ═════════════════════════════════════════════════════════════════════
  // Résumé (debug uniquement)
  // ═════════════════════════════════════════════════════════════════════

  static String describe() {
    return 'AppConfig{'
        'env=$environment '
        'host=$productionHost '
        'primary=$primaryServer '
        'secondary=$secondaryServer '
        'relay=$relayUrl '
        'features={advancedRouting:$enableAdvancedRouting '
        'meshAutonome:$enableMeshAutonome '
        'apkShare:$enableApkShare}'
        '}';
  }
}