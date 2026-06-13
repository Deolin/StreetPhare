// test_servers/modules/reports_store.js
//
// Module : Stockage des Signalements & Algorithme "Panic Collectif"
// ================================================================
// Responsabilités :
//   1. Stocker en mémoire les signalements (alertes) envoyés par les
//      utilisateurs, avec gestion stricte du cycle de vie (TTL).
//   2. Appliquer les règles de visibilité (votes >= 3 pour diffusion).
//   3. Implémenter l'algorithme "Panic Collectif" :
//      si 5 requêtes "Panic" géolocalisées arrivent en < 2 min dans
//      un rayon proche, générer automatiquement un "Danger Collectif".
//
// ── Règles de TTL côté serveur ────────────────────────────────────────────
//
//   Type                              TTL       Diffusion si votes >=
//   ─────────────────────────────────────────────────────────────────
//   barrage / casseurs / danger       600 s     3
//   policiers / autopompes / filtre   60 s      3
//   panic (individuel)                120 s     —  (alimente Panic Coll.)
//   danger_collectif (généré auto)    600 s     0  (toujours visible)
//
// ── Format d'un signalement entrant (POST /v1/reports) ───────────────────
//   {
//     id          : string (UUID côté client)
//     type        : 'barrage'|'casseurs'|'danger'|'policiers'|
//                   'autopompes'|'filtre'|'panic'
//     lat         : number
//     lon         : number
//     reporter_id : string (ID anonyme de l'appareil)
//     description : string (optionnel)
//     timestamp   : ISO8601 (optionnel, sinon now)
//   }
//
// ── Format de distribution (GET /v1/reports) ─────────────────────────────
//   {
//     reports: [
//       {
//         id         : string
//         type       : string
//         lat        : number
//         lon        : number
//         votes      : number
//         expires_at : ISO8601
//         is_collective_danger : boolean
//         description : string
//       }
//     ],
//     generated_at : ISO8601,
//     total_active : number
//   }
//
'use strict';

const { haversineM } = require('./events_manager');

// ── Constantes de configuration ────────────────────────────────────────────

/** TTL en secondes selon le type de signalement. */
const TTL_BY_TYPE = {
  barrage:           600,
  casseurs:          600,
  danger:            600,
  policiers:         60,
  autopompes:        60,
  filtre:            60,
  panic:             120,
  danger_collectif:  600,
  density:           300, // 5 minutes (fenêtre glissante)
};

/** Nombre de votes (signalements uniques) requis pour la diffusion. */
const VOTES_REQUIRED_FOR_DISTRIBUTION = 3;
const DENSITY_REQUIRED_FOR_DISTRIBUTION = 1; // La densité est informative dès le 1er signalement

/** Rayon de regroupement spatial pour Panic Collectif (mètres). */
const PANIC_CLUSTER_RADIUS_M = 200;

/** Nombre de requêtes panic dans le rayon pour déclencher un Danger Collectif. */
const PANIC_THRESHOLD_COUNT = 5;

/** Fenêtre temporelle pour Panic Collectif (secondes). */
const PANIC_WINDOW_S = 120;

// ── Structures de données en mémoire ──────────────────────────────────────

/**
 * Map principale des signalements actifs.
 * Clé : report.id
 * Valeur : ReportEntry (voir jsdoc ci-dessous)
 *
 * @type {Map<string, ReportEntry>}
 *
 * @typedef {Object} ReportEntry
 * @property {string}   id
 * @property {string}   type
 * @property {number}   lat
 * @property {number}   lon
 * @property {Set<string>} voters         - IDs des appareils ayant voté
 * @property {number}   createdAt         - timestamp ms
 * @property {number}   expiresAt         - timestamp ms
 * @property {boolean}  is_collective     - généré par Panic Collectif ?
 * @property {string}   description
 */
const reportStore = new Map();

/**
 * File des requêtes "panic" récentes (pour l'algorithme Panic Collectif).
 * Chaque entrée : { lat, lon, reporter_id, ts }
 * @type {Array<{lat:number, lon:number, reporter_id:string, ts:number}>}
 */
const panicQueue = [];

/**
 * Callbacks appelés lors d'un changement d'état du store.
 * (utilisé par le serveur pour mettre à jour le dashboard)
 * @type {Array<Function>}
 */
const changeListeners = [];

// ── Gestion des versions applicatives (Kill Switch) ────────────────────────

