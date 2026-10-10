// server/src/services/broadcast.js
//
// Diffusion temps réel vers les clients WebSocket d'administration.
// Le broadcaster est configuré par primary.js (qui possède adminWss).

let adminBroadcaster = () => {};

/// Configure la fonction de diffusion (appelée par primary.js).
function setAdminBroadcaster(fn) {
  adminBroadcaster = fn;
}

/// Diffuse un événement à tous les admins connectés.
/// [type] : 'new_alert', 'report_updated', 'chat_message', 'panic', 'global_alert', etc.
function broadcast(type, payload = {}) {
  try { adminBroadcaster(type, payload); } catch (_) {}
}

module.exports = { setAdminBroadcaster, broadcast };
