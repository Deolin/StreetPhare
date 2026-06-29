// lib/network/network_config.dart
//
// Configuration réseau de StreetPhare — Version PRODUCTION HTTPS/WSS.
//
// Centralise TOUTES les URL de serveurs (principal + secours +
// relay) pour pointer exclusivement vers l'infrastructure de
// production sécurisée.
//
//   Serveur Principal : https://streetphare.ddns.net:3000
//   Serveur Backup   : https://streetphare.ddns.net:3001
//   Relay WebSocket   : wss://streetphare.ddns.net:3000/mesh
//
// NOTE DE SÉCURITÉ : Les fallbacks locaux (127.0.0.1 / 10.0.2.2)
// utilisent HTTP/WS car ils ne traversent jamais le réseau public.
// Ces adresses de loopback sont isolées à la machine locale et ne
// présentent pas de risque d'interception réseau.
//
// Ce fichier est consommé par :
//   * lib/main.dart            -> valeurs passées à buildNetworkBootstrap
//   * lib/network/bootstrap.dart -> déjà branché en conséquence
//   * potentiellement d'autres clients HTTP de l'app
//
// IMPORTANT : ne JAMAIS hardcoder d'URL ailleurs dans l'app.
// Toujours importer 'network_config.dart' pour rester cohérent.

import 'package:flutter/foundation.dart';
import 'package:flutter_streetphare/constants/app_constants.dart';

/// Configuration réseau résolue pour l'environnement courant.
class NetworkConfig {
  NetworkConfig._();

  // ---------------------------------------------------------------------------
  // Adresse No-IP de production
  // ---------------------------------------------------------------------------
  static final String _productionHost = AppStrings.adminServerUrl
      .replaceAll('https://', '')
      .replaceAll('http://', '')
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
  // Adresses RÉSEAU (mode PRODUCTION — HTTPS/WSS)
  // ---------------------------------------------------------------------------

  /// URL du serveur PRINCIPAL courant.
  ///
  /// Production : https://streetphare.ddns.net:3000
  static String get primaryServer {
    return 'https://$_productionHost:$_primaryPort';
  }

  /// URL du serveur SECONDAIRE (secours).
  ///
  /// https://streetphare.ddns.net:3001
  static String get initialSecondaryServer {
    return 'https://$_productionHost:$_secondaryPort';
  }

  /// URL du relay WebSocket (utilisé par `RelayMeshTransport`).
  ///
  /// wss://streetphare.ddns.net:3000/mesh
  static String get relayUrl {
    return 'wss://$_productionHost:$_primaryPort/mesh';
  }

  /// URL WebSocket du relais d'administration serveur.
  ///
  /// wss://streetphare.ddns.net:3000/admin
  static String get primaryUrl {
    return 'wss://$_productionHost:$_primaryPort/admin';
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
  // Fallback local (NAT Hairpinning / Loopback)
  // ---------------------------------------------------------------------------
  //
  // Contexte : De nombreuses box internet bloquent le NAT Hairpinning,
  // empêchant l'application (exécutée sur le même PC que le serveur)
  // de résoudre `streetphare.ddns.net` → IP publique → rebouclage local.
  // Sur Android (émulateur ou device en debug USB), 127.0.0.1 pointe
  // vers l'appareil lui-même, pas vers le PC hôte. L'émulateur expose
  // le PC hôte via 10.0.2.2.
  //
  // NOTE DE SÉCURITÉ : Les adresses de loopback (127.0.0.1, 10.0.2.2)
  // utilisent HTTP/WS car le trafic ne quitte JAMAIS la machine locale.
  // Aucun risque d'interception réseau sur ces adresses. Le certificat
  // TLS n'est pas nécessaire pour les communications intra-machine.
  //
  // Solution : Le FailoverManager tente automatiquement ces adresses
  // de fallback local lorsque la résolution No-IP échoue.

  /// Adresse locale de fallback (dépend de la plateforme).
  ///
  /// - Android émulateur → 10.0.2.2 (le port 10.0.2.2 du PC hôte)
  /// - Toutes autres plateformes → 127.0.0.1
  static String get _localFallbackHost {
    if (kIsWeb) return '127.0.0.1';
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // En mode debug sur Android, l'émulateur ou le device USB
        // peut contacter le PC hôte via 10.0.2.2 (émulateur) ou
        // l'IP de la passerelle USB (192.168.x.x). 10.0.2.2 est
        // le standard émulateur Android. Pour un device physique,
        // l'utilisateur doit configurer l'IP de son serveur dans
        // les constantes.
        return '10.0.2.2';
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// URL locale du serveur PRINCIPAL (fallback loopback — DEBUG UNIQUEMENT).
  ///
  /// http://127.0.0.1:3000 ou http://10.0.2.2:3000 sur Android
  ///
  /// Cette URL n'utilise PAS HTTPS car le trafic reste confiné à
  /// la machine locale (loopback). Aucune interception réseau possible.
  static String get localhostPrimaryServer {
    return 'http://$_localFallbackHost:$_primaryPort';
  }

  /// URL locale du serveur SECONDAIRE (fallback loopback — DEBUG UNIQUEMENT).
  ///
  /// http://127.0.0.1:3001 ou http://10.0.2.2:3001 sur Android
  static String get localhostSecondaryServer {
    return 'http://$_localFallbackHost:$_secondaryPort';
  }

  /// URL locale du relay WebSocket (fallback loopback — DEBUG UNIQUEMENT).
  ///
  /// ws://127.0.0.1:3000/mesh ou ws://10.0.2.2:3000/mesh
  static String get localhostRelayUrl {
    return 'ws://$_localFallbackHost:$_primaryPort/mesh';
  }

  /// URL locale WebSocket d'administration (fallback loopback — DEBUG UNIQUEMENT).
  ///
  /// ws://127.0.0.1:3000/admin ou ws://10.0.2.2:3000/admin
  static String get localhostPrimaryUrl {
    return 'ws://$_localFallbackHost:$_primaryPort/admin';
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