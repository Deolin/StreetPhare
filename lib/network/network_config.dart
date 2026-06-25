// lib/network/network_config.dart
//
// Configuration réseau de StreetPhare — Version PRODUCTION No-IP.
//
// Centralise TOUTES les URL de serveurs (principal + secours +
// relay) pour pointer exclusivement vers l'infrastructure de
// production.
//
//   Serveur Principal : http://adminServerUrl:3000
//   Serveur Backup   : http://adminServerUrl:3001
//   Relay WebSocket   : ws://adminServerUrl:3000/mesh
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

import 'package:flutter_streetphare/constants/app_constants.dart';

/// Configuration réseau résolue pour l'environnement courant.
class NetworkConfig {
  NetworkConfig._();

  // ---------------------------------------------------------------------------
  // Adresse No-IP de production
  // ---------------------------------------------------------------------------
  static final String _productionHost = AppStrings.adminServerUrl
      .replaceAll('http://', '')
      .replaceAll('https://', '')
      .split(':')
      .first;

  // ---------------------------------------------------------------------------
  // Constantes de ports
  // ---------------------------------------------------------------------------
  static const int _primaryPort = 3000;
  static const int _secondaryPort = 3001;

  /// Host de production (exposé pour le FailoverManager).
  static String get productionHost => _productionHost;

  /// Port principal (exposé pour le FailoverManager).
  static int get primaryPort => _primaryPort;

  /// Port secondaire (exposé pour le FailoverManager).
  static int get secondaryPort => _secondaryPort;

  // ---------------------------------------------------------------------------
  // Adresses RÉSEAU (mode PRODUCTION)
  // ---------------------------------------------------------------------------

  /// URL du serveur PRINCIPAL courant.
  ///
  /// Production : http://adminServerUrl:3000
  static String get primaryServer {
    return 'http://$_productionHost:$_primaryPort';
  }

  /// URL du serveur SECONDAIRE (secours).
  ///
  /// http://adminServerUrl:3001
  static String get initialSecondaryServer {
    return 'http://$_productionHost:$_secondaryPort';
  }

  /// URL du relay WebSocket (utilisé par `RelayMeshTransport`).
  ///
  /// ws://adminServerUrl:3000/mesh
  static String get relayUrl {
    return 'ws://$_productionHost:$_primaryPort/mesh';
  }

  /// URL WebSocket du relais d'administration serveur.
  ///
  /// ws://adminServerUrl:3000/admin
  static String get primaryUrl {
    return 'ws://$_productionHost:$_primaryPort/admin';
  }

  /// La clé maîtresse est désormais gérée par `KeyStoreService`
  /// (lib/core/security/keystore_service.dart). Elle est générée
  /// aléatoirement au premier lancement et stockée dans le keystore
  /// sécurisé de l'OS (Android Keystore / iOS Keychain).
  ///
  /// L'ancien getter `masterPassphrase` basé sur
  /// `String.fromEnvironment('STREETPHARE_MASTER_KEY')` est
  /// supprimé car il compilait la clé en dur dans le binaire.

  // ---------------------------------------------------------------------------
  // Helpers de debug
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Fallback local (NAT Hairpinning / Loopback)
  // ---------------------------------------------------------------------------
  //
  // Contexte : De nombreuses box internet bloquent le NAT Hairpinning,
  // empêchant l'application (exécutée sur le même PC que le serveur)
  // de résoudre `adminServerUrl` → IP publique → rebouclage local.
  //
  // Solution : Le FailoverManager tente automatiquement ces adresses
  // de fallback local lorsque la résolution No-IP échoue.

  /// URL locale du serveur PRINCIPAL (fallback loopback).
  ///
  /// http://127.0.0.1:3000
  static String get localhostPrimaryServer {
    return 'http://127.0.0.1:$_primaryPort';
  }

  /// URL locale du serveur SECONDAIRE (fallback loopback).
  ///
  /// http://127.0.0.1:3001
  static String get localhostSecondaryServer {
    return 'http://127.0.0.1:$_secondaryPort';
  }

  /// URL locale du relay WebSocket (fallback loopback).
  ///
  /// ws://127.0.0.1:3000/mesh
  static String get localhostRelayUrl {
    return 'ws://127.0.0.1:$_primaryPort/mesh';
  }

  /// URL locale WebSocket d'administration (fallback loopback).
  ///
  /// ws://127.0.0.1:3000/admin
  static String get localhostPrimaryUrl {
    return 'ws://127.0.0.1:$_primaryPort/admin';
  }

  /// Renvoie un résumé lisible de la configuration (à n'utiliser
  /// QUE dans des `debugPrint`). Ne jamais logger les secrets.
  static String describe() {
    return 'NetworkConfig{'
        'host=$_productionHost '
        'primary=$primaryServer '
        'secondary=$initialSecondaryServer '
        'relay=$relayUrl '
        'localhost_primary=$localhostPrimaryServer '
        'localhost_secondary=$localhostSecondaryServer'
        '}';
  }
}
