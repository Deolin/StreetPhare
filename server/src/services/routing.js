// server/src/services/routing.js
//
// Moteur de routage piéton embarqué côté serveur (Dijkstra en mémoire).
// Charge le graphe compact généré par scripts/build_routing_graph.js
// (server/data/fleurus.graph.json) et calcule des itinéraires sans
// dépendance native. Aucune requête vers OSRM/GraphHopper externe.

const fs = require('fs');
const path = require('path');

const PEDESTRIAN_SPEED_MS = 1.2; // ~4.3 km/h

// ── Binary min-heap ────────────────────────────────────────────────────────
class MinHeap {
  constructor() {
    this.heap = []; // [priority, value]
  }
  size() {
    return this.heap.length;
  }
  push(priority, value) {
    const h = this.heap;
    h.push([priority, value]);
    let i = h.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (h[p][0] <= h[i][0]) break;
      [h[p], h[i]] = [h[i], h[p]];
      i = p;
    }
  }
  pop() {
    const h = this.heap;
    const top = h[0];
    const last = h.pop();
    if (h.length > 0) {
      h[0] = last;
      let i = 0;
      const n = h.length;
      for (;;) {
        const l = 2 * i + 1;
        const r = 2 * i + 2;
        let m = i;
        if (l < n && h[l][0] < h[m][0]) m = l;
        if (r < n && h[r][0] < h[m][0]) m = r;
        if (m === i) break;
        [h[m], h[i]] = [h[i], h[m]];
        i = m;
      }
    }
    return top;
  }
}

/** Distance minimale entre un point P et le segment [A, B] (mètres). */
function pointSegDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) return Math.hypot(px - ax, py - ay);
  let t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
  if (t < 0) t = 0;
  else if (t > 1) t = 1;
  const cx = ax + t * dx;
  const cy = ay + t * dy;
  return Math.hypot(px - cx, py - cy);
}

class RoutingEngine {
  constructor() {
    this.graph = null;
    this.connected = [];
    this.nodesX = null;
    this.nodesY = null;
    this.refLat = 0;
    this.refLon = 0;
    this.cosRef = 1;
  }

  load() {
    if (this.graph) return this.graph;
    const file = path.join(__dirname, '..', '..', 'data', 'fleurus.graph.json');
    if (!fs.existsSync(file)) {
      throw new Error(
        'Graphe de routage absent. Exécutez : node scripts/build_routing_graph.js',
      );
    }
    this.graph = JSON.parse(fs.readFileSync(file, 'utf-8'));
    this.connected = [];
    for (let i = 0; i < this.graph.adj.length; i++) {
      if (this.graph.adj[i].length > 0) this.connected.push(i);
    }
    // Pré-calcul des coordonnées planaires (projection équirectangulaire)
    // pour des calculs de distance rapides et l'évitement des zones à risque.
    const nb = this.graph.nodes.length;
    this.refLat = this.graph.nodes[0][0];
    this.refLon = this.graph.nodes[0][1];
    this.cosRef = Math.cos((this.refLat * Math.PI) / 180);
    this.nodesX = new Float64Array(nb);
    this.nodesY = new Float64Array(nb);
    for (let i = 0; i < nb; i++) {
      this.nodesX[i] = (this.graph.nodes[i][1] - this.refLon) * 111320 * this.cosRef;
      this.nodesY[i] = (this.graph.nodes[i][0] - this.refLat) * 110540;
    }
    console.log(
      `[ROUTING] Graphe chargé : ${this.graph.meta.nodes} nœuds, ` +
        `${this.connected.length} connectés, ${this.graph.meta.edges} arêtes`,
    );
    return this.graph;
  }

  isReady() {
    return !!this.graph;
  }

  /** Renvoie l'index du nœud connecté le plus proche (distance angulaire). */
  nearest(lat, lon) {
    const nodes = this.graph.nodes;
    let best = -1;
    let bestD = Infinity;
    for (const idx of this.connected) {
      const n = nodes[idx];
      const dLat = n[0] - lat;
      const dLon = n[1] - lon;
      const d = dLat * dLat + dLon * dLon;
      if (d < bestD) {
        bestD = d;
        best = idx;
      }
    }
    return best;
  }

