// server/src/routes/adminEvents.js
//
// Routes d'administration des EVENEMENTS (montees sous /api/admin/events).
//
// Objectif : permettre a un administrateur (ou un moderateur disposant de
// la permission `manageEvents`) de gerer depuis le dashboard web :
//   1. La liste des evenements (creation / modification / suppression).
//   2. Les POINTS de chaque evenement :
//        - `waypoints`   : points de passage du cortege (avec heure prevue)
//        - `exitPoints`  : points d'entree / sortie de cortege
//        - `safeZones`   : zones sures de repli (avec rayon)
//        - `careCenters` : medecins / centres de soins (street-medics)
//        - `pois`        : points remarquables (rassemblement syndicaliste)
//   3. Le TRAJET (`routeGeoJson`, polyline GeoJSON) et la destination.
//
// Les structures de donnees sont alignees sur le modele Flutter
// `EventModel` (lib/features/events/domain/models/event_model.dart) afin
// que les points geres depuis le dashboard soient directement exploitables
// par l'application mobile.

const express = require('express');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const store = require('../store');
const sync = require('../sync');
const { broadcast } = require('../services/broadcast');

const router = express.Router();

const log = (category, message) => console.log(`[ADMIN-EVENTS] [${category}] ${message}`);

// ===========================================================================
// CATALOGUE DES TYPES DE POINTS
// ===========================================================================
//
// Source de verite unique : le dashboard web consomme ce catalogue via
// `GET /api/admin/events/point-types` pour construire dynamiquement les
// formulaires d'ajout / edition. Ajouter un type ici suffit donc a le
// rendre gerable depuis l'interface.

const POINT_TYPES = [
  {
    key: 'waypoints',
    label: 'Point de passage (cortege)',
    icon: 'F1',
    color: '#d29922',
    ordered: true,
    fields: [
      { name: 'label', label: 'Libelle', type: 'text', required: true, default: 'Nouveau passage' },
      { name: 'scheduledAt', label: 'Heure de passage prevue', type: 'datetime-local', required: false },
    ],
  },
  {
    key: 'exitPoints',
    label: "Point d'entree / sortie",
    icon: 'E',
    color: '#ffa657',
    ordered: false,
    fields: [
      { name: 'label', label: 'Libelle', type: 'text', required: true, default: 'Nouvelle sortie' },
      { name: 'direction', label: 'Direction / indication', type: 'text', required: false },
    ],
  },
  {
    key: 'safeZones',
    label: 'Zone sure (repli)',
    icon: 'S',
    color: '#3fb950',
    ordered: false,
    fields: [
      { name: 'label', label: 'Libelle', type: 'text', required: true, default: 'Nouvelle zone sure' },
      { name: 'radius', label: 'Rayon (m)', type: 'number', required: false, default: 50, min: 5, max: 5000, step: 5 },
    ],
  },
  {
    key: 'careCenters',
    label: 'Medecin / centre de soins',
    icon: 'M',
    color: '#f85149',
    ordered: false,
    fields: [
      { name: 'label', label: 'Libelle', type: 'text', required: true, default: 'Nouveau centre de soins' },
      { name: 'contact', label: 'Contact (telephone / radio)', type: 'text', required: false },
      { name: 'notes', label: 'Notes (specialisation, capacite)', type: 'text', required: false },
    ],
  },
  {
    key: 'pois',
    label: 'Point remarquable (rassemblement)',
    icon: 'R',
    color: '#bc8cff',
    ordered: false,
    fields: [
      { name: 'label', label: 'Libelle', type: 'text', required: true, default: 'Nouveau point remarquable' },
      {
        name: 'icon', label: 'Icone', type: 'select', required: false, default: 'flag',
        options: ['flag', 'rally', 'water', 'medical', 'exit', 'safe', 'info'],
      },
    ],
  },
];

const POINT_TYPE_KEYS = POINT_TYPES.map(t => t.key);

// ===========================================================================
// UTILITAIRES
// ===========================================================================

