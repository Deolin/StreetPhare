// server/src/runtimeConfig.js
//
// Configuration RUNTIME (modifiable à chaud) de StreetPhare.
//
// Contrairement à `config.js` (valeurs statiques issues des variables
// d'environnement), ce module gère les paramètres « métier » ajustables
// depuis la page d'administration et synchronisables avec les apps mobiles :
//   - consensusThreshold        → nombre de votes pour valider un signalement
//   - mergeRadiusMeters         → rayon de fusion « rapproché » (anti-doublon)
//   - crowdDensityThreshold     → seuil d'alerte de densité de foule
//   - crowdDensityRadiusMeters  → rayon de comptage de la densité
//   - ttls.*                    → durées de vie par type de signalement (minutes)
//   - panic.*                   → paramètres de l'agrégation PANIC collectif
//
// Fonctionnement : au démarrage, on MUTE `config` avec les éventuelles valeurs
// persistées (server/data/runtime-config.json). Les mises à jour ré-écrivent le
// fichier et le reste du code continue d'utiliser `config.X` sans changement.

const fs = require('fs');
const path = require('path');
const config = require('./config');

const FILE = path.join(__dirname, '..', 'data', 'runtime-config.json');

// Schéma de validation : clé → { type, min, max }.
const SCHEMA = {
  consensusThreshold: { type: 'number', min: 1, max: 10 },
  mergeRadiusMeters: { type: 'number', min: 2, max: 500 },
  crowdDensityThreshold: { type: 'number', min: 5, max: 1000 },
  crowdDensityRadiusMeters: { type: 'number', min: 5, max: 500 },
  ttls: {
    type: 'object',
    fields: {
      mobileDanger: { min: 1, max: 1440 },
      staticDanger: { min: 1, max: 1440 },
      panic: { min: 1, max: 1440 },
      collectiveDanger: { min: 1, max: 1440 },
      pendingDisplayMinutes: { min: 1, max: 1440 },
      absoluteRgpd: { min: 60, max: 4320 },
    },
  },
  panic: {
    type: 'object',
    fields: {
      proximityMeters: { min: 5, max: 500 },
      timeWindowMinutes: { min: 1, max: 60 },
      threshold: { min: 2, max: 50 },
      autoZoneRadius: { min: 10, max: 1000 },
    },
  },
};

/// Clés éditables par l'admin ET exposées aux clients.
function publicConfig() {
  return {
    consensusThreshold: config.consensusThreshold,
    mergeRadiusMeters: config.mergeRadiusMeters,
    crowdDensityThreshold: config.crowdDensityThreshold,
    crowdDensityRadiusMeters: config.crowdDensityRadiusMeters,
    ttls: { ...config.ttls },
    panic: { ...config.panic },
  };
}

function _applyValue(key, meta, rawValue) {
  if (meta.type === 'number') {
    const v = Number(rawValue);
    if (!Number.isFinite(v)) return false;
    if (v < meta.min || v > meta.max) return false;
    config[key] = Math.round(v);
    return true;
  }
  if (meta.type === 'object' && rawValue && typeof rawValue === 'object') {
    for (const [field, fmeta] of Object.entries(meta.fields || {})) {
      if (rawValue[field] === undefined) continue;
      const v = Number(rawValue[field]);
      if (!Number.isFinite(v)) continue;
      if (v < fmeta.min || v > fmeta.max) continue;
      config[key][field] = Math.round(v);
    }
    return true;
  }
  return false;
}

/// Applique un patch partiel { clé: valeur } sur `config`.
/// Ne touche que les clés valides de [SCHEMA].
function applyPatch(patch, { persist = true } = {}) {
  const applied = [];
  if (!patch || typeof patch !== 'object') return { applied };
  for (const [key, meta] of Object.entries(SCHEMA)) {
    if (patch[key] === undefined) continue;
    if (_applyValue(key, meta, patch[key])) applied.push(key);
  }
  if (persist) save();
  return { applied };
}

function save() {
  try {
    fs.mkdirSync(path.dirname(FILE), { recursive: true });
    fs.writeFileSync(FILE, JSON.stringify(publicConfig(), null, 2));
  } catch (e) {
    console.error('[RuntimeConfig] Échec sauvegarde :', e.message);
  }
}

function load() {
  try {
    if (!fs.existsSync(FILE)) return;
    const saved = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    const { applied } = applyPatch(saved, { persist: false });
    if (applied.length > 0) {
      console.log('[RuntimeConfig] Config runtime chargée depuis', FILE, '→', applied.join(', '));
    }
  } catch (e) {
    console.warn('[RuntimeConfig] Échec chargement config runtime :', e.message);
  }
}

module.exports = { load, save, applyPatch, publicConfig, SCHEMA, FILE };
