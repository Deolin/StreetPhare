// lib/features/bug_report/presentation/bug_report_service.dart
//
// [5] Service de signalement de bugs — StreetPhare
//
// Fonctionnalités :
//   - Bouton flottant persistant (bas gauche) sur tous les écrans.
//   - Section dédiée dans les Paramètres (bouton + texte explicatif).
//   - Envoi des rapports au serveur web d'administration.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_streetphare/constants/app_constants.dart';

// ============================================================================
// Modèle de rapport
// ============================================================================

class BugReport {
  const BugReport({
    required this.title,
    required this.description,
    required this.platform,
    required this.appVersion,
    this.extraLogs,
    this.category = BugCategory.bug,
  });

  final String title;
  final String description;
  final String platform;
  final String appVersion;
  final String? extraLogs;
  final BugCategory category;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'platform': platform,
        'app_version': appVersion,
        'category': category.name,
        'extra_logs': extraLogs,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      };
}

enum BugCategory {
  bug,
  suggestion,
  crash,
  performance,
}

extension BugCategoryExt on BugCategory {
  String get label {
    switch (this) {
      case BugCategory.bug:
        return '🐛 Bug';
      case BugCategory.suggestion:
        return '💡 Suggestion';
      case BugCategory.crash:
        return '💥 Crash';
      case BugCategory.performance:
        return '⚡ Performance';
    }
  }
}

// ============================================================================
// BugReportService
// ============================================================================

class BugReportService {
  BugReportService._();
  static final BugReportService instance = BugReportService._();

  /// Envoie un rapport de bug au serveur d'administration.
  Future<BugReportResult> submit(BugReport report) async {
    try {
      final payload = jsonEncode(report.toJson());
      debugPrint('[BugReport] envoi en cours… ${report.title}');

      final response = await http
          .post(
            Uri.parse(AppStrings.adminServerUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-StreetPhare-Client': '1.0',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[BugReport] rapport envoyé avec succès.');
        return BugReportResult.success;
      } else {
        debugPrint('[BugReport] erreur serveur: ${response.statusCode}');
        return BugReportResult.serverError;
      }
    } catch (e) {
      if (!kIsWeb && e is io.SocketException) {
        debugPrint('[BugReport] pas de connexion réseau');
        return BugReportResult.networkError;
      }
      if (e is TimeoutException) {
        debugPrint('[BugReport] timeout lors de l\'envoi');
        return BugReportResult.networkError;
      }
      debugPrint('[BugReport] erreur inattendue: $e');
      return BugReportResult.unknownError;
    }
  }

  /// Détecte la plateforme courante.
  static String get currentPlatform {
    if (kIsWeb) return 'web';
    try {
      if (io.Platform.isAndroid) return 'android';
      if (io.Platform.isIOS) return 'ios';
      if (io.Platform.isWindows) return 'windows';
      if (io.Platform.isMacOS) return 'macos';
      if (io.Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }
}

enum BugReportResult {
  success,
  networkError,
  serverError,
  unknownError;

  String get message {
    switch (this) {
      case BugReportResult.success:
        return '✅ Rapport envoyé avec succès. Merci !';
      case BugReportResult.networkError:
        return '📶 Impossible de joindre le serveur. '
            'Vérifiez votre connexion réseau.';
      case BugReportResult.serverError:
        return '⚠️ Erreur du serveur. Réessayez plus tard.';
      case BugReportResult.unknownError:
        return '❓ Erreur inattendue. Réessayez plus tard.';
    }
  }
}
