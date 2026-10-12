// server/src/services/broadcast.js
//
// Diffusion temps réel vers les clients WebSocket :
//   - clients d'administration (adminWss) — format `{ type, ...payload }`
//   - clients mesh / mobiles (wss)        — format `{ kind, ...payload }`
//
// Les diffuseurs sont configurés par primary.js / backup.js (qui possèdent
// les instances WebSocketServer).

let adminBroadcaster = () => {};
let meshBroadcaster = () => {};

/// Configure la fonction de diffusion admin (appelée par primary.js/backup.js).
function setAdminBroadcaster(fn) {
  adminBroadcaster = fn;
}

/// Configure la fonction de diffusion mesh/mobile (appelée par primary.js/backup.js).
function setMeshBroadcaster(fn) {
  meshBroadcaster = fn;
}

/// Diffuse un événement aux clients d'administration uniquement.
/// [type] : 'new_alert', 'report_updated', 'chat_message', 'panic', etc.
function broadcast(type, payload = {}) {
  try { adminBroadcaster(type, payload); } catch (_) {}
}

/// Diffuse un événement aux clients mesh/mobiles uniquement.
function broadcastToMesh(type, payload = {}) {
  try { meshBroadcaster(type, payload); } catch (_) {}
}

/// Diffuse un événement à TOUS les clients connectés (admin + mesh).
/// À utiliser pour les événements transverses (ex: signalement validé).
function broadcastToAll(type, payload = {}) {
  try { adminBroadcaster(type, payload); } catch (_) {}
  try { meshBroadcaster(type, payload); } catch (_) {}
}

module.exports = {
  setAdminBroadcaster,
  setMeshBroadcaster,
  broadcast,
  broadcastToMesh,
  broadcastToAll,
};

