// server/src/services/simulation.js
//
// Moteur de simulation de données fictives pour tester le dashboard,
// les cartes et la charge réseau, isolé des données de production.
//
// Toutes les entités générées sont marquées `simulated: true` afin de
// pouvoir être purgées en un clic sans affecter les vraies données.

const { v4: uuidv4 } = require('uuid');
const store = require('../store');
const { broadcast } = require('./broadcast');

const log = (category, message) => console.log(`[SIM] [${category}] ${message}`);

const DEFAULT_CENTER = { lat: 50.4762, lng: 4.5422 };

// ── Types d'entités générables au clic ─────────────────────────────────
const ENTITY_TYPES = [
  { id: 'police', label: 'Police', kind: 'alert' },
  { id: 'danger', label: 'Danger (mobile)', kind: 'alert' },
  { id: 'collective', label: 'Nasle / Danger collectif', kind: 'alert' },
  { id: 'barrage', label: 'Barrage / Filtre', kind: 'alert' },
  { id: 'panic', label: 'PANIC individuel', kind: 'panic' },
  { id: 'panic_collective', label: 'PANIC collectif', kind: 'panic' },
  { id: 'safe_zone', label: 'Safe Zone', kind: 'zone' },
  { id: 'waypoint', label: 'Point de passage', kind: 'event' },
  { id: 'zone', label: 'Zone géorepérage', kind: 'zone' },
];

// ── Scénarios batch préconfigurés ──────────────────────────────────────
const SCENARIOS = {
  manifestation: {
    label: 'Manifestation massive',
    description: '20 signalements + 5 PANIC + 12 bots',
  },
  festival: {
    label: 'Incident festival',
    description: '15 signalements + 3 PANIC + 8 bots',
  },
  barrage: {
    label: 'Bouchon / Barrage routier',
    description: '12 barrages le long d\'un axe + 6 bots',
  },
};

// ── Utilitaires ────────────────────────────────────────────────────────
const rand = (min, max) => min + Math.random() * (max - min);
const randInt = (min, max) => Math.floor(rand(min, max + 1));

function jitter(center, radiusKm) {
  // ~1 deg lat ≈ 111 km, 1 deg lng ≈ 111*cos(lat) km
  const dLat = radiusKm / 111;
  const dLng = radiusKm / (111 * Math.cos(center.lat * Math.PI / 180));
  return {
    lat: center.lat + rand(-dLat, dLat),
    lng: center.lng + rand(-dLng, dLng),
  };
}

function shortId() { return uuidv4().slice(0, 8); }

// ── Bot : utilisateur virtuel se déplaçant ─────────────────────────────
class Bot {
  constructor(center) {
    this.id = 'bot_' + shortId();
    this.name = 'Bot ' + this.id.slice(-4);
    this.lat = center.lat + rand(-0.02, 0.02);
    this.lng = center.lng + rand(-0.02, 0.02);
    this.destLat = center.lat + rand(-0.03, 0.03);
    this.destLng = center.lng + rand(-0.03, 0.03);
    this.speed = rand(0.0003, 0.0012); // degrés / tick
  }

  tick(center) {
    const dLat = this.destLat - this.lat;
    const dLng = this.destLng - this.lng;
    const dist = Math.sqrt(dLat * dLat + dLng * dLng);
    if (dist < 0.0005) {
      // Nouvelle destination aléatoire autour du centre.
      this.destLat = center.lat + rand(-0.03, 0.03);
      this.destLng = center.lng + rand(-0.03, 0.03);
      return;
    }
    const step = Math.min(this.speed, dist);
    this.lat += (dLat / dist) * step;
    this.lng += (dLng / dist) * step;
  }
}

// ── État interne ───────────────────────────────────────────────────────
const state = {
  bots: new Map(),        // id → Bot
  botTimer: null,
  center: { ...DEFAULT_CENTER },
  totalInjected: 0,
};

module.exports.__state = state; // (debug / tests)

// ═══════════════════════════════════════════════════════════════════════
// GÉNÉRATEURS UNITAIRES (clic sur carte)
// ═══════════════════════════════════════════════════════════════════════

const ALERT_TYPE_MAP = {
  police: 'police',
  danger: 'mobile_danger',
  collective: 'collective_danger',
  barrage: 'filter',
  panic: 'panic',
};

