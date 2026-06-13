// test_servers/sandbox.js
//
// [4] Page Sandbox / Diagnostic de StreetPhare
// ─────────────────────────────────────────────
// Module Express séparé monté sur /sandbox dans l'admin dashboard.
//
// Permet aux développeurs de :
//   1. Injecter massivement de faux événements (en masse).
//   2. Simuler des déplacements d'utilisateurs fictifs.
//   3. Envoyer des flux de messages Hive P2P.
//   4. Déclencher des alertes de test de tous types.
//   5. Simuler un signal Panic collectif.
//   6. Visualiser les événements en temps réel via SSE.
//
// Accès : http://localhost:3000/sandbox (ou port 3001)

'use strict';

const express = require('express');
const { EventEmitter } = require('events');
const router = express.Router();

// ── Bus d'événements interne (SSE) ───────────────────────────────────────────
const sandboxBus = new EventEmitter();
sandboxBus.setMaxListeners(50);

// ── Compteurs / État de la sandbox ───────────────────────────────────────────
let injectedAlertsCount  = 0;
let injectedEventsCount  = 0;
let simulatedUsersCount  = 0;
let hiveMessagesCount    = 0;
let panicSignalsCount    = 0;
const simulatedUsers     = [];        // Utilisateurs fictifs en mouvement
const sandboxLog         = [];        // Historique des opérations (50 dernières)
const MAX_LOG = 50;

function pushLog(type, message, data = {}) {
  const entry = { ts: new Date().toISOString(), type, message, data };
  sandboxLog.unshift(entry);
  if (sandboxLog.length > MAX_LOG) sandboxLog.pop();
  sandboxBus.emit('log', entry);
}

// ── Types d'alertes disponibles ───────────────────────────────────────────────
const ALERT_TYPES = [
  'barrage', 'nasse', 'controle', 'accident',
  'rassemblement', 'zoneSafe', 'panicCollectif', 'autre',
];

// ── Générateurs de données fictives ──────────────────────────────────────────
function randomId(len = 8) {
  return Math.random().toString(36).substring(2, 2 + len);
}

function randomAround(center, radiusMeters = 500) {
  const r = radiusMeters / 111320;
  const u = Math.random();
  const v = Math.random();
  const w = r * Math.sqrt(u);
  const t = 2 * Math.PI * v;
  return {
    lat: center.lat + w * Math.cos(t),
    lng: center.lng + w * Math.sin(t) / Math.cos(center.lat * Math.PI / 180),
  };
}

function buildFakeAlert(type, center) {
  const pos = randomAround(center);
  return {
    id          : randomId(10),
    ephemeralUserId: `sandbox_${randomId(6)}`,
    signature   : `fake_sig_${randomId(16)}`,
    type        : type || ALERT_TYPES[Math.floor(Math.random() * ALERT_TYPES.length)],
    latitude    : pos.lat,
    longitude   : pos.lng,
    description : `[SANDBOX] Alerte de test générée automatiquement`,
    createdAt   : new Date().toISOString(),
    ttlHours    : 2,
    status      : 'validated',
    confirmations: Array.from({ length: 3 }, () => `peer_${randomId(6)}`),
    votes       : 3,
    uploadedTo  : [],
  };
}

function buildFakeEvent(index, center) {
  const pos = randomAround(center, 1000);
  return {
    id       : `sandbox_event_${randomId(8)}`,
    title    : `[SANDBOX] Événement Test #${index}`,
    startAt  : new Date(Date.now() - 3600000).toISOString(),
    endAt    : new Date(Date.now() + 7200000).toISOString(),
    destination: { lat: pos.lat, lng: pos.lng },
    waypoints: [
      { label: 'Point A', lat: pos.lat + 0.001, lng: pos.lng + 0.001, revealAt: new Date().toISOString() },
      { label: 'Point B (Final)', lat: pos.lat, lng: pos.lng, revealAt: new Date(Date.now() + 3600000).toISOString() },
    ],
    careCenters: [
      { label: 'Street-médics sandbox', lat: pos.lat - 0.002, lng: pos.lng - 0.001 },
    ],
    exitPoints: [
      { label: 'Sortie de secours', lat: pos.lat + 0.003, lng: pos.lng },
    ],
    safeZones: [
      { label: 'Zone Safe de Test', lat: pos.lat - 0.001, lng: pos.lng + 0.002 },
    ],
  };
}

