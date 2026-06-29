// server/src/store.js
// Stockage avec persistance JSON automatique sur disque.
// 
// Mécanismes :
//   - Chargement de l'état depuis store.json au démarrage (si existant).
//   - Sauvegarde automatique après chaque mutation (addAlert, addEvent,
//     deleteAlert, addPanicPing, syncState) avec un throttle de 2 secondes
//     pour éviter les écritures excessives lors de bursts.
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
    this.meshClients = new Set();
    this.adminClients = new Set();
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
  // PERSISTANCE DISQUE
  // ═══════════════════════════════════════════════════════════════════════

  /// Charge l'état depuis le fichier JSON. Si absent ou corrompu,
  /// initialise un état vide et sauvegarde immédiatement.
  _loadFromDisk() {
    try {
      if (!fs.existsSync(STORE_PATH)) {
        log('STORE', `Aucun fichier de persistance trouvé → état vide (${STORE_PATH})`);
        this._saveToDiskSync();
        return;
      }

      const raw = fs.readFileSync(STORE_PATH, 'utf-8');
      const data = JSON.parse(raw);

      // Validation minimale de la structure.
      if (!data || typeof data !== 'object') {
        throw new Error('Structure invalide');
      }

      // Restauration des alertes.
      if (Array.isArray(data.alerts)) {
        this.alerts = data.alerts;
      }

      // Restauration des événements.
      if (Array.isArray(data.events)) {
        this.events = data.events;
      }

      // Restauration des panicPings (filtrés : on ne garde pas ceux > 5 min).
      if (Array.isArray(data.panicPings)) {
        const cutoff = new Date(Date.now() - 5 * 60 * 1000);
        this.panicPings = data.panicPings.filter(
          p => p.timestamp && new Date(p.timestamp) > cutoff
        );
      }

      // Restauration du syncState.
      if (data.syncState && typeof data.syncState === 'object') {
        this.syncState = {
          lastSyncAt: data.syncState.lastSyncAt || null,
          lastSyncSuccess: data.syncState.lastSyncSuccess || false,
          partnerUrl: data.syncState.partnerUrl || config.partnerUrl,
        };
      }

      // Les clients connectés (mesh, admin) ne sont PAS persistés.
      // Un redémarrage implique la déconnexion de tous les clients.

      log('STORE',
        `État chargé depuis ${STORE_PATH} : ` +
        `${this.alerts.length} alertes, ${this.events.length} événements, ` +
        `${this.panicPings.length} pings panic`
      );
    } catch (err) {
      log('STORE', `⚠ Erreur chargement ${STORE_PATH} : ${err.message}`);
      log('STORE', '  Fallback → état vide. Le fichier corrompu sera écrasé.');
      // Sauvegarde propre immédiate pour remplacer le fichier corrompu.
      try {
        this._saveToDiskSync();
      } catch (saveErr) {
        log('STORE', `⚠ Impossible d'écrire le fichier propre : ${saveErr.message}`);
      }
    }
  }

  /// Sauvegarde immédiate (synchrone) de l'état complet sur disque.
  /// Écriture atomique : .tmp → rename.
  _saveToDiskSync() {
    const dir = path.dirname(STORE_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    const data = this._serialize();
    fs.writeFileSync(STORE_TMP_PATH, JSON.stringify(data, null, 2), 'utf-8');
    fs.renameSync(STORE_TMP_PATH, STORE_PATH);
  }

  /// Programme une sauvegarde asynchrone avec throttle (debounce 2s).
  /// Appelée après chaque mutation. Si plusieurs mutations surviennent
  /// en moins de SAVE_DEBOUNCE_MS, une seule écriture disque est effectuée.
  _scheduleSave() {
    this._savePending = true;

    // Si un timer est déjà actif, on le laisse courir (il écrira
    // l'état le plus récent à son expiration).
    if (this._saveTimer) return;

    this._saveTimer = setTimeout(() => {
      this._saveTimer = null;
      const wasPending = this._savePending;
      this._savePending = false;

      if (!wasPending) return;

      try {
        const dir = path.dirname(STORE_PATH);
        if (!fs.existsSync(dir)) {
          fs.mkdirSync(dir, { recursive: true });
        }

        const data = this._serialize();
        fs.writeFileSync(STORE_TMP_PATH, JSON.stringify(data, null, 2), 'utf-8');
        fs.renameSync(STORE_TMP_PATH, STORE_PATH);
      } catch (err) {
        log('STORE', `⚠ Erreur sauvegarde asynchrone : ${err.message}`);
      }
    }, SAVE_DEBOUNCE_MS);
  }

  /// Force une sauvegarde immédiate (utile avant arrêt propre).
  saveSync() {
    if (this._saveTimer) {
      clearTimeout(this._saveTimer);
      this._saveTimer = null;
    }
    this._savePending = false;
    try {
      this._saveToDiskSync();
      log('STORE', `Sauvegarde forcée → ${STORE_PATH}`);
      return true;
    } catch (err) {
      log('STORE', `⚠ Échec sauvegarde forcée : ${err.message}`);
      return false;
    }
  }

  /// Sérialise l'état persistable (hors Sets clients réseau).
  _serialize() {
    return {
      version: 1,
      savedAt: new Date().toISOString(),
      alerts: this.alerts.map(a => ({ ...a, votes: a.votes ? [...a.votes] : [] })),
      events: this.events,
      panicPings: this.panicPings,
      bugReports: this.bugReports.slice(-200), // max 200 persistés
      syncState: { ...this.syncState },
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ALERTES
  // ═══════════════════════════════════════════════════════════════════════

  addAlert(alert) {
    const existing = this.alerts.find(a => a.id === alert.id);
    if (existing) {
      // Fusion des votes
      if (alert.votes && alert.votes.length > 0) {
        existing.votes.push(...alert.votes.filter(v => !existing.votes.includes(v)));
      }
      existing.updatedAt = new Date().toISOString();
      this._scheduleSave();
      return existing;
    }
    this.alerts.push({
      ...alert,
      createdAt: alert.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    this._scheduleSave();
    return this.alerts[this.alerts.length - 1];
  }

  getActiveAlerts() {
    const now = new Date();
    return this.alerts.filter(a => {
      if (a.status === 'rejected') return false;
      const ageMinutes = (now - new Date(a.createdAt)) / 60000;
      // TTL RGPD absolu : 24h
      if (ageMinutes > config.ttls.absoluteRgpd) return false;
      // TTL métier selon le type
      const ttls = {
        mobile_danger: config.ttls.mobileDanger,
        police: config.ttls.staticDanger,
        fire_truck: config.ttls.staticDanger,
        filter: config.ttls.staticDanger,
        panic: config.ttls.panic,
        collective_danger: config.ttls.collectiveDanger,
      };
      const maxAge = ttls[alert.type] || config.ttls.mobileDanger;
      if (ageMinutes > maxAge) return false;
      // Consensus : au moins 3 votes
      return (alert.votes?.length || 0) >= config.consensusThreshold;
    });
  }

  getAllAlerts() {
    return this.alerts;
  }

  deleteAlert(id) {
    const idx = this.alerts.findIndex(a => a.id === id);
    if (idx !== -1) {
      this.alerts.splice(idx, 1);
      this._scheduleSave();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ÉVÉNEMENTS
  // ═══════════════════════════════════════════════════════════════════════

  addEvent(event) {
    const existing = this.events.find(e => e.code === event.code);
    if (existing) {
      Object.assign(existing, event);
      this._scheduleSave();
      return existing;
    }
    this.events.push(event);
    this._scheduleSave();
    return event;
  }

  getEventByCode(code) {
    return this.events.find(e => e.code === code.toUpperCase());
  }

  getAllEvents() {
    return this.events;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PANIC
  // ═══════════════════════════════════════════════════════════════════════

  addPanicPing(ping) {
    this.panicPings.push({
      ...ping,
      timestamp: ping.timestamp || new Date().toISOString(),
    });
    // Nettoie les pings > 5 min
    const cutoff = new Date(Date.now() - 5 * 60 * 1000);
    this.panicPings = this.panicPings.filter(p => new Date(p.timestamp) > cutoff);

    this._scheduleSave();
    return this.checkPanicAggregation(ping.lat, ping.lng);
  }

  /// Vérifie si 5 pings proches en < 2 min → zone de danger auto-générée.
  checkPanicAggregation(lat, lng) {
    const windowMs = config.panic.timeWindowMinutes * 60 * 1000;
    const cutoff = new Date(Date.now() - windowMs);
    const radius = config.panic.proximityMeters;

    const nearby = this.panicPings.filter(p => {
      if (new Date(p.timestamp) < cutoff) return false;
      const dist = this._haversine(lat, lng, p.lat, p.lng);
      return dist <= radius;
    });

    if (nearby.length >= config.panic.threshold) {
      return {
        aggregated: true,
        count: nearby.length,
        lat,
        lng,
        radius: config.panic.autoZoneRadius,
        type: 'collective_danger',
        description: `Zone de danger collectif — ${nearby.length} pings PANIC agrégés`,
      };
    }
    return { aggregated: false, count: nearby.length };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UTILITAIRES
  // ═══════════════════════════════════════════════════════════════════════

  _haversine(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) ** 2 +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  /// Hash simple de l'état pour la synchro différentielle.
  getStateHash() {
    const active = this.getActiveAlerts().length;
    const total = this.alerts.length;
    return `${active}/${total}:${this.events.length}`;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUG REPORTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Ajoute un rapport de bug au stockage persistant.
  addBugReport(report) {
    const entry = {
      id: report.id || require('uuid').v4(),
      type: report.type || 'report',
      message: report.message || '',
      stackTrace: report.stackTrace || null,
      deviceInfo: report.deviceInfo || null,
      appVersion: report.appVersion || 'unknown',
      receivedAt: new Date().toISOString(),
    };
    this.bugReports.push(entry);

    // Limiter à 1000 rapports max (FIFO).
    if (this.bugReports.length > 1000) {
      this.bugReports = this.bugReports.slice(-1000);
    }

    this._scheduleSave();
    log('STORE', `Bug report #${entry.id} enregistré (total: ${this.bugReports.length})`);
    return entry;
  }

  /// Récupère les bug reports avec pagination optionnelle.
  getBugReports({ limit = 50, offset = 0 } = {}) {
    const total = this.bugReports.length;
    const items = this.bugReports
      .slice()
      .reverse()
      .slice(offset, offset + limit);
    return { items, total, offset, limit };
  }

  /// Récupère un bug report par son ID.
  getBugReportById(id) {
    return this.bugReports.find(r => r.id === id) || null;
  }

  /// Export complet pour le dump de synchro.
  exportAll() {
    return {
      alerts: this.alerts.map(a => ({ ...a, votes: a.votes ? [...a.votes] : [] })),
      events: this.events,
      exportedAt: new Date().toISOString(),
    };
  }

  /// Import depuis un dump de synchro.
  importAll(data) {
    if (!data || !data.alerts) return;
    for (const alert of data.alerts) {
      this.addAlert({ ...alert, votes: alert.votes || [] });
    }
    if (data.events) {
      for (const event of data.events) {
        this.addEvent(event);
      }
    }
    // Sauvegarde immédiate après import complet.
    this._scheduleSave();
  }
}

module.exports = new Store();