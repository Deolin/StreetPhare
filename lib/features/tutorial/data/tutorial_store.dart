// lib/features/tutorial/data/tutorial_store.dart
//
// Store de persistance du flag "premier démarrage" (isFirstLaunch).
//
// Utilise SharedPreferences pour stocker un booléen indiquant si
// l'utilisateur a déjà complété (ou ignoré) le tutoriel de bienvenue.
//
// Logique :
//   - À l'installation / premier lancement : `isFirstLaunch == true`
//   - Après que l'utilisateur a vu ou ignoré le tutoriel :
//     on appelle `markTutorialSeen()` → `isFirstLaunch == false`
//   - `resetForTesting()` remet le flag à `true` (debug uniquement)

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé SharedPreferences utilisée pour persister le flag.
const _kTutorialSeenKey = 'streetphare_tutorial_seen_v1';

/// Singleton de persistance du flag premier démarrage.
///
/// Utilisé par :
///   - [SplashScreen] pour déclencher le tutoriel automatiquement.
///   - [TutorialScreen] pour marquer le tutoriel comme vu.
///   - [SettingsScreen] pour afficher le tutoriel à la demande.
class TutorialStore {
  TutorialStore._();
  static final TutorialStore instance = TutorialStore._();

  SharedPreferences? _prefs;

  // --------------------------------------------------------------------------
  // Initialisation
  // --------------------------------------------------------------------------

  /// Charge les préférences. À appeler au démarrage (avant runApp).
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (kDebugMode) {
      debugPrint('[TutorialStore] isFirstLaunch=$isFirstLaunch');
    }
  }

  // --------------------------------------------------------------------------
  // Accesseurs
  // --------------------------------------------------------------------------

  /// Retourne `true` si l'utilisateur n'a pas encore vu le tutoriel,
  /// i.e. c'est son premier démarrage effectif de l'application.
  bool get isFirstLaunch {
    final seen = _prefs?.getBool(_kTutorialSeenKey) ?? false;
    return !seen;
  }

  // --------------------------------------------------------------------------
  // Mutations
  // --------------------------------------------------------------------------

  /// Marque le tutoriel comme vu / ignoré. Persiste immédiatement.
  /// À appeler lorsque l'utilisateur ferme le tutoriel (bouton "Passer"
  /// ou bouton "Terminer").
  Future<void> markTutorialSeen() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kTutorialSeenKey, true);
    if (kDebugMode) {
      debugPrint('[TutorialStore] tutoriel marqué comme vu.');
    }
  }

  /// Remet le flag à l'état initial (premier démarrage simulé).
  /// À utiliser en développement uniquement.
  Future<void> resetForTesting() async {
    if (!kDebugMode) return;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_kTutorialSeenKey);
    debugPrint('[TutorialStore] flag premier lancement réinitialisé.');
  }
}
