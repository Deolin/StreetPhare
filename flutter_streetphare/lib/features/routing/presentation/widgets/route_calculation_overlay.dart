// lib/features/routing/presentation/widgets/route_calculation_overlay.dart
//
// Overlay de chargement affiché pendant le calcul d'itinéraire OsmAnd.
//
// Utilisation :
//   RouteCalculationOverlay.show(context, message: 'Calcul en cours…');
//   // ... attendre le calcul ...
//   RouteCalculationOverlay.hide(context);
//
// Ou avec un Future :
//   final result = await RouteCalculationOverlay.wrap(
//     context,
//     future: osmAndService.computeRoutes(...),
//     message: 'Calcul de l\'itinéraire piéton sécurisé via OsmAnd...',
//   );

import 'package:flutter/material.dart';

import '../../../../core/theme/streetphare_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RouteCalculationOverlay
// ══════════════════════════════════════════════════════════════════════════════

/// Overlay modal bloquant affiché pendant le calcul d'un itinéraire.
///
/// Il est intentionnellement NON-dismissible pour forcer l'utilisateur
/// à attendre la fin du calcul avant d'interagir avec la carte.
class RouteCalculationOverlay extends StatelessWidget {
  const RouteCalculationOverlay({
    super.key,
    required this.message,
    this.subMessage,
  });

  final String message;
  final String? subMessage;

  // ── API statique ───────────────────────────────────────────────────────────

  /// Affiche l'overlay sur [context].
  ///
  /// ⚠️ Appeler impérativement [hide] ou [wrap] pour le retirer.
  static void show(
    BuildContext context, {
    String message = 'Calcul de l\'itinéraire piéton sécurisé via OsmAnd…',
    String? subMessage,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => RouteCalculationOverlay(
        message: message,
        subMessage: subMessage,
      ),
    );
  }

  /// Ferme l'overlay.
  ///
  /// Doit être appelé après [show]. Sans effet si aucun dialog n'est ouvert.
  static void hide(BuildContext context) {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Affiche l'overlay, exécute [future], puis le ferme automatiquement.
  ///
  /// Retourne le résultat de [future] ou `null` en cas d'erreur.
  ///
  /// Exemple :
  /// ```dart
  /// final result = await RouteCalculationOverlay.wrap(
  ///   context,
  ///   future: osmAndService.computeRoutes(start: a, end: b, filters: f),
  ///   message: 'Calcul de la route piétonne via OsmAnd...',
  /// );
  /// ```
  static Future<T?> wrap<T>(
    BuildContext context, {
    required Future<T> future,
    String message = 'Calcul de l\'itinéraire piéton sécurisé via OsmAnd…',
    String? subMessage,
  }) async {
    show(context, message: message, subMessage: subMessage);
    try {
      final result = await future;
      if (context.mounted) hide(context);
      return result;
    } catch (e) {
      if (context.mounted) hide(context);
      rethrow;
    }
  }

  // ── Widget ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: StreetPhareTheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icône OsmAnd ────────────────────────────────────────────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: StreetPhareTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.map_outlined,
                color: StreetPhareTheme.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),

            // ── Spinner ─────────────────────────────────────────────────────
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  StreetPhareTheme.primary,
                ),
                backgroundColor:
                    StreetPhareTheme.primary.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 20),

            // ── Message principal ───────────────────────────────────────────
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: StreetPhareTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),

            // ── Sous-message optionnel ──────────────────────────────────────
            if (subMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: StreetPhareTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Label discret ───────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.directions_walk,
                  color: StreetPhareTheme.textSecondary,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'Profil piéton · OpenStreetMap',
                  style: TextStyle(
                    color: StreetPhareTheme.textSecondary.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OsmAndNotInstalledDialog
// ══════════════════════════════════════════════════════════════════════════════

/// Dialog affiché lorsqu'OsmAnd n'est pas installé sur l'appareil.
///
/// Propose deux options :
///   1. Installer OsmAnd (Play Store / F-Droid)
///   2. Utiliser le routage OSRM en ligne (fallback web)
class OsmAndNotInstalledDialog extends StatelessWidget {
  const OsmAndNotInstalledDialog({
    super.key,
    required this.onInstall,
    required this.onUseFallback,
  });

  final VoidCallback onInstall;
  final VoidCallback onUseFallback;

  /// Affiche le dialog OsmAnd non installé.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onInstall,
    required VoidCallback onUseFallback,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => OsmAndNotInstalledDialog(
        onInstall: onInstall,
        onUseFallback: onUseFallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StreetPhareTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Row(
        children: [
          Icon(Icons.map, color: StreetPhareTheme.primary, size: 24),
          SizedBox(width: 8),
          Text(
            'OsmAnd non installé',
            style: TextStyle(
              color: StreetPhareTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: const Text(
        'Pour la navigation piétonne guidée vocalement (idéal malvoyants), '
        'OsmAnd doit être installé.\n\n'
        'Sinon, StreetPhare peut calculer l\'itinéraire via OpenStreetMap '
        'et l\'afficher directement sur la carte.',
        style: TextStyle(
          color: StreetPhareTheme.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        // ── Option 1 : Fallback interne ────────────────────────────────────
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onUseFallback();
          },
          child: const Text(
            'Utiliser OSM en ligne',
            style: TextStyle(color: StreetPhareTheme.textSecondary),
          ),
        ),

        // ── Option 2 : Installer OsmAnd ────────────────────────────────────
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onInstall();
          },
          icon: const Icon(Icons.download, color: Colors.black, size: 18),
          label: const Text(
            'Installer OsmAnd',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: StreetPhareTheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
