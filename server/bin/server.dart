// server/bin/server.dart
//
// Point d'entrée du serveur standalone StreetPhare.
//
// Usage :
//   dart run bin/server.dart [--port 3000] [--data events.json]
//
// Lance un serveur HTTP + WebSocket qui :
//   1. Écoute les clients StreetPhare via /ws
//   2. Synchronise les alertes admin et événements
//   3. Sert un dashboard web d'administration sécurisé sur /
//   4. Exporte les QR codes des événements
//   5. Gère l'authentification (Admin/Modérateur) et les permissions

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import 'package:streetphare_server/event_manager.dart';
import 'package:streetphare_server/qr_generator.dart';
import 'package:streetphare_server/models/event.dart';
import 'package:streetphare_server/map/tile_proxy_service.dart';
import 'package:streetphare_server/core/auth_manager.dart';
import 'package:streetphare_server/core/command_router.dart';
import 'package:streetphare_server/api/admin_handlers.dart';
import 'package:streetphare_server/web/admin_dashboard.dart';

final _log = Logger('Server');
final _uuid = const Uuid();

// ============================================================================
// Application Router
// ============================================================================

Router _buildRouter(TileProxyService tileProxy) {
  final router = Router();

  // ── Dashboard admin sécurisé ────────────────────────────────────────
  router.get('/', (request) {
    return Response.ok(adminDashboardHtml, headers: {
      'Content-Type': 'text/html; charset=utf-8',
    });
  });

  // ── Page de setup (accessible sans authentification) ────────────────
  router.get('/setup', (request) {
    return Response.ok(adminDashboardHtml, headers: {
      'Content-Type': 'text/html; charset=utf-8',
    });
  });

  // ── API REST : liste des événements ──────────────────────────────────
  router.get('/api/events', (request) {
    final events =
        EventManager.instance.all.map((e) => e.toJson()).toList();
    return Response.ok(
      jsonEncode(events),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── API REST : événement par code ───────────────────────────────────
  router.get('/api/events/<code>', (request, String code) {
    final event = EventManager.instance.findByCode(code);
    if (event == null) {
      return Response.notFound(
          jsonEncode({'error': 'Événement introuvable'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'});
    }
    return Response.ok(
      jsonEncode(event.toJson()),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── API REST : QR code d'un événement ───────────────────────────────
  router.get('/api/events/<code>/qr', (request, String code) {
    final event = EventManager.instance.findByCode(code);
    if (event == null) {
      return Response.notFound(
          jsonEncode({'error': 'Événement introuvable'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'});
    }
    final qrDataUri = QrGenerator.instance.generateEventQr(event);
    return Response.ok(
      jsonEncode({'qr': qrDataUri, 'code': code}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── API REST : créer / modifier un événement ────────────────────────
  router.post('/api/events', (request) async {
    try {
      final body = await request.readAsString();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final existingId = map['id'] as String?;

      if (existingId != null && map.containsKey('_action')) {
        final action = map['_action'] as String;
        if (action == 'delete') {
          EventManager.instance.delete(existingId);
          return Response.ok(
              jsonEncode({'deleted': true}),
              headers: {'Content-Type': 'application/json; charset=utf-8'});
        }
        if (action == 'update') {
          final event = _parseEventFromMap(map);
          final updated = EventManager.instance.update(event);
          return Response.ok(
              jsonEncode({'updated': true, 'event': updated?.toJson()}),
              headers: {'Content-Type': 'application/json; charset=utf-8'});
        }
      }

      // Création d'un nouvel événement
      final name = map['name'] as String? ?? 'Événement sans nom';
      final desc = map['description'] as String? ?? '';
      final event = EventManager.instance.createWithGeneratedCode(
        name: name,
        description: desc,
      );
      return Response.ok(
        jsonEncode({'created': true, 'event': event.toJson()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── API REST : statistiques ─────────────────────────────────────────
  router.get('/api/stats', (request) {
    final stats = {
      'events_total': EventManager.instance.count,
      'events_active': EventManager.instance.currentlyActive.length,
      'peers': _connectedPeers.length,
      'tile_cache': tileProxy.stats,
    };
    return Response.ok(
      jsonEncode(stats),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── Proxy de tuiles OSM ─────────────────────────────────────────────
  router.get('/tiles/<zoom>/<x>/<y>', tileProxy.handler);

  // ── Page de setup (accessible sans authentification) ────────────────
  router.get('/setup', (request) {
    return Response.ok(adminDashboardHtml, headers: {
      'Content-Type': 'text/html; charset=utf-8',
    });
  });

  return router;
}

// ============================================================================
// WebSocket — Clients StreetPhare
// ============================================================================

final Set<WebSocketChannel> _connectedPeers = {};

void _handleWebSocket(WebSocketChannel channel) {
  final peerId = _uuid.v4();
  _connectedPeers.add(channel);
  _log.info('[WS] Client connecté : $peerId (total=${_connectedPeers.length})');

  // ── Synchronisation initiale : push des alertes admin manquantes ──
  _pushFullSync(channel);

  channel.stream.listen(
    (data) {
      _handleClientMessage(channel, data as String);
    },
    onDone: () {
      _connectedPeers.remove(channel);
      _log.info('[WS] Client déconnecté : $peerId (total=${_connectedPeers.length})');
    },
    onError: (error) {
      _connectedPeers.remove(channel);
      _log.warning('[WS] Erreur client $peerId : $error');
    },
    cancelOnError: true,
  );
}

/// Pousse la synchronisation complète des événements au client.
void _pushFullSync(WebSocketChannel channel) {
  try {
    final events = EventManager.instance.all;
    for (final event in events) {
      final syncPayload = {
        'kind': 'event_sync',
        'event': event.toJson(),
        'qr': QrGenerator.instance.generateEventQr(event),
        'ts': DateTime.now().toUtc().toIso8601String(),
      };
      channel.sink.add(jsonEncode(syncPayload));
    }
    _log.fine('Sync poussée : ${events.length} événements');
  } catch (e) {
    _log.warning('Erreur sync push : $e');
  }
}

void _handleClientMessage(WebSocketChannel channel, String raw) {
  try {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final kind = msg['kind'] as String?;

    switch (kind) {
      case 'ping':
        channel.sink.add(jsonEncode({'kind': 'pong', 'ts': DateTime.now().toUtc().toIso8601String()}));
        break;

      case 'request_event':
        final code = msg['code'] as String?;
        if (code != null) {
          final event = EventManager.instance.findByCode(code);
          if (event != null) {
            channel.sink.add(jsonEncode({
              'kind': 'event_data',
              'event': event.toJson(),
              'qr': QrGenerator.instance.generateEventQr(event),
            }));
          } else {
            channel.sink.add(jsonEncode({
              'kind': 'event_not_found',
              'code': code,
            }));
          }
        }
        break;

      case 'alert_report':
        // Un client signale une alerte — on la log et on la rediffuse.
        _log.info('[Alert] ${msg['type']} @ ${msg['lat']}, ${msg['lng']}');
        _broadcastToPeers(jsonEncode({
          'kind': 'alert_broadcast',
          'alert': msg,
          'ts': DateTime.now().toUtc().toIso8601String(),
        }));
        break;

      default:
        _log.fine('Message client inconnu : $kind');
    }
  } catch (e) {
    _log.warning('Erreur traitement message client : $e');
  }
}

void _broadcastToPeers(String payload) {
  final dead = <WebSocketChannel>[];
  for (final channel in _connectedPeers) {
    try {
      channel.sink.add(payload);
    } catch (_) {
      dead.add(channel);
    }
  }
  for (final d in dead) {
    _connectedPeers.remove(d);
  }
}

// ============================================================================
// Parsing des events depuis le formulaire admin
// ============================================================================

ServerEvent _parseEventFromMap(Map<String, dynamic> map) {
  return ServerEvent(
    id: map['id'] as String? ?? _uuid.v4(),
    code: map['code'] as String? ?? 'UNKNOWN',
    name: map['name'] as String? ?? '',
    description: map['description'] as String? ?? '',
    createdAt: map['created_at'] != null
        ? DateTime.parse(map['created_at'] as String)
        : DateTime.now().toUtc(),
    startTime: map['start_time'] != null
        ? DateTime.parse(map['start_time'] as String)
        : null,
    endTime: map['end_time'] != null
        ? DateTime.parse(map['end_time'] as String)
        : null,
  );
}

// ============================================================================
// Main — Lancement du serveur
// ============================================================================

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((rec) {
    final ts =
        '${rec.time.hour.toString().padLeft(2, '0')}:${rec.time.minute.toString().padLeft(2, '0')}:${rec.time.second.toString().padLeft(2, '0')}';
    stdout.writeln('[$ts] ${rec.level.name.toUpperCase()}: ${rec.message}');
  });

  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '3000')
    ..addOption('data', abbr: 'd', defaultsTo: 'events.json')
    ..addFlag('help', abbr: 'h', negatable: false);

  final results = parser.parse(args);

  if (results['help'] as bool) {
    _log.info('StreetPhare Server v1.0.0');
    _log.info('Usage: dart run bin/server.dart [options]');
    _log.info(parser.usage);
    return;
  }

  final port = int.tryParse(results['port'] as String) ?? 3000;
  final dataFile = results['data'] as String;

  // Initialise le gestionnaire d'authentification (setup run, sessions, RBAC).
  await AuthManager.instance.init();

  // Initialise le routeur de commandes (matrice de permissions).
  await CommandRouter.instance.init();

  // Initialise le proxy de tuiles OSM (cache 30 jours).
  final tileProxy = TileProxyService(
    cacheDir: 'tiles_cache',
    userAgent: 'StreetPhare/2.2.0',
  );
  await tileProxy.init();

  // Charge les événements persistés
  final loaded = await EventManager.instance.loadFromFile(dataFile);
  _log.info('$loaded événements chargés depuis $dataFile');

  // Sauvegarde automatique toutes les 60 secondes
  Timer.periodic(const Duration(seconds: 60), (_) async {
    await EventManager.instance.saveToFile(dataFile);
  });

  // Gestionnaire d'arrêt propre
  ProcessSignal.sigint.watch().listen((_) async {
    _log.info('Arrêt du serveur…');
    await EventManager.instance.saveToFile(dataFile);
    exit(0);
  });

  // Construction du serveur
  final router = _buildRouter(tileProxy);
  final adminRouter = buildAdminRouter();

  // Pipeline principal.
  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  // Montage du WebSocket
  final wsHandler = webSocketHandler(_handleWebSocket);
  final appRouter = Router()
    ..mount('/ws', wsHandler)
    ..mount('/api/', adminRouter.call) // Routes admin (authentification intégrée via authMiddleware)
    ..mount('/', pipeline);

  await io.serve(appRouter.call, '0.0.0.0', port);
  _log.info('Serveur démarré sur http://0.0.0.0:$port');
  _log.info('WebSocket : ws://0.0.0.0:$port/ws');
  _log.info('Dashboard : http://0.0.0.0:$port/');
  _log.info('Setup : http://0.0.0.0:$port/setup (premier lancement)');
  _log.info('Sauvegarde automatique : $dataFile (toutes les 60s)');
  _log.info('Authentification : ${AuthManager.instance.isSetupComplete ? "✅ Active" : "⚠️ Setup requis"}');
}