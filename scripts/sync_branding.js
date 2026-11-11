#!/usr/bin/env node
// scripts/sync_branding.js
//
// Centralise les assets de marque partagés entre la cible Flutter Web
// (`web/`) et le site vitrine (`web_vitrine/`).
//
// Source de vérité unique : `assets/branding/`.
// Ce script copie ces fichiers vers `web/` et `web_vitrine/` afin d'éviter
// toute divergence future (favicon, manifest PWA, icônes).
//
// Usage :
//   node scripts/sync_branding.js           # copie assets/branding → web/ et web_vitrine/
//   node scripts/sync_branding.js --check   # vérifie la synchronisation (CI), exit 1 si divergence

"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SOURCE = path.join(ROOT, "assets", "branding");
const TARGETS = [
  path.join(ROOT, "web"),
  path.join(ROOT, "web_vitrine"),
];

// Fichiers partagés (chemins relatifs à la source de vérité).
const FILES = [
  "favicon.ico",
  "favicon.png",
  "manifest.json",
  path.join("icons", "Icon-192.png"),
  path.join("icons", "Icon-512.png"),
  path.join("icons", "Icon-maskable-192.png"),
  path.join("icons", "Icon-maskable-512.png"),
];

const CHECK = process.argv.includes("--check");

function readOrNull(p) {
  try {
    return fs.readFileSync(p);
  } catch (e) {
    return null;
  }
}

function syncFile(rel) {
  const src = path.join(SOURCE, rel);
  const srcBuf = readOrNull(src);
  if (srcBuf === null) {
    console.error(`✗ Source manquante : ${rel}`);
    return false;
  }

  let ok = true;
  for (const target of TARGETS) {
    const dst = path.join(target, rel);
    const dstBuf = readOrNull(dst);
    if (dstBuf !== null && dstBuf.equals(srcBuf)) {
      continue; // déjà synchronisé
    }
    if (CHECK) {
      console.error(`✗ Divergence : ${rel} (${path.relative(ROOT, dst)})`);
      ok = false;
      continue;
    }
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.writeFileSync(dst, srcBuf);
    console.log(`✓ ${rel} → ${path.relative(ROOT, dst)}`);
  }
  return ok;
}

function main() {
  let ok = true;
  for (const rel of FILES) {
    if (!syncFile(rel)) ok = false;
  }

  if (CHECK) {
    if (ok) {
      console.log("✓ Assets de marque synchronisés.");
    } else {
      console.error(
        "✗ Des divergences ont été détectées. Lancez `node scripts/sync_branding.js`.",
      );
      process.exit(1);
    }
  } else {
    console.log("✓ Synchronisation terminée.");
  }
}

main();
