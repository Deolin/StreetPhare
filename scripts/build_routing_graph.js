#!/usr/bin/env node
// scripts/build_routing_graph.js
//
// Construit un graphe de routage piéton compact (JSON) à partir du fichier
// OSM XML généré par fetch_fleurus_osm.js. Le serveur Node.js charge ce JSON
// pour calculer des itinéraires SANS dépendance native (Dijkstra en mémoire).
//
// Usage : node scripts/build_routing_graph.js [osmFile] [outFile]

const fs = require('fs');
const readline = require('readline');
const path = require('path');

const OSM_FILE = process.argv[2] || 'android/app/src/main/assets/osm/fleurus.osm';
const OUT_FILE = process.argv[3] || 'server/data/fleurus.graph.json';
const CAR_OUT_FILE = OUT_FILE.replace(/\.graph\.json$/, '.car.graph.json');

// Types de route non praticables à pied.
const NON_WALKABLE = new Set([
  'motorway', 'motorway_link', 'trunk', 'trunk_link',
  'raceway', 'construction', 'proposed',
]);

// Pondération (multiplicateur de distance) : on préfère les chemins piétons
// aux routes majeures. Valeur par défaut : 1.5 (route inconnue).
const HIGHWAY_WEIGHT = {
  footway: 1.0, pedestrian: 1.0, path: 1.0, steps: 1.1,
  corridor: 1.0, living_street: 1.0, residential: 1.1,
  service: 1.2, track: 1.2, unclassified: 1.2,
  tertiary: 1.4, secondary: 1.6, primary: 1.8,
};

// Types de route carrossables (accessibles en voiture).
// Exclut volontairement : footway, pedestrian, path, steps, cycleway,
// corridor, bridleway, track (non revêtu), raceway.
const CAR_ACCESSIBLE = new Set([
  'motorway', 'motorway_link', 'trunk', 'trunk_link',
  'primary', 'primary_link', 'secondary', 'secondary_link',
  'tertiary', 'tertiary_link', 'unclassified', 'residential',
  'living_street', 'service',
]);

// Valeurs OSM indiquant un sens unique.
const ONEWAY_FORWARD = new Set(['yes', 'true', '1']);
const ONEWAY_BACKWARD = new Set(['-1', 'reverse']);

function toRad(d) {
  return (d * Math.PI) / 180;
}

