// test_servers/modules/heartbeat_monitor.js
//
// Module : Surveillance Heartbeat & Failover automatique — StreetPhare
// ====================================================================
// Responsabilités :
//   1. Surveiller en continu l'état du serveur PRINCIPAL (port 3000)
//      depuis le serveur BACKUP (port 3001).
//   2. Détecter une panne (N heartbeats consécutifs échoués).
//   3. Déclencher automatiquement le failover :
//      - Marquer le serveur backup comme "ACTIF" (promoted).
//      - Mettre à jour SERVER_STATUS.md via le logger.
//      - Diffuser un événement 'failover' aux listeners.
//   4. Fournir un endpoint /status enrichi pour la topologie.
//
// ── Paramètres configurables ──────────────────────────────────────────────
//
//   HEARTBEAT_INTERVAL_MS  : fréquence de sondage (défaut : 5 000 ms)
//   HEARTBEAT_TIMEOUT_MS   : délai avant échec d'un ping (défaut : 3 000 ms)
//   FAILOVER_THRESHOLD     : pings consécutifs échoués avant failover (défaut : 3)
//   RECOVERY_THRESHOLD     : pings consécutifs réussis pour rétablissement (défaut : 3)
//
// ── États possibles du serveur surveillé ─────────────────────────────────
//
//   'unknown'   : surveillance non encore démarrée
//   'online'    : dernière tentative réussie
//   'degraded'  : au moins 1 échec (mais sous le seuil failover)
//   'offline'   : failover déclenché
//   'recovered' : revenu en ligne après une panne
//
'use strict';

const http  = require('http');
const https = require('https');

// ── Configuration par défaut ──────────────────────────────────────────────

const DEFAULT_HEARTBEAT_INTERVAL_MS = 5_000;
const DEFAULT_HEARTBEAT_TIMEOUT_MS  = 3_000;
const DEFAULT_FAILOVER_THRESHOLD    = 3;
const DEFAULT_RECOVERY_THRESHOLD    = 3;

// ── Classe HeartbeatMonitor ────────────────────────────────────────────────

/**
 * Surveille un serveur cible via des requêtes HTTP périodiques vers /healthz.
 * Émet des événements (callbacks) lors des transitions d'état.
 *
 * @example
 * const monitor = new HeartbeatMonitor({
 *   targetUrl: 'http://localhost:3000',
 *   onFailover: (info) => console.log('FAILOVER!', info),
 *   onRecovery: (info) => console.log('RECOVERY!', info),
 * });
 * monitor.start();
 */
class HeartbeatMonitor {
  /**
   * @param {object} opts
   * @param {string}   opts.targetUrl          - URL du serveur à surveiller
   * @param {string}   [opts.monitorName]       - Nom du moniteur (pour logs)
   * @param {number}   [opts.intervalMs]        - Fréquence de sondage (ms)
   * @param {number}   [opts.timeoutMs]         - Délai max par ping (ms)
   * @param {number}   [opts.failoverThreshold] - Échecs consécutifs avant failover
   * @param {number}   [opts.recoveryThreshold] - Succès consécutifs pour recovery
   * @param {Function} [opts.onFailover]        - Appelé lors d'un failover
   * @param {Function} [opts.onRecovery]        - Appelé lors d'un rétablissement
   * @param {Function} [opts.onPing]            - Appelé à chaque ping (succès ou échec)
   * @param {object}   [opts.logger]            - Instance du logger dashboard (dash)
   */
  constructor(opts = {}) {
    this.targetUrl          = opts.targetUrl || 'http://localhost:3000';
    this.monitorName        = opts.monitorName || 'HeartbeatMonitor';
    this.intervalMs         = opts.intervalMs         ?? DEFAULT_HEARTBEAT_INTERVAL_MS;
    this.timeoutMs          = opts.timeoutMs          ?? DEFAULT_HEARTBEAT_TIMEOUT_MS;
    this.failoverThreshold  = opts.failoverThreshold  ?? DEFAULT_FAILOVER_THRESHOLD;
    this.recoveryThreshold  = opts.recoveryThreshold  ?? DEFAULT_RECOVERY_THRESHOLD;
    this.onFailover         = opts.onFailover  || (() => {});
    this.onRecovery         = opts.onRecovery  || (() => {});
    this.onPing             = opts.onPing      || (() => {});
    this.logger             = opts.logger      || null;

    // État interne
    this._status            = 'unknown';  // voir états ci-dessus
    this._consecutiveFails  = 0;
    this._consecutiveOks    = 0;
    this._totalPings        = 0;
    this._totalFails        = 0;
    this._lastPingAt        = null;
    this._lastSuccessAt     = null;
    this._lastFailAt        = null;
    this._failoverTriggeredAt = null;
    this._timerId           = null;
    this._running           = false;
    this._selfRole          = opts.selfRole || 'backup'; // rôle du serveur courant
    this._isPromoted        = false; // true si ce backup est devenu principal
  }

