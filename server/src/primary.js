// server/src/primary.js
// Serveur Principal StreetPhare — Node.js v3.0
//
// Rôle : PRIMARY
//   - Écoute sur le port configuré (défaut 3000).
//   - Reçoit les signalements, les valide (consensus), les stocke.
//   - Réplique automatiquement les données vers le Backup.
//   - Sert l'interface d'administration web (/admin).
//   - Expose les API REST et le WebSocket mesh.

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const path = require('path');
const { WebSocketServer } = require('ws');
const http = require('http');
const cron = require('node-cron');

const config = require('./config');
const store = require('./store');
const sync = require('./sync');
const apiRoutes = require('./routes/api');

const app = express();

// ── Log helper formaté [HH:MM:SS - DD/MM] - [CATEGORY] Message ────────────
function log(level, category, message) {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const MM = String(now.getMonth() + 1).padStart(2, '0');
  const ts = `[${hh}:${mm}:${ss} - ${dd}/${MM}]`;
  const line = `${ts} - [${category}] ${message}`;
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else console.log(line);
}

// ── Middlewares ──────────────────────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Morgan avec horodatage personnalisé
morgan.token('date-streetphare', () => {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const MM = String(now.getMonth() + 1).padStart(2, '0');
  return `[${hh}:${mm}:${ss} - ${dd}/${MM}]`;
});
app.use(morgan(':date-streetphare - [HTTP] :method :url :status - :response-time ms'));

// ── Fichiers statiques (interface admin) ────────────────────────────────
app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// ── Route GET /admin redirige vers index.html ────────────────────────────
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// ── Routes API ──────────────────────────────────────────────────────────
app.use('/api', apiRoutes);

// ── Page d'accueil ──────────────────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({
    name: 'StreetPhare Server',
    version: '3.0.0',
    role: 'PRIMARY',
    endpoints: {
      api: '/api',
      admin: '/admin',
      status: '/api/status',
      ping: '/api/ping',
      mesh: 'ws://<host>:3000/mesh',
    },
    sync: {
      partner: config.partnerUrl,
      intervalSeconds: config.syncIntervalSeconds,
      lastSync: store.syncState.lastSyncAt,
    },
  });
});

// ── Serveur HTTP ────────────────────────────────────────────────────────
const server = http.createServer(app);

// ── WebSocket Mesh ──────────────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/mesh' });
wss.on('connection', (ws) => {
  store.meshClients.add(ws);
  log('info', 'MESH', `Client connecté (total: ${store.meshClients.size})`);
  ws.on('message', (data) => {
    const msg = data.toString();
    store.meshClients.forEach(client => {
      if (client !== ws && client.readyState === 1) {
        client.send(msg);
      }
    });
  });
  ws.on('close', () => {
    store.meshClients.delete(ws);
    log('info', 'MESH', `Client déconnecté (total: ${store.meshClients.size})`);
  });
});

// ── WebSocket Admin ─────────────────────────────────────────────────────
const adminWss = new WebSocketServer({ server, path: '/admin-ws' });
adminWss.on('connection', (ws) => {
  store.adminClients.add(ws);
  log('info', 'ADMIN', `Admin connecté (total: ${store.adminClients.size})`);
  ws.on('close', () => {
    store.adminClients.delete(ws);
    log('info', 'ADMIN', `Admin déconnecté (total: ${store.adminClients.size})`);
  });
  ws.send(JSON.stringify({
    type: 'admin_snapshot',
    alerts: store.getActiveAlerts(),
    events: store.getAllEvents(),
    syncState: store.syncState,
  }));
});

// ── Synchronisation périodique ──────────────────────────────────────────
// Intervalle en secondes, converti en expression cron.
// Ex: 30s → '*/30 * * * * *' (toutes les 30 secondes).
const syncSec = Math.max(config.syncIntervalSeconds, 5);
const cronExpr = `*/${syncSec} * * * * *`;
cron.schedule(cronExpr, () => {
  log('info', 'SYNC', `Tentative synchro → ${config.partnerUrl}`);
  sync.pollSync().catch(e => {
    log('error', 'SYNC', `Échec vers ${config.partnerUrl}: ${e.message}`);
  });
});

// ── Démarrage ───────────────────────────────────────────────────────────
server.listen(config.port, config.host, () => {
  log('info', 'BOOT', '═══════════════════════════════════════════════');
  log('info', 'BOOT', `StreetPhare Server v3.0 — PRIMARY`);
  log('info', 'BOOT', `Adresse : http://${config.host}:${config.port}`);
  log('info', 'BOOT', `Admin   : http://${config.host}:${config.port}/admin`);
  log('info', 'BOOT', `Backup  : ${config.partnerUrl}`);
  log('info', 'BOOT', `Sync    : toutes les ${syncSec}s`);
  log('info', 'BOOT', '═══════════════════════════════════════════════');
});

module.exports = app;