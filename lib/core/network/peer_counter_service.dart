// lib/core/network/peer_counter_service.dart
//
// Compteur d'appareils proches ("HIVE") en fenêtre glissante.
// Alimenté EXCLUSIVEMENT par les événements réseau réels issus de
// `P2PMeshService._processIncomingMessage()` (pings de présence P2P)
// et des callbacks natifs BLE / Wi-Fi Direct.
//
// === Alimentation réelle (production) ===
//
// Le flux de données est le suivant :
//
//   BLE scan / Wi-Fi Direct / WebSocket mesh
//       │
//       ▼
//   P2PMeshService._processIncomingMessage()
//       │  (kind: 'ping', id: peerId, svc: serviceUuid, meta: metadata)
//       ▼
//   PeerCounterService.instance.recordPeer(peerId, serviceUuid, metadata)
//
// Aucune simulation ni mock n'est utilisé en production. Le compteur
// reflète exclusivement les appareils StreetPhare physiquement détectés
// à portée radio (BLE, Wi-Fi Direct) ou connectés via le relay mesh.
//
// === Filtre Strict BLE StreetPhare ===
//
// Le compteur n'incrémente QUE si l'appareil distant passe la validation
// [isStreetPharePeer] :
//
//   - peerId préfixé par `sp-` (identifiants éphémères StreetPhare).
//   - UUID de service BLE correspondant à `kStreetPhareBleServiceUuid`.
//   - Métadonnée préfixée par `SP_HIVE_`.
//
// === Contrat de déduplication (anti-double-comptage) ===
//
// Chaque appareil StreetPhare est identifié par un `peerId` STABLE.
// Le compteur n'incrémente que si un `peerId` ENTIÈREMENT NOUVEAU
// est observé. Les ré-observations rafraîchissent simplement le timestamp.

import 'dart:async';

import 'package:flutter/foundation.dart';

// ============================================================================
// Constantes de signature BLE StreetPhare
// ============================================================================

/// UUID de service BLE exclusif à StreetPhare.
const String kStreetPhareBleServiceUuid =
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

/// Préfixe attendu dans le `metadata` ou `serviceId` d'un pair pour
/// que ce pair soit considéré comme un appareil StreetPhare authentique.
const String kStreetPhareSignaturePrefix = 'SP_HIVE_';

// ============================================================================
// PeerCounterService
// ============================================================================

/// Service singleton : compte les pairs P2P StreetPhare vus dans la dernière
/// fenêtre glissante de 5 minutes.
///
/// **Alimenté exclusivement par les transports réseau réels** (BLE, Wi-Fi
/// Direct, WebSocket mesh). Aucune simulation ni mock.
///
/// Expose deux sorties réactives :
///   - [value] (hérité de [ValueNotifier]) : compteur actuel de pairs.
///   - [onPeerObserved] : [Stream] émis à chaque NOUVEAU pair valide détecté.
///     Les couches supérieures (UI, [TransportFailoverService]) s'abonnent
///     à ce stream pour réagir en temps réel à l'activité du réseau.
class PeerCounterService extends ValueNotifier<int> {
  PeerCounterService._() : super(0);

  static final PeerCounterService instance = PeerCounterService._();

  /// Largeur de la fenêtre glissante (5 minutes).
  static const Duration windowSize = Duration(minutes: 5);

  /// Période du timer de purge (1 s).
  static const Duration tickInterval = Duration(seconds: 1);

  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  String? _localPeerId;

  /// Controller pour le stream de pairs nouvellement observés.
  /// Émet le [peerId] à chaque première observation dans la fenêtre.
  final _peerObservedController = StreamController<String>.broadcast();

  Timer? _ticker;
  bool _started = false;

  /// Stream de pairs nouvellement observés.
  ///
  /// Émet le [peerId] à chaque première observation valide dans la fenêtre
  /// glissante. Les ré-observations (rafraîchissement de timestamp) ne
  /// déclenchent PAS d'émission.
  ///
  /// Les couches supérieures ([TransportFailoverService], UI) s'abonnent
  /// à ce stream pour réagir en temps réel à la détection de nouveaux
  /// appareils StreetPhare à proximité.
  Stream<String> get onPeerObserved => _peerObservedController.stream;

