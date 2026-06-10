// lib/core/network/peer_counter_service.dart
//
// Compteur d'appareils proches ("HIVE") en fenêtre glissante.
//
// Responsabilité unique : exposer, à n'importe quel widget, le
// NOMBRE d'appareils distincts détectés par l'un des transports
// P2P (BLE / Wi-Fi / Relay) AU COURS DES 60 DERNIÈRES SECONDES.
//
// === Contrat de déduplication (anti-double-comptage) ===
//
// Chaque appareil émetteur est identifié par un `peerId` STABLE
// pendant la durée d'une session anonyme : c'est l'`ephemeralUserId`
// du pair distant (par exemple, l'EUID diffusé dans le paquet BLE).
//
// Le compteur n'incrémente la valeur que si un `peerId` ENTIÈREMENT
// NOUVEAU (jamais vu dans la fenêtre) est observé. Si le même
// `peerId` réapparaît, on met simplement à jour son timestamp
// `lastSeen` et le compteur NE BOUGE PAS.
//
// Implémentation :
//   * Une `Map<String, DateTime>` associe l'identifiant éphémère
//     d'un pair à la dernière fois qu'on l'a vu.
//   * Un `Timer` s'exécute toutes les secondes et PURGE toutes
//     les entrées dont le `lastSeen` est antérieur à `now - 60s`.
//   * Un `ValueNotifier<int>` expose le compte courant pour que
//     la couche UI puisse se reconstruire sans polling.
//
// Cette classe est délibérément isolée de la couche `network/`
// pour rester un service UI-level (la persistance des pairs dans
// `P2PMeshService` reste l'autorité métier, ce service-ci n'est
// qu'un agrégateur temporel pour le badge "Appareils proches").

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Service singleton : compte les pairs P2P vus dans la dernière
/// fenêtre glissante de 60 secondes.
class PeerCounterService extends ValueNotifier<int> {
  PeerCounterService._() : super(0);

  static final PeerCounterService instance = PeerCounterService._();

  /// Largeur de la fenêtre glissante (par défaut 60 s, comme
  /// spécifié dans la roadmap "HIVE counter").
  static const Duration windowSize = Duration(seconds: 60);

  /// Période du timer de purge (par défaut 1 s).
  static const Duration tickInterval = Duration(seconds: 1);

  /// Identifiant éphémère -> dernier timestamp observé.
  ///
  /// Clé = `peerId` STABLE pendant toute la durée de la session
  /// anonyme de l'émetteur (ex : son `ephemeralUserId`).
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  Timer? _ticker;
  bool _started = false;

  /// Démarre le ticker (idempotent). À appeler une fois, par
  /// exemple depuis `initState` du `MapScreen`.
  void start() {
    if (_started) return;
    _started = true;
    _ticker = Timer.periodic(tickInterval, (_) => _pruneAndEmit());
  }

  /// Enregistre l'observation d'un pair.
  ///
  /// **Règle anti-double-comptage** :
  ///   * Si [peerId] est **inconnu** dans la fenêtre → on l'ajoute
  ///     et le compteur augmente de 1.
  ///   * Si [peerId] est **déjà présent** → on met juste à jour
  ///     son timestamp `lastSeen` (rafraîchissement de la fenêtre)
  ///     et le compteur NE BOUGE PAS. Aucun doublon n'est créé.
  ///
  /// Le compteur exposé par ce service reflète donc le **nombre
  /// d'UUID uniques** vus dans la fenêtre glissante, pas le
  /// **nombre de paquets reçus**.
  void recordPeer(String peerId) {
    if (peerId.isEmpty) return;
    final now = DateTime.now().toUtc();
    final previous = _lastSeen[peerId];
    _lastSeen[peerId] = now;
    if (previous == null) {
      // Nouveau pair (UUID jamais vu dans la fenêtre) : on MAJ
      // le compteur après purge des entrées expirées.
      value = _prune(now).length;
    }
    // Sinon : même pair, simple rafraîchissement du timestamp.
    // Le compteur reste inchangé → pas de doublon.
  }

  /// Variante batch : utile quand un transport nous remonte
  /// plusieurs pairs d'un coup (ex. fin d'un cycle de scan).
  ///
  /// Chaque identifiant est traité indépendamment par
  /// [recordPeer] : les doublons sont dédupliqués.
  void recordPeers(Iterable<String> peerIds) {
    final now = DateTime.now().toUtc();
    bool added = false;
    for (final id in peerIds) {
      if (id.isEmpty) continue;
      final prev = _lastSeen[id];
      _lastSeen[id] = now;
      if (prev == null) added = true;
    }
    if (added) {
      value = _prune(now).length;
    }
  }

  /// Purge manuelle (par ex. quand on perd la connexion réseau).
  void reset() {
    _lastSeen.clear();
    value = 0;
  }

  /// Renvoie la liste des identifiants actuellement dans la
  /// fenêtre (utile pour les tests / debug).
  List<String> get currentPeerIds => List.unmodifiable(_lastSeen.keys);

  /// Date de dernière observation d'un pair (ou `null` s'il
  /// n'est pas dans la fenêtre). Utile pour le debug.
  DateTime? lastSeenOf(String peerId) => _lastSeen[peerId];

  /// Nettoie la map et MAJ la valeur.
  /// Retourne la liste des ids qui restent dans la fenêtre.
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
      // Pour conserver la fréquence d'update stable, on émet
      // systématiquement (ValueNotifier déduplique via ==
      // seulement, donc c'est un no-op visuel).
      notifyListeners();
    }
  }

  /// À appeler au démontage (par ex. `dispose` du `MapScreen`).
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _started = false;
    _lastSeen.clear();
    value = 0;
  }
}
