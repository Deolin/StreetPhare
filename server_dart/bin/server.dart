// server_dart/bin/server.dart
//
// Serveur StreetPhare — 100% Dart (remplace server_primary_v2.js
// et server_secondary_v2.js).
//
// Compilation native :
//   Windows : dart compile exe bin/server.dart -o build/server.exe
//   Linux   : dart compile exe bin/server.dart -o build/server
//
// Usage :
//   dart run bin/server.dart
//   ROLE=backup PORT=3001 dart run bin/server.dart
//
// Variables d'environnement :
//   PORT              — port d'écoute (défaut 3000)
//   ROLE              — 'primary' (défaut) ou 'backup'
//   PRIMARY_URL       — URL du serveur principal (pour le backup)
//   STREETPHARE_MASTER_KEY — passphrase maître (défaut: clé de dev)
//
// Endpoints HTTP :
//   GET  /ping              — heartbeat
//   GET  /healthz           — healthcheck
//   GET  /status            — topologie complète
//   GET  /api/version/check — kill switch version
//   GET  /v1/events         — catalogue événements
//   GET  /v1/events/:id     — détail événement
//   POST /v1/events/:id/route — calcul Safe Route
//   POST /v1/reports        — signalement danger
//   GET  /v1/reports        — liste signalements validés
//   POST /v1/panic          — alerte PANIC
//   GET  /api/v2/sync-check — synchronisation différentielle
//
// WebSocket :
//   WS /mesh                — relais maillage P2P (propagation alertes)
//   WS /admin               — dashboard administrateur

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logging/logging.dart';
import 'package:crypto/crypto.dart' show sha256;

// ══════════════════════════════════════════════════════════════════════════════
// RBAC — Authentification & Rôles
// ══════════════════════════════════════════════════════════════════════════════

enum AdminRole { admin, moderator }

class AdminUser {
  final String username;
  final String passwordHash;
  final AdminRole role;
  final bool canBypassConsensus;
  final bool canKickPeers;

