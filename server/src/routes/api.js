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
const { authenticateToken, requireRole, requireScout, requireSuperAdmin, canManageRoleMiddleware } = require('../middleware/auth');
const scoutService = require('../auth/scoutService');
const eventAdminService = require('../auth/eventAdminService');

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
/// Body: { type, lat, lng, description?, userId, eventId? }
/// Retourne l'alerte créée ou mise à jour, avec son statut de consensus.
/// Protégé par reportLimiter (3 signalements max / 5 min / IP).
router.post('/alerts', reportLimiter, (req, res) => {
  // Les variables sont déclarées HORS du bloc try pour rester
  // accessibles dans la suite du handler (validation du type, etc.).
  let type, lat, lng, description, userId, eventId;
  try {
    if (!req.body || Object.keys(req.body).length === 0) {
      console.error('[API] POST /api/alerts — body vide ou mal formé');
      return res.status(400).json({ error: 'body JSON requis' });
    }

    ({ type, lat, lng, description, userId, eventId } = req.body);
    console.log(`[API] POST /api/alerts — type=${type} lat=${lat} lng=${lng} userId=${userId || 'anon'} eventId=${eventId || 'auto'}`);

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

  // ── Cycle de vie lié à l'événement suivi : rattachement obligatoire
  const resolvedEventCode = eventId
    ? String(eventId).toUpperCase().trim()
    : (userId ? store.getUserCurrentEvent(userId) : null);

  if (!resolvedEventCode) {
    return res.status(409).json({
      error: 'Aucun événement suivi — le signalement doit être rattaché à un événement actif',
    });
  }

  const linkedEvent = store.getEventByCode(resolvedEventCode);
  if (!linkedEvent) {
    return res.status(400).json({ error: `Événement inconnu : ${resolvedEventCode}` });
  }
  if (linkedEvent.status === 'closed') {
    return res.status(400).json({ error: `L'événement ${resolvedEventCode} est clôturé` });
  }
  if (userId) {
    store.setUserCurrentEvent(userId, resolvedEventCode);
  }

  // ── Privilège Éclaireur : validation instantanée (bypass consensus 3 votes)
  let isScout = false;
  if (userId) {
    isScout = scoutService.isScout(userId);
  }
  if (!isScout) {
    const authHeader = req.headers['authorization'];
    if (authHeader && authHeader.startsWith('Bearer ')) {
      try {
        const decoded = jwt.verify(authHeader.slice(7), config.jwtSecret, { algorithms: ['HS256'] });
        if (decoded && (decoded.role === 'scout' || decoded.role === 'admin' || decoded.role === 'superadmin')) {
          isScout = true;
          if (!userId && decoded.username) userId = decoded.username;
        }
      } catch (_) {}
    }
  }

  const alert = {
    id: uuidv4(),
    type,
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    description: description || '',
    userId,
    eventId: resolvedEventCode,
    votes: isScout ? [] : (userId ? [userId] : []),
    status: isScout ? 'validated' : 'active',
    scoutValidated: isScout,
    uploadedTo: '',
  };

  // 1) Anti-doublon : fusion si même type à ≤ 50 m
  const merged = !isScout ? store.mergeNearbyIdentical(alert) : null;
  const saved = merged || store.addAlert(alert);

  // 2) Détection de signalement contradictoire/différent au même endroit (≤ 50 m)
  const conflicts = store.findContradictoryNearby(saved);
  if (conflicts.length > 0) {
    const nowIso = new Date().toISOString();
    saved.validationRequestedAt = nowIso;
    for (const c of conflicts) {
      c.validationRequestedAt = nowIso;
    }
    broadcastToAll('validation_requested', {
      reason: 'contradictory_report',
      conflictingAlert: { ...saved, votes: saved.votes || [] },
      targetAlerts: conflicts.map(c => ({ ...c, votes: c.votes || [] })),
      radiusMeters: 100,
    });
  }

  // Réplication vers le Backup via outbox (retry automatique).
  sync.enqueueAlert(saved);

  // Diffusion temps réel :
  //   - Éclaireur : validation immédiate (bypass consensus).
  //   - Citoyen : validation dès atteinte du seuil de consensus.
  const validated = isScout || ((saved.votes || []).length >= config.consensusThreshold);
  if (validated) {
    broadcastToAll('report_validated', { alert: { ...saved, votes: saved.votes || [] } });
  }

  res.status(201).json({
    alert: { ...saved, votes: saved.votes || [] },
    votesCount: (saved.votes || []).length,
    consensusThreshold: config.consensusThreshold,
    validated,
    scoutValidated: isScout,
    merged: Boolean(merged),
    validationRequested: conflicts.length > 0,
    conflicts: conflicts.map(c => ({ id: c.id, type: c.type, lat: c.lat, lng: c.lng })),
  });
});

/// GET /api/alerts/validation-requests — Demandes dynamiques de validation pour les utilisateurs proches.
/// Sollicite les utilisateurs à portée si :
///   a) Aucun vote/confirmation n'a été enregistré depuis ≥ 5 minutes (stale_5min).
///   b) Un signalement contradictoire/différent existe au même endroit (contradictory_report).
router.get('/alerts/validation-requests', (req, res) => {
  const { lat, lng, radius_m, inactivity_ms } = req.query;
  const inactivityMs = inactivity_ms ? parseInt(inactivity_ms, 10) : 5 * 60 * 1000;
  const radiusMeters = radius_m ? parseFloat(radius_m) : 150;

  const staleAlerts = store.getStaleAlertsForValidation(inactivityMs, 60 * 1000);
  const requests = [];
  const seenIds = new Set();

  for (const a of staleAlerts) {
    if (lat != null && lng != null) {
      const dist = store._haversine(parseFloat(lat), parseFloat(lng), a.lat, a.lng);
      if (dist > radiusMeters) continue;
    }
    seenIds.add(a.id);
    requests.push({
      reason: 'stale_5min',
      alert: { ...a, votes: a.votes || [], downvotes: a.downvotes || [] },
    });
  }

  // Vérifier également les paires de signalements contradictoires au même endroit
  for (const a of store.alerts) {
    if (!a || a.status === 'rejected' || a.status === 'voided' || a.status === 'tombstone') continue;
    if (seenIds.has(a.id)) continue;
    if (lat != null && lng != null) {
      const dist = store._haversine(parseFloat(lat), parseFloat(lng), a.lat, a.lng);
      if (dist > radiusMeters) continue;
    }
    const conflicts = store.findContradictoryNearby(a);
    if (conflicts.length > 0) {
      seenIds.add(a.id);
      requests.push({
        reason: 'contradictory_report',
        alert: { ...a, votes: a.votes || [], downvotes: a.downvotes || [] },
        conflictsWith: conflicts.map(c => ({ id: c.id, type: c.type })),
      });
    }
  }

  if (staleAlerts.length > 0) {
    const nowIso = new Date().toISOString();
    for (const s of staleAlerts) s.validationRequestedAt = nowIso;
    broadcastToAll('validation_requested', {
      reason: 'stale_5min',
      targetAlerts: staleAlerts.map(a => ({ ...a, votes: a.votes || [] })),
      radiusMeters,
    });
  }

  res.json({ requests, count: requests.length });
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
    const nowIso = new Date().toISOString();
    alert.lastVoteAt = nowIso;
    alert.updatedAt = nowIso;

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

/// POST /api/alerts/:id/verify — Réponse citoyenne à une demande de validation dynamique.
/// Body: { userId, vote: 'confirm' | 'refute' } (ou { userId, confirmed: boolean })
/// Purge automatiquement le signalement erroné si infirmé.
router.post('/alerts/:id/verify', (req, res) => {
  const { userId, vote, confirmed } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'userId requis' });

  const isConfirmed = confirmed !== undefined
    ? Boolean(confirmed)
    : (vote === 'confirm' || vote === 'yes' || vote === 'oui');

  const result = store.recordValidationVote(req.params.id, userId, isConfirmed);
  if (!result) return res.status(404).json({ error: 'Alerte non trouvée' });

  sync.enqueueAlert(result.alert);

  if (result.purged) {
    broadcastToAll('report_rejected', {
      alert: { ...result.alert, votes: result.alert.votes || [] },
      reason: 'community_refuted',
    });
  } else if (result.validated) {
    broadcastToAll('report_validated', {
      alert: { ...result.alert, votes: result.alert.votes || [] },
    });
  }

  res.json({
    success: true,
    purged: result.purged,
    validated: result.validated,
    votesCount: result.votesCount,
    downvotesCount: result.downvotesCount,
    alert: result.alert,
  });
});

/// POST /api/alerts/:id/reject — ADMIN : révoque un signalement (modération).
router.post('/alerts/:id/reject', authenticateToken, requireRole(['admin', 'superadmin', 'event_admin']), (req, res) => {
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: 'Alerte non trouvée' });
  if (req.user.role === 'event_admin') {
    const managed = req.user.managedEventCodes || [];
    if (!alert.eventId || !managed.includes(alert.eventId)) {
      return res.status(403).json({ error: 'Ce signalement n\'appartient pas à vos événements gérés' });
    }
  }
  alert.status = 'rejected';
  alert.updatedAt = new Date().toISOString();
  sync.enqueueAlert(alert);
  // Diffusion temps réel du rejet aux clients mobiles.
  broadcastToAll('report_rejected', { alert: { ...alert, votes: alert.votes || [] } });
  res.json({ success: true, message: 'Signalement révoqué' });
});

