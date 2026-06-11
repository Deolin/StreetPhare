// test_servers/start_servers_v2.js
//
// StreetPhare — Orchestrateur v2 (Serveur Principal + Backup)
// ===========================================================
// Lance les deux serveurs Node.js v2 en parallèle dans un seul
// process Node.js, avec :
//
//   ✅  Surveillance croisée de l'état des deux process enfants
//   ✅  Mise à jour en temps réel de SERVER_STATUS.md (tableau de bord)
//   ✅  Redémarrage automatique d'un serveur crashé (max 3 tentatives)
//   ✅  Arrêt propre (SIGINT / SIGTERM)
//   ✅  Affichage de la topologie dans la console au démarrage
//
// Usage :
//   node start_servers_v2.js
//   STREETPHARE_LOG=0 node start_servers_v2.js   (dashboard désactivé)
//
// Variables d'environnement utilisées :
//   PORT_PRIMARY      — port du serveur principal (défaut: 3000)
//   PORT_BACKUP       — port du serveur backup    (défaut: 3001)
//   STREETPHARE_MASTER_KEY — clé AES (défaut: clé de dev)
//   HB_INTERVAL_MS    — intervalle heartbeat ms   (défaut: 5000)
//   HB_FAIL_THRESHOLD — échecs avant failover     (défaut: 3)
//   STREETPHARE_LOG   — 0 pour désactiver le dashboard
//
'use strict';

const { spawn } = require('child_process');
const path      = require('path');
const fs        = require('fs');

// ── Configuration ─────────────────────────────────────────────────────────
const PORT_PRIMARY   = parseInt(process.env.PORT_PRIMARY || '3000', 10);
const PORT_BACKUP    = parseInt(process.env.PORT_BACKUP  || '3001', 10);
const MAX_RESTARTS   = 3;   // tentatives de redémarrage automatique
const RESTART_DELAY  = 2000; // délai entre redémarrages (ms)
const PROJECT_ROOT   = path.resolve(__dirname, '..');
const STATUS_FILE    = path.join(PROJECT_ROOT, 'SERVER_STATUS.md');

// ── État de l'orchestrateur ───────────────────────────────────────────────
const state = {
  primary:  { child: null, restarts: 0, status: 'starting', port: PORT_PRIMARY },
  backup:   { child: null, restarts: 0, status: 'starting', port: PORT_BACKUP  },
  startedAt: new Date(),
};

// ── Logger orchestrateur ──────────────────────────────────────────────────
function log(label, ...args) {
  const ts = new Date().toISOString();
  console.log(`[${ts}][orchestrator][${label}]`, ...args);
}

// ── Écriture du fichier SERVER_STATUS.md ──────────────────────────────────

/**
 * (Re)écrit SERVER_STATUS.md avec l'état courant de la topologie.
 * Appelé à chaque changement d'état d'un serveur enfant.
 */