  const AdminUser({
    required this.username,
    required this.passwordHash,
    this.role = AdminRole.moderator,
    this.canBypassConsensus = false,
    this.canKickPeers = false,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'role': role.name,
        'can_bypass_consensus': canBypassConsensus,
        'can_kick_peers': canKickPeers,
      };
}

/// Comptes administrateurs en mémoire (initialisés au démarrage).
final List<AdminUser> _admins = [];

/// Sessions actives (token → AdminUser).
final Map<String, AdminUser> _sessions = {};

String _hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

AdminUser? _authenticate(String username, String password) {
  final hash = _hashPassword(password);
  for (final admin in _admins) {
    if (admin.username == username && admin.passwordHash == hash) {
      return admin;
    }
  }
  return null;
}

String _generateToken() {
  return base64Url.encode(List<int>.generate(32, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF));
}

AdminUser? _getSessionUser(String token) => _sessions[token];

bool _hasPermission(AdminUser user, {bool needBypass = false, bool needKick = false}) {
  if (user.role == AdminRole.admin) return true;
  if (needBypass && !user.canBypassConsensus) return false;
  if (needKick && !user.canKickPeers) return false;
  return true;
}

// ══════════════════════════════════════════════════════════════════════════════
// Configuration
// ══════════════════════════════════════════════════════════════════════════════

final _port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
final _role = Platform.environment['ROLE'] ?? 'primary';
final _primaryUrl =
    Platform.environment['PRIMARY_URL'] ?? 'http://127.0.0.1:3000';
const _appMinVersion = '2.2.0';

final _log = Logger('StreetPhareServer');

// Types d'alertes alignés strictement avec le client Flutter AlertType
// ══════════════════════════════════════════════════════════════════════════════

/// Liste exhaustive des types d'alertes reconnus par le serveur,
/// miroir de `AlertType` dans `lib/database/alert_model.dart`.
const _validAlertTypes = {
  'barrage',
  'casseurs',
  'danger',
  'policiers',
  'autopompes',
  'filtre',
  'panic',
  'dangerCollectif',
  'density',
  'autre',
};

/// Statuts d'alerte alignés sur le client Flutter `AlertStatus`.
const _validAlertStatuses = {
  'pending',
  'active',
  'rejected',
};

/// Normalise un type d'alerte. Si la valeur n'est pas reconnue, retourne 'autre'.
String _normalizeAlertType(dynamic rawType) {
  final s = rawType?.toString() ?? 'autre';
  return _validAlertTypes.contains(s) ? s : 'autre';
}

/// Normalise un statut d'alerte.
String _normalizeAlertStatus(dynamic rawStatus) {
  final s = rawStatus?.toString() ?? 'pending';
  return _validAlertStatuses.contains(s) ? s : 'pending';
}

// ══════════════════════════════════════════════════════════════════════════════
// Stockage en mémoire
// ══════════════════════════════════════════════════════════════════════════════

/// Signalements de dangers validés.
/// Clés alignées sur le contrat client `Alert.toJson()` :
///   id, reporter_id, type, lat, lon, description, density_value,
///   timestamp, ttl_hours, status, confirmations, signature,
///   last_modified_at
final List<Map<String, dynamic>> _reports = [];

/// Connexions WebSocket mesh actives.
final Set<WebSocketChannel> _meshClients = {};

/// Connexions WebSocket admin actives.
final Set<WebSocketChannel> _adminClients = {};

/// Événements en cours.
final List<Map<String, dynamic>> _events = [
  {
    'id': 'fleurus-6220',
    'name': 'Fleurus 6220',
    'description': 'Rassemblement citoyen — zone de test StreetPhare',
    'lat': 50.4833,
    'lng': 4.5500,
    'radius_m': 3000,
    'active': true,
  },
  {
    'id': 'bruxelles-centre',
    'name': 'Bruxelles Centre',
    'description': 'Zone pilote Bruxelles — test urbain dense',
    'lat': 50.8503,
    'lng': 4.3517,
    'radius_m': 2000,
    'active': true,
  },
  {
    'id': 'charleroi-test',
    'name': 'Charleroi Test',
    'description': 'Zone de validation Charleroi',
    'lat': 50.4108,
    'lng': 4.4446,
    'radius_m': 2000,
    'active': false,
  },
];

// ══════════════════════════════════════════════════════════════════════════════
// Main
// ══════════════════════════════════════════════════════════════════════════════

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final ts = record.time.toUtc().toIso8601String();
    stderr.writeln('[$ts] ${record.level.name.padRight(7)} ${record.message}');
  });

  final app = Router();

  // ── Heartbeat & Statut ────────────────────────────────────────────────
  app.get('/ping', _ping);
  app.get('/healthz', _healthz);
  app.get('/status', _status);

  // ── Version Kill Switch ───────────────────────────────────────────────
  app.get('/api/version/check', _versionCheck);

  // ── Événements ────────────────────────────────────────────────────────
  app.get('/v1/events', _listEvents);
  app.get('/v1/events/<id>', _getEvent);
  app.post('/v1/events/<id>/route', _calculateRoute);

  // ── Signalements ──────────────────────────────────────────────────────
  app.post('/v1/reports', _submitReport);
  app.get('/v1/reports', _listReports);

  // ── PANIC ─────────────────────────────────────────────────────────────
  app.post('/v1/panic', _panic);

  // ── Sync différentielle (inter-cluster Hive) ──────────────────────────
  app.get('/api/v2/sync-check', _syncCheck);

  // ── Auth RBAC ──────────────────────────────────────────────────────────
  app.post('/api/admin/login', _adminLogin);
  app.post('/api/admin/logout', _adminLogout);
  app.get('/api/admin/session', _adminSession);
  app.post('/api/admin/users', _adminCreateUser);
  app.delete('/api/admin/users/<username>', _adminDeleteUser);

  // ── Sandbox Admin (simulation & injection directe) ─────────────────────
  app.post('/api/admin/sandbox/inject-fault', _injectFault);
  app.post('/api/admin/sandbox/simulate-cluster', _simulateCluster);
  app.post('/api/admin/force-alert', _forceAlert);
  app.post('/api/admin/kick-peer', _kickPeer);

  // ── Pipeline CORS + JSON ──────────────────────────────────────────────
  final pipeline = Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(app.call);

  // ── WebSocket Mesh ────────────────────────────────────────────────────
  final wsHandler = webSocketHandler((WebSocketChannel channel, _) {
    _registerMeshClient(channel);
  });

  // ── WebSocket Admin ───────────────────────────────────────────────────
  final adminWsHandler = webSocketHandler((WebSocketChannel channel, _) {
    _registerAdminClient(channel);
  });

  // ── Initialisation du compte admin par défaut ──────────────────────────
  _initDefaultAdmin();

  // ── Fichiers statiques (dashboard web) ────────────────────────────────
  final staticHandler =
      createStaticHandler('web', defaultDocument: 'index.html');

  // ── Démarrage ─────────────────────────────────────────────────────────
  FutureOr<Response> rootHandler(Request request) {
    final path = request.url.path;
    if (path == 'mesh') return wsHandler(request);
    if (path == 'admin') return adminWsHandler(request);
    if (path == 'dashboard' || path.startsWith('dashboard/')) {
      final subPath =
          path == 'dashboard' ? '' : path.substring('dashboard/'.length);
      final modifiedRequest = Request(
        request.method,
        request.requestedUri.replace(path: subPath),
        body: request.read(),
        headers: request.headers,
        protocolVersion: request.protocolVersion,
      );
      return staticHandler(modifiedRequest);
    }
    return pipeline(request);
  }

  final server =
      await shelf_io.serve(rootHandler, InternetAddress.anyIPv4, _port);
  _log.info('StreetPhare serveur $_role démarré sur le port $_port');
  _log.info('  HTTP      : http://0.0.0.0:$_port');
  _log.info('  WS Mesh   : ws://0.0.0.0:$_port/mesh');
  _log.info('  WS Admin  : ws://0.0.0.0:$_port/admin');

  ProcessSignal.sigint.watch().listen((_) {
    _log.info('Arrêt du serveur...');
    for (final c in [..._meshClients, ..._adminClients]) {
      c.sink.close();
    }
    server.close();
    exit(0);
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// Middleware CORS
// ══════════════════════════════════════════════════════════════════════════════

Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders());
      }
      final response = await handler(request);
      return response.change(headers: _corsHeaders());
    };
  };
}

