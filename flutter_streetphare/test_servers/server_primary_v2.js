// test_servers/server_primary_v2.js
//
// StreetPhare — SERVEUR PRINCIPAL v2 (Port 3000)
// ===============================================
// Version enrichie du serveur primaire. Intègre :
//
//   ✅  Module Événements & Itinéraires Safe Route (events_manager)
//   ✅  Module Signalements avec TTL, votes, Panic Collectif (reports_store)
//   ✅  Heartbeat /ping + /healthz + /status enrichi
//   ✅  Rétrocompatibilité avec les endpoints v1 (alertes, backup-route)
//
// ── ENDPOINTS ─────────────────────────────────────────────────────────────
//
//  Heartbeat & Statut
//    GET  /ping                    heartbeat simple (spec Flutter)
//    GET  /healthz                 heartbeat FailoverManager
//    GET  /status                  topologie complète JSON
//
//  Événements (Fleurus 6220)
//    GET  /v1/events               liste tous les événements
//    GET  /v1/events/:id           détails + QR payload
//    POST /v1/events/:id/route     calcule Safe Route (1 principal + 3 alts)
//
//  Signalements (Dangers & Zones)
//    POST /v1/reports              soumet un signalement (vote/nouveau)
//    GET  /v1/reports              liste les signalements visibles (votes >= 3)
//    GET  /v1/reports/stats        statistiques (panic queue, etc.)
//
//  Compatibilité v1 (FailoverManager Flutter)
//    POST /alerts                  réception alerte (consensus 3)
//    POST /v1/alerts/sync          sync alertes + next_backup chiffré
//    GET  /backup-route            adresse chiffrée du serveur suivant
//
//  Debug (admin)
//    GET  /_debug/store            snapshot du store d'alertes legacy
//    GET  /_debug/reports          snapshot complet du store v2
//    POST /_debug/demote           forcer la démission (test failover)
//
// ─────────────────────────────────────────────────────────────────────────
'use strict';

const http    = require('http');
const express = require('express');
const path    = require('path');
const { WebSocketServer } = require('ws');

// ── Modules StreetPhare ──────────────────────────────────────────────────
const eventsManager  = require('./modules/events_manager');
const reportsStore   = require('./modules/reports_store');
const { buildStatusResponse } = require('./modules/heartbeat_monitor');
const { encryptAddress }      = require('./server_crypto');

// ── Logger de tableau de bord ────────────────────────────────────────────
const dash = (() => {
  if (process.env.STREETPHARE_LOG === '0') {
    const noop = () => {};
    return {
      init: noop, pingReceived: noop, alertReceived: noop,
      consensusReached: noop, promoted: noop, demoted: noop,
      setCurrentRole: noop, setOnline: noop, failoverTriggered: noop,
      backupRequested: noop, broadcastEvent: noop, mergeNode: noop,
      getOutputFile: () => null, getState: () => ({}),
    };
  }
  return require('./logger');
})();

// ── Configuration ────────────────────────────────────────────────────────
const PORT              = parseInt(process.env.PORT  || '3000', 10);
const ROLE              = (process.env.ROLE           || 'primary').trim();
const MASTER_PASSPHRASE = (process.env.STREETPHARE_MASTER_KEY
                          || 'streetphare-dev-key-CHANGE_ME_IN_PROD').trim();
const NEXT_BACKUP_CLEAR = (process.env.NEXT_BACKUP_URL || 'http://localhost:3001').trim();
const SELF_URL          = `http://localhost:${PORT}`;

// ── Initialisation du dashboard ──────────────────────────────────────────
dash.init({ role: ROLE, port: PORT, name: 'Principal', url: SELF_URL });

// ── Application Express ──────────────────────────────────────────────────
const app = express();
app.use(express.json({ limit: '2mb' }));

// ── Logger horodaté ──────────────────────────────────────────────────────
function log(...args) {
  console.log(`[${new Date().toISOString()}][primary:${PORT}]`, ...args);
}

