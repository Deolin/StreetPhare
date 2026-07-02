// server/src/primary.js
// Serveur Principal StreetPhare — Node.js v3.1 (HTTP — TLS terminé par Caddy)
//
// Rôle : PRIMARY
//   - Écoute sur 127.0.0.1:3000 en HTTP (le TLS est terminé par Caddy).
//   - Reçoit les signalements, les valide (consensus), les stocke.
//   - Réplique automatiquement les données vers le Backup.
//   - Sert l'interface d'administration web (/admin).
//   - Expose les API REST et le WebSocket mesh.
//
// Architecture réseau :
//   Client ←→ Caddy (TLS :443) ←→ Primary (HTTP :3000, 127.0.0.1)
//                    ↕
//              Backup (HTTP :3001, 127.0.0.1)

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const path = require('path');
const { WebSocketServer } = require('ws');
const http = require('http');
const { spawn } = require('child_process');
const cron = require('node-cron');

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
// Helmet avec HSTS activé (force HTTPS pour les navigateurs)
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
  // HSTS désactivé : Caddy gère le TLS et les en-têtes HSTS.
  // Le serveur Node.js ne doit PAS rediriger HTTP→HTTPS lui-même.
}));
// FIX v3.3.4 : CORS permissif pour le reverse-proxy Caddy.
// Caddy transmet l'Origin du client mobile via header_up Origin {header.origin}.
// Le middleware cors() avec origin: true accepte tout Origin (la sécurité
// est assurée par Caddy en amont : TLS, rate limiting, HSTS).
// Sans cela, les connexions WebSocket sans Origin étaient rejetées → code 1006.
app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ── Trust Proxy — Récupère la vraie IP du client via X-Forwarded-For ──
// Caddy transmet l'IP réelle du citoyen dans le header X-Forwarded-For.
// `trust proxy` est limité à 1 saut (Caddy uniquement) pour éviter
// l'erreur ERR_ERL_PERMISSIVE_TRUST_PROXY de express-rate-limit v7.
// Les limiters utilisent `keyGenerator: (req) => req.ip` qui exploite
// cette confiance pour retourner l'IP distante réelle.
app.set('trust proxy', 1);

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

// ── Rate Limiting — Protection anti-brute force sur toutes les routes ──
// Configurable via RATE_LIMIT_WINDOW_MS et RATE_LIMIT_MAX.
const limiter = rateLimit({
  windowMs: config.rateLimitWindowMs,
  max: config.rateLimitMax,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Trop de requêtes. Veuillez réessayer plus tard.',
  },
  handler: (req, res, /* next */ _next, options) => {
    log('RATELIMIT', `⛔ Limite atteinte — IP: ${req.ip} — ${req.method} ${req.originalUrl}`);
    res.status(429).json({
      error: options.message.error,
      retryAfterMs: options.windowMs,
    });
  },
  // Routes exclues du rate limiting : WebSocket (géré par leur propre
  // mécanisme de rate limiting) et sync interne Primary↔Backup.
  skip: (req) => {
    // Ne pas limiter les requêtes de synchronisation entre serveurs
    // ni les requêtes de sync client (sync-push, sync-check).
    if (req.path.startsWith('/api/sync')) return true;
    // Ne pas limiter le ping (healthcheck).
    if (req.path === '/api/ping') return true;
    return false;
  },
});
app.use(limiter);

// ── Route GET /admin — DÉCLARÉE AVANT express.static pour éviter le conflit ──
app.get('/admin', (req, res) => {
  // Désactive le cache navigateur pour que les mises à jour du dashboard
  // soient visibles immédiatement après un `npm run dev:primary`.
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
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
    tls: 'terminated-by-caddy',
    endpoints: {
      api: '/api',
      admin: '/admin',
      status: '/api/status',
      ping: '/api/ping',
      mesh: 'wss://streetphare.ddns.net/mesh',
    },
    sync: {
      partner: config.partnerUrl,
      intervalSeconds: config.syncIntervalSeconds,
      lastSync: store.syncState.lastSyncAt,
    },
  });
});

// ── Création du serveur HTTP (TLS terminé par Caddy) ─────────────────
const server = http.createServer(app);

