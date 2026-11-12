// server/src/routes/streetmedic.js
//
// Routes "street-medic" (médecins de rue volontaires), montées sous /api/streetmedic.
//   - Demande de statut (contact admin chiffré), position temps réel,
//     liste publique des street-medics actifs, et cycle de vie des missions.

const express = require('express');
const store = require('../store');
const { broadcast, broadcastToAll } = require('../services/broadcast');

const router = express.Router();

/// POST /api/streetmedic/request — Demande de statut street-medic.
/// Body: { userId, eventId?, lat?, lng?, contactCipher?, contactMessage? }
router.post('/request', (req, res) => {
  const { userId, eventId, lat, lng, contactCipher, contactMessage } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  const sm = store.requestStreetMedic({ userId, eventId, lat, lng, contactMessage, contactCipher });
  broadcast('streetmedic_request', { streetmedic: sm });
  res.status(201).json({ success: true, streetmedic: sm });
});

/// GET /api/streetmedic/me?userId= — Statut street-medic de l'utilisateur.
router.get('/me', (req, res) => {
  const { userId } = req.query;
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  res.json({ streetmedic: store.getStreetMedicByUser(String(userId)) });
});

/// POST /api/streetmedic/position — Signale la position / active le partage.
/// Body: { userId, lat, lng, sharing, eventId? }
router.post('/position', (req, res) => {
  const { userId, lat, lng, sharing, eventId } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  const sm = store.reportStreetMedicPosition(String(userId), { lat, lng, sharing, eventId });
  if (!sm) return res.status(403).json({ error: 'Statut street-medic non autorisé' });
  broadcastToAll('streetmedics_changed', { streetmedics: store.getActiveStreetMedics() });
  res.json({ success: true, streetmedic: sm });
});

/// GET /api/streetmedic/active — Positions des street-medics actifs (carte publique).
router.get('/active', (req, res) => {
  const list = store.getActiveStreetMedics();
  res.json({ streetmedics: list, count: list.length });
});

// ── Missions d'intervention ────────────────────────────────────────────

/// POST /api/streetmedic/missions — Appeler le street-medic le plus proche.
/// Body: { userId, lat, lng, note? }
router.post('/missions', (req, res) => {
  const { userId, lat, lng, note } = req.body || {};
  if (!userId || lat == null || lng == null) return res.status(400).json({ error: 'userId, lat, lng requis' });
  const mission = store.createMedicMission({ callerUserId: String(userId), lat: Number(lat), lng: Number(lng), note });
  if (!mission) return res.status(404).json({ error: 'Aucun street-medic disponible à proximité' });
  broadcastToAll('medic_mission_update', { mission });
  res.status(201).json({ success: true, mission });
});

/// GET /api/streetmedic/missions?userId= — Missions de l'utilisateur (appelant ou medic).
router.get('/missions', (req, res) => {
  const { userId } = req.query;
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  res.json({ missions: store.getAllMissionsForUser(String(userId)), active: store.getActiveMissionForMedic(String(userId)) });
});

/// GET /api/streetmedic/missions/:id — Statut d'une mission.
router.get('/missions/:id', (req, res) => {
  const m = store.getMissionById(req.params.id);
  if (!m) return res.status(404).json({ error: 'Mission non trouvée' });
  res.json({ mission: m });
});

/// POST /api/streetmedic/missions/:id/accept — Le medic accepte la mission.
/// Body: { userId, lat?, lng? }
router.post('/missions/:id/accept', (req, res) => {
  const { userId, lat, lng } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  const m = store.acceptMedicMission(req.params.id, String(userId), lat, lng);
  if (!m) return res.status(404).json({ error: 'Mission non trouvée ou déjà traitée' });
  broadcastToAll('medic_mission_update', { mission: m });
  broadcastToAll('medic_alerted', { medicId: m.medicId, missionId: m.id });
  res.json({ success: true, mission: m });
});

/// POST /api/streetmedic/missions/:id/refuse — Refuse, passe au medic suivant.
/// Body: { userId }
router.post('/missions/:id/refuse', (req, res) => {
  const { userId } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  const m = store.refuseMedicMission(req.params.id, String(userId));
  if (!m) return res.status(404).json({ error: 'Mission non trouvée ou déjà traitée' });
  broadcastToAll('medic_mission_update', { mission: m });
  res.json({ success: true, mission: m });
});

/// POST /api/streetmedic/missions/:id/complete — Intervention terminée.
/// Body: { userId }
router.post('/missions/:id/complete', (req, res) => {
  const { userId } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });
  const m = store.completeMedicMission(req.params.id, String(userId));
  if (!m) return res.status(404).json({ error: 'Mission non trouvée' });
  broadcastToAll('medic_mission_update', { mission: m });
  res.json({ success: true, mission: m });
});

/// POST /api/streetmedic/missions/:id/track — Le blessé met à jour sa position.
/// Body: { userId (appelant = blessé), lat, lng }
router.post('/missions/:id/track', (req, res) => {
  const { userId, lat, lng } = req.body || {};
  if (!userId || lat == null || lng == null) {
    return res.status(400).json({ error: 'userId, lat, lng requis' });
  }
  const m = store.trackMedicMissionInjured(req.params.id, String(userId), Number(lat), Number(lng));
  if (!m) return res.status(404).json({ error: 'Mission non trouvée' });
  broadcastToAll('medic_mission_update', { mission: m });
  res.json({ success: true, mission: m });
});

module.exports = router;