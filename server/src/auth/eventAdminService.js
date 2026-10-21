// server/src/auth/eventAdminService.js
//
// Service de gestion des administrateurs d'événements.
//
// Un admin d'événement dispose de droits d'édition/modération strictement
// cantonnés à ses propres événements, points d'événements et signalements
// associés.
//
// Persistance : fichier data/eventAdmins.json

const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { ROLE_EVENT_ADMIN, defaultPermissions } = require('./roles');

const EVENT_ADMINS_PATH = path.join(__dirname, '..', '..', 'data', 'eventAdmins.json');

const log = (category, message) => {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${ts}] [${category}] ${message}`);
};

class EventAdminService {
  constructor() {
    this.admins = [];
    this._load();
  }

  // ── Persistance ─────────────────────────────────────────────────────────
  _load() {
    try {
      if (!fs.existsSync(EVENT_ADMINS_PATH)) { this._save(); return; }
      const raw = fs.readFileSync(EVENT_ADMINS_PATH, 'utf-8');
      const data = JSON.parse(raw);
      this.admins = Array.isArray(data) ? data : [];
      log('EVENT_ADMINS', `Chargés : ${this.admins.length} admin(s) d'événement`);
    } catch (err) {
      log('EVENT_ADMINS', `⚠ Erreur chargement : ${err.message}`);
      this.admins = [];
    }
  }

  _save() {
    try {
      const dir = path.dirname(EVENT_ADMINS_PATH);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(EVENT_ADMINS_PATH, JSON.stringify(this.admins, null, 2), 'utf-8');
    } catch (err) {
      log('EVENT_ADMINS', `⚠ Erreur sauvegarde : ${err.message}`);
    }
  }

  // ── Sanitisation ────────────────────────────────────────────────────────
  _public(admin) {
    return {
      id: admin.id,
      username: admin.username,
      displayName: admin.displayName || admin.username,
      role: admin.role,
      permissions: admin.permissions || [],
      managedEventCodes: admin.managedEventCodes || [],
      createdAt: admin.createdAt,
      updatedAt: admin.updatedAt,
    };
  }

  // ── CRUD ────────────────────────────────────────────────────────────────
  list() {
    return this.admins.map(a => this._public(a));
  }

  getById(id) {
    return this.admins.find(a => a.id === id) || null;
  }

  getByUsername(username) {
    return this.admins.find(a => a.username === username) || null;
  }

  /// Retourne les admins d'un événement donné (par code).
  getByEventCode(eventCode) {
    return this.admins.filter(a => (a.managedEventCodes || []).includes(eventCode));
  }

  /// Vérifie si un admin peut gérer un événement donné.
  canManageEvent(adminId, eventCode) {
    const admin = this.getById(adminId);
    if (!admin) return false;
    return (admin.managedEventCodes || []).includes(eventCode);
  }

  async create(username, { displayName, permissions, managedEventCodes, password } = {}) {
    if (!username) return { error: 'username requis' };
    if (this.getByUsername(username)) return { error: 'Nom d\'utilisateur déjà utilisé' };

    let passwordHash = null;
    if (password) {
      passwordHash = await bcrypt.hash(password, 12);
    }

    const admin = {
      id: uuidv4(),
      username,
      displayName: displayName || username,
      role: ROLE_EVENT_ADMIN,
      passwordHash,
      permissions: Array.isArray(permissions)
        ? permissions.filter(p => defaultPermissions(ROLE_EVENT_ADMIN).includes(p))
        : defaultPermissions(ROLE_EVENT_ADMIN),
      managedEventCodes: Array.isArray(managedEventCodes) ? managedEventCodes : [],
      createdAt: new Date().toISOString(),
    };
    this.admins.push(admin);
    this._save();
    log('EVENT_ADMINS', `Admin d'événement créé : ${username} (événements: ${admin.managedEventCodes.join(',') || 'aucun'})`);
    return { admin: this._public(admin) };
  }

  /// Vérifie les identifiants d'un admin d'événement (username + password).
  async verify(username, password) {
    const admin = this.getByUsername(username);
    if (!admin || !admin.passwordHash) return null;
    const ok = await bcrypt.compare(password, admin.passwordHash);
    return ok ? this._public(admin) : null;
  }

  async update(id, { displayName, permissions, managedEventCodes } = {}) {
    const admin = this.getById(id);
    if (!admin) return { error: 'Admin d\'événement non trouvé' };
    if (displayName !== undefined) admin.displayName = displayName;
    if (Array.isArray(permissions)) {
      admin.permissions = permissions.filter(p => defaultPermissions(ROLE_EVENT_ADMIN).includes(p));
    }
    if (Array.isArray(managedEventCodes)) admin.managedEventCodes = managedEventCodes;
    admin.updatedAt = new Date().toISOString();
    this._save();
    return { admin: this._public(admin) };
  }

  remove(id) {
    const idx = this.admins.findIndex(a => a.id === id);
    if (idx === -1) return false;
    this.admins.splice(idx, 1);
    this._save();
    log('EVENT_ADMINS', `Admin d'événement supprimé (id=${id})`);
    return true;
  }
}

module.exports = new EventAdminService();
