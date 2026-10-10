// server/src/routes/admin.js
//
// Routes d'administration avancée (montées sous /api/admin).
// Regroupe : gestion des modérateurs, modération des signalements,
// modération du tchat, et gestion du géorepérage.

const express = require('express');
const jwt = require('jsonwebtoken');

const config = require('../config');
const store = require('../store');
const sync = require('../sync');
const moderators = require('../services/moderators');
const { broadcast } = require('../services/broadcast');
const { authenticateToken, requirePermission } = require('../middleware/auth');

const router = express.Router();

const log = (category, message) => console.log(`[ADMIN-API] [${category}] ${message}`);

// ═══════════════════════════════════════════════════════════════════════════
// 1. AUTHENTIFICATION DES MODÉRATEURS
// ═══════════════════════════════════════════════════════════════════════════

/// POST /api/admin/moderators/login — Connexion d'un compte modérateur.
router.post('/moderators/login', async (req, res) => {
  try {
    const { username, password } = req.body || {};
    if (!username || !password) return res.status(400).json({ error: 'username et password requis' });

    const mod = await moderators.verify(username, password);
    if (!mod) return res.status(401).json({ error: 'Identifiants invalides' });

    const token = jwt.sign(
      { role: 'moderator', username: mod.username, permissions: mod.permissions || [] },
      config.jwtSecret,
      { algorithm: 'HS256', expiresIn: config.jwtExpiresIn },
    );

    log('AUTH', `Connexion modérateur réussie : ${mod.username}`);
    res.json({ success: true, token, role: 'moderator', permissions: mod.permissions || [] });
  } catch (err) {
    log('AUTH', `Erreur login modérateur : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de l\'authentification' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// 2. GESTION DES MODÉRATEURS (réservé à l'admin principal)
// ═══════════════════════════════════════════════════════════════════════════

/// GET /api/admin/moderators — Liste des modérateurs.
router.get('/moderators', authenticateToken, (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Réservé à l\'administrateur principal' });
  }
  res.json({ moderators: moderators.list(), permissions: moderators.PERMISSIONS });
});

/// POST /api/admin/moderators — Créer un modérateur.
router.post('/moderators', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Réservé à l\'administrateur principal' });
  }
  const { username, password, permissions } = req.body || {};
  const result = await moderators.create(username, password, permissions);
  if (result.error) return res.status(400).json({ error: result.error });
  broadcast('moderators_changed', {});
  res.status(201).json({ success: true, moderator: result.mod });
});

/// PUT /api/admin/moderators/:id — Modifier un modérateur.
router.put('/moderators/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Réservé à l\'administrateur principal' });
  }
  const { password, permissions } = req.body || {};
  const result = await moderators.update(req.params.id, { password, permissions });
  if (result.error) return res.status(404).json({ error: result.error });
  broadcast('moderators_changed', {});
  res.json({ success: true, moderator: result.mod });
});

/// DELETE /api/admin/moderators/:id — Supprimer un modérateur.
router.delete('/moderators/:id', authenticateToken, (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Réservé à l\'administrateur principal' });
  }
  const removed = moderators.remove(req.params.id);
  if (!removed) return res.status(404).json({ error: 'Modérateur non trouvé' });
  broadcast('moderators_changed', {});
  res.json({ success: true });
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. MODÉRATION DES SIGNALEMENTS
// ═══════════════════════════════════════════════════════════════════════════

/// GET /api/admin/reports — Liste complète des signalements.
router.get('/reports', authenticateToken, requirePermission('reportValidate'), (req, res) => {
  res.json({ alerts: store.getAllAlerts().map(a => ({ ...a, votes: a.votes || [] })) });
});

/// POST /api/admin/reports/:id/validate — Valider un signalement.
router.post('/reports/:id/validate', authenticateToken, requirePermission('reportValidate'), (req, res) => {
  if (!store.validateAlert(req.params.id)) return res.status(404).json({ error: 'Signalement non trouvé' });
  broadcast('report_updated', { id: req.params.id, status: 'active' });
  res.json({ success: true });
});

/// POST /api/admin/reports/:id/reject — Rejeter un signalement.
router.post('/reports/:id/reject', authenticateToken, requirePermission('reportValidate'), (req, res) => {
  if (!store.rejectAlert(req.params.id)) return res.status(404).json({ error: 'Signalement non trouvé' });
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (alert) sync.enqueueAlert(alert);
  broadcast('report_updated', { id: req.params.id, status: 'rejected' });
  res.json({ success: true });
});

/// DELETE /api/admin/reports/:id — Supprimer un signalement.
router.delete('/reports/:id', authenticateToken, requirePermission('reportValidate'), (req, res) => {
  if (!store.deleteAlert(req.params.id)) return res.status(404).json({ error: 'Signalement non trouvé' });
  broadcast('report_updated', { id: req.params.id, status: 'deleted' });
  res.json({ success: true });
});

// ═══════════════════════════════════════════════════════════════════════════
// 4. MODÉRATION DU TCHAT P2P / RELAIS
// ═══════════════════════════════════════════════════════════════════════════

/// GET /api/admin/chat — Liste des messages mesh récents.
router.get('/chat', authenticateToken, requirePermission('chatModerate'), (req, res) => {
  res.json({ messages: store.meshMessages.slice(-200).reverse() });
});

/// DELETE /api/admin/chat/:id — Supprimer un message.
router.delete('/chat/:id', authenticateToken, requirePermission('chatModerate'), (req, res) => {
  if (!store.deleteMeshMessage(req.params.id)) return res.status(404).json({ error: 'Message non trouvé' });
  broadcast('chat_message_deleted', { id: req.params.id });
  res.json({ success: true });
});

/// POST /api/admin/chat/ban — Bannir un UUID d'émetteur.
router.post('/chat/ban', authenticateToken, requirePermission('chatModerate'), (req, res) => {
  const { uuid } = req.body || {};
  if (!uuid) return res.status(400).json({ error: 'uuid requis' });
  store.banUser(uuid);
  broadcast('user_banned', { uuid });
  res.json({ success: true });
});

/// POST /api/admin/chat/unban — Lever un bannissement.
router.post('/chat/unban', authenticateToken, requirePermission('chatModerate'), (req, res) => {
  const { uuid } = req.body || {};
  if (!uuid) return res.status(400).json({ error: 'uuid requis' });
  store.unbanUser(uuid);
  broadcast('user_unbanned', { uuid });
  res.json({ success: true });
});

/// GET /api/admin/bans — Liste des UUIDs bannis.
router.get('/bans', authenticateToken, requirePermission('chatModerate'), (req, res) => {
  res.json({ bans: store.getBannedUsers() });
});

// ═══════════════════════════════════════════════════════════════════════════
// 5. GÉOREPÉRAGE
// ═══════════════════════════════════════════════════════════════════════════

/// GET /api/admin/geofencing — Liste des zones.
router.get('/geofencing', authenticateToken, requirePermission('manageGeofencing'), (req, res) => {
  res.json({ zones: store.getGeofencingZones() });
});

/// POST /api/admin/geofencing — Ajouter une zone.
router.post('/geofencing', authenticateToken, requirePermission('manageGeofencing'), (req, res) => {
  const { name, type, lat, lng, radiusMeters } = req.body || {};
  if (lat == null || lng == null) return res.status(400).json({ error: 'lat et lng requis' });
  const zone = store.addGeofencingZone({ name, type, lat, lng, radiusMeters });
  broadcast('geofencing_changed', {});
  res.status(201).json({ success: true, zone });
});

/// DELETE /api/admin/geofencing/:id — Supprimer une zone.
router.delete('/geofencing/:id', authenticateToken, requirePermission('manageGeofencing'), (req, res) => {
  if (!store.removeGeofencingZone(req.params.id)) return res.status(404).json({ error: 'Zone non trouvée' });
  broadcast('geofencing_changed', {});
  res.json({ success: true });
});

module.exports = router;

