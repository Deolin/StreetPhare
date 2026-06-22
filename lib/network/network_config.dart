// lib/network/network_config.dart
//
// Configuration réseau de StreetPhare — Version PRODUCTION No-IP.
//
// Centralise TOUTES les URL de serveurs (principal + secours +
// relay) pour pointer exclusivement vers l'infrastructure de
// production : streetphare.ddns.be.
//
//   Serveur Principal : http://streetphare.ddns.be:3000
//   Serveur Backup   : http://streetphare.ddns.be:3001
//   Relay WebSocket   : ws://streetphare.ddns.be:3000/mesh
//
// Le FailoverManager est configuré avec un heartbeat normal
// (30s) et un timeout de ping standard (5s).
//
// Ce fichier est consommé par :
//   * lib/main.dart            -> valeurs passées à buildNetworkBootstrap
//   * lib/network/bootstrap.dart -> déjà branché en conséquence
//   * potentiellement d'autres clients HTTP de l'app
//
// IMPORTANT : ne JAMAIS hardcoder d'URL ailleurs dans l'app.
// Toujours importer 'network_config.dart' pour rester cohérent.

/// Configuration réseau résolue pour l'environnement courant.
class NetworkConfig {
  NetworkConfig._();

  // ---------------------------------------------------------------------------
  // Adresse No-IP de production
  // ---------------------------------------------------------------------------
  static const String _productionHost = 'streetphare.ddns.be';

  // ---------------------------------------------------------------------------
  // Constantes de ports
  // ---------------------------------------------------------------------------
  static const int _primaryPort = 3000;
  static const int _secondaryPort = 3001;

  // ---------------------------------------------------------------------------
  // Adresses RÉSEAU (mode PRODUCTION)
  // ---------------------------------------------------------------------------

  /// URL du serveur PRINCIPAL courant.
  ///
  /// Production : http://streetphare.ddns.be:3000
  static String get primaryServer {
    return 'http://$_productionHost:$_primaryPort';
  }

  /// URL du serveur SECONDAIRE (secours).
  ///
  /// http://streetphare.ddns.be:3001
  static String get initialSecondaryServer {
    return 'http://$_productionHost:$_secondaryPort';
  }

  /// URL du relay WebSocket (utilisé par `RelayMeshTransport`).
  ///
  /// ws://streetphare.ddns.be:3000/mesh
  static String get relayUrl {
    return 'ws://$_productionHost:$_primaryPort/mesh';
  }

  /// URL WebSocket du relais d'administration serveur.
  ///
  /// ws://streetphare.ddns.be:3000/admin
  static String get primaryUrl {
    return 'ws://$_productionHost:$_primaryPort/admin';
  }

  /// Master passphrase utilisée pour dériver la clé AES
  /// de chiffrement / déchiffrement des adresses de backup.
  /// DOIT être fournie via la variable d'environnement
  /// `STREETPHARE_MASTER_KEY` au moment de la compilation.
  /// Aucune valeur par défaut n'est acceptée en production.
  static String get masterPassphrase {
    const key = String.fromEnvironment('STREETPHARE_MASTER_KEY');
    if (key.isEmpty) {
      throw StateError(
        'STREETPHARE_MASTER_KEY non définie. '
        'Passez --dart-define=STREETPHARE_MASTER_KEY=... '
        'à la compilation.',
      );
    }
    return key;
  }

  // ---------------------------------------------------------------------------
  // Helpers de debug
  // ---------------------------------------------------------------------------

  /// Renvoie un résumé lisible de la configuration (à n'utiliser
  /// QUE dans des `debugPrint`). Ne jamais logger les secrets.
  static String describe() {
    return 'NetworkConfig{'
        'host=$_productionHost '
        'primary=$primaryServer '
        'secondary=$initialSecondaryServer '
        'relay=$relayUrl'
        '}';
  }
}
