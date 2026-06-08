// Point d'entrée principal de l'application StreetPhare.
//
// Initialise très tôt le logger de débogage client
// (lib/debug/client_debug_logger.dart) pour qu'il commence
// à produire `CLIENT_DEBUG.md` dès la phase de bootstrap.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'core/theme/streetphare_theme.dart';
import 'core/theme/theme_controller.dart';
import 'debug/client_debug_logger.dart';
import 'features/settings/data/panic_contact_store.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'network/bootstrap.dart';
import 'network/network_config.dart';
import 'network/network_coordinator.dart';

/// Point d'entrée principal de l'application StreetPhare
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise le logger Markdown de débogage (no-op en release).
  await ClientDebugLogger.instance.init();

  // Orientation verrouillée en portrait
  await SystemChrome.setPreferredOrientations([
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

  if (kDebugMode) {
    debugPrint('[main] orientation verrouillée + logger client initialisé');
  }

  // === Chargement des préférences locales (thème + contacts PANIC)
  await ThemeController.instance.load();
  await PanicContactStore.instance.load();

  // === Initialisation de la "ruche" réseau décentralisée ===
  if (kDebugMode) {
    debugPrint('[main] ${NetworkConfig.describe()}');
  }
  ClientDebugLogger.instance.log(
    'Démarrage app',
    details: NetworkConfig.describe(),
    emoji: '🚀',
  );

  try {
    final bootstrap = await buildNetworkBootstrap(
      primaryServer: NetworkConfig.primaryServer,
      relayUrl: NetworkConfig.relayUrl,
      masterPassphrase: NetworkConfig.masterPassphrase,
      initialBackupChain: NetworkConfig.initialSecondaryServer.isEmpty
          ? const []
          : await _seedSingleBackup(NetworkConfig.initialSecondaryServer,
              NetworkConfig.masterPassphrase),
    );

    await NetworkCoordinator.instance.init(
      failoverConfig: bootstrap.failoverConfig,
      transports: bootstrap.transports,
    );

    if (kDebugMode) {
      debugPrint('[main] réseau StreetPhare initialisé sur '
          '${describePlatform()}');
    }
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
        return MaterialApp(
          title: 'StreetPhare',
          debugShowCheckedModeBanner: false,

          // Thèmes clair & sombre.
          theme: StreetPhareTheme.lightTheme(),
          darkTheme: StreetPhareTheme.darkTheme(),

          // ThemeMode est piloté par le ThemeController
          // (système / clair / sombre, persistant).
          themeMode: mode.toThemeMode(),

          home: const SplashScreen(),
        );
      },
    );
  }
}
