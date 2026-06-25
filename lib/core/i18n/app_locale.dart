// lib/core/i18n/app_locale.dart
//
// Contrôleur de localisation centralisé pour StreetPhare.
//
// Gère :
//   - La détection de la langue système (avec fallback vers FR)
//   - La persistance du choix utilisateur via SharedPreferences
//   - La reconstruction des vues via ValueNotifier
//   - La résolution des chaînes traduites via AppStrings

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// Langues supportées par l'application.
enum AppLanguage {
  fr('fr', 'FR'),
  en('en', 'EN'),
  nl('nl', 'NL'),
  de('de', 'DE');

  final String code;
  final String flag;

  const AppLanguage(this.code, this.flag);

  /// Retourne la locale Flutter correspondante.
  Locale get locale => Locale(code);

  /// Reconstitue depuis un code ISO (ex: "en", "fr", "nl", "de").
  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.fr,
    );
  }

  /// Détecte la langue du système ; fallback FR si non supportée.
  static AppLanguage system() {
    try {
      // Utilisation de dart:ui pour la locale système (cross-platform)
      final locale = ui.PlatformDispatcher.instance.locale;
      final code = locale.languageCode.toLowerCase();
      return AppLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.fr,
      );
    } catch (_) {
      return AppLanguage.fr;
    }
  }
}

/// Contrôleur singleton de la locale applicative.
///
/// Expose un [ValueNotifier<AppLanguage>] pour la reconstruction
/// automatique des widgets qui en dépendent.
class AppLocale extends ValueNotifier<AppLanguage> {
  AppLocale._() : super(AppLanguage.fr);
  static final AppLocale instance = AppLocale._();

  static const String _prefsKey = 'streetphare_app_locale_v1';
  SharedPreferences? _prefs;

  // Cache de l'instance AppStrings pour la langue courante.
  AppStrings _strings = AppStrings.fr();

  /// Retourne les chaînes traduites pour la langue courante.
  AppStrings get strings => _strings;

  /// Charge la langue persistée ou détecte la langue système.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      // Langue persistée (l'utilisateur a déjà choisi)
      value = AppLanguage.fromCode(raw);
    } else {
      // Premier lancement : détection système
      value = AppLanguage.system();
    }
    _updateStrings();
    if (kDebugMode) {
      debugPrint('[AppLocale] loaded: ${value.code}');
    }
  }

  /// Change la langue et persiste le choix.
  Future<void> setLanguage(AppLanguage language) async {
    if (language == value) return;
    value = language;
    _updateStrings();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefsKey, language.code);
    if (kDebugMode) {
      debugPrint('[AppLocale] changed to: ${language.code}');
    }
  }

  /// Met à jour le cache des chaînes traduites.
  void _updateStrings() {
    _strings = switch (value) {
      AppLanguage.fr => AppStrings.fr(),
      AppLanguage.en => AppStrings.en(),
      AppLanguage.nl => AppStrings.nl(),
      AppLanguage.de => AppStrings.de(),
    };
  }
}
