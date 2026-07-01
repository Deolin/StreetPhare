// Point d'entrée principal de l'application StreetPhare.
//
// Initialise très tôt le logger de débogage client
// (lib/debug/client_debug_logger.dart) pour qu'il commence
// à produire `CLIENT_DEBUG.md` dès la phase de bootstrap.
import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/i18n/app_locale.dart';
import 'core/network/url_strategy_noop.dart'
    if (dart.library.js_util) 'package:flutter_streetphare/core/network/url_strategy_web.dart';
import 'core/security/keystore_service.dart';
import 'core/theme/streetphare_theme.dart';
import 'core/theme/theme_controller.dart';
import 'database/crypto_utils.dart';
import 'debug/client_debug_logger.dart';
import 'features/bug_report/presentation/bug_report_fab.dart';
import 'features/bug_report/presentation/bug_report_service.dart';
import 'features/events/presentation/event_manager.dart';
import 'features/geofencing/presentation/geofencing_service.dart';
import 'features/geofencing/presentation/proximity_validation_service.dart';
import 'features/messaging/presentation/hive_messaging_service.dart';
import 'features/routing/data/avoidance_filter_store.dart';
import 'features/settings/data/app_preferences_store.dart';
import 'features/settings/data/panic_contact_store.dart';
import 'features/settings/data/settings_store.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'features/start_screen/data/start_screen_store.dart';
import 'features/tutorial/data/tutorial_store.dart';
import 'network/bootstrap.dart';
import 'network/network_config.dart';
import 'network/network_coordinator.dart';
import 'network/server_heartbeat_service.dart';
import 'services/apk_backup_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/version_check_service.dart';

