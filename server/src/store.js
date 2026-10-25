// server/src/store.js
// Stockage avec persistance JSON automatique sur disque.
// 
// Mécanismes :
//   - Chargement de l'état depuis store.json au démarrage (si existant).
//   - Sauvegarde automatique après chaque mutation (addAlert, addEvent,
//     deleteAlert, addPanicPing, syncState) avec un throttle de 2 secondes.
//   - Corruption détectée → fallback sur état vide + sauvegarde propre.
//   - Les Sets (meshClients, adminClients) ne sont pas persistés (transitoires).
//   - Le fichier store.json est atomique : écriture dans un .tmp puis rename.

const fs = require('fs');
const path = require('path');
const config = require('./config');

// ── Log helper formaté [HH:MM:SS - DD/MM] ──────────────────────────────
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

/// Chemin du fichier de persistance (configurable).
const STORE_PATH = config.storePath || path.join(__dirname, '..', 'data', 'store.json');
const STORE_TMP_PATH = STORE_PATH + '.tmp';
const SAVE_DEBOUNCE_MS = 2000; // throttle d'écriture disque

class Store {
  constructor() {
    this.alerts = [];
    this.events = [];
    this.panicPings = [];
    this.bugReports = [];
    this.meshMessages = [];      // Backlog de messages mesh (store-and-forward)
    this.meshClients = new Set();
    this.adminClients = new Set();
    this.bannedUsers = new Set();     // UUIDs d'émetteurs bannis (modération tchat)
    this.geofencingZones = [];        // Zones de géorepérage administrées
    this.tombstones = [];             // Tombstones (suppressions/rejets) pour sync différentielle
    this.userCurrentEvent = new Map(); // userId -> code de l'événement actuellement suivi par l'utilisateur
    this._listeners = {};             // Événements internes (alert_added, …)
    this._msgTimestamps = [];         // Timestamps des messages (taux msg/s)
    this.syncState = {
      lastSyncAt: null,
      lastSyncSuccess: false,
      partnerUrl: config.partnerUrl,
    };

    // Throttle d'écriture : timer unique, réinitialisé à chaque mutation.
    this._saveTimer = null;
    this._savePending = false;

    // Chargement initial depuis le disque.
    this._loadFromDisk();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ÉVÉNEMENTS INTERNES (flux temps réel)
  // ═══════════════════════════════════════════════════════════════════════

  on(event, fn) {
    (this._listeners[event] = this._listeners[event] || []).push(fn);
    return this;
  }

  emit(event, payload) {
    const fns = this._listeners[event] || [];
    for (const fn of fns) {
      try { fn(payload); } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PERSISTANCE DISQUE
  // ═══════════════════════════════════════════════════════════════════════

  _loadFromDisk() {
    try {
      if (!fs.existsSync(STORE_PATH)) {
        log('STORE', `Aucun fichier de persistance trouvé → état vide (${STORE_PATH})`);
        this._saveToDiskSync();
        return;
      }

      const raw = fs.readFileSync(STORE_PATH, 'utf-8');
      const data = JSON.parse(raw);

      if (!data || typeof data !== 'object') {
        throw new Error('Structure invalide');
      }

      if (Array.isArray(data.alerts)) this.alerts = data.alerts;
      if (Array.isArray(data.events)) this.events = data.events;
      if (Array.isArray(data.tombstones)) this.tombstones = data.tombstones;

      if (Array.isArray(data.panicPings)) {
        const cutoff = new Date(Date.now() - 5 * 60 * 1000);
        this.panicPings = data.panicPings.filter(
          p => p.timestamp && new Date(p.timestamp) > cutoff
        );
      }

      if (Array.isArray(data.meshMessages)) {
        this.meshMessages = data.meshMessages.slice(-5000);
      }

      if (Array.isArray(data.bannedUsers)) {
        this.bannedUsers = new Set(data.bannedUsers);
      }

      if (Array.isArray(data.geofencingZones)) {
        this.geofencingZones = data.geofencingZones;
      }

      if (data.syncState && typeof data.syncState === 'object') {
        this.syncState = {
          lastSyncAt: data.syncState.lastSyncAt || null,
          lastSyncSuccess: data.syncState.lastSyncSuccess || false,
          partnerUrl: data.syncState.partnerUrl || config.partnerUrl,
        };
      }

      log('STORE', `État chargé : ${this.alerts.length} alertes, ${this.events.length} événements, ${this.meshMessages.length} messages mesh`);
    } catch (err) {
      log('STORE', `⚠ Erreur chargement : ${err.message} → fallback état vide`);
      try { this._saveToDiskSync(); } catch (_) {}
    }
  }

  _saveToDiskSync() {
    const dir = path.dirname(STORE_PATH);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const data = this._serialize();
    fs.writeFileSync(STORE_TMP_PATH, JSON.stringify(data, null, 2), 'utf-8');
    fs.renameSync(STORE_TMP_PATH, STORE_PATH);
  }

  _scheduleSave() {
    this._savePending = true;
    if (this._saveTimer) return;
    this._saveTimer = setTimeout(() => {
      this._saveTimer = null;
      const wasPending = this._savePending;
      this._savePending = false;
      if (!wasPending) return;
      try {
        const dir = path.dirname(STORE_PATH);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        const data = this._serialize();
        fs.writeFileSync(STORE_TMP_PATH, JSON.stringify(data, null, 2), 'utf-8');
        fs.renameSync(STORE_TMP_PATH, STORE_PATH);
      } catch (err) { log('STORE', `⚠ Erreur sauvegarde : ${err.message}`); }
    }, SAVE_DEBOUNCE_MS);
  }

  saveSync() {
    if (this._saveTimer) { clearTimeout(this._saveTimer); this._saveTimer = null; }
    this._savePending = false;
    try { this._saveToDiskSync(); log('STORE', `Sauvegarde forcée → ${STORE_PATH}`); return true; }
    catch (err) { log('STORE', `⚠ Échec sauvegarde forcée : ${err.message}`); return false; }
  }

  _serialize() {
    return {
      version: 1,
      savedAt: new Date().toISOString(),
      alerts: this.alerts.map(a => ({ ...a, votes: a.votes ? [...a.votes] : [] })),
      events: this.events,
      panicPings: this.panicPings,
      bugReports: this.bugReports.slice(-200),
      meshMessages: this.meshMessages.slice(-1000),
      bannedUsers: [...this.bannedUsers],
      geofencingZones: this.geofencingZones,
      tombstones: this.tombstones.slice(-5000),
      syncState: { ...this.syncState },
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ALERTES
  // ═══════════════════════════════════════════════════════════════════════

  addAlert(alert) {
    // Filtrage anti-faux-positif sur la densité : ignore les rapports de densité
    // sous le seuil de foule configuré (ex: 25 utilisateurs minimum).
    if (alert && alert.type === 'density') {
      const dv = Number(alert.density_value ?? alert.densityValue ?? 0);
      const minDensity = config.crowdDensityThreshold || 25;
      if (dv < minDensity) {
        return alert;
      }
    }
    const nowIso = new Date().toISOString();
    const existing = this.alerts.find(a => a.id === alert.id);
    if (existing) {
      if (alert.votes && alert.votes.length > 0) {
        if (!existing.votes) existing.votes = [];
        const newVotes = alert.votes.filter(v => !existing.votes.includes(v));
        if (newVotes.length > 0) {
          existing.votes.push(...newVotes);
          existing.lastVoteAt = nowIso;
        }
      }
      // Propagation des champs mutables lors de la réplication
      // Primary ↔ Backup : le statut (validé/rejeté) doit être
      // synchronisé, pas seulement les votes.
      if (alert.status !== undefined) existing.status = alert.status;
      if (alert.type !== undefined) existing.type = alert.type;
      if (alert.lat !== undefined) existing.lat = alert.lat;
      if (alert.lng !== undefined) existing.lng = alert.lng;
      if (alert.description !== undefined) existing.description = alert.description;
      if (alert.eventId !== undefined) existing.eventId = alert.eventId;
      if (alert.scoutValidated !== undefined) existing.scoutValidated = alert.scoutValidated;
      if (alert.voidedBy !== undefined) existing.voidedBy = alert.voidedBy;
      if (alert.voidedAt !== undefined) existing.voidedAt = alert.voidedAt;
      if (alert.lastVoteAt !== undefined) existing.lastVoteAt = alert.lastVoteAt;
      if (alert.downvotes !== undefined) existing.downvotes = alert.downvotes;
      existing.updatedAt = nowIso;
      this._scheduleSave();
      return existing;
    }
    this.alerts.push({
      ...alert,
      downvotes: Array.isArray(alert.downvotes) ? alert.downvotes : [],
      createdAt: alert.createdAt || nowIso,
      lastVoteAt: alert.lastVoteAt || alert.createdAt || nowIso,
      updatedAt: nowIso,
    });
    this._scheduleSave();
    this.emit('alert_added', this.alerts[this.alerts.length - 1]);
    return this.alerts[this.alerts.length - 1];
  }

  /// Fusionne un signalement dans une alerte existante de MÊME type et proche
  /// (anti-doublons : deux signalements identiques trop proches sont fusionnés
  /// et le vote est incrémenté au lieu de créer un doublon).
  ///
  /// Retourne l'alerte existante si une fusion a eu lieu, sinon `null`.
  mergeNearbyIdentical(alert, radiusMeters) {
    const r = radiusMeters || config.mergeRadiusMeters || 50;
    if (alert.lat == null || alert.lng == null || !alert.type) return null;

    const target = this.alerts.find(a => {
      if (!a || a.id === alert.id) return false;
      if (a.status === 'rejected') return false;
      if (a.type !== alert.type) return false;
      if (a.lat == null || a.lng == null) return false;
      return this._haversine(alert.lat, alert.lng, a.lat, a.lng) <= r;
    });
    if (!target) return null;

    const incoming = Array.isArray(alert.votes) ? alert.votes : [];
    if (!Array.isArray(target.votes)) target.votes = [];
    for (const v of incoming) {
      if (!target.votes.includes(v)) target.votes.push(v);
    }
    const nowIso = new Date().toISOString();
    target.lastVoteAt = nowIso;
    target.updatedAt = nowIso;
    this._scheduleSave();
    log('ALERT', `Fusion ${alert.type} (${alert.id}) → ${target.id} (${target.votes.length} votes)`);
    return target;
  }

  /// Détecte les signalements actifs/validés situés au même endroit (≤ radiusMeters)
  /// mais d'un type DIFFÉRENT / CONTRADICTOIRE (`a.type !== alert.type`).
  findContradictoryNearby(alert, radiusMeters) {
    const r = radiusMeters || config.mergeRadiusMeters || 50;
    if (alert.lat == null || alert.lng == null || !alert.type) return [];

    return this.alerts.filter(a => {
      if (!a || a.id === alert.id) return false;
      if (a.status === 'rejected' || a.status === 'voided' || a.status === 'tombstone') return false;
      if (a.type === alert.type) return false;
      if (a.lat == null || a.lng == null) return false;
      return this._haversine(alert.lat, alert.lng, a.lat, a.lng) <= r;
    });
  }

  /// Retourne les signalements actifs/validés qui n'ont reçu aucun vote/confirmation
  /// depuis au moins `inactivityMs` (par défaut 5 minutes) et qui n'ont pas déjà
  /// fait l'objet d'une demande de validation dynamique depuis `cooldownMs`.
  getStaleAlertsForValidation(inactivityMs = 5 * 60 * 1000, cooldownMs = 5 * 60 * 1000) {
    const now = Date.now();
    const results = [];
    for (const a of this.alerts) {
      if (!a || a.status === 'rejected' || a.status === 'voided' || a.status === 'tombstone') continue;
      const ageMinutes = (now - new Date(a.createdAt).getTime()) / 60000;
      if (ageMinutes > config.ttls.absoluteRgpd) continue;

      const lastVoteTs = new Date(a.lastVoteAt || a.updatedAt || a.createdAt).getTime();
      if (isNaN(lastVoteTs) || (now - lastVoteTs) < inactivityMs) continue;

      const lastReqTs = a.validationRequestedAt ? new Date(a.validationRequestedAt).getTime() : 0;
      if (lastReqTs && (now - lastReqTs) < cooldownMs) continue;

      results.push(a);
    }
    return results;
  }

  /// Enregistre la réponse d'un utilisateur proche à une demande de validation :
  ///   - `isConfirmed === true`  : ajoute un vote positif et rafraîchit `lastVoteAt`.
  ///   - `isConfirmed === false` : ajoute une infirmation (`downvotes`). Si le
  ///     signalement est infirmé majoritairement ou atteint ≥ 2 infirmations,
  ///     il est purgé (`status = 'rejected'` + tombstone).
  recordValidationVote(id, userId, isConfirmed) {
    const alert = this.alerts.find(a => a.id === id);
    if (!alert) return null;
    if (alert.status === 'rejected' || alert.status === 'voided' || alert.status === 'tombstone') {
      return { alert, purged: true, validated: false };
    }

    const uid = String(userId || 'anonymous');
    const nowIso = new Date().toISOString();
    if (!Array.isArray(alert.votes)) alert.votes = [];
    if (!Array.isArray(alert.downvotes)) alert.downvotes = [];

    if (isConfirmed) {
      alert.downvotes = alert.downvotes.filter(u => u !== uid);
      if (!alert.votes.includes(uid)) {
        alert.votes.push(uid);
      }
      alert.lastVoteAt = nowIso;
      alert.updatedAt = nowIso;
      const validated = alert.scoutValidated || alert.status === 'validated' || alert.votes.length >= config.consensusThreshold;
      if (validated && alert.status === 'active') {
        alert.status = 'validated';
      }
      this._scheduleSave();
      return {
        alert,
        purged: false,
        validated,
        votesCount: alert.votes.length,
        downvotesCount: alert.downvotes.length,
      };
    } else {
      alert.votes = alert.votes.filter(u => u !== uid);
      if (!alert.downvotes.includes(uid)) {
        alert.downvotes.push(uid);
      }
      alert.lastVoteAt = nowIso;
      alert.updatedAt = nowIso;

      // Purge automatique si :
      //   - >= 2 infirmations, OU
      //   - le signalement n'a pas encore atteint le consensus (ou est sous vérification dynamique)
      //     et les infirmations égalent/dépassent les votes positifs (hors éclaireur).
      const hasReachedConsensus = alert.votes.length >= config.consensusThreshold;
      const shouldPurge =
        alert.downvotes.length >= 2 ||
        (!alert.scoutValidated &&
          (!hasReachedConsensus || Boolean(alert.validationRequestedAt)) &&
          alert.downvotes.length >= alert.votes.length);
      if (shouldPurge) {
        alert.status = 'rejected';
        alert.purgedReason = 'community_refuted';
        this._addTombstone(alert.id, 'rejected');
      }
      this._scheduleSave();
      return {
        alert,
        purged: shouldPurge,
        validated: false,
        votesCount: alert.votes.length,
        downvotesCount: alert.downvotes.length,
      };
    }
  }

  getActiveAlerts() {
    const now = new Date();
    const minDensity = config.crowdDensityThreshold || 25;
    return this.alerts.filter(a => {
      if (a.status === 'rejected' || a.status === 'voided' || a.status === 'tombstone') return false;
      if (a.type === 'density') {
        const dv = Number(a.density_value ?? a.densityValue ?? 0);
        if (dv < minDensity) return false;
      }
      const ageMinutes = (now - new Date(a.createdAt)) / 60000;
      if (ageMinutes > config.ttls.absoluteRgpd) return false;
      const ttls = { mobile_danger: config.ttls.mobileDanger, police: config.ttls.staticDanger, fire_truck: config.ttls.staticDanger, filter: config.ttls.staticDanger, panic: config.ttls.panic, collective_danger: config.ttls.collectiveDanger };
      const maxAge = ttls[a.type] || config.ttls.mobileDanger;
      if (ageMinutes > maxAge) return false;
      if (a.scoutValidated || a.status === 'validated') return true;
      return (a.votes?.length || 0) >= config.consensusThreshold;
    });
  }

  getAllAlerts() { return this.alerts; }

  deleteAlert(id) {
    const idx = this.alerts.findIndex(a => a.id === id);
    if (idx !== -1) {
      this.alerts.splice(idx, 1);
      this._addTombstone(id, 'deleted');
      this._scheduleSave();
      return true;
    }
    return false;
  }

  /// Enregistre un tombstone (suppression/rejet) pour la sync différentielle.
  /// Permet aux clients déconnectés de supprimer localement les alertes
  /// retirées côté serveur, même s'ils ont manqué le broadcast temps réel.
  _addTombstone(id, reason) {
    const now = Date.now();
    this.tombstones.push({ id, reason, deletedAt: new Date(now).toISOString() });
    // Nettoyage : tombstones > 60 jours, puis cap à 5000 entrées.
    const cutoff = now - 60 * 24 * 60 * 60 * 1000;
    this.tombstones = this.tombstones
      .filter(t => new Date(t.deletedAt).getTime() > cutoff)
      .slice(-5000);
  }

  /// Retourne les tombstones postérieurs à [since].
  getTombstonesSince(since) {
    if (!since) return [];
    const sinceDate = new Date(since);
    return this.tombstones.filter(t => new Date(t.deletedAt) > sinceDate);
  }

  /// Applique un tombstone reçu d'un serveur partenaire (Primary → Backup).
  /// Le tombstone est TOUJOURS enregistré (même si l'alerte n'existe pas
  /// localement) afin que les clients du Backup suppriment aussi l'alerte.
  applyTombstone(id, reason) {
    if (reason === 'rejected') {
      const alert = this.alerts.find(a => a.id === id);
      if (alert) {
        alert.status = 'rejected';
        alert.updatedAt = new Date().toISOString();
      }
    } else {
      const idx = this.alerts.findIndex(a => a.id === id);
      if (idx !== -1) this.alerts.splice(idx, 1);
    }
    this._addTombstone(id, reason || 'deleted');
    this._scheduleSave();
    return true;
  }

  /// Vérifie si un id a un tombstone (suppression/rejet enregistré).
  isTombstoned(id) {
    return this.tombstones.some(t => t.id === id);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ÉVÉNEMENTS
  // ═══════════════════════════════════════════════════════════════════════

  addEvent(event) {
    const existing = this.events.find(e => e.code === event.code);
    if (existing) { Object.assign(existing, event); this._scheduleSave(); return existing; }
    this.events.push(event); this._scheduleSave(); return event;
  }

  getEventByCode(code) { return this.events.find(e => e.code === code.toUpperCase()); }

  getAllEvents() { return this.events; }

  /// Met à jour (partiellement) un événement existant identifié par son code.
  /// Retourne l'événement mis à jour ou `null` si le code est inconnu.
  updateEvent(code, patch) {
    const existing = this.getEventByCode(code);
    if (!existing) return null;
    Object.assign(existing, patch, { code: existing.code });
    this._scheduleSave();
    return existing;
  }

  /// Supprime un événement identifié par son code.
  /// Retourne `true` si l'événement a été supprimé, `false` s'il est inconnu.
  removeEvent(code) {
    const idx = this.events.findIndex(e => e.code === String(code || '').toUpperCase());
    if (idx === -1) return false;
    this.events.splice(idx, 1);
    this._scheduleSave();
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SUIVI UTILISATEUR -> ÉVÉNEMENT (cycle de vie des signalements)
  // ═══════════════════════════════════════════════════════════════════════

  /// Enregistre l'événement actuellement suivi par un utilisateur.
  setUserCurrentEvent(userId, eventCode) {
    if (!userId || !eventCode) return false;
    this.userCurrentEvent.set(String(userId), String(eventCode).toUpperCase());
    this._scheduleSave();
    return true;
  }

  /// Retourne le code de l'événement suivi par [userId], ou `undefined`.
  getUserCurrentEvent(userId) {
    return this.userCurrentEvent.get(String(userId));
  }

  /// Supprime le suivi de l'utilisateur (déconnexion / changement d'événement).
  removeUserCurrentEvent(userId) {
    const had = this.userCurrentEvent.has(String(userId));
    this.userCurrentEvent.delete(String(userId));
    if (had) this._scheduleSave();
    return had;
  }

  /// Applique un statut "tombstone" (suppression logique) à tous les
  /// signalements actifs rattachés à [eventCode].
  /// Retourne { alertIds: [...], count }.
  tombstoneEvent(eventCode) {
    const code = String(eventCode || '').toUpperCase();
    const alertIds = [];
    for (const alert of this.alerts) {
      if (
        alert.eventId === code &&
        alert.status !== 'tombstone' &&
        alert.status !== 'rejected' &&
        alert.status !== 'voided'
      ) {
        alert.status = 'tombstone';
        alert.updatedAt = new Date().toISOString();
        this._addTombstone(alert.id, 'tombstone');
        alertIds.push(alert.id);
      }
    }
    if (alertIds.length) this._scheduleSave();
    return { alertIds, count: alertIds.length };
  }

  /// Clôture un événement et applique le tombstone à ses signalements actifs.
  /// Retourne l'événement modifié ou `null` s'il est inconnu.
  closeEvent(eventCode) {
    const event = this.getEventByCode(eventCode);
    if (!event) return null;
    event.status = 'closed';
    event.updatedAt = new Date().toISOString();
    this.tombstoneEvent(event.code);
    this._scheduleSave();
    return event;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PANIC
  // ═══════════════════════════════════════════════════════════════════════

  addPanicPing(ping) {
    this.panicPings.push({ ...ping, timestamp: ping.timestamp || new Date().toISOString() });
    const cutoff = new Date(Date.now() - 5 * 60 * 1000);
    this.panicPings = this.panicPings.filter(p => new Date(p.timestamp) > cutoff);
    this._scheduleSave();
    return this.checkPanicAggregation(ping.lat, ping.lng);
  }

  checkPanicAggregation(lat, lng) {
    const windowMs = config.panic.timeWindowMinutes * 60 * 1000;
    const cutoff = new Date(Date.now() - windowMs);
    const radius = config.panic.proximityMeters;
    const nearby = this.panicPings.filter(p => { if (new Date(p.timestamp) < cutoff) return false; const dist = this._haversine(lat, lng, p.lat, p.lng); return dist <= radius; });
    if (nearby.length >= config.panic.threshold) {
      return { aggregated: true, count: nearby.length, lat, lng, radius: config.panic.autoZoneRadius, type: 'collective_danger', description: `Zone de danger collectif — ${nearby.length} pings PANIC agrégés` };
    }
    return { aggregated: false, count: nearby.length };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MESH MESSAGES (Store-and-Forward pour clients 5G / isolés)
  // ═══════════════════════════════════════════════════════════════════════

  addMeshMessage(payload) {
    const msg = {
      id: require('uuid').v4(),
      kind: payload.kind || 'mesh',
      data: payload.data || payload,
      receivedAt: new Date().toISOString(),
      senderId: payload.sender_id || 'unknown',
    };
    if (payload.simulated) msg.simulated = true;
    this.meshMessages.push(msg);
    if (this.meshMessages.length > 5000) this.meshMessages = this.meshMessages.slice(-5000);
    this._msgTimestamps.push(Date.now());
    if (this._msgTimestamps.length > 1000) this._msgTimestamps = this._msgTimestamps.slice(-1000);
    this._scheduleSave();
    log('MESH', `Message backlog #${msg.id} enregistré (total: ${this.meshMessages.length})`);
    return msg;
  }

  getMeshMessagesSince(sinceIso) {
    if (!sinceIso) return this.meshMessages.slice(-1000);
    const since = new Date(sinceIso);
    if (isNaN(since.getTime())) return [];
    return this.meshMessages.filter(m => new Date(m.receivedAt) > since);
  }

  purgeExpiredMeshMessages() {
    const cutoff = new Date(Date.now() - 48 * 60 * 60 * 1000);
    const before = this.meshMessages.length;
    this.meshMessages = this.meshMessages.filter(m => new Date(m.receivedAt) > cutoff);
    const removed = before - this.meshMessages.length;
    if (removed > 0) { this._scheduleSave(); log('MESH', `Purge backlog : ${removed} messages > 48h`); }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UTILITAIRES
  // ═══════════════════════════════════════════════════════════════════════

  _haversine(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  getStateHash() { const active = this.getActiveAlerts().length; const total = this.alerts.length; return `${active}/${total}:${this.events.length}`; }

  // ═══════════════════════════════════════════════════════════════════════
  // BUG REPORTS
  // ═══════════════════════════════════════════════════════════════════════

  addBugReport(report) {
    const entry = {
      id: report.id || require('uuid').v4(),
      type: report.type || 'report',
      title: report.title || null,
      message: report.message || '',
      stackTrace: report.stackTrace || null,
      deviceInfo: report.deviceInfo || null,
      appVersion: report.appVersion || 'unknown',
      platform: report.platform || null,
      extraLogs: report.extraLogs || null,
      clientTimestamp: report.clientTimestamp || null,
      attempts: report.attempts ?? 0,
      receivedAt: new Date().toISOString(),
    };
    this.bugReports.push(entry);
    if (this.bugReports.length > 1000) this.bugReports = this.bugReports.slice(-1000);
    this._scheduleSave();
    log('STORE', `Bug report #${entry.id} enregistré`);
    return entry;
  }

  getBugReports({ limit = 50, offset = 0 } = {}) {
    const total = this.bugReports.length;
    const items = this.bugReports.slice().reverse().slice(offset, offset + limit);
    return { items, total, offset, limit };
  }

  getBugReportById(id) { return this.bugReports.find(r => r.id === id) || null; }

  exportAll() { return { alerts: this.alerts.map(a => ({ ...a, votes: a.votes ? [...a.votes] : [] })), events: this.events, tombstones: this.tombstones, exportedAt: new Date().toISOString() }; }

  importAll(data) {
    if (!data || !data.alerts) return;
    for (const alert of data.alerts) { this.addAlert({ ...alert, votes: alert.votes || [] }); }
    if (data.events) { for (const event of data.events) { this.addEvent(event); } }
    // Réconcilier les suppressions/rejets (tombstones) du partenaire.
    if (Array.isArray(data.tombstones)) {
      for (const t of data.tombstones) { this.applyTombstone(t.id, t.reason); }
    }
    this._scheduleSave();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODÉRATION — Bannissement d'UUID (tchat P2P / relais)
  // ═══════════════════════════════════════════════════════════════════════

  banUser(uuid) {
    if (!uuid) return false;
    this.bannedUsers.add(uuid);
    this._scheduleSave();
    return true;
  }

  unbanUser(uuid) {
    const removed = this.bannedUsers.delete(uuid);
    if (removed) this._scheduleSave();
    return removed;
  }

  isBanned(uuid) { return this.bannedUsers.has(uuid); }

  getBannedUsers() { return [...this.bannedUsers]; }

  // ═══════════════════════════════════════════════════════════════════════
  // GÉOREPÉRAGE — Zones administrées
  // ═══════════════════════════════════════════════════════════════════════

  addGeofencingZone(zone) {
    const entry = {
      id: zone.id || require('uuid').v4(),
      name: zone.name || 'Zone sans nom',
      type: zone.type || 'safe', // safe | danger | custom
      lat: zone.lat,
      lng: zone.lng,
      radiusMeters: zone.radiusMeters || 100,
      createdAt: new Date().toISOString(),
    };
    if (zone.simulated) entry.simulated = true;
    this.geofencingZones.push(entry);
    this._scheduleSave();
    return entry;
  }

  removeGeofencingZone(id) {
    const idx = this.geofencingZones.findIndex(z => z.id === id);
    if (idx !== -1) { this.geofencingZones.splice(idx, 1); this._scheduleSave(); return true; }
    return false;
  }

  getGeofencingZones() { return this.geofencingZones; }

  // ═══════════════════════════════════════════════════════════════════════
  // CONSOLE — Purge des vieux signalements
  // ═══════════════════════════════════════════════════════════════════════

  purgeOldAlerts(maxAgeHours = 24) {
    const cutoff = new Date(Date.now() - maxAgeHours * 60 * 60 * 1000);
    const before = this.alerts.length;
    this.alerts = this.alerts.filter(a => new Date(a.createdAt) > cutoff);
    const removed = before - this.alerts.length;
    if (removed > 0) this._scheduleSave();
    return removed;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CONSOLE — Informations sur les connexions actives
  // ═══════════════════════════════════════════════════════════════════════

  getConnectionsInfo() {
    return {
      meshClients: this.meshClients.size,
      adminClients: this.adminClients.size,
      alertsTotal: this.alerts.length,
      alertsActive: this.getActiveAlerts().length,
      events: this.events.length,
      bannedUsers: this.bannedUsers.size,
      geofencingZones: this.geofencingZones.length,
      meshMessages: this.meshMessages.length,
      stateHash: this.getStateHash(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODÉRATION — Validation / rejet / suppression de signalements
  // ═══════════════════════════════════════════════════════════════════════

  validateAlert(id) {
    const alert = this.alerts.find(a => a.id === id);
    if (!alert) return false;
    alert.status = 'active';
    alert.updatedAt = new Date().toISOString();
    // Retirer le tombstone éventuel (re-validation après un rejet).
    this.tombstones = this.tombstones.filter(t => t.id !== id);
    this._scheduleSave();
    return true;
  }

  rejectAlert(id) {
    const alert = this.alerts.find(a => a.id === id);
    if (!alert) return false;
    alert.status = 'rejected';
    alert.updatedAt = new Date().toISOString();
    this._addTombstone(id, 'rejected');
    this._scheduleSave();
    return true;
  }

  /// Marque un signalement comme « annulé » (faux signalement)
  /// par un éclaireur. Diffère de rejectAlert par le statut `voided`
  /// et le marquage du modérateur ayant procédé à l'annulation.
  voidAlert(id, userId) {
    const alert = this.alerts.find(a => a.id === id);
    if (!alert) return false;
    alert.status = 'voided';
    alert.voidedBy = userId;
    alert.voidedAt = new Date().toISOString();
    this._addTombstone(id, 'voided');
    this._scheduleSave();
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODÉRATION — Suppression d'un message mesh
  // ═══════════════════════════════════════════════════════════════════════

  deleteMeshMessage(id) {
    const idx = this.meshMessages.findIndex(m => m.id === id);
    if (idx === -1) return false;
    this.meshMessages.splice(idx, 1);
    this._scheduleSave();
    return true;
  }
  // ═══════════════════════════════════════════════════════════════════════
  // SIMULATION & MÉTRIQUES
  // ═══════════════════════════════════════════════════════════════════════

  /// Ajoute des votes (upvotes) à une alerte. Retourne le nombre ajouté.
  addVotes(id, userIds) {
    const a = this.alerts.find(x => x.id === id);
    if (!a) return 0;
    if (!a.votes) a.votes = [];
    let added = 0;
    for (const u of userIds) {
      if (!a.votes.includes(u)) { a.votes.push(u); added++; }
    }
    if (added) { a.updatedAt = new Date().toISOString(); this._scheduleSave(); }
    return added;
  }

  /// Retire jusqu'à `count` votes (downvotes). Retourne le nombre retiré.
  removeVotes(id, count) {
    const a = this.alerts.find(x => x.id === id);
    if (!a || !a.votes || a.votes.length === 0) return 0;
    const before = a.votes.length;
    a.votes = a.votes.slice(0, Math.max(0, before - count));
    const removed = before - a.votes.length;
    if (removed) { a.updatedAt = new Date().toISOString(); this._scheduleSave(); }
    return removed;
  }

  /// Supprime toutes les entités fictives (marquées `simulated: true`).
  /// N'affecte pas les données de production réelles.
  removeSimulatedEntities() {
    const removed = {
      alerts: this.alerts.filter(a => a.simulated).length,
      events: this.events.filter(e => e.simulated).length,
      zones: this.geofencingZones.filter(z => z.simulated).length,
      messages: this.meshMessages.filter(m => m.simulated).length,
      panics: this.panicPings.filter(p => p.simulated).length,
    };
    this.alerts = this.alerts.filter(a => !a.simulated);
    this.events = this.events.filter(e => !e.simulated);
    this.geofencingZones = this.geofencingZones.filter(z => !z.simulated);
    this.meshMessages = this.meshMessages.filter(m => !m.simulated);
    this.panicPings = this.panicPings.filter(p => !p.simulated);
    this._scheduleSave();
    return removed;
  }

  /// Taux de messages (moyenne sur la dernière minute, msg/s).
  getMessageRate() {
    const cutoff = Date.now() - 60000;
    this._msgTimestamps = this._msgTimestamps.filter(t => t > cutoff);
    return this._msgTimestamps.length / 60;
  }

  /// Métriques temps réel (pour le widget de charge admin).
  getMetrics() {
    return {
      meshClients: this.meshClients.size,
      adminClients: this.adminClients.size,
      alertsActive: this.getActiveAlerts().length,
      alertsTotal: this.alerts.length,
      events: this.events.length,
      messagesPerSec: Math.round(this.getMessageRate() * 100) / 100,
      memoryMB: Math.round(process.memoryUsage().rss / 1024 / 1024),
      uptimeSeconds: Math.round(process.uptime()),
    };
  }
}

module.exports = new Store();