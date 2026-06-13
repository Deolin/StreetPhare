// test_servers/modules/events_manager.js
//
// Module : Gestionnaire d'Événements & Itinéraires — StreetPhare
// ==============================================================
// Responsabilités :
//   1. Héberger et distribuer les données JSON des événements de
//      Fleurus (6220) avec leurs QR Codes / métadonnées.
//   2. Fournir une API de calcul d'itinéraire "Safe Route" :
//      un itinéraire principal + trois alternatives piétons,
//      en soustrayant dynamiquement les zones dangereuses validées.
//
// Intégration d'itinéraire :
//   - Mode LOCAL  : graphe statique simplifié des rues piétonnes de
//     Fleurus (coordonnées réelles, OSM-like), calculé en interne par
//     un algorithme A* adapté.
//   - Mode REMOTE : appel à l'API GraphHopper public (profil piéton)
//     si GRAPHHOPPER_API_KEY est défini dans les variables d'environ-
//     nement, avec fallback automatique sur le mode LOCAL.
//
// Format de retour pour le client Flutter :
//   {
//     event_id : string,
//     routes   : [
//       { id: 'main'|'alt1'|'alt2'|'alt3',
//         label : string,
//         distance_m : number,
//         duration_s : number,
//         safe_score : number,   // 0.0–1.0 (1 = totalement sûr)
//         polyline  : [[lat,lon], …],
//         warnings  : [{ lat, lon, type, severity }]
//       }
//     ]
//   }
//
'use strict';

const https = require('https');

// ── Catalogue des événements de Fleurus 6220 ──────────────────────────────
// Chaque événement possède :
//   id           : identifiant stable
//   name         : nom lisible
//   description  : résumé
//   date         : date de l'édition courante (ISO 8601)
//   start_coords : point de départ par défaut [lat, lon]
//   end_coords   : point d'arrivée  par défaut [lat, lon]
//   waypoints    : étapes intermédiaires (tableau [[lat,lon]])
//   qr_payload   : contenu du QR Code distribué sur le terrain
//   status       : 'active' | 'upcoming' | 'past'
const EVENTS_CATALOG = [
  {
    id: 'fleurus-tour',
    name: 'Le Tour de Fleurus',
    description:
      'Parcours pédestre autour du centre historique de Fleurus, '  +
      'guidé par les bénévoles StreetPhare.',
    date: '2026-07-14T10:00:00+02:00',
    start_coords: [50.4891, 4.5452],   // Place Albert Ier — Fleurus centre
    end_coords:   [50.4891, 4.5452],   // retour au départ (boucle)
    waypoints: [
      [50.4905, 4.5420],  // Rue de Namur
      [50.4875, 4.5480],  // Parc du Château
      [50.4860, 4.5440],  // Place communale
    ],
    qr_payload: JSON.stringify({
      event: 'fleurus-tour',
      server: 'http://localhost:3000',
      endpoint: '/v1/events/fleurus-tour',
      signed_at: '2026-06-01T00:00:00Z',
    }),
    status: 'upcoming',
    color_hex: '#1565C0',
    icon: 'directions_walk',
  },
  {
    id: 'traversee-ecoles',
    name: 'La Traversée des Écoles',
    description:
      'Itinéraire sécurisé reliant les principales écoles de Fleurus '  +
      'pour les familles et les enfants lors des grands rassemblements publics.',
    date: '2026-07-14T08:30:00+02:00',
    start_coords: [50.4930, 4.5500],   // École primaire Saint-Pierre
    end_coords:   [50.4855, 4.5370],   // Athénée Royal de Fleurus
    waypoints: [
      [50.4920, 4.5465],
      [50.4900, 4.5430],
      [50.4878, 4.5390],
    ],
    qr_payload: JSON.stringify({
      event: 'traversee-ecoles',
      server: 'http://localhost:3000',
      endpoint: '/v1/events/traversee-ecoles',
      signed_at: '2026-06-01T00:00:00Z',
    }),
    status: 'upcoming',
    color_hex: '#2E7D32',
    icon: 'school',
  },
  {
    id: 'cortege-police',
    name: 'Le Cortège de la Police Montée-Démonté',
    description:
      'Défilé officiel de la police montée de Fleurus. '  +
      'L\'application signale en temps réel les zones de circulation '  +
      'restreinte et propose des itinéraires de contournement.',
    date: '2026-07-14T14:00:00+02:00',
    start_coords: [50.4895, 4.5460],   // Caserne de police de Fleurus
    end_coords:   [50.4891, 4.5452],   // Place Albert Ier
    waypoints: [
      [50.4888, 4.5472],
      [50.4880, 4.5458],
      [50.4885, 4.5445],
    ],
    qr_payload: JSON.stringify({
      event: 'cortege-police',
      server: 'http://localhost:3000',
      endpoint: '/v1/events/cortege-police',
      signed_at: '2026-06-01T00:00:00Z',
    }),
    status: 'upcoming',
    color_hex: '#B71C1C',
    icon: 'local_police',
  },
];