function buildFakeHiveMessage(senderId, content) {
  return {
    kind     : 'hive_p2p_message',
    payload  : {
      id        : randomId(12),
      threadId  : `sandbox_thread_${randomId(6)}`,
      senderId  : senderId || `sandbox_user_${randomId(6)}`,
      content   : content || `[SANDBOX] Message Hive de test à ${new Date().toLocaleTimeString()}`,
      type      : 'TEXT',
      createdAt : new Date().toISOString(),
    },
    ts        : new Date().toISOString(),
    sender_id : senderId || `sandbox_${randomId(6)}`,
    local_only: false,
  };
}

// ── Stockage in-memory des données injectées ──────────────────────────────────
const injectedAlerts   = [];   // Alertes injectées
const injectedEvents   = [];   // Événements injectés
const injectedMessages = [];   // Messages Hive injectés

// ── Routes API de la Sandbox ──────────────────────────────────────────────────

/**
 * GET /sandbox
 * Page HTML principale de la sandbox.
 */
router.get('/', (req, res) => {
  res.send(sandboxHtml());
});

/**
 * GET /sandbox/stats
 * État courant de la sandbox (JSON).
 */
router.get('/stats', (req, res) => {
  res.json({
    injectedAlertsCount,
    injectedEventsCount,
    simulatedUsersCount,
    hiveMessagesCount,
    panicSignalsCount,
    simulatedUsers: simulatedUsers.map(u => ({
      id: u.id, lat: u.lat, lng: u.lng, speed: u.speed,
    })),
    recentLog: sandboxLog.slice(0, 10),
  });
});

/**
 * GET /sandbox/log
 * Journal complet des opérations sandbox (50 dernières).
 */
router.get('/log', (req, res) => {
  res.json(sandboxLog);
});

/**
 * POST /sandbox/inject-alerts
 * Injecte N fausses alertes autour d'un centre géographique.
 *
 * Body: { count: number, type?: string, centerLat?: number, centerLng?: number }
 */
router.post('/inject-alerts', express.json(), (req, res) => {
  const { count = 10, type = null, centerLat = 48.8566, centerLng = 2.3522 } = req.body;
  const n = Math.min(parseInt(count) || 10, 500);
  const center = { lat: parseFloat(centerLat), lng: parseFloat(centerLng) };
  const alerts = [];
  for (let i = 0; i < n; i++) {
    const alert = buildFakeAlert(type, center);
    alerts.push(alert);
    injectedAlerts.push(alert);
  }
  injectedAlertsCount += n;
  pushLog('alert_inject', `${n} alertes injectées (type=${type || 'aléatoire'})`, { count: n, type, center });
  res.json({ success: true, injected: n, alerts: alerts.slice(0, 5) });
});

/**
 * POST /sandbox/inject-events
  * Injecte N faux événements de rassemblement public.
 *
 * Body: { count: number, centerLat?: number, centerLng?: number }
 */
router.post('/inject-events', express.json(), (req, res) => {
  const { count = 3, centerLat = 48.8566, centerLng = 2.3522 } = req.body;
  const n = Math.min(parseInt(count) || 3, 50);
  const center = { lat: parseFloat(centerLat), lng: parseFloat(centerLng) };
  const events = [];
  for (let i = 0; i < n; i++) {
    const ev = buildFakeEvent(injectedEventsCount + i + 1, center);
    events.push(ev);
    injectedEvents.push(ev);
  }
  injectedEventsCount += n;
  pushLog('event_inject', `${n} événements injectés`, { count: n, center });
  res.json({ success: true, injected: n, events });
});

/**
 * POST /sandbox/simulate-users
 * Démarre N utilisateurs fictifs en déplacement (simulation GPS).
 *
 * Body: { count: number, centerLat?: number, centerLng?: number, speedKmh?: number }
 */
