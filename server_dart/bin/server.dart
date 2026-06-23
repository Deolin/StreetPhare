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
//   GET  /healthz           — healthcheck (utilisé par le failover)
//   GET  /status            — topologie complète
//   GET  /api/version/check — kill switch version
//   GET  /v1/events         — catalogue événements
//   GET  /v1/events/:id     — détail événement
//   POST /v1/events/:id/route — calcul Safe Route
//   POST /v1/reports        — signalement danger
//   GET  /v1/reports        — liste signalements validés
//   POST /v1/panic          — alerte PANIC
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
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logging/logging.dart';

import 'package:streetphare_server/crypto_utils.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Configuration
// ══════════════════════════════════════════════════════════════════════════════

final _port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
final _role = Platform.environment['ROLE'] ?? 'primary';
final _primaryUrl =
    Platform.environment['PRIMARY_URL'] ?? 'http://127.0.0.1:3000';
const _appMinVersion = '2.2.0';

final _log = Logger('StreetPhareServer');

// ══════════════════════════════════════════════════════════════════════════════
// Stockage en mémoire
// ══════════════════════════════════════════════════════════════════════════════

/// Signalements de dangers validés.
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

  // ── Pipeline CORS + JSON ──────────────────────────────────────────────
  final pipeline = Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(app);

  // ── WebSocket Mesh ────────────────────────────────────────────────────
  final wsHandler = webSocketHandler((WebSocketChannel channel, _) {
    _registerMeshClient(channel);
  });

  // ── WebSocket Admin ───────────────────────────────────────────────────
  final adminWsHandler = webSocketHandler((WebSocketChannel channel, _) {
    _registerAdminClient(channel);
  });

  // ── Démarrage ─────────────────────────────────────────────────────────
  // Handler racine : route /mesh et /admin vers les WebSocket,
  // toutes les autres requêtes vers le pipeline HTTP.
  FutureOr<Response> rootHandler(Request request) {
    if (request.url.path == 'mesh') return wsHandler(request);
    if (request.url.path == 'admin') return adminWsHandler(request);
    return pipeline(request);
  }

  final server = await shelf_io.serve(rootHandler, InternetAddress.anyIPv4, _port);
  _log.info('StreetPhare serveur $_role démarré sur le port $_port');
  _log.info('  HTTP      : http://0.0.0.0:$_port');
  _log.info('  WS Mesh   : ws://0.0.0.0:$_port/mesh');
  _log.info('  WS Admin  : ws://0.0.0.0:$_port/admin');

  // Nettoyage propre.
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

Response _ping(Request request) => _json({'status': 'ok', 'role': _role, 'ts': DateTime.now().toUtc().toIso8601String()});

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
      'validated': _reports.where((r) => r['status'] == 'validated').length,
      'active': _reports.where((r) => r['status'] == 'validated' && r['active'] == true).length,
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
  final events = activeOnly ? _events.where((e) => e['active'] == true).toList() : _events;
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

  final originLat = (body['lat'] as num?)?.toDouble() ?? 0;
  final originLng = (body['lng'] as num?)?.toDouble() ?? 0;

  // Récupère les zones dangereuses validées pour les éviter.
  final dangerZones = _reports
      .where((r) => r['status'] == 'validated' && r['active'] == true)
      .map((r) => {
            'lat': r['lat'],
            'lng': r['lng'],
            'radius_m': r['radius_m'] ?? 200,
          })
      .toList();

  // Construit l'itinéraire principal (ligne droite jusqu'à l'événement).
  final route = _buildRoute(originLat, originLng, (event['lat'] as num).toDouble(), (event['lng'] as num).toDouble(), dangerZones);

  // Génère 3 alternatives.
  final alternatives = List.generate(3, (i) {
    final offsetLat = (i + 1) * 0.001;
    final offsetLng = (i - 1) * 0.001;
    return _buildRoute(
        originLat, originLng, (event['lat'] as num).toDouble() + offsetLat, (event['lng'] as num).toDouble() + offsetLng, dangerZones);
  });

  return _json({
    'event_id': id,
    'origin': {'lat': originLat, 'lng': originLng},
    'destination': {'lat': event['lat'], 'lng': event['lng']},
    'route': route,
    'alternatives': alternatives,
    'danger_zones_avoided': dangerZones.length,
  });
}

Map<String, dynamic> _buildRoute(double fromLat, double fromLng, double toLat, double toLng, List<Map<String, dynamic>> dangerZones) {
  const steps = 20;
  final waypoints = <Map<String, dynamic>>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    var lat = fromLat + (toLat - fromLat) * t;
    var lng = fromLng + (toLng - fromLng) * t;

    // Évitement basique des zones dangereuses.
    for (final zone in dangerZones) {
      final dLat = lat - (zone['lat'] as num).toDouble();
      final dLng = lng - (zone['lng'] as num).toDouble();
      final dist = (dLat * dLat + dLng * dLng) * 111000; // degrés → mètres approximatifs
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
    'duration_min': (distanceKm / 1.4).toStringAsFixed(0), // ~1.4 m/s marche
  };
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
  final dLng = (lng2 - lng1) * 3.141592653589793 / 180;
  final a = _sinHalf(dLat) * _sinHalf(dLat) + _cos(lat1 * 3.141592653589793 / 180) * _cos(lat2 * 3.141592653589793 / 180) * _sinHalf(dLng) * _sinHalf(dLng);
  return r * 2 * _atan2(_sqrt(a), _sqrt(1 - a));
}

