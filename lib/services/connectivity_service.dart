// lib/services/connectivity_service.dart
//
// Service de surveillance de la connectivité critique (Mode Isolé Total).
//
// Responsabilités :
//   1. Écouter l'état des serveurs (via FailoverManager).
//   2. Écouter le nombre de pairs Hive (via PeerCounterService).
//   3. Détecter l'isolement total (pas de serveur ET pas de pairs) pendant > 5 min.
//   4. Détecter l'état des couches physiques (BLE, Wi-Fi, WebSocket).
//   5. Synchronisation conditionnelle selon l'état réseau.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/peer_counter_service.dart';
import '../network/failover_manager.dart';

/// État d'une couche de transport réseau.
enum TransportLayerState {
  /// Active et fonctionnelle.
  active,

  /// En cours d'initialisation.
  initializing,

  /// Désactivée (permission manquante, service système coupé).
  disabled,

  /// Non supportée sur cette plateforme.
  unsupported,

  /// Erreur temporaire (reconnexion en cours).
  error,
}

/// État global de la connectivité réseau.
class NetworkState {
  const NetworkState({
    this.ble = TransportLayerState.initializing,
    this.wifiDirect = TransportLayerState.initializing,
    this.webSocket = TransportLayerState.initializing,
    this.isIsolated = false,
    this.isolationDuration = Duration.zero,
    this.missingLayers = const [],
  });

  final TransportLayerState ble;
  final TransportLayerState wifiDirect;
  final TransportLayerState webSocket;
  final bool isIsolated;
  final Duration isolationDuration;
  final List<String> missingLayers;

  bool get allLayersDown =>
      ble != TransportLayerState.active &&
      wifiDirect != TransportLayerState.active &&
      webSocket != TransportLayerState.active;

  bool get anyLayerActive =>
      ble == TransportLayerState.active ||
      wifiDirect == TransportLayerState.active ||
      webSocket == TransportLayerState.active;

  int get activeLayerCount {
    int count = 0;
    if (ble == TransportLayerState.active) count++;
    if (wifiDirect == TransportLayerState.active) count++;
    if (webSocket == TransportLayerState.active) count++;
    return count;
  }

  TransportLayerState? get primaryLayer {
    if (ble == TransportLayerState.active) return ble;
    if (wifiDirect == TransportLayerState.active) return wifiDirect;
    if (webSocket == TransportLayerState.active) return webSocket;
    return null;
  }
}

// ignore: must_be_immutable
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  NetworkState _state = const NetworkState();
  NetworkState get state => _state;

  bool get isIsolated => _state.isIsolated;
  bool get allLayersDown => _state.allLayersDown;

  DateTime? _isolationStartTime;
  bool _started = false;
  Timer? _periodicTimer;
  StreamSubscription? _failoverSub;

  // ignore: prefer_final_fields
  bool _wasAnyLayerDown = false;

  final _networkRestoredController = StreamController<bool>.broadcast();
  Stream<bool> get onNetworkRestored => _networkRestoredController.stream;

  void start() {
    if (_started) return;
    _started = true;

    _failoverSub =
        FailoverManager.instance.activeServer.listen((_) => _checkState());
    PeerCounterService.instance.addListener(_checkState);

    _checkState();

    _periodicTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _checkState());
  }

  // ignore: must_dispose_subscriptions
  @override
  void dispose() {
    _periodicTimer?.cancel();
    _failoverSub?.cancel();
    _failoverSub = null;
    PeerCounterService.instance.removeListener(_checkState);
    _networkRestoredController.close();
    super.dispose();
  }

  void updateLayerState(String layer, TransportLayerState newState) {
    NetworkState updated;
    switch (layer) {
      case 'ble':
        updated = NetworkState(
          ble: newState,
          wifiDirect: _state.wifiDirect,
          webSocket: _state.webSocket,
          isIsolated: _state.isIsolated,
          isolationDuration: _state.isolationDuration,
          missingLayers: _state.missingLayers,
        );
        break;
      case 'wifi':
        updated = NetworkState(
          ble: _state.ble,
          wifiDirect: newState,
          webSocket: _state.webSocket,
          isIsolated: _state.isIsolated,
          isolationDuration: _state.isolationDuration,
          missingLayers: _state.missingLayers,
        );
        break;
      case 'websocket':
        updated = NetworkState(
          ble: _state.ble,
          wifiDirect: _state.wifiDirect,
          webSocket: newState,
          isIsolated: _state.isIsolated,
          isolationDuration: _state.isolationDuration,
          missingLayers: _state.missingLayers,
        );
        break;
      default:
        return;
    }

    final missing = <String>[];
    if (updated.ble != TransportLayerState.active &&
        updated.ble != TransportLayerState.unsupported) {
      missing.add('Bluetooth (BLE)');
    }
    if (updated.wifiDirect != TransportLayerState.active &&
        updated.wifiDirect != TransportLayerState.unsupported) {
      missing.add('Wi-Fi Direct');
    }
    if (updated.webSocket != TransportLayerState.active &&
        updated.webSocket != TransportLayerState.unsupported) {
      missing.add('Serveur Web');
    }

    _state = NetworkState(
      ble: updated.ble,
      wifiDirect: updated.wifiDirect,
      webSocket: updated.webSocket,
      isIsolated: updated.isIsolated,
      isolationDuration: updated.isolationDuration,
      missingLayers: missing,
    );

    notifyListeners();
  }

  void _checkState() {
    final bool serversDown = FailoverManager.instance.currentAddress.isEmpty;
    final bool noPeers = PeerCounterService.instance.value == 0;

    if (serversDown && noPeers) {
      if (_isolationStartTime == null) {
        _isolationStartTime = DateTime.now();
        _wasAnyLayerDown = true;
        if (kDebugMode) {
          debugPrint('[Connectivity] Phase d\'isolement potentiel — '
              'serveurs down & 0 pairs BLE');
        }
      } else {
        final duration = DateTime.now().difference(_isolationStartTime!);
        // Basculer en mode isolé après 30 secondes (au lieu de 5 minutes).
        // 5 minutes est trop long : pendant ce temps, broadcastHiveMessage
        // tente toujours le relay serveur et échoue silencieusement.
        if (duration >= const Duration(seconds: 30)) {
          if (!_state.isIsolated) {
            _state = NetworkState(
              ble: _state.ble,
              wifiDirect: _state.wifiDirect,
              webSocket: _state.webSocket,
              isIsolated: true,
              isolationDuration: duration,
              missingLayers: _state.missingLayers,
            );
            notifyListeners();
            if (kDebugMode) {
              debugPrint('[Connectivity] ⚠ MODE ISOLÉ TOTAL ACTIVÉ '
                  '(serveurs down + 0 pairs BLE depuis ${duration.inSeconds}s)');
            }
          }
        }
      }
    } else {
      // Réseau restauré : si on était isolé ou dégradé, déclencher sync.
      if (_state.isIsolated || _isolationStartTime != null || _wasAnyLayerDown) {
        _networkRestoredController.add(true);
        _wasAnyLayerDown = false;
      }
      if (_state.isIsolated || _isolationStartTime != null) {
        _state = NetworkState(
          ble: _state.ble,
          wifiDirect: _state.wifiDirect,
          webSocket: _state.webSocket,
          isIsolated: false,
          isolationDuration: Duration.zero,
          missingLayers: _state.missingLayers,
        );
        _isolationStartTime = null;
        notifyListeners();
        debugPrint(
            '[Connectivity] Retour à un état connecté (Serveur ou Hive)');
      }
    }
  }
}