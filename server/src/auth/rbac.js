// server/src/auth/rbac.js
//
// Middleware RBAC (Role-Based Access Control) pour StreetPhare.
//
// Intègre la hiérarchie des rôles définie dans roles.js :
//   - superadmin : Admin Principal, exclusivité absolue
//   - admin      : Administrateur principal (compte unique ADMIN_HASH)
//   - event_admin: Admin d'Événement (droits cantonnés à ses événements)
//   - scout      : Éclaireur (validation instantanée, suppression faux signalements)
//   - moderator  : Modérateur secondaire (permissions granulaires)
//   - user       : Utilisateur citoyen standard

const jwt = require('jsonwebtoken');
const config = require('../config');
const {
  ROLE_SUPERADMIN,
  ROLE_ADMIN,
  ROLE_EVENT_ADMIN,
  ROLE_SCOUT,
  ROLE_MODERATOR,
  ROLE_USER,
  roleGte,
  canManageRole,
} = require('./roles');

const log = (category, message) => {
  const now = new Date();
  const ts = [
    String(now.getHours()).padStart(2, '0'),
    String(now.getMinutes()).padStart(2, '0'),
    String(now.getSeconds()).padStart(2, '0'),
    ' - ',
    String(now.getDate()).padStart(2, '0'),
    '/',
    String(now.getMonth() + 1).padStart(2, '0'),
  ].join('');
  console.log(`[${ts}] - [${category}] ${message}`);
};

// ════════════════════════════════════════════════════════════════════════════════
// authenticateToken
// ════════════════════════════════════════════════════════════════════════════════

function authenticateToken(req, res, next) {
  let token = null;

  const authHeader = req.headers['authorization'];
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.slice(7);
  }

  if (!token && req.query && req.query.token) {
    token = req.query.token;
  }

  if (!token) {
    log('AUTH', `Tentative d'accès sans token — ${req.method} ${req.originalUrl} — IP: ${req.ip}`);
    return res.status(401).json({ error: 'Accès refusé : token d\'authentification requis' });
  }

  try {
    const decoded = jwt.verify(token, config.jwtSecret, {
      algorithms: ['HS256'],
      maxAge: config.jwtExpiresIn || '8h',
    });

    if (!decoded || !decoded.role) {
      log('AUTH', `Token invalide (payload sans rôle) — ${req.method} ${req.originalUrl}`);
      return res.status(403).json({ error: 'Token invalide : rôle manquant' });
    }

    req.user = {
      role: decoded.role,
      username: decoded.username,
      permissions: Array.isArray(decoded.permissions) ? decoded.permissions : [],
      managedEventCodes: Array.isArray(decoded.managedEventCodes) ? decoded.managedEventCodes : [],
      iat: decoded.iat,
      exp: decoded.exp,
    };

    log('AUTH', `Accès autorisé — rôle=${decoded.role} — ${req.method} ${req.originalUrl}`);
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      log('AUTH', `Token expiré — ${req.method} ${req.originalUrl}`);
      return res.status(401).json({ error: 'Token expiré, veuillez vous reconnecter' });
    }
    log('AUTH', `Token invalide — ${err.message} — ${req.method} ${req.originalUrl}`);
    return res.status(403).json({ error: 'Token invalide' });
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// requireRole
// ════════════════════════════════════════════════════════════════════════════════

/// Vérifie que l'utilisateur possède l'un des rôles requis.
/// Usage : `router.post('/...', authenticateToken, requireRole(['superadmin', 'admin']), handler)`
function requireRole(allowedRoles) {
  return (req, res, next) => {
    if (!req.user) {
      log('AUTH', 'requireRole appelé sans authenticateToken préalable');
      return res.status(500).json({ error: 'Erreur de configuration du serveur' });
    }

    if (!allowedRoles.includes(req.user.role)) {
      log('AUTH', `Rôle insuffisant — requis=${allowedRoles.join(',')} — actuel=${req.user.role}`);
      return res.status(403).json({
        error: `Droits insuffisants. Rôle(s) requis : ${allowedRoles.join(', ')}`,
      });
    }

    next();
  };
}

/// Vérifie que l'utilisateur a un rôle dont le poids est >= au rôle minimum requis.
/// Usage : `requireMinRole('event_admin')` autorise superadmin, admin, event_admin.
function requireMinRole(minRole) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(500).json({ error: 'Erreur de configuration du serveur' });
    }

    if (!roleGte(req.user.role, minRole)) {
      log('AUTH', `Rôle insuffisant — minimum requis=${minRole} — actuel=${req.user.role}`);
      return res.status(403).json({
        error: `Droits insuffisants. Rôle minimum requis : ${minRole}`,
      });
    }

    next();
  };
}

