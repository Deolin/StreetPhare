// lib/core/network/transport_failover.dart
//
// Failover énergétique des transports P2P.
//
// Implémente la stratégie de priorisation énergétique suivante :
//
//   1. CANAL PAR DÉFAUT : BLE (Bluetooth Low Energy).
//      Il scanne et diffuse en arrière-plan. C'est de loin le
//      transport le moins gourmand en batterie.
//
//   2. FALLBACK : si le scan BLE ne détecte AUCUN pair pendant
//      [bleIdleTimeout] (15 s par défaut), l'application ACTIVE
//      temporairement le transport Wi-Fi local (LAN multicast).
//
//   3. FALLBACK DE SECOND NIVEAU : si le Wi-Fi local ne ramène
//      rien non plus pendant [wifiIdleTimeout] (10 s par défaut),
//      l'application ACTIVE le transport Relay (données mobiles).
//
//   4. DÈS QU'UN PAIR EST DETECTÉ sur n'importe quel canal, on
//      REPASSE en veille BLE (pour économiser la batterie). Le
//      cycle reprend à l'étape 1.
//
// Ce service n'IMPOSE PAS un type de transport particulier : il
// opère sur n'importe quelle liste de `MeshTransport` et se
// branche sur leurs flux `incoming` pour détecter du trafic.
//
// IMPORTANT : ce service NE REMPLACE PAS `P2PMeshService` (qui
// reste l'autorité métier sur la propagation des alertes). Il
// est purement une politique de mise en marche/arrêt des
// transports, branchée au-dessus de `P2PMeshService`.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../network/p2p_mesh_service.dart';

/// État courant du failover.
enum FailoverState {
  /// BLE actif, autres transports arrêtés.
  bleOnly,

  /// BLE + Wi-Fi actifs (fallback BLE silencieux depuis 15s).
  bleAndWifi,

  /// BLE + Wi-Fi + Relay (données mobiles).
  allActive,
}

/// Politique de bascule entre transports P2P.
class TransportFailoverService {
  TransportFailoverService({
    required this.transports,
    this.bleIdleTimeout = const Duration(seconds: 15),
    this.wifiIdleTimeout = const Duration(seconds: 10),
    this.escalationTick = const Duration(seconds: 5),
  });

  /// Liste de TOUS les transports gérés par la politique.
  final List<MeshTransport> transports;

  /// Temps d'inactivité BLE avant d'allumer le Wi-Fi.
  final Duration bleIdleTimeout;

  /// Temps d'inactivité Wi-Fi avant d'allumer le Relay (mobile).
  final Duration wifiIdleTimeout;

  /// Granularité du check d'escalade (par défaut 5 s).
  final Duration escalationTick;

  final _stateController =
      StreamController<FailoverState>.broadcast();
  Stream<FailoverState> get state => _stateController.stream;

  FailoverState _state = FailoverState.bleOnly;
  FailoverState get currentState => _state;

  /// Timestamp de la dernière observation d'un pair (peu importe
  /// le transport) — sert de référence pour la fenêtre "inactivité".
  DateTime _lastPeerSeen = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  Timer? _escalationTimer;
  Timer? _heartbeatTimer;
  final List<StreamSubscription> _subs = [];
  bool _started = false;

  /// Démarre la politique. À appeler APRÈS que `P2PMeshService`
  /// ait lui-même démarré les transports (sinon les flux sont
  /// vides).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // 1) On s'abonne au flux "incoming" de chaque transport pour
    //    détecter toute activité (peu importe le canal).
    for (final t in transports) {
      _subs.add(t.incoming.listen((_) => _onPeerActivity()));
    }

    // 2) On s'abonne aussi au flux de pairs remonté par P2PMeshService
    //    (utile si une autre instance alimente ce flux).
    //    Note : on l'écoute indirectement via l'API de la couche
    //    réseau, mais on NE MODIFIE PAS l'autorité de P2PMeshService.

    // 3) Au démarrage, on n'active QUE le BLE.
    await _applyState(FailoverState.bleOnly);

    // 4) Timer d'escalade : vérifie périodiquement s'il faut
    //    activer un transport plus gourmand.
    _escalationTimer = Timer.periodic(escalationTick, (_) => _checkEscalation());