  // ── Contrôle du cycle de vie ──────────────────────────────────────────

  /**
   * Démarre la surveillance périodique.
   * Idempotent : un appel supplémentaire est sans effet.
   */
  start() {
    if (this._running) return;
    this._running = true;
    this._log(`Démarrage surveillance → ${this.targetUrl} (intervalle ${this.intervalMs}ms)`);
    // Premier ping immédiat
    this._tick();
    this._timerId = setInterval(() => this._tick(), this.intervalMs);
  }

  /**
   * Arrête la surveillance.
   */
  stop() {
    if (!this._running) return;
    this._running = false;
    if (this._timerId) { clearInterval(this._timerId); this._timerId = null; }
    this._log('Surveillance arrêtée.');
  }

  // ── Ping ──────────────────────────────────────────────────────────────

  /** Exécute un ping et met à jour l'état interne. */
  async _tick() {
    const startTs = Date.now();
    const result  = await this._doPing();
    const elapsed = Date.now() - startTs;

    this._totalPings++;
    this._lastPingAt = new Date();

    if (this.logger) this.logger.pingReceived(`${this.monitorName} → ${this.targetUrl}`);

    if (result.ok) {
      this._handleSuccess(result, elapsed);
    } else {
      this._handleFailure(result, elapsed);
    }

    this.onPing({ ok: result.ok, elapsed, status: this._status, result });
  }

  /**
   * Effectue la requête HTTP GET /healthz vers le serveur cible.
   * @returns {Promise<{ok:boolean, statusCode?:number, body?:object, error?:string}>}
   */
  _doPing() {
    return new Promise((resolve) => {
      const url  = `${this.targetUrl}/healthz`;
      const lib  = url.startsWith('https') ? https : http;
      let settled = false;

      const req = lib.get(url, { timeout: this.timeoutMs }, (res) => {
        let raw = '';
        res.on('data', c => (raw += c));
        res.on('end', () => {
          if (settled) return;
          settled = true;
          try {
            const body = JSON.parse(raw);
            resolve({ ok: res.statusCode === 200, statusCode: res.statusCode, body });
          } catch {
            resolve({ ok: res.statusCode === 200, statusCode: res.statusCode });
          }
        });
      });

      req.on('timeout', () => {
        if (!settled) { settled = true; req.destroy(); resolve({ ok: false, error: 'timeout' }); }
      });
      req.on('error', (err) => {
        if (!settled) { settled = true; resolve({ ok: false, error: err.message }); }
      });
    });
  }

  // ── Gestion des transitions d'état ────────────────────────────────────

  _handleSuccess(result, elapsed) {
    this._consecutiveFails = 0;
    this._consecutiveOks++;
    this._lastSuccessAt = new Date();

    const wasOffline = this._status === 'offline';
    const wasDegraded = this._status === 'degraded';

    if (this._status !== 'online') {
      this._status = 'online';
      if (wasOffline && this._consecutiveOks >= this.recoveryThreshold) {
        this._triggerRecovery(result);
      }
    }

    this._log(`✓ PING OK (${elapsed}ms) — statut: ${this._status}`);
    if (this.logger) this.logger.setOnline(true, `Heartbeat OK (${elapsed}ms)`);
  }