/// Sanitise un point : ne conserve que les champs du type + lat/lng.
function sanitizePoint(typeKey, input = {}) {
  const type = POINT_TYPES.find(t => t.key === typeKey);
  if (!type) return null;

  const lat = Number(input.lat);
  const lng = Number(input.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  const point = { lat, lng };
  for (const f of type.fields) {
    let value = input[f.name];
    if (value === undefined || value === null || value === '') {
      if (f.default !== undefined) value = f.default;
      else continue;
    }
    if (f.type === 'number') {
      const n = Number(value);
      if (!Number.isFinite(n)) continue;
      if (f.min !== undefined) value = Math.max(f.min, n);
      else if (f.max !== undefined) value = Math.min(f.max, n);
      else value = n;
    } else {
      value = String(value);
    }
    point[f.name] = value;
  }
  if (!point.label) point.label = type.label;
  return point;
}

/// Normalise un evenement stocke : garantit la presence de tous les
/// tableaux de points et de la route, sans casser les evenements existants.
function normalizeEvent(event) {
  if (!event) return null;
  const out = { ...event };
  for (const key of POINT_TYPE_KEYS) {
    out[key] = Array.isArray(event[key]) ? event[key] : [];
  }
  if (typeof out.routeGeoJson !== 'string') out.routeGeoJson = '';
  if (out.destinationLatitude === undefined) out.destinationLatitude = null;
  if (out.destinationLongitude === undefined) out.destinationLongitude = null;
  if (out.generalZone === undefined) out.generalZone = null;
  return out;
}

/// Alias de compatibilite avec le modele Flutter (`route`, `destLat`...).
function withClientAliases(event) {
  const e = normalizeEvent(event);
  return {
    ...e,
    route: e.routeGeoJson,
    destLat: e.destinationLatitude,
    destLng: e.destinationLongitude,
  };
}

/// Diffuse la liste des evenements aux dashboards admin connectes.
function publishEvents() {
  broadcast('events_changed', { events: store.getAllEvents().map(withClientAliases) });
}

// ===========================================================================
// ROUTES
// ===========================================================================

/// Middleware : vérifie qu'un event_admin n'agit que sur ses événements attitrés.
function ensureEventScope(req, res, next) {
  if (req.user && req.user.role === 'event_admin') {
    const code = String(req.params.code || '').toUpperCase().trim();
    const managed = (req.user.managedEventCodes || []).map(c => String(c).toUpperCase().trim());
    if (code && !managed.includes(code)) {
      return res.status(403).json({
        error: `Accès refusé : vous n'êtes pas administrateur de l'événement ${code}`,
      });
    }
  }
  next();
}

router.param('code', (req, res, next) => {
  ensureEventScope(req, res, next);
});

/// GET /api/admin/events/point-types : Catalogue des types de points gerables.
router.get('/point-types', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  res.json({ types: POINT_TYPES });
});

/// GET /api/admin/events : Liste complete des evenements (avec leurs points).
router.get('/', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  let events = store.getAllEvents();
  if (req.user && req.user.role === 'event_admin') {
    const managed = (req.user.managedEventCodes || []).map(c => String(c).toUpperCase().trim());
    events = events.filter(e => managed.includes(String(e.code).toUpperCase().trim()));
  }
  res.json({ events: events.map(withClientAliases) });
});

/// GET /api/admin/events/:code : Detail d'un evenement.
router.get('/:code', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  const event = store.getEventByCode(req.params.code);
  if (!event) return res.status(404).json({ error: 'Evenement non trouve' });
  res.json(withClientAliases(event));
});

/// POST /api/admin/events : Cree un evenement.
/// Body: { code, title, startAt, endAt?, visibleAt?, generalZone? }
router.post('/', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const { code, title, startAt, endAt, visibleAt, generalZone } = req.body || {};
    if (!code || !title || !startAt) {
      return res.status(400).json({ error: 'code, title et startAt sont requis' });
    }
    const upper = String(code).toUpperCase().trim();
    if (store.getEventByCode(upper)) {
      return res.status(409).json({ error: `L'evenement ${upper} existe deja` });
    }

    const event = {
      code: upper,
      title: String(title),
      startAt,
      endAt: endAt || null,
      visibleAt: visibleAt || startAt,
      generalZone: generalZone || null,
      routeGeoJson: '',
      waypoints: [],
      pois: [],
      careCenters: [],
      exitPoints: [],
      safeZones: [],
      destinationLatitude: null,
      destinationLongitude: null,
    };

    const saved = store.addEvent(event);
    sync.enqueueEvent(saved);
    publishEvents();
    log('EVENT', `Cree : ${saved.code} - ${saved.title}`);
    res.status(201).json({ success: true, event: withClientAliases(saved) });
  } catch (err) {
    log('EVENT', `Erreur creation : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la creation de l evenement' });
  }
});

/// PUT /api/admin/events/:code : Modifie les metadonnees d'un evenement.
/// Body: { title?, startAt?, endAt?, visibleAt?, generalZone? }
router.put('/:code', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const patch = {};
    const body = req.body || {};
    for (const field of ['title', 'startAt', 'endAt', 'visibleAt', 'generalZone', 'status']) {
      if (body[field] !== undefined) patch[field] = body[field];
    }
    if (patch.title !== undefined && !String(patch.title).trim()) {
      return res.status(400).json({ error: 'Le titre ne peut pas etre vide' });
    }
    const updated = store.updateEvent(req.params.code, patch);
    // Clôture explicite : tombstone des signalements liés + broadcast temps réel.
    if (patch.status === 'closed') {
      store.closeEvent(req.params.code);
      broadcast('event_tombstoned', { code: req.params.code, status: 'closed' });
      broadcast('alerts_tombstoned', { eventCode: req.params.code });
    }
    if (!updated) return res.status(404).json({ error: 'Evenement non trouve' });
    sync.enqueueEvent(updated);
    publishEvents();
    log('EVENT', `Modifie : ${updated.code}`);
    res.json({ success: true, event: withClientAliases(updated) });
  } catch (err) {
    log('EVENT', `Erreur modification : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la modification de l evenement' });
  }
});