function writeDashboard() {
  if (process.env.STREETPHARE_LOG === '0') return;

  const now    = new Date();
  const uptime = Math.round((now - state.startedAt) / 1000);
  const pad    = (n) => String(n).padStart(2, '0');
  const fmt    = (d) =>
    `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;

  const icon = (s) =>
    s === 'online'   ? '🟢 EN LIGNE'   :
    s === 'starting' ? '🟡 DÉMARRAGE'  :
    s === 'crashed'  ? '🔴 CRASHÉ'     :
    s === 'stopped'  ? '⚫ ARRÊTÉ'     : '⚪ INCONNU';

  const lines = [
    '# 📡 Tableau de bord StreetPhare — Topologie Serveurs',
    '',
    `> Dernière mise à jour : **${fmt(now)}** — Uptime orchestrateur : **${uptime}s**`,
    `> Fichier généré par \`test_servers/start_servers_v2.js\``,
    '',
    '---',
    '',
    '## 🖥️ Statut des Nœuds',
    '',
    '| Serveur | Port | URL | Statut | Redémarrages |',
    '| --- | --- | --- | --- | --- |',
    `| ⭐ Principal | ${PORT_PRIMARY} | http://localhost:${PORT_PRIMARY} | ${icon(state.primary.status)} | ${state.primary.restarts}/${MAX_RESTARTS} |`,
    `| 🛡️ Backup    | ${PORT_BACKUP}  | http://localhost:${PORT_BACKUP}  | ${icon(state.backup.status)}  | ${state.backup.restarts}/${MAX_RESTARTS} |`,
    '',
    '---',
    '',
    '## 🔗 Endpoints Disponibles',
    '',
    '### Serveur Principal (`http://localhost:' + PORT_PRIMARY + '`)',
    '',
    '| Méthode | Endpoint | Description |',
    '| --- | --- | --- |',
    '| GET | `/ping` | Heartbeat simple |',
    '| GET | `/healthz` | Heartbeat FailoverManager |',
    '| GET | `/status` | Topologie JSON complète |',
    '| GET | `/v1/events` | Liste des événements (Fleurus) |',
    '| GET | `/v1/events/:id` | Détails + QR payload |',
    '| POST | `/v1/events/:id/route` | Calcul Safe Route (1+3 alt.) |',
    '| POST | `/v1/reports` | Soumettre un signalement |',
    '| GET | `/v1/reports` | Signalements actifs (votes≥3) |',
    '| GET | `/v1/reports/stats` | Statistiques Panic Collectif |',
    '| POST | `/v1/alerts/sync` | Sync alertes v1 + next_backup chiffré |',
    '| GET | `/backup-route` | Adresse backup chiffrée AES |',
    '| GET | `/_debug/reports` | Debug store v2 complet |',
    '| POST | `/_debug/demote` | Forcer failover (test) |',
    '',
    '### Serveur Backup (`http://localhost:' + PORT_BACKUP + '`)',
    '',
    '| Méthode | Endpoint | Description |',
    '| --- | --- | --- |',
    '| GET | `/status` | Topologie + état HeartbeatMonitor |',
    '| POST | `/v1/events/:id/route` | Safe Route (mirror principal) |',
    '| POST | `/v1/reports` | Signalement (mirror principal) |',
    '| POST | `/_debug/promote` | Simuler promotion failover |',
    '| POST | `/_debug/demote` | Arrêter ce backup |',
    '',
    '---',
    '',
    '## ⚙️ Règles Métier',
    '',
    '### TTL des Signalements',
    '',
    '| Type | TTL | Diffusé si votes ≥ |',
    '| --- | --- | --- |',
    '| barrage / casseurs / danger | 600 s (10 min) | 3 |',
    '| policiers / autopompes / filtre | 60 s (1 min) | 3 |',
    '| panic (individuel) | 120 s | — (alimente Panic Collectif) |',
    '| danger_collectif (auto) | 600 s | 0 (toujours visible) |',
    '',
    '### Algorithme Panic Collectif',
    '',
    '> Si **5 requêtes `panic`** géolocalisées dans un rayon de **200 m**',
    '> arrivent en **< 2 minutes**, le serveur génère automatiquement',
    '> un point **Danger Collectif** centré sur le barycentre du cluster.',
    '',
    '---',
    '',
    '## 🧪 Tests Rapides (curl)',
    '',
    '```bash',
    '# Heartbeat',
    `curl http://localhost:${PORT_PRIMARY}/ping`,
    `curl http://localhost:${PORT_BACKUP}/healthz`,
    '',
    '# Topologie',
    `curl http://localhost:${PORT_BACKUP}/status | jq .topology_summary`,
    '',
    '# Événements',
    `curl http://localhost:${PORT_PRIMARY}/v1/events`,
    `curl http://localhost:${PORT_PRIMARY}/v1/events/fleurus-tour`,
    '',
    '# Safe Route',
    `curl -X POST http://localhost:${PORT_PRIMARY}/v1/events/fleurus-tour/route \\`,
    '     -H "Content-Type: application/json" \\',
    '     -d \'{"from":{"lat":50.4891,"lon":4.5452}}\'',
    '',
    '# Signalement (vote 1/3)',
    `curl -X POST http://localhost:${PORT_PRIMARY}/v1/reports \\`,
    '     -H "Content-Type: application/json" \\',
    '     -d \'{"id":"test-001","type":"barrage","lat":50.489,"lon":4.545,"reporter_id":"dev-1"}\'',
    '',
    '# Test Failover — couper le principal',
    `curl -X POST http://localhost:${PORT_PRIMARY}/_debug/demote -H "Content-Type: application/json" -d \'{"reason":"test failover"}\'`,
    `# → Le backup (port ${PORT_BACKUP}) devrait se promouvoir en ~15s`,
    `curl http://localhost:${PORT_BACKUP}/status`,
    '```',
    '',
    '---',
    '',
    `> ℹ️ Pour suivre en direct : \`tail -f SERVER_STATUS.md\``,
    `> Orchestrateur démarré le : **${fmt(state.startedAt)}**`,
    '',
  ];

  const body = lines.join('\n');
  try {
    const tmp = STATUS_FILE + '.tmp';
    fs.writeFileSync(tmp, body, 'utf8');
    fs.renameSync(tmp, STATUS_FILE);
  } catch (e) {
    console.error('[orchestrator] Erreur écriture SERVER_STATUS.md:', e.message);
  }
}

