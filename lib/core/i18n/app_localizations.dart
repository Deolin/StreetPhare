import 'package:flutter/material.dart';
// Déclarations des locales.
// Ne pas modifier manuellement. Généré par `flutter gen-l10n`.
import 'package:flutter_streetphare/l10n/app_localizations.dart';

export 'package:flutter_streetphare/l10n/app_localizations.dart';

/// Wrapper pour accéder aux traductions de manière plus pratique.
///
/// Utilise [AppLocalizations] généré par `flutter gen-l10n`.
class S {
  static late AppLocalizations current;

  static void init(BuildContext context) {
    current = AppLocalizations.of(context)!;
  }

  /// Retourne le délégué de localisation pour l'application.
  static Iterable<LocalizationsDelegate<dynamic>> get localizationsDelegates =>
      AppLocalizations.localizationsDelegates;

  /// Retourne les locales supportées par l'application.
  static Iterable<Locale> get supportedLocales =>
      AppLocalizations.supportedLocales;

  /// Exemple d'utilisation :
  /// `Text(S.current.helloWorld)`
}