/// POST /api/admin/events/:code/close : Clôture un événement (tombstone des signalements liés).
router.post('/:code/close', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const code = String(req.params.code).toUpperCase();
    const updated = store.closeEvent(code);
    if (!updated) return res.status(404).json({ error: 'Evenement non trouve' });

    broadcast('event_tombstoned', { code, status: 'closed' });
    broadcast('alerts_tombstoned', { eventCode: code });
    sync.enqueueEvent(updated);
    publishEvents();

    log('EVENT', `Cloture (tombstone) : ${code}`);
    res.json({ success: true, event: withClientAliases(updated) });
  } catch (err) {
    log('EVENT', `Erreur cloture : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la cloture de l evenement' });
  }
});

/// DELETE /api/admin/events/:code : Supprime un événement (tombstone des signalements liés).
router.delete('/:code', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const code = String(req.params.code).toUpperCase();
    const event = store.getEventByCode(code);
    if (!event) return res.status(404).json({ error: 'Evenement non trouve' });

    // 1. Tombstone des signalements actifs rattachés à cet événement.
    const ts = store.tombstoneEvent(code);
    // 2. Suppression de l'événement et de ses points associés.
    store.removeEvent(code);

    // 3. Diffusion temps réel : effacement immédiat des éléments côté clients.
    broadcast('event_tombstoned', { code });
    if (ts.count) broadcast('alerts_tombstoned', { eventCode: code, alertIds: ts.alertIds });
    publishEvents();

    log('EVENT', `Supprime (tombstone) : ${code} — ${ts.count} alerte(s) liée(s)`);
    res.json({ success: true, eventCode: code, alertsTombstoned: ts.count });
  } catch (err) {
    log('EVENT', `Erreur suppression : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la suppression de l evenement' });
  }
});

// ===========================================================================
// POINTS DE L EVENEMENT
// ===========================================================================

/// POST /api/admin/events/:code/points/:typeKey : Ajoute un point.
/// Body: { lat, lng, ...champs propres au type }
router.post('/:code/points/:typeKey', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const { typeKey } = req.params;
    if (!POINT_TYPE_KEYS.includes(typeKey)) {
      return res.status(400).json({ error: `Type de point inconnu : ${typeKey}` });
    }
    const event = store.getEventByCode(req.params.code);
    if (!event) return res.status(404).json({ error: 'Evenement non trouve' });

    const point = sanitizePoint(typeKey, req.body || {});
    if (!point) return res.status(400).json({ error: 'lat et lng valides requis' });

    const list = Array.isArray(event[typeKey]) ? event[typeKey] : [];
    list.push(point);
    const updated = store.updateEvent(event.code, { [typeKey]: list });
    sync.enqueueEvent(updated);
    publishEvents();
    log('POINT', `Ajout ${typeKey} sur ${updated.code}`);
    res.status(201).json({ success: true, point, event: withClientAliases(updated) });
  } catch (err) {
    log('POINT', `Erreur ajout point : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de l ajout du point' });
  }
});

/// PUT /api/admin/events/:code/points/:typeKey/:index : Modifie un point.
/// Body: { lat?, lng?, ...champs propres au type }
router.put('/:code/points/:typeKey/:index', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const { typeKey } = req.params;
    const index = parseInt(req.params.index, 10);
    if (!POINT_TYPE_KEYS.includes(typeKey)) {
      return res.status(400).json({ error: `Type de point inconnu : ${typeKey}` });
    }
    const event = store.getEventByCode(req.params.code);
    if (!event) return res.status(404).json({ error: 'Evenement non trouve' });

    const list = Array.isArray(event[typeKey]) ? event[typeKey] : [];
    if (!Number.isInteger(index) || index < 0 || index >= list.length) {
      return res.status(404).json({ error: 'Point introuvable' });
    }

    const merged = { ...list[index], ...(req.body || {}) };
    const point = sanitizePoint(typeKey, merged);
    if (!point) return res.status(400).json({ error: 'lat et lng valides requis' });

    list[index] = point;
    const updated = store.updateEvent(event.code, { [typeKey]: list });
    sync.enqueueEvent(updated);
    publishEvents();
    log('POINT', `Modification ${typeKey}[${index}] sur ${updated.code}`);
    res.json({ success: true, point, event: withClientAliases(updated) });
  } catch (err) {
    log('POINT', `Erreur modification point : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la modification du point' });
  }
});

