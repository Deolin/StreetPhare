// test_servers/logger.js
//
// Module de journalisation "ultra-lisible" pour le tableau de bord
// de débogage StreetPhare.
//
// Génère (et écrase/complète) un fichier `SERVER_STATUS.md` à la
// racine du projet. Le fichier est mis à jour dynamiquement à
// chaque action (Ping, Alerte reçue, niveau de consensus atteint,
// basculement, etc.) pour permettre de suivre visuellement les
// tests de basculement (failover) et de consensus P2P.
//
// Utilisation côté serveur :
//
//   const log = require('./logger');
//   log.init({ role: 'primary', port: 3000, name: 'Principal' });
//   log.pingReceived();                  // à chaque /ping ou /healthz
//   log.alertReceived(id, type, votes);  // à chaque POST /alerts
//   log.consensusReached(id, type);      // à 3/3 votes
//   log.promoted('Principal');           // quand on devient principal
//   log.demoted('Défaillant');           // quand on tombe en panne
//   log.broadcastEvent('CUSTOM', '...'); // évènement libre
//
// Stratégie d'écriture (anti-race entre primary + secondary) :
//   - chaque serveur écrit dans SON PROPRE fichier
//     `SERVER_STATUS_<port>.md` à la racine du projet ;
//   - un mode "agrégé" (env STREETPHARE_DASHBOARD_AGGREGATE=1)
//     permet à UN process coordinateur (start_servers.js) de
//     recevoir l'état de tous les nœuds et de produire LE
//     fichier canonique `SERVER_STATUS.md`汇总.
'use strict';

const fs = require('fs');
const path = require('path');

// ----- Configuration interne -----
const PROJECT_ROOT = path.resolve(__dirname, '..');
const STATUS_FILE = path.join(PROJECT_ROOT, 'SERVER_STATUS.md');
const MAX_RECENT_ALERTS = 15;
const MAX_RECENT_EVENTS = 25;

// ----- État interne -----
const state = {
  role: 'unknown',
  port: 0,
  name: 'Serveur',
  url: '',
  online: true,
  startedAt: new Date(),
  currentRole: 'Actif',
  pingsCount: 0,
  lastPingAt: null,
  alerts: new Map(),
  recentEvents: [],
  writeQueue: Promise.resolve(),
  initialized: false,
  outputFile: STATUS_FILE,
  otherNodes: new Map(),
};

// ----- Helpers -----
function nowFr() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return (
    d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
    ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds())
  );
}

function classifyAlertType(alert) {
  if (!alert) return 'Inconnue';
  const candidate =
    alert.type ||
    alert.kind ||
    alert.category ||
    alert.payload?.type ||
    alert.payload?.kind ||
    '';
  const c = String(candidate).toLowerCase();
  if (!c) return 'Inconnue';
  if (c.includes('nasse')) return 'Nasse';
  if (c.includes('polic')) return 'Policiers';
  if (c.includes('aggress') || c.includes('agr')) return 'Agression';
  if (c.includes('accident')) return 'Accident';
  if (c.includes('fire') || c.includes('incendi')) return 'Incendie';
  if (c.includes('medical') || c.includes('urgence')) return 'Urgence médicale';
  return c.charAt(0).toUpperCase() + c.slice(1);
}

// ----- File d'écriture sérialisée -----
function scheduleWrite() {
  state.writeQueue = state.writeQueue.then(render).catch((e) => {
    console.error('[logger] échec rendu SERVER_STATUS.md:', e);
  });
  return state.writeQueue;
}

// ----- API publique -----
function init(opts = {}) {
  state.role = opts.role || 'unknown';
  state.port = parseInt(opts.port || 0, 10) || 0;
  state.name = opts.name || roleToName(state.role);
  state.url = opts.url || (state.port ? `http://localhost:${state.port}` : '');
  state.online = true;
  state.startedAt = new Date();
  state.currentRole = state.role === 'primary' ? 'Actif' : 'En veille';
  state.pingsCount = 0;
  state.lastPingAt = null;
  state.alerts.clear();
  state.recentEvents = [];
  state.initialized = true;
  state.otherNodes = new Map();

  // Sortie : par défaut, on écrit dans SERVER_STATUS_<port>.md
  // (anti-race). Si on est en mode "agrégateur", on écrit
  // directement dans SERVER_STATUS.md.
  if (process.env.STREETPHARE_DASHBOARD_AGGREGATE === '1') {
    state.outputFile = STATUS_FILE;
  } else {
    state.outputFile = state.port
      ? path.join(PROJECT_ROOT, `SERVER_STATUS_${state.port}.md`)
      : STATUS_FILE;
  }

  pushEvent('INFO', '🟢', 'Démarrage', `${state.name} en ligne sur ${state.url}`);
  return scheduleWrite();
}

function roleToName(role) {
  switch (role) {
    case 'primary':
      return 'Principal';
    case 'secondary':
      return 'Backup 1';
    case 'tertiary':
      return 'Backup 2';
    default:
      return role;
  }
}