/// Vérifie que l'utilisateur possède une permission granulaire donnée.
/// Le superadmin et l'admin ont toutes les permissions automatiquement.
function requirePermission(permission) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(500).json({ error: 'Erreur de configuration du serveur' });
    }

    if (req.user.role === ROLE_SUPERADMIN || req.user.role === ROLE_ADMIN) {
      return next();
    }

    if (Array.isArray(req.user.permissions) && req.user.permissions.includes(permission)) {
      return next();
    }

    return res.status(403).json({ error: `Permission requise : ${permission}` });
  };
}

// ════════════════════════════════════════════════════════════════════════════════
// Rôles spécifiques
// ════════════════════════════════════════════════════════════════════════════════

function requireSuperAdmin(req, res, next) {
  if (!req.user) {
    return res.status(500).json({ error: 'Erreur de configuration du serveur' });
  }
  if (req.user.role !== ROLE_SUPERADMIN && req.user.role !== ROLE_ADMIN) {
    log('AUTH', `Accès refusé (superadmin requis) — rôle=${req.user.role}`);
    return res.status(403).json({ error: 'Réservé à l\'Administrateur Principal (Superadmin)' });
  }
  next();
}

function requireEventAdmin(req, res, next) {
  if (!req.user) {
    return res.status(500).json({ error: 'Erreur de configuration du serveur' });
  }
  if (!roleGte(req.user.role, ROLE_EVENT_ADMIN)) {
    log('AUTH', `Accès refusé (event_admin requis) — rôle=${req.user.role}`);
    return res.status(403).json({ error: 'Réservé aux administrateurs d\'événements et supérieurs' });
  }
  next();
}

function requireScout(req, res, next) {
  if (!req.user) {
    return res.status(500).json({ error: 'Erreur de configuration du serveur' });
  }
  if (!roleGte(req.user.role, ROLE_SCOUT)) {
    log('AUTH', `Accès refusé (scout requis) — rôle=${req.user.role}`);
    return res.status(403).json({ error: 'Réservé aux éclaireurs et supérieurs' });
  }
  next();
}

function canManageRoleMiddleware(targetRole) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(500).json({ error: 'Erreur de configuration du serveur' });
    }
    if (!canManageRole(req.user.role, targetRole)) {
      log('AUTH', `Gestion de rôle refusée — gestionnaire=${req.user.role} — cible=${targetRole}`);
      return res.status(403).json({
        error: `Vous n'êtes pas autorisé à gérer des comptes de rôle "${targetRole}"`,
      });
    }
    next();
  };
}

// ════════════════════════════════════════════════════════════════════════════════
// WebSocket token verification
// ════════════════════════════════════════════════════════════════════════════════

function verifyWsToken(url) {
  if (!url) {
    throw new Error('URL de connexion WebSocket manquante');
  }

  let token = null;
  try {
    const urlObj = new URL(url, 'https://localhost');
    token = urlObj.searchParams.get('token');
  } catch (_) {
    const match = url.match(/[?&]token=([^&]+)/);
    if (match) token = decodeURIComponent(match[1]);
  }

  if (!token) {
    throw new Error('Token d\'authentification requis pour la connexion WebSocket admin');
  }

  const decoded = jwt.verify(token, config.jwtSecret, {
    algorithms: ['HS256'],
    maxAge: config.jwtExpiresIn || '8h',
  });

  if (!decoded || !decoded.role) {
    throw new Error('Token WebSocket invalide : rôle manquant');
  }

  const wsAuthorizedRoles = [ROLE_SUPERADMIN, ROLE_ADMIN, ROLE_EVENT_ADMIN, ROLE_MODERATOR, ROLE_SCOUT];
  if (!wsAuthorizedRoles.includes(decoded.role)) {
    throw new Error('Token WebSocket invalide : rôle non autorisé');
  }

  log('AUTH', `WebSocket admin autorisé — rôle=${decoded.role}`);
  return decoded;
}

module.exports = {
  authenticateToken,
  requireRole,
  requireMinRole,
  requirePermission,
  requireSuperAdmin,
  requireEventAdmin,
  requireScout,
  canManageRoleMiddleware,
  canManageRole,
  verifyWsToken,
  ROLE_SUPERADMIN,
  ROLE_ADMIN,
  ROLE_EVENT_ADMIN,
  ROLE_SCOUT,
  ROLE_MODERATOR,
  ROLE_USER,
};

