// lib/network/network_manager.dart
//
// Machine d'état de basculement réseau (Failover) par ordre de priorité.
//
// Orchestre la sélection automatique du meilleur transport disponible :
//   1. BLE P2P (Bluetooth Low Energy) — priorité absolue, décentralisé.
//   2. Wi-Fi Direct / P2P — réseau local sans Internet requis.
//   3. Cellular (3G/4G/5G) — relais Internet via serveur Node.js.
//
// Écoute en continu les indicateurs de santé réseau et bascule
// automatiquement dès qu'une priorité supérieure devient disponible.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/peer_counter_service.dart';
import '../services/connectivity_service.dart';
import 'failover_manager.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ordre de priorité des transports réseau.
/// Les valeurs sont classées par priorité décroissante (0 = meilleur).
enum NetworkTransport {
  /// Bluetooth Low Energy P2P — décentralisé, anonyme, sans Internet.
  ble,

  /// Wi-Fi Direct / P2P — réseau local, portée élargie.
  wifiDirect,

  /// Données mobiles (3G/4G/5G) — Internet requis, relais serveur.
  cellular,

  /// Aucun transport disponible — mode isolé.
  none,
}

/// État complet d'un transport réseau.
class TransportStatus {
  const TransportStatus({
    required this.type,
    required this.isAvailable,
    this.peerCount = 0,
    this.detail = '',
  });

  final NetworkTransport type;
  final bool isAvailable;
  final int peerCount;
  final String detail;

  /// Description lisible pour l'UI.
  String get label {
    switch (type) {
      case NetworkTransport.ble:
        return 'BLE P2P';
      case NetworkTransport.wifiDirect:
        return 'Wi-Fi Direct';
      case NetworkTransport.cellular:
        return 'Relais Internet';
      case NetworkTransport.none:
        return 'Aucun';
    }
  }
}

/// Service centralisé de gestion du réseau.
///
/// Machine d'état qui évalue en continu le meilleur transport
/// disponible selon la politique de priorité suivante :
///   BLE (pairs > 0) > Wi-Fi Direct > Internet > none.
///
/// Écoute [PeerCounterService], [ConnectivityService] et
/// [FailoverManager] pour réagir aux changements d'état.
class NetworkManager extends ChangeNotifier {
  NetworkManager._();
  static final NetworkManager instance = NetworkManager._();

  // ── État courant ──────────────────────────────────────────────────────────

  NetworkTransport _currentTransport = NetworkTransport.none;
  int _activeBlePeers = 0;
  bool _isWifiP2PAvailable = false;
  bool _hasInternet = false;

  bool _started = false;
  Timer? _evaluationTimer;
  Timer? _hardwareCheckTimer;

  /// État du matériel (Bluetooth / Wi-Fi) vérifié périodiquement.
  final Map<String, bool> _hardwareState = {
    'ble': true,
    'wifi': true,
  };

  // ── Getters publics ────────────────────────────────────────────────────────

  /// Transport actif courant.
  NetworkTransport get currentTransport => _currentTransport;

  /// Nombre de pairs BLE actifs.
  int get activeBlePeers => _activeBlePeers;

  /// Indique si un transport est disponible.
  bool get isConnected => _currentTransport != NetworkTransport.none;

  /// Indique si l'appareil est en mode isolé total.
  bool get isIsolated => _currentTransport == NetworkTransport.none;

  /// Liste des statuts de tous les transports (pour UI tableau de bord).
  List<TransportStatus> get allStatuses => [
        TransportStatus(
          type: NetworkTransport.ble,
          isAvailable: _activeBlePeers > 0,
          peerCount: _activeBlePeers,
          detail:
              _activeBlePeers > 0 ? '$_activeBlePeers pair(s)' : 'Aucun pair',
        ),
        TransportStatus(
          type: NetworkTransport.wifiDirect,
          isAvailable: _isWifiP2PAvailable,
          detail: _isWifiP2PAvailable ? 'Actif' : 'Indisponible',
        ),
        TransportStatus(
          type: NetworkTransport.cellular,
          isAvailable: _hasInternet,
          detail: _hasInternet ? 'Connecté' : 'Hors ligne',
        ),
      ];

  // ── Cycle de vie ───────────────────────────────────────────────────────────

  /// Démarre la surveillance continue. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    // Abonnement aux changements du compteur de pairs BLE.
    PeerCounterService.instance.addListener(_onPeerCountChanged);

    // Abonnement aux changements d'état des couches réseau.
    ConnectivityService.instance.addListener(_onConnectivityChanged);

    // Abonnement au basculement du serveur (Internet reachable).
    FailoverManager.instance.activeServer.listen((_) => _onServerChanged());

    // Évaluation initiale.
    _refreshIndicators();
    _evaluateBestTransport();

