// lib/features/settings/data/settings_store.dart
//
// ValueNotifier dédié au mode malvoyant.
//
// Ce notifier est utilisé par main.dart pour forcer un textScaleFactor
// de 1.5 lorsque le mode malvoyant est activé, indépendamment du
// slider de taille de texte des préférences générales.

import 'package:flutter/foundation.dart';

/// Store singleton pour le mode malvoyant.
///
/// Écoutable via [ValueListenableBuilder].
class VisualImpairedStore extends ValueNotifier<bool> {
  VisualImpairedStore._() : super(false);
  static final VisualImpairedStore instance = VisualImpairedStore._();

  /// Active / désactive le mode malvoyant.
  void setMode(bool enabled) {
    value = enabled;
  }

  /// Bascule le mode malvoyant.
  void toggle() {
    value = !value;
  }
}
