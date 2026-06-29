// server/src/primary.js
// Serveur Principal StreetPhare — Node.js v3.1 (HTTPS/WSS)
//
// Rôle : PRIMARY
//   - Écoute sur le port configuré (défaut 3000) en HTTPS (TLS).
//   - En développement, fallback HTTP si les certificats sont absents.
//   - Reçoit les signalements, les valide (consensus), les stocke.
//   - Réplique automatiquement les données vers le Backup.
//   - Sert l'interface d'administration web (/admin).
//   - Expose les API REST et le WebSocket mesh en WSS.

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const path = require('path');
const { WebSocketServer } = require('ws');
const https = require('https');
const http = require('http');
const fs = require('fs');
const cron = require('node-cron');

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
// Helmet avec HSTS activé (force HTTPS pour les navigateurs)
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
  hsts: {
    maxAge: 31536000, // 1 an
    includeSubDomains: true,
    preload: true,
  },
}));
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ── Middleware de redirection HTTP → HTTPS ────────────────────────────────
// Intercepte les requêtes HTTP entrantes (si le serveur écoute en HTTP)
// et redirige vers HTTPS. Désactivé pour les requêtes loopback (debug).
app.use((req, res, next) => {
  const proto = req.headers['x-forwarded-proto'] || req.protocol;
  const isLocal = req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1';

  // Ne redirige pas les requêtes loopback (développement local).
  if (proto === 'http' && !isLocal && req.hostname !== 'localhost') {
    const httpsUrl = `https://${req.hostname}${req.originalUrl}`;
    log('SEC', `Redirection HTTP→HTTPS : ${req.originalUrl} → ${httpsUrl}`);
    return res.redirect(301, httpsUrl);
  }
  next();
});

// ── Logger HTTP personnalisé [YYYY-MM-DD HH:mm:ss] [HTTP] REQ: METHOD /ROUTE - IP: CLIENT
app.use((req, res, next) => {
  const now = new Date();
  const ts = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
  console.log(`[${ts}] [HTTP] REQ: ${req.method} ${req.originalUrl} - IP: ${ip}`);
  next();
});

// Morgan avec horodatage personnalisé (logs HTTP détaillés)
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

// ── Route GET /admin — DÉCLARÉE AVANT express.static pour éviter le conflit ──
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'admin', 'index.html'));
});

// ── Fichiers statiques (interface admin + assets) ────────────────────────
app.use('/admin', express.static(path.join(__dirname, '..', 'public', 'admin')));
app.use('/public', express.static(path.join(__dirname, '..', 'public')));

// ── Routes API ──────────────────────────────────────────────────────────
app.use('/api', apiRoutes);

// ── Page d'accueil ──────────────────────────────────────────────────────
app.get('/', (req, res) => {
  log('HTTP', `GET / — accueil demandé`);
  res.json({
    name: 'StreetPhare Server',
    version: '3.1.0',
    role: 'PRIMARY',
    tls: tlsOptions ? 'enabled' : 'disabled (dev mode)',
    endpoints: {
      api: '/api',
      admin: '/admin',
      status: '/api/status',
      ping: '/api/ping',
      mesh: tlsOptions ? 'wss://<host>:3000/mesh' : 'ws://<host>:3000/mesh',
    },
    sync: {
      partner: config.partnerUrl,
      intervalSeconds: config.syncIntervalSeconds,
      lastSync: store.syncState.lastSyncAt,
    },
  });
});

// ── TLS / HTTPS — Certificats Let's Encrypt ou auto-signés ────────────────
// En production, ces fichiers doivent pointer vers les certificats
// délivrés par Let's Encrypt (via certbot ou acme.sh).
// En développement local, générer un certificat auto-signé :
//   openssl req -x509 -newkey rsa:4096 -keyout privkey.pem -out fullchain.pem -days 365 -nodes -subj "/CN=localhost"
const TLS_KEY_PATH = config.tlsKeyPath || path.join(__dirname, '..', 'assets', 'privkey.pem');
const TLS_CERT_PATH = config.tlsCertPath || path.join(__dirname, '..', 'assets', 'fullchain.pem');

const isProduction = process.env.NODE_ENV === 'production';

