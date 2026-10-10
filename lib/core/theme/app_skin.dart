// lib/core/theme/app_skin.dart
//
// Profils visuels (« skins ») disponibles dans StreetPhare.
//
// Chaque skin expose une palette sémantique (`ThemePalette`) ainsi que
// ses deux `ThemeData` (clair & sombre). Le `SkinController` sélectionne
// le skin courant, et les getters dynamiques de `StreetPhareTheme`
// (primary, danger, surface…) reflètent la palette active.

import 'package:flutter/material.dart';

import '../i18n/app_locale.dart';
import 'skins/mars_attacks_theme.dart';
import 'streetphare_theme.dart';
import 'theme_palette.dart';

/// Identité visuelle de l'application.
enum AppSkin {
  /// Thème StreetPhare classique (ambre / nuit OLED).
  defaultSkin('default'),

  /// Skin rétro-futuriste « Mars Attacks ».
  marsAttacks('mars_attacks');

  const AppSkin(this.id);

  /// Identifiant sérialisé dans SharedPreferences.
  final String id;

  /// Libellé affiché dans l'UI des paramètres.
  String get label {
    final s = AppLocale.instance.strings;
    return switch (this) {
      AppSkin.defaultSkin => s.skinDefaultLabel,
      AppSkin.marsAttacks => s.skinMarsAttacksLabel,
    };
  }

  /// Sous-titre descriptif affiché dans l'UI des paramètres.
  String get subtitle {
    final s = AppLocale.instance.strings;
    return switch (this) {
      AppSkin.defaultSkin => s.skinDefaultSubtitle,
      AppSkin.marsAttacks => s.skinMarsAttacksSubtitle,
    };
  }

  /// Reconstitue le skin depuis l'identifiant stocké (fallback `defaultSkin`).
  static AppSkin fromId(String? id) {
    if (id == null) return AppSkin.defaultSkin;
    return AppSkin.values.firstWhere(
      (s) => s.id == id,
      orElse: () => AppSkin.defaultSkin,
    );
  }

  /// Palette sémantique du skin (consommée par les getters dynamiques).
  ThemePalette get palette => switch (this) {
        AppSkin.defaultSkin => StreetPhareTheme.defaultPalette,
        AppSkin.marsAttacks => MarsAttacksTheme.palette,
      };

  /// Thème clair du skin.
  ThemeData lightTheme() => switch (this) {
        AppSkin.defaultSkin => StreetPhareTheme.lightTheme(),
        AppSkin.marsAttacks => MarsAttacksTheme.lightTheme(),
      };

  /// Thème sombre du skin.
  ThemeData darkTheme() => switch (this) {
        AppSkin.defaultSkin => StreetPhareTheme.darkTheme(),
        AppSkin.marsAttacks => MarsAttacksTheme.darkTheme(),
      };
}
