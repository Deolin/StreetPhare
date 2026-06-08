// lib/network/network_config.dart
//
// Configuration réseau de StreetPhare.
//
// Centralise TOUTES les URL de serveurs (principal + secours +
// relay) selon le mode d'exécution de l'application :
//
//   * kDebugMode == true  -> on pointe sur les serveurs de test
//     locaux (test_servers/server_*.js) via 'localhost' (Windows,
//     Linux, macOS, iOS Simulator) ou '10.0.2.2' (émulateur
//     Android, qui est l'alias de loopback de l'hôte).
//
//   * kDebugMode == false -> mode production : on utilise les
//     URLs FICTIVES du domaine streetphare.org. Ces valeurs
//     peuvent (et doivent) être SURCHARGEES au build par
//     --dart-define (ex. :
//       flutter build apk --dart-define=STREETPHARE_PRIMARY=https://api.streetphare.org
//     ).
//
// Ce fichier est consommé par :
//   * lib/main.dart          -> valeurs passées à buildNetworkBootstrap
//   * lib/network/bootstrap.dart -> déjà branché en conséquence
//   * potentiellement d'autres clients HTTP de l'app
//
// IMPORTANT : ne JAMAIS hardcoder d'URL ailleurs dans l'app.
// Toujours importer 'network_config.dart' pour rester cohérent.

import 'package:flutter/foundation.dart';

/// Configuration réseau résolue pour l'environnement courant.
class NetworkConfig {
  NetworkConfig._();

  // ---------------------------------------------------------------------------
  // Plateforme courante (utile pour le routing Android emulator vs. desktop)
  // ---------------------------------------------------------------------------
  static const bool _isAndroidEmulatorTarget =
      bool.fromEnvironment('STREETPHARE_ANDROID_EMULATOR');

  /// Hôte à utiliser pour atteindre la machine de développement
  /// depuis un client. Sur émulateur Android, '10.0.2.2' est l'alias
  /// officiel du host (cf. https://developer.android.com/studio/run/emulator-networking).
  /// Sur Windows / Linux / macOS / iOS Simulator / web -> 'localhost'.
  static String get _loopbackHost {
    if (_isAndroidEmulatorTarget) return '10.0.2.2';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return 'localhost';
  }

  // ---------------------------------------------------------------------------
  // Constantes de ports (miroir de test_servers/server_*.js)
  // ---------------------------------------------------------------------------
  static const int _primaryPortDev = 3000;
  static const int _secondaryPortDev = 3001;

  // ---------------------------------------------------------------------------
  // Adresses RÉSEAU (calculées à partir de kDebugMode)
  // ---------------------------------------------------------------------------

  /// URL du serveur PRINCIPAL courant.
  ///
  /// Debug : http://loopback:3000  (test_servers/server_primary.js)
  /// Prod  : https://api.streetphare.org
  static String get primaryServer {
    if (kDebugMode) {
      return 'http://$_loopbackHost:$_primaryPortDev';
    }
    return const String.fromEnvironment(
      'STREETPHARE_PRIMARY',
      defaultValue: 'https://api.streetphare.org',
    );
  }

  /// URL du serveur SECONDAIRE (normalement reçue chiffrée du
  /// serveur principal, puis déchiffrée par `FailoverManager`).
  ///
  /// Cette constante est utilisée UNIQUEMENT pour pré-charger la
  /// chaîne de secours au premier lancement (`bootstrap.dart`).
  /// En debug on pointe en clair sur localhost:3001 ; en prod on
  /// n'expose rien (la chaîne sera construite depuis le serveur
  /// principal via `next_backup`).
  static String get initialSecondaryServer {
    if (kDebugMode) {
      return 'http://$_loopbackHost:$_secondaryPortDev';
    }
    return const String.fromEnvironment(
      'STREETPHARE_SECONDARY',
      defaultValue: '',
    );
  }

  /// URL du relay WebSocket (utilisé par `RelayMeshTransport`).
  ///
  /// Debug : ws://loopback:3000/mesh  (mêmes serveurs Node)
  /// Prod  : wss://relay.streetphare.org/mesh
  static String get relayUrl {
    if (kDebugMode) {
      return 'ws://$_loopbackHost:$_primaryPortDev/mesh';
    }
    return const String.fromEnvironment(
      'STREETPHARE_RELAY',
      defaultValue: 'wss://relay.streetphare.org/mesh',
    );
  }

  /// Master passphrase utilisée pour dériver la clé AES
  /// de chiffrement / déchiffrement des adresses de backup.
  ///
  /// EN PRODUCTION, cette valeur NE DOIT PAS être une chaîne
  /// statique. Elle doit provenir d'un secure-storage natif ou
  /// d'un serveur de clés distant.
  static String get masterPassphrase {
    return const String.fromEnvironment(
      'STREETPHARE_MASTER_KEY',
      defaultValue: 'streetphare-dev-key-CHANGE_ME_IN_PROD',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers de debug
  // ---------------------------------------------------------------------------

  /// Renvoie un résumé lisible de la configuration (à n'utiliser
  /// QUE dans des `debugPrint`). Ne jamais logger les secrets.
  static String describe() {
    return 'NetworkConfig{'
        'debug=$kDebugMode '
        'loopback=$_loopbackHost '
        'primary=$primaryServer '
        'secondary=$initialSecondaryServer '
        'relay=$relayUrl'
        '}';
  }
}
