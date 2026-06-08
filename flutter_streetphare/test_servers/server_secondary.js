// test_servers/server_secondary.js
//
// SERVEUR SECONDAIRE (backup #1) de test StreetPhare.
// Port : 3001
//
// Mêmes routes que le serveur principal, mais avec un port
// différent et un "next backup" pointant vers un éventuel serveur
// tertiaire (port 3002 par défaut, ou rien du tout si on n'en
// lance pas).
//
// Le but : si on coupe le serveur principal (port 3000), le
// FailoverManager (lib/network/failover_manager.dart) doit
// basculer automatiquement sur ce serveur (port 3001) après
// 3 heartbeats échoués.

const express = require('express');
const { encryptAddress } = require('./server_crypto');

const app = express();
app.use(express.json({ limit: '1mb' }));

// ----- Configuration -----
const PORT = parseInt(process.env.PORT || '3001', 10);
const ROLE = process.env.ROLE || 'secondary';
const MASTER_PASSPHRASE =
  process.env.STREETPHARE_MASTER_KEY || 'streetphare-dev-key-CHANGE_ME_IN_PROD';
// Le serveur secondaire pointe (par défaut) vers un 3e serveur
// de test (3002) — laissez vide pour ne pas en avoir.
const NEXT_BACKUP_CLEAR =
  process.env.NEXT_BACKUP_URL || 'http://localhost:3002';

// Logger de tableau de bord (SERVER_STATUS.md) — facultatif
// (activé par défaut, peut être coupé via STREETPHARE_LOG=0).
const dash = (() => {
  if (process.env.STREETPHARE_LOG === '0') {
    const noop = () => {};
    return { init: noop, pingReceived: noop, alertReceived: noop, consensusReached: noop, promoted: noop, demoted: noop, setCurrentRole: noop, setOnline: noop, failoverTriggered: noop, backupRequested: noop, broadcastEvent: noop, mergeNode: noop, getOutputFile: () => null, getState: () => ({}) };
  }
  return require('./logger');
})();

// Initialisation du logger de tableau de bord.
dash.init({
  role: ROLE,
  port: PORT,
  name: 'Backup 1',
  url: `http://localhost:${PORT}`,
});

// ----- État en mémoire -----
const alertStore = new Map();

function ensureAlert(id, payload) {
  if (!alertStore.has(id)) {
    alertStore.set(id, {
      payload: payload || null,
      confirmations: new Set(),
      validatedAt: null,
    });
  }
  return alertStore.get(id);
}

function log(...args) {
  const ts = new Date().toISOString();
  console.log(`[${ts}][secondary:${PORT}]`, ...args);
}

// ----- Routes -----

