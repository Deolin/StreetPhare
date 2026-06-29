// lib/network/transports/loopback_transport.dart
//
// Transport MAILLÉ en boucle locale (loopback) EXCLUSIVEMENT pour le
// mode DEBUG sur le Web.
//
// ⚠️  CE TRANSPORT NE DOIT JAMAIS ÊTRE INSTANCIÉ EN PRODUCTION. ⚠️
//
// Il est protégé par trois niveaux de garde :
//   1. `bootstrap.dart` : instanciation conditionnelle (`kIsWeb && kDebugMode`).
//   2. Ce fichier : assertion dans le constructeur qui empêche toute
//      instanciation hors debug mode.
//   3. `injectPacket()` : vérifie `kDebugMode` avant chaque injection.
//
// Sur le Web, les transports physiques (BLE, Wi‑Fi Direct) ne sont
// pas disponibles.  Ce transport purement logiciel joue le rôle de
// « réseau local simulé » pour le panneau d'administration sandbox :
//
//   * Expose `injectPacket(Map<String,dynamic>)` qui permet au panneau
//     d'administration d'injecter des alertes simulées.
//   * Chaque paquet injecté est ré-émis dans le flux `incoming` comme
//     s'il provenait d'un pair BLE ou Wi‑Fi Direct.
//
// Ce transport n'importe AUCUNE dépendance native (ni `dart:io`,
// ni plugin BLE/Wi‑Fi), ce qui garantit qu'il compile sur Chrome.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../p2p_mesh_service.dart';

/// Transport maillé en boucle locale — DEBUG WEB UNIQUEMENT.
///
/// Injectez des paquets simulés via [injectPacket] ; ils seront
/// reçus par le `P2PMeshService` comme n'importe quel paquet P2P.
///
/// Pour connecter ce transport au backend sandbox Node.js, utilisez
/// le `SandboxController` (lib/features/sandbox/) qui gère le
/// WebSocket vers `ws://localhost:4000/sandbox`.
///
/// ---
/// **Garde anti-production** : ce constructeur lève une [AssertionError]
/// si `kDebugMode` est `false`. Cela garantit que le transport ne peut
/// JAMAIS être instancié dans un build release (Android/iOS/Web release).
/// ---
class LoopbackMeshTransport implements MeshTransport {
  LoopbackMeshTransport({String? peerId})
      : assert(
          kDebugMode,
          'LoopbackMeshTransport NE DOIT PAS être instancié en mode release. '
          'Il est réservé au mode DEBUG sur le Web.',
        ),
        _peerId =
            peerId ?? 'sp-loopback-${DateTime.now().millisecondsSinceEpoch}';

  // ignore: unused_field
  // _peerId is used for debug logging and identity tracking in sandbox mode.
  String get peerId => _peerId;
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
  ///
  /// En dehors du mode DEBUG, cette méthode est un no-op silencieux
  /// (garde de sécurité supplémentaire).
  void injectPacket(Map<String, dynamic> packet) {
    if (!kDebugMode) return; // Garde de sécurité : no-op en release.

    try {
      final raw = const JsonEncoder().convert(packet);
      _incomingController.add(raw);
      debugPrint(
        '[LoopbackTransport] paquet sandbox injecté : '
        '${packet['kind'] ?? 'unknown'}',
      );
    } catch (e) {
      debugPrint('[LoopbackTransport] erreur sérialisation : $e');
    }
  }

  // ── MeshTransport ────────────────────────────────────────────────────────

  @override
  String get name => 'Loopback (Web Sandbox)';

  @override
  bool get isAvailable => kDebugMode; // Uniquement en debug.

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
    // Pas de broadcast réel : ce transport est unidirectionnel
    // (injection uniquement). Le relay WebSocket s'occupe de la
    // diffusion réelle.
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
