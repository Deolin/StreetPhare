// server/src/routes/simulation.js
//
// Routes d'administration de simulation (montées sous /api/admin/simulation).
// Permettent d'injecter et de purger des données fictives, de piloter les
// bots et de simuler le consensus — sans toucher aux données de production.

const express = require('express');
const simulation = require('../services/simulation');
const { authenticateToken, requirePermission } = require('../middleware/auth');

const router = express.Router();

// En production, le panneau de simulation est désactivé (outil de test et de
// développement uniquement). Toutes les sous-routes renvoient 404.
router.use((req, res, next) => {
  if (process.env.NODE_ENV === 'production') {
    return res.status(404).json({ error: 'Simulation indisponible en production' });
  }
  next();
});

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

// ═══════════════════════════════════════════════════════════════════════
// STREET-MEDICS SIMULÉS — tester le flux complet (appel → acceptation →
// clôture → urgence 112) depuis le dashboard admin.
// ═══════════════════════════════════════════════════════════════════════

/// GET /api/admin/simulation/streetmedics — Faux medics + missions simulées.
router.get('/streetmedics', (req, res) => {
  res.json({
    streetmedics: simulation.listFakeMedics(),
    missions: simulation.listFakeMissions(),
  });
});

/// POST /api/admin/simulation/streetmedics — Crée un faux medic.
/// Body: { lat?, lng?, sharing?, status?, busy? }
router.post('/streetmedics', (req, res) => {
  const { lat, lng, sharing, status, busy } = req.body || {};
  const sm = simulation.createFakeMedic({ lat, lng, sharing, status, busy });
  res.status(201).json({ success: true, streetmedic: sm });
});

/// POST /api/admin/simulation/streetmedics/:userId/state — Pilote l'état.
/// Body: { status?, sharing?, lat?, lng?, busy? }
router.post('/streetmedics/:userId/state', (req, res) => {
  const { status, sharing, lat, lng, busy } = req.body || {};
  const sm = simulation.setFakeMedicState(req.params.userId, { status, sharing, lat, lng, busy });
  if (!sm) return res.status(404).json({ error: 'Medic simulé non trouvé' });
  res.json({ success: true, streetmedic: sm });
});

/// DELETE /api/admin/simulation/streetmedics/:userId — Supprime un faux medic.
router.delete('/streetmedics/:userId', (req, res) => {
  res.json({ success: true, ...simulation.removeFakeMedic(req.params.userId) });
});

/// POST /api/admin/simulation/missions — Crée une mission assignée à un medic.
/// Body: { medicId, lat?, lng?, note?, accept? }
router.post('/missions', (req, res) => {
  const { medicId, lat, lng, note, accept } = req.body || {};
  if (!medicId) return res.status(400).json({ error: 'medicId requis' });
  const m = simulation.createFakeMission({ medicId, lat, lng, note, accept });
  if (!m) return res.status(404).json({ error: 'Medic simulé non trouvé' });
  res.status(201).json({ success: true, mission: m });
});

/// POST /api/admin/simulation/missions/:id/state — Fait évoluer une mission.
/// Body: { status: 'accepted'|'refused'|'completed'|'emergency'|'cancelled' }
router.post('/missions/:id/state', (req, res) => {
  const { status } = req.body || {};
  const m = simulation.setFakeMissionState(req.params.id, { status });
  if (!m) return res.status(404).json({ error: 'Mission non trouvée' });
  res.json({ success: true, mission: m });
});

module.exports = router;
