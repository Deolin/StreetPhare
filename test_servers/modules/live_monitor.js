// test_servers/modules/live_monitor.js
//
// MONITEUR TEMPS RÉEL — Hub WebSocket central de StreetPhare
// ============================================================
//
// Ce module capture TOUS les événements internes des serveurs
// (requêtes HTTP, messages mesh P2P, signalements, logs d'erreurs,
//  changements d'état, heartbeat) et les diffuse en temps réel
// via WebSocket à tous les clients abonnés (Dashboard NOC/Ops).
//
// Architecture :
//   - Un EventEmitter interne collecte tous les événements.
//   - Un serveur WebSocket (ws) expose le flux sur un port dédié
//     (par défaut 4001) ou peut être attaché à un http.Server existant.
//   - Les clients reçoivent un flux JSON-NL (un objet JSON par ligne).
//   - Un tampon circulaire conserve les 500 derniers événements
//     pour les clients qui se connectent en cours de session.
//
// Utilisation :
//   const monitor = require('./modules/live_monitor');
//   monitor.init({ port: 4001 });  // port dédié
//   // ou
//   monitor.attach(httpServer);     // sur un serveur HTTP existant (chemin /_monitor)
//
//   // Dans les gestionnaires de requêtes :
//   monitor.emit('http_request', { method: 'GET', path: '/ping', clientIp: '...' });
//   monitor.emit('mesh_message', { peerId: 'abc', payload: '...' });
//   monitor.emit('report', { id: 'x', type: 'barrage', votes: 3 });
//   monitor.emit('error', { source: 'primary', message: '...' });
//   monitor.emit('state_change', { server: 'primary', from: 'active', to: 'demoted' });
//   monitor.emit('heartbeat', { server: 'primary', ts: Date.now() });

'use strict';

const { EventEmitter } = require('events');
const { WebSocketServer, WebSocket } = require('ws');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const MAX_BUFFER_SIZE = 500;       // Nombre max d'événements conservés en tampon
const DEFAULT_PORT = 4001;         // Port WebSocket dédié pour le monitoring
const HEARTBEAT_INTERVAL_MS = 5000; // Ping/Keep-Alive toutes les 5 secondes

// ---------------------------------------------------------------------------
// Bus d'événements interne
// ---------------------------------------------------------------------------
const bus = new EventEmitter();
bus.setMaxListeners(200);

// Tampon circulaire des derniers événements
const eventBuffer = [];
let eventSequence = 0;

// Ensemble des clients WebSocket connectés
const clients = new Set();

// Statistiques globales
const stats = {
  httpRequestsTotal: 0,
  meshMessagesTotal: 0,
  reportsTotal: 0,
  errorsTotal: 0,
  stateChangesTotal: 0,
  heartbeatsTotal: 0,
  startTime: new Date(),
  requestsByPath: new Map(),
  reportsByType: new Map(),
  lastActivity: null,
};

// Compteurs par serveur
const serverStats = new Map(); // serverName → { online, lastHeartbeat, role, port }

// ---------------------------------------------------------------------------
// Fonctions internes
// ---------------------------------------------------------------------------

/**
 * Ajoute un événement au tampon circulaire et le diffuse à tous les clients.
 * @param {string} type - Type d'événement (http_request, mesh_message, report, error, state_change, heartbeat, etc.)
 * @param {object} data - Données de l'événement
 */
function pushEvent(type, data) {
  eventSequence++;
  const event = {
    seq: eventSequence,
    type,
    ts: new Date().toISOString(),
    data,
  };

  // Ajout au tampon circulaire
  eventBuffer.push(event);
  if (eventBuffer.length > MAX_BUFFER_SIZE) {
    eventBuffer.shift();
  }

  // Mise à jour des statistiques
  updateStats(type, data);

  // Diffusion à tous les clients connectés
  const payload = JSON.stringify(event);
  for (const ws of clients) {
    if (ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(payload);
      } catch (_) {
        clients.delete(ws);
      }
    }
  }
}

