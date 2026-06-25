// server/src/store.js
// Stockage en mémoire volatile avec persistance JSON optionnelle.
// En production, remplacer par MongoDB/Redis.

const fs = require('fs');
const path = require('path');
const config = require('./config');

class Store {
  constructor() {
    this.alerts = [];        // { id, type, lat, lng, description, createdAt, ttlMinutes, votes: Set, status, uploadedTo }
    this.events = [];        // { code, title, startAt, visibleAt, routeGeoJson, waypoints, pois, careCenters, exitPoints, safeZones, destinationLatitude, destinationLongitude }
    this.panicPings = [];    // { id, lat, lng, timestamp, userId }
    this.meshClients = new Set();
    this.adminClients = new Set();
    this.syncState = {
      lastSyncAt: null,
      lastSyncSuccess: false,
      partnerUrl: config.partnerUrl,
    };
  }

  // ── Alertes ─────────────────────────────────────────────────────────

  addAlert(alert) {
    const existing = this.alerts.find(a => a.id === alert.id);
    if (existing) {
      // Fusion des votes
      if (alert.votes && alert.votes.length > 0) {
        existing.votes.push(...alert.votes.filter(v => !existing.votes.includes(v)));
      }
      existing.updatedAt = new Date().toISOString();
      return existing;
    }
    this.alerts.push({
      ...alert,
      createdAt: alert.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
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
      return true;
    }
    return false;
  }

  // ── Événements ──────────────────────────────────────────────────────

  addEvent(event) {
    const existing = this.events.find(e => e.code === event.code);
    if (existing) {
      Object.assign(existing, event);
      return existing;
    }
    this.events.push(event);
    return event;
  }

  getEventByCode(code) {
    return this.events.find(e => e.code === code.toUpperCase());
  }

  getAllEvents() {
    return this.events;
  }

  // ── Panic ────────────────────────────────────────────────────────────

  addPanicPing(ping) {
    this.panicPings.push({
      ...ping,
      timestamp: ping.timestamp || new Date().toISOString(),
    });
    // Nettoie les pings > 5 min
    const cutoff = new Date(Date.now() - 5 * 60 * 1000);
    this.panicPings = this.panicPings.filter(p => new Date(p.timestamp) > cutoff);

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

  // ── Utilitaires ─────────────────────────────────────────────────────

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
  }
}

module.exports = new Store();