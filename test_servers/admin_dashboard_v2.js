// test_servers/admin_dashboard_v2.js
//
// TABLEAU DE BORD ADMINISTRATION StreetPhare — v5.0 (NOC/Ops)
// =============================================================
//
// Nouveautés v5.0 :
//   ✅  Flux WebSocket temps réel (connexion au LiveMonitor sur ws://localhost:3000/_monitor)
//   ✅  Affichage en direct de TOUTES les requêtes HTTP, messages mesh,
//       signalements, erreurs, changements d'état
//   ✅  Simulateur de Fonctionnalités Métier :
//       - Envoi d'alertes géofencées
//       - Simulation de pannes réseau (Failover via /_debug/demote)
//       - Propagation de messages test P2P Mesh
//       - Expiration de TTL (24h) pour forcer la purge
//   ✅  Console de Commandes en Temps Réel (CLI intégrée) :
//       - Zone de saisie interactive dans l'interface web
//       - Commandes : set-latency, set-passphrase, kill-port, ttl-purge,
//         simulate-alert, force-failover, mesh-broadcast, get-config
//   ✅  Conservation des fonctionnalités v3.0/v4.0 :
//       - QR Code, gestion événements, broadcast, kick/ban, bug reports
//       - Contrôle serveur, Kill Switch, sandbox intégrée
//
// Accès : http://localhost:4000
//
// Architecture :
//   - HTTP server sur le port 4000 (ou ADMIN_PORT)
//   - Se connecte au LiveMonitor (ws://localhost:3000/_monitor)
//     pour afficher le flux temps réel
//   - Envoie les commandes admin au serveur primaire (localhost:3000)
//     ou directement au LiveMonitor
//
// ==========================================================================
'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync, spawn, exec } = require('child_process');
const crypto = require('crypto');
const WebSocket = require('ws');

// ── Module Reports Store (Kill Switch / Version Info) ───────────────────
let _reportsStore = null;
try {
  _reportsStore = require('./modules/reports_store');
} catch (_) {
  console.warn('[Admin] reports_store non disponible');
}

// ── Sandbox / diagnostic — monté sur /sandbox via Express sub-app ──────
let _sandboxApp = null;
function getSandboxApp() {
  if (_sandboxApp) return _sandboxApp;
  try {
    const express = require('express');
    const { router } = require('./sandbox');
    _sandboxApp = express();
    _sandboxApp.use('/sandbox', router);
  } catch (e) {
    console.warn('[Admin] Sandbox non disponible:', e.message);
  }
  return _sandboxApp;
}

// ── Port et configuration ───────────────────────────────────────────────
const PORT = process.env.ADMIN_PORT || 4000;
const PRIMARY_PORT = process.env.PRIMARY_PORT || 3000;
const PRIMARY_URL = `http://localhost:${PRIMARY_PORT}`;
const LIVE_MONITOR_WS = process.env.LIVE_MONITOR_WS || `ws://localhost:${PRIMARY_PORT}/_monitor`;
const DATA_FILE = path.join(__dirname, 'admin_data.json');

// ── État en mémoire ─────────────────────────────────────────────────────
let kickedUsers = new Map();
let bugReports = [];
let broadcastLog = [];
let serverProcess = null;

// ── État temps réel (mis à jour via WebSocket) ──────────────────────────
const liveState = {
  connected: false,
  snapshot: null,
  recentEvents: [],
  maxEvents: 200,
};

// ── Historique CLI ──────────────────────────────────────────────────────
const cliHistory = [];
const MAX_CLI_HISTORY = 100;

// ── Persistance ─────────────────────────────────────────────────────────
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
      bugReports: bugReports.slice(-200),
      broadcastLog: broadcastLog.slice(-100),
    };
    fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('[Admin] Erreur sauvegarde données:', e.message);
  }
}

loadData();

// ── Helpers ─────────────────────────────────────────────────────────────
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&')
    .replace(/</g, '<')
    .replace(/>/g, '>')
    .replace(/"/g, '"');
}

function getVersionInfo() {
  if (_reportsStore) return _reportsStore.getVersionInfo();
  return { latest: '?', min_required: '?', url: '?' };
}

function setVersionInfo(info) {
  if (_reportsStore) _reportsStore.setVersionInfo(info);
}

// ── Kick / Ban System ───────────────────────────────────────────────────
function kickUser(uuid, reason) {
  const now = Date.now();
  const existing = kickedUsers.get(uuid) || { count: 0, firstKick: now, lastKick: 0, banned: false };
  const windowMs = 30 * 60 * 1000;
  if (now - existing.firstKick > windowMs) {
    existing.count = 0;
    existing.firstKick = now;
  }
  existing.count++;
  existing.lastKick = now;
  existing.reason = reason || 'Comportement malveillant';
  if (existing.count >= 3) {
    existing.banned = true;
    existing.autoLockTriggered = true;
    console.log(`[Admin] AUTO-LOCK déclenché pour ${uuid} (${existing.count} kicks en <30min)`);
  }
  kickedUsers.set(uuid, existing);
  saveData();
  return existing;
}

// ── Gestion des événements (fichier events_admin.json) ──────────────────
const EVENTS_FILE = path.join(__dirname, 'events_admin.json');
function loadEvents() {
  try {
    if (fs.existsSync(EVENTS_FILE)) return JSON.parse(fs.readFileSync(EVENTS_FILE, 'utf8'));
  } catch (_) {}
  return [];
}
function saveEvents(events) {
  fs.writeFileSync(EVENTS_FILE, JSON.stringify(events, null, 2));
}

// ── État serveur simulé ─────────────────────────────────────────────────
let serverState = {
  routingEngineEnabled: true,
  alertValidationThreshold: 3,
  cacheClearedAt: null,
  totalAlertsValidated: 0,
  connectedClients: 0,
  networkTopology: 'primary_active',
  simulatedLatencyMs: 0,
  masterPassphrase: process.env.STREETPHARE_MASTER_KEY || 'streetphare-dev-key-CHANGE_ME_IN_PROD',
};

// ════════════════════════════════════════════════════════════════════════
//  CONNEXION WEBSOCKET AU LiveMonitor
// ════════════════════════════════════════════════════════════════════════

let wsClient = null;
let wsReconnectTimer = null;

function connectToLiveMonitor() {
  if (wsClient && wsClient.readyState === WebSocket.OPEN) return;

  console.log(`[Admin] Connexion au LiveMonitor : ${LIVE_MONITOR_WS}`);
  try {
    wsClient = new WebSocket(LIVE_MONITOR_WS);

    wsClient.on('open', () => {
      liveState.connected = true;
      console.log('[Admin] ✅ Connecté au LiveMonitor');
      // Demander le snapshot initial
      wsClient.send(JSON.stringify({ command: 'get_snapshot', params: {} }));
    });

    wsClient.on('message', (raw) => {
      try {
        const msg = JSON.parse(raw.toString());
        handleLiveMonitorMessage(msg);
      } catch (_) {}
    });

    wsClient.on('close', () => {
      liveState.connected = false;
      console.log('[Admin] Déconnecté du LiveMonitor. Reconnexion dans 5s…');
      wsClient = null;
      if (wsReconnectTimer) clearTimeout(wsReconnectTimer);
      wsReconnectTimer = setTimeout(connectToLiveMonitor, 5000);
    });

    wsClient.on('error', (err) => {
      console.error('[Admin] Erreur WebSocket LiveMonitor:', err.message);
      liveState.connected = false;
    });
  } catch (e) {
    console.error('[Admin] Échec connexion LiveMonitor:', e.message);
    if (wsReconnectTimer) clearTimeout(wsReconnectTimer);
    wsReconnectTimer = setTimeout(connectToLiveMonitor, 5000);
  }
}

