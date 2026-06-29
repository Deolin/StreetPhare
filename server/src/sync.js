// server/src/sync.js
// Module de synchronisation automatique entre le serveur Primary et Backup.
//
// Mécanismes :
//   1. Outbox avec retry : les alertes/événements à répliquer sont placés
//      dans une file d'attente. En cas d'échec (Backup down), le système
//      retente automatiquement avec backoff exponentiel (1s → 2s → 4s,
//      max 3 tentatives). La file est flushée périodiquement toutes les
//      30 secondes.
//   2. Hash polling (toutes les N secondes) : le Primary envoie un hash
//      de son état. Si le Backup détecte une divergence, il demande un
//      dump complet pour se remettre à jour.
//
// Référence : docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md — Anomalie M10

const config = require('./config');
const store = require('./store');
const https = require('https');
const http = require('http');

// ── Outbox de synchronisation ────────────────────────────────────────────
// File d'attente pour les pushs vers le Backup. Chaque entrée :
//   { type: 'alert'|'event', id: string, payload: object,
//     attempts: number, nextRetry: number }
const outbox = [];
let outboxTimer = null;
const OUTBOX_FLUSH_INTERVAL_MS = 30000; // flush toutes les 30s
const OUTBOX_MAX_ATTEMPTS = 3;
const OUTBOX_BACKOFF_BASE_MS = 1000; // 1s → 2s → 4s

// ── Log helper formaté [HH:MM:SS - DD/MM] ──────────────────────────────
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

const fetch = (url, options) => {
  return new Promise((resolve, reject) => {
    const { protocol, hostname, port, pathname } = new URL(url);
    const client = protocol === 'https:' ? https : http;

    const reqOptions = {
      ...options,
      hostname,
      port: port || (protocol === 'https:' ? 443 : 80),
      path: pathname,
      timeout: 15000,
    };

    const req = client.request(reqOptions, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', (err) => reject(err));
    req.on('timeout', () => {
      req.destroy();
      reject(new Error(`timeout (15s) — ${url}`));
    });
    if (options.body) req.write(JSON.stringify(options.body));
    req.end();
  });
};

// ═══════════════════════════════════════════════════════════════════════════
// OUTBOX — File d'attente avec retry automatique
// ═══════════════════════════════════════════════════════════════════════════

/// Ajoute une alerte dans l'outbox pour réplication vers le Backup.
function enqueueAlert(alert) {
  if (!config.isPrimary) return;
  if (!alert || !alert.id) return;

  // Déduplication : si l'alerte est déjà en attente, on met à jour le
  // payload (fusion des votes) plutôt que de dupliquer.
  const existing = outbox.find(e => e.type === 'alert' && e.id === alert.id);
  if (existing) {
    existing.payload = alert;
    existing.attempts = 0;           // reset des tentatives
    existing.nextRetry = Date.now(); // retry immédiat
    log('OUTBOX', `Alerte ${alert.id} mise à jour dans l'outbox (déjà en attente)`);
    return;
  }

  outbox.push({
    type: 'alert',
    id: alert.id,
    payload: alert,
    attempts: 0,
    nextRetry: Date.now(), // immédiat
  });
  log('OUTBOX', `Alerte ${alert.id} ajoutée à l'outbox (taille: ${outbox.length})`);
}

/// Ajoute un événement dans l'outbox pour réplication vers le Backup.
function enqueueEvent(event) {
  if (!config.isPrimary) return;
  if (!event || !event.code) return;

  const existing = outbox.find(e => e.type === 'event' && e.id === event.code);
  if (existing) {
    existing.payload = event;
    existing.attempts = 0;
    existing.nextRetry = Date.now();
    log('OUTBOX', `Événement ${event.code} mis à jour dans l'outbox`);
    return;
  }

  outbox.push({
    type: 'event',
    id: event.code,
    payload: event,
    attempts: 0,
    nextRetry: Date.now(),
  });
  log('OUTBOX', `Événement ${event.code} ajouté à l'outbox (taille: ${outbox.length})`);
}

/// Tente d'envoyer un élément de l'outbox vers le Backup.
/// Retourne true en cas de succès, false si à réessayer plus tard.
async function _processOutboxItem(item) {
  try {
    const endpoint = item.type === 'alert' ? 'alert' : 'event';
    const url = `${config.partnerUrl}/api/sync/${endpoint}`;
    const bodyKey = item.type === 'alert' ? 'alert' : 'event';

    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { [bodyKey]: item.payload, from: config.serverType },
    });

    if (res.status >= 200 && res.status < 300) {
      log('OUTBOX', `✅ ${item.type} ${item.id} répliqué avec succès (tentative ${item.attempts + 1})`);
      return true; // succès → retirer de l'outbox
    } else {
      log('OUTBOX', `⚠ ${item.type} ${item.id} — statut HTTP ${res.status} (tentative ${item.attempts + 1})`);
      return false;
    }
  } catch (err) {
    log('OUTBOX', `❌ ${item.type} ${item.id} — échec réseau: ${err.message} (tentative ${item.attempts + 1})`);
    return false;
  }
}

