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
//   3. Sert un dashboard web d'administration sur /
//   4. Exporte les QR codes des événements

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

final _log = Logger('Server');
final _uuid = const Uuid();

// ============================================================================
// Application Router
// ============================================================================

Router _buildRouter(TileProxyService tileProxy) {
  final router = Router();

  // ── Dashboard admin ──────────────────────────────────────────────────
  router.get('/', (request) {
    return Response.ok(_adminHtml, headers: {
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
// Page HTML du dashboard admin
// ============================================================================

const String _adminHtml = r'''
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>StreetPhare — Admin Dashboard</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,sans-serif;background:#1a1a2e;color:#eee;min-height:100vh}
header{background:#16213e;padding:16px 24px;display:flex;align-items:center;justify-content:space-between;border-bottom:2px solid #0f3460}
header h1{font-size:20px;color:#e94560}
header .stats{font-size:13px;color:#aaa}
main{display:grid;grid-template-columns:1fr 1fr;gap:20px;padding:24px;max-width:1400px;margin:0 auto}
.panel{background:#16213e;border-radius:12px;padding:20px;border:1px solid #0f3460}
.panel h2{font-size:16px;margin-bottom:12px;color:#e94560;display:flex;align-items:center;gap:8px}
.panel h2 span{font-size:13px;color:#aaa;font-weight:normal}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{text-align:left;padding:8px 6px;border-bottom:1px solid #0f3460}
th{color:#aaa;font-weight:600}
.mono{font-family:monospace;font-size:12px}
.btn{padding:6px 14px;border:none;border-radius:6px;cursor:pointer;font-size:13px;font-weight:600;display:inline-flex;align-items:center;gap:4px;transition:all .2s}
.btn-primary{background:#e94560;color:#fff}
.btn-primary:hover{background:#c73050}
.btn-outline{background:transparent;border:1px solid #e94560;color:#e94560}
.btn-outline:hover{background:#e9456015}
.btn-danger{background:#d32f2f;color:#fff}
.form-group{margin-bottom:12px}
.form-group label{display:block;font-size:13px;color:#aaa;margin-bottom:4px}
.form-group input,.form-group textarea{width:100%;padding:8px 10px;border-radius:6px;border:1px solid #0f3460;background:#1a1a2e;color:#eee;font-size:13px;font-family:inherit}
.form-group textarea{resize:vertical;min-height:60px}
.qr-preview{text-align:center;padding:12px;background:#fff;border-radius:8px;display:inline-block}
.qr-preview img{max-width:256px;height:auto}
.empty-state{text-align:center;padding:32px;color:#666;font-style:italic}
.peer-count{display:inline-block;padding:4px 10px;background:#0f3460;border-radius:20px;font-size:12px;color:#4fc3f7}
.flex{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
@media(max-width:800px){main{grid-template-columns:1fr}}
</style>
</head>
<body>
<header>
<h1>🚦 StreetPhare — Admin Server</h1>
<div class="stats" id="statsBar">Pairs : <span id="peerCount">0</span> | Événements : <span id="eventCount">0</span></div>
</header>
<main>
<section class="panel" style="grid-column:1/-1">
<h2>📋 Événements <span id="eventCountHeader">(0)</span></h2>
<div id="eventsList"></div>
<div class="flex" style="margin-top:12px">
<button class="btn btn-primary" onclick="createEvent()">＋ Nouvel événement</button>
</div>
</section>
<section class="panel" id="eventDetailPanel" style="display:none;grid-column:1/-1">
<h2>✏️ Édition — <span id="detailTitle"></span></h2>
<div class="form-group"><label>Nom</label><input id="editName" type="text"></div>
<div class="form-group"><label>Description</label><textarea id="editDesc"></textarea></div>
<div class="flex" style="margin-top:12px">
<button class="btn btn-primary" onclick="saveEvent()">💾 Sauvegarder</button>
<button class="btn btn-outline" onclick="closeDetail()">Annuler</button>
</div>
<div style="margin-top:16px" id="qrPanel"></div>
</section>
<section class="panel">
<h2>🔌 Pairs connectés</h2>
<div id="peersPanel"><span class="peer-count" id="peerBadge">0 connecté(s)</span></div>
</section>
</main>
<script>
let events=[],selectedEventId=null,ws=null;
const api=async(url,opts={})=>{const r=await fetch(url,opts);return r.json()};
const load=async()=>{
events=await api('/api/events');
renderEvents();
const s=await api('/api/stats');
document.getElementById('eventCount').textContent=s.events_total;
document.getElementById('peerCount').textContent=s.peers;
document.getElementById('eventCountHeader').textContent=`(${s.events_total})`;
document.getElementById('peerBadge').textContent=`${s.peers} connecté(s)`;
};
const renderEvents=()=>{
const el=document.getElementById('eventsList');
if(!events.length){el.innerHTML='<div class="empty-state">Aucun événement créé</div>';return}
el.innerHTML=events.map(e=>`<tr>
<td><strong>${e.code}</strong></td>
<td>${e.name}</td>
<td class="mono">${e.created_at?.substring(0,10)||''}</td>
<td class="flex">
<button class="btn btn-outline" onclick="editEvent('${e.id}')">✏️</button>
<button class="btn btn-outline" onclick="showQr('${e.code}')">📱 QR</button>
<button class="btn btn-danger" onclick="deleteEvent('${e.id}')">🗑</button>
</td></tr>`).join('');
document.getElementById('eventsList').innerHTML='<table><thead><tr><th>Code</th><th>Nom</th><th>Créé le</th><th>Actions</th></tr></thead><tbody>'+document.getElementById('eventsList').innerHTML+'</tbody></table>';
};
const createEvent=()=>{const n=prompt('Nom de l\'événement :');if(!n)return;api('/api/events',{method:'POST',body:JSON.stringify({name:n})}).then(load)};
const editEvent=(id)=>{const e=events.find(x=>x.id===id);if(!e)return;selectedEventId=id;document.getElementById('eventDetailPanel').style.display='';document.getElementById('detailTitle').textContent=e.code;document.getElementById('editName').value=e.name;document.getElementById('editDesc').value=e.description||'';loadQr(e.code)};
const closeDetail=()=>{document.getElementById('eventDetailPanel').style.display='none';selectedEventId=null};
const saveEvent=()=>{if(!selectedEventId)return;const e=events.find(x=>x.id===selectedEventId);if(!e)return;e.name=document.getElementById('editName').value;e.description=document.getElementById('editDesc').value;api('/api/events',{method:'POST',body:JSON.stringify({...e,_action:'update'})}).then(load).then(closeDetail)};
const deleteEvent=(id)=>{if(!confirm('Supprimer cet événement ?'))return;api('/api/events',{method:'POST',body:JSON.stringify({id,_action:'delete'})}).then(load)};
const showQr=async(code)=>{const r=await api('/api/events/'+code+'/qr');const el=document.getElementById('qrPanel');el.innerHTML='<div class="qr-preview"><img src="'+r.qr+'" alt="QR Code"><p style="color:#333;font-size:12px;margin-top:8px"><code>SP_EVENT:'+code+'</code></p></div>'};
const loadQr=async(code)=>{const r=await api('/api/events/'+code+'/qr');const el=document.getElementById('qrPanel');el.innerHTML='<div class="qr-preview"><img src="'+r.qr+'" alt="QR Code"><p style="color:#333;font-size:12px;margin-top:8px"><code>'+code+'</code></p></div>'};
load();setInterval(load,10000);
</script>
</body>
</html>
''';

// ============================================================================
// Main — Lancement du serveur
// ============================================================================

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((rec) {
    final ts =
        '${rec.time.hour.toString().padLeft(2, '0')}:${rec.time.minute.toString().padLeft(2, '0')}:${rec.time.second.toString().padLeft(2, '0')}';
    print('[$ts] ${rec.level.name.toUpperCase()}: ${rec.message}');
  });

  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '3000')
    ..addOption('data', abbr: 'd', defaultsTo: 'events.json')
    ..addFlag('help', abbr: 'h', negatable: false);

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('StreetPhare Server v1.0.0');
    print('Usage: dart run bin/server.dart [options]');
    print(parser.usage);
    return;
  }

  final port = int.tryParse(results['port'] as String) ?? 3000;
  final dataFile = results['data'] as String;

  // Initialise le proxy de tuiles OSM (cache 30 jours)
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
  const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  // Montage du WebSocket
  final wsHandler = webSocketHandler(_handleWebSocket);
  final appRouter = Router()
    ..mount('/ws', wsHandler)
    ..mount('/', router);

  await io.serve(appRouter, '0.0.0.0', port);
  _log.info('Serveur démarré sur http://0.0.0.0:$port');
  _log.info('WebSocket : ws://0.0.0.0:$port/ws');
  _log.info('Dashboard : http://0.0.0.0:$port/');
  _log.info('Sauvegarde automatique : $dataFile (toutes les 60s)');
}