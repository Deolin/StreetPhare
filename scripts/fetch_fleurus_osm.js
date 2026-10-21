#!/usr/bin/env node
// scripts/fetch_fleurus_osm.js
//
// Télécharge l'extrait OSM de la zone de Fleurus via l'API Overpass
// (OpenStreetMap) et le place dans les assets Android pour le moteur
// de routage GraphHopper local.
//
// Bbox de Fleurus : Sud 50.44, Ouest 4.50, Nord 50.52, Est 4.60
//   → node(50.44, 4.50, 50.52, 4.60) etc.
//
// Usage : node scripts/fetch_fleurus_osm.js

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

const ROOT = path.resolve(__dirname, '..');
const ASSETS_DIR = path.join(ROOT, 'android', 'app', 'src', 'main', 'assets', 'osm');
const OUTPUT_FILE = path.join(ASSETS_DIR, 'fleurus.osm');

const QUERY_PBF = '[out:pbf][timeout:25];' +
  '(node(50.45,4.52,50.50,4.58);' +
  'way(50.45,4.52,50.50,4.58););' +
  'out body;>;out skel qt;';

const QUERY_XML = '[out:xml][timeout:25];' +
  '(node(50.45,4.52,50.50,4.58);' +
  'way(50.45,4.52,50.50,4.58););' +
  'out body;>;out skel qt;';

const HOST = 'overpass-api.de';
const API_PATH = '/api/interpreter';

function requestOnce(protocol, query) {
  return new Promise((resolve, reject) => {
    const mod = protocol === 'https:' ? https : http;
    const url = `${protocol}//${HOST}${API_PATH}?data=${encodeURIComponent(query)}`;

    console.log(`[OSM] → ${protocol}//${HOST}${API_PATH} (${query.slice(0, 12)})`);

    const req = mod.get(
      url,
      { headers: { 'User-Agent': 'StreetPhare/1.0 (osm-extract)' } },
      (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          reject(new Error(`Redirection ${res.statusCode}`));
          return;
        }
        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`HTTP ${res.statusCode}`));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
      },
    );

    req.on('error', reject);
    req.setTimeout(90000, () => req.destroy(new Error('Timeout 90s')));
  });
}

async function fetchWithFallback(query) {
  try {
    const data = await requestOnce('https:', query);
    console.log('[OSM] Récupération HTTPS OK');
    return data;
  } catch (e) {
    console.warn(`[OSM] HTTPS échoué (${e.message}) → tentative HTTP`);
    return await requestOnce('http:', query);
  }
}

function isPbf(buf) {
  // En-tête PBF : 4 octets de longueur + "OSMHeader".
  return buf.length > 16 && buf.slice(4, 13).toString('latin1') === 'OSMHeader';
}

// Réordonne l'XML OSM : tous les <node> avant les <way> (GraphHopper l'exige).
// La sortie Overpass `>; out skel qt;` place des <node> APRÈS les <way>.
function reorderOsm(xml) {
  const lines = xml.split(/\r?\n/);
  const header = [];
  const footer = [];
  const nodes = [];
  const ways = [];
  const relations = [];
  let current = null;

  // Déduplique les nœuds : la sortie Overpass `>; out skel qt;` ré-émet des
  // nœuds déjà présents via `out body` (même ID, mêmes coordonnées). GraphHopper
  // refuse les IDs de nœud en double.
  const seenNodeIds = new Set();

  const flush = () => {
    if (!current) return;
    if (current.type === 'node') {
      const m = (current.lines[0] || '').match(/id="([^"]+)"/);
      if (m) {
        if (seenNodeIds.has(m[1])) {
          current = null;
          return;
        }
        seenNodeIds.add(m[1]);
      }
    }
    const arr = current.type === 'node' ? nodes
      : current.type === 'way' ? ways : relations;
    arr.push(...current.lines);
    current = null;
  };

  for (const line of lines) {
    const t = line.trim();
    if (t.startsWith('<?xml') || t.startsWith('<osm')) {
      header.push(line);
    } else if (t.startsWith('</osm>')) {
      flush();
      footer.push(line);
    } else if (t.startsWith('<node')) {
      flush();
      current = { type: 'node', lines: [line] };
      if (t.endsWith('/>')) flush();
    } else if (t.startsWith('<way')) {
      flush();
      current = { type: 'way', lines: [line] };
    } else if (t.startsWith('<relation')) {
      flush();
      current = { type: 'relation', lines: [line] };
    } else if (
      t.startsWith('</node>') || t.startsWith('</way>') || t.startsWith('</relation>')
    ) {
      if (current) current.lines.push(line);
      flush();
    } else if (current) {
      current.lines.push(line);
    }
  }

  return [...header, ...nodes, ...ways, ...relations, ...footer].join('\n');
}

async function main() {
  // 1. Crée le dossier assets s'il n'existe pas.
  fs.mkdirSync(ASSETS_DIR, { recursive: true });
  console.log(`[OSM] Dossier prêt : ${ASSETS_DIR}`);

  // 2. Essaie d'abord le PBF (binaire, beaucoup plus léger et rapide
  //    à importer par GraphHopper), puis retombe sur le XML.
  let data;
  try {
    data = await fetchWithFallback(QUERY_PBF);
    if (isPbf(data)) {
      const pbfFile = path.join(ASSETS_DIR, 'fleurus.osm.pbf');
      fs.writeFileSync(pbfFile, data);
      console.log(`[OSM] PBF valide écrit : ${pbfFile}`);
      console.log(`[OSM] Taille : ${(data.length / 1024).toFixed(1)} Ko`);
      // Nettoie un éventuel ancien fichier XML.
      const oldXml = path.join(ASSETS_DIR, 'fleurus.osm');
      if (fs.existsSync(oldXml)) fs.unlinkSync(oldXml);
      return;
    }
    console.warn('[OSM] Réponse non-PBF → repli XML');
  } catch (e) {
    console.warn(`[OSM] PBF échoué (${e.message}) → repli XML`);
  }

  data = await fetchWithFallback(QUERY_XML);
  const text = data.toString('utf-8');
  if (text.length === 0 || (!text.includes('<osm') && !text.includes('</osm>'))) {
    console.error('[OSM] Réponse XML inattendue. Début :');
    console.error(text.slice(0, 300));
    process.exit(1);
  }
  const ordered = reorderOsm(text);
  fs.writeFileSync(OUTPUT_FILE, ordered, 'utf-8');
  const size = Buffer.byteLength(ordered, 'utf-8');
  console.log(`[OSM] Fichier XML écrit (réordonné) : ${OUTPUT_FILE}`);
  console.log(`[OSM] Taille : ${(size / 1024).toFixed(1)} Ko`);
}

main().catch((e) => {
  console.error('[OSM] Erreur :', e && e.message ? e.message : e);
  process.exit(1);
});
