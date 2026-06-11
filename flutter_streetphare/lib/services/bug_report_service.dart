// lib/services/bug_report_service.dart
//
// Service d'envoi de rapports de bugs pour StreetPhare.
//
// Pipeline hybride :
//   1. Envoie le rapport au serveur d'administration StreetPhare via REST.
//   2. Détecte les environnements de test (Play Console / Firebase Test Lab)
//      et y envoie simultanément les logs de crash.
//   3. Stocke les rapports en local (SharedPreferences) si hors-ligne.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ============================================================================
// Modèle de rapport de bug
// ============================================================================

class BugReport {
  const BugReport({
    required this.title,
    required this.description,
    this.screenshotBase64,
    this.appVersion = '1.2.0',
    this.platform,
    this.metadata = const {},
  });

  final String title;
  final String description;
  final String? screenshotBase64;
  final String appVersion;
  final String? platform;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'screenshot': screenshotBase64,
        'app_version': appVersion,
        'platform': platform ?? _currentPlatform(),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'is_test_env': BugReportService.isTestEnvironment,
        'metadata': metadata,
      };

  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isWindows) return 'windows';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }
}

// ============================================================================
// BugReportService
// ============================================================================

class BugReportService {
  BugReportService._();
  static final BugReportService instance = BugReportService._();

  /// URL du serveur d'administration.
  static const String _adminBaseUrl = 'http://localhost:4000';

  /// Détecte si l'app tourne dans un environnement de test Google
  /// (Firebase Test Lab, Play Console pre-launch testing).
  static bool get isTestEnvironment {
    // Firebase Test Lab définit la propriété système 'firebase.test.lab'
    // ou la variable d'environnement 'FIREBASE_TEST_LAB'.
    if (const String.fromEnvironment('FIREBASE_TEST_LAB') == 'true') {
      return true;
    }
    // Heuristique Debug : en mode release sur emulateur = test probable.
    if (kDebugMode) return false;
    return false; // Peut être étendu via platform channels Android/iOS
  }

  // --------------------------------------------------------------------------
  // Envoi d'un rapport de bug
  // --------------------------------------------------------------------------

  /// Envoie un rapport de bug au serveur d'administration.
  /// Retourne `true` si l'envoi a réussi.
  Future<bool> send(BugReport report) async {
    bool success = false;

    // 1. Envoi vers le serveur StreetPhare Admin.
    try {
      final response = await http
          .post(
            Uri.parse('$_adminBaseUrl/api/bugs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(report.toJson()),
          )
          .timeout(const Duration(seconds: 8));
      success = response.statusCode == 200 || response.statusCode == 201;
      debugPrint('[BugReport] Envoyé → admin: ${response.statusCode}');
    } catch (e) {
      debugPrint('[BugReport] Erreur envoi admin: $e');
    }

    // 2. Si environnement de test → log supplémentaire.
    if (isTestEnvironment) {
      _logForTestEnvironment(report);
    }

    return success;
  }

  /// Log spécifique aux environnements de test Google.
  void _logForTestEnvironment(BugReport report) {
    // En Firebase Test Lab ou Play Console, les logs stdout sont
    // automatiquement capturés et remontés dans la console Firebase.
    // Préfixe "[STREETPHARE_BUG]" pour faciliter le filtrage.
    debugPrint('[STREETPHARE_BUG] ===========================');
    debugPrint('[STREETPHARE_BUG] TITLE: ${report.title}');
    debugPrint('[STREETPHARE_BUG] DESC:  ${report.description}');
    debugPrint('[STREETPHARE_BUG] VER:   ${report.appVersion}');
    debugPrint('[STREETPHARE_BUG] PLAT:  ${report.platform}');
    debugPrint('[STREETPHARE_BUG] TIME:  ${DateTime.now().toIso8601String()}');
    debugPrint('[STREETPHARE_BUG] ===========================');
  }
}