Map<String, String> _corsHeaders() => {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    };

// ══════════════════════════════════════════════════════════════════════════════
// Endpoints HTTP
// ══════════════════════════════════════════════════════════════════════════════

Response _ping(Request request) => _json({
      'status': 'ok',
      'role': _role,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });

Response _healthz(Request request) => _json({'status': 'ok'});

Response _status(Request request) {
  final isPrimary = _role == 'primary';
  return _json({
    'server': {
      'role': _role,
      'port': _port,
      'uptime': DateTime.now().toUtc().toIso8601String(),
    },
    'mesh': {
      'clients_connected': _meshClients.length,
      'admin_connected': _adminClients.length,
    },
    'reports': {
      'total': _reports.length,
      'active': _reports.where((r) => r['status'] == 'active').length,
    },
    'events': {
      'total': _events.length,
      'active': _events.where((e) => e['active'] == true).length,
    },
    'failover': {
      'is_primary': isPrimary,
      'primary_url': _primaryUrl,
    },
  });
}

Response _versionCheck(Request request) {
  return _json({
    'min_version': _appMinVersion,
    'current_stable': '2.2.0',
    'update_required': false,
    'message': 'Votre application est à jour.',
  });
}

// ── Événements ────────────────────────────────────────────────────────────

Response _listEvents(Request request) {
  final activeOnly = request.url.queryParameters['active'] == 'true';
  final events =
      activeOnly ? _events.where((e) => e['active'] == true).toList() : _events;
  return _json({'events': events});
}

Response _getEvent(Request request, String id) {
  final event = _events.where((e) => e['id'] == id).firstOrNull;
  if (event == null) {
    return Response.notFound(_body({'error': 'Événement introuvable'}));
  }
  final qrPayload = {
    'event_id': event['id'],
    'name': event['name'],
    'lat': event['lat'],
    'lng': event['lng'],
    'radius_m': event['radius_m'],
    'ts': DateTime.now().toUtc().toIso8601String(),
  };
  return _json({
    'event': event,
    'qr_payload': base64Url.encode(utf8.encode(jsonEncode(qrPayload))),
  });
}