// ── DIAGNOSTIC v3.2.1 : Log toutes les requêtes d'upgrade WebSocket ──
// Intercepte l'événement `upgrade` AVANT que le WebSocketServer ne
// le traite, pour voir exactement ce que Caddy transmet.
server.on('upgrade', (request, socket, head) => {
  const headers = request.headers;
  log('MESH', `[UPGRADE] ${request.url} — Upgrade: ${headers['upgrade'] || 'N/A'} — Connection: ${headers['connection'] || 'N/A'} — Origin: ${headers['origin'] || 'N/A'} — IP: ${headers['x-forwarded-for'] || request.socket.remoteAddress}`);
});

// ── WebSocket Mesh ──────────────────────────────────────────────────────
// FIX v3.2 : Options de heartbeat intégrées à WebSocketServer pour
// détecter les connexions mortes au niveau du protocole (RFC 6455).
// - maxPayload: limite la taille des messages pour éviter les crashs OOM
// - skipUTF8Validation: true pour les clients compatibles (perf)
const wss = new WebSocketServer({
  server,
  path: '/mesh',
  maxPayload: 512 * 1024, // 512 Ko max par message (évite crash OOM sur welcome massif)
  clientTracking: true,
  // FIX v3.3.4 — Désactiver la compression permessage-deflate.
  // Le client Dart/dart:io ne supporte PAS l'extension permessage-deflate
  // (RFC 7692). Sans cette désactivation, le serveur ws compresse les
  // frames, dart:io voit un bit RSV1 inattendu et ferme la connexion
  // avec le code 1002 (Protocol Error). Le serveur voit un code 1006
  // (Abnormal Closure) car le client ne fait pas de handshake de close
  // propre. Résultat : déconnexion 1ms après le welcome → boucle infinie.
  perMessageDeflate: false,
});

// ── Heartbeat serveur : détection des clients fantômes ──────────────────
// Envoie un ping natif (RFC 6455) toutes les 30 secondes.
// Attend un pong dans les 10 secondes. Après 2 échecs consécutifs,
// le client est considéré comme fantôme et déconnecté.
//
// FIX v3.2 : Le compteur était remis à 0 APRÈS chaque ping sans
// attendre le pong (bug). Maintenant, on enregistre l'heure du
// dernier pong reçu et on vérifie l'écart.
const PING_INTERVAL_MS = 30000;
const PONG_TIMEOUT_MS = 10000;
const MAX_MISSED_PONGS = 2;
const lastPongSeen = new WeakMap(); // ws → timestamp du dernier pong

// Écoute les pongs reçus (réponses aux pings serveur).
wss.on('pong', (ws) => {
  lastPongSeen.set(ws, Date.now());
});

const meshPingInterval = setInterval(() => {
  const now = Date.now();
  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      try {
        client.ping();
      } catch (_) {
        // Échec du ping → socket probablement déjà fermé.
        const missed = lastPongSeen.has(client)
          ? Math.floor((now - lastPongSeen.get(client)) / PONG_TIMEOUT_MS)
          : MAX_MISSED_PONGS;
        if (missed >= MAX_MISSED_PONGS) {
          log('MESH', `Client fantôme détecté (${missed}+ pings sans pong) → déconnexion`);
          try { client.close(1001, 'Ping timeout'); } catch (__) {}
          store.meshClients.delete(client);
        }
      }
    }
  });

  // Vérifie les clients qui n'ont jamais répondu à un pong
  // (connexions récentes qui n'ont pas encore eu de heartbeat).
  wss.clients.forEach((client) => {
    if (client.readyState === 1 && lastPongSeen.has(client)) {
      const elapsed = now - lastPongSeen.get(client);
      if (elapsed > PING_INTERVAL_MS * MAX_MISSED_PONGS + PONG_TIMEOUT_MS) {
        log('MESH', `Client silencieux (dernier pong il y a ${Math.round(elapsed / 1000)}s) → déconnexion`);
        try { client.close(1001, 'Pong timeout'); } catch (_) {}
        store.meshClients.delete(client);
      }
    }
  });
}, PING_INTERVAL_MS);
wss.on('close', () => clearInterval(meshPingInterval));

// ── Anti-tempête de reconnexion WebSocket ──────────────────────────
// FIX v3.3.0 — Cooldown réduit + nettoyage CGNAT :
//   Clients WAN derrière NAT/CGNAT partagent la même IP publique.
//   2000ms rejetait des clients légitimes → code 1006 côté Flutter.
//   Réduit à 500ms (anti-boucle rapide uniquement).
const _meshReconnectCooldowns = new Map(); // ip → timestamp prochaine connexion autorisée
const MESH_RECONNECT_COOLDOWN_MS = 500;

