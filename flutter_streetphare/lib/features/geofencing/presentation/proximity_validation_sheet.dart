// lib/features/geofencing/presentation/proximity_validation_sheet.dart
//
// Feuille d'ancrage (BottomSheet) affichée à l'utilisateur quand
// il entre dans un rayon de proximité d'un signalement actif.
//
// Contenu :
//   * Type de danger détecté + icône
//   * Distance à laquelle il a été détecté
//   * Deux boutons d'action : [OUI] (valider, allonge le TTL)
//     et [NON] (invalider, supprime le marqueur).
//
// Cette feuille est affichée par `MapScreen` à chaque `GeofenceEvent`
// filtré (anti-spam 5 min géré par `ProximityValidationService`).

import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../database/alert_model.dart';
import '../../../database/alert_ttl_policy.dart';
import '../domain/models/geofence_event.dart';
import 'proximity_validation_service.dart';

class ProximityValidationSheet extends StatelessWidget {
  const ProximityValidationSheet({super.key, required this.event});

  final GeofenceEvent event;

  /// Affiche la feuille d'ancrage modale et renvoie le vote :
  ///   * `true`  → OUI
  ///   * `false` → NON
  ///   * `null`  → dismiss / ignoré
  static Future<bool?> show(BuildContext context, GeofenceEvent event) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProximityValidationSheet(event: event),
    );
  }

  String _labelForType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return 'un barrage';
      case AlertType.nasse:
        return 'une nasse';
      case AlertType.controle:
        return 'un contrôle de police';
      case AlertType.accident:
        return 'un danger / accident';
      case AlertType.manifestation:
        return 'un groupe de casseurs';
      case AlertType.zoneSafe:
        return 'une zone safe';
      case AlertType.panicCollectif:
        return 'une alerte panic collective';
      case AlertType.autre:
        return 'un danger';
    }
  }

  IconData _iconForType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return Icons.block;
      case AlertType.nasse:
        return Icons.crop_square;
      case AlertType.controle:
        return Icons.local_police;
      case AlertType.accident:
        return Icons.warning_amber;
      case AlertType.manifestation:
        return Icons.groups;
      case AlertType.zoneSafe:
        return Icons.shield_outlined;
      case AlertType.panicCollectif:
        return Icons.emergency;
      case AlertType.autre:
        return Icons.error_outline;
    }
  }

  Color _colorForType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return const Color(0xFFE53935);
      case AlertType.nasse:
        return const Color(0xFFFFB300);
      case AlertType.controle:
        return const Color(0xFF3F51B5);
      case AlertType.accident:
        return const Color(0xFFFF6F00);
      case AlertType.manifestation:
        return const Color(0xFF7B1FA2);
      case AlertType.zoneSafe:
        return const Color(0xFF2E7D32);
      case AlertType.panicCollectif:
        return const Color(0xFFE53935);
      case AlertType.autre:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = event.alert;
    final color = _colorForType(alert.type);
    final expiry = AlertTtlPolicy.expiryInstant(alert);
    final remaining = expiry.difference(DateTime.now().toUtc());

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
            // Poignée
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: StreetPhareTheme.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Icône
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(_iconForType(alert.type), color: color, size: 32),
            ),
            const SizedBox(height: 12),
            // Question principale
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${_labelForType(alert.type)} est signalé${alert.type == AlertType.barrage ? '' : 'e'} ici, est-il toujours là ?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Détecté à ${event.distanceMeters.toStringAsFixed(0)} m. '
                'Disparaît dans ${remaining.inMinutes + 1} min.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: StreetPhareTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Boutons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close,
                          color: StreetPhareTheme.danger),
                      label: const Text(
                        'NON',
                        style: TextStyle(
                          color: StreetPhareTheme.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: StreetPhareTheme.danger,
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check, color: Colors.black),
                      label: const Text(
                        'OUI',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StreetPhareTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Plus tard',
                style: TextStyle(color: StreetPhareTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper qui combine l'affichage de la feuille et le traitement
/// du vote via `ProximityValidationService`. Retourne un
/// `Future<bool?>` (`true` = OUI, `false` = NON, `null` = ignoré).
Future<bool?> showAndProcessProximityVote(
  BuildContext context,
  dynamic event,
) async {
  final result = await ProximityValidationSheet.show(
    context,
    event,
  );
  if (result == true) {
    await ProximityValidationService.instance.castYes(event);
    return true;
  } else if (result == false) {
    await ProximityValidationService.instance.castNo(event);
    return false;
  }
  return null;
}
