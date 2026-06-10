// lib/features/routing/data/avoidance_filter_store.dart
//
// Store persistant des `AvoidanceFilters` (préférences utilisateur
// du moteur de routage). Sauvegardés en `SharedPreferences`.
//
// L'UI des Paramètres écoute ce store via `ValueListenableBuilder`
// pour refléter les changements en temps réel. Le moteur de
// routage `SafePathEngine` lit la valeur courante via `value` au
// moment du calcul.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/avoidance_filters.dart';

/// Store singleton des préférences d'évitement.
class AvoidanceFilterStore extends ValueNotifier<AvoidanceFilters> {
  AvoidanceFilterStore._() : super(const AvoidanceFilters());
  static final AvoidanceFilterStore instance = AvoidanceFilterStore._();

  static const String _prefsKey = 'streetphare_avoidance_filters_v1';

  SharedPreferences? _prefs;

  /// Charge les préférences depuis le stockage local. À appeler
  /// UNE SEULE FOIS au démarrage de l'app.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) {
      value = const AvoidanceFilters();
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      value = AvoidanceFilters.fromJson(json);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AvoidanceFilterStore] erreur de parsing : $e');
      }
      value = const AvoidanceFilters();
    }
  }

  /// Met à jour les préférences (et persiste).
  Future<void> update(AvoidanceFilters filters) async {
    value = filters;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefsKey, jsonEncode(filters.toJson()));
    if (kDebugMode) {
      debugPrint('[AvoidanceFilterStore] prefs sauvegardées : '
          '${filters.toJson()}');
    }
  }
}