function setCurrentRole(label) {
  if (state.currentRole !== label) {
    const old = state.currentRole;
    state.currentRole = label;
    pushEvent('ROLE', '🧭', 'Changement de rôle', `${old} → ${label}`);
    scheduleWrite();
  }
}

function setOnline(online, reason = '') {
  if (state.online === online) return;
  state.online = !!online;
  pushEvent(
    online ? 'ONLINE' : 'OFFLINE',
    online ? '🟢' : '🔴',
    online ? 'En ligne' : 'Hors ligne',
    reason || (online ? 'Heartbeat OK' : 'Heartbeats échoués'),
  );
  scheduleWrite();
}

function pingReceived(details = '') {
  state.pingsCount += 1;
  state.lastPingAt = new Date();
  if (state.pingsCount === 1 || !state.online) {
    state.online = true;
    pushEvent('PING', '💓', 'Ping reçu', details || 'Heartbeat');
  }
  scheduleWrite();
}

function alertReceived(id, alertObj, currentVotes, requiredVotes) {
  const required = requiredVotes || 3;
  const votes = Math.max(0, currentVotes || 0);
  const type = classifyAlertType(alertObj);
  const wasKnown = state.alerts.has(id);
  state.alerts.set(id, {
    id,
    type,
    votes,
    required,
    validated: votes >= required,
    firstSeenAt: wasKnown ? state.alerts.get(id).firstSeenAt : new Date(),
    lastVoteAt: new Date(),
  });
  pushEvent(
    'ALERT',
    '📨',
    wasKnown ? 'Vote supplémentaire' : 'Alerte reçue',
    `#${id} (${type}) — ${votes}/${required}`,
  );
  scheduleWrite();
}

function consensusReached(id, alertObj) {
  const type = classifyAlertType(alertObj);
  const existing = state.alerts.get(id) || {};
  state.alerts.set(id, {
    ...existing,
    id,
    type,
    votes: existing.required || 3,
    required: existing.required || 3,
    validated: true,
    lastVoteAt: new Date(),
  });
  pushEvent(
    'CONSENSUS',
    '✅',
    'Consensus atteint',
    `#${id} (${type}) validée par 3/3 pairs`,
  );
  scheduleWrite();
}

function promoted(newRoleLabel = 'Promu Principal') {
  state.role = 'primary';
  state.name = roleToName('primary');
  setCurrentRole(newRoleLabel);
  pushEvent('PROMOTION', '🚀', 'Promotion', `Devient ${state.name}`);
  scheduleWrite();
}

function demoted(reason = 'Défaillant') {
  setCurrentRole('Obsolète');
  setOnline(false, reason);
  pushEvent('DEMOTION', '💀', 'Démotion', reason);
  scheduleWrite();
}

function failoverTriggered(fromLabel, toLabel) {
  pushEvent('FAILOVER', '🔁', 'Basculement', `${fromLabel} → ${toLabel}`);
  scheduleWrite();
}

function backupRequested(cipher) {
  pushEvent(
    'BACKUP',
    '🔐',
    'Adresse de backup chiffrée renvoyée',
    cipher ? `${cipher.length} caractères` : '(vide)',
  );
  scheduleWrite();
}

function broadcastEvent(level, emoji, label, details) {
  pushEvent(level || 'INFO', emoji || 'ℹ️', label || 'Évènement', details || '');
  scheduleWrite();
}

function pushEvent(level, emoji, label, details) {
  state.recentEvents.push({ ts: new Date(), level, emoji, label, details });
  if (state.recentEvents.length > MAX_RECENT_EVENTS) {
    state.recentEvents.splice(0, state.recentEvents.length - MAX_RECENT_EVENTS);
  }
}

function mergeNode(nodeInfo) {
  if (!nodeInfo || !nodeInfo.name) return;
  state.otherNodes.set(nodeInfo.name, {
    ...nodeInfo,
    updatedAt: nodeInfo.updatedAt || new Date().toISOString(),
  });
  scheduleWrite();
}

function getOutputFile() {
  return state.outputFile;
}