let tlsOptions = null;
try {
  tlsOptions = {
    key: fs.readFileSync(TLS_KEY_PATH),
    cert: fs.readFileSync(TLS_CERT_PATH),
  };
  log('TLS', `✅ Certificats chargés : ${TLS_CERT_PATH}`);
} catch (err) {
  if (isProduction) {
    console.error('╔══════════════════════════════════════════════════════╗');
    console.error('║  ERREUR FATALE : Certificats TLS introuvables       ║');
    console.error('║  En production, le HTTPS est OBLIGATOIRE.           ║');
    console.error(`║  Fichiers attendus :                                ║`);
    console.error(`║    Clé  : ${TLS_KEY_PATH.padEnd(45)}║`);
    console.error(`║    Cert : ${TLS_CERT_PATH.padEnd(45)}║`);
    console.error('║  Pour générer des certificats auto-signés :         ║');
    console.error('║    openssl req -x509 -newkey rsa:4096 \\             ║');
    console.error('║      -keyout privkey.pem -out fullchain.pem \\       ║');
    console.error('║      -days 365 -nodes -subj "/CN=localhost"         ║');
    console.error('║  Pour Let\'s Encrypt : utiliser certbot ou acme.sh   ║');
    console.error('╚══════════════════════════════════════════════════════╝');
    process.exit(1);
  }
  log('TLS', `⚠ Certificats TLS introuvables — démarrage en HTTP (dev uniquement).`);
  log('TLS', `  (${err.message})`);
}

// ── Création du serveur (HTTPS prioritaire, fallback HTTP en dev) ────
const server = tlsOptions
  ? https.createServer(tlsOptions, app)
  : http.createServer(app);

// ── WebSocket Mesh ──────────────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/mesh' });

// Intervalle de ping/pong pour maintenir les connexions WebSocket
// ouvertes malgré les proxy/timeout réseau (30s).
// Détection des clients fantômes : 3 pings échoués consécutifs → déconnexion.
const pingFailures = new WeakMap(); // ws → compteur d'échecs

const meshPingInterval = setInterval(() => {
  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      try {
        client.ping();
        // Reset du compteur en cas de succès (pong implicite).
        pingFailures.set(client, 0);
      } catch (_) {
        // Échec du ping → incrémenter le compteur.
        const fails = (pingFailures.get(client) || 0) + 1;
        pingFailures.set(client, fails);
        if (fails >= 3) {
          log('MESH', `Client fantôme détecté (${fails} pings échoués) → déconnexion`);
          try { client.close(1001, 'Ping timeout'); } catch (__) {}
          store.meshClients.delete(client);
        }
      }
    }
  });
}, 30000);
wss.on('close', () => clearInterval(meshPingInterval));

wss.on('connection', (ws) => {
  try {
    store.meshClients.add(ws);
    log('MESH', `Client connecté (total: ${store.meshClients.size})`);

    // ── Envoi immédiat d'un message d'accueil (handshake) ──────────
    try {
      ws.send(JSON.stringify({
        kind: 'welcome',
        server: 'StreetPhare-Primary',
        version: '3.1.0',
        tls: !!tlsOptions,
        ts: new Date().toISOString(),
      }));
    } catch (e) {
      log('MESH', `Erreur envoi welcome: ${e.message}`);
    }

    // Rate limiting : max 10 messages par seconde par client.
    // Au-delà → blacklist temporaire de 30 secondes.
    const msgTimestamps = []; // horodatages des messages de ce client
    const RATE_LIMIT_MAX = 10;
    const RATE_LIMIT_WINDOW_MS = 1000;
    const RATE_LIMIT_BLACKLIST_MS = 30000;
    let blacklistedUntil = 0;

    ws.on('message', (data) => {
      try {
        const now = Date.now();

        // Blacklist active ?
        if (now < blacklistedUntil) {
          log('MESH', `Message bloqué (blacklist ${Math.round((blacklistedUntil - now) / 1000)}s restantes)`);
          return;
        }

        // Nettoyage des timestamps hors fenêtre.
        while (msgTimestamps.length > 0 && msgTimestamps[0] < now - RATE_LIMIT_WINDOW_MS) {
          msgTimestamps.shift();
        }

        msgTimestamps.push(now);

        // Vérification du rate limit.
        if (msgTimestamps.length > RATE_LIMIT_MAX) {
          blacklistedUntil = now + RATE_LIMIT_BLACKLIST_MS;
          log('MESH', `⛔ Rate limit dépassé (${msgTimestamps.length} msg/s) → blacklist 30s`);
          return;
        }

        const msg = data.toString();
        log('MESH', `Message reçu: ${msg.substring(0, 200)}`);
        store.meshClients.forEach(client => {
          if (client !== ws && client.readyState === 1) {
            try {
              client.send(msg);
            } catch (sendErr) {
              log('MESH', `Erreur envoi à client: ${sendErr.message}`);
            }
          }
        });
      } catch (e) {
        log('MESH', `Erreur traitement message: ${e.message}`);
      }
    });

    ws.on('close', () => {
      store.meshClients.delete(ws);
      log('MESH', `Client déconnecté (total: ${store.meshClients.size})`);
    });

    ws.on('error', (err) => {
      log('MESH', `Erreur socket: ${err.message}`);
    });
  } catch (e) {
    log('MESH', `Erreur critique connexion: ${e.message}`);
    try { ws.close(); } catch (_) {}
  }
});

