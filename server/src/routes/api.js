// server/src/routes/api.js
// Routes API REST pour l'application Flutter StreetPhare.

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');
const store = require('../store');
const sync = require('../sync');

const router = express.Router();

// ═══════════════════════════════════════════════════════════════════════
// ALERTS (Signalements citoyens)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/alerts — Réception d'un signalement.
/// Body: { type, lat, lng, description?, userId }
/// Retourne l'alerte créée ou mise à jour, avec son statut de consensus.
router.post('/alerts', (req, res) => {
  const { type, lat, lng, description, userId } = req.body || {};
  if (!type || lat == null || lng == null) {
    return res.status(400).json({ error: 'type, lat, lng requis' });
  }

  const validTypes = ['mobile_danger', 'police', 'fire_truck', 'filter', 'panic', 'collective_danger'];
  if (!validTypes.includes(type)) {
    return res.status(400).json({ error: `type invalide. Valides: ${validTypes.join(', ')}` });
  }

  const alert = {
    id: uuidv4(),
    type,
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    description: description || '',
    votes: userId ? [userId] : [],
    status: 'active',
    uploadedTo: '',
  };

  const saved = store.addAlert(alert);

  // Réplication immédiate vers le Backup (si PRIMARY).
  sync.pushAlert(saved).catch(() => {});

  res.status(201).json({
    alert: { ...saved, votes: saved.votes || [] },
    votesCount: (saved.votes || []).length,
    consensusThreshold: config.consensusThreshold,
    validated: (saved.votes || []).length >= config.consensusThreshold,
  });
});

/// GET /api/alerts/active — Alertes valides (≥3 votes, TTL respecté).
router.get('/alerts/active', (req, res) => {
  const { lat, lng, radius_km } = req.query;
  let active = store.getActiveAlerts().map(a => ({
    ...a,
    votes: a.votes || [],
    votesCount: (a.votes || []).length,
  }));

  // Filtre optionnel par proximité.
  if (lat != null && lng != null) {
    const r = parseFloat(radius_km || '5');
    active = active.filter(a => {
      const dist = store._haversine(
        parseFloat(lat), parseFloat(lng),
        a.lat, a.lng
      );
      return dist <= r * 1000;
    });
  }

  res.json({ alerts: active, count: active.length });
});

/// GET /api/alerts/:id — Détail d'une alerte.
router.get('/alerts/:id', (req, res) => {
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: 'Alerte non trouvée' });
  res.json({ ...alert, votes: alert.votes || [] });
});

/// POST /api/alerts/:id/vote — Ajoute un vote (confirmation citoyenne).
router.post('/alerts/:id/vote', (req, res) => {
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: 'Alerte non trouvée' });

  const { userId } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });

  if (!alert.votes) alert.votes = [];
  if (!alert.votes.includes(userId)) {
    alert.votes.push(userId);
    alert.updatedAt = new Date().toISOString();

    // Réplication vers le Backup.
    sync.pushAlert(alert).catch(() => {});
  }

  const validated = alert.votes.length >= config.consensusThreshold;
  res.json({
    votesCount: alert.votes.length,
    validated,
    consensusThreshold: config.consensusThreshold,
  });
});

/// POST /api/alerts/:id/reject — Révoque un signalement (modération).
router.post('/alerts/:id/reject', (req, res) => {
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: 'Alerte non trouvée' });
  alert.status = 'rejected';
  alert.updatedAt = new Date().toISOString();
  sync.pushAlert(alert).catch(() => {});
  res.json({ success: true, message: 'Signalement révoqué' });
});

// ═══════════════════════════════════════════════════════════════════════
// SYNC (Synchronisation Primary ↔ Backup)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/sync/alert — Reçoit une alerte du partenaire.
router.post('/sync/alert', (req, res) => {
  const { alert } = req.body || {};
  if (!alert) return res.status(400).json({ error: 'alert requise' });
  store.addAlert(alert);
  res.json({ success: true });
});

/// POST /api/sync/event — Reçoit un événement du partenaire.
router.post('/sync/event', (req, res) => {
  const { event } = req.body || {};
  if (!event) return res.status(400).json({ error: 'event requis' });
  store.addEvent(event);
  res.json({ success: true });
});

/// POST /api/sync/check — Vérifie l'intégrité de la synchro.
/// Le Primary envoie son hash ; le Backup répond si full_sync nécessaire.
router.post('/sync/check', (req, res) => {
  const { hash, from } = req.body || {};

  // Le Primary reçoit la vérif du Backup ? Non, c'est le Primary qui push.
  // Ici c'est le Backup qui reçoit le hash du Primary.
  if (config.isBackup) {
    const needsSync = sync.checkHash(hash);
    res.json({
      action: needsSync ? 'full_sync' : 'ok',
      localHash: store.getStateHash(),
      remoteHash: hash,
    });
  } else {
    res.json({ action: 'ok' });
  }
});

