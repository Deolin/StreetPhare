// server/src/routes/api.js
// Routes API REST pour l'application Flutter StreetPhare.

const express = require('express');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');
const store = require('../store');
const sync = require('../sync');
const { broadcastToAll } = require('../services/broadcast');
const { routingEngine } = require('../services/routing');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();

// ═══════════════════════════════════════════════════════════════════════
// RATE LIMITERS DÉDIÉS (anti-spam / anti-DoS)
// ═══════════════════════════════════════════════════════════════════════

/// Limiteur strict pour les signalements citoyens (alertes + panic).
/// Un citoyen réel ne déclare pas plus de 3 alertes majeures en 5 minutes.
const reportLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 minutes
  limit: 3,
  standardHeaders: true,  // headers RateLimit-*
  legacyHeaders: false,   // désactive X-RateLimit-* (obsolètes)
  message: {
    error: 'Trop de signalements émis. Veuillez patienter avant de déclarer un nouvel événement.',
  },
  keyGenerator: (req) => {
    // Utilise l'IP réelle du citoyen transmise par Caddy via X-Forwarded-For.
    // `app.set('trust proxy', true)` dans primary.js/backup.js permet
    // à req.ip de retourner l'IP distante et non 127.0.0.1.
    return req.ip;
  },
});

/// Limiteur pour la messagerie / chat P2P (sync-push).
/// 15 messages par minute et par IP : fluide pour un humain, bloque un script.
const messageLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  limit: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Vitesse d\'envoi trop élevée. Ralentissez vos messages.',
  },
  keyGenerator: (req) => req.ip,
});

// ═══════════════════════════════════════════════════════════════════════
// ALERTS (Signalements citoyens)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/alerts — Réception d'un signalement.
/// Body: { type, lat, lng, description?, userId }
/// Retourne l'alerte créée ou mise à jour, avec son statut de consensus.
/// Protégé par reportLimiter (3 signalements max / 5 min / IP).
router.post('/alerts', reportLimiter, (req, res) => {
  // Les variables sont déclarées HORS du bloc try pour rester
  // accessibles dans la suite du handler (validation du type, etc.).
  let type, lat, lng, description, userId;
  try {
    if (!req.body || Object.keys(req.body).length === 0) {
      console.error('[API] POST /api/alerts — body vide ou mal formé');
      return res.status(400).json({ error: 'body JSON requis' });
    }

    ({ type, lat, lng, description, userId } = req.body);
    console.log(`[API] POST /api/alerts — type=${type} lat=${lat} lng=${lng} userId=${userId || 'anon'}`);

    if (!type || lat == null || lng == null) {
      return res.status(400).json({ error: 'type, lat, lng requis' });
    }
  } catch (e) {
    console.error('[API] POST /api/alerts — erreur parsing:', e.message);
    return res.status(400).json({ error: 'JSON invalide' });
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

  // Réplication vers le Backup via outbox (retry automatique).
  sync.enqueueAlert(saved);

  // Diffusion temps réel si le signalement est déjà validé (≥ seuil).
  if ((saved.votes || []).length >= config.consensusThreshold) {
    broadcastToAll('report_validated', { alert: { ...saved, votes: saved.votes || [] } });
  }

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

    // Réplication vers le Backup via outbox.
    sync.enqueueAlert(alert);
  }

  const validated = alert.votes.length >= config.consensusThreshold;

  // Diffusion temps réel : le signalement devient visible pour tout le
  // réseau (mobiles connectés + admin + Backup) dès le franchissement du seuil.
  if (validated && alert.status !== 'rejected') {
    broadcastToAll('report_validated', { alert: { ...alert, votes: alert.votes || [] } });
  }

  res.json({
    votesCount: alert.votes.length,
    validated,
    consensusThreshold: config.consensusThreshold,
  });
});

/// POST /api/alerts/:id/reject — ADMIN : révoque un signalement (modération).
router.post('/alerts/:id/reject', authenticateToken, requireRole(['admin']), (req, res) => {
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: 'Alerte non trouvée' });
  alert.status = 'rejected';
  alert.updatedAt = new Date().toISOString();
  sync.enqueueAlert(alert);
  // Diffusion temps réel du rejet aux clients mobiles.
  broadcastToAll('report_rejected', { alert: { ...alert, votes: alert.votes || [] } });
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