// Nettoyage périodique pour éviter les fuites mémoire.
setInterval(() => {
  const now = Date.now();
  for (const [ip, until] of _meshReconnectCooldowns.entries()) {
    if (until < now) _meshReconnectCooldowns.delete(ip);
  }
}, 60000);

// FIX v3.2 : Limite la taille du welcome (backlog) à 50 messages max
// pour éviter d'envoyer un payload de plusieurs Mo qui saturerait
// le client et causerait une déconnexion immédiate.
const MAX_WELCOME_BACKLOG = 50;

// DIAGNOSTIC v3.2.1 : Logs de timing pour identifier la cause
// du code 1006 (fermeture anormale immédiate).
wss.on('connection', (ws, req) => {
  const connId = Math.random().toString(36).slice(2, 8);
  const t0 = Date.now();
  try {
    // ── Vérification du cooldown de reconnexion par IP ──────────
    const clientIp = (req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown').toString().split(',')[0].trim();
    const now = t0;
    const cooldownUntil = _meshReconnectCooldowns.get(clientIp) || 0;
    if (now < cooldownUntil) {
      log('MESH', `[${connId}] Reconnexion trop rapide (IP=${clientIp}, ${Math.round((cooldownUntil - now) / 1000)}s restantes) → rejetée`);
      try { ws.close(4001, 'Reconnect too fast'); } catch (_) {}
      return;
    }
    _meshReconnectCooldowns.set(clientIp, now + MESH_RECONNECT_COOLDOWN_MS);

    // DIAGNOSTIC : Enregistre les handlers AVANT d'envoyer le welcome
    // pour capturer toute fermeture précoce.
    let closeCaptured = false;
    ws.on('close', (code, reason) => {
      closeCaptured = true;
      store.meshClients.delete(ws);
      lastPongSeen.delete(ws);
      const reasonStr = reason ? reason.toString() : 'non spécifiée';
      const elapsed = Date.now() - t0;
      log('MESH', `[${connId}] Client déconnecté (code=${code || '?'}, raison=${reasonStr}, elapsed=${elapsed}ms, total: ${store.meshClients.size})`);
    });

    ws.on('error', (err) => {
      log('MESH', `[${connId}] Erreur socket: ${err.message}`);
    });

    store.meshClients.add(ws);
    log('MESH', `[${connId}] Client connecté (total: ${store.meshClients.size}, IP: ${clientIp})`);

    // Enregistre un premier pong "virtuel" pour éviter que le client
    // soit considéré comme fantôme avant le premier cycle de ping.
    lastPongSeen.set(ws, Date.now());

    // ── Handshake + synchronisation des messages manqués ──────────
    try {
      const syncSince = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const missedMessages = store.getMeshMessagesSince(syncSince);
      const truncated = missedMessages.slice(-MAX_WELCOME_BACKLOG);
      const welcomePayload = JSON.stringify({
        kind: 'welcome',
        server: 'StreetPhare-Primary',
        version: '3.2.1',
        tls: true,
        ts: new Date().toISOString(),
        missedCount: truncated.length,
        totalMissed: missedMessages.length,
        missed: truncated,
      });

      const payloadSize = Buffer.byteLength(welcomePayload, 'utf-8');
      if (payloadSize > 256 * 1024) {
        log('MESH', `[${connId}] ⚠ Welcome trop volumineux (${Math.round(payloadSize / 1024)} Ko) → envoi sans backlog`);
        ws.send(JSON.stringify({
          kind: 'welcome',
          server: 'StreetPhare-Primary',
          version: '3.2.1',
          tls: true,
          ts: new Date().toISOString(),
          missedCount: 0,
          totalMissed: missedMessages.length,
          missed: [],
          note: 'Backlog trop volumineux, synchronisation différée',
        }), (err) => {
          if (err) log('MESH', `[${connId}] Erreur envoi welcome (fallback): ${err.message}`);
          else log('MESH', `[${connId}] Welcome fallback envoyé (${Date.now() - t0}ms)`);
        });
      } else {
        ws.send(welcomePayload, (err) => {
          if (err) {
            log('MESH', `[${connId}] Erreur envoi welcome: ${err.message}`);
          } else if (!closeCaptured) {
            log('MESH', `[${connId}] Welcome envoyé (${Math.round(payloadSize / 1024)} Ko, ${Date.now() - t0}ms)`);
            if (truncated.length > 0) {
              log('MESH', `[${connId}] Handshake : ${truncated.length}/${missedMessages.length} messages backlog`);
            }
          }
        });
      }
    } catch (e) {
      log('MESH', `[${connId}] Erreur handshake/sync: ${e.message}`);
      try {
        ws.send(JSON.stringify({
          kind: 'welcome',
          server: 'StreetPhare-Primary',
          version: '3.2.1',
          tls: true,
          ts: new Date().toISOString(),
          missedCount: 0,
          missed: [],
        }));
      } catch (_) {}
    }

    // Rate limiting : max 10 messages par seconde par client.
    const msgTimestamps = [];
    const RATE_LIMIT_MAX = 10;
    const RATE_LIMIT_WINDOW_MS = 1000;
    const RATE_LIMIT_BLACKLIST_MS = 30000;
    let blacklistedUntil = 0;

    ws.on('message', (data) => {
      try {
        const now = Date.now();

        if (now < blacklistedUntil) {
          log('MESH', `[${connId}] Message bloqué (blacklist ${Math.round((blacklistedUntil - now) / 1000)}s restantes)`);
          return;
        }

        while (msgTimestamps.length > 0 && msgTimestamps[0] < now - RATE_LIMIT_WINDOW_MS) {
          msgTimestamps.shift();
        }

        msgTimestamps.push(now);

        if (msgTimestamps.length > RATE_LIMIT_MAX) {
          blacklistedUntil = now + RATE_LIMIT_BLACKLIST_MS;
          log('MESH', `[${connId}] ⛔ Rate limit dépassé → blacklist 30s`);
          return;
        }

        const msg = data.toString();
        log('MESH', `[${connId}] Message reçu (${Date.now() - t0}ms): ${msg.substring(0, 150)}`);

        try {
          const parsed = JSON.parse(msg);
          store.addMeshMessage({
            kind: parsed.kind || 'mesh',
            data: parsed,
            sender_id: parsed.sender_id || parsed.peerId || 'unknown',
          });
        } catch (_) {}

        store.meshClients.forEach(client => {
          if (client !== ws && client.readyState === 1) {
            try { client.send(msg); } catch (sendErr) {
              log('MESH', `[${connId}] Erreur relai: ${sendErr.message}`);
            }
          }
        });
      } catch (e) {
        log('MESH', `[${connId}] Erreur traitement message: ${e.message}`);
      }
    });
  } catch (e) {
    log('MESH', `[${connId}] Erreur critique connexion: ${e.message}`);
    try { ws.close(1011, 'Internal server error'); } catch (_) {}
  }
});

// ── WebSocket Admin (protégé par JWT) ─────────────────────────────────
// Le client doit fournir un token JWT valide dans le query param :
//   wss://host:3000/admin-ws?token=eyJ...
// La vérification est effectuée par verifyClient avant l'upgrade.
const adminWss = new WebSocketServer({
  server,
  path: '/admin-ws',
  maxPayload: 512 * 1024,
  verifyClient: (info, cb) => {
    const reqUrl = info.req.url || '';
    log('ADMIN', `WebSocket handshake reçu → ${reqUrl.substring(0, 120)}`);

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

  // ── Envoi immédiat du snapshot après authentification ──────────
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
    const msg = data.toString();
    log('ADMIN', `Message admin (${adminUser.role}): ${msg.substring(0, 200)}`);
  });

  ws.on('close', () => {
    store.adminClients.delete(ws);
    log('ADMIN', `Admin déconnecté (total: ${store.adminClients.size})`);
  });

  ws.on('error', (err) => {
    log('ADMIN', `Erreur socket: ${err.message}`);
  });
});