router.post('/simulate-users', express.json(), (req, res) => {
  const { count = 5, centerLat = 48.8566, centerLng = 2.3522, speedKmh = 5 } = req.body;
  const n = Math.min(parseInt(count) || 5, 100);
  const center = { lat: parseFloat(centerLat), lng: parseFloat(centerLng) };
  const speed = parseFloat(speedKmh) || 5;

  for (let i = 0; i < n; i++) {
    const pos = randomAround(center, 300);
    const user = {
      id       : `sim_user_${randomId(8)}`,
      lat      : pos.lat,
      lng      : pos.lng,
      heading  : Math.random() * 360,
      speed    : speed,
      startedAt: new Date().toISOString(),
    };
    simulatedUsers.push(user);
    // Mise à jour de position toutes les 3 secondes
    const interval = setInterval(() => {
      const d = (speed / 3600) / 111320; // mètres/s → degrés
      user.lat += d * Math.cos(user.heading * Math.PI / 180) * 3;
      user.lng += d * Math.sin(user.heading * Math.PI / 180) * 3;
      user.heading += (Math.random() - 0.5) * 20; // légère déviation
      sandboxBus.emit('user_move', { id: user.id, lat: user.lat, lng: user.lng });
    }, 3000);
    user._interval = interval;
  }
  simulatedUsersCount += n;
  pushLog('user_simulate', `${n} utilisateurs simulés à ${speed} km/h`, { count: n, speed, center });
  res.json({ success: true, started: n, totalActive: simulatedUsers.length });
});

/**
 * POST /sandbox/stop-simulated-users
 * Arrête tous les utilisateurs simulés.
 */
router.post('/stop-simulated-users', express.json(), (req, res) => {
  const stopped = simulatedUsers.length;
  for (const u of simulatedUsers) {
    if (u._interval) clearInterval(u._interval);
  }
  simulatedUsers.length = 0;
  pushLog('user_stop', `${stopped} utilisateurs simulés arrêtés`);
  res.json({ success: true, stopped });
});

/**
 * POST /sandbox/send-hive-messages
 * Envoie N faux messages sur le flux Hive P2P.
 *
 * Body: { count: number, senderId?: string, content?: string }
 */
router.post('/send-hive-messages', express.json(), (req, res) => {
  const { count = 10, senderId = null, content = null } = req.body;
  const n = Math.min(parseInt(count) || 10, 200);
  const messages = [];
  for (let i = 0; i < n; i++) {
    const msg = buildFakeHiveMessage(senderId, content);
    messages.push(msg);
    injectedMessages.push(msg);
    sandboxBus.emit('hive_message', msg);
  }
  hiveMessagesCount += n;
  pushLog('hive_inject', `${n} messages Hive injectés`, { count: n });
  res.json({ success: true, sent: n, messages: messages.slice(0, 3) });
});

/**
 * POST /sandbox/trigger-alert
 * Déclenche UNE alerte précise.
 *
 * Body: { type: string, lat: number, lng: number, description?: string }
 */
router.post('/trigger-alert', express.json(), (req, res) => {
  const { type = 'barrage', lat = 48.8566, lng = 2.3522, description = '[SANDBOX] Test alert' } = req.body;
  if (!ALERT_TYPES.includes(type)) {
    return res.status(400).json({ error: `Type invalide. Valeurs: ${ALERT_TYPES.join(', ')}` });
  }
  const alert = buildFakeAlert(type, { lat: parseFloat(lat), lng: parseFloat(lng) });
  alert.description = description;
  injectedAlerts.push(alert);
  injectedAlertsCount++;
  sandboxBus.emit('alert', alert);
  pushLog('alert_trigger', `Alerte ${type} déclenchée`, { type, lat, lng });
  res.json({ success: true, alert });
});

/**
 * POST /sandbox/trigger-panic
 * Simule un signal Panic collectif depuis N pairs.
 *
 * Body: { peerCount?: number, centerLat?: number, centerLng?: number }
 */
router.post('/trigger-panic', express.json(), (req, res) => {
  const { peerCount = 5, centerLat = 48.8566, centerLng = 2.3522 } = req.body;
  const n = parseInt(peerCount) || 5;
  const signals = [];
  for (let i = 0; i < n; i++) {
    const pos = randomAround({ lat: parseFloat(centerLat), lng: parseFloat(centerLng) }, 100);
    signals.push({
      kind  : 'panic',
      peerId: `panic_peer_${randomId(6)}`,
      lat   : pos.lat,
      lng   : pos.lng,
      ts    : new Date().toISOString(),
    });
  }
  panicSignalsCount += n;
  sandboxBus.emit('panic', { peerCount: n, center: { lat: centerLat, lng: centerLng }, signals });
  pushLog('panic_simulate', `Panic collectif simulé (${n} pairs)`, { peerCount: n });
  res.json({ success: true, peerCount: n, signals });
});