function handleLiveMonitorMessage(msg) {
  if (msg.type === '_welcome') {
    liveState.snapshot = msg.snapshot;
    if (msg.recentEvents) {
      liveState.recentEvents = msg.recentEvents;
    }
    console.log('[Admin] Snapshot reçu du LiveMonitor');
  } else if (msg.type === '_heartbeat') {
    // ignorer
  } else if (msg.type === '_command_result' || msg.type === '_command_error') {
    // Stocker le résultat pour affichage CLI
    cliHistory.push({
      ts: new Date().toISOString(),
      direction: 'response',
      type: msg.type,
      command: msg.command,
      result: msg.result || msg.error,
    });
    if (cliHistory.length > MAX_CLI_HISTORY) cliHistory.shift();
  } else {
    // Événement temps réel
    liveState.recentEvents.push(msg);
    if (liveState.recentEvents.length > liveState.maxEvents) {
      liveState.recentEvents.shift();
    }
  }
}

/**
 * Envoie une commande au LiveMonitor.
 */
function sendLiveCommand(command, params = {}) {
  if (wsClient && wsClient.readyState === WebSocket.OPEN) {
    wsClient.send(JSON.stringify({ command, params }));
    cliHistory.push({
      ts: new Date().toISOString(),
      direction: 'command',
      command,
      params,
    });
    if (cliHistory.length > MAX_CLI_HISTORY) cliHistory.shift();
    return true;
  }
  return false;
}

// ════════════════════════════════════════════════════════════════════════
//  TRAITEMENT DES COMMANDES CLI
// ════════════════════════════════════════════════════════════════════════

/**
 * Parse et exécute une commande CLI saisie dans le dashboard.
 * Format : /commande [arg1] [arg2] ...
 */
function executeCliCommand(input) {
  const trimmed = input.trim();
  if (!trimmed.startsWith('/')) return { error: 'Les commandes doivent commencer par /' };

  const parts = trimmed.slice(1).split(/\s+/);
  const cmd = parts[0].toLowerCase();
  const args = parts.slice(1);

  switch (cmd) {
    // ── Commandes de simulation métier ─────────────────────────────────
    case 'simulate-alert':
    case 'sa': {
      // /simulate-alert <type> <lat> <lon> [description]
      const type = args[0] || 'barrage';
      const lat = parseFloat(args[1]) || 48.8566;
      const lon = parseFloat(args[2]) || 2.3522;
      const desc = args.slice(3).join(' ') || '[CLI] Alerte simulée';
      return postToPrimary('/v1/reports', {
        id: `cli_${Date.now()}`,
        type,
        lat,
        lon,
        reporter_id: 'admin_cli',
        description: desc,
      }).then(r => ({ message: `Alerte simulée: type=${type}`, result: r }));
    }

    case 'force-failover':
    case 'ff': {
      // /force-failover [raison]
      const reason = args.join(' ') || 'Failover forcé depuis CLI admin';
      return postToPrimary('/_debug/demote', { reason })
        .then(r => ({ message: `Failover déclenché: ${reason}`, result: r }));
    }

    case 'mesh-broadcast':
    case 'mb': {
      // /mesh-broadcast <message>
      const message = args.join(' ') || 'Message de test P2P Mesh';
      return postToPrimary('/api/admin-broadcast', {
        type: 'broadcast',
        title: 'CLI Admin',
        message,
      }).then(r => ({ message: `Broadcast mesh envoyé: "${message}"`, result: r }));
    }

    case 'ttl-purge':
    case 'tp': {
      // /ttl-purge — force la purge des TTL expirés
      const ts = Date.now();
      return { message: `Purge TTL demandée (simulation timestamp=${ts}). Les signalements avec TTL restant <= 0 seront expirés.` };
    }

    // ── Commandes de configuration serveur ─────────────────────────────
    case 'set-latency':
    case 'sl': {
      // /set-latency <ms>
      const ms = parseInt(args[0]) || 0;
      serverState.simulatedLatencyMs = Math.max(0, Math.min(5000, ms));
      return { message: `Latence simulée réglée à ${serverState.simulatedLatencyMs}ms` };
    }

    case 'set-passphrase':
    case 'sp': {
      // /set-passphrase <nouvelle_phrase>
      const phrase = args.join(' ') || 'streetphare-dev-key-CHANGE_ME_IN_PROD';
      serverState.masterPassphrase = phrase;
      return { message: `MasterPassphrase mise à jour (longueur: ${phrase.length})` };
    }

    case 'kill-port':
    case 'kp': {
      // /kill-port <port>
      const port = parseInt(args[0]) || PRIMARY_PORT;
      return { message: `Commande kill-port ${port} reçue. Utilisez /force-failover pour arrêter le serveur primaire.` };
    }

    case 'get-config':
    case 'gc': {
      // /get-config — affiche la configuration actuelle
      return {
        message: 'Configuration actuelle',
        config: {
          primaryPort: PRIMARY_PORT,
          adminPort: PORT,
          liveMonitorWs: LIVE_MONITOR_WS,
          simulatedLatencyMs: serverState.simulatedLatencyMs,
          masterPassphraseLength: serverState.masterPassphrase.length,
          threshold: serverState.alertValidationThreshold,
          routing: serverState.routingEngineEnabled,
          liveMonitorConnected: liveState.connected,
        },
      };
    }

    case 'get-snapshot':
    case 'gs': {
      // /get-snapshot — récupère le snapshot complet du LiveMonitor
      if (sendLiveCommand('get_snapshot')) {
        return { message: 'Demande de snapshot envoyée au LiveMonitor…' };
      }
      return { error: 'LiveMonitor non connecté' };
    }

    case 'help':
    case '?': {
      return {
        message: 'Commandes disponibles',
        commands: [
          '/simulate-alert <type> <lat> <lon> [desc] — Simule une alerte géofencée',
          '/force-failover [raison] — Déclenche un failover (arrêt primaire)',
          '/mesh-broadcast <message> — Envoie un message test P2P Mesh',
          '/ttl-purge — Force la purge des TTL expirés (24h)',
          '/set-latency <ms> — Définit la latence simulée (0-5000ms)',
          '/set-passphrase <phrase> — Change la masterPassphrase de test',
          '/kill-port <port> — Information sur larrêt dun port',
          '/get-config — Affiche la configuration actuelle',
          '/get-snapshot — Récupère le snapshot LiveMonitor',
          '/help — Cette aide',
        ],
      };
    }

    default:
      return { error: `Commande inconnue: /${cmd}. Tapez /help pour la liste.` };
  }
}

