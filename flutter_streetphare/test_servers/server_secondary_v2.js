// test_servers/server_secondary_v2.js
//
// StreetPhare — SERVEUR BACKUP v2 (Port 3001)
// ============================================
// Version enrichie du serveur secondaire. Intègre :
//
//   ✅  Même surface d'API que le serveur principal (failover transparent)
//   ✅  Module Événements & Itinéraires Safe Route (events_manager)
//   ✅  Module Signalements avec TTL, votes, Panic Collectif (reports_store)
//   ✅  HeartbeatMonitor : surveille le principal (port 3000) en continu
//   ✅  Failover automatique : si 3 pings consécutifs échouent, ce serveur
//       prend le rôle de principal et met à jour SERVER_STATUS.md
//   ✅  Recovery automatique : retour en mode standby si le principal revient
//   ✅  Rétrocompatibilité avec les endpoints v1 (alertes, backup-route)
//
// ── TOPOLOGIE ─────────────────────────────────────────────────────────────
//
//   [Client Flutter]
//       │
//       ├─► [Principal :3000]  ◄── HeartbeatMonitor (depuis :3001)
//       │       │
//       │       └─ si HORS LIGNE ──►  [Backup :3001] devient ACTIF
//       │
//       └─► [Backup :3001]  (en veille → promu si failover)
//
// ── ENDPOINTS (identiques au principal) ──────────────────────────────────
//
//  Heartbeat & Statut
//    GET  /ping                    heartbeat simple
//    GET  /healthz                 heartbeat FailoverManager
//    GET  /status                  topologie + état du monitor
//
//  Événements
//    GET  /v1/events
//    GET  /v1/events/:id
//    POST /v1/events/:id/route
//
//  Signalements
//    POST /v1/reports
//    GET  /v1/reports
//    GET  /v1/reports/stats
//
//  Compatibilité v1
//    POST /alerts
//    POST /v1/alerts/sync
//    GET  /backup-route
//
//  Debug
//    GET  /_debug/store
//    GET  /_debug/reports
//    POST /_debug/promote          promouvoir manuellement ce backup
//    POST /_debug/demote           démissionner manuellement
//
// ─────────────────────────────────────────────────────────────────────────
'use strict';

const express = require('express');

// ── Modules StreetPhare ──────────────────────────────────────────────────
const eventsManager  = require('./modules/events_manager');
const reportsStore   = require('./modules/reports_store');
const {
  HeartbeatMonitor,
  buildStatusResponse,
  buildTopologyMarkdown,
} = require('./modules/heartbeat_monitor');
const { encryptAddress } = require('./server_crypto');

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
const PORT                = parseInt(process.env.PORT  || '3001', 10);
const ROLE                = (process.env.ROLE           || 'secondary').trim();
const MASTER_PASSPHRASE   = (process.env.STREETPHARE_MASTER_KEY
                            || 'streetphare-dev-key-CHANGE_ME_IN_PROD').trim();
const NEXT_BACKUP_CLEAR   = (process.env.NEXT_BACKUP_URL || 'http://localhost:3002').trim();
const PRIMARY_URL         = (process.env.PRIMARY_URL    || 'http://localhost:3000').trim();
const SELF_URL            = `http://localhost:${PORT}`;

// Paramètres heartbeat (surchargeables via env)
const HB_INTERVAL_MS      = parseInt(process.env.HB_INTERVAL_MS  || '5000',  10);
const HB_TIMEOUT_MS       = parseInt(process.env.HB_TIMEOUT_MS   || '3000',  10);
const HB_FAIL_THRESHOLD   = parseInt(process.env.HB_FAIL_THRESHOLD || '3',   10);
const HB_RECOVERY_THRESH  = parseInt(process.env.HB_RECOVERY_THRESHOLD || '3', 10);

// ── Initialisation du dashboard ──────────────────────────────────────────
dash.init({ role: ROLE, port: PORT, name: 'Backup 1', url: SELF_URL });

// ── Application Express ──────────────────────────────────────────────────
const app = express();
app.use(express.json({ limit: '2mb' }));

