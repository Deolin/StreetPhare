import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../database/alert_model.dart';
import '../../../network/network_coordinator.dart';
import '../domain/models/report_type.dart';

/// Feuille d'ancrage (Bottom Sheet) présentant les différents types
/// de signalements citoyens disponibles.
///
/// L'utilisateur peut :
///   1. Choisir un type de signalement (Barrages, Nasses, etc.)
///   2. Le système capture **automatiquement la position GPS réelle**
///      de l'appareil À CE MOMENT PRÉCIS (latitude + longitude).
///   3. Une `Alert` signée anonymement est créée, persistée dans
///      la base Hive locale (TTL 24h) et broadcastée sur le maillage.
///   4. Le marqueur apparaît INSTANTANÉMENT sur la carte.
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

  /// Mapping entre un `ReportType` (UI) et un `AlertType` (couche
  /// métier / base de données).
  static AlertType _alertTypeFor(ReportType type) {
    switch (type) {
      case ReportType.barrages:
        return AlertType.barrage;
      case ReportType.zonesFiltrees:
        return AlertType.controle;
      case ReportType.nasses:
        return AlertType.nasse;
      case ReportType.autopompes:
        return AlertType.accident;
      case ReportType.policiers:
        return AlertType.controle;
      case ReportType.dangers:
        return AlertType.accident;
      case ReportType.groupesCasseurs:
        return AlertType.manifestation;
    }
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
                'Sélectionnez la nature de l\'événement à signaler :\n'
                'Votre position GPS sera capturée automatiquement.',
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

  /// Action déclenchée lors du choix d'un type de signalement.
  ///
  /// Pipeline :
  ///   1. Ferme la feuille d'ancrage.
  ///   2. Capture la position GPS de l'appareil.
  ///   3. Crée une `Alert` via `NetworkCoordinator.createAlert`
  ///      (qui la signe, la persiste dans Hive, la broadcast).
  ///   4. Affiche un snackbar de confirmation à l'utilisateur.
  Future<void> _onTypeSelected(
    BuildContext context,
    ReportType type,
  ) async {
    // Capture le ScaffoldMessenger AVANT les awaits pour éviter
    // tout "use_build_context_synchronously" sur context.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    // 1) Capture la position GPS de l'appareil.
    final pos = await _capturePosition();

    if (pos == null) {
      _showSnackBar(
        messenger,
        'Impossible d\'obtenir la position GPS. '
        'Activez la localisation et réessayez.',
        icon: Icons.location_off,
        backgroundColor: StreetPhareTheme.danger,
        foregroundColor: Colors.white,
      );
      return;
    }

    // 2) Crée l'alerte (signe + persiste Hive + broadcast).
    try {
      final alertType = _alertTypeFor(type);
      await NetworkCoordinator.instance.createAlert(
        type: alertType,
        latitude: pos.latitude,
        longitude: pos.longitude,
        description: type.label,
      );
      debugPrint(
        '[Report] Signalement "${type.label}" enregistré à '
        '(${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}).',
      );
      _showSnackBar(
        messenger,
        'Signalement "${type.label}" enregistré à '
        '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}.\n'
        'Merci de votre contribution citoyenne.',
        icon: type.icon,
        backgroundColor: type.color,
        foregroundColor: Colors.white,
      );
    } catch (e) {
      debugPrint('[Report] erreur createAlert: $e');
      _showSnackBar(
        messenger,
        'Erreur lors de l\'enregistrement du signalement : $e',
        icon: Icons.error_outline,
        backgroundColor: StreetPhareTheme.danger,
        foregroundColor: Colors.white,
      );
    }
  }

  /// Capture la position GPS réelle de l'appareil À CE MOMENT PRÉCIS.
  /// Reprend la même logique que dans `map_screen.dart` (factorisable
  /// dans un service dédié à terme).
  Future<Position?> _capturePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('[Report] erreur GPS : $e');
      return null;
    }
  }

  void _showSnackBar(
    ScaffoldMessengerState messenger,
    String message, {
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: foregroundColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foregroundColor),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
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