/// Génère un signalement fictif. Retourne l'alerte créée.
function generateAlert(typeId, lat, lng, description) {
  const type = ALERT_TYPE_MAP[typeId] || typeId;
  const alert = {
    id: uuidv4(),
    type,
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    description: description || `[SIM] ${typeId}`,
    votes: [],
    status: 'active',
    uploadedTo: '',
    simulated: true,
  };
  const saved = store.addAlert(alert);
  state.totalInjected++;
  broadcast('simulation_changed', { kind: 'alert', id: saved.id, type });
  return saved;
}

/// Génère une alerte PANIC (individuelle ou collective).
function generatePanic(lat, lng, collective = false) {
  const count = collective ? 5 : 1;
  let aggregation = null;
  for (let i = 0; i < count; i++) {
    const p = jitter({ lat, lng }, collective ? 0.08 : 0);
    aggregation = store.addPanicPing({ id: uuidv4(), lat: p.lat, lng: p.lng, simulated: true });
  }
  const alert = generateAlert(collective ? 'collective' : 'panic', lat, lng,
    collective ? '[SIM] PANIC collectif (5 pings)' : '[SIM] PANIC individuel');
  broadcast('panic', { lat, lng, collective, count, alertId: alert.id });
  return { aggregation, alert, count };
}

/// Ajoute une zone de géorepérage fictive.
function addZone(name, type, lat, lng, radiusMeters = 100) {
  const zone = store.addGeofencingZone({ name, type, lat, lng, radiusMeters, simulated: true });
  state.totalInjected++;
  broadcast('simulation_changed', { kind: 'zone', id: zone.id });
  return zone;
}

/// Ajoute un point de passage / navigation fictif (sous forme d'événement).
function addWaypoint(name, lat, lng) {
  const event = {
    code: 'SIM-WP-' + shortId().toUpperCase(),
    title: name || 'Point de passage SIM',
    destinationLatitude: parseFloat(lat),
    destinationLongitude: parseFloat(lng),
    startAt: new Date().toISOString(),
    simulated: true,
  };
  store.addEvent(event);
  state.totalInjected++;
  broadcast('simulation_changed', { kind: 'event', code: event.code });
  return event;
}

// ═══════════════════════════════════════════════════════════════════════
// SCÉNARIOS BATCH
// ═══════════════════════════════════════════════════════════════════════

function injectScenario(name) {
  if (!SCENARIOS[name]) return { error: 'Scénario inconnu' };
  const center = state.center;
  const result = { alerts: 0, panics: 0, bots: 0, name };

  if (name === 'manifestation') {
    for (let i = 0; i < 20; i++) {
      const p = jitter(center, 1.5);
      const t = i % 3 === 0 ? 'police' : (i % 3 === 1 ? 'collective' : 'danger');
      generateAlert(t, p.lat, p.lng, `[SIM] Manifestation #${i + 1}`);
      result.alerts++;
    }
    for (let i = 0; i < 5; i++) { const p = jitter(center, 1); generatePanic(p.lat, p.lng, false); result.panics++; }
    startBots(12, center); result.bots = 12;
  } else if (name === 'festival') {
    for (let i = 0; i < 15; i++) {
      const p = jitter(center, 0.8);
      const t = i % 3 === 0 ? 'collective' : (i % 3 === 1 ? 'danger' : 'police');
      generateAlert(t, p.lat, p.lng, `[SIM] Festival #${i + 1}`);
      result.alerts++;
    }
    for (let i = 0; i < 3; i++) { const p = jitter(center, 0.5); generatePanic(p.lat, p.lng, true); result.panics++; }
    startBots(8, center); result.bots = 8;
  } else if (name === 'barrage') {
    for (let i = 0; i < 12; i++) {
      const lat = center.lat + rand(-0.012, 0.012);
      const lng = center.lng - 0.03 + i * 0.0055;
      generateAlert('barrage', lat, lng, `[SIM] Barrage routier #${i + 1}`);
      result.alerts++;
    }
    startBots(6, center); result.bots = 6;
  }

  broadcast('simulation_changed', { scenario: name, ...result });
  log('SCENARIO', `${SCENARIOS[name].label} injecté : ${JSON.stringify(result)}`);
  return result;
}

// ═══════════════════════════════════════════════════════════════════════
// BOTS — Utilisateurs virtuels se déplaçant en temps réel
// ═══════════════════════════════════════════════════════════════════════

function startBots(count = 5, center) {
  if (center) state.center = center;
  for (let i = 0; i < count; i++) {
    const bot = new Bot(state.center);
    state.bots.set(bot.id, bot);
  }
  if (!state.botTimer) {
    state.botTimer = setInterval(_tickBots, 1000);
  }
  log('BOTS', `${count} bot(s) démarrés (total: ${state.bots.size})`);
  broadcast('simulation_changed', { bots: state.bots.size });
  return { started: count, total: state.bots.size };
}