Future<Response> _calculateRoute(Request request, String id) async {
  final event = _events.where((e) => e['id'] == id).firstOrNull;
  if (event == null) {
    return Response.notFound(_body({'error': 'Événement introuvable'}));
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  // Contrat client : { from: { lat, lon }, to: { lat, lon }, avoid_filters: {...} }
  final from = body['from'] as Map<String, dynamic>?;
  final to = body['to'] as Map<String, dynamic>?;
  final originLat = (from?['lat'] as num?)?.toDouble() ?? 0;
  final originLng = (from?['lon'] as num?)?.toDouble() ?? 0;
  final destLat = (to?['lat'] as num?)?.toDouble() ?? (event['lat'] as num).toDouble();
  final destLng = (to?['lon'] as num?)?.toDouble() ?? (event['lng'] as num).toDouble();

  final dangerZones = _reports
      .where((r) => r['status'] == 'active')
      .map((r) => {
            'lat': (r['lat'] as num?)?.toDouble() ?? 0,
            'lng': (r['lon'] as num?)?.toDouble() ?? 0,
            'radius_m': (r['radius_m'] as num?)?.toDouble() ?? 200,
          })
      .toList();

  final route = _buildRoute(originLat, originLng,
      destLat, destLng,
      dangerZones);

  final alternatives = List.generate(3, (i) {
    final offsetLat = (i + 1) * 0.001;
    final offsetLng = (i - 1) * 0.001;
    return _buildRoute(originLat, originLng,
        destLat + offsetLat,
        destLng + offsetLng, dangerZones);
  });

  // Contrat client (_computeViaServer) :
  //   { routes: [ { polyline: [[lat,lng],...], distance_m, safe_score }, ... ] }
  final routesJson = <Map<String, dynamic>>[];
  final allRoutes = [route, ...alternatives];
  for (var i = 0; i < allRoutes.length; i++) {
    final r = allRoutes[i];
    final waypoints = (r['waypoints'] as List<dynamic>)
        .map((w) => [(w as Map)['lat'], w['lng']])
        .toList();
    final distanceKm = double.tryParse(r['distance_km'] as String? ?? '0') ?? 0;
    routesJson.add({
      'polyline': waypoints,
      'distance_m': (distanceKm * 1000).toStringAsFixed(0),
      'safe_score': (100 - dangerZones.length * 10).clamp(0, 100),
    });
  }

  return _json({
    'event_id': id,
    'origin': {'lat': originLat, 'lng': originLng},
    'destination': {'lat': destLat, 'lng': destLng},
    'routes': routesJson,
    'danger_zones_avoided': dangerZones.length,
  });
}

Map<String, dynamic> _buildRoute(double fromLat, double fromLng, double toLat,
    double toLng, List<Map<String, dynamic>> dangerZones) {
  const steps = 20;
  final waypoints = <Map<String, dynamic>>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    var lat = fromLat + (toLat - fromLat) * t;
    var lng = fromLng + (toLng - fromLng) * t;

    for (final zone in dangerZones) {
      final dLat = lat - (zone['lat'] as num).toDouble();
      final dLng = lng - (zone['lng'] as num).toDouble();
      final dist = (dLat * dLat + dLng * dLng) * 111000;
      final radius = (zone['radius_m'] as num?)?.toDouble() ?? 200;
      if (dist < radius * radius) {
        lat += dLat * 0.3;
        lng += dLng * 0.3;
      }
    }

    waypoints.add({'lat': lat, 'lng': lng});
  }

  final distanceKm = _haversineKm(fromLat, fromLng, toLat, toLng) * 1.1;
  return {
    'waypoints': waypoints,
    'distance_km': distanceKm.toStringAsFixed(2),
    'duration_min': (distanceKm / 1.4).toStringAsFixed(0),
  };
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
  final dLng = (lng2 - lng1) * 3.141592653589793 / 180;
  final a = _sinHalf(dLat) * _sinHalf(dLat) +
      _cos(lat1 * 3.141592653589793 / 180) *
          _cos(lat2 * 3.141592653589793 / 180) *
          _sinHalf(dLng) *
          _sinHalf(dLng);
  return r * 2 * _atan2(_sqrt(a), _sqrt(1 - a));
}

double _sinHalf(double x) => _sin(x / 2) * _sin(x / 2);
double _sin(double x) =>
    x - x * x * x / 6 + x * x * x * x * x / 120;
