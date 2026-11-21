// server/src/services/adminService.js
//
// Service de gestion des ADMINISTRATEURS GLOBAUX (rôle `admin`).
//
//   - Superadmin   : détenteur du serveur (compte unique défini par
//                    ADMIN_USERNAME / ADMIN_HASH dans la configuration).
//   - Admin global : compte géré ici. Peut gérer tous les autres comptes
//                    (admins globaux, admins d'événements, modérateurs,
//                    éclaireurs) mais PAS le Superadmin.
//
// Conformité (admins NON anonymes) : email + numéro de téléphone obligatoires,
// et confirmation par email avant activation de la connexion.
// La traçabilité des administrateurs (responsables d'événements) contraste
// volontairement avec l'anonymat des participants : elle permet de désigner
// un responsable joignable et de prévenir les dérives (usage malhonnête ou
// illégal de la plateforme).
//
// Persistance : fichier data/admins.json

const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { ROLE_ADMIN } = require('../auth/roles');

const ADMINS_PATH = path.join(__dirname, '..', '..', 'data', 'admins.json');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^\+?[0-9][0-9()\s.-]{6,20}$/;

const log = (category, message) => {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${ts}] [ADMINS] ${message}`);
};

class AdminService {
  constructor() {
    this.admins = [];
    this._load();
  }

  // ── Persistance ─────────────────────────────────────────────────────────
  _load() {
    try {
      if (!fs.existsSync(ADMINS_PATH)) { this._save(); return; }
      const data = JSON.parse(fs.readFileSync(ADMINS_PATH, 'utf-8'));
      this.admins = Array.isArray(data) ? data : [];
      log('LOAD', `Chargés : ${this.admins.length} admin(s) global(aux)`);
    } catch (err) {
      log('ERROR', `⚠ Erreur chargement : ${err.message}`);
      this.admins = [];
    }
  }

  _save() {
    try {
      const dir = path.dirname(ADMINS_PATH);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(ADMINS_PATH, JSON.stringify(this.admins, null, 2), 'utf-8');
    } catch (err) {
      log('ERROR', `⚠ Erreur sauvegarde : ${err.message}`);
    }
  }

  // ── Sanitisation (jamais de hash ni de token) ───────────────────────────
  _public(admin) {
    return {
      id: admin.id,
      username: admin.username,
      displayName: admin.displayName || admin.username,
      email: admin.email,
      phone: admin.phone,
      role: admin.role,
      emailConfirmed: !!admin.emailConfirmed,
      createdAt: admin.createdAt,
      updatedAt: admin.updatedAt,
    };
  }

  // ── Lectures ────────────────────────────────────────────────────────────
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

  // ── Création ────────────────────────────────────────────────────────────
  async create(username, { displayName, email, phone, password } = {}) {
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
      role: ROLE_ADMIN,
      passwordHash,
      emailConfirmed: false,
      confirmationToken: uuidv4(),
      createdAt: new Date().toISOString(),
    };
    this.admins.push(admin);
    this._save();
    log('CREATE', `Créé : ${username} (${admin.email}) — en attente de confirmation email`);
    return { admin: this._public(admin), confirmationToken: admin.confirmationToken };
  }

  // ── Authentification ────────────────────────────────────────────────────
  /// Retourne l'objet brut si identifiants corrects, sinon null.
  async verify(username, password) {
    const admin = this.getByUsername(username);
    if (!admin || !admin.passwordHash) return null;
    const ok = await bcrypt.compare(password, admin.passwordHash);
    return ok ? admin : null;
  }

  /// Change le mot de passe d'un administrateur global après vérification
  /// du mot de passe actuel.
  async changePassword(username, currentPassword, newPassword) {
    const admin = this.getByUsername(username);
    if (!admin || !admin.passwordHash) return { error: 'Compte non trouvé' };
    const ok = await bcrypt.compare(String(currentPassword || ''), admin.passwordHash);
    if (!ok) return { error: 'Mot de passe actuel incorrect' };
    if (!newPassword || String(newPassword).length < 8) {
      return { error: 'Nouveau mot de passe requis (8 caractères minimum)' };
    }
    admin.passwordHash = await bcrypt.hash(String(newPassword), 12);
    admin.updatedAt = new Date().toISOString();
    this._save();
    log('PASSWORD', `Mot de passe modifié : ${admin.username}`);
    return { success: true };
  }

  // ── Mise à jour ─────────────────────────────────────────────────────────
  async update(id, { displayName, email, phone, password } = {}) {
    const admin = this.getById(id);
    if (!admin) return { error: 'Administrateur global non trouvé' };

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

    admin.updatedAt = new Date().toISOString();
    this._save();
    log('UPDATE', `Modifié : ${admin.username}`);
    return { admin: this._public(admin), confirmationToken: admin.confirmationToken };
  }

  // ── Confirmation email ──────────────────────────────────────────────────
  confirmEmailByToken(token) {
    const admin = this.getByConfirmationToken(token);
    if (!admin) return null;
    admin.emailConfirmed = true;
    admin.confirmationToken = null;
    admin.updatedAt = new Date().toISOString();
    this._save();
    log('CONFIRM', `Email confirmé : ${admin.email}`);
    return this._public(admin);
  }

  regenerateConfirmationToken(id) {
    const admin = this.getById(id);
    if (!admin) return null;
    if (admin.emailConfirmed) return admin;
    admin.confirmationToken = uuidv4();
    admin.updatedAt = new Date().toISOString();
    this._save();
    return admin;
  }

  // ── Suppression ─────────────────────────────────────────────────────────
  remove(id) {
    const idx = this.admins.findIndex(a => a.id === id);
    if (idx === -1) return false;
    this.admins.splice(idx, 1);
    this._save();
    log('REMOVE', `Supprimé (id=${id})`);
    return true;
  }
}

module.exports = new AdminService();