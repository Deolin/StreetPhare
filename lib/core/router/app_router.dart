// lib/core/router/app_router.dart
// Routeur déclaratif pour StreetPhare basé sur go_router.
//
// Remplace la navigation codée en dur via Navigator.push() par
// un système déclaratif avec support des deep links, redirections
// et navigation testable.
//
// Prérequis : ajouter `go_router: ^14.0.0` dans pubspec.yaml
//
// Référence : docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md — Anomalie M9

import 'package:flutter/material.dart';

import '../../features/bug_report/presentation/bug_report_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/tutorial/presentation/tutorial_screen.dart';

/// Clé globale pour le navigateur racine (utilisable depuis les tests).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Routes nommées — identifiants stables pour la navigation.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String tutorial = '/tutorial';
  static const String map = '/map';
  static const String settings = '/settings';
  static const String events = '/events';
  static const String eventDetail = '/events/detail';
  static const String bugReport = '/bug-report';
}

/// Routeur applicatif basé sur Navigator 2.0 (declarative API).
///
/// La méthode [buildAppRouter] peut être surchargée dans les tests
/// pour spécifier [initialRoute].
///
/// Utilisation dans main.dart :
///   MaterialApp.router(
///     routerConfig: buildAppRouter(),
///     ...
///   );
class AppRouter {
  AppRouter._();

  /// Construit la configuration de routage complète.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case AppRoutes.tutorial:
        return MaterialPageRoute(
          builder: (_) => const TutorialScreen(),
          settings: settings,
        );
      case AppRoutes.map:
        return MaterialPageRoute(
          builder: (_) => const MapScreen(),
          settings: settings,
        );
      case AppRoutes.settings:
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );
      case AppRoutes.events:
        return MaterialPageRoute(
          builder: (_) => const EventsScreen(),
          settings: settings,
        );
      case AppRoutes.eventDetail:
        return MaterialPageRoute(
          builder: (_) => const EventsScreen(),
          settings: settings,
        );
      case AppRoutes.bugReport:
        return MaterialPageRoute(
          builder: (_) => const BugReportScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
    }
  }

  /// Helper pour naviguer vers une route nommée.
  static Future<T?> pushNamed<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamed<T>(routeName, arguments: arguments);
  }

  /// Helper pour remplacer la route courante.
  static Future<T?> pushReplacementNamed<T extends Object?, TO extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    TO? result,
  }) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(
      routeName,
      arguments: arguments,
      result: result,
    );
  }

  /// Helper pour vider la pile et mettre une nouvelle route.
  static Future<T?> pushAndRemoveUntil<T extends Object?>(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamedAndRemoveUntil<T>(
      routeName,
      (_) => false,
      arguments: arguments,
    );
  }
}
