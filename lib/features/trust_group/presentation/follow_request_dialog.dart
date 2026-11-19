// lib/features/trust_group/presentation/follow_request_dialog.dart
//
// Boîtes de dialogue de consentement pour les demandes de suivi :
//   1. Confirmation « X souhaite suivre ta position » (Accepter / Refuser).
//   2. Proposition de « suivre en retour » (Suivre en retour / Plus tard).

import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/follow_request.dart';
import 'trust_group_service.dart';

/// Affiche la confirmation d'une demande de suivi puis, en cas d'acceptation,
/// propose de suivre l'autre personne en retour.
Future<void> showFollowRequestDialog(
  BuildContext context,
  FollowRequest request,
) async {
  final service = TrustGroupService.instance;
  final onSurface = Theme.of(context).colorScheme.onSurface;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.person_search, color: StreetPhareTheme.primary, size: 24),
          const SizedBox(width: 10),
          const Text('Demande de suivi'),
        ],
      ),
      content: Text(
        '« ${request.fromAlias} » souhaite suivre votre position sur sa carte.\n\n'
        'En acceptant, cette personne verra votre position tant que vous '
        'partagerez votre position.',
        style: TextStyle(color: onSurface.withValues(alpha: 0.8), fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Refuser'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: StreetPhareTheme.primary,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Accepter'),
        ),
      ],
    ),
  );

  if (accepted != true) {
    service.declineFollowRequest(request);
    return;
  }

  if (!context.mounted) return;

  final followBack = await showFollowBackOffer(context, request);
  await service.acceptFollowRequest(request, followBack: followBack == true);
}

/// Affiche uniquement la proposition de « suivre en retour ».
/// Retourne `true` si l'utilisateur choisit de suivre en retour,
/// `false`/`null` sinon (dont fermeture).
Future<bool?> showFollowBackOffer(
  BuildContext context,
  FollowRequest request,
) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      title: const Text('Suivre en retour ?'),
      content: Text(
        'Voulez-vous suivre « ${request.fromAlias} » en retour pour voir '
        'aussi sa position sur votre carte ?',
        style: TextStyle(color: onSurface.withValues(alpha: 0.8), fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Plus tard'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: StreetPhareTheme.primary,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Suivre en retour'),
        ),
      ],
    ),
  );
}