double _sinHalf(double x) {
  final s = _sin(x / 2);
  return s * s;
}

double _sin(double x) {
  // Série de Taylor degré 3 pour sin (sans dart:math).
  return x - x * x * x / 6 + x * x * x * x * x / 120;
}

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

  final report = {
    'id': _randomId(),
    'type': body['type'] ?? 'danger',
    'lat': body['lat'] ?? 0,
    'lng': body['lng'] ?? 0,
    'description': body['description'] ?? '',
    'status': 'pending',
    'active': true,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'reports_count': 1,
    'signature': body['signature'],
    'public_key': body['public_key'],
  };

  _reports.add(report);
  _log.info('Nouveau signalement: ${report['id']} (${report['type']})');

  // Propager aux clients mesh.
  _broadcastMesh({
    'type': 'new_report',
    'report': {
      'id': report['id'],
      'type': report['type'],
      'lat': report['lat'],
      'lng': report['lng'],
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
  final validatedOnly = request.url.queryParameters['validated'] == 'true';
  final reports = validatedOnly ? _reports.where((r) => r['status'] == 'validated').toList() : _reports;
  final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
  final lng = double.tryParse(request.url.queryParameters['lng'] ?? '');
  final radiusKm = double.tryParse(request.url.queryParameters['radius_km'] ?? '5') ?? 5;

  var filtered = reports;
  if (lat != null && lng != null) {
    filtered = reports.where((r) {
      final d = _haversineKm(lat, lng, (r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
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
    'lat': body['lat'] ?? 0,
    'lng': body['lng'] ?? 0,
    'message': body['message'] ?? 'ALERTE PANIC',
    'contacts': body['contacts'] ?? [],
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };

  _log.warning('ALERTE PANIC reçue: ${panicAlert['id']}');

  // Propager immédiatement à tous les clients mesh.
  _broadcastMesh({
    'type': 'panic_alert',
    'alert': panicAlert,
  });

  _broadcastAdmin({
    'type': 'panic_alert',
    'alert': panicAlert,
  });

  return _json({'status': 'ok', 'panic_id': panicAlert['id'], 'mesh_relayed_to': _meshClients.length});
}

// ══════════════════════════════════════════════════════════════════════════════
// WebSocket Mesh — Relais P2P
// ══════════════════════════════════════════════════════════════════════════════

void _registerMeshClient(WebSocketChannel channel) {
  _meshClients.add(channel);
  _log.info('Mesh client connecté (total: ${_meshClients.length})');

  // Envoie l'état courant au nouveau client.
  channel.sink.add(jsonEncode({
    'type': 'mesh_status',
    'connected_clients': _meshClients.length,
    'active_reports': _reports.where((r) => r['active'] == true).length,
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
      sender.sink.add(jsonEncode({'type': 'pong', 'ts': DateTime.now().toUtc().toIso8601String()}));
      break;

    case 'alert':
    case 'report':
    case 'broadcast':
      // Relayer à tous les autres clients mesh.
      for (final client in _meshClients) {
        if (client != sender) {
          client.sink.add(jsonEncode(msg));
        }
      }
      break;

    case 'peer_discovery':
      // Répond avec la liste des événements actifs.
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

  // Envoie le snapshot complet.
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

void _handleAdminMessage(WebSocketChannel sender, Map<String, dynamic> msg) {
  final type = msg['type'] as String?;

  switch (type) {
    case 'validate_report':
      final reportId = msg['report_id'] as String?;
      if (reportId != null) {
        final report = _reports.where((r) => r['id'] == reportId).firstOrNull;
        if (report != null) {
          report['status'] = 'validated';
          _log.info('Signalement validé: $reportId');
          _broadcastAdmin({'type': 'report_updated', 'report': report});
          _broadcastMesh({
            'type': 'report_validated',
            'report': {
              'id': report['id'],
              'lat': report['lat'],
              'lng': report['lng'],
              'type': report['type'],
            },
          });
          sender.sink.add(jsonEncode({'type': 'validation_ok', 'report_id': reportId}));
        }
      }
      break;

    case 'reject_report':
      final reportId = msg['report_id'] as String?;
      if (reportId != null) {
        final report = _reports.where((r) => r['id'] == reportId).firstOrNull;
        if (report != null) {
          report['status'] = 'rejected';
          report['active'] = false;
          _log.info('Signalement rejeté: $reportId');
          _broadcastAdmin({'type': 'report_updated', 'report': report});
          sender.sink.add(jsonEncode({'type': 'rejection_ok', 'report_id': reportId}));
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
// Helpers
// ══════════════════════════════════════════════════════════════════════════════

Response _json(Map<String, dynamic> data) {
  return Response.ok(
    _body(data),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}

String _body(Map<String, dynamic> data) => jsonEncode(data);

String _randomId() {
  final rng = List<int>.generate(8, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF);
  return base64Url.encode(rng).replaceAll('=', '');
}