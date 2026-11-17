// lib/features/streetmedic/presentation/streetmedic_mission_panel.dart
import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/streetmedic_models.dart';
import 'streetmedic_service.dart';

/// Panneau de mission côté medic : acceptation / refus + suivi du blessé.
class StreetMedicMissionPanel extends StatelessWidget {
  const StreetMedicMissionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MedicMission?>(
      valueListenable: StreetMedicService.instance.medicMission,
      builder: (context, mission, _) {
        if (mission == null ||
            mission.status == MedicMissionStatus.completed ||
            mission.status == MedicMissionStatus.cancelled) {
          return const SizedBox.shrink();
        }
        final service = StreetMedicService.instance;
        return Material(
          color: const Color(0xFF1E272C),
          borderRadius: BorderRadius.circular(12),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: mission.isActive
                ? _activeBody(context, service, mission)
                : _pendingBody(context, service, mission),
          ),
        );
      },
    );
  }

  Widget _pendingBody(
      BuildContext context, StreetMedicService service, MedicMission m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '🚨 Mission reçue',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Blessé à ${m.injuredLatitude.toStringAsFixed(5)}, '
          '${m.injuredLongitude.toStringAsFixed(5)}'
          '${m.note.isNotEmpty ? '\n« ${m.note} »' : ''}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () => _refuse(context, service, m.id),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: StreetPhareTheme.danger),
              ),
              child: Text(
                'Refuser',
                style: TextStyle(color: StreetPhareTheme.danger),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _accept(context, service, m),
              child: const Text('Accepter'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activeBody(
      BuildContext context, StreetMedicService service, MedicMission m) {
    return Column(
      // `stretch` + bouton sans `width: double.infinity` : évite le crash
      // « BoxConstraints forces an infinite width » (ConstrainedBox → Semantics).
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_hospital, color: Color(0xFF2E7D32), size: 18),
            SizedBox(width: 6),
            Text(
              '🩺 En intervention',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Blessé : ${m.injuredLatitude.toStringAsFixed(5)}, '
          '${m.injuredLongitude.toStringAsFixed(5)}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Clôturer l\'intervention :',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _complete(context, service, m.id, 'treated'),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Victime soignée sur place'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32)),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _emergency(context, service, m),
          icon: const Icon(Icons.emergency, size: 18),
          label: const Text('Non soignable — Appeler le 112'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F)),
        ),
      ],
    );
  }

  Future<void> _accept(
      BuildContext context, StreetMedicService service, MedicMission m) async {
    await service.acceptMission(m.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
            content: Text('Mission acceptée — suivi du blessé activé.')),
      );
  }

  Future<void> _refuse(
      BuildContext context, StreetMedicService service, String id) async {
    await service.refuseMission(id);
  }

  Future<void> _complete(
      BuildContext context, StreetMedicService service, String id,
      [String outcome = 'treated']) async {
    await service.completeMission(id, outcome: outcome);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
            content:
                Text('Intervention terminée. Vous êtes à nouveau disponible.')),
      );
  }

  /// Victime non soignable sur place : demande de confirmation, clôture la
  /// mission en « urgence » (alerte transmise à l'administration) puis
  /// déclenche l'appel de détresse 112.
  Future<void> _emergency(
      BuildContext context, StreetMedicService service, MedicMission m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Appeler le 112 ?'),
        content: const Text(
            'La victime n\'est pas soignable sur place. Un appel de détresse '
            'sera lancé et l\'alerte transmise à l\'administration.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Lancer le 112'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Clôture d'abord la mission (l'alerte admin part immédiatement), puis
    // déclenche l'appel téléphonique.
    await service.completeMission(m.id, outcome: 'emergency');
    final launched = await service.launchEmergencyCall();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            launched
                ? 'Alerte transmise à l\'administration. Appel du 112 lancé.'
                : 'Alerte transmise. Composez le 112 manuellement.',
          ),
        ),
      );
  }
}