// 1) Heartbeat générique (spec)
app.get('/ping', (_req, res) => {
  dash.pingReceived('GET /ping (spec)');
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// 2) Heartbeat utilisé par FailoverManager
app.get('/healthz', (_req, res) => {
  dash.pingReceived('GET /healthz (FailoverManager)');
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// Helper de journalisation dashboard (miroir du primary).
function notifyAlertChange(id, payload, newVoteCount) {
  dash.alertReceived(id, payload, newVoteCount, 3);
  if (newVoteCount >= 3) {
    dash.consensusReached(id, payload);
  }
}

// 3) Réception d'alerte (consensus 3)
app.post('/alerts', (req, res) => {
  const body = req.body || {};
  if (body && typeof body.id === 'string') {
    return handleSpecAlert(body, res);
  }
  if (Array.isArray(body.alerts)) {
    const results = body.alerts.map(handleAlertPayload);
    return res.json({ ok: true, results });
  }
  return res
    .status(400)
    .json({ error: 'format invalide (attendu: {id,...} ou {alerts:[...]})' });
});

function handleSpecAlert(body, res) {
  const id = body.id;
  const confirmations = Array.isArray(body.confirmations)
    ? body.confirmations
    : [];
  const entry = ensureAlert(id, body);
  const wasValidated = !!entry.validatedAt;
  for (const c of confirmations) entry.confirmations.add(c);
  if (entry.confirmations.size >= 3 && !entry.validatedAt) {
    entry.validatedAt = new Date().toISOString();
    log(`ALERTE VALIDÉE (consensus 3) -> id=${id}`);
    notifyAlertChange(id, entry.payload, entry.confirmations.size);
    return res.json({ status: 'stored', id, consensus: true });
  }
  log(
    `alerte en cours de validation id=${id} ` +
      `(${entry.confirmations.size}/3)`,
  );
  if (!wasValidated) {
    notifyAlertChange(id, entry.payload, entry.confirmations.size);
  }
  return res.json({
    status: 'pending',
    id,
    confirmations: entry.confirmations.size,
  });
}

function handleAlertPayload(a) {
  if (!a || typeof a.id !== 'string') {
    return { id: a && a.id, ok: false, reason: 'id manquant' };
  }
  const entry = ensureAlert(a.id, a);
  const confs = Array.isArray(a.confirmations) ? a.confirmations : [];
  for (const c of confs) entry.confirmations.add(c);
  const validated =
    entry.confirmations.size >= 3 && !entry.validatedAt;
  const wasValidated = !!entry.validatedAt;
  if (validated) entry.validatedAt = new Date().toISOString();
  if (!wasValidated) {
    notifyAlertChange(a.id, entry.payload, entry.confirmations.size);
  }
  return {
    id: a.id,
    ok: true,
    consensus: validated,
    confirmations: entry.confirmations.size,
  };
}

// 4) Endpoint RÉEL utilisé par FailoverManager.uploadAlerts
app.post('/v1/alerts/sync', (req, res) => {
  const body = req.body || {};
  const results = Array.isArray(body.alerts)
    ? body.alerts.map(handleAlertPayload)
    : [];
  // Si on a un 3e serveur configuré, on en chiffre l'adresse ;
  // sinon on renvoie une chaîne vide (le client n'ajoutera rien).
  const nextBackupCipher = NEXT_BACKUP_CLEAR
    ? encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE)
    : '';
  log(
    `sync reçu : ${results.length} alerte(s) ; ` +
      `next_backup=${NEXT_BACKUP_CLEAR || '(aucun)'}`,
  );
  dash.broadcastEvent(
    'SYNC',
    '🔄',
    'Synchronisation alertes',
    `${results.length} alerte(s) reçue(s) sur le backup`,
  );
  res.json({
    ok: true,
    server: `http://localhost:${PORT}`,
    next_backup: nextBackupCipher,
    results,
  });
});

// 5) Backup route (spec)
app.get('/backup-route', (_req, res) => {
  if (!NEXT_BACKUP_CLEAR) {
    return res.json({
      next: null,
      encrypted_next: '',
      algorithm: 'AES-256-CBC+HMAC-SHA256',
      note: 'pas de serveur tertiaire configuré',
    });
  }
  const cipher = encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE);
  log(`backup-route demandé -> ${NEXT_BACKUP_CLEAR} (chiffré)`);
  dash.backupRequested(cipher);
  res.json({
    next: NEXT_BACKUP_CLEAR,
    encrypted_next: cipher,
    algorithm: 'AES-256-CBC+HMAC-SHA256',
  });
});

// 6b) Endpoint de promotion (admin / test) : permet de
//     simuler la promotion de ce secondaire au rang de
//     principal (utile pour valider visuellement le tableau
//     de bord). Le serveur devient "Actif".
app.post('/_debug/promote', (req, res) => {
  const reason = (req.body && req.body.reason) || 'Promotion manuelle';
  log(`PROMOTION demandée : ${reason}`);
  dash.promoted('Promu Principal');
  res.json({ ok: true, promoted: true, reason });
});

// 6c) Endpoint de démission (admin / test).
app.post('/_debug/demote', (req, res) => {
  const reason = (req.body && req.body.reason) || 'Démission manuelle';
  log(`DÉMITION demandée : ${reason}`);
  dash.demoted(reason);
  setTimeout(() => process.exit(0), 200);
  res.json({ ok: true, demoted: true, reason });
});

// 6) Debug
app.get('/_debug/store', (_req, res) => {
  const out = [];
  for (const [id, e] of alertStore.entries()) {
    out.push({
      id,
      confirmations: e.confirmations.size,
      validatedAt: e.validatedAt,
    });
  }
  res.json({ count: alertStore.size, alerts: out });
});

// ----- Démarrage -----
app.listen(PORT, () => {
  log(
    `SERVEUR SECONDAIRE démarré sur http://localhost:${PORT} ` +
      `(next_backup=${NEXT_BACKUP_CLEAR || '(aucun)'})`,
  );
});
