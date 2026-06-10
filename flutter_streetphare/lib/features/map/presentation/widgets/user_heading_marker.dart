// lib/features/map/presentation/widgets/user_heading_marker.dart
//
// Marqueur directionnel de l'utilisateur pour la carte FlutterMap.
//
// Remplace le point GPS statique par une flèche orientée selon le cap
// de déplacement (heading) de l'utilisateur en temps réel.
//
// Paramètres :
//   • heading  — cap en degrés (0° = Nord, 90° = Est, …), tel que
//                renvoyé par `Position.heading` de Geolocator.
//   • accuracy — précision GPS en mètres (utilisée pour le halo).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/streetphare_theme.dart';

/// Widget réutilisable affichant la position de l'utilisateur sous
/// la forme d'une flèche orientée selon son cap de déplacement.
///
/// À insérer dans un [Marker] de [MarkerLayer] dans [FlutterMap].
class UserHeadingMarker extends StatelessWidget {
  const UserHeadingMarker({
    super.key,
    required this.heading,
    this.accuracy = 0.0,
  });

  /// Cap de l'utilisateur en degrés (0 = Nord, sens horaire).
  final double heading;

  /// Précision GPS en mètres (pour le rayon du halo d'imprécision).
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    // Conversion degrés → radians pour Transform.rotate.
    // L'icône Icons.navigation pointe vers le haut (Nord) par défaut,
    // donc aucune compensation d'angle n'est nécessaire.
    final angleRad = heading * math.pi / 180.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // ── Halo d'imprécision GPS ────────────────────────────────
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: StreetPhareTheme.primary.withValues(alpha: 0.12),
            border: Border.all(
              color: StreetPhareTheme.primary.withValues(alpha: 0.30),
              width: 1,
            ),
          ),
        ),

        // ── Ombre portée de la flèche ─────────────────────────────
        Transform.rotate(
          angle: angleRad,
          child: Icon(
            Icons.navigation,
            color: Colors.black.withValues(alpha: 0.25),
            size: 30,
          ),
        ),

        // ── Flèche directionnelle orientée ────────────────────────
        Transform.rotate(
          angle: angleRad,
          child: const Icon(
            Icons.navigation,
            color: StreetPhareTheme.primary,
            size: 26,
          ),
        ),

        // ── Point central de précision ───────────────────────────
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
