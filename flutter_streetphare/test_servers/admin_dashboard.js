// test_servers/admin_dashboard.js
//
// StreetPhare — Interface Web d'Administration
// =============================================
//
// Dashboard HTML/JS accessible à distance pour :
//   1. Visualiser l'état en temps réel des serveurs (Principal / Backup).
//   2. Configurer les événements (créer, modifier, supprimer).
//   3. Voir les signalements actifs et leur statut de votes.
//   4. Simuler une panne du serveur principal (test failover).
//   5. Accéder aux statistiques réseau et panic queue.
//
// Démarrage :
//   node admin_dashboard.js
//   → http://localhost:4000/admin
//
// Intégré au start_servers_v2.js (PORT 4000 par défaut).

'use strict';

const express = require('express');
const http    = require('http');
const path    = require('path');

const ADMIN_PORT = parseInt(process.env.ADMIN_PORT || '4000', 10);
const PRIMARY_URL   = process.env.PRIMARY_URL   || 'http://localhost:3000';
const SECONDARY_URL = process.env.SECONDARY_URL || 'http://localhost:3001';

const app = express();
app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, 'admin_static')));

function log(...args) {
  console.log(`[${new Date().toISOString()}][admin:${ADMIN_PORT}]`, ...args);
}

// ── Helper : requête HTTP interne vers les serveurs StreetPhare ──────────────
function fetchInternal(url, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      port:     urlObj.port || 80,
      path:     urlObj.pathname + urlObj.search,
      method,
      headers: { 'Content-Type': 'application/json' },
      timeout: 3000,
    };
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error',   reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ============================================================================
//  API ADMIN
// ============================================================================

// GET /admin/api/status — état des deux serveurs
app.get('/admin/api/status', async (_req, res) => {
  const [primary, secondary] = await Promise.allSettled([
    fetchInternal(`${PRIMARY_URL}/status`),
    fetchInternal(`${SECONDARY_URL}/status`),
  ]);
  res.json({
    primary:   primary.status   === 'fulfilled' ? primary.value   : { error: primary.reason?.message },
    secondary: secondary.status === 'fulfilled' ? secondary.value : { error: secondary.reason?.message },
    admin_time: new Date().toISOString(),
  });
});