  /** Convertit les zones à risque en coordonnées planaires. */
  _prepareAvoid(avoidPoints) {
    if (!avoidPoints || avoidPoints.length === 0) return [];
    const out = [];
    for (const p of avoidPoints) {
      const lat = p.lat;
      const lon = p.lon;
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
      out.push({
        x: (lon - this.refLon) * 111320 * this.cosRef,
        y: (lat - this.refLat) * 110540,
        radius: Number.isFinite(p.radius) ? p.radius : 30,
        weight: Number.isFinite(p.weight) ? p.weight : 10,
      });
    }
    return out;
  }

  /** Poids d'une arête, pénalisé si elle traverse une zone à risque. */
  _edgeWeight(u, v, baseDist, avoid) {
    if (avoid.length === 0) return baseDist;
    const ax = this.nodesX[u];
    const ay = this.nodesY[u];
    const bx = this.nodesX[v];
    const by = this.nodesY[v];
    let mult = 1;
    for (const p of avoid) {
      const d = pointSegDist(p.x, p.y, ax, ay, bx, by);
      if (d <= p.radius) {
        mult = Math.max(mult, p.weight);
      }
    }
    return baseDist * mult;
  }

  /**
   * Calcule l'itinéraire piéton le plus court en pénalisant les zones à risque.
   *
   * @param {Array<{lat:number,lon:number,radius?:number,weight?:number}>} avoidPoints
   *   Zones de danger validées : les arêtes passant à moins de `radius` mètres
   *   d'un point sont pondérées (×`weight`, défaut 10) pour être évitées sans
   *   être exclues (si aucun contournement n'existe, le chemin traverse).
   * @returns {Object|null} { points: [[lat,lon],...], distanceMeters, durationSeconds }
   */
  route(fromLat, fromLon, toLat, toLon, avoidPoints = []) {
    const g = this.load();
    const start = this.nearest(fromLat, fromLon);
    const end = this.nearest(toLat, toLon);
    if (start < 0 || end < 0) return null;

    // Départ et arrivée identiques.
    if (start === end) {
      return {
        points: [
          [fromLat, fromLon],
          [toLat, toLon],
        ],
        distanceMeters: 0,
        durationSeconds: 0,
      };
    }

    const avoid = this._prepareAvoid(avoidPoints);

    const n = g.nodes.length;
    const dist = new Float64Array(n).fill(Infinity);
    const prev = new Int32Array(n).fill(-1);
    const visited = new Uint8Array(n);
    const heap = new MinHeap();

    dist[start] = 0;
    heap.push(0, start);

    while (heap.size() > 0) {
      const [, u] = heap.pop();
      if (visited[u]) continue;
      visited[u] = 1;
      if (u === end) break;
      const adj = g.adj[u];
      for (let i = 0; i < adj.length; i++) {
        const v = adj[i][0];
        if (visited[v]) continue;
        const w = this._edgeWeight(u, v, adj[i][1], avoid);
        const nd = dist[u] + w;
        if (nd < dist[v]) {
          dist[v] = nd;
          prev[v] = u;
          heap.push(nd, v);
        }
      }
    }

    if (!visited[end]) return null; // pas de chemin

    // Reconstruction du chemin.
    const pathIdx = [];
    let cur = end;
    while (cur !== -1) {
      pathIdx.push(cur);
      cur = prev[cur];
    }
    pathIdx.reverse();

    const points = [];
    for (const idx of pathIdx) {
      points.push([g.nodes[idx][0], g.nodes[idx][1]]);
    }

    // On force les extrémités exactes demandées par le client.
    points[0] = [fromLat, fromLon];
    points[points.length - 1] = [toLat, toLon];

    const distanceMeters = Math.round(dist[end]);
    return {
      points,
      distanceMeters,
      durationSeconds: Math.round(distanceMeters / PEDESTRIAN_SPEED_MS),
    };
  }
}

// Singleton partagé.
const routingEngine = new RoutingEngine();

module.exports = { routingEngine, RoutingEngine };
