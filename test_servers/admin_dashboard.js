// test_servers/admin_dashboard.js
//
// [6] Serveur web d'administration StreetPhare — v3.0
//
// Nouvelles fonctionnalités v3.0 :
//   - Générateur de QR Code pour événements
//   - Menu de gestion des événements (CRUD trajets Fleurus)
//   - Console de communication (Broadcast + Alertes réseau Hive)
//   - Contrôle serveur local (Start / Stop / Restart)
//   - Système de Kick et Bannissement des utilisateurs malveillants
//   - Endpoint de réception des rapports de bugs (/api/bug-report)
//   - Verrouillage automatique client après 3 kicks en 30 min

'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync, spawn, exec } = require('child_process');
const crypto = require('crypto');

// [4] Sandbox / diagnostic — monté sur /sandbox via Express sub-app
let _sandboxApp = null;
function getSandboxApp() {
  if (_sandboxApp) return _sandboxApp;
  try {
    const express = require('express');
    const { router } = require('./sandbox');
    _sandboxApp = express();
    _sandboxApp.use('/sandbox', router);
  } catch (e) {
    console.warn('[Admin] Sandbox non disponible (express manquant?):', e.message);
  }
  return _sandboxApp;
}

// ── Port et configuration ────────────────────────────────────────────────────
const PORT = process.env.ADMIN_PORT || 4000;
const PRIMARY_SERVER_PORT = process.env.PRIMARY_PORT || 3000;
const DATA_FILE = path.join(__dirname, 'admin_data.json');

// ── État en mémoire ──────────────────────────────────────────────────────────
let kickedUsers = new Map();   // uuid → { count, firstKick, lastKick, banned }
let bugReports = [];
let broadcastLog = [];
let serverProcess = null;

// ── Persistance des données admin ────────────────────────────────────────────
function loadData() {
  try {
    if (fs.existsSync(DATA_FILE)) {
      const raw = fs.readFileSync(DATA_FILE, 'utf8');
      const data = JSON.parse(raw);
      kickedUsers = new Map(Object.entries(data.kickedUsers || {}));
      bugReports = data.bugReports || [];
      broadcastLog = data.broadcastLog || [];
    }
  } catch (e) {
    console.error('[Admin] Erreur chargement données:', e.message);
  }
}

function saveData() {
  try {
    const data = {
      kickedUsers: Object.fromEntries(kickedUsers),
      bugReports: bugReports.slice(-200), // garder les 200 derniers
      broadcastLog: broadcastLog.slice(-100),
    };
    fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('[Admin] Erreur sauvegarde données:', e.message);
  }
}

loadData();