// GET /admin/api/reports — signalements actifs du serveur principal
app.get('/admin/api/reports', async (_req, res) => {
  try {
    const r = await fetchInternal(`${PRIMARY_URL}/v1/reports`);
    res.json(r.body);
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
});

// GET /admin/api/reports/stats — statistiques
app.get('/admin/api/reports/stats', async (_req, res) => {
  try {
    const r = await fetchInternal(`${PRIMARY_URL}/v1/reports/stats`);
    res.json(r.body);
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
});

// GET /admin/api/events — liste des événements
app.get('/admin/api/events', async (_req, res) => {
  try {
    const r = await fetchInternal(`${PRIMARY_URL}/v1/events`);
    res.json(r.body);
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
});

// ── KILL SWITCH : arrêt logiciel du serveur principal ───────────────────────
//
// POST /admin/api/kill-primary
//
// Envoie une demande de démission (/_debug/demote) au serveur principal.
// Cela simule une panne et déclenche le failover automatique vers
// le serveur de backup (Port 3001).
//
// ⚠️  ATTENTION : cette action ARRÊTE le processus Node.js du serveur
//     principal. À n'utiliser que dans un environnement de test.
//
app.post('/admin/api/kill-primary', async (req, res) => {
  const reason = (req.body && req.body.reason) || 'Kill depuis Admin Dashboard';
  log(`⚠️  KILL PRINCIPAL demandé : ${reason}`);
  try {
    const r = await fetchInternal(
      `${PRIMARY_URL}/_debug/demote`,
      'POST',
      { reason },
    );
    log(`   → Serveur principal a répondu : ${JSON.stringify(r.body)}`);
    res.json({
      ok: true,
      message: `Serveur principal (${PRIMARY_URL}) en cours d'arrêt.`,
      demote_response: r.body,
    });
  } catch (e) {
    // Si le serveur ne répond plus, il est peut-être déjà arrêté.
    log(`   → Aucune réponse (déjà arrêté ?) : ${e.message}`);
    res.json({
      ok: true,
      message: `Serveur principal ne répond plus (peut-être déjà arrêté).`,
      error: e.message,
    });
  }
});

// ── RESTART : redémarre le serveur de backup ─────────────────────────────────
app.get('/admin/api/secondary/health', async (_req, res) => {
  try {
    const r = await fetchInternal(`${SECONDARY_URL}/healthz`);
    res.json({ online: r.status === 200, body: r.body });
  } catch (e) {
    res.json({ online: false, error: e.message });
  }
});

// ── DEBUG STORE ──────────────────────────────────────────────────────────────
app.get('/admin/api/debug/primary', async (_req, res) => {
  try {
    const r = await fetchInternal(`${PRIMARY_URL}/_debug/reports`);
    res.json(r.body);
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
});

// ============================================================================
//  INTERFACE HTML (Dashboard principal)
// ============================================================================

app.get('/admin', (_req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(ADMIN_HTML);
});

// Redirect racine → /admin
app.get('/', (_req, res) => res.redirect('/admin'));

// ============================================================================
//  HTML INLINE DU DASHBOARD
// ============================================================================

const ADMIN_HTML = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>StreetPhare — Admin Dashboard</title>
<style>
  :root {
    --primary: #FFB300;
    --danger: #E53935;
    --surface: #1E1E1E;
    --card: #2A2A2A;
    --text: #EEEEEE;
    --text2: #999;
    --green: #4CAF50;
    --blue: #2196F3;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--surface); color: var(--text); font-family: 'Segoe UI', sans-serif; font-size: 14px; }
  header { background: var(--card); padding: 14px 24px; display: flex; align-items: center; gap: 12px; border-bottom: 2px solid var(--primary); }
  header h1 { font-size: 20px; color: var(--primary); }
  header span { color: var(--text2); font-size: 12px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 16px; padding: 20px; }
  .card { background: var(--card); border-radius: 12px; padding: 18px; border: 1px solid #333; }
  .card h2 { font-size: 15px; margin-bottom: 12px; color: var(--primary); display: flex; align-items: center; gap: 8px; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: bold; }
  .badge.online { background: #1B5E20; color: #81C784; }
  .badge.offline { background: #B71C1C; color: #EF9A9A; }
  .badge.warn { background: #E65100; color: #FFCC80; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th { text-align: left; color: var(--text2); padding: 4px 8px; border-bottom: 1px solid #444; }
  td { padding: 5px 8px; border-bottom: 1px solid #333; vertical-align: top; }
  td.val { color: var(--primary); font-weight: 600; }
  .btn { display: inline-block; padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer; font-size: 13px; font-weight: 600; margin: 4px 2px; transition: opacity .2s; }
  .btn:hover { opacity: .85; }
  .btn-primary { background: var(--primary); color: #000; }
  .btn-danger  { background: var(--danger);  color: #fff; }
  .btn-blue    { background: var(--blue);    color: #fff; }
  .btn-ghost   { background: #444; color: var(--text); }
  .log { background: #111; border-radius: 8px; padding: 10px; font-family: monospace; font-size: 11px; max-height: 200px; overflow-y: auto; color: #a8d08d; white-space: pre-wrap; }
  .stat-row { display: flex; justify-content: space-between; padding: 4px 0; border-bottom: 1px solid #333; }
  .stat-label { color: var(--text2); }
  .stat-val   { color: var(--primary); font-weight: 600; }
  .kill-section { border: 2px solid var(--danger); border-radius: 12px; padding: 18px; margin-top: 0; }
  .kill-section h2 { color: var(--danger); }
  .section-title { font-size: 12px; color: var(--text2); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; }
  #toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); background: #333; color: #fff; padding: 10px 20px; border-radius: 8px; font-size: 13px; display: none; z-index: 999; }
</style>
</head>
<body>

<header>
  <span style="font-size:24px">🔦</span>
  <h1>StreetPhare Admin</h1>
  <span id="clock"></span>
  <span style="flex:1"></span>
  <button class="btn btn-primary" onclick="refreshAll()">↻ Actualiser</button>
  <button class="btn btn-ghost" onclick="toggleAutoRefresh()" id="autoBtn">▶ Auto (5s)</button>
</header>

<div class="grid">

  <!-- Statut Serveurs -->
  <div class="card">
    <h2>🖥️ Serveurs <span id="badge-primary" class="badge warn">…</span></h2>
    <div class="section-title">Serveur Principal (Port 3000)</div>
    <table id="tbl-primary"></table>
    <br>
    <div class="section-title">Serveur Backup (Port 3001)</div>
    <table id="tbl-secondary"></table>
    <br>
    <button class="btn btn-blue" onclick="loadStatus()">Rafraîchir statut</button>
  </div>

  <!-- Signalements -->
  <div class="card">
    <h2>📍 Signalements actifs</h2>
    <div id="reports-stats" style="margin-bottom:10px;"></div>
    <table id="tbl-reports">
      <thead><tr><th>Type</th><th>Votes</th><th>Dist. ?</th><th>Expire</th></tr></thead>
      <tbody></tbody>
    </table>
    <br>
    <button class="btn btn-ghost" onclick="loadReports()">↻ Rafraîchir</button>
  </div>

  <!-- Événements -->
  <div class="card">
    <h2>📅 Événements</h2>
    <table id="tbl-events">
      <thead><tr><th>ID</th><th>Titre</th><th>Statut</th></tr></thead>
      <tbody></tbody>
    </table>
    <br>
    <button class="btn btn-ghost" onclick="loadEvents()">↻ Rafraîchir</button>
  </div>

  <!-- Kill Switch -->
  <div class="card kill-section">
    <h2>⚠️ Simulation de Panne</h2>
    <p style="color:var(--text2); font-size:12px; margin-bottom:12px;">
      Arrête logiquement le serveur principal (Port 3000) pour valider
      instantanément le basculement automatique vers le backup (Port 3001).
    </p>
    <div style="margin-bottom:12px;">
      <input id="kill-reason" type="text" value="Test failover depuis Admin Dashboard"
        style="width:100%; padding:8px; background:#111; color:#fff; border:1px solid #555; border-radius:6px; font-size:12px;">
    </div>
    <button class="btn btn-danger" onclick="killPrimary()">
      🔴 KILL Serveur Principal
    </button>
    <div id="kill-result" style="margin-top:10px; font-size:12px; color:var(--text2);"></div>
  </div>

  <!-- Journal des actions -->
  <div class="card" style="grid-column: 1 / -1;">
    <h2>📋 Journal des actions</h2>
    <div class="log" id="log-box">Prêt. En attente d'actions…
</div>
  </div>

</div>

<div id="toast"></div>

<script>
  let autoRefreshInterval = null;
  let autoActive = false;

  function addLog(msg) {
    const box = document.getElementById('log-box');
    const ts = new Date().toLocaleTimeString('fr-FR');
    box.textContent += '[' + ts + '] ' + msg + '\\n';
    box.scrollTop = box.scrollHeight;
  }

  function toast(msg, color = '#333') {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.style.background = color;
    t.style.display = 'block';
    setTimeout(() => t.style.display = 'none', 3000);
  }

  // ── Horloge ──────────────────────────────────────────────────────────────
  function updateClock() {
    document.getElementById('clock').textContent =
      new Date().toLocaleTimeString('fr-FR');
  }
  setInterval(updateClock, 1000);
  updateClock();

  // ── Statut serveurs ───────────────────────────────────────────────────────
  async function loadStatus() {
    try {
      const r = await fetch('/admin/api/status');
      const d = await r.json();
      renderServer('tbl-primary',   d.primary,   'badge-primary');
      renderServer('tbl-secondary', d.secondary, null);
    } catch (e) {
      addLog('Erreur chargement statut : ' + e.message);
    }
  }

  function renderServer(tableId, data, badgeId) {
    const tbl = document.getElementById(tableId);
    const isOnline = data && !data.error;
    if (badgeId) {
      const badge = document.getElementById(badgeId);
      badge.className = 'badge ' + (isOnline ? 'online' : 'offline');
      badge.textContent = isOnline ? 'En ligne' : 'Hors ligne';
    }
    if (data && data.error) {
      tbl.innerHTML = '<tr><td style="color:#EF9A9A">Hors ligne : ' + data.error + '</td></tr>';
      return;
    }
    const body = data.body || data;
    const rows = Object.entries(body || {}).map(([k, v]) =>
      '<tr><th>' + k + '</th><td class="val">' + JSON.stringify(v) + '</td></tr>'
    ).join('');
    tbl.innerHTML = rows || '<tr><td>Aucune donnée</td></tr>';
  }

  // ── Signalements ─────────────────────────────────────────────────────────
  async function loadReports() {
    try {
      const [r, s] = await Promise.all([
        fetch('/admin/api/reports').then(x => x.json()),
        fetch('/admin/api/reports/stats').then(x => x.json()),
      ]);
      const tbody = document.querySelector('#tbl-reports tbody');
      const reports = r.reports || [];
      tbody.innerHTML = reports.length === 0
        ? '<tr><td colspan="4" style="color:var(--text2)">Aucun signalement actif</td></tr>'
        : reports.map(rep =>
            '<tr><td>' + rep.type + '</td>' +
            '<td class="val">' + (rep.votes || 0) + '</td>' +
            '<td>' + (rep.distributed ? '✅' : '❌') + '</td>' +
            '<td>' + Math.round((rep.ttl_remaining_s || 0) / 60) + ' min</td></tr>'
          ).join('');
      const statsDiv = document.getElementById('reports-stats');
      statsDiv.innerHTML = '<div class="stat-row"><span class="stat-label">Total actifs</span><span class="stat-val">' + (s.total_active_reports || 0) + '</span></div>' +
        '<div class="stat-row"><span class="stat-label">Panic en attente</span><span class="stat-val">' + (s.panic_queue_size || 0) + '</span></div>' +
        '<div class="stat-row"><span class="stat-label">Votes requis</span><span class="stat-val">' + (s.votes_required || 3) + '</span></div>';
    } catch (e) {
      addLog('Erreur signalements : ' + e.message);
    }
  }

  // ── Événements ────────────────────────────────────────────────────────────
  async function loadEvents() {
    try {
      const r = await fetch('/admin/api/events');
      const d = await r.json();
      const tbody = document.querySelector('#tbl-events tbody');
      const events = d.events || [];
      tbody.innerHTML = events.length === 0
        ? '<tr><td colspan="3" style="color:var(--text2)">Aucun événement</td></tr>'
        : events.map(ev =>
            '<tr><td>' + (ev.id || '—') + '</td>' +
            '<td>' + (ev.title || ev.name || '—') + '</td>' +
            '<td>' + (ev.status || ev.state || '—') + '</td></tr>'
          ).join('');
    } catch (e) {
      addLog('Erreur événements : ' + e.message);
    }
  }

  // ── Kill Switch ───────────────────────────────────────────────────────────
  async function killPrimary() {
    const reason = document.getElementById('kill-reason').value;
    if (!confirm('⚠️ Arrêter le serveur principal ?\\nCela déclenchera le failover vers le backup.')) return;
    addLog('🔴 Kill switch activé : ' + reason);
    try {
      const r = await fetch('/admin/api/kill-primary', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ reason }),
      });
      const d = await r.json();
      document.getElementById('kill-result').textContent =
        JSON.stringify(d, null, 2);
      toast('Kill envoyé ! Vérifiez le basculement.', '#B71C1C');
      addLog('Kill result : ' + JSON.stringify(d));
      setTimeout(loadStatus, 1500);
    } catch (e) {
      addLog('Erreur kill : ' + e.message);
      toast('Erreur : ' + e.message, '#B71C1C');
    }
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────────
  function toggleAutoRefresh() {
    autoActive = !autoActive;
    const btn = document.getElementById('autoBtn');
    if (autoActive) {
      autoRefreshInterval = setInterval(refreshAll, 5000);
      btn.textContent = '⏸ Auto actif';
      btn.style.background = 'var(--primary)';
      btn.style.color = '#000';
    } else {
      clearInterval(autoRefreshInterval);
      btn.textContent = '▶ Auto (5s)';
      btn.style.background = '#444';
      btn.style.color = 'var(--text)';
    }
  }

  function refreshAll() {
    loadStatus();
    loadReports();
    loadEvents();
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  refreshAll();
  addLog('Dashboard chargé — ' + new Date().toLocaleString('fr-FR'));
</script>
</body>
</html>`;

// ============================================================================
//  DÉMARRAGE
// ============================================================================

if (require.main === module) {
  app.listen(ADMIN_PORT, () => {
    log(`✅ Admin Dashboard démarré → http://localhost:${ADMIN_PORT}/admin`);
    log(`   Connecté à Primary:   ${PRIMARY_URL}`);
    log(`   Connecté à Secondary: ${SECONDARY_URL}`);
  });
}

module.exports = { app, ADMIN_PORT };
