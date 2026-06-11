// lib/features/map/presentation/widgets/user_heading_marker.dart
//
// Marqueur directionnel de l'utilisateur pour la carte FlutterMap.
//
// Gestion Dynamique du Curseur :
//   - Si [showArrow] est vrai ET [heading] est valide → flèche directionnelle.
//   - Sinon → point de positionnement circulaire classique.
//
// La décision "showArrow" est calculée par l'appelant (MapScreen) en
// fonction de la vitesse GPS et de la disponibilité du cap :
//   * heading >= 0 ET (speed > 0 OU capteur boussole actif) → flèche
//   * sinon → point circulaire

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/streetphare_theme.dart';

/// Widget réutilisable affichant la position de l'utilisateur.
///
/// Mode FLÈCHE (showArrow = true) :
///   Flèche directionnelle orientée selon [heading] (degrés, 0 = Nord).
///
/// Mode POINT (showArrow = false) :
///   Point circulaire classique avec halo d'imprécision GPS.
///
/// À insérer dans un [Marker] de [MarkerLayer] dans [FlutterMap].
class UserHeadingMarker extends StatelessWidget {
  const UserHeadingMarker({
    super.key,
    required this.heading,
    this.accuracy = 0.0,
    this.showArrow = true,
  });

  /// Cap de l'utilisateur en degrés (0 = Nord, sens horaire).
  final double heading;

  /// Précision GPS en mètres (pour le rayon du halo d'imprécision).
  final double accuracy;

  /// Si `true`, affiche une flèche directionnelle orientée selon [heading].
  /// Si `false`, affiche un point circulaire (GPS valide mais cap inconnu).
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return showArrow ? _buildArrowMarker() : _buildDotMarker();
  }

  // --------------------------------------------------------------------------
  // Mode flèche directionnelle
  // --------------------------------------------------------------------------

  Widget _buildArrowMarker() {
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

  // --------------------------------------------------------------------------
  // Mode point circulaire (GPS valide, cap indisponible)
  // --------------------------------------------------------------------------

  Widget _buildDotMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // ── Halo d'imprécision GPS ────────────────────────────────
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: StreetPhareTheme.primary.withValues(alpha: 0.12),
            border: Border.all(
              color: StreetPhareTheme.primary.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
        ),

        // ── Cercle extérieur blanc ────────────────────────────────
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),

        // ── Dot central coloré ────────────────────────────────────
        Container(
          width: 13,
          height: 13,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: StreetPhareTheme.primary,
          ),
        ),
      ],
    );
  }
}