/// Point d'entrée principal de l'application StreetPhare
void main() async {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════
  // Catcher de crash global — StreetPhare Offline-First Bug Report
  // ═══════════════════════════════════════════════════════════════════
  // Capture TOUTES les erreurs Flutter non interceptées et les
  // envoie au BugReportService pour stockage local + envoi différé.
  // Le service est blindé : il ne peut PAS provoquer un crash
  // secondaire (try-catch dans toutes les méthodes).
  //
  // Inclut le filtre du bug connu geolocator_windows (thread non-UI).
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    // Filtre le bug connu geolocator_windows.
    if (msg.contains('geolocator_updates') &&
        msg.contains('non-platform thread')) {
      return; // Ignorée : bug connu, données GPS OK.
    }
    // Capture le crash pour le bug report.
    try {
      BugReportService.instance.submitCrash(
        error: msg,
        stackTrace: details.stack.toString(),
      );
    } catch (_) {
      // Silence absolu — le catcher ne doit jamais crasher.
    }
    FlutterError.presentError(details);
  };

  // Capture les erreurs de la PlatformDispatcher (isolate principal).
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      BugReportService.instance.submitCrash(
        error: error.toString(),
        stackTrace: stack.toString(),
      );
    } catch (_) {
      // Silence.
    }
    return false; // Laisse Flutter gérer l'erreur normalement aussi.
  };

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
  // Timeout de sécurité à 15 secondes : si un store bloque (ex: SharedPreferences
  // corrompu), on ne bloque pas l'application indéfiniment.
  try {
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
    ]).timeout(const Duration(seconds: 15));
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[main] ⚠ Timeout ou erreur init parallèle : $e\n$st');
    }
    ClientDebugLogger.instance.log(
      'Timeout init parallèle',
      details: e.toString(),
      emoji: '⏱️',
    );
  }

  // === Étape 2 : Sauvegarde de l'APK source (premier lancement uniquement) ===
  // Non-bloquant : s'exécute en arrière-plan sans retarder le démarrage.
  // Copie l'APK installé vers le stockage Documents persistant pour
  // la fonctionnalité de distribution P2P (partage sans Play Store).
  unawaited(
    ApkBackupService.instance.init().catchError((e, st) {
      if (kDebugMode) {
        debugPrint('[main] ⚠ Erreur init APK backup : $e\n$st');
      }
      ClientDebugLogger.instance.log(
        'Erreur APK backup',
        details: e.toString(),
        emoji: '📦',
      );
    }),
  );

  if (kDebugMode) {
    debugPrint('[main] orientation verrouillée + logger client initialisé');
  }

  // === Étape 3 : Initialisation de la "ruche" réseau décentralisée ===
  if (kDebugMode) {
    try {
      debugPrint('[main] ${NetworkConfig.describe()}');
    } catch (_) {
      debugPrint('[main] NetworkConfig indisponible');
    }
  }

  // Flag indiquant si l'initialisation réseau a réussi. Si false,
  // les services dépendants de Hive (Geofencing, Proximity) ne
  // démarrent pas, évitant la cascade "Bad state: HiveAlertDatabase
  // non initialisée".
  var networkInitOk = false;

  try {
    // Charge la clé maîtresse depuis le keystore sécurisé
    // (Android Keystore / iOS Keychain). Génère une clé
    // aléatoire au premier lancement si nécessaire.
    final masterKey = await KeyStoreService.instance.loadOrCreateMasterKey();

    ClientDebugLogger.instance.log(
      'Démarrage app',
      details: 'Web mode',
      emoji: '🚀',
    );

    final bootstrap = await buildNetworkBootstrap(
      primaryServer: NetworkConfig.primaryServer,
      relayUrl: NetworkConfig.relayUrl,
      masterKey: masterKey,
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

    // === Étape 5 : Intelligence StreetPhare (services légers uniquement) ===
    // Les services sans accès natif lourd démarrent ici.
    ConnectivityService.instance.start();
    EventManager.instance.start();
    HiveMessagingService.instance.start();
    unawaited(NotificationService.instance.showPersistentNotification());

    networkInitOk = true;

    // Démarre le heartbeat serveur après l'init réseau (FailoverManager prêt).
    ServerHeartbeatService.instance.start();

    // Démarre le service de bug report offline-first.
    unawaited(BugReportService.instance.start());
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

  runApp(const StreetPhareApp());

  // === Étape 6 : Services géolocalisés (démarrage différé après 1er rendu) ===
  // Le GeofencingService et ProximityValidationService ouvrent des flux
  // natifs (Geolocator.getPositionStream) qui peuvent saturer le thread UI
  // et provoquer des drops de frames. On les démarre APRÈS le premier
  // rendu pour que l'UI soit responsive immédiatement.
  //
  // ⚠️ Si l'init réseau a échoué, Hive n'a jamais été ouverte. On bloque
  //    le démarrage pour éviter la cascade "Bad state: HiveAlertDatabase
  //    non initialisée" en boucle.
  if (networkInitOk) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        GeofencingService.instance.start();
        ProximityValidationService.instance.start();
      });
    });
  }
}

Future<List<String>> _seedSingleBackup(
  String address,
  SecretKey masterKey,
) async {
  if (address.isEmpty) return const [];
  try {
    final ciphered = await CryptoUtils.instance
        .encryptAddress(address, masterKey);
    return [ciphered];
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[main] ⚠ Erreur chiffrement backup: $e');
    }
    ClientDebugLogger.instance.log(
      'Erreur chiffrement backup',
      details: e.toString(),
      emoji: '🔑',
    );
    return const [];
  }
}

/// Widget racine de l'application StreetPhare.
/// Clé globale du navigateur, utilisée par le bouton de bug global
/// pour ouvrir le dialogue sans dépendre du contexte du builder.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
                return ValueListenableBuilder<bool>(
                  valueListenable: VisualImpairedStore.instance,
                  builder: (context, isVisualImpaired, _) {
                    return MaterialApp(
                      title: 'StreetPhare',
                      debugShowCheckedModeBanner: false,
                      navigatorKey: navigatorKey,

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

                      // Facteur d'échelle du texte global (accessibilité / malvoyant)
                      // + bouton de débogage global permanent.
                      builder: (context, child) {
                        final factor =
                            isVisualImpaired ? 1.5 : prefs.textScaleFactor;
                        return MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(factor),
                          ),
                          child: Stack(
                            children: [
                              if (child != null) child,
                              const BugReportFab(),
                            ],
                          ),
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
      },
    );
  }
}
