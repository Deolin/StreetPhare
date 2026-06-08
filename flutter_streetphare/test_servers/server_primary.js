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
  res.json({ status: 'ok', role: ROLE, ts: Date.now() });
});

// 2) Heartbeat réellement utilisé par FailoverManager.dart
app.get('/healthz', (_req, res) => {
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

function handleSpecAlert(body, res) {
  const id = body.id;
  const confirmations = Array.isArray(body.confirmations)
    ? body.confirmations
    : [];
  const entry = ensureAlert(id, body);
  for (const c of confirmations) entry.confirmations.add(c);
  if (entry.confirmations.size >= 3 && !entry.validatedAt) {
    entry.validatedAt = new Date().toISOString();
    log(`ALERTE VALIDÉE (consensus 3) -> id=${id}`);
    return res.json({ status: 'stored', id, consensus: true });
  }
  log(
    `alerte en cours de validation id=${id} ` +
      `(${entry.confirmations.size}/3)`,
  );
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
  if (validated) entry.validatedAt = new Date().toISOString();
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
  res.json({
    ok: true,
    server: `http://localhost:${PORT}`,
    next_backup: nextBackupCipher,
    results,
  });
});

// 5) Route de basculement : renvoie l'adresse CHIFFRÉE du
//    PROCHAIN serveur de secours (cf. spec).
app.get('/backup-route', (_req, res) => {
  const cipher = encryptAddress(NEXT_BACKUP_CLEAR, MASTER_PASSPHRASE);
  log(`backup-route demandé -> ${NEXT_BACKUP_CLEAR} (chiffré)`);
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