function stopBots() {
  if (state.botTimer) { clearInterval(state.botTimer); state.botTimer = null; }
  const n = state.bots.size;
  state.bots.clear();
  broadcast('bot_update', { bots: [] });
  log('BOTS', `${n} bot(s) arrêtés`);
  return { stopped: n };
}

function _tickBots() {
  try {
    for (const bot of state.bots.values()) bot.tick(state.center);
    const bots = [...state.bots.values()].map(b => ({ id: b.id, name: b.name, lat: b.lat, lng: b.lng }));
    broadcast('bot_update', { bots });
  } catch (err) {
    // Blindage : une erreur dans le tick des bots ne doit jamais faire
    // planter le processus (callback d'un setInterval, donc hors du
    // contexte Express).
    log('BOTS', `Erreur tick bots : ${err.message}`);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// VOTES — Simulation du consensus
// ═══════════════════════════════════════════════════════════════════════

function simulateVotes(alertId, upvotes = 0, downvotes = 0) {
  const upIds = Array.from({ length: upvotes }, () => 'sim_' + shortId());
  const added = store.addVotes(alertId, upIds);
  const removed = store.removeVotes(alertId, downvotes);
  broadcast('report_updated', { id: alertId, status: 'votes' });
  return { added, removed };
}

/// Vote automatiquement sur toutes les alertes simulées (consensus).
function autoVoteAll(upvotesPerAlert = 3) {
  let total = 0;
  let touched = 0;
  for (const a of store.alerts) {
    if (a.simulated) {
      const added = store.addVotes(a.id, Array.from({ length: upvotesPerAlert }, () => 'sim_' + shortId()));
      total += added; touched++;
    }
  }
  broadcast('report_updated', {});
  return { total, touched };
}

// ═══════════════════════════════════════════════════════════════════════
// TCHAT P2P — Injection de messages fictifs
// ═══════════════════════════════════════════════════════════════════════

const CHAT_SAMPLES = [
  'Y a-t-il du monde par ici ?',
  'Attention, contrôle de police rue de la Gare.',
  'Quelqu\'un a vu la manifestation ?',
  'C\'est calme dans le coin, merci pour les infos.',
  'Barrage signalé vers la grand-place.',
  'Rentrez chez vous, ça chauffe au centre.',
  'Besoin d\'aide, je suis perdu près du parc.',
  'Faites attention près du stade, gros mouvement.',
  'Safe zone confirmée, merci !',
  'Des nouvelles du festival ?',
];

function injectChat(count = 10) {
  let injected = 0;
  for (let i = 0; i < count; i++) {
    const botId = 'sim_' + shortId();
    const text = CHAT_SAMPLES[randInt(0, CHAT_SAMPLES.length - 1)];
    const msg = store.addMeshMessage({
      kind: 'chat', simulated: true, sender_id: botId,
      data: { text, sentAt: new Date().toISOString() },
    });
    broadcast('chat_message', { id: msg.id, senderId: botId, text });
    injected++;
  }
  return { injected };
}

// ═══════════════════════════════════════════════════════════════════════
// PURGE — Suppression de toutes les entités fictives
// ═══════════════════════════════════════════════════════════════════════

function purge() {
  stopBots();
  const removed = store.removeSimulatedEntities();
  state.totalInjected = 0;
  broadcast('simulation_changed', { purged: true, ...removed });
  log('PURGE', `Entités simulées supprimées : ${JSON.stringify(removed)}`);
  return removed;
}

// ═══════════════════════════════════════════════════════════════════════
// STATS
// ═══════════════════════════════════════════════════════════════════════

function getStats() {
  return {
    bots: state.bots.size,
    simulatedAlerts: store.alerts.filter(a => a.simulated).length,
    simulatedZones: store.geofencingZones.filter(z => z.simulated).length,
    simulatedEvents: store.events.filter(e => e.simulated).length,
    simulatedMessages: store.meshMessages.filter(m => m.simulated).length,
    totalInjected: state.totalInjected,
    metrics: store.getMetrics(),
  };
}

module.exports = {
  ENTITY_TYPES,
  SCENARIOS,
  generateAlert,
  generatePanic,
  addZone,
  addWaypoint,
  injectScenario,
  startBots,
  stopBots,
  simulateVotes,
  autoVoteAll,
  injectChat,
  purge,
  getStats,
};


