// lib/core/theme/skin_controller.dart
//
// Gestionnaire du skin (profil visuel) actif.
//
// Responsabilités :
//   * Stocker en mémoire le skin courant (`AppSkin`).
//   * Persister le choix utilisateur dans `shared_preferences`.
//   * Exposer un `ValueNotifier<AppSkin>` que le `MaterialApp` racine
//     écoute pour appliquer le skin instantanément.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_skin.dart';

/// Contrôleur global du skin. Singleton accessible partout.
class SkinController extends ValueNotifier<AppSkin> {
  SkinController._() : super(AppSkin.defaultSkin);

  static final SkinController instance = SkinController._();

  static const String _prefsKey = 'streetphare.skin';

  /// Charge le skin persisté. À appeler une fois au boot de l'application.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = AppSkin.fromId(prefs.getString(_prefsKey));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SkinController] impossible de charger le skin : $e');
      }
      value = AppSkin.defaultSkin;
    }
  }

  /// Change le skin et persiste le choix de manière asynchrone.
  Future<void> setSkin(AppSkin skin) async {
    if (value == skin) return;
    value = skin;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, skin.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SkinController] impossible de persister le skin : $e');
      }
    }
  }
}
