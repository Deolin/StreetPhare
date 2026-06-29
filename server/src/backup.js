// server/src/backup.js
// Serveur Miroir StreetPhare — Node.js v3.1 (HTTP — TLS terminé par Caddy)
//
// Rôle : BACKUP
//   - Écoute sur 127.0.0.1:3001 en HTTP (le TLS est terminé par Caddy).
//   - Reçoit les données répliquées du Primary (push + sync).
//   - Prend le relais automatiquement si le Primary est down.
//   - Sert l'interface d'administration (/admin) en cas de basculement.
//   - N'initie PAS de synchro sortante (rôle passif).

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const path = require('path');
const { WebSocketServer } = require('ws');
const http = require('http');

const config = require('./config');
const store = require('./store');
const sync = require('./sync');
const apiRoutes = require('./routes/api');
const { verifyWsToken } = require('./middleware/auth');

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
  // HSTS désactivé : Caddy gère le TLS et les en-têtes HSTS.
}));
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ── Trust Proxy — Récupère la vraie IP du client via X-Forwarded-For ──
app.set('trust proxy', 1);

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

// ── Rate Limiting — Protection anti-brute force sur toutes les routes ──
const limiter = rateLimit({
  windowMs: config.rateLimitWindowMs,
  max: config.rateLimitMax,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Trop de requêtes. Veuillez réessayer plus tard.',
  },
  handler: (req, res, _next, options) => {
    log('RATELIMIT', `⛔ Limite atteinte — IP: ${req.ip} — ${req.method} ${req.originalUrl}`);
    res.status(429).json({
      error: options.message.error,
      retryAfterMs: options.windowMs,
    });
  },
  skip: (req) => {
    if (req.path.startsWith('/api/sync/')) return true;
    if (req.path === '/api/ping') return true;
    return false;
  },
});
app.use(limiter);

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
    tls: 'terminated-by-caddy',
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

// ── Création du serveur HTTP (TLS terminé par Caddy) ─────────────────
const server = http.createServer(app);

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
      tls: true, // TLS terminé par Caddy.
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

// ── WebSocket Admin (protégé par JWT) ─────────────────────────────────
const adminWss = new WebSocketServer({
  server,
  path: '/admin-ws',
  verifyClient: (info, cb) => {
    const reqUrl = info.req.url || '';
    try {
      const decoded = verifyWsToken(reqUrl);
      info.req.adminUser = decoded;
      cb(true);
    } catch (err) {
      log('ADMIN', `Tentative de connexion WebSocket admin rejetée : ${err.message}`);
      cb(false, 401, 'Unauthorized');
    }
  },
});

adminWss.on('connection', (ws, req) => {
  const adminUser = req.adminUser || { role: 'unknown' };

  store.adminClients.add(ws);
  log('ADMIN', `Admin authentifié (rôle=${adminUser.role}, total: ${store.adminClients.size})`);

  try {
    ws.send(JSON.stringify({
      type: 'admin_snapshot',
      alerts: store.getActiveAlerts(),
      events: store.getAllEvents(),
      syncState: store.syncState,
    }));
  } catch (e) {
    log('ADMIN', `Erreur envoi snapshot: ${e.message}`);
  }

  ws.on('message', (data) => {
    log('ADMIN', `Message (${adminUser.role}): ${data.toString().substring(0, 200)}`);
  });

  ws.on('close', () => {
    store.adminClients.delete(ws);
    log('ADMIN', `Admin déconnecté (total: ${store.adminClients.size})`);
  });

  ws.on('error', (err) => log('ADMIN', `Erreur socket: ${err.message}`));
});

// ── Démarrage ───────────────────────────────────────────────────────────
server.listen(config.backupPort, config.backupHost, () => {
  console.log('═══════════════════════════════════════════════');
  console.log(`  StreetPhare Server v3.1 — BACKUP (HTTP)`);
  console.log(`  Adresse : http://${config.backupHost}:${config.backupPort}`);
  console.log(`  Admin   : http://${config.backupHost}:${config.backupPort}/admin`);
  console.log(`  Mesh    : ws://${config.backupHost}:${config.backupPort}/mesh`);
  console.log(`  Primary : ${config.partnerUrl}`);
  console.log(`  TLS     : ✅ Terminé par Caddy (reverse-proxy)`);
  console.log('═══════════════════════════════════════════════');
});

module.exports = app;