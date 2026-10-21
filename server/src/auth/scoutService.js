// server/src/auth/scoutService.js
//
// Service de gestion des éclaireurs (Trusted Users).
//
// Les éclaireurs sont des utilisateurs de confiance sur le terrain.
// Privilèges :
//   - Leurs signalements sont validés instantanément (bypass des 3 votes).
//   - Ils disposent d'une option dédiée pour supprimer directement les faux
//     signalements constatés.
//
// Persistance : fichier data/scouts.json

const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { ROLE_SCOUT, defaultPermissions } = require('./roles');

const SCOUTS_PATH = path.join(__dirname, '..', '..', 'data', 'scouts.json');

const log = (category, message) => {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${ts}] [${category}] ${message}`);
};

class ScoutService {
  constructor() {
    this.scouts = [];
    this._load();
  }

  // ── Persistance ─────────────────────────────────────────────────────────
  _load() {
    try {
      if (!fs.existsSync(SCOUTS_PATH)) { this._save(); return; }
      const raw = fs.readFileSync(SCOUTS_PATH, 'utf-8');
      const data = JSON.parse(raw);
      this.scouts = Array.isArray(data) ? data : [];
      log('SCOUTS', `Chargés : ${this.scouts.length} éclaireur(s)`);
    } catch (err) {
      log('SCOUTS', `⚠ Erreur chargement : ${err.message}`);
      this.scouts = [];
    }
  }

  _save() {
    try {
      const dir = path.dirname(SCOUTS_PATH);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(SCOUTS_PATH, JSON.stringify(this.scouts, null, 2), 'utf-8');
    } catch (err) {
      log('SCOUTS', `⚠ Erreur sauvegarde : ${err.message}`);
    }
  }

  // ── Sanitisation ────────────────────────────────────────────────────────
  _public(scout) {
    return {
      id: scout.id,
      username: scout.username,
      displayName: scout.displayName || scout.username,
      role: scout.role,
      permissions: scout.permissions || [],
      createdAt: scout.createdAt,
      updatedAt: scout.updatedAt,
    };
  }

  // ── CRUD ────────────────────────────────────────────────────────────────
  list() {
    return this.scouts.map(s => this._public(s));
  }

  getById(id) {
    return this.scouts.find(s => s.id === id) || null;
  }

  getByUsername(username) {
    return this.scouts.find(s => s.username === username) || null;
  }

  isScout(userId) {
    return this.scouts.some(s => s.id === userId || s.username === userId);
  }

  async create(username, { displayName, permissions, password } = {}) {
    if (!username) return { error: 'username requis' };
    if (this.getByUsername(username)) return { error: 'Nom d\'utilisateur déjà utilisé' };

    let passwordHash = null;
    if (password) {
      passwordHash = await bcrypt.hash(password, 12);
    }

    const scout = {
      id: uuidv4(),
      username,
      displayName: displayName || username,
      role: ROLE_SCOUT,
      passwordHash,
      permissions: Array.isArray(permissions)
        ? permissions.filter(p => defaultPermissions(ROLE_SCOUT).includes(p))
        : defaultPermissions(ROLE_SCOUT),
      createdAt: new Date().toISOString(),
    };
    this.scouts.push(scout);
    this._save();
    log('SCOUTS', `Éclaireur créé : ${username}`);
    return { scout: this._public(scout) };
  }

  /// Vérifie les identifiants d'un éclaireur (username + password).
  /// Retourne l'objet éclaireur public en cas de succès, null sinon.
  async verify(username, password) {
    const scout = this.getByUsername(username);
    if (!scout || !scout.passwordHash) return null;
    const ok = await bcrypt.compare(password, scout.passwordHash);
    return ok ? this._public(scout) : null;
  }

  async update(id, { displayName, permissions } = {}) {
    const scout = this.scouts.find(s => s.id === id);
    if (!scout) return { error: 'Éclaireur non trouvé' };
    if (displayName !== undefined) scout.displayName = displayName;
    if (Array.isArray(permissions)) {
      scout.permissions = permissions.filter(p => defaultPermissions(ROLE_SCOUT).includes(p));
    }
    scout.updatedAt = new Date().toISOString();
    this._save();
    return { scout: this._public(scout) };
  }

  remove(id) {
    const idx = this.scouts.findIndex(s => s.id === id);
    if (idx === -1) return false;
    this.scouts.splice(idx, 1);
    this._save();
    log('SCOUTS', `Éclaireur supprimé (id=${id})`);
    return true;
  }
}

module.exports = new ScoutService();