double _cos(double x) => _sin(1.5707963267948966 - x);
double _sqrt(double x) {
  if (x <= 0) return 0;
  var guess = x;
  for (var i = 0; i < 10; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
double _atan2(double y, double x) {
  if (x > 0) return _atan(y / x);
  if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
  if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
  if (x == 0 && y > 0) return 1.5707963267948966;
  if (x == 0 && y < 0) return -1.5707963267948966;
  return 0;
}
double _atan(double x) {
  if (x.abs() > 1) {
    final sign = x > 0 ? 1.0 : -1.0;
    return sign * 1.5707963267948966 - _atan(1 / x.abs());
  }
  var result = 0.0;
  var term = x;
  for (var i = 1; i < 15; i += 2) {
    result += term / i;
    term *= -x * x;
  }
  return result;
}

// ── Signalements ──────────────────────────────────────────────────────────

Future<Response> _submitReport(Request request) async {
  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  // Normalisation des champs (contrat client Alert.toJson).
  final now = DateTime.now().toUtc();
  final reportType = _normalizeAlertType(body['type']);
  final reportStatus = _normalizeAlertStatus(body['status']);
  final lat = (body['lat'] as num?)?.toDouble() ?? 0.0;
  final lon = (body['lon'] as num?)?.toDouble() ?? 0.0;

  final report = {
    'id': body['id'] ?? _randomId(),
    'reporter_id': body['reporter_id'] ?? '',
    'type': reportType,
    'lat': lat,
    'lon': lon,
    'description': body['description'] ?? '',
    'density_value': body['density_value'],
    'timestamp': body['timestamp'] ?? now.toIso8601String(),
    'ttl_hours': (body['ttl_hours'] as int?) ?? 24,
    'status': reportStatus,
    'confirmations': ((body['confirmations'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    'signature': body['signature'] ?? '',
    'last_modified_at': body['last_modified_at'] ?? now.toIso8601String(),
  };

  _reports.add(report);
  _log.info(
      'Nouveau signalement: ${report['id']} (${report['type']}) status=${report['status']}');

  // Propager aux clients mesh.
  _broadcastMesh({
    'type': 'new_report',
    'report': {
      'id': report['id'],
      'type': report['type'],
      'lat': report['lat'],
      'lon': report['lon'],
      'description': report['description'],
    },
  });

  // Notifier les admins.
  _broadcastAdmin({
    'type': 'new_report',
    'report': report,
  });

  return _json({'status': 'ok', 'report_id': report['id']});
}

Response _listReports(Request request) {
  final activeOnly = request.url.queryParameters['active'] == 'true';
  final reports = activeOnly
      ? _reports.where((r) => r['status'] == 'active').toList()
      : _reports;
  final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
  final lng = double.tryParse(request.url.queryParameters['lng'] ?? '');
  final radiusKm =
      double.tryParse(request.url.queryParameters['radius_km'] ?? '5') ?? 5;

  var filtered = reports;
  if (lat != null && lng != null) {
    filtered = reports.where((r) {
      final d = _haversineKm(lat, lng, (r['lat'] as num).toDouble(),
          (r['lon'] as num?)?.toDouble() ?? 0);
      return d <= radiusKm;
    }).toList();
  }

  return _json({'reports': filtered, 'total': filtered.length});
}

// ── PANIC ─────────────────────────────────────────────────────────────────

Future<Response> _panic(Request request) async {
  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  final panicAlert = {
    'id': 'PANIC-${_randomId()}',
    'type': 'panic',
    'lat': (body['lat'] as num?)?.toDouble() ?? 0,
    'lon': (body['lon'] as num?)?.toDouble() ?? 0,
    'message': body['message'] ?? 'ALERTE PANIC',
    'contacts': body['contacts'] ?? [],
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };

  _log.warning('ALERTE PANIC reçue: ${panicAlert['id']}');

  _broadcastMesh({
    'type': 'panic_alert',
    'alert': panicAlert,
  });

  _broadcastAdmin({
    'type': 'panic_alert',
    'alert': panicAlert,
  });

  return _json({
    'status': 'ok',
    'panic_id': panicAlert['id'],
    'mesh_relayed_to': _meshClients.length,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// Sync différentielle — /api/v2/sync-check
// ══════════════════════════════════════════════════════════════════════════════

/// GET /api/v2/sync-check?since=ISO8601
///
/// Résolution de conflits basée sur les timestamps `last_modified_at`.
///
/// Algorithme :
///   1. Le client envoie le timestamp de sa dernière modification locale
///      via le paramètre `since`.
///   2. Le serveur retourne toutes les alertes modifiées APRÈS ce timestamp
///      dans la liste `updates`.
///   3. Si le client envoie également des alertes locales plus récentes
///      (via POST /v1/reports), le serveur les a déjà enregistrées.
///      Cette route se contente de fournir les deltas serveur → client.
///   4. Les mises à jour sont immédiatement notifiées aux dashboards admin
///      connectés via WebSocket /admin.
Future<Response> _syncCheck(Request request) async {
  final sinceStr = request.url.queryParameters['since'] ?? '';
  final since = sinceStr.isNotEmpty
      ? DateTime.tryParse(sinceStr)?.toUtc()
      : null;

  // Collecte les alertes modifiées après `since`.
  final List<Map<String, dynamic>> updates;
  final sinceUtc = since; // variable locale non-null dans la closure
  if (sinceUtc != null) {
    updates = _reports.where((r) {
      final modifiedStr = r['last_modified_at'] as String?;
      if (modifiedStr == null) return false;
      final modified = DateTime.tryParse(modifiedStr)?.toUtc();
      if (modified == null) return false;
      return modified.isAfter(sinceUtc);
    }).toList();
  } else {
    // Pas de timestamp → retourne tout (première sync).
    updates = List.unmodifiable(_reports);
  }

  // Notifie les dashboards admin de la synchronisation.
  if (updates.isNotEmpty) {
    _broadcastAdmin({
      'type': 'sync_delta',
      'since': sinceStr,
      'count': updates.length,
      'items': updates,
    });
  }

  return _json({
    'status': 'ok',
    'since': sinceStr,
    'count': updates.length,
    'items': updates,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// WebSocket Mesh — Relais P2P
// ══════════════════════════════════════════════════════════════════════════════

void _registerMeshClient(WebSocketChannel channel) {
  _meshClients.add(channel);
  _log.info('Mesh client connecté (total: ${_meshClients.length})');

  channel.sink.add(jsonEncode({
    'type': 'mesh_status',
    'connected_clients': _meshClients.length,
    'active_reports': _reports.where((r) => r['status'] == 'active').length,
  }));

  channel.stream.listen(
    (data) {
      try {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        _handleMeshMessage(channel, message);
      } catch (e) {
        _log.warning('Message mesh invalide: $e');
      }
    },
    onDone: () {
      _meshClients.remove(channel);
      _log.info('Mesh client déconnecté (total: ${_meshClients.length})');
      _broadcastMesh({
        'type': 'peer_disconnected',
        'total_peers': _meshClients.length,
      });
    },
    onError: (e) {
      _meshClients.remove(channel);
      _log.warning('Erreur mesh client: $e');
    },
    cancelOnError: true,
  );
}

void _handleMeshMessage(WebSocketChannel sender, Map<String, dynamic> msg) {
  final type = msg['type'] as String?;

  switch (type) {
    case 'ping':
      sender.sink.add(jsonEncode({
        'type': 'pong',
        'ts': DateTime.now().toUtc().toIso8601String(),
      }));
      break;
    case 'alert':
    case 'report':
    case 'broadcast':
      for (final client in _meshClients) {
        if (client != sender) {
          client.sink.add(jsonEncode(msg));
        }
      }
      break;
    case 'peer_discovery':
      sender.sink.add(jsonEncode({
        'type': 'peer_discovery_response',
        'events': _events.where((e) => e['active'] == true).toList(),
        'reports_count': _reports.length,
      }));
      break;
    default:
      if (_log.isLoggable(Level.FINE)) {
        _log.fine('Message mesh inconnu: $type');
      }
  }
}

void _broadcastMesh(Map<String, dynamic> msg) {
  final encoded = jsonEncode(msg);
  for (final client in _meshClients) {
    client.sink.add(encoded);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WebSocket Admin — Dashboard
// ══════════════════════════════════════════════════════════════════════════════

void _registerAdminClient(WebSocketChannel channel) {
  _adminClients.add(channel);
  _log.info('Admin client connecté (total: ${_adminClients.length})');

  channel.sink.add(jsonEncode({
    'type': 'admin_snapshot',
    'server': {'role': _role, 'port': _port},
    'mesh_clients': _meshClients.length,
    'reports': _reports,
    'events': _events,
  }));

  channel.stream.listen(
    (data) {
      try {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        _handleAdminMessage(channel, message);
      } catch (e) {
        _log.warning('Message admin invalide: $e');
      }
    },
    onDone: () {
      _adminClients.remove(channel);
      _log.info('Admin client déconnecté');
    },
    onError: (e) {
      _adminClients.remove(channel);
    },
    cancelOnError: true,
  );
}

void _handleAdminMessage(
    WebSocketChannel sender, Map<String, dynamic> msg) {
  final type = msg['type'] as String?;

  switch (type) {
    case 'validate_report':
      final reportId = msg['report_id'] as String?;
      if (reportId != null) {
        final report =
            _reports.where((r) => r['id'] == reportId).firstOrNull;
        if (report != null) {
          report['status'] = 'active';
          report['last_modified_at'] =
              DateTime.now().toUtc().toIso8601String();
          _log.info('Signalement activé: $reportId');
          _broadcastAdmin({'type': 'report_updated', 'report': report});
          _broadcastMesh({
            'type': 'report_validated',
            'report': {
              'id': report['id'],
              'lat': report['lat'],
              'lon': report['lon'],
              'type': report['type'],
            },
          });
          sender.sink.add(
              jsonEncode({'type': 'validation_ok', 'report_id': reportId}));
        }
      }
      break;
    case 'reject_report':
      final reportId = msg['report_id'] as String?;
      if (reportId != null) {
        final report =
            _reports.where((r) => r['id'] == reportId).firstOrNull;
        if (report != null) {
          report['status'] = 'rejected';
          report['last_modified_at'] =
              DateTime.now().toUtc().toIso8601String();
          _log.info('Signalement rejeté: $reportId');
          _broadcastAdmin({'type': 'report_updated', 'report': report});
          sender.sink.add(
              jsonEncode({'type': 'rejection_ok', 'report_id': reportId}));
        }
      }
      break;
    case 'refresh':
      sender.sink.add(jsonEncode({
        'type': 'admin_snapshot',
        'server': {'role': _role, 'port': _port},
        'mesh_clients': _meshClients.length,
        'reports': _reports,
        'events': _events,
      }));
      break;
    default:
      break;
  }
}

void _broadcastAdmin(Map<String, dynamic> msg) {
  final encoded = jsonEncode(msg);
  for (final client in _adminClients) {
    client.sink.add(encoded);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sandbox Admin — Simulation & Injection Directe
// ══════════════════════════════════════════════════════════════════════════════

Future<Response> _injectFault(Request request) async {
  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  final faultType = body['fault'] ?? 'none';
  _log.warning('Sandbox: injection défaut "$faultType"');

  switch (faultType) {
    case 'disconnect-mesh':
      for (final c in _meshClients.toList()) {
        c.sink.close();
      }
      _meshClients.clear();
      _broadcastAdmin({
        'type': 'sandbox_event',
        'event': 'mesh_disconnected',
        'clients_remaining': 0,
      });
      break;
    case 'latency':
      final delayMs = (body['delay_ms'] as int?) ?? 2000;
      _broadcastAdmin({
        'type': 'sandbox_event',
        'event': 'latency_injected',
        'delay_ms': delayMs,
      });
      break;
    case 'packet-loss':
      final pct = (body['pct'] as num?)?.toDouble() ?? 0.3;
      _broadcastAdmin({
        'type': 'sandbox_event',
        'event': 'packet_loss_injected',
        'pct': pct,
      });
      break;
    case 'reset':
      _broadcastAdmin({
        'type': 'sandbox_event',
        'event': 'fault_reset',
      });
      break;
    default:
      return _json({'status': 'ok', 'fault': faultType, 'applied': true});
  }

  return _json({'status': 'ok', 'fault': faultType, 'applied': true});
}

Future<Response> _simulateCluster(Request request) async {
  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  final count = (body['count'] as int?) ?? 10;
  final clusterLat = (body['lat'] as num?)?.toDouble() ?? 50.4833;
  final clusterLng = (body['lng'] as num?)?.toDouble() ?? 4.5500;
  final spread = (body['spread'] as num?)?.toDouble() ?? 0.01;

  final now = DateTime.now().toUtc();
  final generated = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final lat = clusterLat +
        (now.microsecondsSinceEpoch % 1000 / 1000 - 0.5) * spread;
    final lng = clusterLng +
        (now.microsecondsSinceEpoch % 1000 / 1000 - 0.5) * spread;
    final types = _validAlertTypes.toList();
    final report = {
      'id': _randomId(),
      'reporter_id': 'sandbox-${_randomId()}',
      'type': types[i % types.length],
      'lat': lat,
      'lon': lng,
      'description': 'Simulation cluster #${i + 1}',
      'density_value': null,
      'timestamp': now.toIso8601String(),
      'ttl_hours': 24,
      'status': 'pending',
      'confirmations': <String>[],
      'signature': '',
      'last_modified_at': now.toIso8601String(),
    };
    _reports.add(report);
    generated.add(report);
  }

  _log.info(
      'Sandbox: $count signalements simulés autour de ($clusterLat, $clusterLng)');

  _broadcastAdmin({
    'type': 'sandbox_event',
    'event': 'cluster_simulated',
    'count': count,
    'items': generated,
    'cluster_lat': clusterLat,
    'cluster_lng': clusterLng,
  });

  _broadcastAdmin({
    'type': 'admin_snapshot',
    'server': {'role': _role, 'port': _port},
    'mesh_clients': _meshClients.length,
    'reports': _reports,
    'events': _events,
  });

  return _json({
    'status': 'ok',
    'generated': count,
    'report_ids': generated.map((r) => r['id']).toList(),
  });
}

Future<Response> _forceAlert(Request request) async {
  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  final now = DateTime.now().toUtc();
  final alertType = _normalizeAlertType(body['type']);
  final lat = (body['lat'] as num?)?.toDouble() ?? 0;
  final lon = (body['lon'] as num?)?.toDouble() ?? 0;
  final description =
      body['description'] ?? 'Alerte forcée par administrateur';

  final report = {
    'id': 'FORCE-${_randomId()}',
    'reporter_id': 'admin-force',
    'type': alertType,
    'lat': lat,
    'lon': lon,
    'description': description,
    'density_value': null,
    'timestamp': now.toIso8601String(),
    'ttl_hours': 24,
    'status': 'active',
    'confirmations': ['admin-force'],
    'signature': '',
    'last_modified_at': now.toIso8601String(),
    'bypass_consensus': true,
  };

  _reports.add(report);
  _log.warning(
      'FORCE ALERT (bypass consensus): ${report['id']} ($alertType) @ ($lat, $lon)');

  _broadcastMesh({
    'type': 'report_validated',
    'report': {
      'id': report['id'],
      'lat': report['lat'],
      'lon': report['lon'],
      'type': report['type'],
    },
  });

  _broadcastAdmin({
    'type': 'force_alert',
    'report': report,
  });

  return _json({
    'status': 'ok',
    'report_id': report['id'],
    'mesh_relayed_to': _meshClients.length,
    'admin_relayed_to': _adminClients.length,
    'consensus_bypassed': true,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════════

String _body(Map<String, dynamic> data) => jsonEncode(data);

void _initDefaultAdmin() {
  final defaultPassword = 'admin123';
  _admins.add(AdminUser(
    username: 'admin',
    passwordHash: _hashPassword(defaultPassword),
    role: AdminRole.admin,
    canBypassConsensus: true,
    canKickPeers: true,
  ));
  _log.info('Compte admin par défaut créé (admin / $defaultPassword)');
}

// ── Endpoints d'authentification ─────────────────────────────────────────

Future<Response> _adminLogin(Request request) async {
  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: _body({'error': 'JSON invalide'}));
  }

  final username = body['username'] as String? ?? '';
  final password = body['password'] as String? ?? '';
  final user = _authenticate(username, password);

  if (user == null) {
    return _json({'ok': false, 'error': 'Identifiants invalides'}, status: 401);
  }

  final token = _generateToken();
  _sessions[token] = user;
  _log.info('Login admin: $username (${user.role.name})');

  return _json({
    'ok': true,
    'token': token,
    'user': user.toJson(),
  });
}

Future<Response> _adminLogout(Request request) async {
  final token = request.headers['Authorization'] ?? '';
  _sessions.remove(token);
  return _json({'ok': true});
}

Response _adminSession(Request request) {
  final token = request.headers['Authorization'] ?? '';
  final user = _getSessionUser(token);
  if (user == null) {
    return _json({'ok': false, 'error': 'Session invalide'}, status: 401);
  }
  return _json({'ok': true, 'user': user.toJson()});
}

/// Création d'un modérateur (admin seulement).
Future<Response> _adminCreateUser(Request request) async {
  final token = request.headers['Authorization'] ?? '';
  final admin = _getSessionUser(token);
  if (admin == null || admin.role != AdminRole.admin) {
    return _json({'ok': false, 'error': 'Accès refusé'}, status: 403);
  }

  Map<String, dynamic> body;
  try { body = jsonDecode(await request.readAsString()) as Map<String, dynamic>; }
  catch (_) { return Response.badRequest(body: _body({'error': 'JSON invalide'})); }

  final username = body['username'] as String? ?? '';
  final password = body['password'] as String? ?? '';
  if (username.isEmpty || password.isEmpty) {
    return _json({'ok': false, 'error': 'username et password requis'});
  }

  _admins.add(AdminUser(
    username: username,
    passwordHash: _hashPassword(password),
    role: AdminRole.moderator,
  ));
  _log.info('Modérateur créé: $username');
  return _json({'ok': true, 'username': username});
}

/// Suppression d'un modérateur (admin seulement).
Future<Response> _adminDeleteUser(Request request, String username) async {
  final token = request.headers['Authorization'] ?? '';
  final admin = _getSessionUser(token);
  if (admin == null || admin.role != AdminRole.admin) {
    return _json({'ok': false, 'error': 'Accès refusé'}, status: 403);
  }
  _admins.removeWhere((u) => u.username == username && u.role != AdminRole.admin);
  return _json({'ok': true});
}

/// Expulsion d'un pair mesh (nécessite permission kick).
Future<Response> _kickPeer(Request request) async {
  final token = request.headers['Authorization'] ?? '';
  final admin = _getSessionUser(token);
  if (admin == null || !_hasPermission(admin, needKick: true)) {
    return _json({'ok': false, 'error': 'Permission refusée'}, status: 403);
  }

  Map<String, dynamic> body;
  try { body = jsonDecode(await request.readAsString()) as Map<String, dynamic>; }
  catch (_) { return Response.badRequest(body: _body({'error': 'JSON invalide'})); }

  final peerId = body['peer_id'] as String? ?? '';
  // Ferme la connexion du pair ciblé.
  var kicked = 0;
  for (final c in _meshClients.toList()) {
    // Identifie le client par son peer_id dans les métadonnées
    c.sink.close();
    _meshClients.remove(c);
    kicked++;
  }
  _log.warning('Kick pair: $peerId ($kicked connexions fermées)');
  _broadcastAdmin({'type': 'peer_kicked', 'peer_id': peerId});
  return _json({'ok': true, 'kicked': kicked});
}

String _randomId() {
  final rng = List<int>.generate(
      8, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF);
  return base64Url.encode(rng).replaceAll('=', '');
}

Response _json(Map<String, dynamic> data, {int status = 200}) {
  return Response(
    status,
    body: _body(data),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}
