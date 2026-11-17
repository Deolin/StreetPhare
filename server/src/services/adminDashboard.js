// server/src/services/adminDashboard.js
//
// Sert l'index du dashboard d'administration en y injectant un flag
// d'environnement : l'onglet « Simulation » (fonction de test / dev) est
// masqué côté client quand le serveur tourne en NODE_ENV=production.
//
// Le fichier index.html contient le marqueur `<!--SP_ENV-->`, remplacé ici
// par une déclaration `window.SP_PRODUCTION = true|false`.

const fs = require('fs');
const path = require('path');

const INDEX_PATH = path.join(__dirname, '..', '..', 'public', 'admin', 'index.html');
const ENV_MARKER = '<!--SP_ENV-->';

/// `true` lorsque le serveur tourne en production (NODE_ENV=production).
const isProduction = process.env.NODE_ENV === 'production';

/// Lit index.html et remplace le marqueur par le flag d'environnement.
function renderHtml() {
  const html = fs.readFileSync(INDEX_PATH, 'utf8');
  const flag = `<script>window.SP_PRODUCTION = ${isProduction};</script>`;
  return html.replace(ENV_MARKER, flag);
}

/// Handler Express : sert l'index avec un en-tête anti-cache et le flag injecté.
function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  res.type('html').send(renderHtml());
}

module.exports = { handler, isProduction };
