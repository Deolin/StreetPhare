// lib/network/transports/loopback_transport.dart
//
// Transport MAILLÉ en boucle locale (loopback) pour le Web.
//
// Sur le Web, les transports physiques (BLE, Wi‑Fi Direct) ne sont
// pas disponibles.  Ce transport purement logiciel joue le rôle de
// « réseau local simulé » :
//
//   * En mode **sandbox**, il expose un contrôleur public
//     `injectPacket(Map<String,dynamic>)` qui permet au panneau
//     d'administration d'injecter des alertes simulées.  Chaque
//     paquet injecté est ré-émis dans le flux `incoming` comme
//     s'il provenait d'un pair BLE ou Wi‑Fi Direct.
//
//   * En mode **production**, il reste inactif mais ne bloque rien
//     (isAvailable = true, start/stop immédiats sans erreur).
//
// Ce transport est instancié UNIQUEMENT quand `kIsWeb == true`
// (voir `lib/network/bootstrap.dart`).  Il n'importe AUCUNE
// dépendance native (ni `dart:io`, ni plugin BLE/Wi‑Fi), ce qui
// garantit qu'il compile et s'exécute sur Chrome sans erreur.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../p2p_mesh_service.dart';

/// Transport maillé en boucle locale – exclusivement Web.
///
/// Injectez des paquets simulés via [injectPacket] ; ils seront
/// reçus par le `P2PMeshService` comme n'importe quel paquet P2P.
///
/// Pour connecter ce transport au backend sandbox Node.js, utilisez
/// le `SandboxController` (lib/features/sandbox/) qui gère le
/// WebSocket vers `ws://localhost:4000/sandbox`.
class LoopbackMeshTransport implements MeshTransport {
  LoopbackMeshTransport({String? peerId})
      : _peerId = peerId ?? 'sp-loopback-${DateTime.now().millisecondsSinceEpoch}';

  final String _peerId;

  final _incomingController = StreamController<String>.broadcast();

  // ── API publique sandbox ─────────────────────────────────────────────────

  /// Injecte un paquet simulé dans le flux entrant du transport.
  ///
  /// [packet] doit être une Map sérialisable en JSON, typiquement
  /// avec une clé `"kind"` (`"alert"`, `"hive_p2p_message"`, etc.).
  ///
  /// Cette méthode est appelée par le panneau d'administration pour
  /// simuler des alertes P2P sans hardware physique.
  void injectPacket(Map<String, dynamic> packet) {
    try {
      final raw = const JsonEncoder().convert(packet);
      _incomingController.add(raw);
      if (kDebugMode) {
        debugPrint(
          '[LoopbackTransport] paquet sandbox injecté : '
          '${packet['kind'] ?? 'unknown'}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LoopbackTransport] erreur sérialisation : $e');
      }
    }
  }

  // ── MeshTransport ────────────────────────────────────────────────────────

  @override
  String get name => 'Loopback (Web Sandbox)';

  @override
  bool get isAvailable => true;

  @override
  Future<void> start() async {
    if (kDebugMode) {
      debugPrint('[LoopbackTransport] démarré – prêt pour la sandbox');
    }
  }

  @override
  Future<void> stop() async {
    if (kDebugMode) debugPrint('[LoopbackTransport] arrêté');
  }

  @override
  Future<void> broadcast(String payload) async {
    // Pas de broadcast réel (le relay s'en charge).
    if (kDebugMode) {
      final preview = payload.length > 80
          ? '${payload.substring(0, 80)}...'
          : payload;
      debugPrint('[LoopbackTransport] broadcast (ignoré) : $preview');
    }
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    // Non implémenté en loopback.
  }

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  void dispose() {
    _incomingController.close();
  }
}