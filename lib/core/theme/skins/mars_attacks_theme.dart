// lib/core/theme/skins/mars_attacks_theme.dart
//
// Skin thématique « Mars Attacks ».
//
// Identité visuelle : esthétique rétro-futuriste / pulp SF des années 50.
//   * Noir d'encre (fond) + vert sombre (surfaces) → ambiance « martienne ».
//   * Rouge/orange vif → accents et alertes, fort contraste.
//   * Crème / blanc cassé → texte, touche « bande dessinée ».
//   * Typographie audacieuse (graisses lourdes + espacement) pour l'effet
//     « affiche de série B ».
//
// NOTE : le rendu typographique rétro complet nécessiterait une police
// dédiée (slab/pulp). En attendant, on évoque l'esprit via FontWeight.w900
// et letterSpacing.

import 'package:flutter/material.dart';

import '../theme_palette.dart';

/// Thème et palette du skin « Mars Attacks ».
class MarsAttacksTheme {
  MarsAttacksTheme._();

  // ── Palette « Mars Attacks » (rétro-pulp / SF vintage) ──────────────────
  static const Color inkBlack = Color(0xFF222222); // noir profond (fond sombre)
  static const Color deepGreenSurface = Color(0xFF244131); // vert sombre d'encre
  static const Color deepGreenVariant = Color(0xFF1B3326); // vert très sombre
  static const Color alienGreen = Color(0xFF4A7C5C); // vert clair dérivé (accent)
  static const Color vividRed = Color(0xFFCB633A); // rouge/orange vif d'alerte
  static const Color cream = Color(0xFFEEEDDE); // crème / blanc cassé (texte)
  static const Color creamMuted = Color(0xFFC4C1AF); // crème atténué

  // Variante claire (« papier crème »).
  static const Color creamPaper = Color(0xFFEEEDDE);
  static const Color creamSurface = Color(0xFFF6F5EA);
  static const Color inkText = Color(0xFF222222);
  static const Color inkTextMuted = Color(0xFF57544A);
  static const Color deepGreen = Color(0xFF244131);

  /// Palette sémantique du skin (utilisée par les getters dynamiques).
  static const ThemePalette palette = ThemePalette(
    primary: vividRed, // #CB633A — FAB « New Report » & actions (alerte)
    accent: deepGreenSurface, // #244131 — vert sombre d'encre (dominant)
    danger: vividRed, // #CB633A — alertes
    background: inkBlack, // #222222
    surface: deepGreenSurface, // #244131
    surfaceVariant: deepGreenVariant,
    textPrimary: cream, // #EEEDDE
    textSecondary: creamMuted,
  );

  // ── Thème sombre (principal) ────────────────────────────────────────────
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: inkBlack,
      colorScheme: const ColorScheme.dark(
        primary: vividRed,
        onPrimary: Colors.white,
        secondary: deepGreenSurface,
        onSecondary: cream,
        tertiary: alienGreen,
        surface: deepGreenSurface,
        onSurface: cream,
        error: vividRed,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: cream),
        titleTextStyle: TextStyle(
          color: cream,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: vividRed,
        foregroundColor: Colors.white,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: deepGreenVariant,
        selectedColor: alienGreen,
        side: BorderSide(color: alienGreen),
        labelStyle: TextStyle(color: cream, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: deepGreenSurface,
        contentTextStyle: TextStyle(color: cream, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: cream,
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
        headlineLarge: TextStyle(
          color: cream,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
        headlineMedium: TextStyle(
          color: cream,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
        titleMedium: TextStyle(
          color: cream,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: cream, fontSize: 16),
        bodyMedium: TextStyle(color: creamMuted, fontSize: 14),
        labelLarge: TextStyle(
          color: cream,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: deepGreenSurface,
        modalBackgroundColor: deepGreenSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  // ── Thème clair (« papier crème ») ──────────────────────────────────────
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: creamPaper,
      colorScheme: const ColorScheme.light(
        primary: deepGreen,
        onPrimary: Colors.white,
        secondary: vividRed,
        onSecondary: Colors.white,
        tertiary: alienGreen,
        surface: creamSurface,
        onSurface: inkText,
        error: vividRed,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: inkText),
        titleTextStyle: TextStyle(
          color: inkText,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: vividRed,
        foregroundColor: Colors.white,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: inkText,
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
        headlineLarge: TextStyle(
          color: inkText,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
        headlineMedium: TextStyle(
          color: inkText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: inkText,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: inkText, fontSize: 16),
        bodyMedium: TextStyle(color: inkTextMuted, fontSize: 14),
        labelLarge: TextStyle(
          color: inkText,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: creamSurface,
        modalBackgroundColor: creamSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