/// DELETE /api/admin/events/:code/points/:typeKey/:index : Supprime un point.
router.delete('/:code/points/:typeKey/:index', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const { typeKey } = req.params;
    const index = parseInt(req.params.index, 10);
    if (!POINT_TYPE_KEYS.includes(typeKey)) {
      return res.status(400).json({ error: `Type de point inconnu : ${typeKey}` });
    }
    const event = store.getEventByCode(req.params.code);
    if (!event) return res.status(404).json({ error: 'Evenement non trouve' });

    const list = Array.isArray(event[typeKey]) ? event[typeKey] : [];
    if (!Number.isInteger(index) || index < 0 || index >= list.length) {
      return res.status(404).json({ error: 'Point introuvable' });
    }

    list.splice(index, 1);
    const updated = store.updateEvent(event.code, { [typeKey]: list });
    sync.enqueueEvent(updated);
    publishEvents();
    log('POINT', `Suppression ${typeKey}[${index}] sur ${updated.code}`);
    res.json({ success: true, event: withClientAliases(updated) });
  } catch (err) {
    log('POINT', `Erreur suppression point : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la suppression du point' });
  }
});

/// POST /api/admin/events/:code/points/:typeKey/reorder : Reordonne les points.
/// Body: { from, to }
router.post('/:code/points/:typeKey/reorder', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const { typeKey } = req.params;
    if (!POINT_TYPE_KEYS.includes(typeKey)) {
      return res.status(400).json({ error: `Type de point inconnu : ${typeKey}` });
    }
    const event = store.getEventByCode(req.params.code);
    if (!event) return res.status(404).json({ error: 'Evenement non trouve' });

    const list = Array.isArray(event[typeKey]) ? event[typeKey] : [];
    const from = parseInt((req.body || {}).from, 10);
    const to = parseInt((req.body || {}).to, 10);
    if (!Number.isInteger(from) || !Number.isInteger(to)
        || from < 0 || from >= list.length || to < 0 || to >= list.length) {
      return res.status(400).json({ error: 'Index de reordonnancement invalide' });
    }

    const [moved] = list.splice(from, 1);
    list.splice(to, 0, moved);

    const updated = store.updateEvent(event.code, { [typeKey]: list });
    sync.enqueueEvent(updated);
    publishEvents();
    log('POINT', `Reordonnancement ${typeKey} sur ${updated.code}`);
    res.json({ success: true, event: withClientAliases(updated) });
  } catch (err) {
    log('POINT', `Erreur reordonnancement : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors du reordonnancement des points' });
  }
});

/// PUT /api/admin/events/:code/route : Modifie le trajet (polyline) et la destination.
/// Body: { routeGeoJson?, destinationLatitude?, destinationLongitude? }
router.put('/:code/route', authenticateToken, requirePermission('manageEvents'), (req, res) => {
  try {
    const event = store.getEventByCode(req.params.code);
    if (!event) return res.status(404).json({ error: 'Evenement non trouve' });

    const body = req.body || {};
    const patch = {};

    if (body.routeGeoJson !== undefined) {
      const route = String(body.routeGeoJson || '').trim();
      if (route) {
        try {
          const parsed = JSON.parse(route);
          if (!Array.isArray(parsed)) throw new Error('GeoJSON attendu sous forme de tableau');
          patch.routeGeoJson = JSON.stringify(parsed);
        } catch (e) {
          return res.status(400).json({ error: 'routeGeoJson invalide : tableau JSON attendu' });
        }
      } else {
        patch.routeGeoJson = '';
      }
    }

    for (const field of ['destinationLatitude', 'destinationLongitude']) {
      if (body[field] === undefined || body[field] === null || body[field] === '') continue;
      const n = Number(body[field]);
      if (!Number.isFinite(n)) return res.status(400).json({ error: `${field} invalide` });
      patch[field] = n;
    }

    const updated = store.updateEvent(event.code, patch);
    sync.enqueueEvent(updated);
    publishEvents();
    log('ROUTE', `Trajet mis a jour pour ${updated.code}`);
    res.json({ success: true, event: withClientAliases(updated) });
  } catch (err) {
    log('ROUTE', `Erreur mise a jour trajet : ${err.message}`);
    res.status(500).json({ error: 'Erreur interne lors de la mise a jour du trajet' });
  }
});

module.exports = router;
module.exports.POINT_TYPES = POINT_TYPES;
