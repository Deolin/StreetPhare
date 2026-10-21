// server/src/middleware/auth.js
// Middleware d'authentification JWT + RBAC pour StreetPhare v3.1
//
// Ce module réexporte le système RBAC unifié depuis src/auth/rbac.js
// tout en conservant la rétrocompatibilité avec les anciennes signatures.
//
// Rôles supportés :
//   - superadmin : Admin Principal (exclusivité absolue)
//   - admin      : Administrateur principal (compte unique ADMIN_HASH)
//   - event_admin: Admin d'Événement (droits cantonnés à ses événements)
//   - scout      : Éclaireur (validation instantanée, suppression faux signalements)
//   - moderator  : Modérateur secondaire (permissions granulaires)
//   - user       : Utilisateur citoyen standard

const rbac = require('../auth/rbac');

// Réexport de toutes les fonctions RBAC (rétrocompatibilité préservée).
module.exports = {
  authenticateToken: rbac.authenticateToken,
  requireRole: rbac.requireRole,
  requirePermission: rbac.requirePermission,
  verifyWsToken: rbac.verifyWsToken,

  // Nouveaux middlewares RBAC
  requireMinRole: rbac.requireMinRole,
  requireSuperAdmin: rbac.requireSuperAdmin,
  requireEventAdmin: rbac.requireEventAdmin,
  requireScout: rbac.requireScout,
  canManageRoleMiddleware: rbac.canManageRoleMiddleware,
  canManageRole: rbac.canManageRole,

  // Constantes de rôles
  ROLE_SUPERADMIN: rbac.ROLE_SUPERADMIN,
  ROLE_ADMIN: rbac.ROLE_ADMIN,
  ROLE_EVENT_ADMIN: rbac.ROLE_EVENT_ADMIN,
  ROLE_SCOUT: rbac.ROLE_SCOUT,
  ROLE_MODERATOR: rbac.ROLE_MODERATOR,
  ROLE_USER: rbac.ROLE_USER,
};
