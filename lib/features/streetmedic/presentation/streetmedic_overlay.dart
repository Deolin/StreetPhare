// lib/features/streetmedic/presentation/streetmedic_overlay.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/streetmedic_models.dart';
import 'streetmedic_mission_panel.dart';
import 'streetmedic_service.dart';

/// Marqueur « croix blanche sur fond rouge » (vert en mode « alerté »).
class StreetMedicMarkerIcon extends StatelessWidget {
  const StreetMedicMarkerIcon({super.key, this.alerted = false});

  final bool alerted;

  @override
  Widget build(BuildContext context) {
    final color = alerted ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        alerted ? Icons.local_hospital : Icons.add,
        color: Colors.white,
        size: alerted ? 19 : 24,
      ),
    );
  }
}

/// Overlay placé sur la carte : indicateur « tracé » + partage + appel.
class StreetMedicOverlay extends StatelessWidget {
  const StreetMedicOverlay({
    super.key,
    this.userPosition,
    this.onPanic,
    this.panicLabel,
  });

  final LatLng? userPosition;

  /// Déclenche le mode PANIC (fourni par l'écran carte).
  final VoidCallback? onPanic;

  /// Libellé localisé du bouton PANIC.
  final String? panicLabel;

  @override
  Widget build(BuildContext context) {
    // `right` est nécessaire pour borner la largeur du panneau de mission :
    // sans lui, le `Positioned` laisse une largeur non bornée et le
    // `CrossAxisAlignment.stretch` de `StreetMedicMissionPanel` provoque un
    // crash de layout (« RenderBox was not laid out »).
    return Positioned(
      left: 12,
      right: 12,
      bottom: 32,
      child: ValueListenableBuilder<StreetMedic?>(
        valueListenable: StreetMedicService.instance,
        builder: (context, medic, _) {
          final service = StreetMedicService.instance;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (service.isAuthorized) ...[
                const StreetMedicMissionPanel(),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _callButton(context, service),
                  if (onPanic != null) _panicButton(),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _callButton(BuildContext context, StreetMedicService service) {
    return ValueListenableBuilder<MedicMission?>(
      valueListenable: service.myCallNotifier,
      builder: (context, call, _) {
        final active = service.hasActiveCall;
        return Material(
          color: active ? const Color(0xFF546E7A) : const Color(0xFFD32F2F),
          borderRadius: BorderRadius.circular(24),
          elevation: 4,
          child: InkWell(
            onTap: () => active
                ? _cancelCall(context, service)
                : _callMedic(context, service),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active ? Icons.close : Icons.local_hospital,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active ? 'Annuler l\'appel' : 'Appeler un street-medic',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bouton PANIC, placé à droite du bouton « Appeler un street-medic ».
  Widget _panicButton() {
    return Material(
      color: StreetPhareTheme.danger,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      child: InkWell(
        onTap: onPanic,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emergency, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                panicLabel ?? 'PANIC',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callMedic(
      BuildContext context, StreetMedicService service) async {
    if (userPosition == null) {
      _snack(context, 'Position indisponible. Activez le GPS.');
      return;
    }
    final ok = await _confirm(
      context,
      title: 'Appeler un street-medic',
      message:
          '⚠️ À n\'utiliser qu\'en cas de réel besoin de secours.\n\n'
          'Un faux signalement mobilise un street-medic pour rien et peut '
          'retarder une vraie intervention.\n\n'
          'Votre position sera signalée au street-medic le plus proche.',
    );
    if (ok != true || !context.mounted) return;
    final mission = await service.callNearestMedic(
      lat: userPosition!.latitude,
      lng: userPosition!.longitude,
    );
    if (!context.mounted) return;
    _snack(
      context,
      mission == null
          ? 'Aucun street-medic disponible à proximité.'
          : 'Street-medic alerté. Gardez votre téléphone à portée.',
    );
  }

  /// Annule l'appel en cours afin d'éviter de mobiliser un medic pour rien.
  Future<void> _cancelCall(
      BuildContext context, StreetMedicService service) async {
    final ok = await _confirm(
      context,
      title: 'Annuler l\'appel au street-medic',
      message:
          'Le street-medic sera informé que vous n\'avez plus besoin d\'aide. '
          'Annuler l\'appel évite de mobiliser un secouriste inutilement.',
    );
    if (ok != true || !context.mounted) return;
    final success = await service.cancelMyCall();
    if (!context.mounted) return;
    _snack(
      context,
      success
          ? 'Appel annulé.'
          : 'Impossible d\'annuler l\'appel (hors-ligne ?).',
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Bouton « Partager ma position » du street-medic, repositionné en haut de la
/// carte : sous le titre StreetPhare, au-dessus du bouton de signalement de bug.
class StreetMedicSharingToggle extends StatelessWidget {
  const StreetMedicSharingToggle({super.key, this.userPosition});

  final LatLng? userPosition;

  @override
  Widget build(BuildContext context) {
    // Positionné SOUS la barre supérieure (titre + compteur de pairs) dont la
    // hauteur dépend de la SafeArea (encoche / barre de statut Android 15+).
    // On décale donc le bouton de la hauteur de l'encoche + une marge fixe,
    // au lieu d'un `top: 72` qui chevauchait le titre sur certains appareils.
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 68,
      left: 12,
      child: ValueListenableBuilder<StreetMedic?>(
        valueListenable: StreetMedicService.instance,
        builder: (context, medic, _) {
          final service = StreetMedicService.instance;
          if (!service.isAuthorized) return const SizedBox.shrink();
          final sharing = medic?.sharing ?? false;
          return _medicPanel(context, service, sharing);
        },
      ),
    );
  }

  Widget _medicPanel(
      BuildContext context, StreetMedicService service, bool sharing) {
    return Material(
      color: const Color(0xFF1E272C),
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sharing ? const Color(0xFF2E7D32) : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sharing ? '🩺 Tracé' : 'Partage inactif',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _toggleSharing(context, service, sharing),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: sharing
                      ? StreetPhareTheme.danger
                      : StreetPhareTheme.primary,
                ),
              ),
              child: Text(
                sharing ? 'Arrêter' : 'Partager',
                style: TextStyle(
                  color: sharing
                      ? StreetPhareTheme.danger
                      : StreetPhareTheme.primary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSharing(
      BuildContext context, StreetMedicService service, bool sharing) async {
    if (sharing) {
      await service.stopSharing();
      return;
    }
    final ok = await _confirm(context,
        title: 'Partager ma position',
        message:
            'Votre position sera visible par tous les participants tant que le partage est actif.');
    if (ok != true) return;
    await service.startSharing(
      lat: userPosition?.latitude,
      lng: userPosition?.longitude,
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}