// ── Utilitaires QR Code (génération SVG simple) ─────────────────────────────
function generateQRCodeSvg(text) {
  // QR Code minimaliste : renvoie une URL de service externe fiable
  // En production, utiliser qrcode npm package
  const encoded = encodeURIComponent(text);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <rect width="200" height="200" fill="white"/>
  <image href="https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encoded}" 
         x="10" y="10" width="180" height="180"/>
</svg>`;
}

// ── Kick / Ban System ────────────────────────────────────────────────────────
function kickUser(uuid, reason) {
  const now = Date.now();
  const existing = kickedUsers.get(uuid) || { count: 0, firstKick: now, lastKick: 0, banned: false };
  
  // Réinitialise le compteur si la fenêtre de 30 min est dépassée
  const windowMs = 30 * 60 * 1000;
  if (now - existing.firstKick > windowMs) {
    existing.count = 0;
    existing.firstKick = now;
  }
  
  existing.count++;
  existing.lastKick = now;
  existing.reason = reason || 'Comportement malveillant';
  
  // Bannissement automatique après 3 kicks en 30 min
  if (existing.count >= 3) {
    existing.banned = true;
    existing.autoLockTriggered = true;
    console.log(`[Admin] AUTO-LOCK déclenché pour ${uuid} (${existing.count} kicks en <30min)`);
  }
  
  kickedUsers.set(uuid, existing);
  saveData();
  return existing;
}

function isUserKicked(uuid) {
  const user = kickedUsers.get(uuid);
  if (!user) return false;
  // Les kicks expirent après 2 heures (sauf bannissement permanent)
  if (user.banned) return true;
  const twoHours = 2 * 60 * 60 * 1000;
  return (Date.now() - user.lastKick) < twoHours;
}

function isAutoLockNeeded(uuid) {
  const user = kickedUsers.get(uuid);
  return user?.autoLockTriggered === true;
}

// ── État serveur simulé ──────────────────────────────────────────────────────
let serverState = {
  routingEngineEnabled: true,
  alertValidationThreshold: 3,
  cacheClearedAt: null,
  totalAlertsValidated: 0,
  connectedClients: 0,
  networkTopology: 'primary_active', // 'primary_active' | 'failover_active' | 'both_active'
};

// ── HTML du dashboard ────────────────────────────────────────────────────────
function getDashboardHtml() {
  const kickList = Array.from(kickedUsers.entries())
    .map(([uuid, data]) => `
      <tr>
        <td class="mono">${uuid.substring(0,12)}…</td>
        <td>${data.count}</td>
        <td>${data.banned ? '<span class="badge banned">BANNI</span>' : '<span class="badge kicked">Kické</span>'}</td>
        <td>${data.reason || '-'}</td>
        <td>${new Date(data.lastKick).toLocaleString('fr-BE')}</td>
        <td>
          <button onclick="unban('${uuid}')" class="btn btn-sm btn-success">Lever</button>
        </td>
      </tr>`).join('');

  const bugList = bugReports.slice(-10).reverse()
    .map(r => `
      <tr>
        <td>${new Date(r.submitted_at || Date.now()).toLocaleString('fr-BE')}</td>
        <td><span class="badge">${r.category || 'bug'}</span></td>
        <td>${r.platform || '?'}</td>
        <td>${escapeHtml(r.title || '')}</td>
        <td style="max-width:300px">${escapeHtml(r.description || '')}</td>
      </tr>`).join('');

  // Dashboard v4.0 — Vue unifiée
  const statsHtml = `
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px">
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:28px;font-weight:700;color:#FFB300" id="stat-clients">${serverState.connectedClients}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Clients connectés</div>
      </div>
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:28px;font-weight:700;color:#3fb950" id="stat-alerts">${serverState.totalAlertsValidated}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Alertes validées</div>
      </div>
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:28px;font-weight:700;color:${serverState.routingEngineEnabled ? '#3fb950' : '#f85149'}" id="stat-routing">${serverState.routingEngineEnabled ? 'ON' : 'OFF'}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Moteur Routage</div>
      </div>
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:28px;font-weight:700;color:#58a6ff" id="stat-threshold">${serverState.alertValidationThreshold}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Seuil Validation</div>
      </div>
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:28px;font-weight:700;color:#d2a8ff" id="stat-kicks">${kickedUsers.size}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Kicks actifs</div>
      </div>
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:28px;font-weight:700;color:#f85149" id="stat-bugs">${bugReports.length}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Bugs signalés</div>
      </div>
      <div style="background:#0d1117;border-radius:8px;padding:14px;text-align:center">
        <div style="font-size:20px;font-weight:700;color:#58a6ff" id="stat-version">${reportsStore.getVersionInfo().min_required}</div>
        <div style="font-size:10px;color:#8b949e;text-transform:uppercase;margin-top:4px">Version Min Requise</div>
      </div>
    </div>`;

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>StreetPhare — Administration</title>
  <style>
    :root {
      --bg: #0d1117; --surface: #161b22; --border: #30363d;
      --primary: #FFB300; --danger: #f85149; --success: #3fb950;
      --text: #c9d1d9; --muted: #8b949e;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: -apple-system, sans-serif; }
    header { background: var(--surface); border-bottom: 1px solid var(--border);
             padding: 16px 24px; display: flex; align-items: center; gap: 12px; }
    header h1 { font-size: 20px; color: var(--primary); }
    .status-dot { width: 10px; height: 10px; border-radius: 50%; background: var(--success); }
    .container { max-width: 1400px; margin: 0 auto; padding: 24px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(380px, 1fr)); gap: 20px; }
    .card { background: var(--surface); border: 1px solid var(--border); 
            border-radius: 10px; padding: 20px; }
    .card h2 { font-size: 14px; color: var(--muted); margin-bottom: 16px; 
               text-transform: uppercase; letter-spacing: 0.8px; }
    .card h2 .icon { margin-right: 8px; }
    input, textarea, select { background: var(--bg); border: 1px solid var(--border);
      color: var(--text); padding: 8px 12px; border-radius: 6px; width: 100%;
      font-size: 14px; margin-bottom: 10px; }
    textarea { resize: vertical; min-height: 80px; }
    .btn { padding: 8px 16px; border-radius: 6px; border: none; cursor: pointer;
           font-size: 13px; font-weight: 600; transition: opacity 0.15s; }
    .btn:hover { opacity: 0.85; }
    .btn-primary { background: var(--primary); color: #000; }
    .btn-danger { background: var(--danger); color: #fff; }
    .btn-success { background: var(--success); color: #000; }
    .btn-outline { background: transparent; border: 1px solid var(--border); color: var(--text); }
    .btn-sm { padding: 4px 10px; font-size: 11px; }
    .btn-row { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th { text-align: left; color: var(--muted); padding: 8px 4px; 
         border-bottom: 1px solid var(--border); }
    td { padding: 8px 4px; border-bottom: 1px solid var(--border); }
    .badge { padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; }
    .badge.banned { background: var(--danger); color: #fff; }
    .badge.kicked { background: #e3b341; color: #000; }
    .mono { font-family: monospace; font-size: 12px; }
    .server-controls { display: flex; gap: 10px; margin-top: 12px; flex-wrap: wrap; }
    #qr-preview { margin-top: 12px; text-align: center; }
    #qr-preview svg, #qr-preview img { border: 2px solid var(--border); border-radius: 8px; }
    .log { background: var(--bg); border: 1px solid var(--border); border-radius: 6px;
           padding: 10px; font-family: monospace; font-size: 12px; max-height: 200px;
           overflow-y: auto; margin-top: 8px; color: var(--muted); }
    .broadcast-type { display: flex; gap: 8px; margin-bottom: 10px; }
    .broadcast-type label { font-size: 13px; cursor: pointer; }
    #status-bar { background: var(--surface); border-top: 1px solid var(--border);
                 padding: 8px 24px; font-size: 12px; color: var(--muted);
                 position: fixed; bottom: 0; left: 0; right: 0; }
    .toggle { display:flex; align-items:center; gap:8px; margin-bottom:10px; }
    .toggle input[type="checkbox"] { width:40px; height:22px; appearance:none; background:var(--border);
      border-radius:11px; cursor:pointer; position:relative; transition:background .2s; }
    .toggle input[type="checkbox"]:checked { background:var(--success); }
    .toggle input[type="checkbox"]::after { content:''; position:absolute; width:18px; height:18px;
      background:#fff; border-radius:50%; top:2px; left:2px; transition:transform .2s; }
    .toggle input[type="checkbox"]:checked::after { transform:translateX(18px); }
    .threshold-control { display:flex; align-items:center; gap:10px; margin-bottom:10px; }
    .threshold-control input[type="range"] { flex:1; accent-color:var(--primary); }
    .topology-badge { display:inline-block; padding:4px 10px; border-radius:12px; font-size:11px; font-weight:600; }
    .topology-primary { background:#1a3a1a; color:#3fb950; }
    .topology-failover { background:#3a1a1a; color:#f85149; }
  </style>
</head>
<body>
<header>
  <div class="status-dot" id="status-dot"></div>
  <h1>💡 StreetPhare — Administration</h1>
  <span class="topology-badge topology-primary" id="topology-badge">🟢 Serveur Principal Actif</span>
  <span style="margin-left:auto;font-size:12px;color:var(--muted)">
    Dashboard v4.0 — ${new Date().toLocaleString('fr-BE')}
  </span>
</header>

<div class="container">

  <!-- ── Stats globales ──────────────────────────────────────────── -->
  ${statsHtml}

  <div class="grid">

    <!-- ── Contrôle du serveur + routage + seuils ────────────────── -->
    <div class="card" style="grid-column:1/-1">
      <h2><span class="icon">🎛️</span> Contrôle Total du Serveur</h2>
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;flex-wrap:wrap">
        <div>
          <h3 style="font-size:12px;color:var(--muted);margin-bottom:8px">Processus Serveur (port ${PRIMARY_SERVER_PORT})</h3>
          <div class="server-controls">
            <button class="btn btn-success" onclick="serverAction('start')">▶ Start</button>
            <button class="btn btn-danger" onclick="serverAction('stop')">■ Stop</button>
            <button class="btn btn-primary" onclick="serverAction('restart')">↺ Restart</button>
          </div>
          <div class="log" id="server-log">En attente de commandes…</div>
        </div>
        <div>
          <h3 style="font-size:12px;color:var(--muted);margin-bottom:8px">Moteur de Routage OsmAnd Core</h3>
          <div class="toggle">
            <input type="checkbox" id="routing-toggle" ${serverState.routingEngineEnabled ? 'checked' : ''} onchange="toggleRouting(this.checked)">
            <label for="routing-toggle" style="font-size:13px">${serverState.routingEngineEnabled ? '🟢 Activé' : '🔴 Désactivé'}</label>
          </div>
          <h3 style="font-size:12px;color:var(--muted);margin:12px 0 8px">Seuil de Validation des Alertes</h3>
          <div class="threshold-control">
            <input type="range" id="threshold-slider" min="1" max="10" value="${serverState.alertValidationThreshold}" oninput="document.getElementById('threshold-val').textContent=this.value">
            <span id="threshold-val" style="font-size:16px;font-weight:bold;color:var(--primary);min-width:30px">${serverState.alertValidationThreshold}</span>
            <button class="btn btn-primary btn-sm" onclick="setThreshold(document.getElementById('threshold-slider').value)">Appliquer</button>
          </div>
          <button class="btn btn-danger btn-sm" onclick="clearCache()" style="margin-top:12px">🗑 Effacer le Cache Global</button>
        </div>
        <div>
          <h3 style="font-size:12px;color:var(--muted);margin-bottom:8px">Kill Switch & Versions</h3>
          <div style="display:flex;flex-direction:column;gap:5px">
             <input type="text" id="v-latest" placeholder="Dernière version (ex: 1.2.0)" value="${reportsStore.getVersionInfo().latest}">
             <input type="text" id="v-min" placeholder="Version min requise (ex: 1.1.0)" value="${reportsStore.getVersionInfo().min_required}">
             <input type="text" id="v-url" placeholder="URL de téléchargement" value="${reportsStore.getVersionInfo().url}">
             <button class="btn btn-danger btn-sm" onclick="updateVersionInfo()">⚠️ Appliquer Kill Switch</button>
          </div>
          <h3 style="font-size:12px;color:var(--muted);margin:12px 0 8px">Injection de Données Fictives (Sandbox)</h3>
          <div class="server-controls">
            <button class="btn btn-primary" onclick="sandboxQuick('alerts',5)">🚨 +5 Alertes</button>
            <button class="btn btn-primary" onclick="sandboxQuick('users',10)">👥 +10 Users</button>
            <button class="btn btn-primary" onclick="sandboxQuick('panic',3)">🆘 Panic</button>
          </div>
          <div class="log" id="sandbox-log">Prêt pour injection…</div>
          <a href="/sandbox" target="_blank" class="btn btn-outline btn-sm" style="margin-top:8px;display:inline-block">🔗 Ouvrir la Sandbox complète</a>
        </div>
      </div>
    </div>

    <!-- ── Générateur QR Code ──────────────────────────────────── -->
    <div class="card">
      <h2><span class="icon">📱</span> Générateur de QR Code</h2>
      <input type="text" id="qr-event-title" placeholder="Titre de l'événement">
      <input type="text" id="qr-event-code" placeholder="Code d'accès (ex: FLEURUS2026)">
      <input type="datetime-local" id="qr-event-time">
      <button class="btn btn-primary" onclick="generateQR()">Générer le QR Code</button>
      <div id="qr-preview"></div>
      <div id="qr-data" style="font-size:11px;color:var(--muted);margin-top:8px;word-break:break-all"></div>
    </div>

    <!-- ── Gestion des événements ──────────────────────────────── -->
    <div class="card">
      <h2><span class="icon">📍</span> Gestion des Événements Fleurus</h2>
      <input type="text" id="ev-title" placeholder="Titre (ex: Marche de Fleurus 2026)">
      <textarea id="ev-route" placeholder="Coordonnées du trajet (JSON ou GeoJSON)…" rows="4"></textarea>
      <input type="text" id="ev-destination" placeholder="Destination (lat,lng)">
      <input type="datetime-local" id="ev-time">
      <div class="btn-row">
        <button class="btn btn-primary" onclick="saveEvent()">💾 Enregistrer</button>
        <button class="btn btn-outline" onclick="loadEvents()">🔄 Actualiser</button>
      </div>
      <div id="events-list" style="margin-top:12px;font-size:13px"></div>
    </div>

    <!-- ── Console de communication ───────────────────────────── -->
    <div class="card">
      <h2><span class="icon">📡</span> Console de Communication Réseau</h2>
      <div class="broadcast-type">
        <label><input type="radio" name="btype" value="broadcast" checked> 📢 Broadcast global</label>
        <label><input type="radio" name="btype" value="alert"> 🚨 Alerte événement</label>
        <label><input type="radio" name="btype" value="info"> ℹ️ Information</label>
      </div>
      <input type="text" id="bc-title" placeholder="Titre du message">
      <textarea id="bc-message" placeholder="Contenu du message à diffuser sur le réseau Hive…"></textarea>
      <button class="btn btn-primary" onclick="sendBroadcast()">📤 Envoyer sur le réseau Hive</button>
      <div class="log" id="broadcast-log">Aucun broadcast envoyé.</div>
    </div>

    <!-- ── Kick / Ban ──────────────────────────────────────────── -->
    <div class="card">
      <h2><span class="icon">🚫</span> Kick & Bannissement</h2>
      <p style="font-size:12px;color:var(--muted);margin-bottom:10px">
        3 kicks en 30 min → verrouillage automatique de l'application cliente.
      </p>
      <input type="text" id="kick-uuid" placeholder="UUID éphémère de l'utilisateur">
      <input type="text" id="kick-reason" placeholder="Raison (ex: Spam, Insultes)">
      <div class="btn-row">
        <button class="btn btn-danger" onclick="kickUser()">🦵 Kicker</button>
        <button class="btn btn-outline" onclick="banUser()">⛔ Bannir définitivement</button>
      </div>
      <table style="margin-top:16px">
        <thead>
          <tr>
            <th>UUID</th><th>Kicks</th><th>Statut</th>
            <th>Raison</th><th>Dernier kick</th><th>Action</th>
          </tr>
        </thead>
        <tbody id="kick-table">${kickList || '<tr><td colspan="6" style="color:var(--muted)">Aucun utilisateur kické.</td></tr>'}</tbody>
      </table>
    </div>

    <!-- ── Rapports de bugs ────────────────────────────────────── -->
    <div class="card">
      <h2><span class="icon">🐛</span> Rapports de Bugs (${bugReports.length})</h2>
      <table>
        <thead>
          <tr><th>Date</th><th>Cat.</th><th>Plateforme</th><th>Titre</th><th>Description</th></tr>
        </thead>
        <tbody id="bug-table">${bugList || '<tr><td colspan="5" style="color:var(--muted)">Aucun rapport.</td></tr>'}</tbody>
      </table>
      <button class="btn btn-outline btn-sm" onclick="clearBugReports()" style="margin-top:8px">
        Effacer tous les rapports
      </button>
    </div>

  </div>
</div>

<div id="status-bar">Admin StreetPhare v3.0 | Port ${PORT} | 
  Kicks actifs : <span id="kick-count">${kickedUsers.size}</span> | 
  Bugs reçus : <span id="bug-count">${bugReports.length}</span>
</div>

<script>
async function api(endpoint, method = 'GET', body = null) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch('/api' + endpoint, opts);
  return r.json();
}

async function serverAction(action) {
  const log = document.getElementById('server-log');
  log.textContent = 'Exécution de : ' + action + '…';
  try {
    const res = await api('/server/' + action, 'POST');
    log.textContent = res.message || JSON.stringify(res);
  } catch(e) { log.textContent = 'Erreur : ' + e.message; }
}

function generateQR() {
  const title = document.getElementById('qr-event-title').value;
  const code = document.getElementById('qr-event-code').value;
  const time = document.getElementById('qr-event-time').value;
  const payload = JSON.stringify({ title, code, time, type: 'streetphare_event' });
  const preview = document.getElementById('qr-preview');
  const dataEl = document.getElementById('qr-data');
  const encoded = encodeURIComponent(payload);
  preview.innerHTML = \`<img src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=\${encoded}" width="200" height="200" alt="QR Code">\`;
  dataEl.textContent = 'Données : ' + payload;
}

async function saveEvent() {
  const ev = {
    title: document.getElementById('ev-title').value,
    route: document.getElementById('ev-route').value,
    destination: document.getElementById('ev-destination').value,
    eventTime: document.getElementById('ev-time').value,
  };
  const res = await api('/events', 'POST', ev);
  alert(res.message || 'Événement sauvegardé');
  loadEvents();
}

async function loadEvents() {
  const res = await api('/events');
  const el = document.getElementById('events-list');
  if (!res.events || res.events.length === 0) {
    el.textContent = 'Aucun événement enregistré.';
    return;
  }
  el.innerHTML = res.events.map((ev, i) => \`
    <div style="padding:8px;border:1px solid var(--border);border-radius:6px;margin-bottom:6px">
      <strong>\${ev.title}</strong> — \${ev.eventTime || 'heure inconnue'}
      <button class="btn btn-sm btn-danger" onclick="deleteEvent(\${i})" style="float:right">🗑</button>
    </div>\`).join('');
}

async function deleteEvent(i) {
  await api('/events/' + i, 'DELETE');
  loadEvents();
}

async function sendBroadcast() {
  const type = document.querySelector('input[name="btype"]:checked').value;
  const title = document.getElementById('bc-title').value;
  const message = document.getElementById('bc-message').value;
  if (!message.trim()) { alert('Message vide'); return; }
  const res = await api('/broadcast', 'POST', { type, title, message });
  const log = document.getElementById('broadcast-log');
  log.textContent = '[' + new Date().toLocaleTimeString('fr-BE') + '] ' 
    + (res.message || 'Broadcast envoyé') + '\\n' + log.textContent;
  document.getElementById('bc-message').value = '';
}

async function kickUser() {
  const uuid = document.getElementById('kick-uuid').value.trim();
  const reason = document.getElementById('kick-reason').value.trim();
  if (!uuid) { alert('UUID requis'); return; }
  const res = await api('/kick', 'POST', { uuid, reason });
  alert(res.message);
  location.reload();
}

async function banUser() {
  const uuid = document.getElementById('kick-uuid').value.trim();
  const reason = document.getElementById('kick-reason').value.trim();
  if (!uuid) { alert('UUID requis'); return; }
  const res = await api('/ban', 'POST', { uuid, reason });
  alert(res.message);
  location.reload();
}

async function unban(uuid) {
  const res = await api('/unban', 'POST', { uuid });
  alert(res.message);
  location.reload();
}

async function clearBugReports() {
  if (!confirm('Effacer tous les rapports de bugs ?')) return;
  await api('/bug-reports/clear', 'DELETE');
  location.reload();
}

loadEvents();

// ── Fonctions de contrôle serveur (Dashboard v4.0) ──────────────────
async function toggleRouting(enabled) {
  await api('/routing-toggle', 'POST', { enabled });
  document.getElementById('stat-routing').textContent = enabled ? 'ON' : 'OFF';
  document.getElementById('stat-routing').style.color = enabled ? '#3fb950' : '#f85149';
}

async function setThreshold(val) {
  await api('/threshold', 'POST', { threshold: parseInt(val) });
  document.getElementById('stat-threshold').textContent = val;
}

async function clearCache() {
  const r = await api('/clear-cache', 'POST');
  alert(r.message || 'Cache effacé');
}

async function updateVersionInfo() {
  const info = {
    latest: document.getElementById('v-latest').value,
    min_required: document.getElementById('v-min').value,
    url: document.getElementById('v-url').value,
  };
  await api('/version-config', 'POST', info);
  alert('Configuration des versions mise à jour');
  refreshDashboard();
}

async function sandboxQuick(type, count) {
  const log = document.getElementById('sandbox-log');
  log.textContent = 'Injection en cours…';
  try {
    const endpoint = type === 'panic' ? '/trigger-panic' : type === 'users' ? '/simulate-users' : '/inject-alerts';
    const body = type === 'panic' ? { peerCount: count } : { count };
    const r = await fetch('/sandbox' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await r.json();
    log.textContent = '✅ ' + JSON.stringify(data).substring(0, 120);
  } catch(e) {
    log.textContent = '❌ ' + e.message;
  }
}

async function refreshDashboard() {
  try {
    const r = await api('/server-state');
    document.getElementById('stat-clients').textContent = r.connectedClients;
    document.getElementById('stat-alerts').textContent = r.totalAlertsValidated;
    document.getElementById('stat-kicks').textContent = r.kickedUsersCount;
    document.getElementById('stat-bugs').textContent = r.bugReportsCount;
    document.getElementById('stat-routing').textContent = r.routingEngineEnabled ? 'ON' : 'OFF';
    document.getElementById('stat-routing').style.color = r.routingEngineEnabled ? '#3fb950' : '#f85149';
    document.getElementById('stat-threshold').textContent = r.alertValidationThreshold;
    document.getElementById('threshold-slider').value = r.alertValidationThreshold;
    document.getElementById('threshold-val').textContent = r.alertValidationThreshold;
    document.getElementById('stat-version').textContent = r.min_required;
  } catch(_) {}
}
setInterval(refreshDashboard, 10000);
</script>
</body>
</html>`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Gestion des événements (fichier events.json) ─────────────────────────────
const EVENTS_FILE = path.join(__dirname, 'events_admin.json');

function loadEvents() {
  try {
    if (fs.existsSync(EVENTS_FILE)) {
      return JSON.parse(fs.readFileSync(EVENTS_FILE, 'utf8'));
    }
  } catch (_) {}
  return [];
}

function saveEvents(events) {
  fs.writeFileSync(EVENTS_FILE, JSON.stringify(events, null, 2));
}

// ── Routeur HTTP ──────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;

  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-StreetPhare-Client');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Dashboard principal
  if (pathname === '/' || pathname === '/dashboard') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(getDashboardHtml());
    return;
  }

  // Lecture du body JSON
  const bodyPromise = () => new Promise((resolve) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try { resolve(JSON.parse(body)); } catch (_) { resolve({}); }
    });
  });

  const json = (code, data) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
  };

  // ── API Routes ──────────────────────────────────────────────────
  if (pathname.startsWith('/api/')) {
    const apiPath = pathname.slice(4); // retire /api

    // POST /api/bug-report — Réception des rapports de bugs depuis les clients
    if (req.method === 'POST' && apiPath === '/bug-report') {
      bodyPromise().then(body => {
        const report = { ...body, receivedAt: new Date().toISOString() };
        bugReports.push(report);
        saveData();
        console.log(`[Admin] Bug report reçu: ${body.title || 'Sans titre'} (${body.platform})`);
        json(201, { status: 'ok', message: 'Rapport reçu' });
      });
      return;
    }

    // POST /api/server/start|stop|restart|status
    if (req.method === 'POST' && apiPath.startsWith('/server/')) {
      const action = apiPath.split('/')[2];
      const serverScript = path.join(__dirname, 'server_primary_v2.js');

      if (action === 'start') {
        if (serverProcess) {
          json(200, { message: 'Serveur déjà en cours d\'exécution.' });
          return;
        }
        try {
          serverProcess = spawn('node', [serverScript], {
            stdio: 'inherit',
            detached: false,
          });
          serverProcess.on('exit', () => { serverProcess = null; });
          json(200, { message: `Serveur démarré (PID ${serverProcess.pid})` });
        } catch (e) {
          json(500, { message: `Erreur: ${e.message}` });
        }
      } else if (action === 'stop') {
        if (!serverProcess) {
          json(200, { message: 'Aucun serveur en cours.' });
          return;
        }
        try {
          serverProcess.kill('SIGTERM');
          serverProcess = null;
          json(200, { message: 'Serveur arrêté.' });
        } catch (e) {
          json(500, { message: `Erreur: ${e.message}` });
        }
      } else if (action === 'restart') {
        if (serverProcess) {
          try { serverProcess.kill('SIGTERM'); } catch (_) {}
          serverProcess = null;
        }
        try {
          serverProcess = spawn('node', [serverScript], {
            stdio: 'inherit',
            detached: false,
          });
          serverProcess.on('exit', () => { serverProcess = null; });
          json(200, { message: `Serveur redémarré (PID ${serverProcess.pid})` });
        } catch (e) {
          json(500, { message: `Erreur: ${e.message}` });
        }
      } else if (action === 'status') {
        json(200, {
          running: serverProcess !== null,
          pid: serverProcess?.pid || null,
          message: serverProcess ? `En cours (PID ${serverProcess.pid})` : 'Arrêté',
        });
      } else {
        json(404, { message: 'Action inconnue' });
      }
      return;
    }

    // GET /api/events
    if (req.method === 'GET' && apiPath === '/events') {
      json(200, { events: loadEvents() });
      return;
    }

    // POST /api/events
    if (req.method === 'POST' && apiPath === '/events') {
      bodyPromise().then(body => {
        const events = loadEvents();
        events.push({ ...body, id: crypto.randomUUID(), createdAt: new Date().toISOString() });
        saveEvents(events);
        json(201, { message: 'Événement créé' });
      });
      return;
    }

    // DELETE /api/events/:index
    if (req.method === 'DELETE' && apiPath.startsWith('/events/')) {
      const idx = parseInt(apiPath.split('/')[2]);
      const events = loadEvents();
      if (idx >= 0 && idx < events.length) {
        events.splice(idx, 1);
        saveEvents(events);
        json(200, { message: 'Événement supprimé' });
      } else {
        json(404, { message: 'Événement introuvable' });
      }
      return;
    }

    // POST /api/broadcast — Diffuse un message vers le serveur primaire
    if (req.method === 'POST' && apiPath === '/broadcast') {
      bodyPromise().then(body => {
        const { type = 'broadcast', title, message } = body;
        const entry = {
          type, title, message,
          sentAt: new Date().toISOString(),
        };
        broadcastLog.push(entry);
        saveData();

        // Forward vers le serveur primaire
        const payload = JSON.stringify({
          event: 'admin_broadcast',
          type,
          title: title || 'Message Administrateur',
          message,
          timestamp: entry.sentAt,
        });

        const options = {
          hostname: '127.0.0.1',
          port: PRIMARY_SERVER_PORT,
          path: '/api/admin-broadcast',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payload),
            'X-Admin-Key': process.env.ADMIN_KEY || 'streetphare_admin',
          },
        };

        const req2 = http.request(options, r => {
          console.log(`[Admin] Broadcast relayé → ${r.statusCode}`);
        });
        req2.on('error', err => {
          console.error('[Admin] Erreur relay broadcast:', err.message);
        });
        req2.write(payload);
        req2.end();

        json(200, { message: `Broadcast "${type}" envoyé sur le réseau Hive` });
      });
      return;
    }

    // POST /api/kick
    if (req.method === 'POST' && apiPath === '/kick') {
      bodyPromise().then(body => {
        const { uuid, reason } = body;
        if (!uuid) { json(400, { message: 'UUID requis' }); return; }
        const result = kickUser(uuid, reason);
        const msg = result.autoLockTriggered
          ? `⚠️ VERROUILLAGE AUTO déclenché pour ${uuid} (${result.count} kicks)`
          : `Utilisateur ${uuid} kické (${result.count} fois)`;
        json(200, { message: msg, autoLock: result.autoLockTriggered });
      });
      return;
    }

    // POST /api/ban
    if (req.method === 'POST' && apiPath === '/ban') {
      bodyPromise().then(body => {
        const { uuid, reason } = body;
        if (!uuid) { json(400, { message: 'UUID requis' }); return; }
        const existing = kickedUsers.get(uuid) || { count: 0, firstKick: Date.now() };
        existing.banned = true;
        existing.reason = reason || 'Bannissement manuel';
        existing.lastKick = Date.now();
        kickedUsers.set(uuid, existing);
        saveData();
        json(200, { message: `Utilisateur ${uuid} banni définitivement` });
      });
      return;
    }

    // POST /api/unban
    if (req.method === 'POST' && apiPath === '/unban') {
      bodyPromise().then(body => {
        const { uuid } = body;
        kickedUsers.delete(uuid);
        saveData();
        json(200, { message: `Utilisateur ${uuid} débanni` });
      });
      return;
    }

    // GET /api/kick-status/:uuid — Vérifié par les clients
    if (req.method === 'GET' && apiPath.startsWith('/kick-status/')) {
      const uuid = apiPath.split('/')[2];
      json(200, {
        kicked: isUserKicked(uuid),
        autoLock: isAutoLockNeeded(uuid),
        banned: kickedUsers.get(uuid)?.banned || false,
      });
      return;
    }

    // DELETE /api/bug-reports/clear
    if (req.method === 'DELETE' && apiPath === '/bug-reports/clear') {
      bugReports = [];
      saveData();
      json(200, { message: 'Rapports de bugs effacés' });
      return;
    }

    // POST /api/routing-toggle — Activation/désactivation moteur de routage
    if (req.method === 'POST' && apiPath === '/routing-toggle') {
      bodyPromise().then(body => {
        serverState.routingEngineEnabled = !!body.enabled;
        console.log(`[Admin] Moteur routage ${serverState.routingEngineEnabled ? 'ACTIVÉ' : 'DÉSACTIVÉ'}`);
        json(200, { enabled: serverState.routingEngineEnabled });
      });
      return;
    }

    // POST /api/threshold — Modification du seuil de validation
    if (req.method === 'POST' && apiPath === '/threshold') {
      bodyPromise().then(body => {
        const val = parseInt(body.threshold) || 3;
        serverState.alertValidationThreshold = Math.max(1, Math.min(10, val));
        console.log(`[Admin] Seuil de validation → ${serverState.alertValidationThreshold}`);
        json(200, { threshold: serverState.alertValidationThreshold });
      });
      return;
    }

    // POST /api/clear-cache — Effacement global du cache
    if (req.method === 'POST' && apiPath === '/clear-cache') {
      serverState.cacheClearedAt = new Date().toISOString();
      console.log('[Admin] Cache global effacé');
      json(200, { message: 'Cache effacé', clearedAt: serverState.cacheClearedAt });
      return;
    }

    // POST /api/version-config — Configuration du Kill Switch
    if (req.method === 'POST' && apiPath === '/version-config') {
      bodyPromise().then(body => {
        reportsStore.setVersionInfo(body);
        console.log('[Admin] Configuration version mise à jour:', body);
        json(200, { status: 'ok' });
      });
      return;
    }

    // GET /api/server-state — État global du serveur
    if (req.method === 'GET' && apiPath === '/server-state') {
      const vInfo = reportsStore.getVersionInfo();
      json(200, {
        ...serverState,
        ...vInfo,
        kickedUsersCount: kickedUsers.size,
        bugReportsCount: bugReports.length,
        uptime: process.uptime(),
      });
      return;
    }

    json(404, { message: 'Route API inconnue' });
    return;
  }

  // [4] Sandbox — délègue à l'app Express sous-montée sur /sandbox
  if (pathname.startsWith('/sandbox')) {
    const app = getSandboxApp();
    if (app) {
      app(req, res);
    } else {
      res.writeHead(503, { 'Content-Type': 'text/plain' });
      res.end('Sandbox indisponible (express non installé). Lancez : cd test_servers && npm install');
    }
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

server.listen(PORT, () => {
  console.log(`\n🌐 [Admin Dashboard] StreetPhare v3.0`);
  console.log(`   URL : http://localhost:${PORT}`);
  console.log(`   Fonctionnalités : QR Codes | Événements | Broadcast | Kick/Ban | Bug Reports\n`);
});

module.exports = { kickUser, isUserKicked, isAutoLockNeeded };