// ── Synchronisation périodique avec exponential backoff ─────────────────
// Remplace le cron fixe `*/30 * * * * *` par un timer auto-adaptatif
// qui espace les tentatives quand le Backup est injoignable (30s → 8 min).
sync.startPolling();

// ── Outbox de réplication (retry automatique) ───────────────────────────
sync.startOutbox();

// ── Purge périodique du backlog mesh (48h) ──────────────────────────
cron.schedule('0 * * * *', () => {
  try { store.purgeExpiredMeshMessages(); } catch (_) {}
});

// ── Démon Caddy (Reverse-Proxy TLS) ──────────────────────────────────
// Lance Caddy en processus détaché. Si Caddy crashe ou est tué,
// il n'impacte PAS le serveur Node.js. Réciproquement, si Node.js
// crashe ou est "kické", Caddy continue de tourner en arrière-plan
// et peut rediriger le trafic vers le Backup (port 3001).
//
// Utilise `spawn` avec :
//   - `detached: true`  → nouveau groupe de processus, indépendant.
//   - `stdio: 'ignore'` → pas d'héritage des flux stdin/stdout/stderr.
//   - `unref()`          → Node.js ne bloque PAS l'event loop sur ce
//                          processus enfant. Le processus Caddy survit
//                          à l'arrêt du processus Node.js parent.
launchCaddyIndependent();

