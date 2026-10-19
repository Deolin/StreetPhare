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
  const adjMap = new Map(); // index -> Map(neighbor -> minDist)

  let currentWay = null; // { refs: [], highway: null }
  let wayCount = 0;
  let edgeCount = 0;

  const addEdge = (a, b, dist) => {
    if (a === b) return;
    if (!adjMap.has(a)) adjMap.set(a, new Map());
    if (!adjMap.has(b)) adjMap.set(b, new Map());
    const am = adjMap.get(a);
    const bm = adjMap.get(b);
    if (dist < (am.get(b) ?? Infinity)) {
      am.set(b, dist);
      bm.set(a, dist);
      edgeCount++;
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
      if (m) {
        idToIndex.set(m[1], nodes.length);
        nodes.push([parseFloat(m[2]), parseFloat(m[3])]);
      }
    } else if (t.startsWith('<way ')) {
      currentWay = { refs: [], highway: null };
    } else if (t.startsWith('<nd ')) {
      const m = t.match(/ref="(\d+)"/);
      if (m && currentWay) currentWay.refs.push(m[1]);
    } else if (t.startsWith('<tag ')) {
      const m = t.match(/k="([^"]+)"\s+v="([^"]*)"/);
      if (m && currentWay && m[1] === 'highway') currentWay.highway = m[2];
    } else if (t.startsWith('</way>')) {
      if (currentWay && currentWay.highway && !NON_WALKABLE.has(currentWay.highway)) {
        wayCount++;
        const mult = HIGHWAY_WEIGHT[currentWay.highway] || 1.5;
        const refs = currentWay.refs;
        for (let i = 0; i + 1 < refs.length; i++) {
          const a = idToIndex.get(refs[i]);
          const b = idToIndex.get(refs[i + 1]);
          if (a === undefined || b === undefined) continue;
          const dist = haversine(nodes[a][0], nodes[a][1], nodes[b][0], nodes[b][1]);
          addEdge(a, b, Math.round(dist * mult));
        }
      }
      currentWay = null;
    }
  }

  // Sérialisation compacte : adj[i] = [[voisin, distance], ...]
  const adj = nodes.map((_, i) => {
    const m = adjMap.get(i);
    if (!m) return [];
    return Array.from(m.entries()).map(([to, dist]) => [to, dist]);
  });

  const graph = {
    meta: {
      generatedAt: new Date().toISOString(),
      source: path.basename(OSM_FILE),
      nodes: nodes.length,
      ways: wayCount,
      edges: edgeCount,
    },
    nodes,
    adj,
  };

  fs.mkdirSync(path.dirname(OUT_FILE), { recursive: true });
  fs.writeFileSync(OUT_FILE, JSON.stringify(graph));
  console.log(`[GRAPH] ✅ ${OUT_FILE}`);
  console.log(`[GRAPH] nœuds=${nodes.length} ways=${wayCount} arêtes=${edgeCount}`);
  console.log(
    `[GRAPH] taille=${(fs.statSync(OUT_FILE).size / 1024 / 1024).toFixed(1)} Mo`,
  );
}

main().catch((e) => {
  console.error('[GRAPH] Erreur :', e && e.message ? e.message : e);
  process.exit(1);
});