// ── Abonnement aux changements du store v2 → dashboard ─────────────────
reportsStore.onStoreChange((event, id, entry) => {
  if (event === 'NEW' || event === 'VOTE') {
    const votes = entry.voters ? entry.voters.size : 0;
    dash.alertReceived(id, entry, votes, reportsStore.VOTES_REQUIRED_FOR_DISTRIBUTION);
    if (votes >= reportsStore.VOTES_REQUIRED_FOR_DISTRIBUTION) {
      dash.consensusReached(id, entry);
    }
  }
  if (event === 'COLLECTIVE_DANGER') {
    dash.broadcastEvent('PANIC', '🚨', 'Danger Collectif généré', entry.description);
  }
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 1 — HEARTBEAT & STATUT
// ════════════════════════════════════════════════════════════════════════

// GET /ping — heartbeat simple (spec demandée par Flutter)
app.get('/ping', (_req, res) => {
  dash.pingReceived('GET /ping');
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// GET /healthz — heartbeat utilisé par HeartbeatMonitor
app.get('/healthz', (_req, res) => {
  dash.pingReceived('GET /healthz');
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// GET /status — topologie complète (utilisé par le backup pour surveillance)
app.get('/status', (_req, res) => {
  const response = buildStatusResponse({
    selfRole: ROLE,
    selfUrl:  SELF_URL,
    monitor:  null,          // le primaire ne surveille pas de backup par défaut
    port:     PORT,
  });
  res.json({
    ...response,
    next_backup: NEXT_BACKUP_CLEAR,
    reports_active: reportsStore.getActiveReports().total_active,
    panic_pending:  reportsStore.getPendingPanicCount(),
  });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 2 — ÉVÉNEMENTS (Fleurus 6220)
// ════════════════════════════════════════════════════════════════════════

/**
 * GET /v1/events
 * Liste tous les événements disponibles.
 *
 * Réponse Flutter :
 *   { events: [...], generated_at: ISO8601 }
 */
app.get('/v1/events', (_req, res) => {
  const events = eventsManager.getAllEvents();
  log(`GET /v1/events — ${events.length} événements`);
  dash.broadcastEvent('INFO', '📅', 'Événements demandés', `${events.length} événements`);
  res.json({ events, generated_at: new Date().toISOString() });
});

/**
 * GET /v1/events/:id
 * Détails complets d'un événement, dont le QR payload.
 *
 * Réponse Flutter :
 *   { event: {..., qr_payload: string }, generated_at }
 */
app.get('/v1/events/:id', (req, res) => {
  const event = eventsManager.getEventById(req.params.id);
  if (!event) {
    return res.status(404).json({ error: 'Événement introuvable', id: req.params.id });
  }
  log(`GET /v1/events/${req.params.id}`);
  res.json({ event, generated_at: new Date().toISOString() });
});

/**
 * POST /v1/events/:id/route
 * Calcule les itinéraires Safe Route pour l'événement donné.
 *
 * Corps attendu (optionnel) :
 *   { from: { lat: number, lon: number } }
 *
 * Réponse Flutter :
 *   {
 *     event_id : string,
 *     source   : 'local_graph'|'graphhopper',
 *     routes   : [
 *       { id, label, distance_m, duration_s, safe_score,
 *         polyline: [[lat,lon]], warnings: [...] }
 *     ],
 *     danger_zones_count : number,
 *     generated_at       : ISO8601
 *   }
 */
app.post('/v1/events/:id/route', async (req, res) => {
  const eventId    = req.params.id;
  const fromOverride = req.body && req.body.from ? req.body.from : null;

  // Récupérer les zones dangereuses validées (votes >= 3, TTL actif)
  const dangerZones = reportsStore.getValidatedDangerZones();
  log(`POST /v1/events/${eventId}/route — ${dangerZones.length} zone(s) danger active(s)`);

  try {
    const result = await eventsManager.computeSafeRoutes(eventId, dangerZones, fromOverride);
    if (result.error) {
      return res.status(404).json({ error: result.error, event_id: eventId });
    }
    dash.broadcastEvent(
      'ROUTE', '🗺️', 'Calcul Safe Route',
      `Événement ${eventId} — ${result.routes.length} itinéraire(s) | ${dangerZones.length} danger(s)`,
    );
    res.json({
      ...result,
      danger_zones_count: dangerZones.length,
      generated_at: new Date().toISOString(),
    });
  } catch (err) {
    log(`ERREUR route ${eventId}: ${err.message}`);
    res.status(500).json({ error: 'Erreur calcul itinéraire', details: err.message });
  }
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 3 — SIGNALEMENTS (Dangers & Zones)
// ════════════════════════════════════════════════════════════════════════

/**
 * POST /v1/reports
 * Soumet un nouveau signalement ou un vote sur un signalement existant.
 *
 * Corps attendu :
 *   {
 *     id          : string   — UUID côté client
 *     type        : 'barrage'|'casseurs'|'danger'|'policiers'|
 *                   'autopompes'|'filtre'|'panic'
 *     lat         : number
 *     lon         : number
 *     reporter_id : string   — ID anonyme de l'appareil
 *     description : string   (optionnel)
 *   }
 *
 * Réponse Flutter :
 *   {
 *     ok           : boolean
 *     id           : string
 *     votes        : number
 *     distributed  : boolean     — vrai si visible (votes >= 3)
 *     expires_in_s : number
 *     panic_result : object|null — résultat Panic Collectif si type=panic
 *   }
 */
app.post('/v1/reports', (req, res) => {
  const payload = req.body || {};
  const result  = reportsStore.addReport(payload);

  if (!result.ok) {
    return res.status(400).json(result);
  }

  log(
    `POST /v1/reports — type=${payload.type} id=${payload.id} ` +
    `votes=${result.votes} distributed=${result.distributed}`,
  );

  if (result.panic_result && result.panic_result.triggered) {
    log(`🚨 PANIC COLLECTIF DÉCLENCHÉ — id=${result.panic_result.danger_id}`);
  }

  res.json(result);
});

/**
 * GET /v1/reports
 * Retourne la liste des signalements visibles (votes >= 3 ou collectif).
 *
 * Réponse Flutter :
 *   {
 *     reports: [
 *       { id, type, lat, lon, votes, expires_at,
 *         ttl_remaining_s, is_collective_danger, description }
 *     ],
 *     generated_at  : ISO8601,
 *     total_active  : number
 *   }
 */
app.get('/v1/reports', (_req, res) => {
  const data = reportsStore.getActiveReports();
  log(`GET /v1/reports — ${data.total_active} signalement(s) actif(s)`);
  res.json(data);
});

/**
 * GET /v1/reports/stats
 * Statistiques sur la file panic et les constantes de configuration.
 */
app.get('/v1/reports/stats', (_req, res) => {
  res.json({
    panic_queue_size:              reportsStore.getPendingPanicCount(),
    panic_threshold:               reportsStore.PANIC_THRESHOLD_COUNT,
    panic_window_s:                reportsStore.PANIC_WINDOW_S,
    panic_cluster_radius_m:        reportsStore.PANIC_CLUSTER_RADIUS_M,
    votes_required:                reportsStore.VOTES_REQUIRED_FOR_DISTRIBUTION,
    ttl_by_type:                   reportsStore.TTL_BY_TYPE,
    total_active_reports:          reportsStore.getActiveReports().total_active,
    generated_at:                  new Date().toISOString(),
  });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 4 — RÉTROCOMPATIBILITÉ v1 (FailoverManager Flutter)
// ════════════════════════════════════════════════════════════════════════

// Store legacy (v1 — consensus 3 par id unique)
const alertStore = new Map();

function ensureAlert(id, payload) {
  if (!alertStore.has(id)) {
    alertStore.set(id, { payload: payload || null, confirmations: new Set(), validatedAt: null });
  }
  return alertStore.get(id);
}

function handleAlertPayload(a) {
  if (!a || typeof a.id !== 'string') {
    return { id: a && a.id, ok: false, reason: 'id manquant' };
  }
  const entry  = ensureAlert(a.id, a);
  const confs  = Array.isArray(a.confirmations) ? a.confirmations : [];
  for (const c of confs) entry.confirmations.add(c);
  const validated  = entry.confirmations.size >= 3 && !entry.validatedAt;
  const wasValidated = !!entry.validatedAt;
  if (validated) entry.validatedAt = new Date().toISOString();
  if (!wasValidated) {
    dash.alertReceived(a.id, entry.payload, entry.confirmations.size, 3);
    if (entry.confirmations.size >= 3) dash.consensusReached(a.id, entry.payload);
  }
  return { id: a.id, ok: true, consensus: validated, confirmations: entry.confirmations.size };
}

// POST /alerts — réception alerte legacy (spec Flutter)
app.post('/alerts', (req, res) => {
  const body = req.body || {};
  if (body && typeof body.id === 'string') {
    const entry    = ensureAlert(body.id, body);
    const confs    = Array.isArray(body.confirmations) ? body.confirmations : [];
    const wasValid = !!entry.validatedAt;
    for (const c of confs) entry.confirmations.add(c);
    if (entry.confirmations.size >= 3 && !entry.validatedAt) {
      entry.validatedAt = new Date().toISOString();
      if (!wasValid) { dash.alertReceived(body.id, body, 3, 3); dash.consensusReached(body.id, body); }
      return res.json({ status: 'stored', id: body.id, consensus: true });
    }
    if (!wasValid) dash.alertReceived(body.id, body, entry.confirmations.size, 3);
    return res.json({ status: 'pending', id: body.id, confirmations: entry.confirmations.size });
  }
  if (Array.isArray(body.alerts)) {
    return res.json({ ok: true, results: body.alerts.map(handleAlertPayload) });
  }
  return res.status(400).json({ error: 'Format invalide' });
});

// POST /v1/alerts/sync — sync FailoverManager + next_backup chiffré
app.post('/v1/alerts/sync', (req, res) => {
  const body    = req.body || {};
  const results = Array.isArray(body.alerts) ? body.alerts.map(handleAlertPayload) : [];
  const cipher  = encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE);
  log(`sync reçu : ${results.length} alerte(s) ; next_backup=${NEXT_BACKUP_CLEAR}`);
  dash.broadcastEvent('SYNC', '🔄', 'Sync alertes', `${results.length} alerte(s)`);
  res.json({ ok: true, server: SELF_URL, next_backup: cipher, results });
});

// GET /backup-route — adresse chiffrée du serveur de secours
app.get('/backup-route', (_req, res) => {
  const cipher = encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE);
  log(`backup-route demandé → ${NEXT_BACKUP_CLEAR} (chiffré)`);
  dash.backupRequested(cipher);
  res.json({
    next:           NEXT_BACKUP_CLEAR,
    encrypted_next: cipher,
    algorithm:      'AES-256-CBC+HMAC-SHA256',
  });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 5 — DEBUG (admin)
// ════════════════════════════════════════════════════════════════════════

// GET /_debug/store — store v1 legacy
app.get('/_debug/store', (_req, res) => {
  const out = [];
  for (const [id, e] of alertStore.entries()) {
    out.push({ id, confirmations: e.confirmations.size, validatedAt: e.validatedAt });
  }
  res.json({ count: alertStore.size, alerts: out });
});

// GET /_debug/reports — store v2 complet
app.get('/_debug/reports', (_req, res) => {
  res.json(reportsStore.getDebugSnapshot());
});

// POST /_debug/demote — forcer la démission (test failover)
app.post('/_debug/demote', (req, res) => {
  const reason = (req.body && req.body.reason) || 'Démission manuelle';
  log(`DÉMISSION demandée : ${reason}`);
  dash.demoted(reason);
  setTimeout(() => process.exit(0), 200);
  res.json({ ok: true, demoted: true, reason });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 6 — WEBSOCKET RELAY /mesh
// ════════════════════════════════════════════════════════════════════════

// Serveur HTTP partagé entre Express et le WebSocket server
const httpServer = http.createServer(app);

// Ensemble des clients WebSocket connectés au relay /mesh
const meshClients = new Set();
const wss = new WebSocketServer({ noServer: true });

// Intercepte l'upgrade HTTP → WebSocket uniquement sur /mesh
httpServer.on('upgrade', (req, socket, head) => {
  const pathname = new URL(req.url, `http://localhost:${PORT}`).pathname;
  if (pathname === '/mesh') {
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  } else {
    socket.destroy();
  }
});

wss.on('connection', (ws, req) => {
  const qs     = new URL(req.url, `http://localhost:${PORT}`).searchParams;
  const peerId = qs.get('peerId') || 'unknown';
  meshClients.add(ws);
  log(`[mesh] +client peerId=${peerId} total=${meshClients.size}`);

  ws.on('message', (rawData) => {
    // Relay broadcast : on redistribue à tous les AUTRES clients connectés
    const payload = rawData.toString();
    for (const client of meshClients) {
      if (client !== ws && client.readyState === ws.OPEN) {
        try { client.send(payload); } catch (_) {}
      }
    }
  });

  ws.on('close', () => {
    meshClients.delete(ws);
    log(`[mesh] -client peerId=${peerId} total=${meshClients.size}`);
  });

  ws.on('error', (err) => {
    log(`[mesh] ws error peerId=${peerId}: ${err.message}`);
    meshClients.delete(ws);
  });
});

// Expose le nombre de clients connectés dans /status
const _originalStatusHandler = app._router.stack
  .find((l) => l.route && l.route.path === '/status');
// (pas besoin de patcher — on ajoute mesh_clients_count via /status ci-dessous)

app.get('/mesh/status', (_req, res) => {
  res.json({ connected_clients: meshClients.size, endpoint: `ws://localhost:${PORT}/mesh` });
});

// ════════════════════════════════════════════════════════════════════════
//  DÉMARRAGE
// ════════════════════════════════════════════════════════════════════════

httpServer.listen(PORT, () => {
  log(`✅ SERVEUR PRINCIPAL v2 démarré sur ${SELF_URL}`);
  log(`   WebSocket relay : ws://localhost:${PORT}/mesh`);
  log(`   next_backup = ${NEXT_BACKUP_CLEAR}`);
  log(`   Endpoints : /v1/events | /v1/reports | /v1/alerts/sync | /status | /healthz`);
});