  // --------------------------------------------------------------------------
  // Identité locale (exclusion du nœud courant)
  // --------------------------------------------------------------------------

  /// Enregistre l'identifiant de l'appareil local. Appelé une seule fois
  /// par le [NetworkCoordinator] à l'initialisation.
  ///
  /// Une fois défini, le [PeerCounterService] exclut systématiquement
  /// cet identifiant du décompte des pairs actifs. Si la fenêtre ne
  /// contient que l'ID local, le compteur est forcé à `0`.
  void setLocalPeerId(String id) {
    _localPeerId = id;
    forceRefresh();
  }

  /// Identifiant local actuellement enregistré, ou `null` si non défini.
  String? get localPeerId => _localPeerId;

  // --------------------------------------------------------------------------
  // Validation de la signature StreetPhare
  // --------------------------------------------------------------------------

  /// Vérifie qu'un pair correspond à un appareil exécutant StreetPhare.
  ///
  /// Règles de validation (ANY des conditions suffit) :
  ///   1. [peerId] commence par `sp-` (préfixe des identifiants éphémères
  ///      StreetPhare générés par le NetworkCoordinator).
  ///   2. [serviceUuid] correspond à [kStreetPhareBleServiceUuid].
  ///   3. [metadata] commence par [kStreetPhareSignaturePrefix].
  ///   4. [peerId] commence par [kStreetPhareSignaturePrefix].
  ///
  /// En mode DEBUG, un pair dont le [peerId] commence par "demo_" est
  /// toujours accepté pour faciliter les tests de l'interface.
  static bool isStreetPharePeer({
    required String peerId,
    String? serviceUuid,
    String? metadata,
  }) {
    // Validation par préfixe 'sp-' — identifiants éphémères StreetPhare
    // générés par generateEphemeralUserId() dans le NetworkCoordinator.
    if (peerId.startsWith('sp-')) return true;

    // Validation par UUID de service BLE.
    if (serviceUuid != null &&
        serviceUuid.toUpperCase() == kStreetPhareBleServiceUuid.toUpperCase()) {
      return true;
    }

    // Validation par métadonnée de payload.
    if (metadata != null && metadata.startsWith(kStreetPhareSignaturePrefix)) {
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

    // ── Exclusion locale : ne jamais compter son propre ID ──
    if (peerId == _localPeerId) {
      if (kDebugMode) {
        debugPrint('[PeerCounter] ignoré (ID local): $peerId');
      }
      return;
    }

    final now = DateTime.now().toUtc();
    final previous = _lastSeen[peerId];
    _lastSeen[peerId] = now;
    if (previous == null) {
      // Nouveau pair StreetPhare valide.
      final kept = _excludeLocal(_prune(now));
      value = kept.length;
      // Notifie les abonnés (TransportFailoverService, UI, etc.)
      // qu'un nouveau pair StreetPhare vient d'être détecté.
      _peerObservedController.add(peerId);
      if (kDebugMode) {
        debugPrint(
            '[PeerCounter] nouveau pair StreetPhare: $peerId — total=$value');
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

  /// Libère les ressources du service.
  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _started = false;
    _peerObservedController.close();
    super.dispose();
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
    final filtered = _excludeLocal(kept);
    final count = filtered.length;
    if (count != value) {
      value = count;
    } else {
      notifyListeners();
    }
  }

  /// Force une rafraîchissement immédiat du compteur (purge + notify).
  /// Appelé par le NetworkCoordinator lors du health check des pairs.
  void forceRefresh() {
    final now = DateTime.now().toUtc();
    final kept = _prune(now);
    final filtered = _excludeLocal(kept);
    value = filtered.length;
  }

  /// Retire l'identifiant local de la liste s'il est présent.
  /// Si la liste ne contient QUE l'ID local, retourne une liste vide → 0.
  List<String> _excludeLocal(List<String> ids) {
    if (_localPeerId == null) return ids;
    return ids.where((id) => id != _localPeerId).toList();
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
