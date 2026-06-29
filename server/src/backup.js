// server/src/backup.js
// Serveur Miroir StreetPhare — Node.js v3.1 (HTTPS/WSS)
//
// Rôle : BACKUP
//   - Écoute sur le port configuré (défaut 3001) en HTTPS (TLS).
//   - Reçoit les données répliquées du Primary (push + sync).
//   - Prend le relais automatiquement si le Primary est down.
//   - Sert l'interface d'administration (/admin) en cas de basculement.
//   - N'initie PAS de synchro sortante (rôle passif).

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const path = require('path');
const { WebSocketServer } = require('ws');
const https = require('https');
const http = require('http');
const fs = require('fs');

const config = require('./config');
const store = require('./store');
const sync = require('./sync');
const apiRoutes = require('./routes/api');

const app = express();

// ── Log helper formaté [HH:MM:SS - DD/MM] - [CATEGORY] Message ────────────
const log = (category, message) => {
  const now = new Date();
  const ts = [
    String(now.getHours()).padStart(2, '0'),
    String(now.getMinutes()).padStart(2, '0'),
    String(now.getSeconds()).padStart(2, '0'),
    ' - ',
    String(now.getDate()).padStart(2, '0'),
    '/',
    String(now.getMonth() + 1).padStart(2, '0'),
  ].join('');
  console.log(`[${ts}] - [${category}] ${message}`);
};

// ── Middlewares ──────────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
}));
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ── Logger HTTP ───────────────────────────────────────────────────────────
app.use((req, res, next) => {
  const now = new Date();
  const ts = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
  console.log(`[${ts}] [HTTP] REQ: ${req.method} ${req.originalUrl} - IP: ${ip}`);
  next();
});

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

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});
app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));
app.use('/public', express.static(path.join(__dirname, '..', 'public')));
app.use('/api', apiRoutes);

app.get('/', (req, res) => {
  res.json({
    name: 'StreetPhare Server',
    version: '3.1.0',
    role: 'BACKUP',
    tls: tlsOptions ? 'enabled' : 'disabled (dev mode)',
    endpoints: {
      api: '/api',
      admin: '/admin',
      status: '/api/status',
      ping: '/api/ping',
    },
    sync: {
      partner: config.partnerUrl,
      lastSync: store.syncState.lastSyncAt,
    },
  });
});

// ── TLS / HTTPS ────────────────────────────────────────────────────────────
const TLS_KEY_PATH = config.tlsKeyPath || path.join(__dirname, '..', 'assets', 'privkey.pem');
const TLS_CERT_PATH = config.tlsCertPath || path.join(__dirname, '..', 'assets', 'fullchain.pem');

let tlsOptions = null;
try {
  tlsOptions = {
    key: fs.readFileSync(TLS_KEY_PATH),
    cert: fs.readFileSync(TLS_CERT_PATH),
  };
  log('TLS', `Certificats chargés : ${TLS_CERT_PATH}`);
} catch (_) {
  log('TLS', `⚠ Certificats TLS introuvables. Fallback HTTP (dev uniquement).`);
}

const server = tlsOptions
  ? https.createServer(tlsOptions, app)
  : http.createServer(app);

// ── WebSocket Mesh (miroir) ────────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/mesh' });
const meshPingInterval = setInterval(() => {
  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      try { client.ping(); } catch (_) { /* ignore */ }
    }
  });
}, 30000);
wss.on('close', () => clearInterval(meshPingInterval));

wss.on('connection', (ws) => {
  store.meshClients.add(ws);
  log('MESH', `Client connecté (total: ${store.meshClients.size})`);
  try {
    ws.send(JSON.stringify({
      kind: 'welcome',
      server: 'StreetPhare-Backup',
      version: '3.1.0',
      tls: !!tlsOptions,
      ts: new Date().toISOString(),
    }));
  } catch (_) {}
  ws.on('message', (data) => {
    try {
      const msg = data.toString();
      log('MESH', `Message reçu: ${msg.substring(0, 200)}`);
      store.meshClients.forEach(client => {
        if (client !== ws && client.readyState === 1) {
          try { client.send(msg); } catch (_) {}
        }
      });
    } catch (e) {
      log('MESH', `Erreur message: ${e.message}`);
    }
  });
  ws.on('close', () => {
    store.meshClients.delete(ws);
    log('MESH', `Client déconnecté (total: ${store.meshClients.size})`);
  });
  ws.on('error', (err) => log('MESH', `Erreur socket: ${err.message}`));
});

// ── WebSocket Admin ─────────────────────────────────────────────────────
const adminWss = new WebSocketServer({ server, path: '/admin-ws' });
adminWss.on('connection', (ws) => {
  store.adminClients.add(ws);
  log('ADMIN', `Admin connecté (total: ${store.adminClients.size})`);
  ws.on('message', (data) => {
    log('ADMIN', `Message: ${data.toString().substring(0, 200)}`);
  });
  ws.on('close', () => {
    store.adminClients.delete(ws);
    log('ADMIN', `Admin déconnecté (total: ${store.adminClients.size})`);
  });
  ws.on('error', (err) => log('ADMIN', `Erreur socket: ${err.message}`));
  ws.send(JSON.stringify({
    type: 'admin_snapshot',
    alerts: store.getActiveAlerts(),
    events: store.getAllEvents(),
    syncState: store.syncState,
  }));
});

// ── Démarrage ───────────────────────────────────────────────────────────
server.listen(config.backupPort, config.backupHost, () => {
  const proto = tlsOptions ? 'https' : 'http';
  const wsProto = tlsOptions ? 'wss' : 'ws';
  console.log('═══════════════════════════════════════════════');
  console.log(`  StreetPhare Server v3.1 — BACKUP (${proto.toUpperCase()})`);
  console.log(`  Adresse : ${proto}://${config.backupHost}:${config.backupPort}`);
  console.log(`  Admin   : ${proto}://${config.backupHost}:${config.backupPort}/admin`);
  console.log(`  Mesh    : ${wsProto}://${config.backupHost}:${config.backupPort}/mesh`);
  console.log(`  Primary : ${config.partnerUrl}`);
  console.log(`  TLS     : ${tlsOptions ? '✅ Actif' : '⚠ Désactivé (dev)'}`);
  console.log('═══════════════════════════════════════════════');
});

module.exports = app;