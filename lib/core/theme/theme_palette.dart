// lib/core/theme/theme_palette.dart
//
// Palette sémantique d'un profil visuel (« skin »).
//
// Chaque skin (Default, MarsAttacks, …) expose sa propre palette de
// couleurs sémantiques. Les widgets qui référencent `StreetPhareTheme.*`
// (getters dynamiques) ou le `ColorScheme` du `ThemeData` s'adaptent
// automatiquement au skin courant.

import 'package:flutter/material.dart';

/// Couleurs sémantiques d'un skin.
@immutable
class ThemePalette {
  const ThemePalette({
    required this.primary,
    required this.accent,
    required this.danger,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
  });

  /// Couleur d'action principale (boutons, FAB, accent de marque).
  final Color primary;

  /// Couleur secondaire (éléments d'appui).
  final Color accent;

  /// Couleur de danger / alerte critique.
  final Color danger;

  /// Fond général (scaffold / carte).
  final Color background;

  /// Surface des cartes / feuilles modales.
  final Color surface;

  /// Variante de surface (profondeur, bordures).
  final Color surfaceVariant;

  /// Texte principal (contraste élevé).
  final Color textPrimary;

  /// Texte secondaire (atténué).
  final Color textSecondary;
}
