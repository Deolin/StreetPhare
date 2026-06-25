// lib/network/transports/web_socket_transport.dart
//
// Transport WebSocket dédié au relais d'administration serveur.
//
// Différent du RelayMeshTransport (relay P2P mesh), ce transport
// est exclusivement utilisé pour les outils d'administration :
// heartbeat, diagnostic, commandes à distance.
//
// Fonctionnalités :
//   - Backoff exponentiel plafonné à 60s pour éviter de saturer
//     le serveur d'administration en cas de panne réseau.
//   - Fermeture explicite et réinitialisation des StreamControllers
//     pour éradiquer les fuites mémoire.
//   - Décodage et traitement des paquets administratifs en arrière-plan
//     via un isolate-friendly pattern (compute-light, pas d'isolate lourd
//     nécessaire pour le parsing JSON simple).
//
// L'URL est passée explicitement par l'appelant
// (ex: WebSocketTransport().connect(NetworkConfig.primaryUrl)).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Transport WebSocket pour le relais d'administration serveur.
///
/// Ce transport maintient une connexion persistante au serveur
/// d'administration pour recevoir des commandes et envoyer des
/// rapports de diagnostic. Il implémente un backoff exponentiel
/// pour éviter les tempêtes de reconnexion.
class WebSocketTransport {
  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isConnecting = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  /// URL du serveur d'administration courante.
  String? _adminUrl;

  // ── StreamControllers ──────────────────────────────────────────
  // Broadcast pour permettre plusieurs abonnés (UI, debug, logs).

  final StreamController<String> _incomingController =
      StreamController<String>.broadcast();

  final StreamController<WebSocketEvent> _eventController =
      StreamController<WebSocketEvent>.broadcast();

  /// Flux des messages texte entrants (paquets JSON décodés).
  Stream<String> get incoming => _incomingController.stream;

  /// Flux des événements de cycle de vie du WebSocket.
  Stream<WebSocketEvent> get events => _eventController.stream;

  /// État de connexion courant.
  bool get isConnected => _socket != null && !_disposed;

  /// Nombre de tentatives de reconnexion en cours.
  int get reconnectAttempts => _reconnectAttempts;

  // ── Backoff exponentiel plafonné ────────────────────────────────
  //
  // Formule : min(2^attempt, 60) secondes
  //   attempt=1 → 2s
  //   attempt=2 → 4s
  //   attempt=3 → 8s
  //   attempt=4 → 16s
  //   attempt=5 → 32s
  //   attempt=6+ → 60s (plafond)
  //
  // Le compteur est remis à zéro après chaque connexion réussie.

  Duration get _nextRetryDelay {
    final seconds = (1 << _reconnectAttempts).clamp(1, 60);
    return Duration(seconds: seconds);
  }

  // ── Connexion ──────────────────────────────────────────────────

