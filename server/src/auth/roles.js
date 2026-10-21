// server/src/auth/roles.js
//
// Définition de la hiérarchie des rôles et des permissions pour StreetPhare.
//
// Rôles supportés :
//   - superadmin  : Admin Principal. Exclusivité absolue sur la création/gestion
//                   des autres comptes admins, modérateurs et éclaireurs.
//   - admin       : Administrateur principal (compte unique, ADMIN_HASH). Gardé
//                   pour rétrocompatibilité avec le login existant.
//   - event_admin : Admin d'Événement. Droits d'édition/modération cantonnés
//                   à ses propres événements, points d'événements et signalements
//                   associés.
//   - scout       : Éclaireur (Trusted User). Signalements validés instantanément
//                   (bypass consensus 3 votes). Option de suppression directe des
//                   faux signalements constatés.
//   - moderator   : Modérateur secondaire (permissions granulaires existantes).
//   - user        : Utilisateur citoyen standard (aucune permission admin).

// ════════════════════════════════════════════════════════════════════════════════
// 1. HIÉRARCHIE DES RÔLES (poids numérique, plus élevé = plus privilégié)
// ════════════════════════════════════════════════════════════════════════════════

const ROLE_WEIGHTS = {
  superadmin: 100,
  admin: 90,
  event_admin: 60,
  moderator: 50,
  scout: 30,
  user: 10,
};

/// Retourne le poids numérique d'un rôle (0 si inconnu).
function roleWeight(role) {
  return ROLE_WEIGHTS[role] || 0;
}

/// Vérifie si `userRole` a un poids >= `minRole`.
function roleGte(userRole, minRole) {
  return roleWeight(userRole) >= roleWeight(minRole);
}

// ════════════════════════════════════════════════════════════════════════════════
// 2. QUI PEUT GÉRER QUEL RÔLE (règle : on ne peut gérer que des rôles de poids
//    strictement inférieur au sien, sauf superadmin qui gère tout)
// ════════════════════════════════════════════════════════════════════════════════

// Matrice : [rôle gestionnaire] => [rôles gérables]
const ROLE_MANAGEMENT_MATRIX = {
  superadmin: ['admin', 'event_admin', 'moderator', 'scout'],
  admin: ['event_admin', 'moderator', 'scout'], // Le compte admin principal (ADMIN_HASH) agit comme Superadmin
  event_admin: [], // Les admins d'événement ne créent pas d'autres comptes
  moderator: [],
  scout: [],
  user: [],
};

/// Vérifie si `managerRole` est autorisé à créer/gérer un compte de `targetRole`.
function canManageRole(managerRole, targetRole) {
  if (!managerRole || !targetRole) return false;
  // Superadmin peut tout gérer.
  if (managerRole === 'superadmin') return true;
  const manageable = ROLE_MANAGEMENT_MATRIX[managerRole] || [];
  return manageable.includes(targetRole);
}

// ════════════════════════════════════════════════════════════════════════════════
// 3. PERMISSIONS GRANULAIRES PAR RÔLE (permissions par défaut)
// ════════════════════════════════════════════════════════════════════════════════

// Toutes les permissions connues du système.
const ALL_PERMISSIONS = [
  'chatModerate',        // modérer le tchat P2P / relais (suppression, ban)
  'reportValidate',      // valider / rejeter / supprimer des signalements
  'consoleAccess',       // accès à la console d'administration
  'manageGeofencing',    // gérer les zones de géorepérage
  'manageEvents',        // gérer les événements et leurs points
  'manageModerators',    // gérer les comptes modérateurs (réservé superadmin)
  'simulateAccess',      // accès au panneau de test & simulation
  'scoutValidate',       // validation instantanée des signalements éclaireur
  'scoutVoid',           // suppression directe de faux signalements (éclaireur)
  'manageScouts',        // gestion des éclaireurs (réservé superadmin)
  'manageEventAdmins',   // gestion des admins d'événements (réservé superadmin)
];

// Permissions par défaut assignées à chaque rôle.
const DEFAULT_PERMISSIONS_BY_ROLE = {
  superadmin: [...ALL_PERMISSIONS],
  admin: [...ALL_PERMISSIONS],
  event_admin: ['manageEvents', 'reportValidate'],
  moderator: [], // permissions assignées individuellement à la création
  scout: ['scoutValidate', 'scoutVoid'],
  user: [],
};

/// Retourne les permissions par défaut pour un rôle donné.
function defaultPermissions(role) {
  return (DEFAULT_PERMISSIONS_BY_ROLE[role] || []).slice();
}

// ════════════════════════════════════════════════════════════════════════════════
// 4. EXPORTS
// ════════════════════════════════════════════════════════════════════════════════

module.exports = {
  ROLES: Object.keys(ROLE_WEIGHTS),
  ROLE_WEIGHTS,
  roleWeight,
  roleGte,
  canManageRole,
  ALL_PERMISSIONS,
  defaultPermissions,
  DEFAULT_PERMISSIONS_BY_ROLE,
  // Rôles spécifiques pour commodité
  ROLE_SUPERADMIN: 'superadmin',
  ROLE_ADMIN: 'admin',
  ROLE_EVENT_ADMIN: 'event_admin',
  ROLE_SCOUT: 'scout',
  ROLE_MODERATOR: 'moderator',
  ROLE_USER: 'user',
};
