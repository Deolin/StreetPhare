// server/src/auth/eventAdminService.js
//
// Service de gestion des administrateurs d'événements.
//
// Un admin d'événement dispose de droits d'édition/modération strictement
// cantonnés à ses propres événements, points d'événements et signalements
// associés.
//
// ⚠️ NON-ANONYMAT OBLIGATOIRE :
// Contrairement aux participants (citoyens) qui restent anonymes, un
// administrateur d'événement est TOUJOURS identifiable : il doit fournir une
// adresse email réelle, un numéro de téléphone valide et confirmer son email.
// Cette traçabilité permet de disposer d'un responsable joignable en cas de
// problème et vise à prévenir toute utilisation de StreetPhare à des fins
// malhonnêtes ou illégales (organisation de débordements sous couvert
// d'anonymat, etc.).
//
// Persistance : fichier data/eventAdmins.json

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { ROLE_EVENT_ADMIN, defaultPermissions } = require('./roles');

const EVENT_ADMINS_PATH = path.join(__dirname, '..', '..', 'data', 'eventAdmins.json');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^\+?[0-9][0-9()\s.-]{6,20}$/;

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
      email: admin.email,
      phone: admin.phone,
      role: admin.role,
      permissions: admin.permissions || [],
      managedEventCodes: admin.managedEventCodes || [],
      emailConfirmed: !!admin.emailConfirmed,
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

  getByEmail(email) {
    const clean = String(email || '').toLowerCase().trim();
    return this.admins.find(a => String(a.email || '').toLowerCase().trim() === clean) || null;
  }

  getByConfirmationToken(token) {
    return this.admins.find(a => a.confirmationToken === token) || null;
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

  async create(username, { displayName, email, phone, permissions, managedEventCodes, password } = {}) {
    if (!username) return { error: 'username requis' };
    const cleanEmail = String(email || '').trim().toLowerCase();
    const cleanPhone = String(phone || '').trim();
    if (!EMAIL_RE.test(cleanEmail)) return { error: 'Adresse email valide requise' };
    if (!PHONE_RE.test(cleanPhone)) return { error: 'Numéro de téléphone valide requis' };
    if (!password || password.length < 8) return { error: 'Mot de passe requis (8 caractères minimum)' };
    if (this.getByUsername(username)) return { error: 'Nom d\'utilisateur déjà utilisé' };
    if (this.getByEmail(cleanEmail)) return { error: 'Adresse email déjà utilisée' };

    const passwordHash = await bcrypt.hash(password, 12);

    const admin = {
      id: uuidv4(),
      username,
      displayName: displayName || username,
      email: cleanEmail,
      phone: cleanPhone,
      role: ROLE_EVENT_ADMIN,
      passwordHash,
      emailConfirmed: false,
      confirmationToken: uuidv4(),
      permissions: Array.isArray(permissions)
        ? permissions.filter(p => defaultPermissions(ROLE_EVENT_ADMIN).includes(p))
        : defaultPermissions(ROLE_EVENT_ADMIN),
      managedEventCodes: Array.isArray(managedEventCodes) ? managedEventCodes : [],
      createdAt: new Date().toISOString(),
    };
    this.admins.push(admin);
    this._save();
    log('EVENT_ADMINS', `Admin d'événement créé : ${username} (événements: ${admin.managedEventCodes.join(',') || 'aucun'})`);
    return { admin: this._public(admin), confirmationToken: admin.confirmationToken };
  }

  /// Génère un Admin d'Événement à partir d'une soumission acceptée.
  /// L'identifiant est l'email ; le pseudo sert de nom affiché. Un mot de passe
  /// temporaire aléatoire est généré et transmis dans l'email de confirmation
  /// (l'admin pouvant ensuite demander une réinitialisation via un admin).
  async createForEvent({ email, phone, pseudo, eventCode, password }) {
    const username = String(email || '').toLowerCase().trim();
    if (this.getByEmail(username)) return { error: 'Un admin existe déjà pour cette adresse email' };

    const temporaryPassword = password || crypto.randomBytes(6).toString('hex');
    const result = await this.create(username, {
      displayName: pseudo || username,
      email,
      phone,
      password: temporaryPassword,
      managedEventCodes: eventCode ? [String(eventCode).toUpperCase()] : [],
    });
    if (result.error) return result;
    result.temporaryPassword = temporaryPassword;
    return result;
  }

  confirmEmailByToken(token) {
    const admin = this.getByConfirmationToken(token);
    if (!admin) return null;
    admin.emailConfirmed = true;
    admin.confirmationToken = null;
    admin.updatedAt = new Date().toISOString();
    this._save();
    log('EVENT_ADMINS', `Email confirmé : ${admin.email}`);
    return this._public(admin);
  }

  /// Vérifie les identifiants d'un admin d'événement (username + password).
  async verify(username, password) {
    const admin = this.getByUsername(username);
    if (!admin || !admin.passwordHash) return null;
    const ok = await bcrypt.compare(password, admin.passwordHash);
    return ok ? this._public(admin) : null;
  }

  async update(id, { displayName, email, phone, permissions, managedEventCodes, password } = {}) {
    const admin = this.getById(id);
    if (!admin) return { error: 'Admin d\'événement non trouvé' };
    if (displayName !== undefined) admin.displayName = displayName;

    if (email !== undefined) {
      const cleanEmail = String(email).trim().toLowerCase();
      if (!EMAIL_RE.test(cleanEmail)) return { error: 'Adresse email valide requise' };
      const other = this.getByEmail(cleanEmail);
      if (other && other.id !== id) return { error: 'Adresse email déjà utilisée' };
      if (cleanEmail !== admin.email) {
        admin.email = cleanEmail;
        admin.emailConfirmed = false;
        admin.confirmationToken = uuidv4();
      }
    }

    if (phone !== undefined) {
      const cleanPhone = String(phone).trim();
      if (!PHONE_RE.test(cleanPhone)) return { error: 'Numéro de téléphone valide requis' };
      admin.phone = cleanPhone;
    }

    if (password) {
      if (password.length < 8) return { error: 'Mot de passe requis (8 caractères minimum)' };
      admin.passwordHash = await bcrypt.hash(password, 12);
    }

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