/// POST /api/sync/full — Reçoit un dump complet.
router.post('/sync/full', (req, res) => {
  const { dump } = req.body || {};
  if (!dump) return res.status(400).json({ error: 'dump requis' });
  sync.receiveFullSync(dump);
  res.json({ success: true });
});

// ═══════════════════════════════════════════════════════════════════════
// EVENTS (Manifestations / Événements)
// ═══════════════════════════════════════════════════════════════════════

/// GET /api/events — Liste des événements disponibles.
router.get('/events', (req, res) => {
  const { active } = req.query;
  let events = store.getAllEvents();
  if (active === 'true') {
    const now = new Date();
    events = events.filter(e => new Date(e.startAt) > now || !e.endAt || new Date(e.endAt) > now);
  }
  res.json({ events: events.map(e => ({ code: e.code, title: e.title, startAt: e.startAt })) });
});

/// GET /api/events/:code — Détail complet d'un événement.
router.get('/events/:code', (req, res) => {
  const event = store.getEventByCode(req.params.code);
  if (!event) return res.status(404).json({ error: 'Événement non trouvé' });
  res.json(event);
});

/// POST /api/events/join — Validation d'un code d'invitation.
/// Body: { code: "MANIF-123" }
/// Retourne le JSON complet de l'événement (trajet, horaires, etc.).
router.post('/events/join', (req, res) => {
  const { code } = req.body || {};
  if (!code) return res.status(400).json({ error: 'code requis' });

  const event = store.getEventByCode(code);
  if (!event) return res.status(404).json({ error: 'Code d\'invitation invalide' });

  // Vérification de la validité temporelle.
  const now = new Date();
  if (event.endAt && new Date(event.endAt) < now) {
    return res.status(410).json({ error: 'Cet événement est terminé' });
  }

  res.json({
    success: true,
    event: {
      code: event.code,
      title: event.title,
      startAt: event.startAt,
      visibleAt: event.visibleAt || event.startAt,
      routeGeoJson: event.routeGeoJson,
      waypoints: event.waypoints,
      pois: event.pois,
      careCenters: event.careCenters,
      exitPoints: event.exitPoints,
      safeZones: event.safeZones,
      destinationLatitude: event.destinationLatitude,
      destinationLongitude: event.destinationLongitude,
    },
  });
});

/// POST /api/events/create — ADMIN : crée un événement.
router.post('/events/create', (req, res) => {
  const { code, title, startAt, endAt, visibleAt, routeGeoJson, waypoints, pois, careCenters, exitPoints, safeZones, destinationLatitude, destinationLongitude } = req.body || {};

  if (!code || !title || !startAt) {
    return res.status(400).json({ error: 'code, title, startAt requis' });
  }

  const event = {
    code: code.toUpperCase(),
    title,
    startAt,
    endAt: endAt || null,
    visibleAt: visibleAt || startAt,
    routeGeoJson: routeGeoJson || '',
    waypoints: waypoints || [],
    pois: pois || [],
    careCenters: careCenters || [],
    exitPoints: exitPoints || [],
    safeZones: safeZones || [],
    destinationLatitude,
    destinationLongitude,
  };

  const saved = store.addEvent(event);
  sync.pushEvent(saved).catch(() => {});
  res.status(201).json(saved);
});

// ═══════════════════════════════════════════════════════════════════════
// PANIC (Alerte collective)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/panic/collective — Ping PANIC d'un utilisateur.
router.post('/panic/collective', (req, res) => {
  const { lat, lng, userId } = req.body || {};
  if (lat == null || lng == null) {
    return res.status(400).json({ error: 'lat, lng requis' });
  }

  const result = store.addPanicPing({
    id: uuidv4(),
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    userId: userId || 'anonymous',
  });

  if (result.aggregated) {
    // Génère automatiquement une zone de danger.
    const dangerZone = store.addAlert({
      id: uuidv4(),
      type: 'collective_danger',
      lat: result.lat,
      lng: result.lng,
      description: result.description,
      votes: ['SYSTEM_AUTO'],
      status: 'active',
    });
    sync.pushAlert(dangerZone).catch(() => {});
  }

  res.json(result);
});

// ═══════════════════════════════════════════════════════════════════════
// STATUS (Observabilité)
// ═══════════════════════════════════════════════════════════════════════

router.get('/status', (req, res) => {
  res.json({
    serverType: config.serverType,
    port: config.port,
    partnerUrl: config.partnerUrl,
    sync: store.syncState,
    alerts: { total: store.alerts.length, active: store.getActiveAlerts().length },
    events: store.events.length,
    meshClients: store.meshClients.size,
    adminClients: store.adminClients.size,
    uptime: process.uptime(),
  });
});

router.get('/ping', (req, res) => {
  res.json({ pong: true, role: config.serverType, ts: new Date().toISOString() });
});

module.exports = router;