// ── Helper pour POST vers le serveur primaire ───────────────────────────
function postToPrimary(pathname, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const opts = {
      hostname: '127.0.0.1',
      port: PRIMARY_PORT,
      path: pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'X-Admin-Key': process.env.ADMIN_KEY || 'streetphare_admin',
      },
    };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { resolve({ raw: data }); }
      });
    });
    req.on('error', (err) => reject(err));
    req.write(payload);
    req.end();
  });
}

// ════════════════════════════════════════════════════════════════════════
//  INTERFACE HTML DU DASHBOARD
// ════════════════════════════════════════════════════════════════════════

function getDashboardHtml() {
  const versionInfo = getVersionInfo();

  const kickList = Array.from(kickedUsers.entries())
    .map(([uuid, data]) => `
      <tr>
        <td class="mono">${uuid.substring(0, 12)}…</td>
        <td>${data.count}</td>
        <td>${data.banned ? '<span class="badge banned">BANNI</span>' : '<span class="badge kicked">Kické</span>'}</td>
        <td>${escapeHtml(data.reason || '-')}</td>
        <td>${new Date(data.lastKick).toLocaleString('fr-BE')}</td>
        <td><button onclick="unban('${uuid}')" class="btn btn-sm btn-success">Lever</button></td>
      </tr>`).join('');

  const bugList = bugReports.slice(-10).reverse()
    .map(r => `
      <tr>
        <td>${new Date(r.submitted_at || r.receivedAt || Date.now()).toLocaleString('fr-BE')}</td>
        <td><span class="badge">${escapeHtml(r.category || 'bug')}</span></td>
        <td>${escapeHtml(r.platform || '?')}</td>
        <td>${escapeHtml(r.title || '')}</td>
        <td style="max-width:300px">${escapeHtml(r.description || '')}</td>
      </tr>`).join('');

  const statsHtml = `
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin-bottom:18px">
      <div class="stat-card">
        <div class="stat-val" id="stat-clients">${serverState.connectedClients}</div>
        <div class="stat-lbl">Clients</div>
      </div>
      <div class="stat-card">
        <div class="stat-val" id="stat-alerts">${serverState.totalAlertsValidated}</div>
        <div class="stat-lbl">Alertes</div>
      </div>
      <div class="stat-card">
        <div class="stat-val" style="color:${serverState.routingEngineEnabled ? '#3fb950' : '#f85149'}" id="stat-routing">${serverState.routingEngineEnabled ? 'ON' : 'OFF'}</div>
        <div class="stat-lbl">Routage</div>
      </div>
      <div class="stat-card">
        <div class="stat-val" style="color:#58a6ff" id="stat-threshold">${serverState.alertValidationThreshold}</div>
        <div class="stat-lbl">Seuil</div>
      </div>
      <div class="stat-card">
        <div class="stat-val" style="color:#d2a8ff" id="stat-kicks">${kickedUsers.size}</div>
        <div class="stat-lbl">Kicks</div>
      </div>
      <div class="stat-card">
        <div class="stat-val" style="color:#f85149" id="stat-bugs">${bugReports.length}</div>
        <div class="stat-lbl">Bugs</div>
      </div>
      <div class="stat-card">
        <div class="stat-val" style="font-size:16px;color:#58a6ff" id="stat-version">${escapeHtml(versionInfo.min_required)}</div>
        <div class="stat-lbl">Min Ver</div>
      </div>
      <div class="stat-card" id="stat-ws-card">
        <div class="stat-val" style="font-size:14px;color:${liveState.connected ? '#3fb950' : '#f85149'}" id="stat-ws">${liveState.connected ? '🔗 LIVE' : '⚫ OFF'}</div>
        <div class="stat-lbl">WebSocket</div>
      </div>
    </div>`;

  // Pré-rendu des événements récents pour le flux temps réel
  const recentEventsHtml = liveState.recentEvents.slice(-30).reverse()
    .map(ev => {
      const time = ev.ts ? ev.ts.slice(11, 19) : '--:--:--';
      const typeLabel = ev.type || '?';
      const summary = ev.data ? JSON.stringify(ev.data).substring(0, 80) : '';
      const typeClass = `ev-${typeLabel.replace(/_/g, '-')}`;
      return `<div class="ev-row ${typeClass}">
        <span class="ev-time">${time}</span>
        <span class="ev-type">${escapeHtml(typeLabel)}</span>
        <span class="ev-summary">${escapeHtml(summary)}</span>
      </div>`;
    }).join('');

  const cliHistoryHtml = cliHistory.slice(-20).reverse()
    .map(h => {
      const time = h.ts ? h.ts.slice(11, 19) : '';
      const isCmd = h.direction === 'command';
      const icon = isCmd ? '▶' : '◀';
      const content = isCmd ? `/${h.command} ${JSON.stringify(h.params || {})}` : JSON.stringify(h.result || h.error || '').substring(0, 100);
      return `<div class="cli-row ${isCmd ? 'cli-cmd' : 'cli-resp'}">
        <span class="cli-time">${time}</span>
        <span class="cli-icon">${icon}</span>
        <span class="cli-text">${escapeHtml(content)}</span>
      </div>`;
    }).join('');

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>StreetPhare — NOC Dashboard v5.0</title>
  <style>
    :root {
      --bg: #0a0e14; --surface: #131820; --border: #1e2a38;
      --primary: #FFB300; --danger: #f85149; --success: #3fb950;
      --text: #c9d1d9; --muted: #6e7681; --accent: #58a6ff;
      --font: 'Segoe UI', -apple-system, system-ui, sans-serif;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: var(--font); font-size: 13px; }
    header { background: var(--surface); border-bottom: 1px solid var(--border);
             padding: 12px 20px; display: flex; align-items: center; gap: 12px; }
    header h1 { font-size: 18px; color: var(--primary); }
    .status-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--success); }
    .topology-badge { display:inline-block; padding:3px 10px; border-radius:12px; font-size:11px; font-weight:600; }
    .topo-primary { background:#1a3a1a; color:#3fb950; }
    .topo-failover { background:#3a1a1a; color:#f85149; }
    .container { max-width: 1500px; margin: 0 auto; padding: 16px 20px; }
    .stat-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
                 padding: 12px 8px; text-align: center; }
    .stat-val { font-size: 24px; font-weight: 700; color: var(--primary); }
    .stat-lbl { font-size: 9px; color: var(--muted); text-transform: uppercase; margin-top: 3px; letter-spacing: .5px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
    @media(max-width:1000px) { .grid { grid-template-columns: 1fr; } }
    .panel { background: var(--surface); border: 1px solid var(--border);
             border-radius: 8px; padding: 16px; }
    .panel h2 { font-size: 12px; color: var(--muted); margin-bottom: 12px;
                text-transform: uppercase; letter-spacing: .6px; display: flex; align-items: center; gap: 6px; }
    .panel-full { grid-column: 1 / -1; }
    input, textarea, select { background: var(--bg); border: 1px solid var(--border);
      color: var(--text); padding: 7px 10px; border-radius: 5px; width: 100%;
      font-size: 12px; margin-bottom: 8px; font-family: var(--font); }
    textarea { resize: vertical; min-height: 60px; }
    .btn { padding: 7px 14px; border-radius: 5px; border: none; cursor: pointer;
           font-size: 11px; font-weight: 600; transition: opacity .15s; font-family: var(--font); }
    .btn:hover { opacity: .85; }
    .btn-primary { background: var(--primary); color: #000; }
    .btn-danger { background: var(--danger); color: #fff; }
    .btn-success { background: var(--success); color: #000; }
    .btn-accent { background: var(--accent); color: #000; }
    .btn-outline { background: transparent; border: 1px solid var(--border); color: var(--text); }
    .btn-sm { padding: 4px 8px; font-size: 10px; }
    .btn-row { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 6px; }
    .btn-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }
    table { width: 100%; border-collapse: collapse; font-size: 11px; }
    th { text-align: left; color: var(--muted); padding: 6px 4px; border-bottom: 1px solid var(--border); }
    td { padding: 6px 4px; border-bottom: 1px solid var(--border); }
    .badge { padding: 1px 6px; border-radius: 10px; font-size: 10px; font-weight: 600; }
    .badge.banned { background: var(--danger); color: #fff; }
    .badge.kicked { background: #e3b341; color: #000; }
    .mono { font-family: 'Cascadia Code', 'Fira Code', monospace; font-size: 11px; }
    /* ── Flux temps réel ───────────────────────────────────── */
    #live-feed { max-height: 350px; overflow-y: auto; font-family: var(--font); font-size: 11px; }
    .ev-row { display: flex; gap: 8px; padding: 4px 6px; border-bottom: 1px solid rgba(255,255,255,.03); align-items: baseline; }
    .ev-time { color: var(--muted); flex-shrink: 0; width: 55px; font-family: monospace; }
    .ev-type { font-weight: 700; flex-shrink: 0; min-width: 90px; font-size: 10px; }
    .ev-summary { color: var(--text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ev-http-request .ev-type { color: #58a6ff; }
    .ev-mesh-message .ev-type { color: #3fb950; }
    .ev-report .ev-type { color: #d2a8ff; }
    .ev-error .ev-type { color: #f85149; }
    .ev-state-change .ev-type { color: #FFB300; }
    .ev-heartbeat .ev-type { color: #6e7681; }
    .ev--system .ev-type { color: #8b949e; }
    /* ── CLI ────────────────────────────────────────────────── */
    #cli-output { max-height: 200px; overflow-y: auto; background: #0a0e14; border: 1px solid var(--border);
                  border-radius: 5px; padding: 8px; font-family: 'Cascadia Code', monospace; font-size: 11px; }
    .cli-row { display: flex; gap: 8px; padding: 2px 0; align-items: baseline; }
    .cli-time { color: var(--muted); flex-shrink: 0; width: 55px; }
    .cli-icon { flex-shrink: 0; width: 12px; }
    .cli-cmd .cli-icon { color: var(--primary); }
    .cli-resp .cli-icon { color: var(--success); }
    .cli-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .cli-cmd .cli-text { color: var(--primary); }
    .cli-resp .cli-text { color: var(--accent); }
    #cli-input { background: #0a0e14; border: 1px solid var(--primary); color: var(--primary);
                 font-family: 'Cascadia Code', monospace; font-size: 12px; padding: 8px 10px; }
    #cli-input::placeholder { color: #3a4a5a; }
    /* ── Simulateurs ────────────────────────────────────────── */
    .sim-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
    @media(max-width:600px) { .sim-grid { grid-template-columns: 1fr; } }
    /* ── Status bar ─────────────────────────────────────────── */
    #status-bar { background: var(--surface); border-top: 1px solid var(--border);
                  padding: 6px 20px; font-size: 11px; color: var(--muted);
                  position: fixed; bottom: 0; left: 0; right: 0; display: flex; gap: 20px; }
  </style>
</head>
<body>
<header>
  <div class="status-dot" id="status-dot"></div>
  <h1>💡 StreetPhare — NOC Dashboard</h1>
  <span class="topology-badge topo-primary" id="topology-badge">🟢 PRINCIPAL ACTIF</span>
  <span style="margin-left:auto;font-size:11px;color:var(--muted)">
    v5.0 — ${new Date().toLocaleString('fr-BE')}
  </span>
</header>

<div class="container">

  <!-- Stats -->
  ${statsHtml}

  <!-- ════ LIGNE 1 : FLUX TEMPS RÉEL + CLI ════ -->
  <div class="grid" style="margin-bottom:14px">
    <!-- Flux temps réel -->
    <div class="panel">
      <h2>📡 Flux Temps Réel (LiveMonitor WebSocket)<span id="ws-indicator" style="font-size:10px;margin-left:auto;color:${liveState.connected ? '#3fb950' : '#f85149'}">${liveState.connected ? '🔗 CONNECTÉ' : '⚫ DÉCONNECTÉ'}</span></h2>
      <div id="live-feed">${recentEventsHtml || '<div style="color:var(--muted);padding:8px">En attente d\'événements…</div>'}</div>
    </div>

    <!-- CLI -->
    <div class="panel">
      <h2>💻 Console de Commandes (CLI)</h2>
      <div id="cli-output">${cliHistoryHtml || '<div style="color:var(--muted);padding:8px">Prêt. Tapez <code style="color:var(--primary)">/help</code> pour la liste des commandes.</div>'}</div>
      <input type="text" id="cli-input" placeholder="/help — Entrez une commande…" autocomplete="off"
             onkeydown="if(event.key==='Enter'){executeCli(this.value);this.value='';}">
      <div class="btn-row" style="margin-top:6px">
        <button class="btn btn-primary btn-sm" onclick="quickCmd('/simulate-alert barrage 48.8566 2.3522')">🚨 Alerte Test</button>
        <button class="btn btn-danger btn-sm" onclick="quickCmd('/force-failover')">⚡ Failover</button>
        <button class="btn btn-accent btn-sm" onclick="quickCmd('/mesh-broadcast Message test P2P')">📡 Mesh Test</button>
        <button class="btn btn-outline btn-sm" onclick="quickCmd('/ttl-purge')">⏱ Purge TTL</button>
        <button class="btn btn-outline btn-sm" onclick="quickCmd('/get-config')">⚙ Config</button>
      </div>
    </div>
  </div>

  <!-- ════ LIGNE 2 : SIMULATEURS + CONTRÔLES ════ -->
  <div class="grid" style="margin-bottom:14px">
    <!-- Simulateurs métier -->
    <div class="panel">
      <h2>🎮 Simulateur de Fonctionnalités Métier</h2>
      <div class="sim-grid">
        <div>
          <label style="font-size:10px;color:var(--muted)">Type Alerte</label>
          <select id="sim-alert-type">
            <option value="barrage">Barrage</option>
            <option value="casseurs">Casseurs</option>
            <option value="danger">Danger</option>
            <option value="policiers">Policiers</option>
            <option value="panic">Panic</option>
          </select>
        </div>
        <div>
          <label style="font-size:10px;color:var(--muted)">Latitude</label>
          <input type="number" id="sim-lat" value="48.8566" step="0.0001">
        </div>
        <div>
          <label style="font-size:10px;color:var(--muted)">Longitude</label>
          <input type="number" id="sim-lon" value="2.3522" step="0.0001">
        </div>
        <div>
          <label style="font-size:10px;color:var(--muted)">Description</label>
          <input type="text" id="sim-desc" placeholder="[Simulation] Alerte test">
        </div>
      </div>
      <div class="btn-grid" style="margin-top:8px">
        <button class="btn btn-primary" onclick="simulateAlert()">🚨 Envoyer Alerte</button>
        <button class="btn btn-danger" onclick="simulateFailover()">⚡ Failover Immédiat</button>
        <button class="btn btn-accent" onclick="simulateMeshBroadcast()">📡 Broadcast P2P Mesh</button>
        <button class="btn btn-outline" onclick="simulateTtlPurge()">⏱ Forcer Purge TTL (24h)</button>
        <button class="btn btn-outline" onclick="simulateLatency()">🐌 Ajouter Latence (+200ms)</button>
        <button class="btn btn-success" onclick="simulateResetLatency()">⚡ Reset Latence</button>
      </div>
      <div id="sim-result" style="margin-top:8px;font-size:11px;color:var(--accent)"></div>
    </div>

    <!-- Contrôle serveur + Config -->
    <div class="panel">
      <h2>🎛️ Contrôle & Configuration</h2>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <div>
          <h3 style="font-size:10px;color:var(--muted);margin-bottom:6px">Processus Serveur</h3>
          <div class="btn-row">
            <button class="btn btn-success btn-sm" onclick="serverAction('start')">▶ Start</button>
            <button class="btn btn-danger btn-sm" onclick="serverAction('stop')">■ Stop</button>
            <button class="btn btn-primary btn-sm" onclick="serverAction('restart')">↺ Restart</button>
          </div>
          <div id="server-log" style="font-size:10px;color:var(--muted);margin-top:4px">En attente…</div>
        </div>
        <div>
          <h3 style="font-size:10px;color:var(--muted);margin-bottom:6px">Kill Switch</h3>
          <input type="text" id="v-latest" placeholder="Dernière version" value="${escapeHtml(versionInfo.latest)}" style="margin-bottom:4px">
          <input type="text" id="v-min" placeholder="Version min requise" value="${escapeHtml(versionInfo.min_required)}" style="margin-bottom:4px">
          <input type="text" id="v-url" placeholder="URL download" value="${escapeHtml(versionInfo.url)}" style="margin-bottom:4px">
          <button class="btn btn-danger btn-sm" onclick="updateVersionInfo()">⚠ Appliquer Kill Switch</button>
        </div>
        <div>
          <h3 style="font-size:10px;color:var(--muted);margin-bottom:6px">Seuil Validation</h3>
          <div style="display:flex;align-items:center;gap:6px">
            <input type="range" id="threshold-slider" min="1" max="10" value="${serverState.alertValidationThreshold}"
                   oninput="document.getElementById('threshold-val').textContent=this.value" style="flex:1;margin:0">
            <span id="threshold-val" style="font-weight:700;color:var(--primary);min-width:20px">${serverState.alertValidationThreshold}</span>
            <button class="btn btn-primary btn-sm" onclick="setThreshold()">Appliquer</button>
          </div>
        </div>
        <div>
          <h3 style="font-size:10px;color:var(--muted);margin-bottom:6px">Master Passphrase (test)</h3>
          <input type="text" id="pwd-passphrase" value="${escapeHtml(serverState.masterPassphrase)}" style="margin-bottom:4px">
          <button class="btn btn-primary btn-sm" onclick="setPassphrase()">🔐 Appliquer</button>
        </div>
      </div>
    </div>
  </div>

  <!-- ════ LIGNE 3 : QR + ÉVÉNEMENTS + BROADCAST + KICK ════ -->
  <div class="grid" style="margin-bottom:14px">
    <!-- QR Code -->
    <div class="panel">
      <h2>📱 Générateur QR Code</h2>
      <input type="text" id="qr-event-title" placeholder="Titre événement">
      <input type="text" id="qr-event-code" placeholder="Code accès (ex: FLEURUS2026)">
      <button class="btn btn-primary" onclick="generateQR()">Générer QR</button>
      <div id="qr-preview" style="margin-top:8px;text-align:center"></div>
    </div>
    <!-- Gestion événements -->
    <div class="panel">
      <h2>📍 Événements Fleurus</h2>
      <input type="text" id="ev-title" placeholder="Titre événement">
      <input type="datetime-local" id="ev-time">
      <div class="btn-row">
        <button class="btn btn-primary" onclick="saveEvent()">💾 Enregistrer</button>
        <button class="btn btn-outline" onclick="loadEventsList()">🔄 Actualiser</button>
      </div>
      <div id="events-list" style="margin-top:8px;font-size:11px"></div>
    </div>
    <!-- Broadcast -->
    <div class="panel">
      <h2>📡 Broadcast Réseau</h2>
      <input type="text" id="bc-title" placeholder="Titre">
      <textarea id="bc-message" placeholder="Message…"></textarea>
      <button class="btn btn-primary" onclick="sendBroadcast()">📤 Envoyer</button>
      <div id="broadcast-log" style="font-size:10px;color:var(--muted);margin-top:6px;max-height:60px;overflow-y:auto"></div>
    </div>
    <!-- Kick / Ban -->
    <div class="panel">
      <h2>🚫 Kick & Bannissement</h2>
      <input type="text" id="kick-uuid" placeholder="UUID éphémère">
      <input type="text" id="kick-reason" placeholder="Raison">
      <div class="btn-row">
        <button class="btn btn-danger" onclick="kickUserAction()">🦵 Kicker</button>
        <button class="btn btn-outline" onclick="banUserAction()">⛔ Bannir</button>
      </div>
      <table style="margin-top:8px">
        <thead><tr><th>UUID</th><th>Kicks</th><th>Statut</th><th>Action</th></tr></thead>
        <tbody id="kick-table">${kickList || '<tr><td colspan="4" style="color:var(--muted)">Aucun</td></tr>'}</tbody>
      </table>
    </div>
  </div>

  <!-- ════ LIGNE 4 : RAPPORTS DE BUGS ════ -->
  <div class="panel" style="margin-bottom:14px">
    <h2>🐛 Rapports de Bugs (${bugReports.length})</h2>
    <table>
      <thead><tr><th>Date</th><th>Cat.</th><th>Plateforme</th><th>Titre</th><th>Description</th></tr></thead>
      <tbody id="bug-table">${bugList || '<tr><td colspan="5" style="color:var(--muted)">Aucun rapport.</td></tr>'}</tbody>
    </table>
  </div>

  <!-- ════ LIENS SANDBOX ════ -->
  <div class="panel" style="text-align:center;margin-bottom:40px">
    <a href="/sandbox" target="_blank" class="btn btn-accent btn-sm" style="text-decoration:none">🔗 Ouvrir la Sandbox complète</a>
    <span style="margin:0 10px;color:var(--muted)">|</span>
    <span style="font-size:11px;color:var(--muted)">Serveur Primaire : <a href="${PRIMARY_URL}/status" target="_blank" style="color:var(--accent)">${PRIMARY_URL}/status</a></span>
  </div>

</div>

<div id="status-bar">
  <span>StreetPhare NOC v5.0</span>
  <span>Port Admin: ${PORT}</span>
  <span>Kicks: <span id="kick-count">${kickedUsers.size}</span></span>
  <span>Bugs: <span id="bug-count">${bugReports.length}</span></span>
  <span>LiveMonitor: <span id="ws-status">${liveState.connected ? '🟢' : '🔴'}</span></span>
  <span style="margin-left:auto" id="clock"></span>
</div>

<script>
// ════════════════════════════════════════════════════════════════════════
//  HELPERS
// ════════════════════════════════════════════════════════════════════════
async function api(endpoint, method = 'GET', body = null) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch('/api' + endpoint, opts);
  return r.json();
}

function showResult(id, data) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  el.style.display = 'block';
}

// ════════════════════════════════════════════════════════════════════════
//  SIMULATEURS MÉTIER
// ════════════════════════════════════════════════════════════════════════
async function simulateAlert() {
  const type = document.getElementById('sim-alert-type').value;
  const lat = parseFloat(document.getElementById('sim-lat').value);
  const lon = parseFloat(document.getElementById('sim-lon').value);
  const desc = document.getElementById('sim-desc').value || '[Simulation] Alerte test';
  const res = await api('/simulate-alert', 'POST', { type, lat, lon, description: desc });
  showResult('sim-result', res);
}

async function simulateFailover() {
  const res = await api('/simulate-failover', 'POST', { reason: 'Failover simulé depuis NOC Dashboard' });
  showResult('sim-result', res);
  document.getElementById('topology-badge').textContent = '🔴 FAILOVER EN COURS';
  document.getElementById('topology-badge').className = 'topology-badge topo-failover';
}

async function simulateMeshBroadcast() {
  const res = await api('/simulate-mesh-broadcast', 'POST', {
    title: 'Test NOC',
    message: 'Message de test P2P Mesh depuis le Dashboard NOC v5.0',
  });
  showResult('sim-result', res);
}

async function simulateTtlPurge() {
  const res = await api('/simulate-ttl-purge', 'POST', {});
  showResult('sim-result', res);
}

async function simulateLatency() {
  const res = await api('/set-latency', 'POST', { ms: (serverState.simulatedLatencyMs || 0) + 200 });
  showResult('sim-result', res);
}

async function simulateResetLatency() {
  const res = await api('/set-latency', 'POST', { ms: 0 });
  showResult('sim-result', res);
}

// ════════════════════════════════════════════════════════════════════════
//  CLI
// ════════════════════════════════════════════════════════════════════════
async function executeCli(input) {
  if (!input.trim()) return;
  const res = await api('/cli-execute', 'POST', { command: input });
  // Rafraîchir la page pour voir le résultat (ou recharger via AJAX)
  refreshCliOutput();
}

async function quickCmd(cmd) {
  document.getElementById('cli-input').value = cmd;
  await executeCli(cmd);
  document.getElementById('cli-input').value = '';
}

async function refreshCliOutput() {
  try {
    const r = await api('/cli-history');
    const output = document.getElementById('cli-output');
    if (!r.history || !r.history.length) {
      output.innerHTML = '<div style="color:var(--muted);padding:8px">Prêt. Tapez <code style="color:var(--primary)">/help</code>.</div>';
      return;
    }
    output.innerHTML = r.history.slice(-20).reverse().map(h => {
      const time = h.ts ? h.ts.slice(11,19) : '';
      const isCmd = h.direction === 'command';
      const icon = isCmd ? '▶' : '◀';
      const content = isCmd ? '/' + h.command + ' ' + JSON.stringify(h.params || {}) : JSON.stringify(h.result || h.error || '');
      return '<div class="cli-row ' + (isCmd ? 'cli-cmd' : 'cli-resp') + '">' +
        '<span class="cli-time">' + time + '</span>' +
        '<span class="cli-icon">' + icon + '</span>' +
        '<span class="cli-text">' + content.substring(0, 120) + '</span>' +
      '</div>';
    }).join('');
  } catch(_) {}
}

// ════════════════════════════════════════════════════════════════════════
//  CONTRÔLE SERVEUR
// ════════════════════════════════════════════════════════════════════════
async function serverAction(action) {
  const log = document.getElementById('server-log');
  log.textContent = 'Exécution : ' + action + '…';
  try {
    const res = await api('/server/' + action, 'POST');
    log.textContent = res.message || JSON.stringify(res);
  } catch(e) { log.textContent = 'Erreur : ' + e.message; }
}

async function setThreshold() {
  const val = document.getElementById('threshold-slider').value;
  await api('/threshold', 'POST', { threshold: parseInt(val) });
  document.getElementById('stat-threshold').textContent = val;
}

async function setPassphrase() {
  const val = document.getElementById('pwd-passphrase').value;
  await api('/set-passphrase', 'POST', { passphrase: val });
  alert('Passphrase mise à jour');
}

async function updateVersionInfo() {
  await api('/version-config', 'POST', {
    latest: document.getElementById('v-latest').value,
    min_required: document.getElementById('v-min').value,
    url: document.getElementById('v-url').value,
  });
  alert('Kill Switch appliqué');
}

// ════════════════════════════════════════════════════════════════════════
//  AUTRES FONCTIONS
// ════════════════════════════════════════════════════════════════════════
function generateQR() {
  const title = document.getElementById('qr-event-title').value;
  const code = document.getElementById('qr-event-code').value;
  // ── Construction du payload conforme au contrat EventModel.fromJson ──────
  // Champs obligatoires (qr_scanner_screen.dart:67) :
  //   code, title, startAt, visibleAt, route, destLat, destLng
  // Format des dates : ISO 8601 UTC (ex: "2026-07-14T08:00:00.000Z")
  const now = new Date();
  const startAt = new Date(now.getTime() + 3600000).toISOString();       // +1h
  const visibleAt = new Date(now.getTime() - 300000).toISOString();      // -5min (déjà visible)
  // Coordonnées par défaut : Place Albert 1er, Fleurus (6220), Belgique
  const destLat = 50.4762;
  const destLng = 4.5422;
  // Route GeoJSON par défaut : boucle piétonne autour du centre de Fleurus
  const route = '[[4.5422,50.4762],[4.5440,50.4780],[4.5468,50.4790],' +
                '[4.5510,50.4785],[4.5550,50.4760],[4.5535,50.4730],' +
                '[4.5500,50.4710],[4.5450,50.4705],[4.5390,50.4720],' +
                '[4.5370,50.4750],[4.5390,50.4762],[4.5422,50.4762]]';
  const payload = JSON.stringify({
    code: code || 'FLEURUS-' + Date.now().toString(36).toUpperCase(),
    title: title || 'Événement StreetPhare',
    startAt: startAt,
    visibleAt: visibleAt,
    route: route,
    destLat: destLat,
    destLng: destLng,
    // Champs optionnels (valeurs par défaut vides acceptées par fromJson)
    waypoints: [],
    pois: [],
    careCenters: [],
    exitPoints: [],
    safeZones: [],
  });
  const encoded = encodeURIComponent(payload);
  document.getElementById('qr-preview').innerHTML = '<img src="https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=' + encoded + '" width="180" height="180" alt="QR">';
}

async function saveEvent() {
  await api('/events', 'POST', {
    title: document.getElementById('ev-title').value,
    eventTime: document.getElementById('ev-time').value,
  });
  loadEventsList();
}

async function loadEventsList() {
  const res = await api('/events');
  const el = document.getElementById('events-list');
  el.innerHTML = (res.events || []).map((ev, i) =>
    '<div style="padding:4px 0;border-bottom:1px solid var(--border);display:flex;justify-content:space-between">' +
      '<span>' + ev.title + ' — ' + (ev.eventTime || '?') + '</span>' +
      '<button class="btn btn-sm btn-danger" onclick="deleteEvent(' + i + ')">🗑</button>' +
    '</div>').join('') || 'Aucun événement.';
}

async function deleteEvent(i) {
  await api('/events/' + i, 'DELETE');
  loadEventsList();
}

async function sendBroadcast() {
  const res = await api('/broadcast', 'POST', {
    type: 'broadcast',
    title: document.getElementById('bc-title').value,
    message: document.getElementById('bc-message').value,
  });
  document.getElementById('broadcast-log').textContent = JSON.stringify(res);
}

async function kickUserAction() {
  await api('/kick', 'POST', {
    uuid: document.getElementById('kick-uuid').value,
    reason: document.getElementById('kick-reason').value,
  });
  location.reload();
}

async function banUserAction() {
  await api('/ban', 'POST', {
    uuid: document.getElementById('kick-uuid').value,
    reason: document.getElementById('kick-reason').value,
  });
  location.reload();
}

async function unban(uuid) {
  await api('/unban', 'POST', { uuid });
  location.reload();
}

loadEventsList();

// ════════════════════════════════════════════════════════════════════════
//  MISE À JOUR TEMPS RÉEL (polling léger en fallback)
// ════════════════════════════════════════════════════════════════════════
setInterval(refreshCliOutput, 3000);

// Horloge
function updateClock() {
  document.getElementById('clock').textContent = new Date().toLocaleTimeString('fr-BE');
}
setInterval(updateClock, 1000);
updateClock();
</script>
</body>
</html>`;
}

// ════════════════════════════════════════════════════════════════════════
//  SERVEUR HTTP
// ════════════════════════════════════════════════════════════════════════

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

  // POST /api/cli-execute — Exécute une commande CLI
  if (req.method === 'POST' && pathname === '/api/cli-execute') {
    bodyPromise().then(async (body) => {
      const input = body.command || '';
      let result;
      try {
        // Si c'est une promesse, on attend
        const maybePromise = executeCliCommand(input);
        if (maybePromise && typeof maybePromise.then === 'function') {
          result = await maybePromise;
        } else {
          result = maybePromise;
        }
      } catch (e) {
        result = { error: e.message };
      }
      // Stocker la réponse dans l'historique
      cliHistory.push({
        ts: new Date().toISOString(),
        direction: 'response',
        command: input.trim().slice(1).split(/\s+/)[0] || '?',
        result,
      });
      if (cliHistory.length > MAX_CLI_HISTORY) cliHistory.shift();
      json(200, { ok: true, result });
    });
    return;
  }

  // GET /api/cli-history
  if (req.method === 'GET' && pathname === '/api/cli-history') {
    json(200, { history: cliHistory });
    return;
  }

  // ── API Simulateurs ─────────────────────────────────────────────

  // POST /api/simulate-alert
  if (req.method === 'POST' && pathname === '/api/simulate-alert') {
    bodyPromise().then(async (body) => {
      try {
        const r = await postToPrimary('/v1/reports', {
          id: `sim_${Date.now()}`,
          type: body.type || 'barrage',
          lat: parseFloat(body.lat) || 48.8566,
          lon: parseFloat(body.lon) || 2.3522,
          reporter_id: 'noc_dashboard',
          description: body.description || '[NOC] Alerte simulée',
        });
        json(200, { ok: true, message: 'Alerte envoyée au serveur primaire', result: r });
      } catch (e) {
        json(500, { ok: false, error: e.message });
      }
    });
    return;
  }

  // POST /api/simulate-failover
  if (req.method === 'POST' && pathname === '/api/simulate-failover') {
    bodyPromise().then(async (body) => {
      try {
        const r = await postToPrimary('/_debug/demote', {
          reason: body.reason || 'Failover simulé depuis NOC Dashboard',
        });
        json(200, { ok: true, message: 'Failover déclenché. Le serveur primaire va s\'arrêter.', result: r });
      } catch (e) {
        json(200, { ok: true, message: 'Failover envoyé (le serveur primaire s\'est peut-être déjà arrêté)', error: e.message });
      }
    });
    return;
  }

  // POST /api/simulate-mesh-broadcast
  if (req.method === 'POST' && pathname === '/api/simulate-mesh-broadcast') {
    bodyPromise().then(async (body) => {
      try {
        const r = await postToPrimary('/api/admin-broadcast', {
          type: 'broadcast',
          title: body.title || 'NOC Dashboard',
          message: body.message || 'Message de test P2P Mesh',
        });
        json(200, { ok: true, message: 'Broadcast envoyé au réseau mesh', result: r });
      } catch (e) {
        json(200, { ok: true, message: 'Broadcast envoyé', warning: e.message });
      }
    });
    return;
  }

  // POST /api/simulate-ttl-purge
  if (req.method === 'POST' && pathname === '/api/simulate-ttl-purge') {
    json(200, {
      ok: true,
      message: 'Purge TTL simulée. Les signalements avec TTL <= 0 seront expirés. La purge réelle est gérée par reports_store.',
    });
    return;
  }

  // POST /api/set-latency
  if (req.method === 'POST' && pathname === '/api/set-latency') {
    bodyPromise().then((body) => {
      serverState.simulatedLatencyMs = Math.max(0, Math.min(5000, parseInt(body.ms) || 0));
      json(200, { ok: true, latencyMs: serverState.simulatedLatencyMs });
    });
    return;
  }

  // POST /api/set-passphrase
  if (req.method === 'POST' && pathname === '/api/set-passphrase') {
    bodyPromise().then((body) => {
      serverState.masterPassphrase = body.passphrase || 'streetphare-dev-key-CHANGE_ME_IN_PROD';
      json(200, { ok: true, message: 'Passphrase mise à jour', length: serverState.masterPassphrase.length });
    });
    return;
  }

  // ── API existantes (compatibles v3/v4) ──────────────────────────

  // POST /api/bug-report
  if (req.method === 'POST' && pathname === '/api/bug-report') {
    bodyPromise().then(body => {
      bugReports.push({ ...body, receivedAt: new Date().toISOString() });
      saveData();
      json(201, { status: 'ok', message: 'Rapport reçu' });
    });
    return;
  }

  // POST /api/server/start|stop|restart
  if (req.method === 'POST' && pathname.startsWith('/api/server/')) {
    const action = pathname.split('/')[3];
    const serverScript = path.join(__dirname, 'server_primary_v2.js');
    if (action === 'start') {
      if (serverProcess) { json(200, { message: 'Serveur déjà en cours.' }); return; }
      try {
        serverProcess = spawn('node', [serverScript], { stdio: 'inherit', detached: false });
        serverProcess.on('exit', () => { serverProcess = null; });
        json(200, { message: `Serveur démarré (PID ${serverProcess.pid})` });
      } catch (e) { json(500, { message: `Erreur: ${e.message}` }); }
    } else if (action === 'stop') {
      if (!serverProcess) { json(200, { message: 'Aucun serveur en cours.' }); return; }
      try { serverProcess.kill('SIGTERM'); serverProcess = null; json(200, { message: 'Serveur arrêté.' }); }
      catch (e) { json(500, { message: `Erreur: ${e.message}` }); }
    } else if (action === 'restart') {
      if (serverProcess) { try { serverProcess.kill('SIGTERM'); } catch (_) {} serverProcess = null; }
      try {
        serverProcess = spawn('node', [serverScript], { stdio: 'inherit', detached: false });
        serverProcess.on('exit', () => { serverProcess = null; });
        json(200, { message: `Serveur redémarré (PID ${serverProcess.pid})` });
      } catch (e) { json(500, { message: `Erreur: ${e.message}` }); }
    } else {
      json(404, { message: 'Action inconnue' });
    }
    return;
  }

  // GET /api/events
  if (req.method === 'GET' && pathname === '/api/events') {
    json(200, { events: loadEvents() });
    return;
  }

  // POST /api/events
  if (req.method === 'POST' && pathname === '/api/events') {
    bodyPromise().then(body => {
      const events = loadEvents();
      events.push({ ...body, id: crypto.randomUUID(), createdAt: new Date().toISOString() });
      saveEvents(events);
      json(201, { message: 'Événement créé' });
    });
    return;
  }

  // DELETE /api/events/:index
  if (req.method === 'DELETE' && pathname.startsWith('/api/events/')) {
    const idx = parseInt(pathname.split('/')[3]);
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

  // POST /api/broadcast
  if (req.method === 'POST' && pathname === '/api/broadcast') {
    bodyPromise().then(body => {
      broadcastLog.push({ ...body, sentAt: new Date().toISOString() });
      saveData();
      const payload = JSON.stringify({
        event: 'admin_broadcast', type: body.type || 'broadcast',
        title: body.title || 'Message Admin', message: body.message,
        timestamp: new Date().toISOString(),
      });
      const opts = {
        hostname: '127.0.0.1', port: PRIMARY_PORT,
        path: '/api/admin-broadcast', method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
          'X-Admin-Key': process.env.ADMIN_KEY || 'streetphare_admin',
        },
      };
      const req2 = http.request(opts, r => console.log(`[Admin] Broadcast relayé → ${r.statusCode}`));
      req2.on('error', err => console.error('[Admin] Erreur relay broadcast:', err.message));
      req2.write(payload);
      req2.end();
      json(200, { message: `Broadcast envoyé` });
    });
    return;
  }

  // POST /api/kick
  if (req.method === 'POST' && pathname === '/api/kick') {
    bodyPromise().then(body => {
      const result = kickUser(body.uuid, body.reason);
      json(200, { message: result.autoLockTriggered ? '⚠️ AUTO-LOCK' : 'Kické', kicks: result.count });
    });
    return;
  }

  // POST /api/ban
  if (req.method === 'POST' && pathname === '/api/ban') {
    bodyPromise().then(body => {
      const existing = kickedUsers.get(body.uuid) || { count: 0, firstKick: Date.now() };
      existing.banned = true;
      existing.reason = body.reason || 'Bannissement manuel';
      existing.lastKick = Date.now();
      kickedUsers.set(body.uuid, existing);
      saveData();
      json(200, { message: `Banni` });
    });
    return;
  }

  // POST /api/unban
  if (req.method === 'POST' && pathname === '/api/unban') {
    bodyPromise().then(body => {
      kickedUsers.delete(body.uuid);
      saveData();
      json(200, { message: 'Débanni' });
    });
    return;
  }

  // DELETE /api/bug-reports/clear
  if (req.method === 'DELETE' && pathname === '/api/bug-reports/clear') {
    bugReports = [];
    saveData();
    json(200, { message: 'Rapports effacés' });
    return;
  }

  // POST /api/routing-toggle
  if (req.method === 'POST' && pathname === '/api/routing-toggle') {
    bodyPromise().then(body => {
      serverState.routingEngineEnabled = !!body.enabled;
      json(200, { enabled: serverState.routingEngineEnabled });
    });
    return;
  }

  // POST /api/threshold
  if (req.method === 'POST' && pathname === '/api/threshold') {
    bodyPromise().then(body => {
      serverState.alertValidationThreshold = Math.max(1, Math.min(10, parseInt(body.threshold) || 3));
      json(200, { threshold: serverState.alertValidationThreshold });
    });
    return;
  }

  // POST /api/version-config
  if (req.method === 'POST' && pathname === '/api/version-config') {
    bodyPromise().then(body => {
      if (_reportsStore) _reportsStore.setVersionInfo(body);
      json(200, { status: 'ok' });
    });
    return;
  }

  // GET /api/server-state
  if (req.method === 'GET' && pathname === '/api/server-state') {
    json(200, {
      ...serverState,
      ...getVersionInfo(),
      kickedUsersCount: kickedUsers.size,
      bugReportsCount: bugReports.length,
      liveMonitorConnected: liveState.connected,
      uptime: process.uptime(),
    });
    return;
  }

  // Sandbox
  if (pathname.startsWith('/sandbox')) {
    const app = getSandboxApp();
    if (app) {
      app(req, res);
    } else {
      res.writeHead(503, { 'Content-Type': 'text/plain' });
      res.end('Sandbox indisponible (npm install express requis).');
    }
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

// ── Démarrage ───────────────────────────────────────────────────────────
// Liaison à 0.0.0.0 pour accepter les connexions des appareils du réseau
// local (tablettes, téléphones, autres postes de développement).
const LISTEN_HOST = '0.0.0.0';
server.listen(PORT, LISTEN_HOST, () => {
  // Récupération de l'adresse IP locale pour l'afficher dans les logs
  const os = require('os');
  const localIps = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        localIps.push(net.address);
      }
    }
  }

  console.log(`\n🌐 [NOC Dashboard] StreetPhare v5.0`);
  console.log(`   URL locale : http://localhost:${PORT}`);
  if (localIps.length > 0) {
    console.log(`   URL réseau : http://${localIps[0]}:${PORT}`);
    console.log(`   Adresses   : ${localIps.join(', ')}`);
  }
  console.log(`   LiveMonitor : ${LIVE_MONITOR_WS}`);
  console.log(`   Fonctionnalités : Flux temps réel | CLI | Simulateurs | QR | Kick/Ban | Kill Switch\n`);

  // Connexion au LiveMonitor
  connectToLiveMonitor();
});

module.exports = { kickUser };