let appVersionInfo = {
  latest: '1.2.0',
  min_required: '1.1.0',
  url: 'https://streetphare.org/download'
};

function getVersionInfo() {
  return appVersionInfo;
}

function setVersionInfo(info) {
  appVersionInfo = { ...appVersionInfo, ...info };
}

// ── Nettoyage périodique (purge des entrées expirées) ─────────────────────

setInterval(() => {
  const now = Date.now();
  for (const [id, entry] of reportStore.entries()) {
    if (entry.expiresAt <= now) {
      reportStore.delete(id);
      _notifyChange('EXPIRE', id, entry);
    }
  }
  // Purger aussi la file panic
  const panicCutoff = now - PANIC_WINDOW_S * 1000;
  while (panicQueue.length > 0 && panicQueue[0].ts < panicCutoff) {
    panicQueue.shift();
  }
}, 5000); // vérification toutes les 5 secondes

// ── Helpers internes ──────────────────────────────────────────────────────

function _ttlForType(type) {
  return (TTL_BY_TYPE[type] || TTL_BY_TYPE.danger) * 1000; // en ms
}

function _notifyChange(event, id, entry) {
  for (const cb of changeListeners) {
    try { cb(event, id, entry); } catch { /* ignore */ }
  }
}

/**
 * Génère un ID déterministe pour un Danger Collectif à partir de coordonnées.
 * @param {number} lat @param {number} lon @returns {string}
 */
function _collectiveDangerId(lat, lon) {
  return `collective_${lat.toFixed(4)}_${lon.toFixed(4)}_${Date.now()}`;
}

// ── Algorithme Panic Collectif ─────────────────────────────────────────────

/**
 * Ajoute un événement panic à la file et vérifie si le seuil Panic Collectif
 * est atteint. Si oui, crée automatiquement un signalement "Danger Collectif"
 * centré sur le cluster.
 *
 * Algorithme :
 *   1. Purger les événements panic hors fenêtre temporelle (> 2 min).
 *   2. Ajouter le nouveau panic à la file.
 *   3. Pour chaque panic dans la file, compter les voisins dans le rayon.
 *   4. Si un cluster de >= 5 panics existe, créer un Danger Collectif centré
 *      sur le barycentre géographique du cluster.
 *   5. Éviter les doublons : ne pas créer de Danger Collectif si un autre
 *      existe déjà dans ce rayon.
 *
 * @param {number} lat
 * @param {number} lon
 * @param {string} reporterId
 * @returns {{triggered:boolean, cluster_size?:number, danger_id?:string}}
 */
function processPanic(lat, lon, reporterId) {
  const now = Date.now();
  const cutoff = now - PANIC_WINDOW_S * 1000;

  // 1. Purge
  while (panicQueue.length > 0 && panicQueue[0].ts < cutoff) panicQueue.shift();

  // 2. Ajout
  panicQueue.push({ lat, lon, reporter_id: reporterId, ts: now });

  // 3. Recherche de cluster
  let bestCluster = [];
  for (let i = 0; i < panicQueue.length; i++) {
    const cluster = panicQueue.filter(p => {
      return haversineM(panicQueue[i].lat, panicQueue[i].lon, p.lat, p.lon)
        <= PANIC_CLUSTER_RADIUS_M;
    });
    if (cluster.length > bestCluster.length) bestCluster = cluster;
  }

  // 4. Seuil atteint ?
  if (bestCluster.length < PANIC_THRESHOLD_COUNT) {
    return { triggered: false, pending_count: bestCluster.length };
  }

  // Barycentre du cluster
  const centLat = bestCluster.reduce((s, p) => s + p.lat, 0) / bestCluster.length;
  const centLon = bestCluster.reduce((s, p) => s + p.lon, 0) / bestCluster.length;

  // 5. Doublon ?
  const alreadyExists = [...reportStore.values()].some(r => {
    return r.is_collective &&
      haversineM(centLat, centLon, r.lat, r.lon) < PANIC_CLUSTER_RADIUS_M;
  });

  if (alreadyExists) {
    return { triggered: false, duplicate: true, cluster_size: bestCluster.length };
  }

  // Création du Danger Collectif
  const dangerId = _collectiveDangerId(centLat, centLon);
  const ttl = _ttlForType('danger_collectif');
  const entry = {
    id:          dangerId,
    type:        'danger_collectif',
    lat:         centLat,
    lon:         centLon,
    voters:      new Set(bestCluster.map(p => p.reporter_id)),
    createdAt:   now,
    expiresAt:   now + ttl,
    is_collective: true,
    description: `Danger Collectif généré automatiquement — ` +
                 `${bestCluster.length} signalements Panic en < 2 min`,
  };

  reportStore.set(dangerId, entry);
  _notifyChange('COLLECTIVE_DANGER', dangerId, entry);

  // Vider la file panic pour éviter les re-déclenchements immédiats
  panicQueue.length = 0;

  return {
    triggered:    true,
    danger_id:    dangerId,
    cluster_size: bestCluster.length,
    center:       { lat: centLat, lon: centLon },
  };
}

