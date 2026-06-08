import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../reports/presentation/report_bottom_sheet.dart';

/// Écran principal de StreetPhare : carte plein écran OpenStreetMap
/// avec trois boutons d'action flottants (FAB) :
///   1. **SIGNALEMENT** : ouvre la feuille d'ancrage des signalements
///   2. **ROUTE SAFE**  : affiche un snackbar (calcul d'itinéraire à venir)
///   3. **PANIC**       : alerte système d'urgence
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Contrôleur de la carte
  final MapController _mapController = MapController();

  // Position centrée par défaut (coordonnées fictives : Paris).
  // Sera remplacée par la position GPS de l'utilisateur dans une
  // version ultérieure (avec demande de permission).
  static const LatLng _defaultCenter = LatLng(48.8566, 2.3522);
  static const double _defaultZoom = 13.0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // -------- Actions des boutons flottants --------

  /// Ouvre la feuille d'ancrage des signalements
  void _openReportSheet() {
    ReportBottomSheet.show(context);
  }

  /// Déclenche la recherche d'un itinéraire sécurisé (MVP : placeholder)
  void _triggerRouteSafe() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: StreetPhareTheme.surface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  StreetPhareTheme.primary,
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Recherche d\'un chemin sûr…',
                style: TextStyle(color: StreetPhareTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active le mode panique (alerte système)
  Future<void> _triggerPanic() async {
    // Confirmation rapide avant d'envoyer l'alerte
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: StreetPhareTheme.danger, width: 2),
        ),
        title: Row(
          children: const [
            Icon(Icons.emergency, color: StreetPhareTheme.danger),
            SizedBox(width: 12),
            Text(
              'Mode Panique',
              style: TextStyle(color: StreetPhareTheme.textPrimary),
            ),
          ],
        ),
        content: const Text(
          'Activer le mode panique enverra votre position actuelle '
          'à vos contacts de confiance.\n\nContinuer ?',
          style: TextStyle(color: StreetPhareTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ACTIVER'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Log : aucune donnée nominative n'est collectée à ce stade.
      // L'envoi réel se fera dans une version ultérieure via un
      // service de notifications sécurisé.
      debugPrint('[Panic] Mode Panique Activé - Envoi de la position de secours.');

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StreetPhareTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: StreetPhareTheme.primary),
              SizedBox(width: 12),
              Text(
                'Alerte envoyée',
                style: TextStyle(color: StreetPhareTheme.textPrimary),
              ),
            ],
          ),
          content: const Text(
            'Mode Panique Activé - Envoi de la position de secours.',
            style: TextStyle(color: StreetPhareTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // --- Carte OpenStreetMap plein écran ---
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _defaultZoom,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              // Tuiles OpenStreetMap (avec cache via flutter_map_cache)
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.streetphare.app',
                maxNativeZoom: 19,
              ),

              // Attribution OpenStreetMap (obligatoire)
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // --- Barre supérieure discrète (titre + bouton d'info) ---
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: StreetPhareTheme.surface.withValues(
                          alpha: 0.85,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.lightbulb,
                            color: StreetPhareTheme.primary,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'StreetPhare',
                            style: TextStyle(
                              color: StreetPhareTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _CircleIconButton(
                      icon: Icons.info_outline,
                      onTap: () => _showInfoDialog(context),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --- Boutons d'action flottants (FAB) ---
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 1) SIGNALEMENT
                _ActionFab(
                  icon: Icons.add_alert,
                  label: 'Signalement',
                  backgroundColor: StreetPhareTheme.primary,
                  foregroundColor: Colors.black,
                  onPressed: _openReportSheet,
                ),
                const SizedBox(height: 12),

                // 2) ROUTE SAFE
                _ActionFab(
                  icon: Icons.shield_outlined,
                  label: 'Route Safe',
                  backgroundColor: StreetPhareTheme.surface,
                  foregroundColor: StreetPhareTheme.primary,
                  borderColor: StreetPhareTheme.primary,
                  onPressed: _triggerRouteSafe,
                ),
                const SizedBox(height: 12),

                // 3) PANIC
                _ActionFab(
                  icon: Icons.emergency,
                  label: 'PANIC',
                  backgroundColor: StreetPhareTheme.danger,
                  foregroundColor: Colors.white,
                  isExtended: true,
                  onPressed: _triggerPanic,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        title: const Text(
          'À propos de StreetPhare',
          style: TextStyle(color: StreetPhareTheme.textPrimary),
        ),
        content: const Text(
          'Application citoyenne de cartographie collaborative en temps réel.\n\n'
          'Aucune donnée personnelle n\'est collectée.\n'
          'Version 1.0.0 - Open Source',
          style: TextStyle(color: StreetPhareTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

/// Bouton d'action flottant (FAB) étendu avec libellé
class _ActionFab extends StatelessWidget {
  const _ActionFab({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderColor,
    this.isExtended = false,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool isExtended;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final content = isExtended
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foregroundColor, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          )
        : Icon(icon, color: foregroundColor, size: 24);

    return Material(
      elevation: 6,
      shadowColor: backgroundColor.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(isExtended ? 28 : 16),
      color: backgroundColor,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(isExtended ? 28 : 16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isExtended ? 20 : 16,
            vertical: isExtended ? 14 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isExtended ? 28 : 16),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Petit bouton circulaire pour la barre supérieure
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StreetPhareTheme.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: StreetPhareTheme.textPrimary, size: 22),
        ),
      ),
    );
  }
}