  _handleFailure(result, elapsed) {
    this._consecutiveOks = 0;
    this._consecutiveFails++;
    this._totalFails++;
    this._lastFailAt = new Date();

    this._log(
      `✗ PING ÉCHOUÉ #${this._consecutiveFails}/${this.failoverThreshold} ` +
      `(${result.error || `HTTP ${result.statusCode}`}) — statut: ${this._status}`
    );

    if (this._consecutiveFails < this.failoverThreshold) {
      this._status = 'degraded';
      if (this.logger) this.logger.setOnline(false, `Heartbeat échoué #${this._consecutiveFails}`);
    } else if (this._status !== 'offline') {
      // Seuil atteint → failover
      this._status = 'offline';
      this._failoverTriggeredAt = new Date();
      if (this.logger) {
        this.logger.setOnline(false, `PANNE DÉTECTÉE après ${this._consecutiveFails} échecs`);
        this.logger.failoverTriggered('Principal', 'Backup');
      }
      this._triggerFailover(result);
    }
  }

  // ── Événements failover / recovery ───────────────────────────────────

  _triggerFailover(lastResult) {
    this._isPromoted = true;
    const info = {
      event:             'failover',
      failed_target:     this.targetUrl,
      consecutive_fails: this._consecutiveFails,
      triggered_at:      this._failoverTriggeredAt.toISOString(),
      last_error:        lastResult.error || `HTTP ${lastResult.statusCode}`,
      monitor:           this.monitorName,
    };
    this._log(`🔴 FAILOVER DÉCLENCHÉ — ${JSON.stringify(info)}`);
    if (this.logger) this.logger.promoted('Promu Principal (failover)');
    try { this.onFailover(info); } catch (e) { this._log(`Erreur onFailover: ${e.message}`); }
  }

  _triggerRecovery(lastResult) {
    this._isPromoted = false;
    const info = {
      event:             'recovery',
      recovered_target:  this.targetUrl,
      consecutive_oks:   this._consecutiveOks,
      recovered_at:      new Date().toISOString(),
      monitor:           this.monitorName,
    };
    this._log(`🟢 RECOVERY — serveur principal de retour ${JSON.stringify(info)}`);
    if (this.logger) {
      this.logger.setOnline(true, 'Serveur principal rétabli');
      this.logger.setCurrentRole('En veille'); // retour en mode standby
    }
    try { this.onRecovery(info); } catch (e) { this._log(`Erreur onRecovery: ${e.message}`); }
  }

  // ── Accès à l'état ─────────────────────────────────────────────────────

  /**
   * Retourne un snapshot de l'état courant du monitor.
   * Utilisé par l'endpoint GET /status du serveur.
   * @returns {object}
   */
  getStatus() {
    return {
      monitor:              this.monitorName,
      target_url:           this.targetUrl,
      status:               this._status,          // 'unknown'|'online'|'degraded'|'offline'
      is_promoted:          this._isPromoted,
      consecutive_fails:    this._consecutiveFails,
      consecutive_oks:      this._consecutiveOks,
      total_pings:          this._totalPings,
      total_fails:          this._totalFails,
      last_ping_at:         this._lastPingAt?.toISOString()   ?? null,
      last_success_at:      this._lastSuccessAt?.toISOString() ?? null,
      last_fail_at:         this._lastFailAt?.toISOString()    ?? null,
      failover_triggered_at: this._failoverTriggeredAt?.toISOString() ?? null,
      config: {
        interval_ms:        this.intervalMs,
        timeout_ms:         this.timeoutMs,
        failover_threshold: this.failoverThreshold,
        recovery_threshold: this.recoveryThreshold,
      },
    };
  }

  /** @returns {boolean} true si ce backup a pris le rôle principal */
  get isPromoted() { return this._isPromoted; }

  /** @returns {string} statut textuel courant */
  get currentStatus() { return this._status; }