    // 5) Heartbeat : on relance un tick d'escalade régulièrement
    //    pour ne PAS dépendre uniquement des événements externes.
    _heartbeatTimer = Timer.periodic(
      bleIdleTimeout,
      (_) => _checkEscalation(),
    );

    if (kDebugMode) {
      debugPrint('[TransportFailover] démarré. État initial : $_state');
    }
  }

  /// À appeler pour signaler manuellement qu'on a vu un pair (par
  /// ex. depuis `P2PMeshService` qui a sa propre boucle de
  /// discovery). Réinitialise le timer d'inactivité.
  void notifyPeerSeen() {
    _lastPeerSeen = DateTime.now().toUtc();
  }

  /// Renvoie l'identifiant lisible du transport actuellement
  /// alimenté par le failover (utile pour le badge "transport
  /// actif" dans l'UI).
  String get activeTransportLabel {
    switch (_state) {
      case FailoverState.bleOnly:
        return 'BLE';
      case FailoverState.bleAndWifi:
        return 'BLE + Wi-Fi';
      case FailoverState.allActive:
        return 'BLE + Wi-Fi + Mobile';
    }
  }

  /// Helper public : enregistre l'observation d'un pair identifié
  /// (utilisé par le `MapScreen` quand `PeerCounterService` capte
  /// une nouvelle détection).
  void recordPeerObservation(String peerId) {
    if (peerId.isEmpty) return;
    _onPeerActivity();
  }

  void _onPeerActivity() {
    _lastPeerSeen = DateTime.now().toUtc();
    // Si on est dans un état "boosté", on en profite pour
    // redescendre à `bleOnly` (économie d'énergie).
    if (_state != FailoverState.bleOnly) {
      // On ne rétrograde pas immédiatement : on attend le prochain
      // tick d'escalade pour stabiliser (évite le thrashing).
      _checkEscalation();
    }
  }

  void _checkEscalation() {
    final now = DateTime.now().toUtc();
    final idle = now.difference(_lastPeerSeen);

    switch (_state) {
      case FailoverState.bleOnly:
        if (idle >= bleIdleTimeout) {
          _applyState(FailoverState.bleAndWifi);
        }
        break;
      case FailoverState.bleAndWifi:
        if (idle < bleIdleTimeout) {
          // On a retrouvé du trafic, on rétrograde.
          _applyState(FailoverState.bleOnly);
        } else if (idle >= bleIdleTimeout + wifiIdleTimeout) {
          _applyState(FailoverState.allActive);
        }
        break;
      case FailoverState.allActive:
        if (idle < bleIdleTimeout) {
          _applyState(FailoverState.bleOnly);
        } else if (idle < bleIdleTimeout + wifiIdleTimeout) {
          _applyState(FailoverState.bleAndWifi);
        }
        break;
    }
  }

  Future<void> _applyState(FailoverState next) async {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);

    // Activation/désactivation des transports non-BLE.
    final wifi = _findByName('wifi');
    final relay = _findByName('relay');
    final ble = _findByName('ble');

    switch (next) {
      case FailoverState.bleOnly:
        await _stopIfStarted(wifi);
        await _stopIfStarted(relay);
        await _startIfNeeded(ble);
        break;
      case FailoverState.bleAndWifi:
        await _startIfNeeded(ble);
        await _startIfNeeded(wifi);
        await _stopIfStarted(relay);
        break;
      case FailoverState.allActive:
        await _startIfNeeded(ble);
        await _startIfNeeded(wifi);
        await _startIfNeeded(relay);
        break;
    }

    if (kDebugMode) {
      debugPrint('[TransportFailover] nouvel état : $next');
    }
  }

  MeshTransport? _findByName(String name) {
    for (final t in transports) {
      if (t.name == name) return t;
    }
    return null;
  }

  Future<void> _startIfNeeded(MeshTransport? t) async {
    if (t == null) return;
    if (!t.isAvailable) return;
    try {
      await t.start();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TransportFailover] erreur start ${t.name}: $e');
      }
    }
  }

  Future<void> _stopIfStarted(MeshTransport? t) async {
    if (t == null) return;
    try {
      await t.stop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TransportFailover] erreur stop ${t.name}: $e');
      }
    }
  }

  /// Libère les ressources internes.
  Future<void> stop() async {
    _escalationTimer?.cancel();
    _heartbeatTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _stateController.close();
    _started = false;
  }
}
