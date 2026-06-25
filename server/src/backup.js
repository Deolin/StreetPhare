// server/src/backup.js
// Serveur Miroir StreetPhare — Node.js v3.0
//
// Rôle : BACKUP
//   - Écoute sur le port configuré (défaut 3001).
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
const http = require('http');

const config = require('./config');
const store = require('./store');
const sync = require('./sync');
const apiRoutes = require('./routes/api');

const app = express();

// ── Middlewares ──────────────────────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(morgan(':method :url :status - :response-time ms'));

// ── Fichiers statiques (interface admin) ────────────────────────────────
app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// ── Routes API ──────────────────────────────────────────────────────────
app.use('/api', apiRoutes);

// ── Page d'accueil ──────────────────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({
    name: 'StreetPhare Server',
    version: '3.0.0',
    role: 'BACKUP (Miroir)',
    endpoints: {
      api: '/api',
      admin: '/admin',
      status: '/api/status',
      ping: '/api/ping',
    },
    sync: {
      partner: config.partnerUrl,
      lastSync: store.syncState.lastSyncAt,
      lastSuccess: store.syncState.lastSyncSuccess,
    },
  });
});

// ── Serveur HTTP ────────────────────────────────────────────────────────
const server = http.createServer(app);

// ── WebSocket Mesh ──────────────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/mesh' });
wss.on('connection', (ws) => {
  store.meshClients.add(ws);
  ws.on('message', (data) => {
    const msg = data.toString();
    store.meshClients.forEach(client => {
      if (client !== ws && client.readyState === 1) {
        client.send(msg);
      }
    });
  });
  ws.on('close', () => { store.meshClients.delete(ws); });
});

// ── Démarrage ───────────────────────────────────────────────────────────
server.listen(config.port, config.host, () => {
  console.log('═══════════════════════════════════════════════');
  console.log(`  StreetPhare Server v3.0 — BACKUP (Miroir)`);
  console.log(`  Adresse : http://${config.host}:${config.port}`);
  console.log(`  Admin   : http://${config.host}:${config.port}/admin`);
  console.log(`  Primary : ${config.partnerUrl}`);
  console.log(`  Rôle    : Réception passive — prend le relais`);
  console.log(`           si le Primary est down.`);
  console.log('═══════════════════════════════════════════════');
});

module.exports = app;