// ── Graphe simplifié de rues piétonnes de Fleurus ──────────────────────────
// Nœuds : [id, lat, lon, label]
// Arêtes : [fromId, toId, distance_m, pedestrian_only]
// Source : extrait OpenStreetMap (Fleurus 6220, Belgique)
const PEDESTRIAN_GRAPH = {
  nodes: {
    n1:  { lat: 50.4891, lon: 4.5452, label: 'Place Albert Ier' },
    n2:  { lat: 50.4905, lon: 4.5420, label: 'Rue de Namur' },
    n3:  { lat: 50.4875, lon: 4.5480, label: 'Parc du Château' },
    n4:  { lat: 50.4860, lon: 4.5440, label: 'Place communale' },
    n5:  { lat: 50.4930, lon: 4.5500, label: 'École Saint-Pierre' },
    n6:  { lat: 50.4855, lon: 4.5370, label: 'Athénée Royal' },
    n7:  { lat: 50.4895, lon: 4.5460, label: 'Caserne de Police' },
    n8:  { lat: 50.4920, lon: 4.5465, label: 'Rue des Étudiants' },
    n9:  { lat: 50.4900, lon: 4.5430, label: 'Rue Centrale' },
    n10: { lat: 50.4878, lon: 4.5390, label: 'Avenue de la Libération' },
    n11: { lat: 50.4915, lon: 4.5445, label: 'Rue du Moulin' },
    n12: { lat: 50.4870, lon: 4.5460, label: 'Rue des Templiers' },
    n13: { lat: 50.4840, lon: 4.5420, label: 'Quartier de la Ferme' },
    n14: { lat: 50.4850, lon: 4.5500, label: 'Rue du Calvaire' },
    n15: { lat: 50.4935, lon: 4.5475, label: 'Parking des Fêtes' },
  },
  edges: [
    // Connexions principales
    { from: 'n1',  to: 'n2',  dist: 280,  pedestrian: false },
    { from: 'n1',  to: 'n3',  dist: 350,  pedestrian: false },
    { from: 'n1',  to: 'n4',  dist: 400,  pedestrian: true  },
    { from: 'n1',  to: 'n7',  dist: 120,  pedestrian: false },
    { from: 'n1',  to: 'n9',  dist: 160,  pedestrian: false },
    { from: 'n2',  to: 'n11', dist: 200,  pedestrian: true  },
    { from: 'n2',  to: 'n9',  dist: 180,  pedestrian: false },
    { from: 'n3',  to: 'n4',  dist: 260,  pedestrian: true  },
    { from: 'n3',  to: 'n12', dist: 210,  pedestrian: true  },
    { from: 'n4',  to: 'n6',  dist: 490,  pedestrian: false },
    { from: 'n4',  to: 'n10', dist: 300,  pedestrian: false },
    { from: 'n5',  to: 'n8',  dist: 140,  pedestrian: true  },
    { from: 'n5',  to: 'n15', dist: 250,  pedestrian: false },
    { from: 'n6',  to: 'n10', dist: 180,  pedestrian: false },
    { from: 'n6',  to: 'n13', dist: 220,  pedestrian: true  },
    { from: 'n7',  to: 'n8',  dist: 310,  pedestrian: false },
    { from: 'n8',  to: 'n9',  dist: 190,  pedestrian: true  },
    { from: 'n8',  to: 'n15', dist: 240,  pedestrian: false },
    { from: 'n9',  to: 'n11', dist: 220,  pedestrian: true  },
    { from: 'n10', to: 'n13', dist: 270,  pedestrian: false },
    { from: 'n11', to: 'n15', dist: 310,  pedestrian: true  },
    { from: 'n12', to: 'n4',  dist: 300,  pedestrian: true  },
    { from: 'n12', to: 'n14', dist: 240,  pedestrian: true  },
    { from: 'n13', to: 'n14', dist: 290,  pedestrian: true  },
    { from: 'n14', to: 'n3',  dist: 330,  pedestrian: true  },
    // Alt routes pour diversité
    { from: 'n2',  to: 'n5',  dist: 500,  pedestrian: false },
    { from: 'n7',  to: 'n1',  dist: 120,  pedestrian: false },
    { from: 'n9',  to: 'n4',  dist: 350,  pedestrian: true  },
  ],
};