/// POST /api/sync/tombstone — Reçoit un tombstone (suppression/rejet) du Primary.
/// Applique la suppression/rejet localement afin que les clients du Backup
/// répercutent aussi la suppression.
router.post('/sync/tombstone', (req, res) => {
  const { id, reason } = req.body || {};
  if (!id) return res.status(400).json({ error: 'id requis' });
  store.applyTombstone(id, reason === 'rejected' ? 'rejected' : 'deleted');
  res.json({ success: true });
});

/// POST /api/v2/sync-push — Reçoit un batch d'alertes du client Flutter.
/// Body: { alerts: [{ id, type, lat, lng, description?, votes?: [], ... }], peerId, since }
/// Le serveur fusionne (upsert), puis répond avec les deltas plus récents
/// que le client n'a pas encore (push-pull bidirectionnel).
/// Protégé par messageLimiter (15 requêtes max / 1 min / IP).
router.post('/sync-push', messageLimiter, (req, res) => {
  try {
    const { alerts, peerId, since } = req.body || {};
    if (!Array.isArray(alerts) || alerts.length === 0) {
      return res.status(400).json({ error: 'alerts[] requis' });
    }

    let upserted = 0;
    for (const alert of alerts) {
      if (!alert.id || !alert.type || alert.lat == null || alert.lng == null) {
        continue; // skip malformed
      }
      // Éviter la « résurrection » : ne pas ré-ajouter une alerte supprimée/rejetée.
      if (store.isTombstoned(alert.id)) {
        continue;
      }
      // Ajouter le peerId aux votes s'il n'y est pas déjà.
      if (peerId && (!alert.votes || !alert.votes.includes(peerId))) {
        if (!alert.votes) alert.votes = [];
        alert.votes.push(peerId);
      }
      store.addAlert(alert);
      upserted++;
    }

    // Récupérer les deltas plus récents pour le client (push-pull).
    let deltas = [];
    let tombstones = [];
    if (since) {
      const sinceDate = new Date(since);
      deltas = store.getAllAlerts()
        .filter(a => {
          if (a.status === 'rejected') return false;
          const updated = new Date(a.updatedAt || a.createdAt);
          return updated > sinceDate;
        })
        .map(a => ({ ...a, votes: a.votes || [] }));
      // Suppressions/rejets côté serveur → à répercuter localement.
      tombstones = store.getTombstonesSince(since);
    }

    console.log(
      `[SYNC-PUSH] peer=${peerId || 'anon'} upserted=${upserted} deltas=${deltas.length} tombstones=${tombstones.length}`
    );

    res.json({
      success: true,
      upserted,
      deltas,
      tombstones,
      serverTs: new Date().toISOString(),
    });
  } catch (err) {
    console.error('[SYNC-PUSH] Erreur:', err.message);
    res.status(500).json({ error: err.message });
  }
});