    // Timer périodique de sécurité — réévalue toutes les 30 secondes
    // pour détecter les changements lents (Wi-Fi rejoignant un réseau, etc.).
    _evaluationTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _safeEvaluate());

    // Timer de vérification matérielle (Bluetooth / Wi-Fi éteint).
    _hardwareCheckTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _checkHardware());

    if (kDebugMode) {
      debugPrint(
          '[NetworkManager] démarré — transport actif=${_currentTransport.name}');
    }
  }

  /// Arrêt propre des abonnements.
  @override
  void dispose() {
    _evaluationTimer?.cancel();
    _hardwareCheckTimer?.cancel();
    PeerCounterService.instance.removeListener(_onPeerCountChanged);
    ConnectivityService.instance.removeListener(_onConnectivityChanged);
    _started = false;
    super.dispose();
  }

  // ── Évaluation du meilleur transport ───────────────────────────────────────

  /// Évalue le meilleur transport disponible en fonction des indicateurs
  /// actuels et déclenche le basculement si nécessaire.
  ///
  /// Politique :
  ///   1. BLE P2P si [activeBlePeers] > 0.
  ///   2. Wi-Fi Direct si BLE indisponible et Wi-Fi actif.
  ///   3. Relais Internet si aucun pair local et serveur joignable.
  ///   4. Aucun transport (mode isolé) si toutes les options sont coupées.
  void evaluateBestTransport(
    int activeBlePeers,
    bool isWifiP2PAvailable,
    bool hasInternet,
  ) {
    final NetworkTransport target;

    if (activeBlePeers > 0) {
      target = NetworkTransport.ble;
    } else if (isWifiP2PAvailable) {
      target = NetworkTransport.wifiDirect;
    } else if (hasInternet) {
      target = NetworkTransport.cellular;
    } else {
      target = NetworkTransport.none;
    }

    if (_currentTransport != target) {
      _handleTransportSwitch(_currentTransport, target);
    }
  }

  // ── Méthodes internes ──────────────────────────────────────────────────────

  /// Rafraîchit les trois indicateurs de santé réseau depuis les services
  /// sous-jacents, puis lance l'évaluation du meilleur transport.
  void _refreshIndicators() {
    _activeBlePeers = PeerCounterService.instance.value;
    _isWifiP2PAvailable =
        ConnectivityService.instance.state.wifiDirect ==
            TransportLayerState.active;
    _hasInternet = FailoverManager.instance.currentAddress.isNotEmpty;
  }

  /// Évalue le meilleur transport à partir des indicateurs internes.
  void _evaluateBestTransport() {
    evaluateBestTransport(_activeBlePeers, _isWifiP2PAvailable, _hasInternet);
  }

  /// Évaluation sécurisée qui rafraîchit d'abord les indicateurs.
  void _safeEvaluate() {
    _refreshIndicators();
    _evaluateBestTransport();
  }

  /// Exécute le basculement entre deux transports.
  ///
  /// Log l'événement, met à jour le champ [_currentTransport] et notifie
  /// les observateurs. Les sous-systèmes (transports, coordinateur)
  /// réagissent à ce changement via leur propre écoute de [NetworkManager].
  void _handleTransportSwitch(
    NetworkTransport from,
    NetworkTransport to,
  ) {
    _currentTransport = to;

    if (kDebugMode) {
      final fromLabel = from.name;
      final toLabel = to.name;
      final reason = _buildReason(to);
      debugPrint(
          '[NetworkManager] BASCULEMENT : $fromLabel → $toLabel ($reason)');
    }

    notifyListeners();
  }

  /// Construit une raison lisible pour le basculement.
  String _buildReason(NetworkTransport transport) {
    switch (transport) {
      case NetworkTransport.ble:
        return '$_activeBlePeers pair(s) BLE détecté(s)';
      case NetworkTransport.wifiDirect:
        return 'Wi-Fi Direct disponible, 0 pair BLE';
      case NetworkTransport.cellular:
        return 'Aucun pair local, relais Internet actif';
      case NetworkTransport.none:
        return 'Tous les transports sont indisponibles';
    }
  }

  // ── Callbacks des services observés ────────────────────────────────────────

  void _onPeerCountChanged() {
    final newCount = PeerCounterService.instance.value;
    if (newCount != _activeBlePeers) {
      _activeBlePeers = newCount;
      _evaluateBestTransport();
    }
  }

  void _onConnectivityChanged() {
    final newWifiState = ConnectivityService.instance.state.wifiDirect;
    final isAvailable = newWifiState == TransportLayerState.active;
    if (isAvailable != _isWifiP2PAvailable) {
      _isWifiP2PAvailable = isAvailable;
      _evaluateBestTransport();
    }
  }

  void _onServerChanged() {
    final isReachable = FailoverManager.instance.currentAddress.isNotEmpty;
    if (isReachable != _hasInternet) {
      _hasInternet = isReachable;
      _evaluateBestTransport();
    }
  }

  // ── Vérification matérielle ────────────────────────────────────────────────

  /// État du matériel. `ble` et `wifi` sont à `true` si le capteur est
  /// activé, `false` s'il est désactivé au niveau système.
  Map<String, bool> get hardwareStatus => Map.unmodifiable(_hardwareState);

  /// Vérifie l'état des capteurs Bluetooth et Wi-Fi via
  /// [Permission.bluetoothScan] et [ConnectivityService].
  Future<void> _checkHardware() async {
    final bleOk = await _isBluetoothEnabled();
    final wifiOk = await _isWifiEnabled();

    final changed = _hardwareState['ble'] != bleOk ||
        _hardwareState['wifi'] != wifiOk;

    _hardwareState['ble'] = bleOk;
    _hardwareState['wifi'] = wifiOk;

    if (changed) {
      if (kDebugMode) {
        debugPrint(
            '[NetworkManager] Matériel : BLE=$bleOk, Wi-Fi=$wifiOk');
      }
      notifyListeners();
    }
  }

  Future<bool> _isBluetoothEnabled() async {
    try {
      final status = await Permission.bluetoothScan.status;
      return status.isGranted || status.isLimited;
    } catch (_) {
      return true; // Pas de faux positif si indisponible
    }
  }

  Future<bool> _isWifiEnabled() async {
    try {
      return ConnectivityService.instance.state.wifiDirect !=
          TransportLayerState.disabled;
    } catch (_) {
      return true;
    }
  }

  /// Ouvre les paramètres Bluetooth du système.
  Future<void> openBluetoothSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  /// Ouvre les paramètres Wi-Fi du système.
  Future<void> openWifiSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}
