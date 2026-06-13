// lib/core/theme/theme_controller.dart
//
// Gestionnaire de thème de StreetPhare.
//
// Responsabilités :
//   * Stocker en mémoire le `ThemeMode` courant (système, clair, sombre).
//   * Persister le choix utilisateur dans `shared_preferences` pour
//     qu'il soit restauré au prochain lancement.
//   * Exposer un `ValueListenable<ThemeMode>` que le `MaterialApp`
//     racine écoute pour appliquer le thème instantanément, sans
//     redémarrer l'application.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper typé autour du mode de thème pour pouvoir l'utiliser
/// dans des `Radio` lists et le sérialiser facilement.
enum AppThemeMode {
  system('system', 'Mode Système'),
  light('light', 'Mode Clair'),
  dark('dark', 'Mode Sombre');

  const AppThemeMode(this.id, this.label);

  /// Identifiant sérialisé dans SharedPreferences.
  final String id;

  /// Libellé affiché dans l'UI des paramètres.
  final String label;

  /// Convertit la valeur stockée en enum. Fallback sur `system`.
  static AppThemeMode fromId(String? id) {
    if (id == null) return AppThemeMode.system;
    return AppThemeMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => AppThemeMode.system,
    );
  }

  /// Convertit l'enum en `ThemeMode` Flutter.
  ThemeMode toThemeMode() {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

/// Contrôleur global du thème.
///
/// Singleton accessible depuis n'importe quel widget (notamment la
/// page Paramètres pour changer le thème à la volée).
class ThemeController extends ValueNotifier<AppThemeMode> {
  ThemeController._() : super(AppThemeMode.system);

  static final ThemeController instance = ThemeController._();

  static const String _prefsKey = 'streetphare.theme_mode';

  /// Charge la préférence persistée. À appeler une fois au boot
  /// de l'application, après `WidgetsFlutterBinding.ensureInitialized()`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefsKey);
      value = AppThemeMode.fromId(id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ThemeController] impossible de charger le thème : $e');
      }
      value = AppThemeMode.system;
    }
  }

  /// Change le thème et persiste le choix de manière asynchrone.
  Future<void> setMode(AppThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ThemeController] impossible de persister le thème : $e');
      }
    }
  }
}