// ── API publique ──────────────────────────────────────────────────────────

/**
 * Enregistre ou enrichit un signalement.
 * Un même reporter_id ne peut voter qu'une seule fois par signalement.
 *
 * @param {object} payload
 * @param {string} payload.id
 * @param {string} payload.type
 * @param {number} payload.lat
 * @param {number} payload.lon
 * @param {string} payload.reporter_id
 * @param {string} [payload.description]
 * @returns {{
 *   ok: boolean,
 *   id: string,
 *   votes: number,
 *   distributed: boolean,
 *   panic_result?: object,
 *   error?: string
 * }}
 */
function addReport(payload) {
  const { id, type, lat, lon, reporter_id, description } = payload || {};

  if (!id || !type || lat == null || lon == null || !reporter_id) {
    return { ok: false, error: 'Champs obligatoires manquants (id, type, lat, lon, reporter_id)' };
  }

  const now = Date.now();
  let panicResult = null;

  // Traitement spécial pour les signalements de type "panic"
  if (type === 'panic') {
    panicResult = processPanic(lat, lon, reporter_id);
    // Un panic individuel n'est pas stocké dans le store principal
    // (il alimente uniquement la file panic).
    return {
      ok:            true,
      id,
      votes:         1,
      distributed:   false,
      panic_result:  panicResult,
      expires_in_s:  TTL_BY_TYPE.panic,
    };
  }

  // Traitement spécial pour la densité Bluetooth (HIVE)
  if (type === 'density') {
    const densityVal = parseInt(payload.value) || 0;
    const densityId = `density_${reporter_id}`; // Un seul report de densité par utilisateur
    const ttl = _ttlForType('density');
    const entry = {
      id: densityId,
      type: 'density',
      lat,
      lon,
      value: densityVal,
      voters: new Set([reporter_id]),
      createdAt: now,
      expiresAt: now + ttl,
      is_collective: false,
      description: `Densité locale : ${densityVal} appareils détectés`,
    };
    reportStore.set(densityId, entry);
    _notifyChange('DENSITY', densityId, entry);
    return {
      ok: true,
      id: densityId,
      votes: 1,
      distributed: true,
      expires_in_s: Math.round(ttl / 1000),
    };
  }

  // Signalement ordinaire
  if (reportStore.has(id)) {
    const entry = reportStore.get(id);
    // Vote supplémentaire (idempotent par reporter_id)
    if (!entry.voters.has(reporter_id)) {
      entry.voters.add(reporter_id);
      // Renouveler le TTL à chaque nouveau vote
      entry.expiresAt = now + _ttlForType(type);
    }
    const votes = entry.voters.size;
    const distributed = votes >= VOTES_REQUIRED_FOR_DISTRIBUTION;
    _notifyChange('VOTE', id, entry);
    return {
      ok:          true,
      id,
      votes,
      distributed,
      expires_in_s: Math.round((entry.expiresAt - now) / 1000),
    };
  }

  // Nouveau signalement
  const ttl = _ttlForType(type);
  const entry = {
    id,
    type,
    lat,
    lon,
    voters:       new Set([reporter_id]),
    createdAt:    now,
    expiresAt:    now + ttl,
    is_collective: false,
    description:  description || '',
  };
  reportStore.set(id, entry);
  _notifyChange('NEW', id, entry);

  return {
    ok:          true,
    id,
    votes:       1,
    distributed: false,  // 1/3, pas encore diffusé
    expires_in_s: Math.round(ttl / 1000),
  };
}

/**
 * Retourne la liste des signalements actifs et visibles (votes >= 3
 * ou is_collective === true), triés par nombre de votes décroissant.
 *
 * @returns {object}
 */
