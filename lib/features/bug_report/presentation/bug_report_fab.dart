// lib/features/bug_report/presentation/bug_report_fab.dart
//
// Bouton flottant global "Rapport de Bug" — StreetPhare v3.0
//
// Interface unifiée unique remplaçant les deux anciens boutons redondants.
//
// Flux utilisateur :
//   1. Clic → Dialogue unifié avec deux options :
//      - Option A : "Envoi direct" → rapport technique automatique immédiat
//      - Option B : "Ajouter des détails" → champ texte avant envoi
//   2. Dans tous les cas : compilation automatique des données techniques :
//      - Logs récents (ClientDebugLogger)
//      - État FailoverManager + Heartbeat
//      - Informations appareil (device_info_plus)
//      - Détails saisis par l'utilisateur (si Option B)
//   3. Ouverture du client mail via mailto: supportbug@streetphare.be
//      avec sujet pré-rempli et corps complet encodé URL.

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../main.dart' show navigatorKey;
import '../../../core/theme/streetphare_theme.dart';
import '../../../debug/client_debug_logger.dart';
import '../../../network/failover_manager.dart';

// ============================================================================
// BugReportFab — Bouton global unique (remplace les 2 anciens boutons)
// ============================================================================

class BugReportFab extends StatelessWidget {
  const BugReportFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      top: 100,
      child: SafeArea(
        child: Semantics(
          label: 'Signaler un bug',
          button: true,
          child: Material(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            color: StreetPhareTheme.surface.withValues(alpha: 0.92),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openUnifiedDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bug_report_outlined,
                        color: StreetPhareTheme.primary, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Bug',
                      style: TextStyle(
                        color: StreetPhareTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openUnifiedDialog() {
    final navContext = navigatorKey.currentContext;
    if (navContext != null) {
      UnifiedBugReportDialog.show(navContext);
    } else if (kDebugMode) {
      debugPrint('[BugReportFab] navigatorKey.currentContext est null');
    }
  }
}

// ============================================================================
// UnifiedBugReportDialog — Dialogue unique unifié
// ============================================================================

class UnifiedBugReportDialog extends StatefulWidget {
  const UnifiedBugReportDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const UnifiedBugReportDialog(),
      );

  @override
  State<UnifiedBugReportDialog> createState() => _UnifiedBugReportDialogState();
}

class _UnifiedBugReportDialogState extends State<UnifiedBugReportDialog> {
  // ── Option B : saisie utilisateur ──────────────────────────────────
  final _descCtrl = TextEditingController();
  bool _showDetailsField = false;
  bool _generating = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════
  // COLLECTE TECHNIQUE AUTOMATIQUE
  // ══════════════════════════════════════════════════════════════════════

  /// Compile TOUTES les données techniques et génère le mailto.
  Future<void> _generateAndSend({String? userDetails}) async {
    setState(() => _generating = true);

    try {
      // ── Collecte parallèle des données techniques ─────────────────
      final results = await Future.wait([
        _collectDeviceInfo(),
        _collectAppState(),
      ], eagerError: false);

      String deviceInfoStr;
      try {
        deviceInfoStr = results[0];
      } catch (_) {
        deviceInfoStr = '⚠ Impossible de collecter les infos appareil.';
      }

      String appStateStr;
      try {
        appStateStr = results[1];
      } catch (_) {
        appStateStr = '⚠ Impossible de collecter l\'état de l\'application.';
      }

      final logsStr = _collectRecentLogs();

      // ── Construction du corps de l'email ──────────────────────────
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final body = StringBuffer();
      body.writeln('═══ RAPPORT DE BUG TECHNIQUE — StreetPhare ═══');
      body.writeln('Date : $dateStr (UTC)');
      body.writeln();

      // ── Détails utilisateur (si Option B) ─────────────────────────
      if (userDetails != null && userDetails.trim().isNotEmpty) {
        body.writeln('── SAISIE UTILISATEUR ──');
        body.writeln(userDetails.trim());
        body.writeln();
      }

      // ── Logs récents ──────────────────────────────────────────────
      body.writeln('── LOGS RÉCENTS ──');
      body.writeln(logsStr.isEmpty ? '(aucun log disponible)' : logsStr);
      body.writeln();

      // ── État de l'application ─────────────────────────────────────
      body.writeln('── ÉTAT DE L\'APPLICATION ──');
      body.writeln(appStateStr);
      body.writeln();

      // ── Informations appareil ─────────────────────────────────────
      body.writeln('── INFORMATIONS APPAREIL ──');
      body.writeln(deviceInfoStr);
      body.writeln();

      // ── Pied de page ──────────────────────────────────────────────
      body.writeln('── TRANSMIS AUTOMATIQUEMENT PAR L\'APPLICATION ──');
      body.writeln('Version app : 2.2.0');
      body.writeln('Plateforme  : $_platformLabel');

      // ── Génération mailto ─────────────────────────────────────────
      final subject = 'Rapport de Bug Technique - StreetPhare - $dateStr';
      final encodedBody = Uri.encodeComponent(body.toString());

      final uri = Uri(
        scheme: 'mailto',
        path: 'supportbug@streetphare.be',
        query: 'subject=${Uri.encodeComponent(subject)}&body=$encodedBody',
      );

      if (!mounted) return;

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Impossible d\'ouvrir le client mail. '
                  'Veuillez envoyer manuellement à supportbug@streetphare.be'),
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BugReport] ❌ Erreur génération rapport : $e');
      }
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur lors de la génération du rapport : $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Collecte : Logs récents depuis ClientDebugLogger
  // ══════════════════════════════════════════════════════════════════════

  String _collectRecentLogs() {
    try {
      final snapshot = ClientDebugLogger.instance.getSnapshot();
      if (snapshot.isEmpty) return '(aucun log)';
      final lines = snapshot.split('\n');
      // Prend les 30 dernières lignes maximum.
      final recent =
          lines.length > 30 ? lines.sublist(lines.length - 30) : lines;
      return recent.join('\n');
    } catch (e) {
      return '(erreur collecte logs : $e)';
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Collecte : Informations de l'appareil (device_info_plus)
  // ══════════════════════════════════════════════════════════════════════

  /// Collecte les informations de l'appareil via dart:io (sans dépendance externe).
  /// Utilise les capacités natives de Flutter pour détecter la plateforme
  /// et les caractéristiques de base de l'appareil.
  Future<String> _collectDeviceInfo() async {
    final buf = StringBuffer();
    try {
      if (kIsWeb) {
        buf.writeln('Type         : Web');
        buf.writeln('Navigateur   : (détecté automatiquement)');
      } else {
        // Utilise dart:io pour obtenir le nom de l'OS et sa version.
        buf.writeln('Type         : ${_platformLabel}');
        buf.writeln('OS           : ${io.Platform.operatingSystem}');
        buf.writeln('Version OS   : ${io.Platform.operatingSystemVersion}');
        buf.writeln('Cœurs CPU    : ${io.Platform.numberOfProcessors}');
        buf.writeln('Locale       : ${io.Platform.localeName}');
        buf.writeln(
            'Script shell : ${io.Platform.isWindows ? 'cmd/powershell' : 'bash/sh'}');
      }
      buf.writeln('Mode debug   : $kDebugMode');
      buf.writeln('Mode release : $kReleaseMode');
      buf.writeln('Mode profile : $kProfileMode');
    } catch (e) {
      buf.writeln('Erreur collecte device info : $e');
    }
    return buf.toString();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Collecte : État de l'application
  // ══════════════════════════════════════════════════════════════════════

  Future<String> _collectAppState() async {
    final buf = StringBuffer();
    try {
      // Failover Manager
      final fm = FailoverManager.instance;
      buf.writeln('[FailoverManager]');
      buf.writeln('  Serveur courant : ${fm.currentAddress}');
      buf.writeln(
          '  Serveurs morts  : ${fm.deadServersForSession.join(', ')}\\n'
          'ou (aucun)');
      buf.writeln();
    } catch (e) {
      buf.writeln('[FailoverManager] Erreur collecte : $e');
      buf.writeln();
    }

    try {
      // ClientDebugLogger snapshot complet
      buf.writeln('[ClientDebugLogger — Snapshot complet]');
      final fullSnapshot = ClientDebugLogger.instance.getSnapshot();
      if (fullSnapshot.isEmpty) {
        buf.writeln('  (aucun événement)');
      } else {
        buf.writeln(fullSnapshot);
      }
      buf.writeln();
    } catch (e) {
      buf.writeln('[ClientDebugLogger] Erreur collecte : $e');
      buf.writeln();
    }

    return buf.toString();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════

  static String get _platformLabel {
    try {
      if (kIsWeb) return 'Web';
      if (io.Platform.isAndroid) return 'Android';
      if (io.Platform.isIOS) return 'iOS';
      if (io.Platform.isWindows) return 'Windows';
      if (io.Platform.isMacOS) return 'macOS';
      if (io.Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Inconnue';
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD — Interface
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.bug_report_outlined,
              color: StreetPhareTheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rapport de Bug',
              style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ══════════════════════════════════════════════════════
              // ⚠️ MENTION OBLIGATOIRE : Non anonyme
              // ══════════════════════════════════════════════════════
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: const Color(0xFFFFB300), width: 1.5),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFE65100), size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ce rapport n\'est PAS anonyme. '
                        'Il inclura vos informations d\'appareil, '
                        'les logs de l\'application et vos données '
                        'd\'état, en plus des détails saisis.',
                        style: TextStyle(
                          color: Color(0xFFBF360C),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ══════════════════════════════════════════════════════
              // Option A : Envoi direct
              // ══════════════════════════════════════════════════════
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StreetPhareTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 22),
                  label: Text(
                    _generating ? 'Génération…' : 'Envoi direct',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  onPressed: _generating ? null : () => _generateAndSend(),
                ),
              ),
              const SizedBox(height: 12),

              // ══════════════════════════════════════════════════════
              // Option B : Ajouter des détails
              // ══════════════════════════════════════════════════════
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StreetPhareTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(
                        color: StreetPhareTheme.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    _showDetailsField
                        ? Icons.keyboard_arrow_up
                        : Icons.edit_note_rounded,
                    size: 22,
                  ),
                  label: Text(
                    _showDetailsField
                        ? 'Masquer les détails'
                        : 'Ajouter des détails',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  onPressed: _generating
                      ? null
                      : () => setState(
                          () => _showDetailsField = !_showDetailsField),
                ),
              ),

              // ── Champ de texte (Option B) ──────────────────────
              if (_showDetailsField) ...[
                const SizedBox(height: 14),
                Text(
                  'Décrivez ce que vous faisiez au moment du problème :',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 5,
                  maxLength: 2000,
                  style: TextStyle(color: onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ex: J\'étais en train de naviguer sur la carte '
                        'quand l\'écran est devenu noir…',
                    hintStyle: TextStyle(
                        color: onSurface.withValues(alpha: 0.4), fontSize: 13),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          StreetPhareTheme.primary.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _generating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 22),
                    label: Text(
                      _generating ? 'Génération…' : 'Envoyer avec ces détails',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    onPressed: _generating
                        ? null
                        : () => _generateAndSend(userDetails: _descCtrl.text),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _generating ? null : () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
