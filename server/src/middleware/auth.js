// server/src/middleware/auth.js
// Middleware d'authentification JWT + RBAC pour StreetPhare v3.1
//
// Protège les routes d'administration (/admin, /api/* sensibles) et
// le WebSocket d'administration (/admin-ws) contre les accès non autorisés.
//
// Architecture :
//   - authenticateToken : vérifie le JWT dans l'en-tête Authorization
//     ou dans le query param ?token= (pour WebSocket handshake).
//   - requireRole(['admin']) : valide que le rôle contenu dans le JWT
//     correspond au rôle requis.
//   - Le hash du mot de passe admin est stocké dans ADMIN_HASH (env).
//   - Le secret JWT est stocké dans JWT_SECRET (env).
//
// Les utilisateurs citoyens (anonymes, Ed25519) ne sont PAS affectés
// par ces middlewares : leurs routes (/api/alerts, /mesh, etc.) restent
// ouvertes à l'anonymat cryptographique structurel.

const jwt = require('jsonwebtoken');
const config = require('../config');

// ── Log helper formaté ──────────────────────────────────────────────────
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

// ═══════════════════════════════════════════════════════════════════════════
// MIDDLEWARE : Vérification du token JWT
// ═══════════════════════════════════════════════════════════════════════════

/// Extrait et vérifie un JWT depuis :
///   1. L'en-tête HTTP `Authorization: Bearer <token>`
///   2. Le query parameter `?token=<token>` (fallback WebSocket)
///
/// En cas de succès, injecte `req.user = { role, iat, exp }`.
/// En cas d'échec, répond 401 ou 403 avec un message explicite.
function authenticateToken(req, res, next) {
  let token = null;

  // 1. Extraction depuis l'en-tête Authorization (prioritaire).
  const authHeader = req.headers['authorization'];
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.slice(7);
  }

  // 2. Fallback depuis le query param (WebSocket handshake ou debug).
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

    // Vérification minimale de la structure du payload.
    if (!decoded || !decoded.role) {
      log('AUTH', `Token invalide (payload sans rôle) — ${req.method} ${req.originalUrl}`);
      return res.status(403).json({ error: 'Token invalide : rôle manquant' });
    }

    req.user = {
      role: decoded.role,
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
    if (err.name === 'JsonWebTokenError') {
      log('AUTH', `Token invalide (${err.message}) — ${req.method} ${req.originalUrl}`);
      return res.status(403).json({ error: 'Token invalide ou falsifié' });
    }
    log('AUTH', `Erreur vérification token : ${err.message}`);
    return res.status(500).json({ error: 'Erreur interne d\'authentification' });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIDDLEWARE : Validation de rôle (RBAC)
// ═══════════════════════════════════════════════════════════════════════════

/// Crée un middleware qui vérifie que l'utilisateur authentifié possède
/// au moins un des rôles requis.
///
/// Usage : `router.post('/admin/...', authenticateToken, requireRole(['admin']), handler)`
///
/// @param {string[]} allowedRoles — Liste des rôles autorisés (ex: ['admin'])
/// @returns {Function} Middleware Express
function requireRole(allowedRoles) {
  return (req, res, next) => {
    // Le middleware authenticateToken DOIT avoir été exécuté avant.
    if (!req.user) {
      log('AUTH', `requireRole appelé sans authenticateToken préalable`);
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

// ═══════════════════════════════════════════════════════════════════════════
// UTILITAIRE : Vérification de token pour WebSocket (handshake)
// ═══════════════════════════════════════════════════════════════════════════

/// Vérifie un token JWT extrait de l'URL de connexion WebSocket.
/// Retourne le payload décodé ou lève une exception.
///
/// Usage dans le callback `verifyClient` ou `upgrade` du WebSocket server.
///
/// @param {string} url — URL complète de la requête WebSocket
///   (ex: "wss://host:3000/admin-ws?token=eyJ...")
/// @returns {{ role: string, iat: number, exp: number }} Payload décodé
/// @throws {Error} Si le token est absent, invalide ou expiré
function verifyWsToken(url) {
  if (!url) {
    throw new Error('URL de connexion WebSocket manquante');
  }

  // Extraction du query param `?token=...`
  let token = null;
  try {
    const urlObj = new URL(url, 'https://localhost');
    token = urlObj.searchParams.get('token');
  } catch (_) {
    // Fallback : parsing manuel si URL relative
    const match = url.match(/[?&]token=([^&]+)/);
    if (match) {
      token = decodeURIComponent(match[1]);
    }
  }

  if (!token) {
    throw new Error('Token d\'authentification requis pour la connexion WebSocket admin');
  }

  const decoded = jwt.verify(token, config.jwtSecret, {
    algorithms: ['HS256'],
    maxAge: config.jwtExpiresIn || '8h',
  });

  if (!decoded || !decoded.role || decoded.role !== 'admin') {
    throw new Error('Token WebSocket invalide : rôle admin requis');
  }

  log('AUTH', `WebSocket admin autorisé — rôle=${decoded.role}`);
  return decoded;
}

module.exports = {
  authenticateToken,
  requireRole,
  verifyWsToken,
};