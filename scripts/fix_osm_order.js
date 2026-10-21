#!/usr/bin/env node
// scripts/fix_osm_order.js
//
// Réordonne un fichier OSM XML pour placer TOUS les <node> avant les <way>
// (et <relation>). GraphHopper (WaySegmentParser) exige cet ordre : la sortie
// Overpass avec `>; out skel qt;` place des <node> APRÈS les <way>.
//
// Usage : node scripts/fix_osm_order.js [fichier.osm]

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OSM_FILE = process.argv[2] || path.join(
  ROOT, 'android', 'app', 'src', 'main', 'assets', 'osm', 'fleurus.osm',
);

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
      if (t.endsWith('/>')) flush(); // nœud auto-fermant
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

const xml = fs.readFileSync(OSM_FILE, 'utf-8');
const out = reorderOsm(xml);
fs.writeFileSync(OSM_FILE, out, 'utf-8');
console.log(`[OSM] Réordonné (nodes avant ways) : ${OSM_FILE}`);
console.log(`[OSM] taille : ${(Buffer.byteLength(out, 'utf-8') / 1024 / 1024).toFixed(1)} Mo`);
