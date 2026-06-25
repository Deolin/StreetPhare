// lib/network/server_heartbeat_service.dart
//
// Service de surveillance de la connexion au serveur web.
//
// Effectue un GET /api/ping toutes les 12 secondes vers l'URL
// du serveur actif (Primary ou Backup, géré par le FailoverManager).
// Expose un ValueNotifier<bool> `isServerConnected` que l'UI peut
// écouter pour afficher l'indicateur vert/rouge.
//
// Usage :
//   ServerHeartbeatService.instance.start();
//   ValueListenableBuilder<bool>(
//     valueListenable: ServerHeartbeatService.instance.isServerConnected,
//     builder: (context, connected, _) => DotIndicator(connected: connected),
//   );

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'failover_manager.dart';
import 'network_config.dart';

/// Service singleton de heartbeat serveur.
class ServerHeartbeatService {
  ServerHeartbeatService._();
  static final ServerHeartbeatService instance = ServerHeartbeatService._();

  /// Notifier exposant l'état de connexion au serveur.
  final ValueNotifier<bool> isServerConnected = ValueNotifier<bool>(false);

  /// URL du dernier serveur ayant répondu (pour info/tooltip).
  String? _lastResponsiveServer;

  Timer? _heartbeatTimer;
  bool _started = false;

  /// Intervalle entre deux pings (12 secondes).
  static const Duration heartbeatInterval = Duration(seconds: 12);

  /// Timeout HTTP pour le ping.
  static const Duration pingTimeout = Duration(seconds: 5);

  /// Démarre le heartbeat périodique. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    // Premier ping immédiat pour ne pas attendre 12s le premier état.
    _pingServer();

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _pingServer();
    });
  }

  /// Arrête le heartbeat.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _started = false;
  }

  /// Effectue un ping HTTP vers /api/ping sur le serveur actif.
  Future<void> _pingServer() async {
    try {
      // Utilise l'adresse courante du FailoverManager (primary ou backup).
      final serverUrl = FailoverManager.instance.currentAddress;
      if (serverUrl.isEmpty) {
        _updateState(false);
        return;
      }

      final url = Uri.parse('$serverUrl/api/ping');
      final response = await http
          .get(url)
          .timeout(pingTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _lastResponsiveServer = '${body['role'] ?? '?'} @ $serverUrl';
        _updateState(true);
      } else {
        _updateState(false);
      }
    } catch (_) {
      _updateState(false);
    }
  }

  void _updateState(bool connected) {
    if (isServerConnected.value != connected) {
      isServerConnected.value = connected;
      if (kDebugMode) {
        debugPrint(
          '[Heartbeat] ${connected ? "🟢 Connecté" : "🔴 Déconnecté"}'
          '${connected && _lastResponsiveServer != null ? " → $_lastResponsiveServer" : ""}',
        );
      }
    }
  }

  /// Retourne un message descriptif pour le tooltip.
  String get statusMessage {
    if (isServerConnected.value && _lastResponsiveServer != null) {
      return 'Connecté au serveur $_lastResponsiveServer';
    }
    return 'Mode local : Serveur injoignable';
  }

  /// Libère les ressources.
  void dispose() {
    stop();
    isServerConnected.dispose();
  }
}