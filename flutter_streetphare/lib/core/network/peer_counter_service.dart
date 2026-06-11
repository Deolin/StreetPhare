// lib/core/network/peer_counter_service.dart
//
// Compteur d'appareils proches ("HIVE") en fenêtre glissante.
//
// === Filtre Strict BLE StreetPhare ===
//
// À partir de la v1.2, le compteur n'incrémente le score QUE si
// l'appareil distant signale la signature de service BLE spécifique
// à StreetPhare :
//
//   UUID de service BLE : "STREET-PHARE-HIVE-SVC-0001"
//
// Cette signature est diffusée dans le payload d'advertisement BLE
// par le transport [P2PMeshService]. Un appareil Bluetooth générique
// ou une autre application ne corresponde PAS et n'est pas compté.
//
// === Contrat de déduplication (anti-double-comptage) ===
//
// Chaque appareil StreetPhare est identifié par un `peerId` STABLE
// pendant la durée d'une session anonyme (son `ephemeralUserId`).
// Le compteur n'incrémente que si un `peerId` ENTIÈREMENT NOUVEAU
// est observé avec la signature StreetPhare valide.

import 'dart:async';

import 'package:flutter/foundation.dart';

// ============================================================================
// Constantes de signature BLE StreetPhare
// ============================================================================

/// UUID de service BLE exclusif à StreetPhare.
/// Seuls les appareils diffusant cet UUID dans leur advertisement
/// seront comptés par [PeerCounterService].
///
/// Ce UUID doit correspondre à la valeur configurée dans [P2PMeshService]
/// (transport BLE) côté émetteur.
const String kStreetPhareBleServiceUuid = 'STREET-PHARE-HIVE-SVC-0001';

/// Préfixe attendu dans le `metadata` ou `serviceId` d'un pair pour
/// que ce pair soit considéré comme un appareil StreetPhare authentique.
const String kStreetPhareSignaturePrefix = 'SP_HIVE_';

// ============================================================================
// PeerCounterService
// ============================================================================

/// Service singleton : compte les pairs P2P StreetPhare vus dans la dernière
/// fenêtre glissante de 60 secondes.
///
/// Filtre strict : seuls les pairs ayant passé [isStreetPharePeer] = true
/// sont comptabilisés. Les appareils Bluetooth génériques et les autres
/// applications sont ignorés.
class PeerCounterService extends ValueNotifier<int> {
  PeerCounterService._() : super(0);

  static final PeerCounterService instance = PeerCounterService._();

  /// Largeur de la fenêtre glissante (60 s).
  static const Duration windowSize = Duration(seconds: 60);

  /// Période du timer de purge (1 s).
  static const Duration tickInterval = Duration(seconds: 1);

  /// Identifiant éphémère → dernier timestamp observé.
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  Timer? _ticker;
  bool _started = false;

  // --------------------------------------------------------------------------
  // Validation de la signature StreetPhare
  // --------------------------------------------------------------------------

  /// Vérifie qu'un pair correspond à un appareil exécutant StreetPhare.
  ///
  /// Règles de validation (ANY des conditions suffit) :
  ///   1. [serviceUuid] correspond à [kStreetPhareBleServiceUuid].
  ///   2. [metadata] commence par [kStreetPhareSignaturePrefix].
  ///   3. [peerId] commence par [kStreetPhareSignaturePrefix] (mode demo/test).
  ///
  /// En mode DEBUG, un pair dont le [peerId] commence par "demo_" est
  /// toujours accepté pour faciliter les tests de l'interface.
  static bool isStreetPharePeer({
    required String peerId,
    String? serviceUuid,
    String? metadata,
  }) {
    // Mode demo (DEBUG uniquement) : injection de faux pairs pour l'UI.
    if (kDebugMode && peerId.startsWith('demo_')) return true;

    // Validation par UUID de service BLE.
    if (serviceUuid != null &&
        serviceUuid.toUpperCase() == kStreetPhareBleServiceUuid) {
      return true;
    }

    // Validation par métadonnée de payload.
    if (metadata != null &&
        metadata.startsWith(kStreetPhareSignaturePrefix)) {
      return true;
    }

    // Validation par préfixe d'ID (convention interne des transports StreetPhare).
    if (peerId.startsWith(kStreetPhareSignaturePrefix)) return true;

    return false;
  }

  // --------------------------------------------------------------------------
  // Cycle de vie
  // --------------------------------------------------------------------------

  /// Démarre le ticker (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    _ticker = Timer.periodic(tickInterval, (_) => _pruneAndEmit());
  }

  // --------------------------------------------------------------------------
  // Enregistrement d'un pair
  // --------------------------------------------------------------------------

  /// Enregistre l'observation d'un pair StreetPhare.
  ///
  /// [peerId] : identifiant éphémère du pair.
  /// [serviceUuid] : UUID de service BLE annoncé par ce pair (optionnel).
  /// [metadata] : payload / métadonnée associée (optionnel).
  ///
  /// Le pair n'est comptabilisé QUE s'il passe la validation
  /// [isStreetPharePeer]. Les autres appareils sont silencieusement ignorés.
  void recordPeer(
    String peerId, {
    String? serviceUuid,
    String? metadata,
  }) {
    if (peerId.isEmpty) return;

    // ── Filtre strict : signature StreetPhare requise ──────────────────────
    if (!isStreetPharePeer(
      peerId: peerId,
      serviceUuid: serviceUuid,
      metadata: metadata,
    )) {
      if (kDebugMode) {
        debugPrint('[PeerCounter] ignoré (non-StreetPhare): $peerId');
      }
      return;
    }

    final now = DateTime.now().toUtc();
    final previous = _lastSeen[peerId];
    _lastSeen[peerId] = now;
    if (previous == null) {
      // Nouveau pair StreetPhare valide.
      value = _prune(now).length;
      if (kDebugMode) {
        debugPrint('[PeerCounter] nouveau pair StreetPhare: $peerId — total=$value');
      }
    }
    // Pair déjà connu : simple rafraîchissement du timestamp.
  }

  /// Variante batch : traite plusieurs pairs d'un coup.
  void recordPeers(
    Iterable<String> peerIds, {
    String? serviceUuid,
    String? metadata,
  }) {
    final now = DateTime.now().toUtc();
    bool added = false;
    for (final id in peerIds) {
      if (id.isEmpty) continue;
      if (!isStreetPharePeer(
        peerId: id,
        serviceUuid: serviceUuid,
        metadata: metadata,
      )) {
        continue; // Filtre strict
      }
      final prev = _lastSeen[id];
      _lastSeen[id] = now;
      if (prev == null) added = true;
    }
    if (added) {
      value = _prune(now).length;
    }
  }

  /// Purge manuelle.
  void reset() {
    _lastSeen.clear();
    value = 0;
  }

  /// Identifiants actuellement dans la fenêtre.
  List<String> get currentPeerIds => List.unmodifiable(_lastSeen.keys);

  /// Dernier timestamp d'observation d'un pair.
  DateTime? lastSeenOf(String peerId) => _lastSeen[peerId];

  /// Nettoie la map et retourne les IDs restants.
  List<String> _prune(DateTime now) {
    final cutoff = now.subtract(windowSize);
    _lastSeen.removeWhere((_, ts) => ts.isBefore(cutoff));
    return _lastSeen.keys.toList();
  }

  void _pruneAndEmit() {
    final now = DateTime.now().toUtc();
    final kept = _prune(now);
    final count = kept.length;
    if (count != value) {
      value = count;
    } else {
      notifyListeners();
    }
  }

  /// Arrêt propre du service.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _started = false;
    _lastSeen.clear();
    value = 0;
  }
}