/**
 * Met à jour les compteurs de statistiques en fonction du type d'événement.
 */
function updateStats(type, data) {
  stats.lastActivity = new Date();

  switch (type) {
    case 'http_request':
      stats.httpRequestsTotal++;
      if (data.path) {
        const count = stats.requestsByPath.get(data.path) || 0;
        stats.requestsByPath.set(data.path, count + 1);
      }
      break;
    case 'mesh_message':
      stats.meshMessagesTotal++;
      break;
    case 'report':
      stats.reportsTotal++;
      if (data.type) {
        const count = stats.reportsByType.get(data.type) || 0;
        stats.reportsByType.set(data.type, count + 1);
      }
      break;
    case 'error':
      stats.errorsTotal++;
      break;
    case 'state_change':
      stats.stateChangesTotal++;
      break;
    case 'heartbeat':
      stats.heartbeatsTotal++;
      if (data.server) {
        const s = serverStats.get(data.server) || {};
        s.lastHeartbeat = new Date().toISOString();
        s.online = true;
        if (data.role) s.role = data.role;
        if (data.port) s.port = data.port;
        serverStats.set(data.server, s);
      }
      break;
  }
}

// ---------------------------------------------------------------------------
// API publique — Émission d'événements
// ---------------------------------------------------------------------------

/**
 * Émet un événement dans le flux temps réel.
 * @param {string} type - Catégorie d'événement
 * @param {object} data - Données associées
 */
function emit(type, data = {}) {
  pushEvent(type, data);
  bus.emit(type, data);
}

/**
 * Enregistre une requête HTTP entrante.
 * @param {object} reqInfo - { method, path, clientIp, server, statusCode?, durationMs? }
 */
function logHttpRequest(reqInfo) {
  emit('http_request', {
    method: reqInfo.method || 'GET',
    path: reqInfo.path || '/',
    clientIp: reqInfo.clientIp || '127.0.0.1',
    server: reqInfo.server || 'unknown',
    statusCode: reqInfo.statusCode || null,
    durationMs: reqInfo.durationMs || null,
  });
}

/**
 * Enregistre un message relayé via le mesh P2P.
 * @param {object} msgInfo - { peerId, direction, payloadSize, server }
 */
function logMeshMessage(msgInfo) {
  emit('mesh_message', {
    peerId: msgInfo.peerId || 'unknown',
    direction: msgInfo.direction || 'relay',
    payloadSize: msgInfo.payloadSize || 0,
    server: msgInfo.server || 'unknown',
  });
}

/**
 * Enregistre un signalement (report) reçu ou mis à jour.
 * @param {object} reportInfo - { id, type, votes, action }
 */
function logReport(reportInfo) {
  emit('report', {
    id: reportInfo.id || '?',
    type: reportInfo.type || 'inconnu',
    votes: reportInfo.votes || 0,
    action: reportInfo.action || 'received',
    distributed: reportInfo.distributed || false,
    server: reportInfo.server || 'unknown',
  });
}

/**
 * Enregistre une erreur.
 * @param {object} errInfo - { source, message, stack, server }
 */
function logError(errInfo) {
  emit('error', {
    source: errInfo.source || 'unknown',
    message: errInfo.message || '',
    stack: errInfo.stack || null,
    server: errInfo.server || 'unknown',
  });
}

/**
 * Enregistre un changement d'état (promotion, démotion, failover).
 * @param {object} stateInfo - { server, from, to, reason }
 */
function logStateChange(stateInfo) {
  emit('state_change', {
    server: stateInfo.server || 'unknown',
    from: stateInfo.from || 'unknown',
    to: stateInfo.to || 'unknown',
    reason: stateInfo.reason || '',
  });
  // Mise à jour du registre des serveurs
  const s = serverStats.get(stateInfo.server) || {};
  s.role = stateInfo.to;
  s.lastStateChange = new Date().toISOString();
  serverStats.set(stateInfo.server, s);
}

/**
 * Enregistre un heartbeat.
 * @param {object} hbInfo - { server, role, port }
 */