// ── Utilitaires géographiques ─────────────────────────────────────────────

/**
 * Distance haversine entre deux points (retourne en mètres).
 * @param {number} lat1 @param {number} lon1
 * @param {number} lat2 @param {number} lon2
 * @returns {number}
 */
function haversineM(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Nœud le plus proche des coordonnées données.
 * @param {number} lat @param {number} lon
 * @returns {string} nodeId
 */
function nearestNode(lat, lon) {
  let bestId = null;
  let bestDist = Infinity;
  for (const [id, n] of Object.entries(PEDESTRIAN_GRAPH.nodes)) {
    const d = haversineM(lat, lon, n.lat, n.lon);
    if (d < bestDist) { bestDist = d; bestId = id; }
  }
  return bestId;
}

/**
 * Construit la liste d'adjacence bidirectionnelle du graphe.
 * Applique une pondération dynamique basée sur les zones de danger.
 *
 * @param {Array<{lat,lon,radius_m?,weight?}>} dangerZones - zones à pondérer
 * @returns {Map<string, Array<{to, dist, realDist}>>}
 */
function buildAdjacency(dangerZones = []) {
  const adj = new Map();
  for (const id of Object.keys(PEDESTRIAN_GRAPH.nodes)) adj.set(id, []);

  for (const edge of PEDESTRIAN_GRAPH.edges) {
    const nFrom = PEDESTRIAN_GRAPH.nodes[edge.from];
    const nTo   = PEDESTRIAN_GRAPH.nodes[edge.to];

    // Calcul de la pondération au milieu du segment
    const midLat = (nFrom.lat + nTo.lat) / 2;
    const midLon = (nFrom.lon + nTo.lon) / 2;

    let totalWeight = 1.0;
    for (const z of dangerZones) {
      const r = z.radius_m || 80;
      const d = haversineM(midLat, midLon, z.lat, z.lon);
      if (d < r) {
        // Alourdissement massif du coût de traversée (ex: danger = poids +10)
        totalWeight += (z.weight || 10.0);
      }
    }

    const weightedDist = edge.dist * totalWeight;

    adj.get(edge.from).push({ to: edge.to,   dist: weightedDist, realDist: edge.dist });
    adj.get(edge.to).push(  { to: edge.from, dist: weightedDist, realDist: edge.dist });
  }
  return adj;
}

/**
 * Algorithme A* sur le graphe piéton.
 * Retourne le chemin {nodes, totalDist} ou null si impossible.
 *
 * @param {string} startId
 * @param {string} goalId
 * @param {Map}    adj - liste d'adjacence
 */
function aStar(startId, goalId, adj) {
  const goalNode = PEDESTRIAN_GRAPH.nodes[goalId];
  const h = (id) => {
    const n = PEDESTRIAN_GRAPH.nodes[id];
    return haversineM(n.lat, n.lon, goalNode.lat, goalNode.lon);
  };

  // open set : [{f, g, id, path}], trié par f croissant
  const openSet = [{ f: h(startId), g: 0, id: startId, path: [startId] }];
  const visited = new Map(); // id -> minG

  while (openSet.length > 0) {
    openSet.sort((a, b) => a.f - b.f);
    const { g, id, path } = openSet.shift();

    if (visited.has(id) && visited.get(id) <= g) continue;
    visited.set(id, g);

    if (id === goalId) return { nodes: path, totalDist: g };

    for (const edge of adj.get(id) || []) {
      const newG = g + edge.dist;
      if (visited.has(edge.to) && visited.get(edge.to) <= newG) continue;

      openSet.push({
        f: newG + h(edge.to),
        g: newG,
        id: edge.to,
        path: [...path, edge.to],
      });
    }
  }
  return null; // aucun chemin trouvé
}

/**
 * Convertit une liste de nodeIds en polyline [[lat,lon]].
 */
function nodesToPolyline(nodeIds) {
  return nodeIds.map(id => {
    const n = PEDESTRIAN_GRAPH.nodes[id];
    return [n.lat, n.lon];
  });
}

/**
 * Calcule le score de sécurité d'un chemin (0.0 = dangereux, 1.0 = sûr).
 * Basé sur la densité de segments bloqués traversés et le nombre de
 * zones de danger proches.
 *
 * @param {string[]} nodeIds
 * @param {Array}    dangerZones
 * @returns {number}
 */
function computeSafeScore(nodeIds, dangerZones) {
  if (dangerZones.length === 0) return 1.0;
  let totalPenalty = 0;
  for (let i = 0; i < nodeIds.length; i++) {
    const n = PEDESTRIAN_GRAPH.nodes[nodeIds[i]];
    for (const z of dangerZones) {
      const r = z.radius_m || 80;
      const d = haversineM(n.lat, n.lon, z.lat, z.lon);
      if (d < r * 2) {
        // Pénalité inversement proportionnelle à la distance
        totalPenalty += Math.max(0, 1 - d / (r * 2));
      }
    }
  }
  const raw = 1 - totalPenalty / (nodeIds.length * Math.max(1, dangerZones.length));
  return Math.max(0, Math.min(1, raw));
}

/**
 * Collecte les warnings (passages proches de dangers) sur un chemin.
 */
function collectWarnings(nodeIds, dangerZones) {
  const warnings = [];
  for (let i = 0; i < nodeIds.length; i++) {
    const n = PEDESTRIAN_GRAPH.nodes[nodeIds[i]];
    for (const z of dangerZones) {
      const r = z.radius_m || 80;
      const d = haversineM(n.lat, n.lon, z.lat, z.lon);
      if (d < r * 1.5) {
        warnings.push({
          lat: n.lat,
          lon: n.lon,
          type: z.type || 'danger',
          severity: d < r ? 'high' : 'medium',
          distance_m: Math.round(d),
        });
      }
    }
  }
  return warnings;
}

// ── Calcul d'itinéraire via GraphHopper API (optionnel) ───────────────────

/**
 * Appel à l'API GraphHopper pour un calcul d'itinéraire piéton.
 * Retourne la polyline décodée [[lat, lon]] ou null en cas d'erreur.
 *
 * @param {number} fromLat @param {number} fromLon
 * @param {number} toLat   @param {number} toLon
 * @param {string} apiKey
 * @returns {Promise<{polyline:Array, distanceM:number, durationS:number}|null>}
 */
function fetchGraphhopperRoute(fromLat, fromLon, toLat, toLon, apiKey) {
  return new Promise((resolve) => {
    const url =
      `https://graphhopper.com/api/1/route?` +
      `point=${fromLat},${fromLon}&point=${toLat},${toLon}` +
      `&vehicle=foot&locale=fr&key=${apiKey}&type=json&points_encoded=false`;

    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => (data += chunk));
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (!json.paths || !json.paths[0]) { resolve(null); return; }
          const path = json.paths[0];
          const coords = path.points.coordinates.map(c => [c[1], c[0]]);
          resolve({
            polyline: coords,
            distanceM: Math.round(path.distance),
            durationS: Math.round(path.time / 1000),
          });
        } catch { resolve(null); }
      });
    }).on('error', () => resolve(null));
  });
}

