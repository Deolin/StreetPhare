// server/src/services/pendingEventService.js
//
// Service de gestion des ÉVÉNEMENTS EN ATTENTE DE VALIDATION.
//
// Un événement soumis depuis le site vitrine (page « Créer un événement »)
// est stocké ici avec le statut `pending` jusqu'à ce qu'un Administrateur
// Global ou le Superadmin l'accepte (création de l'événement réel + génération
// de l'admin d'événement) ou le rejette.
//
// Persistance : fichier data/pendingEvents.json

const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const PENDING_PATH = path.join(__dirname, '..', '..', 'data', 'pendingEvents.json');

const log = (category, message) => {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  console.log(`[${ts}] [PENDING-EVENTS] ${message}`);
};

class PendingEventService {
  constructor() {
    this.pending = [];
    this._load();
  }

  _load() {
    try {
      if (!fs.existsSync(PENDING_PATH)) { this._save(); return; }
      const data = JSON.parse(fs.readFileSync(PENDING_PATH, 'utf-8'));
      this.pending = Array.isArray(data) ? data : [];
      log('LOAD', `Chargés : ${this.pending.length} événement(s) en attente`);
    } catch (err) {
      log('ERROR', `⚠ Erreur chargement : ${err.message}`);
      this.pending = [];
    }
  }

  _save() {
    try {
      const dir = path.dirname(PENDING_PATH);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(PENDING_PATH, JSON.stringify(this.pending, null, 2), 'utf-8');
    } catch (err) {
      log('ERROR', `⚠ Erreur sauvegarde : ${err.message}`);
    }
  }

  // ── CRUD ────────────────────────────────────────────────────────────────
  list() {
    return this.pending;
  }

  listByStatus(status) {
    return this.pending.filter(p => p.status === status);
  }

  getById(id) {
    return this.pending.find(p => p.id === id) || null;
  }

  /// Crée une soumission d'événement (en attente de validation).
  create({ email, phone, pseudo, name, startDate, city, summary }) {
    const now = new Date().toISOString();
    const pending = {
      id: uuidv4(),
      email: String(email || '').trim(),
      phone: String(phone || '').trim(),
      pseudo: String(pseudo || '').trim(),
      name: String(name || '').trim(),
      startDate: String(startDate || '').trim(),
      city: String(city || '').trim(),
      summary: String(summary || '').trim(),
      status: 'pending',
      eventCode: null,
      createdAt: now,
      updatedAt: now,
    };
    this.pending.push(pending);
    this._save();
    log('CREATE', `Soumission reçue : "${pending.name}" (${pending.pseudo} <${pending.email}>)`);
    return pending;
  }

  /// Marque la soumission comme acceptée (eventCode = code créé).
  accept(id, eventCode) {
    const pending = this.getById(id);
    if (!pending || pending.status !== 'pending') return null;
    pending.status = 'accepted';
    pending.eventCode = String(eventCode || '').toUpperCase();
    pending.acceptedAt = new Date().toISOString();
    pending.updatedAt = new Date().toISOString();
    this._save();
    return pending;
  }

  /// Marque la soumission comme rejetée.
  reject(id) {
    const pending = this.getById(id);
    if (!pending || pending.status !== 'pending') return null;
    pending.status = 'rejected';
    pending.rejectedAt = new Date().toISOString();
    pending.updatedAt = new Date().toISOString();
    this._save();
    return pending;
  }

  remove(id) {
    const idx = this.pending.findIndex(p => p.id === id);
    if (idx === -1) return false;
    this.pending.splice(idx, 1);
    this._save();
    return true;
  }
}

module.exports = new PendingEventService();