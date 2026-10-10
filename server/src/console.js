// server/src/console.js
//
// Handler des commandes de la console d'administration interactive.
// Reçoit une ligne de commande texte, l'exécute et retourne une réponse
// textuelle destinée au widget "console" du dashboard admin.

const store = require('./store');

// ── Aide ─────────────────────────────────────────────────────────────────
const HELP = [
  'Commandes disponibles :',
  '  help                    → affiche cette aide',
  '  status                  → état du serveur (connexions, alertes…)',
  '  alerts [active]         → liste les signalements (actifs si "active")',
  '  connections             → liste des connexions actives (mesh/admin)',
  '  broadcast <message>     → diffuse une alerte globale à tous les admins',
  '  purge [heures]          → purge les signalements plus vieux que N h (défaut 24)',
  '  ban <uuid>              → bannit un émetteur (modération tchat)',
  '  unban <uuid>            → lève le bannissement d\'un émetteur',
  '  bans                    → liste des émetteurs bannis',
  '  zones                   → liste des zones de géorepérage',
  '  moderators              → liste des comptes modérateurs',
].join('\n');

const moderators = require('./services/moderators');

/// Exécute une commande et retourne la réponse texte.
/// [broadcastFn] permet de diffuser un événement à tous les admins connectés.
function executeCommand(rawLine, { broadcastFn } = {}) {
  const line = String(rawLine || '').trim();
  if (!line) return '';

  const [cmd, ...rest] = line.split(/\s+/);
  const args = rest.join(' ').trim();

  switch (cmd.toLowerCase()) {
    case 'help':
      return HELP;

    case 'status':
      return JSON.stringify(store.getConnectionsInfo(), null, 2);

    case 'alerts': {
      const activeOnly = args === 'active';
      const list = activeOnly ? store.getActiveAlerts() : store.getAllAlerts();
      if (list.length === 0) return activeOnly ? 'Aucun signalement actif.' : 'Aucun signalement.';
      const tail = list.slice(-30);
      return tail.map(a =>
        `  ${a.id} | ${a.type} | ${a.status} | votes=${(a.votes || []).length} | (${a.lat},${a.lng})`
      ).join('\n') + (list.length > tail.length ? `\n  … et ${list.length - tail.length} de plus` : '');
    }

    case 'connections': {
      const info = store.getConnectionsInfo();
      return `Mesh: ${info.meshClients} client(s) | Admin: ${info.adminClients} client(s) | Alertes: ${info.alertsActive}/${info.alertsTotal} actives | Événements: ${info.events}`;
    }

    case 'broadcast': {
      if (!args) return 'Usage : broadcast <message>';
      if (broadcastFn) broadcastFn('global_alert', { message: args, from: 'console' });
      return `✅ Alerte globale diffusée : "${args}"`;
    }

    case 'purge': {
      const hours = parseInt(args, 10) || 24;
      const removed = store.purgeOldAlerts(hours);
      return `✅ ${removed} signalement(s) purgé(s) (> ${hours} h).`;
    }

    case 'ban': {
      if (!args) return 'Usage : ban <uuid>';
      store.banUser(args);
      return `✅ UUID banni : ${args}`;
    }

    case 'unban': {
      if (!args) return 'Usage : unban <uuid>';
      return store.unbanUser(args) ? `✅ UUID débanni : ${args}` : `⚠ UUID non banni : ${args}`;
    }

    case 'bans': {
      const bans = store.getBannedUsers();
      return bans.length ? bans.map(u => `  ${u}`).join('\n') : 'Aucun émetteur banni.';
    }

    case 'zones': {
      const zones = store.getGeofencingZones();
      return zones.length
        ? zones.map(z => `  ${z.id} | ${z.type} | ${z.name} | (${z.lat},${z.lng}) r=${z.radiusMeters}m`).join('\n')
        : 'Aucune zone de géorepérage.';
    }

    case 'moderators': {
      const list = moderators.list();
      return list.length
        ? list.map(m => `  ${m.username} | perms: ${(m.permissions || []).join(',') || 'aucune'}`).join('\n')
        : 'Aucun modérateur.';
    }

    default:
      return `Commande inconnue : "${cmd}". Tapez "help" pour la liste.`;
  }
}

module.exports = { executeCommand, HELP };