function haversine(aLat, aLon, bLat, bLon) {
  const R = 6371000;
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

async function main() {
  const nodes = []; // [[lat, lon], ...] — indexé par position
  const idToIndex = new Map();
  const footAdjMap = new Map(); // index -> Map(neighbor -> minDist) [piéton]
  const carAdjMap = new Map();  // index -> Map(neighbor -> minDist) [voiture]

  let currentWay = null; // { refs: [], highway: null, oneway: null, junction: null }
  let footWayCount = 0, carWayCount = 0;
  let footEdgeCount = 0, carEdgeCount = 0;

  const addFootEdge = (a, b, dist) => {
    if (a === b) return;
    if (!footAdjMap.has(a)) footAdjMap.set(a, new Map());
    if (!footAdjMap.has(b)) footAdjMap.set(b, new Map());
    const am = footAdjMap.get(a);
    const bm = footAdjMap.get(b);
    if (dist < (am.get(b) ?? Infinity)) {
      am.set(b, dist);
      bm.set(a, dist);
      footEdgeCount++;
    }
  };

  // Arête ORIENTÉE (sens unique) pour le graphe voiture.
  const addCarEdge = (a, b, dist) => {
    if (a === b) return;
    if (!carAdjMap.has(a)) carAdjMap.set(a, new Map());
    const am = carAdjMap.get(a);
    if (dist < (am.get(b) ?? Infinity)) {
      am.set(b, dist);
      carEdgeCount++;
    }
  };

  const rl = readline.createInterface({
    input: fs.createReadStream(OSM_FILE),
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    const t = line.trim();
    if (t.startsWith('<node ')) {
      const m = t.match(/id="(\d+)"\s+lat="([-\d.]+)"\s+lon="([-\d.]+)"/);
      // Ignore les doublons de nœud (la sortie Overpass peut ré-émettre un
      // nœud déjà présent) pour ne garder qu'un seul index par ID.
      if (m && !idToIndex.has(m[1])) {
        idToIndex.set(m[1], nodes.length);
        nodes.push([parseFloat(m[2]), parseFloat(m[3])]);
      }
    } else if (t.startsWith('<way ')) {
      currentWay = { refs: [], highway: null, oneway: null, junction: null };
    } else if (t.startsWith('<nd ')) {
      const m = t.match(/ref="(\d+)"/);
      if (m && currentWay) currentWay.refs.push(m[1]);
    } else if (t.startsWith('<tag ')) {
      const m = t.match(/k="([^"]+)"\s+v="([^"]*)"/);
      if (m && currentWay) {
        if (m[1] === 'highway') currentWay.highway = m[2];
        else if (m[1] === 'oneway') currentWay.oneway = m[2];
        else if (m[1] === 'junction') currentWay.junction = m[2];
      }
    } else if (t.startsWith('</way>')) {
      if (currentWay && currentWay.highway) {
        const refs = currentWay.refs;

        // ── Graphe piéton ────────────────────────────────────────────
        if (!NON_WALKABLE.has(currentWay.highway)) {
          footWayCount++;
          const mult = HIGHWAY_WEIGHT[currentWay.highway] || 1.5;
          for (let i = 0; i + 1 < refs.length; i++) {
            const a = idToIndex.get(refs[i]);
            const b = idToIndex.get(refs[i + 1]);
            if (a === undefined || b === undefined) continue;
            const dist = haversine(nodes[a][0], nodes[a][1], nodes[b][0], nodes[b][1]);
            addFootEdge(a, b, Math.round(dist * mult));
          }
        }

        // ── Graphe voiture (routes carrossables + sens uniques) ─────
        if (CAR_ACCESSIBLE.has(currentWay.highway)) {
          carWayCount++;
          const isOnewayForward =
              ONEWAY_FORWARD.has(currentWay.oneway) ||
              currentWay.junction === 'roundabout' ||
              currentWay.junction === 'circular';
          const isOnewayBackward = ONEWAY_BACKWARD.has(currentWay.oneway);
          for (let i = 0; i + 1 < refs.length; i++) {
            const a = idToIndex.get(refs[i]);
            const b = idToIndex.get(refs[i + 1]);
            if (a === undefined || b === undefined) continue;
            const dist = Math.round(haversine(nodes[a][0], nodes[a][1], nodes[b][0], nodes[b][1]));
            if (!isOnewayBackward) addCarEdge(a, b, dist); // sens de numérisation
            if (!isOnewayForward) addCarEdge(b, a, dist);  // sens inverse
          }
        }
      }
      currentWay = null;
    }
  }

  // Sérialisation compacte : adj[i] = [[voisin, distance], ...]
  const serialize = (adjMap) => nodes.map((_, i) => {
    const m = adjMap.get(i);
    if (!m) return [];
    return Array.from(m.entries()).map(([to, dist]) => [to, dist]);
  });

  const nowIso = new Date().toISOString();
  const footGraph = {
    meta: {
      generatedAt: nowIso,
      source: path.basename(OSM_FILE),
      profile: 'foot',
      nodes: nodes.length,
      ways: footWayCount,
      edges: footEdgeCount,
    },
    nodes,
    adj: serialize(footAdjMap),
  };
  const carGraph = {
    meta: {
      generatedAt: nowIso,
      source: path.basename(OSM_FILE),
      profile: 'car',
      nodes: nodes.length,
      ways: carWayCount,
      edges: carEdgeCount,
    },
    nodes,
    adj: serialize(carAdjMap),
  };

  fs.mkdirSync(path.dirname(OUT_FILE), { recursive: true });
  fs.writeFileSync(OUT_FILE, JSON.stringify(footGraph));
  console.log(`[GRAPH] ✅ ${OUT_FILE} (piéton)`);
  console.log(`[GRAPH] nœuds=${nodes.length} ways=${footWayCount} arêtes=${footEdgeCount}`);
  console.log(`[GRAPH] taille=${(fs.statSync(OUT_FILE).size / 1024 / 1024).toFixed(1)} Mo`);

  fs.writeFileSync(CAR_OUT_FILE, JSON.stringify(carGraph));
  console.log(`[GRAPH] ✅ ${CAR_OUT_FILE} (voiture)`);
  console.log(`[GRAPH] nœuds=${nodes.length} ways=${carWayCount} arêtes=${carEdgeCount}`);
}

main().catch((e) => {
  console.error('[GRAPH] Erreur :', e && e.message ? e.message : e);
  process.exit(1);
});
