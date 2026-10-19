// server/_test_broadcast.js
// Test end-to-end du broadcast serveur -> client mesh.
// Se connecte au serveur deja en cours (127.0.0.1:3000) :
//   1. Ouvre un client ws sur /mesh
//   2. POST /api/alerts (signalement citoyen, sans auth)
//   3. Verifie que le client mesh recoit { kind: 'new_alert', alert }

const WebSocket = require('ws');
const http = require('http');

const HOST = '127.0.0.1';
const PORT = 3000;

function postJson(p, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = http.request({
      host: HOST,
      port: PORT,
      path: p,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
    }, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => resolve({ status: res.statusCode, body: buf }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  const received = [];
  const ws = new WebSocket(`ws://${HOST}:${PORT}/mesh`);

  ws.on('message', (data) => {
    const s = data.toString();
    received.push(s);
    console.log('[WS-CLIENT] <- ' + s.substring(0, 300));
  });

  await new Promise((resolve, reject) => {
    ws.on('open', resolve);
    ws.on('error', reject);
  });
  console.log('[WS-CLIENT] connecte sur /mesh');

  // Attendre le welcome eventuel
  await new Promise((r) => setTimeout(r, 500));

  const res = await postJson('/api/sync-push', {
    alerts: [{
      id: 'TEST_' + Date.now(),
      type: 'police',
      lat: 50.4762,
      lng: 4.5422,
      description: 'TEST_BROADCAST',
      votes: [],
      status: 'active',
    }],
    peerId: 'test-peer',
    since: '',
  });
  console.log('[TEST] POST /api/sync-push -> HTTP', res.status, res.body.substring(0, 300));

  // Laisser le temps au broadcast d'arriver
  await new Promise((r) => setTimeout(r, 1500));

  const kinds = received
    .map((s) => { try { return JSON.parse(s).kind; } catch (_) { return '?'; } });
  console.log('[TEST] kinds recus:', JSON.stringify(kinds));

  const hasNewAlert = received.some((s) => s.includes('new_alert'));
  console.log('[TEST] new_alert recu par le client mesh :', hasNewAlert);

  ws.close();
  process.exit(hasNewAlert ? 0 : 1);
}

main().catch((e) => { console.error('[TEST] ERREUR', e.message); process.exit(2); });