function logHeartbeat(hbInfo) {
  emit('heartbeat', {
    server: hbInfo.server || 'unknown',
    role: hbInfo.role || 'unknown',
    port: hbInfo.port || 0,
  });
}

// ---------------------------------------------------------------------------
// API publique — Abonnement (pour usage programmatique)
// ---------------------------------------------------------------------------

/**
 * S'abonne à un type d'événement spécifique.
 * @param {string} eventType
 * @param {function} handler
 */
function on(eventType, handler) {
  bus.on(eventType, handler);
}

/**
 * Se désabonne d'un type d'événement.
 */
function off(eventType, handler) {
  bus.off(eventType, handler);
}

// ---------------------------------------------------------------------------
// API publique — Récupération d'état
// ---------------------------------------------------------------------------

/**
 * Retourne un snapshot complet de l'état du moniteur.
 */
function getSnapshot() {
  return {
    stats: {
      ...stats,
      requestsByPath: Object.fromEntries(stats.requestsByPath),
      reportsByType: Object.fromEntries(stats.reportsByType),
      uptimeSeconds: Math.floor((Date.now() - stats.startTime.getTime()) / 1000),
    },
    servers: Object.fromEntries(serverStats),
    connectedClients: clients.size,
    bufferSize: eventBuffer.length,
    lastSequence: eventSequence,
  };
}

/**
 * Retourne les N derniers événements du tampon.
 * @param {number} count - Nombre d'événements (défaut: 50)
 */
function getRecentEvents(count = 50) {
  return eventBuffer.slice(-Math.min(count, eventBuffer.length));
}

// ---------------------------------------------------------------------------
// API publique — Initialisation du serveur WebSocket
// ---------------------------------------------------------------------------

let wss = null;
let heartbeatInterval = null;

/**
 * Démarre le serveur WebSocket de monitoring sur un port dédié.
 * @param {object} opts - { port: number }
 * @returns {WebSocketServer}
 */
function init(opts = {}) {
  const port = opts.port || DEFAULT_PORT;

  _setupWss(new WebSocketServer({ port }));

  console.log(`[LiveMonitor] ✅ WebSocket démarré sur ws://localhost:${port}`);
  emit('_system', { message: 'Moniteur temps réel démarré', port });

  return wss;
}

/**
 * Configure le WebSocketServer en mode noServer (sans port TCP).
 * À utiliser quand le handler upgrade est géré manuellement par
 * le serveur HTTP hôte (ex: fusion /mesh + /_monitor).
 *
 * @returns {WebSocketServer}
 */
function configureNoServer() {
  if (wss) {
    console.warn('[LiveMonitor] Déjà initialisé.');
    return wss;
  }

  _setupWss(new WebSocketServer({ noServer: true }));

  console.log('[LiveMonitor] ✅ WebSocket configuré en mode noServer');
  emit('_system', { message: 'Moniteur configuré en mode noServer' });

  return wss;
}

/**
 * Attache le WebSocket de monitoring à un serveur HTTP existant.
 * ⚠️  ATTENTION : cette méthode enregistre son propre handler 'upgrade'
 *     et détruira les sockets non-/monitor. Pour une cohabitation
 *     avec d'autres WebSocket sur le même httpServer, utilisez plutôt
 *     configureNoServer() + getWss() et gérez le dispatch dans votre
 *     propre handler upgrade unifié.
 *
 * @param {http.Server} httpServer - Serveur HTTP Node.js
 */
function attach(httpServer) {
  configureNoServer();

  httpServer.on('upgrade', (req, socket, head) => {
    const pathname = new URL(req.url, `http://localhost`).pathname;
    if (pathname === '/_monitor') {
      wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req);
      });
    } else {
      socket.destroy();
    }
  });

  console.log('[LiveMonitor] ✅ WebSocket attaché sur /_monitor');
  emit('_system', { message: 'Moniteur temps réel attaché au serveur HTTP' });

  return wss;
}

/**
 * Initialise la logique de connexion/déconnexion/commandes sur le wss.
 * Fonction interne partagée par init() et configureNoServer().
 */