// ── WebSocket Admin ─────────────────────────────────────────────────────
const adminWss = new WebSocketServer({ server, path: '/admin-ws' });
adminWss.on('connection', (ws) => {
  store.adminClients.add(ws);
  log('ADMIN', `Admin connecté (total: ${store.adminClients.size})`);
  ws.on('message', (data) => {
    const msg = data.toString();
    log('ADMIN', `Message admin: ${msg.substring(0, 200)}`);
  });
  ws.on('close', () => {
    store.adminClients.delete(ws);
    log('ADMIN', `Admin déconnecté (total: ${store.adminClients.size})`);
  });
  ws.on('error', (err) => {
    log('ADMIN', `Erreur socket: ${err.message}`);
  });
  ws.send(JSON.stringify({
    type: 'admin_snapshot',
    alerts: store.getActiveAlerts(),
    events: store.getAllEvents(),
    syncState: store.syncState,
  }));
});

// ── Synchronisation périodique ──────────────────────────────────────────
const syncSec = Math.max(config.syncIntervalSeconds, 5);
const cronExpr = `*/${syncSec} * * * * *`;
cron.schedule(cronExpr, () => {
  log('SYNC', `Tentative synchro → ${config.partnerUrl}`);
  sync.pollSync().catch(e => {
    log('SYNC', `Échec vers ${config.partnerUrl}: ${e.message}`);
  });
});

// ── Outbox de réplication (retry automatique) ───────────────────────────
sync.startOutbox();

// ── Démarrage ───────────────────────────────────────────────────────────
server.listen(config.port, config.host, () => {
  const proto = tlsOptions ? 'https' : 'http';
  const wsProto = tlsOptions ? 'wss' : 'ws';
  console.log('═══════════════════════════════════════════════');
  console.log(`  StreetPhare Server v3.1 — PRIMARY (${proto.toUpperCase()})`);
  console.log(`  Adresse : ${proto}://${config.host}:${config.port}`);
  console.log(`  Admin   : ${proto}://${config.host}:${config.port}/admin`);
  console.log(`  Mesh    : ${wsProto}://${config.host}:${config.port}/mesh`);
  console.log(`  Backup  : ${config.partnerUrl}`);
  console.log(`  Sync    : toutes les ${syncSec}s`);
  console.log(`  TLS     : ${tlsOptions ? '✅ Actif' : '⚠ Désactivé (dev)'}`);
  console.log(`  Store   : persistance JSON → ${store.STORE_PATH || 'data/store.json'}`);
  console.log(`  Outbox  : ${sync.outboxSize()} en attente`);
  console.log('═══════════════════════════════════════════════');
});

// ── Arrêt propre (graceful shutdown) ──────────────────────────────────
// Sauvegarde l'état sur disque et ferme les connexions avant de quitter.
const gracefulShutdown = (signal) => {
  log('SHUTDOWN', `Signal ${signal} reçu — arrêt propre...`);
  
  // 1. Arrêter la synchro cron.
  cron.getTasks().forEach((task) => task.stop());
  
  // 2. Fermer les sockets WebSocket.
  wss.clients.forEach((client) => {
    try { client.close(1001, 'Server shutting down'); } catch (_) {}
  });
  adminWss.clients.forEach((client) => {
    try { client.close(1001, 'Server shutting down'); } catch (_) {}
  });
  
  // 3. Sauvegarder l'état sur disque.
  const saved = store.saveSync();
  log('SHUTDOWN', saved ? 'État persisté avec succès' : '⚠ Échec persistance');
  
  // 4. Fermer le serveur HTTP(S).
  server.close(() => {
    log('SHUTDOWN', 'Serveur fermé. Au revoir.');
    process.exit(0);
  });
  
  // Timeout de sécurité : force l'arrêt après 10s.
  setTimeout(() => {
    log('SHUTDOWN', 'Timeout — arrêt forcé.');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGUSR2', () => gracefulShutdown('SIGUSR2')); // nodemon restart

module.exports = app;
