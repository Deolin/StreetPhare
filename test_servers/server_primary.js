// test_servers/server_primary.js
//
// SERVEUR PRINCIPAL de test StreetPhare.
// Port : 3000
//
// Routes exposées :
//   GET  /ping            -> heartbeat (spec demandée)
//   GET  /healthz         -> alias /ping (utilisé par FailoverManager)
//   POST /alerts          -> reçoit une alerte. Si 3 validations -> stored
//   POST /v1/alerts/sync  -> endpoint RÉEL attendu par le client Flutter
//                            (retourne {ok, server, next_backup})
//   GET  /backup-route    -> renvoie l'adresse CHIFFRÉE du prochain
//                            serveur de secours (chaine de basculement)
//
// Le serveur maintient en mémoire la liste des validations par
// alerte : à la 3e confirmation reçue, l'alerte est considérée
// "validée par consensus" et enregistrée (ici en RAM, c'est un
// environnement de test).
//
// IMPORTANT : ce serveur est volontairement minimaliste. Il sert
// uniquement à valider le routage / failover / consensus du client
// Flutter en environnement local.

// Logger de tableau de bord (SERVER_STATUS.md) — facultatif
// (activé par défaut, peut être coupé via STREETPHARE_LOG=0).
// `dash` (Dashboard) est le logger Markdown ; `print` est la
// fonction console historique (pour ne pas se télescoper avec
// le nom `log`).
const dash = (() => {
  if (process.env.STREETPHARE_LOG === '0') {
    const noop = () => {};
    return { init: noop, pingReceived: noop, alertReceived: noop, consensusReached: noop, promoted: noop, demoted: noop, setCurrentRole: noop, setOnline: noop, failoverTriggered: noop, backupRequested: noop, broadcastEvent: noop, mergeNode: noop, getOutputFile: () => null, getState: () => ({}) };
  }
  return require('./logger');
})();

const express = require('express');
const path = require('path');
const { encryptAddress } = require('./server_crypto');

const app = express();
app.use(express.json({ limit: '1mb' }));

// ----- Configuration -----
const PORT = parseInt(process.env.PORT || '3000', 10);
const ROLE = process.env.ROLE || 'primary';
const MASTER_PASSPHRASE =
  process.env.STREETPHARE_MASTER_KEY || 'streetphare-dev-key-CHANGE_ME_IN_PROD';
// Chaîne de secours : le primary pointe vers le secondary.
// En production, ces valeurs sont injectées par le serveur de build.
const NEXT_BACKUP_CLEAR =
  process.env.NEXT_BACKUP_URL || 'http://localhost:3001';

// Initialisation du logger de tableau de bord.
dash.init({
  role: ROLE,
  port: PORT,
  name: 'Principal',
  url: `http://localhost:${PORT}`,
});

// ----- État en mémoire (volontairement simple) -----
/**
 * Map<alertId, { payload, confirmations: Set<peerId>, validatedAt }>
 */
const alertStore = new Map();

// ----- Helpers -----
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
  // Log horodaté pour faciliter le debug en parallèle du client.
  const ts = new Date().toISOString();
  console.log(`[${ts}][primary:${PORT}]`, ...args);
}

// ----- Routes -----

// 1) Heartbeat générique demandé par la spec
app.get('/ping', (_req, res) => {
  dash.pingReceived('GET /ping (spec)');
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// 2) Heartbeat réellement utilisé par FailoverManager.dart
app.get('/healthz', (_req, res) => {
  dash.pingReceived('GET /healthz (FailoverManager)');
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// 3) Réception d'alerte avec logique de consensus (3 validations)
//    Le client peut envoyer deux formats :
//      a) { id, confirmations: [...] }            (spec de la tâche)
//      b) { alerts: [ { id, confirmations: [...] } ] }
//         (format réel envoyé par FailoverManager.uploadAlerts)
app.post('/alerts', (req, res) => {
  const body = req.body || {};
  if (kIsSpecFormat(body)) {
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

function kIsSpecFormat(body) {
  return body && typeof body.id === 'string';
}

// Helper de journalisation dashboard : appelé à chaque mutation
// d'une alerte (réception / vote / consensus) pour mettre à
// jour SERVER_STATUS.md. `applyConsensus` distingue le passage
// de "pending" à "stored" pour émettre un event "CONSENSUS".
function notifyAlertChange(id, payload, newVoteCount) {
  dash.alertReceived(id, payload, newVoteCount, 3);
  if (newVoteCount >= 3) {
    dash.consensusReached(id, payload);
  }
}

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
    // évite de re-notifier à chaque heartbeat client
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
  const confs = Array.isArray(a.confirmations)
    ? a.confirmations
    : [];
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
//    Format renvoyé : { ok, server, next_backup }
//    - server : adresse publique de ce serveur
//    - next_backup : adresse du serveur de secours CHIFFRÉE (AES)
//      que le client stockera en queue de chaîne.
app.post('/v1/alerts/sync', (req, res) => {
  const body = req.body || {};
  const results = Array.isArray(body.alerts)
    ? body.alerts.map(handleAlertPayload)
    : [];
  // On chiffre la prochaine URL de backup pour le client.
  const nextBackupCipher = encryptAddress(
    NEXT_BACKUP_CLEAR,
    MASTER_PASSPHRASE,
  );
  log(
    `sync reçu : ${results.length} alerte(s) ; ` +
      `next_backup=${NEXT_BACKUP_CLEAR} (cipher_len=${nextBackupCipher.length})`,
  );
  dash.broadcastEvent(
    'SYNC',
    '🔄',
    'Synchronisation alertes',
    `${results.length} alerte(s) reçue(s) ; backup chiffré prêt`,
  );
  res.json({
    ok: true,
    server: `http://localhost:${PORT}`,
    next_backup: nextBackupCipher,
    results,
  });
});

// 6b) Endpoint de basculement (admin / test) : permet au
//     client (ou à un script de test) d'indiquer au serveur
//     qu'il doit se démettre (par ex. pour tester le
//     failover). Le serveur passe alors en "Obsolète".
app.post('/_debug/demote', (req, res) => {
  const reason = (req.body && req.body.reason) || 'Démission manuelle';
  log(`DÉMITION demandée : ${reason}`);
  dash.demoted(reason);
  setTimeout(() => process.exit(0), 200); // coupe proprement
  res.json({ ok: true, demoted: true, reason });
});

// 5) Route de basculement : renvoie l'adresse CHIFFRÉE du
//    PROCHAIN serveur de secours (cf. spec).
app.get('/backup-route', (_req, res) => {
  const cipher = encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE);
  log(`backup-route demandé -> ${NEXT_BACKUP_CLEAR} (chiffré)`);
  dash.backupRequested(cipher);
  res.json({
    next: NEXT_BACKUP_CLEAR, // pratique pour debug en local
    encrypted_next: cipher, // ce que le client doit stocker
    algorithm: 'AES-256-CBC+HMAC-SHA256',
  });
});

// 6) Endpoint de debug : liste l'état du store
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
    `SERVEUR PRINCIPAL démarré sur http://localhost:${PORT} ` +
      `(next_backup=${NEXT_BACKUP_CLEAR})`,
  );
});