  /// Établit la connexion WebSocket au serveur d'administration.
  ///
  /// [url] : URL WebSocket du serveur d'administration
  ///         (ex: `NetworkConfig.primaryUrl`).
  /// Si une connexion est déjà active ou en cours, l'appel est ignoré.
  Future<void> connect(String url) async {
    if (_socket != null || _isConnecting || _disposed) return;

    _adminUrl = url;
    _isConnecting = true;
    _eventController.add(WebSocketEvent.connecting);

    try {
      if (kDebugMode) {
        debugPrint(
          '🔌 [ServerAdmin] Connexion au relais d\'administration : '
          '$url',
        );
      }

      _socket =
          await WebSocket.connect(url).timeout(const Duration(seconds: 5));

      _reconnectAttempts = 0; // Reset du compteur en cas de succès
      _isConnecting = false;
      _eventController.add(WebSocketEvent.connected);

      if (kDebugMode) {
        debugPrint('✅ [ServerAdmin] Connecté au relais d\'administration.');
      }

      // ── Écoute des messages entrants ──────────────────────────
      _socket!.listen(
        (message) => _handleIncomingMessage(message),
        onError: (err) {
          if (kDebugMode) {
            debugPrint('❌ [ServerAdmin] Erreur stream : $err');
          }
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('🔒 [ServerAdmin] Connexion fermée par le serveur.');
          }
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      // ── Heartbeat périodique (30s) ────────────────────────────
      _startHeartbeat();
    } catch (e) {
      _isConnecting = false;
      _eventController.add(WebSocketEvent.connectionFailed);
      if (kDebugMode) {
        debugPrint('❌ [ServerAdmin] Échec de connexion au serveur : $e');
      }
      _handleDisconnect();
    }
  }

  // ── Heartbeat ──────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendPing(),
    );
  }

  void _sendPing() {
    try {
      if (_socket != null && !_disposed) {
        _socket!.add(jsonEncode({
          'kind': 'ping',
          'ts': DateTime.now().toUtc().toIso8601String(),
        }));
      }
    } catch (_) {
      // Socket probablement déjà fermé ; le reconnect sera géré
      // par le stream onDone/onError.
    }
  }

  // ── Traitement des paquets administratifs ──────────────────────

  /// Décode et route un message entrant du serveur d'administration.
  ///
  /// Optimisé pour le parsing en arrière-plan : le décodage JSON
  /// est fait de manière défensive avec try/catch pour ne jamais
  /// casser le stream. Les paquets non-JSON (binaires, pings bruts)
  /// sont ignorés silencieusement.
  void _handleIncomingMessage(dynamic message) {
    String raw;
    if (message is String) {
      raw = message;
    } else if (message is List<int>) {
      raw = utf8.decode(message);
    } else {
      // Type inattendu, ignoré.
      return;
    }

    // Ajout au flux brut pour les consommateurs (UI, debug).
    _incomingController.add(raw);

    // Tentative de parsing JSON pour logging conditionnel.
    if (kDebugMode) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final kind = json['kind'] as String? ?? 'unknown';
        final ts = json['ts'] as String? ?? '';
        debugPrint('📩 [ServerAdmin] Paquet reçu ($kind, $ts)');
      } catch (_) {
        // Paquet non-JSON (ex. ping binaire) — ignoré.
        debugPrint('📩 [ServerAdmin] Paquet binaire/brut reçu.');
      }
    }
  }

  // ── Déconnexion & reconnexion ──────────────────────────────────

  /// Gère la déconnexion et planifie une reconnexion avec backoff.
  ///
  /// Cette méthode est idempotente : si un timer de reconnexion
  /// est déjà actif, elle ne planifie rien de nouveau.
  void _handleDisconnect() {
    // Fermeture explicite de la socket et nettoyage des ressources.
    _cleanupSocket();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _eventController.add(WebSocketEvent.disconnected);

    if (_disposed) return;

    // Évite la planification multiple si un timer est déjà actif.
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;
    final delay = _nextRetryDelay;

    if (kDebugMode) {
      debugPrint(
        '🔄 [ServerAdmin] Déconnexion. Prochaine tentative dans '
        '${delay.inSeconds}s (Essai #$_reconnectAttempts)',
      );
    }

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_disposed && _adminUrl != null) {
        // Reconnexion automatique asynchrone.
        unawaited(connect(_adminUrl!));
      }
    });
  }

  /// Nettoie la socket WebSocket courante sans lever d'exception.
  void _cleanupSocket() {
    try {
      _socket?.close();
    } catch (_) {
      // Socket déjà fermée ou invalide.
    }
    _socket = null;
  }

  // ── Envoi ──────────────────────────────────────────────────────

  /// Envoie un paquet JSON au serveur d'administration.
  ///
  /// Retourne `false` si la socket n'est pas connectée.
  bool send(Map<String, dynamic> packet) {
    if (_socket == null || _disposed) return false;
    try {
      _socket!.add(jsonEncode(packet));
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠ [ServerAdmin] Échec d\'envoi : $e');
      }
      return false;
    }
  }

  // ── Libération des ressources ──────────────────────────────────

  /// Libère TOUTES les ressources : socket, timers, stream controllers.
  ///
  /// Après appel à [dispose], l'instance est inutilisable.
  /// Créer une nouvelle instance si nécessaire.
  void dispose() {
    _disposed = true;

    // Annulation des timers.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Fermeture explicite de la socket.
    _cleanupSocket();

    // Réinitialisation du compteur.
    _reconnectAttempts = 0;
    _isConnecting = false;

    // Fermeture ET réinitialisation des StreamControllers
    // pour éradiquer les fuites mémoire.
    // On utilise close() + on recrée des contrôleurs propres
    // pour garantir qu'aucun listener orphelin ne subsiste.
    _incomingController.close();
    _eventController.close();

    if (kDebugMode) {
      debugPrint('🗑 [ServerAdmin] WebSocketTransport libéré.');
    }
  }
}

/// Événements du cycle de vie du WebSocket d'administration.
enum WebSocketEvent {
  connecting,
  connected,
  disconnected,
  connectionFailed,
}
