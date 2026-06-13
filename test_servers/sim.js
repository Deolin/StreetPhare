#!/usr/bin/env node
// test_servers/sim.js
//
// 🚀 Outil CLI de simulation StreetPhare
//
// Permet d'exécuter des scénarios d'injection massifs depuis la ligne de commande.
//
// Usage :
//   node sim.js --users 50 --alerts 10 --panic 3
//   node sim.js --users 100 --alerts 20 --hive 50 --center 50.489,4.545
//   node sim.js --reset
//
// Toutes les opérations sont envoyées au sandbox API (port 3000/3001 par défaut).

'use strict';

const http = require('http');

// ── Arguments CLI ────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function getArg(name, defaultVal = null) {
  const idx = args.indexOf('--' + name);
  if (idx === -1) return defaultVal;
  return args[idx + 1] || defaultVal;
}
function hasFlag(name) {
  return args.includes('--' + name);
}

const SANDBOX_HOST = getArg('host', '127.0.0.1');
const SANDBOX_PORT = parseInt(getArg('port', '3000'), 10);
const CENTER = getArg('center', '48.8566,2.3522');
const [centerLat, centerLng] = CENTER.split(',').map(Number);

const userCount    = parseInt(getArg('users', '0'), 10);
const alertCount   = parseInt(getArg('alerts', '0'), 10);
const eventCount   = parseInt(getArg('events', '0'), 10);
const hiveCount    = parseInt(getArg('hive', '0'), 10);
const panicPeers   = parseInt(getArg('panic', '0'), 10);
const speed        = parseInt(getArg('speed', '5'), 10);
const alertType    = getArg('type', null);
const doReset      = hasFlag('reset');
const verbose      = hasFlag('v') || hasFlag('verbose');

// ── Helpers ──────────────────────────────────────────────────────────────────
function post(path, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const opts = {
      hostname: SANDBOX_HOST,
      port: SANDBOX_PORT,
      path: '/sandbox' + path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    };
    const req = http.request(opts, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { resolve({ raw: data }); }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function log(emoji, msg) {
  console.log(`${emoji}  ${msg}`);
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('');
  console.log('⚡ StreetPhare Simulation CLI');
  console.log(`   Serveur : http://${SANDBOX_HOST}:${SANDBOX_PORT}/sandbox`);
  console.log(`   Centre  : ${centerLat}, ${centerLng}`);
  console.log('');

  try {
    if (doReset) {
      log('🗑', 'Réinitialisation de la sandbox…');
      const r = await post('/reset', {});
      log('✅', r.message || 'Sandbox réinitialisée');
      return;
    }

    const tasks = [];

    if (userCount > 0) {
      log('👥', `Simulation de ${userCount} utilisateurs GPS à ${speed} km/h…`);
      tasks.push(
        post('/simulate-users', {
          count: userCount,
          centerLat,
          centerLng,
          speedKmh: speed,
        }).then((r) => log('✅', `${r.started} utilisateurs démarrés (total actifs : ${r.totalActive})`))
      );
    }

    if (alertCount > 0) {
      log('🚨', `Injection de ${alertCount} alertes (type=${alertType || 'aléatoire'})…`);
      tasks.push(
        post('/inject-alerts', {
          count: alertCount,
          type: alertType || null,
          centerLat,
          centerLng,
        }).then((r) => log('✅', `${r.injected} alertes injectées`))
      );
    }

    if (eventCount > 0) {
      log('📅', `Injection de ${eventCount} événements…`);
      tasks.push(
        post('/inject-events', {
          count: eventCount,
          centerLat,
          centerLng,
        }).then((r) => log('✅', `${r.injected} événements injectés`))
      );
    }

    if (hiveCount > 0) {
      log('💬', `Envoi de ${hiveCount} messages Hive P2P…`);
      tasks.push(
        post('/send-hive-messages', {
          count: hiveCount,
        }).then((r) => log('✅', `${r.sent} messages Hive envoyés`))
      );
    }

    if (panicPeers > 0) {
      log('🆘', `Simulation de Panic collectif (${panicPeers} pairs)…`);
      tasks.push(
        post('/trigger-panic', {
          peerCount: panicPeers,
          centerLat,
          centerLng,
        }).then((r) => log('✅', `Panic collectif simulé (${r.peerCount} pairs)`))
      );
    }

    if (tasks.length === 0) {
      console.log('ℹ️  Aucune action spécifiée. Options disponibles :');
      console.log('');
      console.log('   --users <n>     Nombre d\'utilisateurs GPS à simuler');
      console.log('   --alerts <n>    Nombre d\'alertes à injecter');
      console.log('   --events <n>    Nombre d\'événements à injecter');
      console.log('   --hive <n>      Nombre de messages Hive P2P');
      console.log('   --panic <n>     Nombre de pairs pour le Panic collectif');
      console.log('   --speed <n>     Vitesse des utilisateurs (km/h, défaut: 5)');
      console.log('   --type <type>   Type d\'alerte (barrage|nasse|controle|accident|...)');
      console.log('   --center <lat,lng> Centre géographique (défaut: 48.8566,2.3522)');
      console.log('   --host <h>      Hôte du serveur sandbox (défaut: 127.0.0.1)');
      console.log('   --port <p>      Port du serveur (défaut: 3000)');
      console.log('   --reset         Réinitialise la sandbox');
      console.log('   --verbose       Mode verbeux');
      console.log('');
      console.log('Exemples :');
      console.log('   npm run sim -- --users 50 --alerts 10');
      console.log('   npm run sim -- --users 100 --hive 50 --panic 5');
      console.log('   npm run sim -- --reset');
      return;
    }

    await Promise.all(tasks);
    log('🎉', 'Toutes les simulations lancées avec succès !');
  } catch (err) {
    log('❌', `Erreur : ${err.message}`);
    console.log('');
    console.log('   Vérifiez que le serveur sandbox est lancé :');
    console.log('   npm start  (ou node start_servers_v2.js)');
    process.exit(1);
  }
}

main();