/**
 * POST /sandbox/reset
 * Réinitialise toute la sandbox.
 */
router.post('/reset', express.json(), (req, res) => {
  // Stop simulated users
  for (const u of simulatedUsers) {
    if (u._interval) clearInterval(u._interval);
  }
  simulatedUsers.length   = 0;
  injectedAlerts.length   = 0;
  injectedEvents.length   = 0;
  injectedMessages.length = 0;
  sandboxLog.length       = 0;
  injectedAlertsCount     = 0;
  injectedEventsCount     = 0;
  simulatedUsersCount     = 0;
  hiveMessagesCount       = 0;
  panicSignalsCount       = 0;
  pushLog('reset', 'Sandbox réinitialisée');
  res.json({ success: true, message: 'Sandbox réinitialisée.' });
});

/**
 * GET /sandbox/data/alerts
 * Liste toutes les alertes injectées.
 */
router.get('/data/alerts', (req, res) => {
  res.json(injectedAlerts.slice(-100));
});

/**
 * GET /sandbox/data/events
 * Liste tous les événements injectés.
 */
router.get('/data/events', (req, res) => {
  res.json(injectedEvents);
});

/**
 * GET /sandbox/events/stream
 * SSE — flux temps réel des événements sandbox.
 */
router.get('/events/stream', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const onLog = (entry) => {
    res.write(`event: log\ndata: ${JSON.stringify(entry)}\n\n`);
  };
  const onAlert = (alert) => {
    res.write(`event: alert\ndata: ${JSON.stringify(alert)}\n\n`);
  };
  const onPanic = (data) => {
    res.write(`event: panic\ndata: ${JSON.stringify(data)}\n\n`);
  };
  const onHive = (msg) => {
    res.write(`event: hive_message\ndata: ${JSON.stringify(msg)}\n\n`);
  };
  const onUserMove = (data) => {
    res.write(`event: user_move\ndata: ${JSON.stringify(data)}\n\n`);
  };

  sandboxBus.on('log', onLog);
  sandboxBus.on('alert', onAlert);
  sandboxBus.on('panic', onPanic);
  sandboxBus.on('hive_message', onHive);
  sandboxBus.on('user_move', onUserMove);

  // Heartbeat toutes les 30 s
  const hb = setInterval(() => {
    res.write(`: heartbeat\n\n`);
  }, 30000);

  req.on('close', () => {
    sandboxBus.off('log', onLog);
    sandboxBus.off('alert', onAlert);
    sandboxBus.off('panic', onPanic);
    sandboxBus.off('hive_message', onHive);
    sandboxBus.off('user_move', onUserMove);
    clearInterval(hb);
  });
});

