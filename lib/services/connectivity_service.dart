// lib/services/connectivity_service.dart
//
// Service de surveillance de la connectivité critique (Mode Isolé Total).
//
// Responsabilités :
//   1. Écouter l'état des serveurs (via FailoverManager).
//   2. Écouter le nombre de pairs Hive (via PeerCounterService).
//   3. Détecter l'isolement total (pas de serveur ET pas de pairs) pendant > 5 min.

import 'dart:async';
import 'package:flutter/material.dart';

import '../core/network/peer_counter_service.dart';
import '../network/failover_manager.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  bool _isIsolated = false;
  bool get isIsolated => _isIsolated;

  DateTime? _isolationStartTime;

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

    // Surveillance via FailoverManager et PeerCounterService
    FailoverManager.instance.activeServer.listen((_) => _checkState());
    PeerCounterService.instance.addListener(_checkState);

    // Vérification initiale
    _checkState();
    
    // Timer périodique de sécurité
    Timer.periodic(const Duration(seconds: 30), (_) => _checkState());
  }

  void _checkState() {
    final bool serversDown = FailoverManager.instance.currentAddress.isEmpty;
    final bool noPeers = PeerCounterService.instance.value == 0;

    if (serversDown && noPeers) {
      if (_isolationStartTime == null) {
        _isolationStartTime = DateTime.now();
        debugPrint('[Connectivity] Début de la phase d\'isolement potentiel...');
      } else {
        final duration = DateTime.now().difference(_isolationStartTime!);
        if (duration >= const Duration(minutes: 5)) {
          if (!_isIsolated) {
            _isIsolated = true;
            notifyListeners();
            debugPrint('[Connectivity] MODE ISOLÉ TOTAL ACTIVÉ');
          }
        }
      }
    } else {
      if (_isIsolated || _isolationStartTime != null) {
        _isIsolated = false;
        _isolationStartTime = null;
        notifyListeners();
        debugPrint('[Connectivity] Retour à un état connecté (Serveur ou Hive)');
      }
    }
  }
}
