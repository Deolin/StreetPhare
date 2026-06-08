// lib/core/theme/streetphare_theme.dart
//
// Définition des thèmes StreetPhare.
//
// Deux thèmes sont fournis :
//   * `darkTheme()` : thème "Nuit" historique. Couleurs sombres
//     optimisées pour économiser les écrans OLED (vrais noirs) et
//     rester discret la nuit.
//   * `lightTheme()` : nouveau thème clair, utilisé quand l'utilisateur
//     force le mode clair ou quand le système est en mode clair.

import 'package:flutter/material.dart';

/// Couleurs et thèmes StreetPhare.
class StreetPhareTheme {
  StreetPhareTheme._();

  // ---------------------------------------------------------------------------
  // Couleurs du thème SOMBRE ("Nuit", optimisé OLED)
  // ---------------------------------------------------------------------------
  static const Color darkBackground = Color(0xFF000000); // vrai noir OLED
  static const Color darkSurface = Color(0xFF0E1116);
  static const Color darkSurfaceVariant = Color(0xFF1A1F29);
  static const Color primary = Color(0xFFFFB300); // Ambre lampadaire
  static const Color accent = Color(0xFFFF6F00);
  static const Color danger = Color(0xFFE53935);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB0BEC5);

  // ---------------------------------------------------------------------------
  // Couleurs du thème CLAIR
  // ---------------------------------------------------------------------------
  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEEF1F5);
  static const Color lightTextPrimary = Color(0xFF101828);
  static const Color lightTextSecondary = Color(0xFF475467);

  // ---------------------------------------------------------------------------
  // Alias historiques (compat avec l'existant : `StreetPhareTheme.surface`
  // est référencé partout). On les fait pointer sur le thème sombre
  // pour préserver la rétrocompatibilité des écrans non encore
  // thémés dynamiquement.
  // ---------------------------------------------------------------------------
  static const Color background = darkBackground;
  static const Color surface = darkSurface;

  /// Couleur d'accent ambre, exposée publiquement pour les widgets
  /// qui construisent leurs propres `Container` en dehors du
  /// `ColorScheme`.
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;

  // ---------------------------------------------------------------------------
  // Construction des ThemeData
  // ---------------------------------------------------------------------------

  /// Construit le thème sombre "Nuit" de l'application.
  ///
  /// Optimisé OLED : vrai noir en `background` pour éteindre
  /// littéralement les pixels, et `surface` gris très sombre pour
  /// la profondeur des cartes/feuilles modales.
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Colors.black,
        secondary: accent,
        onSecondary: Colors.white,
        surface: darkSurface,
        onSurface: darkTextPrimary,
        error: danger,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkTextPrimary),
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: darkTextPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        headlineLarge: TextStyle(
          color: darkTextPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: TextStyle(
          color: darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: darkTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: darkTextPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: darkTextSecondary, fontSize: 14),
        labelLarge: TextStyle(
          color: darkTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        modalBackgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  /// Construit le thème clair de l'application.
  ///
  /// Utilisé quand l'utilisateur force "Mode Clair" ou que le
  /// système est en mode clair. Contraste élevé pour une lecture
  /// diurne confortable.
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        secondary: primary,
        onSecondary: Colors.black,
        surface: lightSurface,
        onSurface: lightTextPrimary,
        error: danger,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: lightTextPrimary),
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        headlineLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: TextStyle(
          color: lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: lightTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: lightTextPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: lightTextSecondary, fontSize: 14),
        labelLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        modalBackgroundColor: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