// ── API publique du module ────────────────────────────────────────────────

/**
 * Retourne la liste complète des événements du catalogue.
 * @returns {Array}
 */
function getAllEvents() {
  return EVENTS_CATALOG.map(e => ({
    id:          e.id,
    name:        e.name,
    description: e.description,
    date:        e.date,
    status:      e.status,
    color_hex:   e.color_hex,
    icon:        e.icon,
    start_coords: e.start_coords,
    end_coords:   e.end_coords,
  }));
}

/**
 * Retourne les détails complets (dont QR payload) d'un événement.
 * @param {string} eventId
 * @returns {object|null}
 */
function getEventById(eventId) {
  return EVENTS_CATALOG.find(e => e.id === eventId) || null;
}

/**
 * Calcule les itinéraires "Safe Route" pour un événement donné.
 * Retourne un principal + 3 alternatives en tenant compte des zones
 * dangereuses validées passées en paramètre.
 *
 * @param {string} eventId
 * @param {Array<{lat,lon,radius_m?,type?}>} dangerZones - zones actives
 * @param {{lat?:number, lon?:number}} [fromOverride] - point de départ custom
 * @returns {Promise<object>}
 */
async function computeSafeRoutes(eventId, dangerZones = [], fromOverride = null) {
  const event = getEventById(eventId);
  if (!event) return { error: 'Événement introuvable', event_id: eventId };

  const startCoords = fromOverride
    ? [fromOverride.lat, fromOverride.lon]
    : event.start_coords;
  const endCoords = event.end_coords;

  const apiKey = process.env.GRAPHHOPPER_API_KEY || null;

  // ── Mode REMOTE : tentative GraphHopper ───────────────────────────────
  if (apiKey) {
    const ghRoute = await fetchGraphhopperRoute(
      startCoords[0], startCoords[1],
      endCoords[0],   endCoords[1],
      apiKey,
    );
    if (ghRoute) {
      // Avec GraphHopper on génère l'itinéraire principal et on crée
      // 3 variantes simplifiées (légèrement décalées) pour le client.
      const safeScore = computeSafeScoreFromPolyline(ghRoute.polyline, dangerZones);
      const routes = [
        buildRouteResult('main',  'Itinéraire principal (GraphHopper)',
          ghRoute.polyline, ghRoute.distanceM, ghRoute.durationS, safeScore,
          collectWarningsFromPolyline(ghRoute.polyline, dangerZones)),
        ...generateAltRoutes(startCoords, endCoords, dangerZones, event.waypoints),
      ];
      return { event_id: eventId, source: 'graphhopper', routes };
    }
    console.warn('[events_manager] GraphHopper indisponible, fallback LOCAL');
  }

  // ── Mode LOCAL : graphe statique + A* ─────────────────────────────────
  const adj         = buildAdjacency(dangerZones);
  const adjUnsafe   = buildAdjacency([]);           // sans contraintes

  const startId = nearestNode(startCoords[0], startCoords[1]);
  const goalId  = nearestNode(endCoords[0],   endCoords[1]);

  // Itinéraire principal (alourdi par les dangers)
  const mainPath = aStar(startId, goalId, adj);

  if (!mainPath) {
    return { event_id: eventId, error: 'Aucun itinéraire calculable', routes: [] };
  }

  const routes = [];

  // Recalcul de la distance réelle (non pondérée) pour l'affichage
  const realDist = mainPath.nodes.reduce((acc, nodeId, idx) => {
    if (idx === 0) return 0;
    const prevId = mainPath.nodes[idx-1];
    const edge = PEDESTRIAN_GRAPH.edges.find(e => (e.from === prevId && e.to === nodeId) || (e.from === nodeId && e.to === prevId));
    return acc + (edge ? edge.dist : 0);
  }, 0);

  routes.push(buildRouteResult(
    'main',
    'Itinéraire Safe (recommandé)',
    nodesToPolyline(mainPath.nodes),
    realDist,
    Math.round(realDist / 1.2),   // ~1.2 m/s marche lente
    computeSafeScore(mainPath.nodes, dangerZones),
    collectWarnings(mainPath.nodes, dangerZones),
  ));

  // Alternatives : on pénalise différemment les nœuds pour obtenir
  // des variantes (heuristique légère : on retire un nœud intermédiaire
  // du chemin principal à chaque itération).
  const altLabels = [
    'Alternative Nord',
    'Alternative Sud',
    'Alternative Rapide',
  ];

  for (let i = 0; i < 3; i++) {
    // Crée une version du graphe avec un sous-ensemble de nœuds exclus
    const skipNode = mainPath.nodes[Math.floor(mainPath.nodes.length * (i + 1) / 4)];
    const adjAlt = buildAdjacencyExcluding(dangerZones, skipNode ? [skipNode] : []);
    const altPath = aStar(startId, goalId, adjAlt);

    if (altPath && altPath.nodes.join(',') !== mainPath.nodes.join(',')) {
      const altRealDist = altPath.nodes.reduce((acc, nodeId, idx) => {
        if (idx === 0) return 0;
        const prevId = altPath.nodes[idx-1];
        const edge = PEDESTRIAN_GRAPH.edges.find(e => (e.from === prevId && e.to === nodeId) || (e.from === nodeId && e.to === prevId));
        return acc + (edge ? edge.dist : 0);
      }, 0);

      routes.push(buildRouteResult(
        `alt${i + 1}`,
        altLabels[i],
        nodesToPolyline(altPath.nodes),
        altRealDist,
        Math.round(altRealDist / 1.2),
        computeSafeScore(altPath.nodes, dangerZones),
        collectWarnings(altPath.nodes, dangerZones),
      ));
    }
  }

  // S'assurer d'avoir au moins 4 entrées (dupliquer si besoin)
  while (routes.length < 4) {
    const base = routes[routes.length - 1];
    routes.push({
      ...base,
      id: `alt${routes.length}`,
      label: altLabels[routes.length - 1] || `Alternative ${routes.length}`,
    });
  }

  return { event_id: eventId, source: 'local_graph', routes };
}

