// server/src/routes/simulation.js
//
// Routes d'administration de simulation (montées sous /api/admin/simulation).
// Permettent d'injecter et de purger des données fictives, de piloter les
// bots et de simuler le consensus — sans toucher aux données de production.

const express = require('express');
const simulation = require('../services/simulation');
const { authenticateToken, requirePermission } = require('../middleware/auth');

const router = express.Router();

// Toutes les routes de simulation exigent la permission `simulateAccess`.
router.use(authenticateToken, requirePermission('simulateAccess'));

/// GET /api/admin/simulation/stats — Métriques + état de la simulation.
router.get('/stats', (req, res) => {
  res.json(simulation.getStats());
});

/// GET /api/admin/simulation/entity-types — Types générables au clic.
router.get('/entity-types', (req, res) => {
  res.json({ types: simulation.ENTITY_TYPES, scenarios: simulation.SCENARIOS });
});

/// POST /api/admin/simulation/alert — Génère un signalement fictif.
/// Body: { type, lat, lng, description? }
router.post('/alert', (req, res) => {
  const { type, lat, lng, description } = req.body || {};
  if (!type || lat == null || lng == null) return res.status(400).json({ error: 'type, lat, lng requis' });
  const alert = simulation.generateAlert(type, lat, lng, description);
  res.status(201).json({ success: true, alert });
});

/// POST /api/admin/simulation/panic — Génère une alerte PANIC.
/// Body: { lat, lng, collective }
router.post('/panic', (req, res) => {
  const { lat, lng, collective } = req.body || {};
  if (lat == null || lng == null) return res.status(400).json({ error: 'lat, lng requis' });
  const result = simulation.generatePanic(lat, lng, !!collective);
  res.status(201).json({ success: true, ...result });
});

/// POST /api/admin/simulation/zone — Ajoute une zone de géorepérage fictive.
router.post('/zone', (req, res) => {
  const { name, type, lat, lng, radiusMeters } = req.body || {};
  if (lat == null || lng == null) return res.status(400).json({ error: 'lat, lng requis' });
  const zone = simulation.addZone(name || 'Zone SIM', type || 'safe', lat, lng, radiusMeters || 100);
  res.status(201).json({ success: true, zone });
});

/// POST /api/admin/simulation/waypoint — Ajoute un point de passage fictif.
router.post('/waypoint', (req, res) => {
  const { name, lat, lng } = req.body || {};
  if (lat == null || lng == null) return res.status(400).json({ error: 'lat, lng requis' });
  const event = simulation.addWaypoint(name, lat, lng);
  res.status(201).json({ success: true, event });
});

/// POST /api/admin/simulation/scenario — Injecte un scénario batch.
/// Body: { name: 'manifestation' | 'festival' | 'barrage' }
router.post('/scenario', (req, res) => {
  const { name } = req.body || {};
  const result = simulation.injectScenario(name);
  if (result.error) return res.status(400).json(result);
  res.status(201).json({ success: true, ...result });
});

/// POST /api/admin/simulation/bots — Démarre/arrête les bots.
/// Body: { action: 'start'|'stop', count? }
router.post('/bots', (req, res) => {
  const { action, count } = req.body || {};
  if (action === 'stop') return res.json({ success: true, ...simulation.stopBots() });
  const result = simulation.startBots(parseInt(count, 10) || 5);
  res.status(201).json({ success: true, ...result });
});

/// POST /api/admin/simulation/votes — Simule des votes sur une alerte.
/// Body: { alertId, upvotes, downvotes }
router.post('/votes', (req, res) => {
  const { alertId, upvotes, downvotes } = req.body || {};
  if (!alertId) return res.status(400).json({ error: 'alertId requis' });
  const result = simulation.simulateVotes(alertId, parseInt(upvotes, 10) || 0, parseInt(downvotes, 10) || 0);
  res.json({ success: true, ...result });
});

/// POST /api/admin/simulation/auto-vote — Vote automatique (consensus).
/// Body: { upvotesPerAlert }
router.post('/auto-vote', (req, res) => {
  const result = simulation.autoVoteAll(parseInt((req.body || {}).upvotesPerAlert, 10) || 3);
  res.json({ success: true, ...result });
});

/// POST /api/admin/simulation/chat — Injecte un flux de messages tchat.
/// Body: { count }
router.post('/chat', (req, res) => {
  const result = simulation.injectChat(parseInt((req.body || {}).count, 10) || 10);
  res.json({ success: true, ...result });
});

/// POST /api/admin/simulation/purge — Purge toutes les entités fictives.
router.post('/purge', (req, res) => {
  const removed = simulation.purge();
  res.json({ success: true, removed });
});

module.exports = router;
