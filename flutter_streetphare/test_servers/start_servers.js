// test_servers/start_servers.js
//
// Orchestrateur : lance les deux serveurs Node.js (principal +
// secondaire) en parallèle dans le même process Node. Très utile
// pour `npm start` ou un double-clic.
//
// En Windows, on préférera `start_tests.bat` (lance 2 terminaux
// séparés, plus lisible), mais ce script est l'alternative
// multiplateforme (Linux/macOS/WSL).

const { spawn } = require('child_process');
const path = require('path');

function start(label, script, port, nextBackup) {
  const child = spawn(process.execPath, [path.join(__dirname, script)], {
    env: {
      ...process.env,
      PORT: String(port),
      ROLE: label,
      NEXT_BACKUP_URL: nextBackup || '',
      STREETPHARE_MASTER_KEY:
        process.env.STREETPHARE_MASTER_KEY ||
        'streetphare-dev-key-CHANGE_ME_IN_PROD',
    },
    stdio: 'inherit',
  });
  child.on('exit', (code) => {
    console.log(`[orchestrator] ${label} (port ${port}) exited with code ${code}`);
  });
  return child;
}

const primary = start('primary', 'server_primary.js', 3000, 'http://localhost:3001');
const secondary = start(
  'secondary',
  'server_secondary.js',
  3001,
  process.env.TERTIARY_URL || 'http://localhost:3002',
);

function shutdown() {
  console.log('\n[orchestrator] arrêt des serveurs...');
  primary.kill('SIGINT');
  secondary.kill('SIGINT');
  setTimeout(() => process.exit(0), 500);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