function getActiveReports() {
  const now = Date.now();
  const visible = [];

  for (const entry of reportStore.values()) {
    if (entry.expiresAt <= now) continue; // expiré (pas encore purgé)
    const votes = entry.voters.size;
    if (!entry.is_collective && votes < VOTES_REQUIRED_FOR_DISTRIBUTION) continue;

    visible.push({
      id:                  entry.id,
      type:                entry.type,
      lat:                 entry.lat,
      lon:                 entry.lon,
      value:               entry.value,
      votes,
      expires_at:          new Date(entry.expiresAt).toISOString(),
      ttl_remaining_s:     Math.round((entry.expiresAt - now) / 1000),
      is_collective_danger: entry.is_collective,
      description:         entry.description,
    });
  }

  visible.sort((a, b) => b.votes - a.votes);

  return {
    reports:     visible,
    generated_at: new Date().toISOString(),
    total_active: visible.length,
  };
}

/**
 * Retourne uniquement les coordonnées des zones à pondérer
 * (utilisées par events_manager pour le calcul de Safe Route).
 *
 * @returns {Array<{lat:number, lon:number, type:string, radius_m:number, weight:number}>}
 */
function getValidatedDangerZones() {
  const now = Date.now();
  const zones = [];

  for (const entry of reportStore.values()) {
    if (entry.expiresAt <= now) continue;
    const votes = entry.voters.size;

    // Filtre de visibilité
    if (entry.type === 'density') {
        // La densité est toujours utile
    } else if (!entry.is_collective && votes < VOTES_REQUIRED_FOR_DISTRIBUTION) {
        continue;
    }

    // Rayon d'influence et poids (weighting)
    let radius = 80;
    let weight = 10.0; // Poids par défaut (alourdissement massif)

    if (entry.type === 'barrage') { radius = 150; weight = 50.0; }
    if (entry.type === 'casseurs') { radius = 120; weight = 100.0; }
    if (entry.type === 'danger_collectif') { radius = 200; weight = 200.0; }

    if (entry.type === 'density') {
        radius = 50; // Le scan Bluetooth a une portée limitée
        // Le poids dépend de la densité (ex: 1.0 + density/5)
        weight = 1.0 + (entry.value || 0) / 5.0;
    }

    zones.push({
        lat: entry.lat,
        lon: entry.lon,
        type: entry.type,
        radius_m: radius,
        weight: weight
    });
  }
  return zones;
}

/**
 * Retourne le nombre de panics en attente (sous le seuil).
 * @returns {number}
 */
function getPendingPanicCount() {
  const cutoff = Date.now() - PANIC_WINDOW_S * 1000;
  return panicQueue.filter(p => p.ts >= cutoff).length;
}

/**
 * Retourne un instantané complet du store (pour debug).
 * @returns {object}
 */
function getDebugSnapshot() {
  const now = Date.now();
  const all = [];
  for (const entry of reportStore.values()) {
    all.push({
      id:              entry.id,
      type:            entry.type,
      lat:             entry.lat,
      lon:             entry.lon,
      votes:           entry.voters.size,
      created_at:      new Date(entry.createdAt).toISOString(),
      expires_at:      new Date(entry.expiresAt).toISOString(),
      ttl_remaining_s: Math.round((entry.expiresAt - now) / 1000),
      is_collective:   entry.is_collective,
    });
  }
  return {
    total:         reportStore.size,
    panic_queue:   panicQueue.length,
    reports:       all,
    panic_entries: panicQueue.map(p => ({
      lat:        p.lat,
      lon:        p.lon,
      ts:         new Date(p.ts).toISOString(),
      age_s:      Math.round((now - p.ts) / 1000),
    })),
  };
}

/**
 * Supprime un signalement par son ID (admin/debug).
 * @param {string} id
 * @returns {boolean}
 */
function deleteReport(id) {
  return reportStore.delete(id);
}

/**
 * Enregistre un callback appelé à chaque mutation du store.
 * Le callback reçoit (event: string, id: string, entry: object).
 * @param {Function} cb
 */
function onStoreChange(cb) {
  changeListeners.push(cb);
}

module.exports = {
  addReport,
  getActiveReports,
  getValidatedDangerZones,
  getPendingPanicCount,
  getDebugSnapshot,
  deleteReport,
  onStoreChange,
  getVersionInfo,
  setVersionInfo,
  // Constantes exposées pour documentation et tests
  TTL_BY_TYPE,
  VOTES_REQUIRED_FOR_DISTRIBUTION,
  PANIC_THRESHOLD_COUNT,
  PANIC_WINDOW_S,
  PANIC_CLUSTER_RADIUS_M,
};