/// GET /api/v2/sync-check — Point de pull pour le client (inchangé).
/// Query: ?since=ISO8601
router.get('/sync-check', (req, res) => {
  const since = req.query.since;
  const sinceDate = since ? new Date(since) : new Date(0);

  const items = store.getAllAlerts()
    .filter(a => {
      if (a.status === 'rejected') return false;
      const updated = new Date(a.updatedAt || a.createdAt);
      return updated > sinceDate;
    })
    .slice(0, 500) // limite à 500 par requête
    .map(a => ({ ...a, votes: a.votes || [] }));

  // Suppressions/rejets côté serveur → à répercuter localement.
  const tombstones = since ? store.getTombstonesSince(since) : [];

  res.json({
    items,
    count: items.length,
    tombstones,
    serverTs: new Date().toISOString(),
  });
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
// ROUTING (Calcul d'itinéraire)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/route — Calcul d'itinéraire avec profil de transport.
/// Body: { from: { lat, lon }, to: { lat, lon }, profile?: "car"|"foot"|"pedestrian", avoid_filters?: {...} }
/// Headers: X-StreetPhare-Route (piéton|voiture|vélo)
///
/// Le paramètre `profile` détermine le moteur de routage ciblé :
///   - "car" / "voiture" → port OSRM car (ex: 5001)
///   - "foot" / "piéton" / absent → port OSRM foot (ex: 5000)
router.post('/route', (req, res) => {
  const { from, to, profile: bodyProfile, avoid_filters } = req.body || {};
  const headerProfile = req.headers['x-streetphare-route'] || '';
  const queryProfile = req.query.profile || '';

  // Résolution du profil — priorité: body > header > query > défaut 'foot'
  const profileRaw = bodyProfile || headerProfile || queryProfile || 'foot';
  const isVehicle = profileRaw === 'car' || profileRaw === 'voiture' || profileRaw === 'vehicle';
  const profileLabel = isVehicle ? 'voiture' : 'piéton';

  // ── Log diagnostic horodaté ──────────────────────────────────────────
  const now = new Date();
  const ts = [
    String(now.getHours()).padStart(2, '0'),
    String(now.getMinutes()).padStart(2, '0'),
    String(now.getSeconds()).padStart(2, '0'),
  ].join(':');
  console.log(
    `[${ts}] [Routing] Calcul d'itinéraire requis — Profil détecté: ${profileLabel}`,
  );
  if (from && to) {
    console.log(
      `[${ts}] [Routing]   De: (${from.lat}, ${from.lon}) → Vers: (${to.lat}, ${to.lon})`,
    );
  }
  // ──────────────────────────────────────────────────────────────────────

  if (!from || !to || from.lat == null || from.lon == null || to.lat == null || to.lon == null) {
    console.log(`[${ts}] [Routing] ❌ Coordonnées invalides ou absentes`);
    return res.status(400).json({ error: 'from et to avec lat/lon requis' });
  }

  // TODO(Déploiement): Implémenter le proxy vers OSRM local selon le profil.
  // Pour l'instant, on retourne un itinéraire minimal en ligne droite
  // (fallback). Le client Flutter doit utiliser OsmAndBridge/GraphHopper
  // en priorité absolue ; ce endpoint est le mode dégradé serveur.

  // Construction d'une réponse de fallback cohérente.
  const points = [
    [from.lat, from.lon],
    [to.lat, to.lon],
  ];

  // Distance approximative (haversine).
  const R = 6371000;
  const dLat = ((to.lat - from.lat) * Math.PI) / 180;
  const dLon = ((to.lon - from.lon) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((from.lat * Math.PI) / 180) *
      Math.cos((to.lat * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const distanceM = Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));

  console.log(
    `[${ts}] [Routing] ✅ Itinéraire ${profileLabel} — ` +
      `distance ≈ ${distanceM} m (fallback ligne droite)`,
  );

  res.json({
    routes: [
      {
        id: 'fallback_route',
        polyline: points,
        distance_m: distanceM,
        safe_score: 0,
        profile: profileLabel,
      },
    ],
    source: 'server_fallback',
    profile: profileLabel,
  });
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
router.post('/events/create', authenticateToken, requireRole(['admin']), (req, res) => {
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
  sync.enqueueEvent(saved);
  res.status(201).json(saved);
});

// ═══════════════════════════════════════════════════════════════════════
// PANIC (Alerte collective)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/panic/collective — Ping PANIC d'un utilisateur.
/// Protégé par reportLimiter (3 signalements max / 5 min / IP).
router.post('/panic/collective', reportLimiter, (req, res) => {
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
    sync.enqueueAlert(dangerZone);
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

// ═══════════════════════════════════════════════════════════════════════
// AUTHENTIFICATION ADMIN (Login JWT)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/auth/login — Authentification administrateur.
/// Body: { username: "admin", password: "..." }
/// Retourne un token JWT signé HS256, valide 8h (configurable).
/// Le mot de passe est vérifié contre le hash bcrypt stocké dans
/// la variable d'environnement ADMIN_HASH (12 rounds de salage).
///
/// En développement, accepte le placeholder comme hash valide
/// (mot de passe : "admin123" hashé en bcrypt).
router.post('/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body || {};

    if (!username || !password) {
      return res.status(400).json({ error: 'username et password requis' });
    }

    // Vérification du nom d'utilisateur (constant, configurable).
    if (username !== config.adminUsername) {
      console.log(`[AUTH] Tentative de connexion — utilisateur inconnu : "${username}"`);
      // Délai artificiel pour contrer le timing attack sur le username.
      await new Promise(resolve => setTimeout(resolve, 500));
      return res.status(401).json({ error: 'Identifiants invalides' });
    }

    // Vérification du mot de passe via bcrypt (12 rounds).
    const passwordValid = await bcrypt.compare(password, config.adminHash);

    if (!passwordValid) {
      console.log(`[AUTH] Tentative de connexion — mot de passe incorrect pour "${username}"`);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }

    // Génération du token JWT.
    const tokenPayload = {
      role: 'admin',
      username: config.adminUsername,
    };

    const token = jwt.sign(tokenPayload, config.jwtSecret, {
      algorithm: 'HS256',
      expiresIn: config.jwtExpiresIn,
    });

    console.log(`[AUTH] Connexion réussie — "${username}" — token valide ${config.jwtExpiresIn}`);

    res.json({
      success: true,
      token,
      expiresIn: config.jwtExpiresIn,
      role: 'admin',
    });
  } catch (err) {
    console.error('[AUTH] Erreur login:', err.message);
    res.status(500).json({ error: 'Erreur interne lors de l\'authentification' });
  }
});

/// POST /api/auth/verify — Vérifie la validité d'un token JWT.
/// Body: { token: "eyJ..." }
/// Utile pour les clients qui veulent vérifier leur token sans
/// accéder à une route protégée.
router.post('/auth/verify', (req, res) => {
  try {
    const { token } = req.body || {};
    if (!token) {
      return res.status(400).json({ error: 'token requis' });
    }

    const decoded = jwt.verify(token, config.jwtSecret, {
      algorithms: ['HS256'],
    });

    res.json({
      valid: true,
      role: decoded.role,
      username: decoded.username,
      expiresAt: new Date(decoded.exp * 1000).toISOString(),
    });
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.json({ valid: false, error: 'Token expiré' });
    }
    res.json({ valid: false, error: 'Token invalide' });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// BUG REPORT (Signalement de bug depuis l'application Flutter)
// ═══════════════════════════════════════════════════════════════════════

/// POST /api/bug-report — Réception d'un rapport de bug.
/// Stocké en base et loggué console. Survit aux redémarrages.
router.post('/bug-report', (req, res) => {
  const {
    type, message, description, title,
    stackTrace, deviceInfo, appVersion, app_version,
    platform, category, extra_logs, client_timestamp, attempts,
    // fallback: `message` ou `description` sont acceptés
  } = req.body || {};

  const msg = message || description || '';
  if (!msg) {
    return res.status(400).json({ error: 'message ou description requis' });
  }

  const saved = store.addBugReport({
    type: category || type || 'report',
    message: msg,
    title: title || null,
    stackTrace: stackTrace || null,
    deviceInfo: deviceInfo || null,
    appVersion: appVersion || app_version || 'unknown',
    platform: platform || null,
    extraLogs: extra_logs || null,
    clientTimestamp: client_timestamp || null,
    attempts: attempts ?? 0,
  });

  const now = new Date();
  const ts = [
    String(now.getHours()).padStart(2, '0'),
    String(now.getMinutes()).padStart(2, '0'),
    String(now.getSeconds()).padStart(2, '0'),
    ' - ',
    String(now.getDate()).padStart(2, '0'),
    '/',
    String(now.getMonth() + 1).padStart(2, '0'),
  ].join('');

  console.log(`[${ts}] - [BUG] #${saved.id} ${saved.type || 'report'}${saved.title ? ' — ' + saved.title : ''}`);
  console.log(`[${ts}] - [BUG] Msg: ${msg.substring(0, 200)}`);
  if (stackTrace) console.log(`[${ts}] - [BUG] Stack:\n${stackTrace}`);
  if (saved.platform) console.log(`[${ts}] - [BUG] Platform: ${saved.platform}`);
  if (saved.appVersion !== 'unknown') console.log(`[${ts}] - [BUG] App version: ${saved.appVersion}`);
  if (saved.extraLogs) console.log(`[${ts}] - [BUG] Extra logs: ${saved.extraLogs.substring(0, 500)}`);

  res.status(201).json({ success: true, id: saved.id, receivedAt: saved.receivedAt });
});

/// GET /api/bug-reports — ADMIN : liste des rapports de bug.
/// Query: ?limit=50&offset=0
router.get('/bug-reports', authenticateToken, requireRole(['admin']), (req, res) => {
  const limit = parseInt(req.query.limit, 10) || 50;
  const offset = parseInt(req.query.offset, 10) || 0;
  const result = store.getBugReports({ limit, offset });
  res.json(result);
});

/// GET /api/bug-reports/:id — ADMIN : détail d'un rapport de bug.
router.get('/bug-reports/:id', authenticateToken, requireRole(['admin']), (req, res) => {
  const report = store.getBugReportById(req.params.id);
  if (!report) return res.status(404).json({ error: 'Rapport non trouvé' });
  res.json(report);
});

// ═══════════════════════════════════════════════════════════════════════
// MESH SYNC (Store-and-Forward — HTTP de secours pour clients 5G)
// ═══════════════════════════════════════════════════════════════════════

/// GET /api/mesh/sync — Récupère les messages mesh manqués.
/// Query: ?since=ISO8601 (timestamp de la dernière synchro du client).
/// Retourne un tableau JSON des messages postérieurs à ce timestamp.
/// Max 1000 messages par requête. Pas de limite hors since (retourne
/// les 1000 derniers).
///
/// Cette route est le fallback HTTP pour les clients qui subissent
/// des micro-coupures en 5G et ne peuvent pas maintenir le WebSocket.
router.get('/mesh/sync', (req, res) => {
  const { since } = req.query;
  const messages = store.getMeshMessagesSince(since || null);
  res.json({
    success: true,
    count: messages.length,
    messages,
    serverTs: new Date().toISOString(),
  });
});

// ═══════════════════════════════════════════════════════════════════════
// ROUTAGE PIÉTON (moteur serveur StreetPhare — priorité sur OSRM externe)
// ═══════════════════════════════════════════════════════════════════════

/// Parse la query `avoid=lat,lon,radius,weight|...` en liste de zones à risque.
function parseAvoidPoints(raw) {
  if (!raw) return [];
  return raw
    .split('|')
    .map((part) => {
      const [lat, lon, radius, weight] = part.split(',').map(Number);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
      return {
        lat,
        lon,
        radius: Number.isFinite(radius) ? radius : 5,
        weight: Number.isFinite(weight) ? weight : 1e6,
      };
    })
    .filter(Boolean);
}

/// GET /api/route — Calcule un itinéraire piéton via le moteur local Dijkstra.
/// Query: ?fromLat=..&fromLon=..&toLat=..&toLon=..
///        &avoid=lat,lon[,radius[,weight]]|...   (zones de danger à pénaliser)
router.get('/route', (req, res) => {
  const { fromLat, fromLon, toLat, toLon } = req.query;
  const lat1 = parseFloat(fromLat);
  const lon1 = parseFloat(fromLon);
  const lat2 = parseFloat(toLat);
  const lon2 = parseFloat(toLon);

  if ([lat1, lon1, lat2, lon2].some((v) => !Number.isFinite(v))) {
    return res.status(400).json({ error: 'fromLat, fromLon, toLat, toLon requis (nombres)' });
  }

  const avoidPoints = parseAvoidPoints(req.query.avoid);

  try {
    const r = routingEngine.route(lat1, lon1, lat2, lon2, avoidPoints);
    if (!r) {
      return res.status(404).json({
        error: 'Aucun itinéraire trouvé dans la zone couverte',
        routes: [],
      });
    }
    res.json({
      source: 'streetphare_server',
      routes: [
        {
          id: 'sp_server_0',
          label: 'Itinéraire piéton (serveur StreetPhare)',
          distanceMeters: r.distanceMeters,
          durationSeconds: r.durationSeconds,
          points: r.points,
        },
      ],
    });
  } catch (e) {
    console.error('[API] /route erreur :', e.message);
    res.status(500).json({ error: e.message, routes: [] });
  }
});

module.exports = router;
