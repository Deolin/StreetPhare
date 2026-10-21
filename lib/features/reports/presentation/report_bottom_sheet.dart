// lib/features/reports/presentation/report_bottom_sheet.dart
//
// Feuille d'ancrage de signalement — v3.0
//
// v3.0 : la feuille ne fait plus que sélectionner la nature de l'événement.
//        La position n'est plus capturée ici : MapScreen passe en mode
//        « placement » avec une icône glissable/déposable que l'utilisateur
//        déplace jusqu'au lieu exact du signalement.

import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../settings/data/app_preferences_store.dart';
import '../domain/models/report_type.dart';

/// Feuille d'ancrage (Bottom Sheet) présentant les types de signalements.
///
/// Retourne le [ReportType] choisi par l'utilisateur, ou `null` s'il annule.
class ReportBottomSheet extends StatelessWidget {
  const ReportBottomSheet({super.key});

  /// Affiche la feuille modale et résout le [ReportType] sélectionné.
  static Future<ReportType?> show(BuildContext context) {
    return showModalBottomSheet<ReportType>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ReportBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLowVision = AppPreferencesStore.instance.value.lowVisionMode;
    // Mode malvoyant : 2 colonnes larges ; mode normal : 4 colonnes.
    final crossAxisCount = isLowVision ? 2 : 4;
    final childAspectRatio = isLowVision ? 1.1 : 0.85;

    return Container(
      decoration: BoxDecoration(
        color: StreetPhareTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée de saisie
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color:
                        StreetPhareTheme.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Titre
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.add_alert, color: StreetPhareTheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Nouveau signalement',
                      style: TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontSize: isLowVision ? 18 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Sélectionnez la nature de l\'événement à signaler :\n'
                  'Vous pourrez ensuite placer l\'icône sur la carte.',
                  style: TextStyle(
                    color: StreetPhareTheme.textSecondary,
                    fontSize: isLowVision ? 15 : 13,
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
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: isLowVision ? 12 : 8,
                  crossAxisSpacing: isLowVision ? 12 : 8,
                  childAspectRatio: childAspectRatio,
                  children: ReportType.values
                      .map(
                        (type) => _ReportTypeTile(
                          type: type,
                          isLargeMode: isLowVision,
                          // Retourne le type sélectionné à l'appelant.
                          onTap: () => Navigator.of(context).pop(type),
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
                      side: BorderSide(color: StreetPhareTheme.textSecondary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Annuler',
                      style: TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontSize: isLowVision ? 17 : 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tuile représentant un type de signalement.
class _ReportTypeTile extends StatelessWidget {
  const _ReportTypeTile({
    required this.type,
    required this.onTap,
    this.isLargeMode = false,
  });

  final ReportType type;
  final VoidCallback onTap;

  /// Si `true`, affiche des boutons plus grands (mode malvoyant).
  final bool isLargeMode;

  @override
  Widget build(BuildContext context) {
    final iconSize = isLargeMode ? 44.0 : 32.0;
    final labelSize = isLargeMode ? 13.0 : 11.0;

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
              Icon(type.icon, color: type.color, size: iconSize),
              const SizedBox(height: 8),
              Text(
                type.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: labelSize,
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

