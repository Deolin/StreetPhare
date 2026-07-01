// lib/services/bug_report_service.dart
//
// ⚠️ DÉPRÉCIÉ — Utiliser `features/bug_report/presentation/bug_report_service.dart`.
//
// Ce fichier est conservé pour rétrocompatibilité et délègue
// au service unifié dans `features/bug_report/`.
// Migration complète planifiée en Phase 3.
//
// Référence : docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md — Anomalie E6

import '../features/bug_report/presentation/bug_report_service.dart' as unified;

// Ré-export pour compatibilité.
export '../features/bug_report/presentation/bug_report_service.dart'
    show BugCategory, BugCategoryExt, BugReport, BugReportResult;

/// @deprecated Utiliser `unified.BugReportService.instance` directement.
class BugReportService {
  BugReportService._();

  @Deprecated('Utiliser unified.BugReportService.instance')
  static final BugReportService instance = BugReportService._();

  /// Délégue au service unifié.
  @Deprecated('Utiliser unified.BugReportService.instance.submit()')
  Future<bool> send(dynamic report) async {
    final unifiedReport = unified.BugReport(
      title: (report as dynamic).title ?? 'Legacy report',
      description: (report).description ?? '',
      platform: (report).platform ?? unified.BugReportService.currentPlatform,
      appVersion: (report).appVersion ?? 'unknown',
    );
    final result =
        await unified.BugReportService.instance.submit(unifiedReport);
    return result == unified.BugReportResult.success;
  }

  /// Délégue au service unifié.
  static bool get isTestEnvironment {
    try {
      return const String.fromEnvironment('FIREBASE_TEST_LAB') == 'true';
    } catch (_) {
      return false;
    }
  }
}
