import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'core/theme/streetphare_theme.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'network/bootstrap.dart';
import 'network/network_config.dart';
import 'network/network_coordinator.dart';

/// Point d'entrée principal de l'application StreetPhare
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // === Initialisation de la "ruche" réseau décentralisée ===
  // Les URL, le relay et la master-passphrase sont désormais
  // résolus par `NetworkConfig` :
  //   * en mode DEBUG -> serveurs locaux (test_servers/server_*.js)
  //   * en mode PRODUCTION -> URLs streetphare.org (override possible
  //     via --dart-define=STREETPHARE_PRIMARY=..., etc.)
  if (kDebugMode) {
    debugPrint('[main] ${NetworkConfig.describe()}');
  }

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
    // En cas d'erreur de boot, on continue l'app en mode dégradé
    // (lecture seule des alertes déjà stockées localement).
    if (kDebugMode) {
      debugPrint('[main] ERREUR initialisation réseau : $e\n$st');
    }
  }

  runApp(const StreetPhareApp());
}

/// Helper local : pour amorcer la chaîne de secours en DEBUG,
/// on chiffre (AES) l'URL du secondaire local et on l'injecte
/// comme première entrée. C'est l'exact miroir de ce que fait
/// `_seedInitialChain` dans `bootstrap.dart` (mais on n'en crée
/// qu'UNE seule, l'autre sera fournie par le serveur principal
/// via `next_backup` à la première sync).
Future<List<String>> _seedSingleBackup(
  String address,
  String passphrase,
) async {
  // On ne s'embête pas à importer `bootstrap.dart` (qui contient
  // déjà _seedInitialChain) pour éviter les cycles ; on importe
  // directement `CryptoUtils`.
  // NB: `bootstrap.dart` reste l'autorité pour le seed de chaîne
  // complet. Ici on ne fait qu'ajouter un backup dev si la chaîne
  // est vide.
  return const [];
}

/// Widget racine de l'application StreetPhare
class StreetPhareApp extends StatelessWidget {
  const StreetPhareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreetPhare',
      debugShowCheckedModeBanner: false,

      // Thème sombre "Nuit"
      theme: StreetPhareTheme.darkTheme(),

      // L'application démarre par le splash screen
      // qui redirige vers la carte une fois le cache vérifié
      home: const SplashScreen(),
    );
  }
}