// ── Page HTML de la Sandbox ───────────────────────────────────────────────────
function sandboxHtml() {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>StreetPhare — Sandbox & Diagnostic</title>
  <style>
    :root {
      --bg: #0a0e1a; --surface: #131929; --border: #1e2d45;
      --primary: #00e676; --accent: #40c4ff; --danger: #ff1744;
      --warn: #ffab00; --text: #e8eaf6; --muted: #607d8b;
      --radius: 10px;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; }
    header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 16px 24px;
             display: flex; align-items: center; gap: 12px; }
    header .logo { font-size: 22px; font-weight: 700; color: var(--primary); }
    header .badge { background: var(--danger); color: #fff; font-size: 11px; padding: 3px 8px;
                    border-radius: 12px; font-weight: 600; letter-spacing: .5px; }
    .main { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; padding: 24px; max-width: 1400px; margin: 0 auto; }
    @media(max-width:900px) { .main { grid-template-columns: 1fr; } }
    .panel { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 20px; }
    .panel h2 { font-size: 14px; font-weight: 600; color: var(--accent); text-transform: uppercase;
                letter-spacing: .8px; margin-bottom: 14px; display: flex; align-items: center; gap: 8px; }
    .form-row { display: flex; gap: 8px; margin-bottom: 8px; flex-wrap: wrap; }
    .form-row input, .form-row select {
      flex: 1; min-width: 100px; background: #0d1525; border: 1px solid var(--border);
      color: var(--text); border-radius: 6px; padding: 8px 10px; font-size: 13px;
    }
    .form-row input:focus, .form-row select:focus { outline: none; border-color: var(--primary); }
    button { cursor: pointer; border: none; border-radius: 6px; font-size: 13px;
             font-weight: 600; padding: 9px 16px; transition: opacity .2s; }
    button:hover { opacity: .85; }
    .btn-primary  { background: var(--primary); color: #000; }
    .btn-danger   { background: var(--danger); color: #fff; }
    .btn-warn     { background: var(--warn); color: #000; }
    .btn-accent   { background: var(--accent); color: #000; }
    .btn-muted    { background: var(--border); color: var(--text); }
    .stat-grid { display: grid; grid-template-columns: repeat(3,1fr); gap: 10px; margin-bottom: 16px; }
    .stat { background: #0d1525; border-radius: 8px; padding: 12px; text-align: center; }
    .stat .val { font-size: 28px; font-weight: 700; color: var(--primary); }
    .stat .lbl { font-size: 10px; color: var(--muted); text-transform: uppercase; margin-top: 4px; }
    #log-panel { grid-column: 1 / -1; }
    #log-list { max-height: 280px; overflow-y: auto; font-size: 12px; font-family: monospace; }
    .log-entry { padding: 5px 8px; border-bottom: 1px solid var(--border); display: flex; gap: 10px; }
    .log-entry .ts { color: var(--muted); flex-shrink: 0; }
    .log-entry .type { font-weight: 700; flex-shrink: 0; min-width: 130px; }
    .type-alert_inject { color: var(--warn); }
    .type-event_inject { color: var(--accent); }
    .type-user_simulate { color: #b39ddb; }
    .type-hive_inject { color: #80cbc4; }
    .type-panic_simulate { color: var(--danger); }
    .type-reset { color: var(--muted); }
    .type-alert_trigger { color: var(--danger); }
    .live-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--danger);
                animation: blink 1s infinite; display: inline-block; }
    @keyframes blink { 0%,100%{opacity:1} 50%{opacity:.2} }
    .result { background: #0d1525; border-radius: 6px; padding: 10px; font-size: 11px;
              font-family: monospace; margin-top: 8px; color: var(--primary);
              max-height: 120px; overflow-y: auto; white-space: pre-wrap; display: none; }
    select option { background: #131929; }
  </style>
</head>
<body>
<header>
  <span class="logo">⚡ StreetPhare</span>
  <span class="badge">SANDBOX DEV</span>
  <span style="margin-left:auto;font-size:12px;color:var(--muted)">Outil de test isolé — NE PAS utiliser en production</span>
</header>

<div class="main">

  <!-- Stats globales -->
  <div class="panel" style="grid-column:1/-1">
    <h2>📊 État de la Sandbox</h2>
    <div class="stat-grid">
      <div class="stat"><div class="val" id="s-alerts">0</div><div class="lbl">Alertes injectées</div></div>
      <div class="stat"><div class="val" id="s-events">0</div><div class="lbl">Événements injectés</div></div>
      <div class="stat"><div class="val" id="s-users">0</div><div class="lbl">Utilisateurs simulés</div></div>
      <div class="stat"><div class="val" id="s-hive">0</div><div class="lbl">Messages Hive</div></div>
      <div class="stat"><div class="val" id="s-panic">0</div><div class="lbl">Signaux Panic</div></div>
      <div class="stat" style="cursor:pointer" onclick="resetSandbox()">
        <div class="val" style="font-size:22px">🗑</div>
        <div class="lbl">Réinitialiser</div>
      </div>
    </div>
    <button class="btn-muted" onclick="refreshStats()">↺ Rafraîchir les stats</button>
  </div>

  <!-- Injection d'alertes -->
  <div class="panel">
    <h2>🚨 Injection d'alertes massives</h2>
    <div class="form-row">
      <input type="number" id="a-count" value="20" min="1" max="500" placeholder="Nombre">
      <select id="a-type">
        <option value="">Type aléatoire</option>
        <option value="barrage">Barrage</option>
        <option value="nasse">Nasse</option>
        <option value="controle">Contrôle</option>
        <option value="accident">Accident/Danger</option>
        <option value="rassemblement">Rassemblement à risque</option>
        <option value="zoneSafe">Zone Safe</option>
        <option value="panicCollectif">Panic collectif</option>
        <option value="autre">Autre</option>
      </select>
    </div>
    <div class="form-row">
      <input type="number" id="a-lat" value="48.8566" step="0.001" placeholder="Latitude centre">
      <input type="number" id="a-lng" value="2.3522" step="0.001" placeholder="Longitude centre">
    </div>
    <button class="btn-warn" onclick="injectAlerts()">⚡ Injecter les alertes</button>
    <div class="result" id="r-alerts"></div>
  </div>

  <!-- Injection d'événements -->
  <div class="panel">
    <h2>📅 Injection d'événements de rassemblement</h2>
    <div class="form-row">
      <input type="number" id="e-count" value="3" min="1" max="50" placeholder="Nombre">
      <input type="number" id="e-lat" value="48.8566" step="0.001" placeholder="Latitude">
      <input type="number" id="e-lng" value="2.3522" step="0.001" placeholder="Longitude">
    </div>
    <button class="btn-accent" onclick="injectEvents()">📅 Injecter les événements</button>
    <div class="result" id="r-events"></div>
  </div>

  <!-- Simulation d'utilisateurs -->
  <div class="panel">
    <h2>👥 Simulation de déplacements GPS</h2>
    <div class="form-row">
      <input type="number" id="u-count" value="10" min="1" max="100" placeholder="Nb utilisateurs">
      <input type="number" id="u-speed" value="5" min="1" max="30" placeholder="Vitesse km/h">
    </div>
    <div class="form-row">
      <input type="number" id="u-lat" value="48.8566" step="0.001" placeholder="Latitude centre">
      <input type="number" id="u-lng" value="2.3522" step="0.001" placeholder="Longitude centre">
    </div>
    <div class="form-row">
      <button class="btn-primary" onclick="startUsers()">▶ Démarrer la simulation</button>
      <button class="btn-muted" onclick="stopUsers()">⏹ Arrêter</button>
    </div>
    <div class="result" id="r-users"></div>
  </div>

  <!-- Messages Hive -->
  <div class="panel">
    <h2>💬 Injection de messages Hive P2P</h2>
    <div class="form-row">
      <input type="number" id="h-count" value="15" min="1" max="200" placeholder="Nombre de messages">
      <input type="text" id="h-sender" placeholder="ID émetteur (opt.)">
    </div>
    <div class="form-row">
      <input type="text" id="h-content" placeholder="Contenu du message (opt.)">
    </div>
    <button class="btn-primary" style="background:#80cbc4;color:#000" onclick="sendHiveMessages()">
      💬 Envoyer les messages Hive
    </button>
    <div class="result" id="r-hive"></div>
  </div>

  <!-- Déclenchement d'alerte précise -->
  <div class="panel">
    <h2>🎯 Déclencher une alerte précise</h2>
    <div class="form-row">
      <select id="t-type">
        <option value="barrage">Barrage</option>
        <option value="nasse">Nasse</option>
        <option value="controle">Contrôle</option>
        <option value="accident">Accident/Danger</option>
        <option value="rassemblement">Rassemblement à risque</option>
        <option value="zoneSafe">Zone Safe</option>
        <option value="panicCollectif">Panic collectif</option>
        <option value="autre">Autre</option>
      </select>
    </div>
    <div class="form-row">
      <input type="number" id="t-lat" value="48.8566" step="0.0001" placeholder="Latitude exacte">
      <input type="number" id="t-lng" value="2.3522" step="0.0001" placeholder="Longitude exacte">
    </div>
    <div class="form-row">
      <input type="text" id="t-desc" placeholder="Description (opt.)">
    </div>
    <button class="btn-danger" onclick="triggerAlert()">🚨 Déclencher l'alerte</button>
    <div class="result" id="r-trigger"></div>
  </div>

  <!-- Simulation Panic -->
  <div class="panel">
    <h2>🆘 Simulation Panic collectif</h2>
    <div class="form-row">
      <input type="number" id="p-count" value="6" min="2" max="50" placeholder="Nombre de pairs">
      <input type="number" id="p-lat" value="48.8566" step="0.001" placeholder="Latitude">
      <input type="number" id="p-lng" value="2.3522" step="0.001" placeholder="Longitude">
    </div>
    <button class="btn-danger" onclick="triggerPanic()">⚠ Simuler le Panic collectif</button>
    <div class="result" id="r-panic"></div>
  </div>

  <!-- Journal en temps réel -->
  <div class="panel" id="log-panel">
    <h2><span class="live-dot"></span>&nbsp; Journal temps réel (SSE)</h2>
    <div id="log-list"></div>
  </div>

</div>

<script>
const BASE = '/sandbox';

async function api(path, method = 'GET', body = null) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(BASE + path, opts);
  return r.json();
}

function showResult(id, data) {
  const el = document.getElementById(id);
  el.style.display = 'block';
  el.textContent = JSON.stringify(data, null, 2);
}

async function refreshStats() {
  const s = await api('/stats');
  document.getElementById('s-alerts').textContent = s.injectedAlertsCount;
  document.getElementById('s-events').textContent = s.injectedEventsCount;
  document.getElementById('s-users').textContent  = s.simulatedUsersCount;
  document.getElementById('s-hive').textContent   = s.hiveMessagesCount;
  document.getElementById('s-panic').textContent  = s.panicSignalsCount;
}

async function injectAlerts() {
  const r = await api('/inject-alerts', 'POST', {
    count: +document.getElementById('a-count').value,
    type: document.getElementById('a-type').value || null,
    centerLat: +document.getElementById('a-lat').value,
    centerLng: +document.getElementById('a-lng').value,
  });
  showResult('r-alerts', r); refreshStats();
}

async function injectEvents() {
  const r = await api('/inject-events', 'POST', {
    count: +document.getElementById('e-count').value,
    centerLat: +document.getElementById('e-lat').value,
    centerLng: +document.getElementById('e-lng').value,
  });
  showResult('r-events', r); refreshStats();
}

async function startUsers() {
  const r = await api('/simulate-users', 'POST', {
    count: +document.getElementById('u-count').value,
    speedKmh: +document.getElementById('u-speed').value,
    centerLat: +document.getElementById('u-lat').value,
    centerLng: +document.getElementById('u-lng').value,
  });
  showResult('r-users', r); refreshStats();
}

async function stopUsers() {
  const r = await api('/stop-simulated-users', 'POST');
  showResult('r-users', r); refreshStats();
}

async function sendHiveMessages() {
  const r = await api('/send-hive-messages', 'POST', {
    count: +document.getElementById('h-count').value,
    senderId: document.getElementById('h-sender').value || null,
    content: document.getElementById('h-content').value || null,
  });
  showResult('r-hive', r); refreshStats();
}

async function triggerAlert() {
  const r = await api('/trigger-alert', 'POST', {
    type: document.getElementById('t-type').value,
    lat: +document.getElementById('t-lat').value,
    lng: +document.getElementById('t-lng').value,
    description: document.getElementById('t-desc').value || undefined,
  });
  showResult('r-trigger', r); refreshStats();
}

async function triggerPanic() {
  const r = await api('/trigger-panic', 'POST', {
    peerCount: +document.getElementById('p-count').value,
    centerLat: +document.getElementById('p-lat').value,
    centerLng: +document.getElementById('p-lng').value,
  });
  showResult('r-panic', r); refreshStats();
}

async function resetSandbox() {
  if (!confirm('Réinitialiser toute la sandbox ?')) return;
  const r = await api('/reset', 'POST');
  document.getElementById('log-list').innerHTML = '';
  refreshStats();
  alert(r.message);
}

// ── SSE temps réel ────────────────────────────────────────────────────────
const logList = document.getElementById('log-list');
const es = new EventSource(BASE + '/events/stream');

es.addEventListener('log', (e) => {
  const d = JSON.parse(e.data);
  const row = document.createElement('div');
  row.className = 'log-entry';
  row.innerHTML =
    '<span class="ts">' + d.ts.slice(11,19) + '</span>' +
    '<span class="type type-' + d.type + '">' + d.type + '</span>' +
    '<span>' + d.message + '</span>';
  logList.prepend(row);
  if (logList.children.length > 50) logList.lastChild.remove();
  refreshStats();
});

['alert','panic','hive_message'].forEach(ev => {
  es.addEventListener(ev, () => refreshStats());
});

// Mise à jour initiale
refreshStats();
setInterval(refreshStats, 15000);
</script>
</body>
</html>`;
}

module.exports = { router, sandboxBus };