// ── Helpers internes ──────────────────────────────────────────────────────

function buildRouteResult(id, label, polyline, distM, durS, safeScore, warnings) {
  return {
    id,
    label,
    distance_m: distM,
    duration_s: durS,
    safe_score: Math.round(safeScore * 100) / 100,
    polyline,
    warnings: warnings || [],
  };
}

/**
 * Construit l'adjacence en excluant certains nœuds (pour les alternatives).
 */
function buildAdjacencyExcluding(dangerZones, excludedNodes = []) {
  const excSet = new Set(excludedNodes);
  const adj = new Map();
  for (const id of Object.keys(PEDESTRIAN_GRAPH.nodes)) {
    if (!excSet.has(id)) adj.set(id, []);
  }
  for (const edge of PEDESTRIAN_GRAPH.edges) {
    if (excSet.has(edge.from) || excSet.has(edge.to)) continue;
    const nFrom = PEDESTRIAN_GRAPH.nodes[edge.from];
    const nTo   = PEDESTRIAN_GRAPH.nodes[edge.to];
    const midLat = (nFrom.lat + nTo.lat) / 2;
    const midLon = (nFrom.lon + nTo.lon) / 2;

    let totalWeight = 1.0;
    for (const z of dangerZones) {
      const r = z.radius_m || 80;
      const d = haversineM(midLat, midLon, z.lat, z.lon);
      if (d < r) {
        totalWeight += (z.weight || 10.0);
      }
    }
    const weightedDist = edge.dist * totalWeight;

    adj.get(edge.from) && adj.get(edge.from).push({ to: edge.to,   dist: weightedDist, realDist: edge.dist });
    adj.get(edge.to)   && adj.get(edge.to).push(  { to: edge.from, dist: weightedDist, realDist: edge.dist });
  }
  return adj;
}