// ── Logger horodaté ──────────────────────────────────────────────────────
function log(...args) {
  console.log(`[${new Date().toISOString()}][secondary:${PORT}]`, ...args);
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
//  HEARTBEAT MONITOR — Surveillance du serveur principal
// ════════════════════════════════════════════════════════════════════════

let isPromotedToPrimary = false;

const monitor = new HeartbeatMonitor({
  targetUrl:         PRIMARY_URL,
  monitorName:       `BackupMonitor(:${PORT}→:3000)`,
  intervalMs:        HB_INTERVAL_MS,
  timeoutMs:         HB_TIMEOUT_MS,
  failoverThreshold: HB_FAIL_THRESHOLD,
  recoveryThreshold: HB_RECOVERY_THRESH,
  selfRole:          ROLE,
  logger:            dash,

  /**
   * Appelé quand le principal ne répond plus (après N échecs consécutifs).
   * Ce serveur BACKUP prend automatiquement le rôle de principal.
   */
  onFailover: (info) => {
    isPromotedToPrimary = true;
    log(`🔴 FAILOVER — principal hors ligne. Ce serveur devient PRINCIPAL.`);
    log(`   Raison : ${info.last_error} | ${info.consecutive_fails} échecs consécutifs`);

    // Mettre à jour le dashboard avec le nouveau rôle
    dash.setCurrentRole('Promu Principal (failover)');
    dash.broadcastEvent(
      'FAILOVER', '🚨', 'Failover automatique déclenché',
      `Principal ${PRIMARY_URL} hors ligne — Backup promu Principal`,
    );
  },

  /**
   * Appelé quand le principal répond à nouveau (après N succès consécutifs).
   * Ce serveur retourne en mode STANDBY.
   */
  onRecovery: (info) => {
    isPromotedToPrimary = false;
    log(`🟢 RECOVERY — principal de retour. Ce serveur repasse en mode BACKUP.`);
    dash.setCurrentRole('En veille');
    dash.broadcastEvent(
      'RECOVERY', '✅', 'Rétablissement du principal',
      `Principal ${PRIMARY_URL} de retour après ${info.consecutive_oks} pings réussis`,
    );
  },

  /** Appelé à chaque ping pour logging léger. */
  onPing: ({ ok, elapsed }) => {
    if (!ok) {
      log(`💔 Ping principal échoué (${elapsed}ms) — échecs: ${monitor._consecutiveFails}/${HB_FAIL_THRESHOLD}`);
    }
  },
});

// Démarrer la surveillance après que le serveur soit prêt
// (le démarrage réel se fait dans app.listen)

// ════════════════════════════════════════════════════════════════════════
//  SECTION 1 — HEARTBEAT & STATUT
// ════════════════════════════════════════════════════════════════════════

// GET /ping — heartbeat simple
app.get('/ping', (_req, res) => {
  dash.pingReceived('GET /ping');
  const role = isPromotedToPrimary ? 'primary_promoted' : ROLE;
  res.json({ status: 'ok', role, ts: Date.now() });
});

// GET /healthz — heartbeat FailoverManager
app.get('/healthz', (_req, res) => {
  dash.pingReceived('GET /healthz');
  const role = isPromotedToPrimary ? 'primary_promoted' : ROLE;
  res.json({ status: 'ok', role, ts: Date.now() });
});

// GET /status — topologie complète (primaire surveillé + état backup)
app.get('/status', (_req, res) => {
  const monitorStatus = monitor.getStatus();

  const response = buildStatusResponse({
    selfRole: isPromotedToPrimary ? 'primary_promoted' : ROLE,
    selfUrl:  SELF_URL,
    monitor,
    port:     PORT,
  });

  res.json({
    ...response,
    is_promoted:    isPromotedToPrimary,
    next_backup:    NEXT_BACKUP_CLEAR,
    primary_url:    PRIMARY_URL,
    reports_active: reportsStore.getActiveReports().total_active,
    panic_pending:  reportsStore.getPendingPanicCount(),
    // Topologie résumée pour le client Flutter
    topology_summary: {
      primary: {
        url:    PRIMARY_URL,
        status: monitorStatus.status,         // 'online'|'offline'|'degraded'
        last_seen: monitorStatus.last_success_at,
      },
      backup: {
        url:         SELF_URL,
        status:      'online',
        is_promoted: isPromotedToPrimary,
      },
    },
  });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 2 — ÉVÉNEMENTS (Fleurus 6220)
// ════════════════════════════════════════════════════════════════════════

app.get('/v1/events', (_req, res) => {
  const events = eventsManager.getAllEvents();
  log(`GET /v1/events — ${events.length} événements`);
  res.json({ events, generated_at: new Date().toISOString() });
});

app.get('/v1/events/:id', (req, res) => {
  const event = eventsManager.getEventById(req.params.id);
  if (!event) return res.status(404).json({ error: 'Événement introuvable', id: req.params.id });
  log(`GET /v1/events/${req.params.id}`);
  res.json({ event, generated_at: new Date().toISOString() });
});

app.post('/v1/events/:id/route', async (req, res) => {
  const eventId      = req.params.id;
  const fromOverride = req.body && req.body.from ? req.body.from : null;
  const dangerZones  = reportsStore.getValidatedDangerZones();

  log(`POST /v1/events/${eventId}/route — ${dangerZones.length} zone(s) danger`);

  try {
    const result = await eventsManager.computeSafeRoutes(eventId, dangerZones, fromOverride);
    if (result.error) return res.status(404).json({ error: result.error, event_id: eventId });

    dash.broadcastEvent(
      'ROUTE', '🗺️', 'Calcul Safe Route (backup)',
      `Événement ${eventId} — ${result.routes.length} itinéraire(s)`,
    );
    res.json({ ...result, danger_zones_count: dangerZones.length, generated_at: new Date().toISOString() });
  } catch (err) {
    res.status(500).json({ error: 'Erreur calcul itinéraire', details: err.message });
  }
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 3 — SIGNALEMENTS (Dangers & Zones)
// ════════════════════════════════════════════════════════════════════════

app.post('/v1/reports', (req, res) => {
  const payload = req.body || {};
  const result  = reportsStore.addReport(payload);

  if (!result.ok) return res.status(400).json(result);

  log(`POST /v1/reports — type=${payload.type} id=${payload.id} votes=${result.votes}`);
  if (result.panic_result && result.panic_result.triggered) {
    log(`🚨 PANIC COLLECTIF DÉCLENCHÉ — id=${result.panic_result.danger_id}`);
  }
  res.json(result);
});

app.get('/v1/reports', (_req, res) => {
  const data = reportsStore.getActiveReports();
  log(`GET /v1/reports — ${data.total_active} signalement(s) actif(s)`);
  res.json(data);
});

app.get('/v1/reports/stats', (_req, res) => {
  res.json({
    panic_queue_size:     reportsStore.getPendingPanicCount(),
    panic_threshold:      reportsStore.PANIC_THRESHOLD_COUNT,
    panic_window_s:       reportsStore.PANIC_WINDOW_S,
    panic_cluster_radius_m: reportsStore.PANIC_CLUSTER_RADIUS_M,
    votes_required:       reportsStore.VOTES_REQUIRED_FOR_DISTRIBUTION,
    ttl_by_type:          reportsStore.TTL_BY_TYPE,
    total_active_reports: reportsStore.getActiveReports().total_active,
    generated_at:         new Date().toISOString(),
  });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 4 — RÉTROCOMPATIBILITÉ v1 (FailoverManager Flutter)
// ════════════════════════════════════════════════════════════════════════

const alertStore = new Map();

function ensureAlert(id, payload) {
  if (!alertStore.has(id)) {
    alertStore.set(id, { payload: payload || null, confirmations: new Set(), validatedAt: null });
  }
  return alertStore.get(id);
}

function handleAlertPayload(a) {
  if (!a || typeof a.id !== 'string') return { id: a && a.id, ok: false, reason: 'id manquant' };
  const entry       = ensureAlert(a.id, a);
  const confs       = Array.isArray(a.confirmations) ? a.confirmations : [];
  for (const c of confs) entry.confirmations.add(c);
  const validated   = entry.confirmations.size >= 3 && !entry.validatedAt;
  const wasValidated = !!entry.validatedAt;
  if (validated) entry.validatedAt = new Date().toISOString();
  if (!wasValidated) {
    dash.alertReceived(a.id, entry.payload, entry.confirmations.size, 3);
    if (entry.confirmations.size >= 3) dash.consensusReached(a.id, entry.payload);
  }
  return { id: a.id, ok: true, consensus: validated, confirmations: entry.confirmations.size };
}

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
  if (Array.isArray(body.alerts)) return res.json({ ok: true, results: body.alerts.map(handleAlertPayload) });
  return res.status(400).json({ error: 'Format invalide' });
});

app.post('/v1/alerts/sync', (req, res) => {
  const body    = req.body || {};
  const results = Array.isArray(body.alerts) ? body.alerts.map(handleAlertPayload) : [];
  const cipher  = NEXT_BACKUP_CLEAR ? encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE) : '';
  log(`sync reçu : ${results.length} alerte(s) ; next_backup=${NEXT_BACKUP_CLEAR || '(aucun)'}`);
  dash.broadcastEvent('SYNC', '🔄', 'Sync alertes (backup)', `${results.length} alerte(s)`);
  res.json({ ok: true, server: SELF_URL, next_backup: cipher, results });
});

app.get('/backup-route', (_req, res) => {
  if (!NEXT_BACKUP_CLEAR) {
    return res.json({ next: null, encrypted_next: '', algorithm: 'AES-256-CBC+HMAC-SHA256', note: 'Pas de serveur tertiaire' });
  }
  const cipher = encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE);
  log(`backup-route → ${NEXT_BACKUP_CLEAR} (chiffré)`);
  dash.backupRequested(cipher);
  res.json({ next: NEXT_BACKUP_CLEAR, encrypted_next: cipher, algorithm: 'AES-256-CBC+HMAC-SHA256' });
});

// ════════════════════════════════════════════════════════════════════════
//  SECTION 5 — DEBUG (admin)
// ════════════════════════════════════════════════════════════════════════

app.get('/_debug/store', (_req, res) => {
  const out = [];
  for (const [id, e] of alertStore.entries()) {
    out.push({ id, confirmations: e.confirmations.size, validatedAt: e.validatedAt });
  }
  res.json({ count: alertStore.size, alerts: out });
});

app.get('/_debug/reports', (_req, res) => {
  res.json(reportsStore.getDebugSnapshot());
});

// POST /_debug/promote — simuler la promotion (test visuel)
app.post('/_debug/promote', (req, res) => {
  const reason = (req.body && req.body.reason) || 'Promotion manuelle';
  isPromotedToPrimary = true;
  log(`PROMOTION manuelle : ${reason}`);
  dash.promoted('Promu Principal (manuel)');
  res.json({ ok: true, promoted: true, reason });
});

// POST /_debug/demote — démissionner (test failover)
app.post('/_debug/demote', (req, res) => {
  const reason = (req.body && req.body.reason) || 'Démission manuelle';
  log(`DÉMISSION demandée : ${reason}`);
  dash.demoted(reason);
  monitor.stop();
  setTimeout(() => process.exit(0), 200);
  res.json({ ok: true, demoted: true, reason });
});

// ════════════════════════════════════════════════════════════════════════
//  DÉMARRAGE
// ════════════════════════════════════════════════════════════════════════

app.listen(PORT, () => {
  log(`✅ SERVEUR BACKUP v2 démarré sur ${SELF_URL}`);
  log(`   Surveillance du principal : ${PRIMARY_URL}`);
  log(`   Failover threshold : ${HB_FAIL_THRESHOLD} échecs | Intervalle : ${HB_INTERVAL_MS}ms`);
  log(`   Endpoints : /v1/events | /v1/reports | /v1/alerts/sync | /status | /healthz`);

  // Démarrer le monitoring APRÈS que le serveur soit bien initialisé
  monitor.start();
  log(`   HeartbeatMonitor démarré → ${PRIMARY_URL}/healthz`);
});

// ── Arrêt propre ─────────────────────────────────────────────────────────
function gracefulShutdown(signal) {
  log(`Signal ${signal} reçu — arrêt du HeartbeatMonitor...`);
  monitor.stop();
  process.exit(0);
}
process.on('SIGINT',  () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