/// Flush périodique de l'outbox : traite chaque entrée éligible.
async function flushOutbox() {
  if (outbox.length === 0) return;

  const now = Date.now();
  const toProcess = outbox.filter(item => item.nextRetry <= now);

  if (toProcess.length === 0) {
    log('OUTBOX', `${outbox.length} en attente, prochain retry dans ${Math.round((outbox[0].nextRetry - now) / 1000)}s`);
    return;
  }

  log('OUTBOX', `Flush — ${toProcess.length}/${outbox.length} éléments à traiter`);

  for (const item of toProcess) {
    const success = await _processOutboxItem(item);

    if (success) {
      // Retirer de l'outbox
      const idx = outbox.indexOf(item);
      if (idx !== -1) outbox.splice(idx, 1);
    } else {
      item.attempts++;
      if (item.attempts >= OUTBOX_MAX_ATTEMPTS) {
        // Abandon après N tentatives
        log('OUTBOX', `🚫 ${item.type} ${item.id} abandonné après ${OUTBOX_MAX_ATTEMPTS} tentatives`);
        const idx = outbox.indexOf(item);
        if (idx !== -1) outbox.splice(idx, 1);
      } else {
        // Backoff exponentiel : 1s, 2s, 4s
        const delay = OUTBOX_BACKOFF_BASE_MS * Math.pow(2, item.attempts - 1);
        item.nextRetry = Date.now() + delay;
        log('OUTBOX', `⏳ ${item.type} ${item.id} — retry dans ${delay / 1000}s (tentative ${item.attempts}/${OUTBOX_MAX_ATTEMPTS})`);
      }
    }
  }

  if (outbox.length > 0) {
    log('OUTBOX', `Flush terminé — ${outbox.length} restants dans l'outbox`);
  }
}

/// Démarre le timer de flush périodique de l'outbox.
function startOutbox() {
  if (outboxTimer) return;
  outboxTimer = setInterval(flushOutbox, OUTBOX_FLUSH_INTERVAL_MS);
  log('OUTBOX', `Démarré — flush toutes les ${OUTBOX_FLUSH_INTERVAL_MS / 1000}s`);
}

/// Arrête le timer de flush (graceful shutdown).
function stopOutbox() {
  if (outboxTimer) {
    clearInterval(outboxTimer);
    outboxTimer = null;
    log('OUTBOX', 'Arrêté');
  }
}

/// Taille actuelle de l'outbox (pour monitoring).
function outboxSize() {
  return outbox.length;
}

/// Dump de l'outbox (pour le endpoint /api/status).
function outboxDump() {
  return outbox.map(item => ({
    type: item.type,
    id: item.id,
    attempts: item.attempts,
    nextRetryMs: Math.max(0, item.nextRetry - Date.now()),
  }));
}

// ═══════════════════════════════════════════════════════════════════════════
// API PUBLIQUE (compatibilité ascendante)
// ═══════════════════════════════════════════════════════════════════════════

/// Push immédiat (direct, sans outbox) — conservé pour compatibilité.
/// Préférer `enqueueAlert()` / `enqueueEvent()` pour la fiabilité.
async function pushAlert(alert) {
  if (!config.isPrimary) return false;
  try {
    const url = `${config.partnerUrl}/api/sync/alert`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { alert, from: config.serverType },
    });
    if (res.status === 200) {
      log('SYNC', `Push direct alert ${alert.id} OK`);
      return true;
    }
    // Échec → fallback outbox
    log('SYNC', `Push direct alert ${alert.id} échoué (${res.status}) → outbox`);
    enqueueAlert(alert);
    return false;
  } catch (e) {
    log('SYNC', `Push direct alert ${alert.id} ÉCHEC: ${e.message} → outbox`);
    enqueueAlert(alert);
    return false;
  }
}

/// Push immédiat d'un événement vers le Backup.
async function pushEvent(event) {
  if (!config.isPrimary) return false;
  try {
    const url = `${config.partnerUrl}/api/sync/event`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { event, from: config.serverType },
    });
    if (res.status === 200) {
      log('SYNC', `Push direct event ${event.code} OK`);
      return true;
    }
    log('SYNC', `Push direct event ${event.code} échoué (${res.status}) → outbox`);
    enqueueEvent(event);
    return false;
  } catch (e) {
    log('SYNC', `Push direct event ${event.code} ÉCHEC: ${e.message} → outbox`);
    enqueueEvent(event);
    return false;
  }
}

/// Hash polling : le Primary envoie son hash ; le Backup vérifie.
async function pollSync() {
  const hash = store.getStateHash();
  try {
    const url = `${config.partnerUrl}/api/sync/check`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { hash, from: config.serverType },
    });

    if (res.status === 200 && res.body && res.body.action === 'full_sync') {
      log('SYNC', `Désynchronisation détectée — dump complet vers ${config.partnerUrl}`);
      const dump = store.exportAll();
      const fullUrl = `${config.partnerUrl}/api/sync/full`;
      await fetch(fullUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: { dump, from: config.serverType },
      });
      log('SYNC', `Full sync envoyé — ${dump.alerts?.length || 0} alerts, ${dump.events?.length || 0} events`);
    }

    store.syncState.lastSyncAt = new Date().toISOString();
    store.syncState.lastSyncSuccess = true;
  } catch (e) {
    store.syncState.lastSyncSuccess = false;
    log('SYNC', `Polling ÉCHEC: ${e.message} — cible: ${config.partnerUrl}`);
  }
}

/// Reçoit un dump complet et importe.
function receiveFullSync(dump) {
  store.importAll(dump);
  store.syncState.lastSyncAt = new Date().toISOString();
  store.syncState.lastSyncSuccess = true;
  log('SYNC', `Full sync reçu — ${dump.alerts?.length || 0} alerts, ${dump.events?.length || 0} events`);
}

/// Vérifie si un hash distant diffère du hash local.
function checkHash(remoteHash) {
  const localHash = store.getStateHash();
  return localHash !== remoteHash;
}

module.exports = {
  // API outbox (recommandée)
  enqueueAlert,
  enqueueEvent,
  startOutbox,
  stopOutbox,
  flushOutbox,
  outboxSize,
  outboxDump,
  // API directe (compatibilité ascendante)
  pushAlert,
  pushEvent,
  pollSync,
  receiveFullSync,
  checkHash,
};