// ── Lancement d'un serveur enfant ─────────────────────────────────────────

/**
 * Démarre (ou redémarre) un serveur enfant.
 *
 * @param {'primary'|'backup'} key
 * @param {string} script    - chemin relatif vers le script JS
 * @param {number} port      - port d'écoute
 * @param {object} extraEnv  - variables d'env supplémentaires
 */
function startServer(key, script, port, extraEnv = {}) {
  const label = key === 'primary' ? 'PRIMARY' : 'BACKUP';
  const entry = state[key];

  const child = spawn(
    process.execPath,
    [path.join(__dirname, script)],
    {
      env: {
        ...process.env,
        PORT:                 String(port),
        ROLE:                 key === 'primary' ? 'primary' : 'secondary',
        STREETPHARE_MASTER_KEY:
          process.env.STREETPHARE_MASTER_KEY || 'streetphare-dev-key-CHANGE_ME_IN_PROD',
        ...extraEnv,
      },
      stdio: 'inherit',
    },
  );

  entry.child  = child;
  entry.status = 'online';
  writeDashboard();

  log(label, `Démarré (pid=${child.pid}) sur http://localhost:${port}`);

  child.on('exit', (code, signal) => {
    log(label, `Exited (code=${code}, signal=${signal})`);
    entry.status = 'crashed';
    entry.child  = null;
    writeDashboard();

    // Redémarrage automatique (si pas d'arrêt volontaire)
    if (code !== 0 && signal !== 'SIGINT' && signal !== 'SIGTERM') {
      if (entry.restarts < MAX_RESTARTS) {
        entry.restarts++;
        log(label, `Redémarrage automatique #${entry.restarts}/${MAX_RESTARTS} dans ${RESTART_DELAY}ms...`);
        setTimeout(() => startServer(key, script, port, extraEnv), RESTART_DELAY);
      } else {
        log(label, `❌ MAX_RESTARTS (${MAX_RESTARTS}) atteint. Pas de nouveau redémarrage.`);
        entry.status = 'stopped';
        writeDashboard();
      }
    } else {
      entry.status = 'stopped';
      writeDashboard();
    }
  });

  return child;
}

// ── Démarrage des deux serveurs ───────────────────────────────────────────

console.log('\n══════════════════════════════════════════════════════════');
console.log('  🚦 StreetPhare — Orchestrateur v2');
console.log('══════════════════════════════════════════════════════════');
console.log(`  Principal : http://localhost:${PORT_PRIMARY}`);
console.log(`  Backup    : http://localhost:${PORT_BACKUP}`);
console.log(`  Dashboard : ${STATUS_FILE}`);
console.log('══════════════════════════════════════════════════════════\n');

// Écrire une première version du dashboard avant le démarrage
writeDashboard();

// Démarrer le serveur principal
startServer('primary', 'server_primary_v2.js', PORT_PRIMARY, {
  NEXT_BACKUP_URL: `http://localhost:${PORT_BACKUP}`,
});

// Démarrer le serveur backup (avec 1s de délai pour laisser
// le principal s'initialiser avant le premier heartbeat)
setTimeout(() => {
  startServer('backup', 'server_secondary_v2.js', PORT_BACKUP, {
    NEXT_BACKUP_URL: `http://localhost:3002`,
    PRIMARY_URL:     `http://localhost:${PORT_PRIMARY}`,
    HB_INTERVAL_MS:  process.env.HB_INTERVAL_MS  || '5000',
    HB_FAIL_THRESHOLD: process.env.HB_FAIL_THRESHOLD || '3',
  });
}, 1000);

// ── Arrêt propre ──────────────────────────────────────────────────────────

function shutdown(signal) {
  console.log(`\n[orchestrator] Signal ${signal} reçu — arrêt des serveurs...`);

  state.primary.status = 'stopped';
  state.backup.status  = 'stopped';

  if (state.primary.child) state.primary.child.kill('SIGINT');
  if (state.backup.child)  state.backup.child.kill('SIGINT');

  writeDashboard();

  setTimeout(() => {
    console.log('[orchestrator] Arrêt complet.');
    process.exit(0);
  }, 800);
}

process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
