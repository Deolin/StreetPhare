// lib/network/network_config.dart
//
// Configuration réseau de StreetPhare — Version TEST locale.
//
// Centralise TOUTES les URL de serveurs (principal + secours +
// relay) pour pointer exclusivement vers l'infrastructure de test
// locale : 192.168.31.18.
//
//   Serveur Principal : http://192.168.31.18:3000
//   Serveur Backup   : http://192.168.31.18:3001
//   Relay WebSocket   : ws://192.168.31.18:3000/mesh
//
// Le FailoverManager est configuré avec un heartbeat accéléré
// (5s au lieu de 30s) et un timeout de ping réduit (2s au lieu
// de 5s) pour un basculement quasi-instantané.
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
  // Adresse IP fixe de la machine de test locale
  // ---------------------------------------------------------------------------
  static const String _testHost = '192.168.31.18';

  // ---------------------------------------------------------------------------
  // Constantes de ports (miroir de test_servers/server_*.js)
  // ---------------------------------------------------------------------------
  static const int _primaryPortDev = 3000;
  static const int _secondaryPortDev = 3001;

  // ---------------------------------------------------------------------------
  // Adresses RÉSEAU (mode DEBUG forcé pour le test)
  // ---------------------------------------------------------------------------

  /// URL du serveur PRINCIPAL courant.
  ///
  /// Debug : http://192.168.31.18:3000  (test_servers/server_primary.js)
  static String get primaryServer {
    return 'http://$_testHost:$_primaryPortDev';
  }

  /// URL du serveur SECONDAIRE (secours).
  ///
  /// http://192.168.31.18:3001 (test_servers/server_secondary.js)
  static String get initialSecondaryServer {
    return 'http://$_testHost:$_secondaryPortDev';
  }

  /// URL du relay WebSocket (utilisé par `RelayMeshTransport`).
  ///
  /// ws://192.168.31.18:3000/mesh
  static String get relayUrl {
    return 'ws://$_testHost:$_primaryPortDev/mesh';
  }

  /// Master passphrase utilisée pour dériver la clé AES
  /// de chiffrement / déchiffrement des adresses de backup.
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
        'host=$_testHost '
        'primary=$primaryServer '
        'secondary=$initialSecondaryServer '
        'relay=$relayUrl'
        '}';
  }
}