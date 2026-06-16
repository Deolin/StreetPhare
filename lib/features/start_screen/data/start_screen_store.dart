// lib/features/start_screen/data/start_screen_store.dart
//
// Store de persistance du flag "premier démarrage du StartScreen".
//
// Utilise SharedPreferences pour stocker un booléen indiquant si
// l'utilisateur a déjà complété l'écran de démarrage (choix de langue).
//
// Logique :
//   - À l'installation / premier lancement : `isFirstLaunch == true`
//   - Après que l'utilisateur a cliqué sur "Commencer" :
//     on appelle `markStartComplete()` → `isFirstLaunch == false`
//   - `resetForTesting()` remet le flag à `true` (debug uniquement)

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé SharedPreferences utilisée pour persister le flag.
const _kStartScreenSeenKey = 'streetphare_start_screen_seen_v1';

/// Singleton de persistance du flag premier démarrage du StartScreen.
///
/// Utilisé par :
///   - [SplashScreen] pour déclencher le StartScreen automatiquement.
///   - [StartScreen] pour marquer l'écran comme vu.
class StartScreenStore {
  StartScreenStore._();
  static final StartScreenStore instance = StartScreenStore._();

  SharedPreferences? _prefs;

  // --------------------------------------------------------------------------
  // Initialisation
  // --------------------------------------------------------------------------

  /// Charge les préférences. À appeler au démarrage (avant runApp).
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (kDebugMode) {
      debugPrint('[StartScreenStore] isFirstLaunch=$isFirstLaunch');
    }
  }

  // --------------------------------------------------------------------------
  // Accesseurs
  // --------------------------------------------------------------------------

  /// Retourne `true` si l'utilisateur n'a pas encore vu le StartScreen,
  /// i.e. c'est son tout premier démarrage de l'application.
  bool get isFirstLaunch {
    final seen = _prefs?.getBool(_kStartScreenSeenKey) ?? false;
    return !seen;
  }

  // --------------------------------------------------------------------------
  // Mutations
  // --------------------------------------------------------------------------

  /// Marque le StartScreen comme vu. Persiste immédiatement.
  /// À appeler lorsque l'utilisateur clique sur "Commencer".
  Future<void> markStartComplete() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kStartScreenSeenKey, true);
    if (kDebugMode) {
      debugPrint('[StartScreenStore] écran de démarrage marqué comme vu.');
    }
  }

  /// Remet le flag à l'état initial (premier démarrage simulé).
  /// À utiliser en développement uniquement.
  Future<void> resetForTesting() async {
    if (!kDebugMode) return;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_kStartScreenSeenKey);
    debugPrint('[StartScreenStore] flag premier lancement réinitialisé.');
  }
}