// ----- Rendu Markdown -----
function render() {
  if (!state.initialized) return;
  const lines = [];
  lines.push('# 📡 Tableau de bord de Débogage - StreetPhare');
  lines.push('');
  lines.push(
    `> Dernière mise à jour : **${nowFr()}** (UTC serveur). ` +
    `Ce fichier est généré automatiquement par \`test_servers/logger.js\`.`,
  );
  lines.push('');
  lines.push('---');
  lines.push('');

  // Section : Statut des Nœuds
  lines.push('## 🖥️ Statut des Nœuds');
  lines.push('');
  lines.push('| Serveur | URL | Statut | Rôle Actuel |');
  lines.push('| --- | --- | --- | --- |');

  const onlineIcon = state.online ? '🟢 EN LIGNE' : '🔴 HORS LIGNE';
  const roleIcon =
    state.currentRole === 'Actif' || state.currentRole === 'Promu Principal'
      ? '⭐ Actif'
      : state.currentRole === 'En veille'
      ? '🟡 En veille'
      : '⚪ ' + state.currentRole;

  lines.push(
    `| ${state.name} | ${state.url || '—'} | ${onlineIcon} | ${roleIcon} |`,
  );

  for (const n of state.otherNodes.values()) {
    const oIcon =
      n.online === null
        ? '⚪ INCONNU'
        : n.online
        ? '🟢 EN LIGNE'
        : '🔴 HORS LIGNE';
    const rIcon =
      n.currentRole === 'Actif' || n.currentRole === 'Promu Principal'
        ? '⭐ Actif'
        : n.currentRole === 'En veille'
        ? '🟡 En veille'
        : n.currentRole === 'Obsolète'
        ? '💀 Obsolète'
        : '⚪ ' + (n.currentRole || '—');
    lines.push(`| ${n.name} | ${n.url || '—'} | ${oIcon} | ${rIcon} |`);
  }
  lines.push('');

  // Résumé express
  lines.push('## ⚡ Résumé Express');
  lines.push('');
  lines.push(`- 💓 Pings reçus : **${state.pingsCount}**`);
  const validated = [...state.alerts.values()].filter((a) => a.validated).length;
  lines.push(
    `- 📨 Alertes connues : **${state.alerts.size}** ` +
    `(✅ validées : **${validated}**)`,
  );
  lines.push(`- 🕒 Dernier ping : **${state.lastPingAt ? nowFr() : '—'}**`);
  lines.push('');

  // Flux du consensus
  lines.push('## 🌐 Flux du Consensus (Dernières Alertes)');
  lines.push('');
  lines.push('| ID Alerte | Type | Votes (Validations) | Statut Réseau |');
  lines.push('| --- | --- | --- | --- |');

  const alerts = [...state.alerts.values()]
    .sort((a, b) => (b.lastVoteAt || 0) - (a.lastVoteAt || 0))
    .slice(0, MAX_RECENT_ALERTS);

  if (alerts.length === 0) {
    lines.push('| — | — | 0 / 3 | ⚪ Aucune alerte reçue pour l\'instant |');
  } else {
    for (const a of alerts) {
      const idLabel = '#' + a.id;
      const type = a.type || 'Inconnue';
      const votes = `${a.votes} / ${a.required}`;
      const status = a.validated
        ? '✅ Validée et Propagée'
        : '⏳ En attente de consensus (P2P)';
      lines.push(`| ${idLabel} | ${type} | ${votes} | ${status} |`);
    }
  }
  lines.push('');

  // Journal d'évènements
  lines.push('## 📜 Journal d\'Évènements (Flux Temps Réel)');
  lines.push('');
  lines.push('| Heure | Niveau | Évènement | Détails |');
  lines.push('| --- | --- | --- | --- |');
  if (state.recentEvents.length === 0) {
    lines.push('| — | ℹ️ INFO | _Aucun évènement_ | — |');
  } else {
    for (let i = state.recentEvents.length - 1; i >= 0; i--) {
      const ev = state.recentEvents[i];
      const time = new Date(ev.ts).toTimeString().slice(0, 8);
      lines.push(
        `| ${time} | ${ev.emoji} ${ev.level} | ${ev.label} | ${
          ev.details || '—'
        } |`,
      );
    }
  }
  lines.push('');
  lines.push('---');
  lines.push('');
  lines.push(
    '> ℹ️ Pour suivre en direct : `tail -f SERVER_STATUS.md` ' +
    '(le fichier est réécrit à chaque évènement).',
  );
  lines.push('');

  const body = lines.join('\n');
  const tmp = state.outputFile + '.tmp';
  try {
    fs.writeFileSync(tmp, body, 'utf8');
    fs.renameSync(tmp, state.outputFile);
  } catch (e) {
    console.error('[logger] écriture échouée:', e);
  }
}

module.exports = {
  init,
  pingReceived,
  alertReceived,
  consensusReached,
  promoted,
  demoted,
  setCurrentRole,
  setOnline,
  failoverTriggered,
  backupRequested,
  broadcastEvent,
  mergeNode,
  getOutputFile,
  // expose en lecture pour un éventuel coordinateur
  getState: () => ({
    role: state.role,
    port: state.port,
    name: state.name,
    url: state.url,
    online: state.online,
    currentRole: state.currentRole,
    pingsCount: state.pingsCount,
    lastPingAt: state.lastPingAt,
    alerts: [...state.alerts.values()].map((a) => ({
      id: a.id,
      type: a.type,
      votes: a.votes,
      required: a.required,
      validated: a.validated,
    })),
    recentEvents: state.recentEvents.slice(-MAX_RECENT_EVENTS),
  }),
};
