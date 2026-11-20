// lib/services/server_config_service.dart
//
// Synchronisation de la configuration serveur vers l'application.
//
// Le serveur expose `GET /api/config` (valeurs publiques, sans secret).
// Ce service :
//   1. Fournit des VALEURS PAR DÉFAUT alignées sur server/src/config.js.
//   2. Récupère la config au démarrage (fetchAndApply) et l'applique aux
//      politiques locales : seuil de consensus, rayon de fusion, densité, TTLs.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/alert_ttl_policy.dart';
import '../database/alert_visibility_policy.dart';
import '../database/hive_alert_database.dart';
import '../network/failover_manager.dart';
import '../network/network_config.dart';

/// Service singleton de configuration distante.
class ServerConfigService {
  ServerConfigService._();
  static final ServerConfigService instance = ServerConfigService._();

  // Valeurs par défaut (alignées sur server/src/config.js).
  int consensusThreshold = 3;
  double mergeRadiusMeters = 10.0;
  int crowdDensityThreshold = 25;
  double crowdDensityRadiusMeters = 50.0;

  bool _fetched = false;
  bool get isFetched => _fetched;

  /// Récupère la config publique du serveur et l'applique localement.
  /// Non bloquant : en cas d'échec, les valeurs par défaut restent actives.
  Future<void> fetchAndApply() async {
    final base = _serverBase();
    if (base.isEmpty) return;
    try {
      final uri = Uri.parse('$base/api/config');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) apply(data);
    } catch (e) {
      debugPrint('[ServerConfig] échec sync config : $e');
    }
  }

  /// Applique les valeurs reçues du serveur.
  void apply(Map<String, dynamic> data) {
    consensusThreshold = _int(data['consensusThreshold'], consensusThreshold);
    mergeRadiusMeters = _double(data['mergeRadiusMeters'], mergeRadiusMeters);
    crowdDensityThreshold =
        _int(data['crowdDensityThreshold'], crowdDensityThreshold);
    crowdDensityRadiusMeters =
        _double(data['crowdDensityRadiusMeters'], crowdDensityRadiusMeters);

    final ttls = data['ttls'];
    if (ttls is Map<String, dynamic>) {
      final mobile =
          _int(ttls['mobileDanger'], AlertTtlPolicy.mobileTtl.inMinutes);
      final stat =
          _int(ttls['staticDanger'], AlertTtlPolicy.staticTtl.inMinutes);
      AlertTtlPolicy.mobileTtl = Duration(minutes: mobile);
      AlertTtlPolicy.staticTtl = Duration(minutes: stat);
    }

    // Application aux politiques locales.
    AlertVisibilityPolicy.minConfirmationsToShow = consensusThreshold;
    AlertVisibilityPolicy.minCrowdDensityThreshold = crowdDensityThreshold;
    HiveAlertDatabase.mergeRadiusMeters = mergeRadiusMeters;

    _fetched = true;
    debugPrint('[ServerConfig] config appliquée : '
        'consensus=$consensusThreshold merge=${mergeRadiusMeters}m '
        'densité=$crowdDensityThreshold');
  }

  String _serverBase() {
    final address = FailoverManager.instance.currentAddress;
    if (address.isNotEmpty) return address;
    return NetworkConfig.baseUrl;
  }

  int _int(dynamic v, int fallback) {
    final n = v == null ? null : int.tryParse(v.toString());
    return (n != null && n > 0) ? n : fallback;
  }

  double _double(dynamic v, double fallback) {
    final n = v == null ? null : double.tryParse(v.toString());
    return (n != null && n > 0) ? n : fallback;
  }
}