/**
 * Génère 3 routes alternatives à partir des waypoints de l'événement.
 * Utilisé en mode GraphHopper uniquement pour compléter les alternatives.
 */
function generateAltRoutes(startCoords, endCoords, dangerZones, waypoints) {
  // Fallback local pour les alternatives quand GraphHopper est utilisé
  const adj  = buildAdjacency(dangerZones);
  const adj0 = buildAdjacency([]);
  const alts = [];
  const labels = ['Alternative Nord', 'Alternative Sud', 'Alternative Rapide'];

  const intermediates = waypoints && waypoints.length > 0 ? waypoints : [];

  for (let i = 0; i < 3; i++) {
    const mid = intermediates[i] || endCoords;
    const midId  = nearestNode(mid[0], mid[1]);
    const startId = nearestNode(startCoords[0], startCoords[1]);
    const goalId  = nearestNode(endCoords[0],   endCoords[1]);

    const leg1 = aStar(startId, midId, adj);
    const leg2 = aStar(midId,   goalId, adj);

    if (leg1 && leg2) {
      const nodes = [...leg1.nodes, ...leg2.nodes.slice(1)];
      const dist  = leg1.totalDist + leg2.totalDist; // Note: this is weighted dist

      const realDist = nodes.reduce((acc, nodeId, idx) => {
        if (idx === 0) return 0;
        const prevId = nodes[idx-1];
        const edge = PEDESTRIAN_GRAPH.edges.find(e => (e.from === prevId && e.to === nodeId) || (e.from === nodeId && e.to === prevId));
        return acc + (edge ? edge.dist : 0);
      }, 0);

      alts.push(buildRouteResult(
        `alt${i + 1}`, labels[i],
        nodesToPolyline(nodes),
        realDist,
        Math.round(realDist / 1.2),
        computeSafeScore(nodes, dangerZones),
        collectWarnings(nodes, dangerZones),
      ));
    }
  }
  return alts;
}

/** Version polyline (tableau de [lat,lon]) pour le calcul de score GraphHopper. */
function computeSafeScoreFromPolyline(polyline, dangerZones) {
  if (!dangerZones.length) return 1.0;
  let pen = 0;
  for (const [lat, lon] of polyline) {
    for (const z of dangerZones) {
      const r = z.radius_m || 80;
      const d = haversineM(lat, lon, z.lat, z.lon);
      if (d < r * 2) pen += Math.max(0, 1 - d / (r * 2));
    }
  }
  const raw = 1 - pen / (polyline.length * Math.max(1, dangerZones.length));
  return Math.max(0, Math.min(1, raw));
}

function collectWarningsFromPolyline(polyline, dangerZones) {
  const w = [];
  for (const [lat, lon] of polyline) {
    for (const z of dangerZones) {
      const r = z.radius_m || 80;
      const d = haversineM(lat, lon, z.lat, z.lon);
      if (d < r * 1.5) {
        w.push({ lat, lon, type: z.type || 'danger',
          severity: d < r ? 'high' : 'medium', distance_m: Math.round(d) });
      }
    }
  }
  return w;
}

module.exports = {
  getAllEvents,
  getEventById,
  computeSafeRoutes,
  haversineM,
};
