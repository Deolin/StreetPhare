// lib/features/bug_report/presentation/bug_report_fab.dart
//
// [5] FAB persistant de signalement de bugs — StreetPhare
//
// S'affiche en bas à gauche au-dessus de tous les éléments de l'interface.
// Ouvre un dialogue de saisie du rapport.

import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import 'bug_report_service.dart';

// ============================================================================
// BugReportFab — Widget à intégrer dans le Stack racine de l'app
// ============================================================================

class BugReportFab extends StatelessWidget {
  const BugReportFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 32,
      child: Tooltip(
        message: 'Signaler un bug ou une suggestion',
        child: Material(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: StreetPhareTheme.surface.withValues(alpha: 0.92),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => BugReportDialog.show(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    );
  }
}

// ============================================================================
// BugReportDialog — Dialogue de saisie
// ============================================================================

class BugReportDialog extends StatefulWidget {
  const BugReportDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const BugReportDialog(),
      );

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  BugCategory _category = BugCategory.bug;
  bool _submitting = false;
  String? _resultMessage;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _resultMessage = null;
    });

    final report = BugReport(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      platform: BugReportService.currentPlatform,
      appVersion: '1.2.0',
      category: _category,
    );

    final result = await BugReportService.instance.submit(report);

    if (mounted) {
      setState(() {
        _submitting = false;
        _resultMessage = result.message;
      });

      if (result == BugReportResult.success) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.bug_report, color: StreetPhareTheme.primary, size: 26),
          const SizedBox(width: 10),
          Text(
            'Signaler un bug',
            style: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Explication
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StreetPhareTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: StreetPhareTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Ce formulaire envoie un rapport de bug ou une '
                    'suggestion d\'amélioration directement au serveur '
                    'web d\'administration de StreetPhare. '
                    'Aucune donnée personnelle n\'est collectée.',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Catégorie
                Text('Catégorie',
                    style: TextStyle(
                        color: onSurface.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: BugCategory.values
                      .map((c) => ChoiceChip(
                            label: Text(c.label, style: const TextStyle(fontSize: 12)),
                            selected: _category == c,
                            selectedColor:
                                StreetPhareTheme.primary.withValues(alpha: 0.2),
                            onSelected: (_) => setState(() => _category = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),

                // Titre
                TextFormField(
                  controller: _titleCtrl,
                  style: TextStyle(color: onSurface),
                  decoration: InputDecoration(
                    labelText: 'Titre bref *',
                    hintText: 'Ex: L\'écran de la carte crash au démarrage',
                    hintStyle: TextStyle(
                        color: onSurface.withValues(alpha: 0.4), fontSize: 12),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
                  maxLength: 80,
                ),
                const SizedBox(height: 10),

                // Description
                TextFormField(
                  controller: _descCtrl,
                  style: TextStyle(color: onSurface),
                  decoration: const InputDecoration(
                    labelText: 'Description détaillée *',
                    hintText:
                        'Décrivez le problème, les étapes pour le reproduire, '
                        'ou votre suggestion…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Description trop courte (min 10 caractères)'
                      : null,
                  maxLength: 1000,
                ),

                // Résultat de l'envoi
                if (_resultMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _resultMessage!,
                    style: TextStyle(
                      color: _resultMessage!.startsWith('✅')
                          ? Colors.green
                          : StreetPhareTheme.danger,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton.icon(
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 18),
          label: Text(_submitting ? 'Envoi…' : 'Envoyer'),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
