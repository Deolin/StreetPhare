// lib/features/reports/presentation/report_bottom_sheet.dart
//
// Feuille d'ancrage de signalement — v2.1
//
// Nouvelles fonctionnalités v2.1 :
//   1. Callback [onLocalReport] : appelé IMMÉDIATEMENT après la création
//      locale du signalement pour que MapScreen affiche un marqueur instantané.
//   2. Mode Malvoyant : si `lowVisionMode` est actif dans les préférences,
//      la grille passe à 2 colonnes (grands boutons tactiles).
//   3. Le réseau P2P diffuse le signalement, visible des autres après ≥3 votes.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../database/alert_model.dart';
import '../../../network/network_coordinator.dart';
import '../../settings/data/app_preferences_store.dart';
import '../domain/models/report_type.dart';

/// Type du callback de signalement local immédiat.
typedef LocalReportCallback = void Function(LatLng position, AlertType type);

/// Feuille d'ancrage (Bottom Sheet) présentant les différents types
/// de signalements citoyens disponibles.
///
/// L'utilisateur peut :
///   1. Choisir un type de signalement (Barrages, Nasses, etc.)
///   2. Le système capture automatiquement la position GPS.
///   3. Une `Alert` est créée, persistée dans Hive (TTL 24h) et broadcastée.
///   4. [onLocalReport] est appelé IMMÉDIATEMENT → marqueur local sur la carte.
///   5. Le signalement est visible des autres pairs dès qu'il atteint ≥3 votes.
class ReportBottomSheet extends StatelessWidget {
  const ReportBottomSheet({
    super.key,
    this.onLocalReport,
  });

  /// Callback déclenché dès que le signalement est créé localement.
  /// Permet à MapScreen d'afficher immédiatement un marqueur provisoire.
  final LocalReportCallback? onLocalReport;

  /// Affiche la feuille d'ancrage modale.
  static Future<void> show(
    BuildContext context, {
    LocalReportCallback? onLocalReport,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReportBottomSheet(onLocalReport: onLocalReport),
    );
  }

  /// Mapping entre un `ReportType` (UI) et un `AlertType` (base de données).
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
        return AlertType.rassemblement;
      case ReportType.zoneSafe:
        return AlertType.zoneSafe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLowVision =
        AppPreferencesStore.instance.value.lowVisionMode;
    // Mode malvoyant : 2 colonnes larges ; mode normal : 4 colonnes.
    final crossAxisCount = isLowVision ? 2 : 4;
    final childAspectRatio = isLowVision ? 1.1 : 0.85;

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.add_alert, color: StreetPhareTheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Nouveau signalement',
                    style: TextStyle(
                      color: StreetPhareTheme.textPrimary,
                      fontSize: isLowVision ? 22 : 18,
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
                'Votre position GPS sera capturée automatiquement.',
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
                      color: StreetPhareTheme.textSecondary
                          .withValues(alpha: 0.3),
                    ),
                    padding: EdgeInsets.symmetric(
                        vertical: isLowVision ? 18 : 14),
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
    );
  }

  /// Pipeline de signalement :
  ///   1. Ferme la feuille.
  ///   2. Capture la position GPS.
  ///   3. Appelle [onLocalReport] IMMÉDIATEMENT → marqueur local sur la carte.
  ///   4. Crée l'alerte (Hive + broadcast réseau).
  ///   5. Snackbar de confirmation.
  Future<void> _onTypeSelected(
    BuildContext context,
    ReportType type,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

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

    final alertType = _alertTypeFor(type);
    final position = LatLng(pos.latitude, pos.longitude);

    // ── FEEDBACK IMMÉDIAT : appelle le callback AVANT la persistance réseau ──
    // Le marqueur local apparaît instantanément sur la carte de l'émetteur.
    onLocalReport?.call(position, alertType);

    // ── Création de l'alerte (persistance Hive + broadcast P2P) ──
    try {
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
        '✅ Signalement "${type.label}" enregistré.\n'
        'Visible des autres pairs dès 3 confirmations.',
        icon: type.icon,
        backgroundColor: type.color,
        foregroundColor: Colors.white,
      );
    } catch (e) {
      debugPrint('[Report] erreur createAlert: $e');
      _showSnackBar(
        messenger,
        'Erreur lors de l\'enregistrement : $e',
        icon: Icons.error_outline,
        backgroundColor: StreetPhareTheme.danger,
        foregroundColor: Colors.white,
      );
    }
  }

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
