// server/src/services/moderators.js
//
// Service de gestion des comptes modérateurs.
//
// Les modérateurs sont des comptes secondaires gérables EXCLUSIVEMENT par
// l'administrateur principal (login via ADMIN_USERNAME / ADMIN_HASH).
// Chaque modérateur dispose de permissions granulaires (RBAC).

const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

const MODERATORS_PATH = path.join(__dirname, '..', '..', 'data', 'moderators.json');

// Permissions granulaires disponibles.
const PERMISSIONS = [
  'chatModerate',      // modérer le tchat P2P / relais (suppression, ban)
  'reportValidate',    // valider / rejeter / supprimer des signalements
  'consoleAccess',     // accès à la console d'administration
  'manageGeofencing',  // gérer les zones de géorepérage
  'manageEvents',      // gérer les événements et leurs points (trajet, POI, soins…)
  'manageModerators',  // gérer les comptes modérateurs (réservé main admin)
  'simulateAccess',    // accès au panneau de test & simulation
];

const log = (category, message) => {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${ts}] [${category}] ${message}`);
};

class ModeratorService {
  constructor() {
    this.moderators = [];
    this._load();
  }

  // ── Persistance ─────────────────────────────────────────────────────────
  _load() {
    try {
      if (!fs.existsSync(MODERATORS_PATH)) { this._save(); return; }
      const raw = fs.readFileSync(MODERATORS_PATH, 'utf-8');
      const data = JSON.parse(raw);
      this.moderators = Array.isArray(data) ? data : [];
      log('MODERATORS', `Chargés : ${this.moderators.length} modérateur(s)`);
    } catch (err) {
      log('MODERATORS', `⚠ Erreur chargement : ${err.message}`);
      this.moderators = [];
    }
  }

  _save() {
    try {
      const dir = path.dirname(MODERATORS_PATH);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(MODERATORS_PATH, JSON.stringify(this.moderators, null, 2), 'utf-8');
    } catch (err) {
      log('MODERATORS', `⚠ Erreur sauvegarde : ${err.message}`);
    }
  }

  // ── Sanitisation (ne jamais exposer le hash de mot de passe) ────────────
  _public(mod) {
    const { passwordHash, ...rest } = mod;
    return rest;
  }

  // ── CRUD ────────────────────────────────────────────────────────────────
  list() {
    return this.moderators.map(m => this._public(m));
  }

  getByUsername(username) {
    return this.moderators.find(m => m.username === username) || null;
  }

  async create(username, password, permissions = []) {
    if (!username || !password) return { error: 'username et password requis' };
    if (this.getByUsername(username)) return { error: 'Nom d\'utilisateur déjà utilisé' };

    const passwordHash = await bcrypt.hash(password, 12);
    const mod = {
      id: uuidv4(),
      username,
      passwordHash,
      permissions: (permissions || []).filter(p => PERMISSIONS.includes(p)),
      createdAt: new Date().toISOString(),
    };
    this.moderators.push(mod);
    this._save();
    log('MODERATORS', `Créé : ${username} (perms: ${mod.permissions.join(',') || 'aucune'})`);
    return { mod: this._public(mod) };
  }

  async update(id, { password, permissions } = {}) {
    const mod = this.moderators.find(m => m.id === id);
    if (!mod) return { error: 'Modérateur non trouvé' };
    if (password) mod.passwordHash = await bcrypt.hash(password, 12);
    if (Array.isArray(permissions)) mod.permissions = permissions.filter(p => PERMISSIONS.includes(p));
    mod.updatedAt = new Date().toISOString();
    this._save();
    return { mod: this._public(mod) };
  }

  remove(id) {
    const idx = this.moderators.findIndex(m => m.id === id);
    if (idx === -1) return false;
    this.moderators.splice(idx, 1);
    this._save();
    return true;
  }

  // ── Authentification d'un modérateur ────────────────────────────────────
  async verify(username, password) {
    const mod = this.getByUsername(username);
    if (!mod) return null;
    const ok = await bcrypt.compare(password, mod.passwordHash);
    return ok ? mod : null;
  }
}

module.exports = new ModeratorService();
module.exports.PERMISSIONS = PERMISSIONS;