/// POST /api/alerts/:id/void — Annulation d'un faux signalement par un éclaireur.
/// Statut : 'voided' (tombstone vers le Backup).
router.post('/alerts/:id/void', authenticateToken, requireScout, (req, res) => {
  const alert = store.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: 'Alerte non trouvée' });
  if (alert.status === 'voided') return res.status(400).json({ error: 'Signalement déjà annulé' });
  if (alert.status === 'rejected') return res.status(400).json({ error: 'Signalement déjà révoqué' });

  const voided = store.voidAlert(req.params.id, req.user?.username || req.user?.role);
  if (!voided) return res.status(404).json({ error: 'Alerte non trouvée' });

  const updated = store.alerts.find(a => a.id === req.params.id);
  sync.enqueueAlert(updated);
  broadcastToAll('report_voided', { alert: { ...updated, votes: updated.votes || [] } });
  res.json({ success: true, message: 'Signalement annulé (faux signalement)', alert: updated });
});

/// POST /api/user/follow-event — Lie un utilisateur à l'événement suivi.
/// Body: { userId, eventCode } (si eventCode est null/vide, supprime le suivi)
router.post('/user/follow-event', (req, res) => {
  const { userId, eventCode } = req.body || {};
  if (!userId) {
    return res.status(400).json({ error: 'userId requis' });
  }
  if (!eventCode) {
    store.removeUserCurrentEvent(userId);
    return res.json({ success: true, userId, eventCode: null });
  }
  const upper = String(eventCode).toUpperCase().trim();
  const event = store.getEventByCode(upper);
  if (!event) {
    return res.status(404).json({ error: `Événement non trouvé : ${upper}` });
  }
  if (event.status === 'closed') {
    return res.status(410).json({ error: 'Cet événement est clôturé' });
  }
  store.setUserCurrentEvent(userId, upper);
  res.json({ success: true, userId, eventCode: upper });
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

/// POST /api/events/create — ADMIN : crée un événement (compatible tous rôles ayant manageEvents).
router.post('/events/create', authenticateToken, requireRole(['admin', 'superadmin', 'event_admin', 'moderator']), (req, res) => {
  const { code, title, startAt, endAt, visibleAt, generalZone, routeGeoJson, waypoints, pois, careCenters, exitPoints, safeZones, destinationLatitude, destinationLongitude } = req.body || {};

  const cleanCode = String(code || '').toUpperCase().trim();
  const cleanTitle = String(title || '').trim();
  if (!cleanCode || !cleanTitle) {
    return res.status(400).json({ error: 'code et title sont requis' });
  }
  if (store.getEventByCode(cleanCode)) {
    return res.status(409).json({ error: `L'événement ${cleanCode} existe déjà` });
  }

  const effectiveStartAt = startAt && !isNaN(new Date(startAt).getTime())
    ? new Date(startAt).toISOString()
    : new Date().toISOString();

  const event = {
    code: cleanCode,
    title: cleanTitle,
    startAt: effectiveStartAt,
    endAt: endAt || null,
    visibleAt: visibleAt || effectiveStartAt,
    generalZone: generalZone || null,
    routeGeoJson: routeGeoJson || '',
    waypoints: waypoints || [],
    pois: pois || [],
    careCenters: careCenters || [],
    exitPoints: exitPoints || [],
    safeZones: safeZones || [],
    destinationLatitude: destinationLatitude !== undefined && destinationLatitude !== '' ? Number(destinationLatitude) : null,
    destinationLongitude: destinationLongitude !== undefined && destinationLongitude !== '' ? Number(destinationLongitude) : null,
  };

  const saved = store.addEvent(event);
  sync.enqueueEvent(saved);
  res.status(201).json({ success: true, event: saved, ...saved });
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

    // ── 1. Compte admin principal (ADMIN_HASH)
    if (username === config.adminUsername) {
      const isDevPlaceholder =
        process.env.NODE_ENV !== 'production' &&
        config.adminHash === '$2b$12$dev-placeholder-change-in-production-hash';
      const passwordValid = isDevPlaceholder
        ? password === 'admin123'
        : await bcrypt.compare(password, config.adminHash);
      if (!passwordValid) {
        console.log(`[AUTH] Mot de passe incorrect pour "${username}"`);
        return res.status(401).json({ error: 'Identifiants invalides' });
      }

      const tokenPayload = {
        role: 'admin',
        username: config.adminUsername,
      };

      const token = jwt.sign(tokenPayload, config.jwtSecret, {
        algorithm: 'HS256',
        expiresIn: config.jwtExpiresIn,
      });

      console.log(`[AUTH] Connexion admin réussie — "${username}" — token valide ${config.jwtExpiresIn}`);

      return res.json({
        success: true,
        token,
        expiresIn: config.jwtExpiresIn,
        role: 'admin',
      });
    }

    // ── 2. Compte éclaireur
    const scout = await scoutService.verify(username, password);
    if (scout) {
      const tokenPayload = {
        role: 'scout',
        username: scout.username,
        permissions: scout.permissions,
      };

      const token = jwt.sign(tokenPayload, config.jwtSecret, {
        algorithm: 'HS256',
        expiresIn: config.jwtExpiresIn,
      });

      console.log(`[AUTH] Connexion éclaireur réussie — "${username}" — token valide ${config.jwtExpiresIn}`);

      return res.json({
        success: true,
        token,
        expiresIn: config.jwtExpiresIn,
        role: 'scout',
      });
    }

    // ── 3. Compte admin d'événement
    const eventAdmin = await eventAdminService.verify(username, password);
    if (eventAdmin) {
      const tokenPayload = {
        role: 'event_admin',
        username: eventAdmin.username,
        permissions: eventAdmin.permissions,
        managedEventCodes: eventAdmin.managedEventCodes,
      };

      const token = jwt.sign(tokenPayload, config.jwtSecret, {
        algorithm: 'HS256',
        expiresIn: config.jwtExpiresIn,
      });

      console.log(`[AUTH] Connexion admin événement réussie — "${username}" — token valide ${config.jwtExpiresIn}`);

      return res.json({
        success: true,
        token,
        expiresIn: config.jwtExpiresIn,
        role: 'event_admin',
      });
    }

    // ── Aucun compte trouvé
    console.log(`[AUTH] Tentative de connexion — utilisateur inconnu : "${username}"`);
    // Délai artificiel pour contrer le timing attack sur le username.
    await new Promise(resolve => setTimeout(resolve, 500));
    return res.status(401).json({ error: 'Identifiants invalides' });

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

/// GET /api/admin/scouts — Liste des éclaireurs (réservé Superadmin).
router.get('/admin/scouts', authenticateToken, requireSuperAdmin, (req, res) => {
  res.json({ scouts: scoutService.list() });
});

/// POST /api/admin/scouts — Créer un éclaireur (réservé Superadmin).
/// Body: { username, displayName?, permissions?, password? }
router.post('/admin/scouts', authenticateToken, requireSuperAdmin, async (req, res) => {
  try {
    const { username, displayName, permissions, password } = req.body || {};
    const result = await scoutService.create(username, { displayName, permissions, password });
    if (result.error) return res.status(400).json({ error: result.error });
    res.status(201).json({ success: true, scout: result.scout });
  } catch (err) {
    console.error('[ADMIN] Erreur création scout:', err.message);
    res.status(500).json({ error: 'Erreur interne lors de la création de l\'éclaireur' });
  }
});

/// PUT /api/admin/scouts/:id — Modifier un éclaireur (réservé Superadmin).
/// Body: { displayName?, permissions? }
router.put('/admin/scouts/:id', authenticateToken, requireSuperAdmin, async (req, res) => {
  try {
    const { displayName, permissions } = req.body || {};
    const result = await scoutService.update(req.params.id, { displayName, permissions });
    if (result.error) return res.status(404).json({ error: result.error });
    res.json({ success: true, scout: result.scout });
  } catch (err) {
    console.error('[ADMIN] Erreur modification scout:', err.message);
    res.status(500).json({ error: 'Erreur interne lors de la modification de l\'éclaireur' });
  }
});

/// DELETE /api/admin/scouts/:id — Supprimer un éclaireur (réservé Superadmin).
router.delete('/admin/scouts/:id', authenticateToken, requireSuperAdmin, (req, res) => {
  const ok = scoutService.remove(req.params.id);
  if (!ok) return res.status(404).json({ error: 'Éclaireur non trouvé' });
  res.json({ success: true });
});

/// GET /api/admin/event-admins — Liste des admins d'événements (réservé Superadmin).
router.get('/admin/event-admins', authenticateToken, requireSuperAdmin, (req, res) => {
  res.json({ admins: eventAdminService.list() });
});

/// POST /api/admin/event-admins — Créer un admin d'événement (réservé Superadmin).
/// Body: { username, displayName?, permissions?, managedEventCodes?, password? }
router.post('/admin/event-admins', authenticateToken, requireSuperAdmin, async (req, res) => {
  try {
    const { username, displayName, permissions, managedEventCodes, password } = req.body || {};
    const result = await eventAdminService.create(username, { displayName, permissions, managedEventCodes, password });
    if (result.error) return res.status(400).json({ error: result.error });
    res.status(201).json({ success: true, admin: result.admin });
  } catch (err) {
    console.error('[ADMIN] Erreur création admin événement:', err.message);
    res.status(500).json({ error: 'Erreur interne lors de la création de l\'admin d\'événement' });
  }
});

/// PUT /api/admin/event-admins/:id — Modifier un admin d'événement (réservé Superadmin).
/// Body: { displayName?, permissions?, managedEventCodes? }
router.put('/admin/event-admins/:id', authenticateToken, requireSuperAdmin, async (req, res) => {
  try {
    const { displayName, permissions, managedEventCodes } = req.body || {};
    const result = await eventAdminService.update(req.params.id, { displayName, permissions, managedEventCodes });
    if (result.error) return res.status(404).json({ error: result.error });
    res.json({ success: true, admin: result.admin });
  } catch (err) {
    console.error('[ADMIN] Erreur modification admin événement:', err.message);
    res.status(500).json({ error: 'Erreur interne lors de la modification de l\'admin d\'événement' });
  }
});

/// DELETE /api/admin/event-admins/:id — Supprimer un admin d'événement (réservé Superadmin).
router.delete('/admin/event-admins/:id', authenticateToken, requireSuperAdmin, (req, res) => {
  const ok = eventAdminService.remove(req.params.id);
  if (!ok) return res.status(404).json({ error: 'Admin d\'événement non trouvé' });
  res.json({ success: true });
});

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

// ═══════════════════════════════════════════════════════════════════════
// PARTAGE D'ÉVÉNEMENT / DEEP LINKING & REDIRECTION PLAY STORE
// ═══════════════════════════════════════════════════════════════════════

const PLAY_STORE_PACKAGE = 'com.example.flutter_streetphare';
const PLAY_STORE_URL = `https://play.google.com/store/apps/details?id=${PLAY_STORE_PACKAGE}`;

function handleInviteRequest(req, res) {
  const rawCode = (req.query.code || '').toString().trim().toUpperCase();
  const rawData = (req.query.data || '').toString().trim();
  const session = (req.query.session || '').toString().trim();

  let eventObj = null;
  if (rawData) {
    for (const enc of ['base64url', 'base64']) {
      try {
        const parsed = JSON.parse(Buffer.from(rawData, enc).toString('utf8'));
        if (parsed && typeof parsed === 'object') { eventObj = parsed; break; }
      } catch (_) {}
    }
  }

  const effectiveCode = rawCode || (eventObj && eventObj.code ? String(eventObj.code).toUpperCase() : '');
  if (!eventObj && effectiveCode) {
    const stored = store.getEventByCode(effectiveCode);
    if (stored) {
      eventObj = {
        code: stored.code,
        title: stored.title,
        startAt: stored.startAt,
        visibleAt: stored.visibleAt || stored.startAt,
        route: stored.routeGeoJson || '',
        destLat: stored.destinationLatitude,
        destLng: stored.destinationLongitude,
        waypoints: stored.waypoints || [],
        pois: stored.pois || [],
        careCenters: stored.careCenters || [],
        exitPoints: stored.exitPoints || [],
        safeZones: stored.safeZones || [],
      };
    }
  }

  const encodedData = rawData || (eventObj ? Buffer.from(JSON.stringify(eventObj), 'utf8').toString('base64url') : '');
  const queryParts = [];
  if (effectiveCode) queryParts.push(`code=${encodeURIComponent(effectiveCode)}`);
  if (encodedData) queryParts.push(`data=${encodeURIComponent(encodedData)}`);
  if (session) queryParts.push(`session=${encodeURIComponent(session)}`);
  const queryString = queryParts.join('&');

  const deepLink = `streetphare://invite${queryString ? '?' + queryString : ''}`;
  const referrer = encodeURIComponent(queryString || 'utm_source=streetphare_share');
  const playStoreRedirectUrl = `${PLAY_STORE_URL}&referrer=${referrer}`;
  const androidIntentUrl =
    `intent://invite${queryString ? '?' + queryString : ''}#Intent;` +
    `scheme=streetphare;package=${PLAY_STORE_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(playStoreRedirectUrl)};end`;

  const wantsJson =
    req.query.format === 'json' ||
    (req.headers.accept && req.headers.accept.includes('application/json') && !req.headers.accept.includes('text/html'));

  if (wantsJson) {
    return res.json({
      success: true,
      code: effectiveCode || null,
      session: session || null,
      event: eventObj,
      deepLink,
      androidIntentUrl,
      playStoreUrl: playStoreRedirectUrl,
    });
  }

  const title = (eventObj && eventObj.title) ? String(eventObj.title) : (effectiveCode || 'Invitation StreetPhare');
  const safeTitle = title.replace(/[<>&"']/g, '');
  const safeCode = (effectiveCode || 'N/A').replace(/[<>&"']/g, '');

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(`<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>StreetPhare — ${safeTitle}</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #12181B; color: #F5F7F8; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }
    .card { max-width: 420px; width: 100%; background: #1E272C; border: 1px solid #FFB300; border-radius: 16px; padding: 24px; text-align: center; }
    h1 { color: #FFB300; font-size: 20px; margin-top: 0; }
    .code { font-family: monospace; font-size: 16px; background: rgba(255,179,0,0.12); color: #FFB300; padding: 8px 14px; border-radius: 8px; display: inline-block; margin: 12px 0; }
    .btn { display: block; width: 100%; padding: 14px; margin-top: 12px; border-radius: 10px; font-weight: 700; text-decoration: none; box-sizing: border-box; }
    .btn-primary { background: #FFB300; color: #000; }
    .btn-store { background: transparent; color: #FFB300; border: 1.5px solid #FFB300; }
    p { color: #B0BEC5; font-size: 14px; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <h1>StreetPhare — Invitation</h1>
    <p>Invitation à rejoindre l'événement <strong>${safeTitle}</strong>.</p>
    <div class="code">Code : ${safeCode}</div>
    <a id="open-app" class="btn btn-primary" href="${deepLink}">Ouvrir dans StreetPhare</a>
    <a id="open-store" class="btn btn-store" href="${playStoreRedirectUrl}">Installer depuis Google Play</a>
    <p style="font-size:12px; margin-top:16px;">Redirection automatique vers l'application ou le Play Store…</p>
  </div>
  <script>
    (function() {
      var deepLink = ${JSON.stringify(deepLink)};
      var storeUrl = ${JSON.stringify(playStoreRedirectUrl)};
      var hidden = false;
      document.addEventListener('visibilitychange', function() { if (document.hidden) hidden = true; });
      window.location.href = deepLink;
      setTimeout(function() { if (!hidden) window.location.replace(storeUrl); }, 1800);
    })();
  </script>
</body>
</html>`);
}

router.get('/invite', handleInviteRequest);

module.exports = router;
module.exports.handleInviteRequest = handleInviteRequest;


