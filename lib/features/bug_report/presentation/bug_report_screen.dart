// lib/features/bug_report/presentation/bug_report_screen.dart
//
// Écran dédié au signalement de bug.
// Wrapper autour de BugReportService pour l'intégration dans le routeur.
//
// Référence : docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md — Anomalie M9

import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import 'bug_report_service.dart';

/// Écran de signalement de bug — formulaire complet.
///
/// Accessible via la route [AppRoutes.bugReport] ou le FAB flottant.
class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;
  String? _result;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _sending = true;
      _result = null;
    });

    try {
      final report = BugReport(
        title: 'Rapport manuel',
        description: message,
        platform: BugReportService.currentPlatform,
        appVersion: '2.2.0',
        category: BugCategory.bug,
      );
      final result = await BugReportService.instance.submit(report);
      setState(() => _result = result.message);
    } catch (e) {
      setState(() => _result = 'Erreur d\'envoi : $e');
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signaler un bug'),
        backgroundColor: StreetPhareTheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Décrivez le problème rencontré :',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Étapes pour reproduire, comportement attendu...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Envoi...' : 'Envoyer le rapport'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Text(
                _result!,
                style: TextStyle(
                  color: _result!.contains('Erreur') ||
                          _result!.contains('Impossible')
                      ? Colors.red
                      : Colors.green,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
