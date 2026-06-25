// server/src/sync.js
// Module de synchronisation automatique entre le serveur Primary et Backup.
//
// Mécanismes :
//   1. Push immédiat : dès qu'une alerte/événement est créé ou mis à jour
//      sur le Primary, il est envoyé immédiatement au Backup via POST.
//   2. Hash polling (toutes les N secondes) : le Primary envoie un hash
//      de son état. Si le Backup détecte une divergence, il demande un
//      dump complet pour se remettre à jour.

const config = require('./config');
const store = require('./store');
const https = require('https');
const http = require('http');

const fetch = (url, options) => {
  return new Promise((resolve, reject) => {
    const { protocol } = new URL(url);
    const client = protocol === 'https:' ? https : http;

    const req = client.request(url, { ...options, timeout: 5000 }, (res) => {
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
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    if (options.body) req.write(JSON.stringify(options.body));
    req.end();
  });
};

/// Push immédiat d'une alerte vers le Backup.
async function pushAlert(alert) {
  if (!config.isPrimary) return false;
  try {
    const res = await fetch(`${config.partnerUrl}/api/sync/alert`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { alert, from: config.serverType },
    });
    return res.status === 200;
  } catch (e) {
    console.warn(`[Sync] Push alert ${alert.id} failed: ${e.message}`);
    return false;
  }
}

/// Push immédiat d'un événement vers le Backup.
async function pushEvent(event) {
  if (!config.isPrimary) return false;
  try {
    const res = await fetch(`${config.partnerUrl}/api/sync/event`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { event, from: config.serverType },
    });
    return res.status === 200;
  } catch (e) {
    console.warn(`[Sync] Push event ${event.code} failed: ${e.message}`);
    return false;
  }
}

/// Hash polling : le Primary envoie son hash ; le Backup vérifie.
// TODO: Sync — logger l'URL exacte (IP:port) du partenaire en cas d'échec de polling
async function pollSync() {
  const hash = store.getStateHash();
  try {
    const res = await fetch(`${config.partnerUrl}/api/sync/check`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: { hash, from: config.serverType },
    });

    if (res.status === 200 && res.body && res.body.action === 'full_sync') {
      console.log('[Sync] Désynchronisation détectée — dump complet demandé.');
      // Le Primary dump tout son état et l'envoie au Backup.
      const dump = store.exportAll();
      await fetch(`${config.partnerUrl}/api/sync/full`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: { dump, from: config.serverType },
      });
    }

    store.syncState.lastSyncAt = new Date().toISOString();
    store.syncState.lastSyncSuccess = true;
  } catch (e) {
    store.syncState.lastSyncSuccess = false;
    console.warn(`[Sync] Polling failed: ${e.message}`);
  }
}

/// Reçoit un dump complet et importe.
function receiveFullSync(dump) {
  store.importAll(dump);
  store.syncState.lastSyncAt = new Date().toISOString();
  store.syncState.lastSyncSuccess = true;
  console.log(`[Sync] Full sync received — ${dump.alerts?.length || 0} alerts, ${dump.events?.length || 0} events`);
}

/// Vérifie si un hash distant diffère du hash local.
function checkHash(remoteHash) {
  const localHash = store.getStateHash();
  return localHash !== remoteHash;
}

module.exports = {
  pushAlert,
  pushEvent,
  pollSync,
  receiveFullSync,
  checkHash,
};