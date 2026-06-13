// test_servers/launch_all.js
// Lanceur intégré StreetPhare v2 — démarre les 4 services :
//   Primary  (3000) + Backup (3001) + Admin (4000) + Vitrine (5000)
// Usage : node launch_all.js
'use strict';

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const http = require('http');

const ROOT = path.join(__dirname, '..');
const HERE = __dirname;

// ── Helper : spawn un serveur Node avec redirection vers log ──────────────
function startServer(label, file, env, logBase) {
  const outPath = path.join(ROOT, logBase + '.log');
  const errPath = path.join(ROOT, logBase + '_err.log');
  const out = fs.openSync(outPath, 'a');
  const err = fs.openSync(errPath, 'a');

  const child = spawn('node', [file], {
    cwd: HERE,
    env: { ...process.env, ...env },
    stdio: ['ignore', out, err],
    detached: false,
  });

  child.on('error', (e) => {
    console.error(`[${label}] spawn error: ${e.message}`);
  });
  child.on('exit', (code, signal) => {
    console.log(`[${label}] exited — code=${code} signal=${signal}`);
  });

  console.log(`✅ [${label}] PID=${child.pid} | log → ${logBase}.log`);
  return child;
}

// ── 1. Serveur Principal :3000 ────────────────────────────────────────────
startServer('Primary:3000', path.join(HERE, 'server_primary_v2.js'), {
  PORT:                    '3000',
  ROLE:                    'primary',
  NEXT_BACKUP_URL:         'http://localhost:3001',
  STREETPHARE_MASTER_KEY:  'streetphare-dev-key-CHANGE_ME_IN_PROD',
  STREETPHARE_LOG:         '1',
  NODE_ENV:                'development',
}, 'primary_live');

// ── 2. Serveur Backup :3001 ───────────────────────────────────────────────
startServer('Backup:3001', path.join(HERE, 'server_secondary_v2.js'), {
  PORT:                    '3001',
  ROLE:                    'secondary',
  PRIMARY_URL:             'http://localhost:3000',
  STREETPHARE_MASTER_KEY:  'streetphare-dev-key-CHANGE_ME_IN_PROD',
  STREETPHARE_LOG:         '1',
  NODE_ENV:                'development',
}, 'secondary_live');

// ── 3. Admin Dashboard :4000 ──────────────────────────────────────────────
startServer('Admin:4000', path.join(HERE, 'admin_dashboard.js'), {
  ADMIN_PORT:   '4000',
  PRIMARY_URL:  'http://localhost:3000',
  NODE_ENV:     'development',
}, 'admin_live');

// ── 4. Mini-site Vitrine :5000 ────────────────────────────────────────────
const VITRINE_DIR = path.join(ROOT, 'web_vitrine');
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css',
  '.js':   'application/javascript',
  '.json': 'application/json',
  '.png':  'image/png',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
};

const vitrineServer = http.createServer((req, res) => {
  const safePath = req.url.split('?')[0].replace(/\.\./g, '');
  const filePath = path.join(VITRINE_DIR, safePath === '/' ? 'index.html' : safePath);
  if (!filePath.startsWith(VITRINE_DIR)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      fs.readFile(path.join(VITRINE_DIR, 'index.html'), (_e, d2) => {
        if (_e) { res.writeHead(404); res.end('Not Found'); return; }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(d2);
      });
      return;
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

vitrineServer.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.warn('[Vitrine:5000] Port déjà occupé — vitrine déjà en cours?');
  } else {
    console.error('[Vitrine:5000] Erreur:', e.message);
  }
});

vitrineServer.listen(5000, () => {
  console.log('✅ [Vitrine:5000] Mini-site web vitrine → http://localhost:5000');
});

// ── Récapitulatif ─────────────────────────────────────────────────────────
console.log('\n🚀 StreetPhare LaunchPad v2 — Démarrage en cours...');
console.log('   Primary  → http://localhost:3000/ping');
console.log('   Backup   → http://localhost:3001/ping');
console.log('   Admin    → http://localhost:4000/dashboard');
console.log('   Vitrine  → http://localhost:5000');
console.log('   Android  → connecté via 192.168.31.18\n');

// ── Keep-alive (empêche le launcher de quitter immédiatement) ─────────────
process.on('SIGINT',  () => { console.log('\n[LaunchPad] SIGINT — arrêt.'); process.exit(0); });
process.on('SIGTERM', () => { console.log('\n[LaunchPad] SIGTERM — arrêt.'); process.exit(0); });

// Ping de vérification après 3 secondes
setTimeout(() => {
  ['3000','3001','4000','5000'].forEach(port => {
    const req = http.request({ host:'127.0.0.1', port, path: port === '5000' ? '/' : '/ping', timeout: 2000 }, r => {
      console.log(`  ✅ :${port} → HTTP ${r.statusCode}`);
    });
    req.on('error', () => console.log(`  ❌ :${port} → connexion refusée`));
    req.end();
  });
}, 3000);

// Maintien en vie
setInterval(() => {}, 30000);
