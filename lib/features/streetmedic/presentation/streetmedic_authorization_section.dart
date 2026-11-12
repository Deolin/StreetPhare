// lib/features/streetmedic/presentation/streetmedic_authorization_section.dart
import 'package:flutter/material.dart';

import '../domain/models/streetmedic_models.dart';
import 'streetmedic_service.dart';

/// Section « devenir street-medic » à placer dans les Paramètres.
class StreetMedicAuthorizationSection extends StatelessWidget {
  const StreetMedicAuthorizationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StreetMedic?>(
      valueListenable: StreetMedicService.instance,
      builder: (context, medic, _) {
        final service = StreetMedicService.instance;
        if (service.isAuthorized) {
          return ListTile(
            leading:
                const Icon(Icons.medical_services, color: Color(0xFF2E7D32)),
            title: const Text('Street-medic autorisé'),
            subtitle: Text(
              medic?.sharing == true
                  ? 'Partage de position actif'
                  : 'Partage de position coupé',
            ),
          );
        }
        if (medic?.status == StreetMedicStatus.pending) {
          return const ListTile(
            leading: Icon(Icons.hourglass_empty, color: Color(0xFFFFB300)),
            title: Text('Demande envoyée'),
            subtitle: Text('En attente d\'autorisation de l\'administrateur.'),
          );
        }
        return ListTile(
          leading: const Icon(Icons.medical_information_outlined),
          title: const Text('Devenir street-medic'),
          subtitle: const Text(
              'Demander l\'autorisation de partager votre position de secours.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _requestStatus(context, service),
        );
      },
    );
  }

  Future<void> _requestStatus(
      BuildContext context, StreetMedicService service) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _StreetMedicRequestDialog(),
    );
    if (!context.mounted || message == null) return;
    final res = await service.requestAuthorization(
      contactMessage: message.isNotEmpty ? message : null,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            res != null
                ? 'Demande envoyée à l\'administrateur.'
                : 'Envoi impossible (hors-ligne ?).',
          ),
        ),
      );
  }
}

class _StreetMedicRequestDialog extends StatefulWidget {
  const _StreetMedicRequestDialog();

  @override
  State<_StreetMedicRequestDialog> createState() =>
      _StreetMedicRequestDialogState();
}

class _StreetMedicRequestDialogState extends State<_StreetMedicRequestDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Devenir street-medic'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Votre demande sera transmise (chiffrée) à l\'administrateur.'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Message de contact (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}