function _setupWss(server) {
  if (wss) {
    console.warn('[LiveMonitor] Déjà initialisé.');
    return;
  }
  wss = server;

  wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress || 'inconnu';
    clients.add(ws);
    console.log(`[LiveMonitor] +client ${clientIp} (total: ${clients.size})`);

    // Envoi de l'état initial (snapshot + derniers événements)
    const welcome = {
      type: '_welcome',
      snapshot: getSnapshot(),
      recentEvents: getRecentEvents(100),
    };
    try {
      ws.send(JSON.stringify(welcome));
    } catch (_) {}

    ws.on('close', () => {
      clients.delete(ws);
      console.log(`[LiveMonitor] -client ${clientIp} (total: ${clients.size})`);
    });

    ws.on('error', (err) => {
      console.error(`[LiveMonitor] Erreur WebSocket ${clientIp}: ${err.message}`);
      clients.delete(ws);
    });

    ws.on('message', (raw) => {
      let cmd;
      try {
        cmd = JSON.parse(raw.toString());
      } catch (_) {
        return;
      }
      handleClientCommand(ws, cmd);
    });
  });

  // Heartbeat périodique
  if (heartbeatInterval) clearInterval(heartbeatInterval);
  heartbeatInterval = setInterval(() => {
    for (const ws of clients) {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.ping();
        } catch (_) {
          clients.delete(ws);
        }
      }
    }
  }, HEARTBEAT_INTERVAL_MS);
}

/**
 * Arrête le serveur WebSocket.
 */
function shutdown() {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval);
    heartbeatInterval = null;
  }
  if (wss) {
    for (const ws of clients) {
      try {
        ws.close();
      } catch (_) {}
    }
    clients.clear();
    wss.close();
    wss = null;
    console.log('[LiveMonitor] Arrêté.');
  }
}

// ---------------------------------------------------------------------------
// Traitement des commandes client
// ---------------------------------------------------------------------------

const commandHandlers = new Map();

/**
 * Enregistre un gestionnaire de commande.
 * @param {string} command - Nom de la commande
 * @param {function} handler - Fonction(ws, params) → résultat
 */
function registerCommand(command, handler) {
  commandHandlers.set(command, handler);
}

function handleClientCommand(ws, cmd) {
  const { command, params } = cmd;
  if (!command) return;

  const handler = commandHandlers.get(command);
  if (handler) {
    try {
      const result = handler(ws, params || {});
      if (result !== undefined) {
        ws.send(JSON.stringify({
          type: '_command_result',
          command,
          result,
          ts: new Date().toISOString(),
        }));
      }
    } catch (e) {
      ws.send(JSON.stringify({
        type: '_command_error',
        command,
        error: e.message,
        ts: new Date().toISOString(),
      }));
    }
  } else {
    ws.send(JSON.stringify({
      type: '_command_error',
      command,
      error: `Commande inconnue: ${command}`,
      ts: new Date().toISOString(),
    }));
  }
}

// Commandes intégrées
registerCommand('get_snapshot', () => getSnapshot());
registerCommand('get_recent_events', (_ws, params) => getRecentEvents(params.count || 50));
registerCommand('ping', () => ({ pong: true, ts: new Date().toISOString() }));

/**
 * Expose le WebSocketServer interne pour intégration dans
 * un handler upgrade personnalisé (cohabitation avec d'autres
 * WebSocket sur le même httpServer).
 * @returns {WebSocketServer|null}
 */
function getWss() {
  return wss;
}

// ---------------------------------------------------------------------------
// Export du module
// ---------------------------------------------------------------------------
module.exports = {
  // Émission
  emit,
  logHttpRequest,
  logMeshMessage,
  logReport,
  logError,
  logStateChange,
  logHeartbeat,

  // Abonnement
  on,
  off,

  // État
  getSnapshot,
  getRecentEvents,

  // Cycle de vie
  init,
  configureNoServer,
  attach,
  shutdown,
  registerCommand,
  getWss,
  isInitialized: () => wss !== null,
};
