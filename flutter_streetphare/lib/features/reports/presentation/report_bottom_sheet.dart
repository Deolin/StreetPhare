import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/report_type.dart';

/// Feuille d'ancrage (Bottom Sheet) présentant les différents types
/// de signalements citoyens disponibles.
///
/// L'utilisateur peut :
///   1. Choisir un type de signalement (Barrages, Nasses, etc.)
///   2. Confirmer pour enregistrer le signalement (MVP : log console)
class ReportBottomSheet extends StatelessWidget {
  const ReportBottomSheet({super.key});

  /// Affiche la feuille d'ancrage modale
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ReportBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: StreetPhareTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poignée de saisie
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: StreetPhareTheme.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Titre
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.add_alert, color: StreetPhareTheme.primary),
                  SizedBox(width: 12),
                  Text(
                    'Nouveau signalement',
                    style: TextStyle(
                      color: StreetPhareTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Sélectionnez la nature de l\'événement à signaler :',
                style: TextStyle(
                  color: StreetPhareTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Grille des types de signalement
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: ReportType.values
                    .map(
                      (type) => _ReportTypeTile(
                        type: type,
                        onTap: () => _onTypeSelected(context, type),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Bouton annuler
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: StreetPhareTheme.textSecondary.withValues(
                        alpha: 0.3,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: StreetPhareTheme.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Action déclenchée lors du choix d'un type de signalement
  void _onTypeSelected(BuildContext context, ReportType type) {
    // Ferme la feuille d'ancrage
    Navigator.of(context).pop();

    // Affiche un message de confirmation (MVP)
    // Note : aucune donnée nominative n'est collectée.
    debugPrint('[Report] Signalement de type "${type.label}" enregistré.');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: type.color,
        content: Row(
          children: [
            Icon(type.icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Signalement "${type.label}" enregistré.\n'
                'Merci de votre contribution citoyenne.',
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Tuile représentant un type de signalement
class _ReportTypeTile extends StatelessWidget {
  const _ReportTypeTile({required this.type, required this.onTap});

  final ReportType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: type.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: type.color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(type.icon, color: type.color, size: 32),
              const SizedBox(height: 8),
              Text(
                type.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
