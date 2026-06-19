// Point d'entrée principal de l'application StreetPhare.
//
// Initialise très tôt le logger de débogage client
// (lib/debug/client_debug_logger.dart) pour qu'il commence
// à produire `CLIENT_DEBUG.md` dès la phase de bootstrap.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/i18n/app_locale.dart';
import 'core/theme/streetphare_theme.dart';
import 'core/theme/theme_controller.dart';
import 'debug/client_debug_logger.dart';
import 'features/events/presentation/event_manager.dart';
import 'features/geofencing/presentation/geofencing_service.dart';
import 'features/geofencing/presentation/proximity_validation_service.dart';
import 'features/messaging/presentation/hive_messaging_service.dart';
import 'features/routing/data/avoidance_filter_store.dart';
import 'features/settings/data/app_preferences_store.dart';
import 'features/settings/data/panic_contact_store.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'features/start_screen/data/start_screen_store.dart';
import 'features/tutorial/data/tutorial_store.dart';
import 'network/bootstrap.dart';
import 'network/network_config.dart';
import 'network/network_coordinator.dart';
import 'services/apk_backup_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/version_check_service.dart';
import 'core/network/url_strategy_noop.dart'
    if (dart.library.js_util) 'package:flutter_streetphare/core/network/url_strategy_web.dart';

/// Point d'entrée principal de l'application StreetPhare
void main() async {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  // Orientation verrouillée en portrait
  final orientationFuture = SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Style de la barre de statut
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // === Étape 1 : Chargement des préférences locales (thème + contacts PANIC
  //     + filtres d'évitement Safe Path + flag premier démarrage tutoriel)
  // On parallélise le chargement des stores et l'initialisation des services de base.
  await Future.wait([
    ClientDebugLogger.instance.init(),
    NotificationService.instance.init(),
    VersionCheckService.instance.init(),
    AppLocale.instance.load(),
    ThemeController.instance.load(),
    PanicContactStore.instance.load(),
    AvoidanceFilterStore.instance.load(),
    AppPreferencesStore.instance.load(),
    TutorialStore.instance.load(),
    StartScreenStore.instance.load(),
    orientationFuture,
  ]);

  // === Étape 2 : Sauvegarde de l'APK source (premier lancement uniquement) ===
  // Non-bloquant : s'exécute en arrière-plan sans retarder le démarrage.
  // Copie l'APK installé vers le stockage Documents persistant pour
  // la fonctionnalité de distribution P2P (partage sans Play Store).
  unawaited(ApkBackupService.instance.init());

  if (kDebugMode) {
    debugPrint('[main] orientation verrouillée + logger client initialisé');
  }

  // === Étape 3 : Initialisation de la "ruche" réseau décentralisée ===
    if (kDebugMode) {
      try {
        debugPrint('[main] ${NetworkConfig.describe()}');
      } catch (_) {
        debugPrint('[main] NetworkConfig indisponible (master key manquante)');
      }
    }

    try {
      // Essaie de récupérer la master passphrase. Sur le Web en
      // développement, la variable dart-define peut être absente.
      // On bascule en mode dégradé (réseau désactivé) plutôt que
      // de planter l'application entière.
      String masterKey;
      try {
        masterKey = NetworkConfig.masterPassphrase;
      } catch (_) {
        masterKey = 'streetphare-web-dev-fallback';
        if (kDebugMode) {
          debugPrint('[main] ⚠ Master key manquante → fallback web-dev');
        }
      }

      ClientDebugLogger.instance.log(
        'Démarrage app',
        details: 'Web mode',
        emoji: '🚀',
      );

      final bootstrap = await buildNetworkBootstrap(
        primaryServer: NetworkConfig.primaryServer,
        relayUrl: NetworkConfig.relayUrl,
        masterPassphrase: masterKey,
        initialBackupChain: NetworkConfig.initialSecondaryServer.isEmpty
            ? const []
            : await _seedSingleBackup(
                NetworkConfig.initialSecondaryServer, masterKey),
      );

      await NetworkCoordinator.instance.init(
        failoverConfig: bootstrap.failoverConfig,
        transports: bootstrap.transports,
        localPeerId: bootstrap.peerId,
      );

      if (kDebugMode) {
        debugPrint('[main] réseau StreetPhare initialisé sur '
            '${describePlatform()}');
      }

      // === Étape 5 : Intelligence StreetPhare ===
      ConnectivityService.instance.start();
      GeofencingService.instance.start();
      ProximityValidationService.instance.start();
      EventManager.instance.start();
      HiveMessagingService.instance.start();
      unawaited(NotificationService.instance.showPersistentNotification());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[main] ERREUR initialisation réseau : $e\n$st');
      }
      ClientDebugLogger.instance.log(
        'ERREUR init réseau',
        details: e.toString(),
        emoji: '❌',
      );
    }

  runApp(StreetPhareApp());
}

Future<List<String>> _seedSingleBackup(
  String address,
  String passphrase,
) async {
  return const [];
}

/// Widget racine de l'application StreetPhare.
class StreetPhareApp extends StatelessWidget {
  const StreetPhareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: AppLocale.instance,
          builder: (context, language, _) {
            return ValueListenableBuilder<AppPreferences>(
              valueListenable: AppPreferencesStore.instance,
              builder: (context, prefs, _) {
                return MaterialApp(
                  title: 'StreetPhare',
                  debugShowCheckedModeBanner: false,

                  // Thèmes clair & sombre.
                  theme: StreetPhareTheme.lightTheme(),
                  darkTheme: StreetPhareTheme.darkTheme(),

                  // ThemeMode est piloté par le ThemeController
                  // (système / clair / sombre, persistant).
                  themeMode: mode.toThemeMode(),

                  // Support multilingue
                  locale: language.locale,
                  // Ajout des délégués requis pour les composants Material (comme DropdownButton)
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  // Déclaration des locales supportées par la Ruche et la vitrine
                  supportedLocales: const [
                    Locale('fr', ''),
                    Locale('en', ''),
                    Locale('nl', ''),
                    Locale('de', ''),
                  ],

                  // Facteur d'échelle du texte global (accessibilité / malvoyant).
                  builder: (context, child) {
                    final factor = prefs.textScaleFactor;
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(factor),
                      ),
                      child: child!,
                    );
                  },

                  home: const SplashScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}