// ── Démarrage ───────────────────────────────────────────────────────────
server.listen(config.port, config.host, () => {
  console.log('═══════════════════════════════════════════════');
  console.log(`  StreetPhare Server v3.2 — PRIMARY (HTTP)`);
  console.log(`  Adresse : http://${config.host}:${config.port}`);
  console.log(`  Admin   : http://${config.host}:${config.port}/admin`);
  console.log(`  Mesh    : ws://${config.host}:${config.port}/mesh`);
  console.log(`  Backup  : ${config.partnerUrl}`);
  console.log(`  Sync    : polling adaptatif (backoff 30s → 8 min)`);
  console.log(`  TLS     : ✅ Terminé par Caddy (reverse-proxy)`);
  console.log(`  Store   : persistance JSON → ${store.STORE_PATH || 'data/store.json'}`);
  console.log(`  Outbox  : ${sync.outboxSize()} en attente`);
  console.log(`  Heartbeat: ping/${PING_INTERVAL_MS / 1000}s, timeout pong/${PONG_TIMEOUT_MS / 1000}s`);
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

// ── Fonction : lancement indépendant de Caddy ─────────────────────────

/// Lance le reverse-proxy Caddy en tant que processus démon détaché.
///
/// Le processus Caddy est totalement indépendant du cycle de vie de
/// Node.js :
///   - `detached: true` : nouveau groupe de processus (survit au
///     kill du parent).
///   - `stdio: 'ignore'` : pas de partage de flux I/O.
///   - `unref()` : l'event loop de Node.js ne bloque pas sur ce
///     processus enfant.
///
/// Si Caddy n'est pas installé, un avertissement est loggué sans
/// faire crasher le serveur Node.js. Le chemin du Caddyfile est
/// relatif au répertoire `server/`.
function launchCaddyIndependent() {
  // Résolution du chemin du Caddyfile.
  // `__dirname` pointe vers `server/src/`, donc `../Caddyfile` remonte
  // dans `server/`.
  const caddyfilePath = path.join(__dirname, '..', 'Caddyfile');

  try {
    const caddyProcess = spawn('caddy', [
      'run',
      '--config', caddyfilePath,
      '--adapter', 'caddyfile',
    ], {
      detached: true,
      stdio: 'ignore',
      // `windowsHide: true` évite un flash de console sur Windows.
      windowsHide: true,
    });

    caddyProcess.unref();

    // On laisse un court délai pour que Caddy ait le temps de
    // rapporter une erreur de démarrage (port occupé, config
    // invalide, etc.) avant de considérer qu'il est lancé.
    caddyProcess.on('error', (err) => {
      // `error` n'est émis qu'avant `unref()` ne détache le processus
      // (ex: exécutable introuvable, permission refusée).
      log('CADDY', `❌ Échec lancement : ${err.message}`);
      log('CADDY', '  Vérifiez que Caddy est installé et que le Caddyfile est valide.');
    });

    // Petite temporisation pour que l'event 'error' ait le temps
    // d'être émis si Caddy n'est pas trouvé.
    setTimeout(() => {
      if (caddyProcess.exitCode === null && !caddyProcess.killed) {
        log('CADDY', '✅ Démon Caddy lancé (détaché)');
      } else if (caddyProcess.exitCode !== null) {
        log('CADDY', `⚠ Caddy s'est arrêté (code ${caddyProcess.exitCode})`);
        log('CADDY', '  Le serveur Node.js fonctionne sans TLS.');
      }
    }, 1500);
  } catch (err) {
    log('CADDY', `⚠ Impossible de lancer Caddy : ${err.message}`);
    log('CADDY', '  Le serveur Node.js fonctionne sans TLS.');
  }
}

module.exports = app;