  // ── Logging interne ────────────────────────────────────────────────────

  _log(...args) {
    const ts = new Date().toISOString();
    console.log(`[${ts}][${this.monitorName}]`, ...args);
  }
}

// ── Helpers de topologie ──────────────────────────────────────────────────

/**
 * Génère l'objet de réponse pour l'endpoint GET /status d'un serveur.
 * Inclut la topologie complète connue (ce serveur + son backup surveillé).
 *
 * @param {object} opts
 * @param {string}              opts.selfRole      - 'primary'|'secondary'
 * @param {string}              opts.selfUrl       - URL de ce serveur
 * @param {HeartbeatMonitor|null} [opts.monitor]   - monitor actif (peut être null)
 * @param {number}              opts.port
 * @returns {object}
 */
function buildStatusResponse(opts) {
  const { selfRole, selfUrl, monitor, port } = opts;
  const ts = new Date().toISOString();

  const topology = {
    self: {
      role:    selfRole,
      url:     selfUrl,
      port,
      status:  'online',
      role_label: selfRole === 'primary' ? 'Principal' : 'Backup',
    },
    monitored: null,
  };

  if (monitor) {
    const ms = monitor.getStatus();
    topology.monitored = {
      url:         ms.target_url,
      status:      ms.status,       // 'online'|'offline'|'degraded'|'unknown'
      is_promoted: ms.is_promoted,
      last_ping:   ms.last_ping_at,
      last_fail:   ms.last_fail_at,
      failover_at: ms.failover_triggered_at,
    };

    // Mise à jour du rôle self si le backup est promu
    if (ms.is_promoted && selfRole === 'secondary') {
      topology.self.role       = 'primary_promoted';
      topology.self.role_label = 'Principal (failover actif)';
    }
  }

  return {
    ok:         true,
    role:       topology.self.role,
    port,
    ts,
    topology,
    monitor:    monitor ? monitor.getStatus() : null,
  };
}

// ── Statut Markdown (pour SERVER_STATUS.md) ───────────────────────────────

/**
 * Retourne un résumé texte Markdown de la topologie pour injection dans
 * le tableau de bord SERVER_STATUS.md.
 *
 * @param {object} primaryStatus   - {status: 'online'|'offline', url, port}
 * @param {object} backupStatus    - {status, url, port, is_promoted}
 * @returns {string}
 */
function buildTopologyMarkdown(primaryStatus, backupStatus) {
  const icon = (s) =>
    s === 'online'    ? '🟢 EN LIGNE'  :
    s === 'offline'   ? '🔴 HORS LIGNE' :
    s === 'degraded'  ? '🟡 DÉGRADÉ'   : '⚪ INCONNU';

  const roleLabel = (s, promoted) => {
    if (promoted) return '⭐ Principal (failover)';
    if (s === 'primary')   return '⭐ Principal';
    if (s === 'secondary') return '🟡 Backup (en veille)';
    return '⚪ Inconnu';
  };

  const lines = [
    '## 🖥️ Topologie Serveurs (Heartbeat)',
    '',
    '| Serveur | URL | Statut | Rôle |',
    '| --- | --- | --- | --- |',
    `| Principal | ${primaryStatus.url || `http://localhost:${primaryStatus.port}`} ` +
      `| ${icon(primaryStatus.status)} ` +
      `| ${roleLabel('primary', false)} |`,
    `| Backup    | ${backupStatus.url  || `http://localhost:${backupStatus.port}`}  ` +
      `| ${icon(backupStatus.status)}  ` +
      `| ${roleLabel('secondary', backupStatus.is_promoted)} |`,
    '',
  ];
  return lines.join('\n');
}

module.exports = {
  HeartbeatMonitor,
  buildStatusResponse,
  buildTopologyMarkdown,
  // Constantes exportées pour documentation
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  DEFAULT_HEARTBEAT_TIMEOUT_MS,
  DEFAULT_FAILOVER_THRESHOLD,
  DEFAULT_RECOVERY_THRESHOLD,
};
