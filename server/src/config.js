// server/src/config.js
// Configuration centralisée StreetPhare — Node.js v3.0
// Lit les variables d'environnement (.env) et expose des valeurs par défaut.

require('dotenv').config();

const config = {
  // ── Identité du serveur ─────────────────────────────────────────────
  serverType: process.env.SERVER_TYPE || 'PRIMARY', // PRIMARY | BACKUP
  host: process.env.SERVER_HOST || '0.0.0.0',
  port: parseInt(process.env.SERVER_PORT || '3000', 10),

  // ── Serveur partenaire ──────────────────────────────────────────────
  partnerUrl: process.env.PARTNER_URL || 'http://192.168.31.63:3001',


  // ── Chiffrement ─────────────────────────────────────────────────────
  // La clé maîtresse DOIT être fournie via la variable d'environnement
  // MASTER_KEY. En production, le serveur REFUSE de démarrer avec la
  // valeur par défaut (qui n'est qu'un placeholder de développement).
  masterKey: (() => {
    const key = process.env.MASTER_KEY;
    if (!key || key === 'streetphare-dev-key-change-in-production') {
      if (process.env.NODE_ENV === 'production') {
        console.error('╔══════════════════════════════════════════════════════╗');
        console.error('║  ERREUR FATALE : MASTER_KEY non configurée          ║');
        console.error('║  En production, définissez la variable              ║');
        console.error('║  d\'environnement MASTER_KEY avec une clé forte.     ║');
        console.error('║  Exemple : export MASTER_KEY="$(openssl rand -hex 32)"  ║');
        console.error('╚══════════════════════════════════════════════════════╝');
        process.exit(1);
      }
      console.warn('[CONFIG] ⚠ MASTER_KEY par défaut — développement uniquement.');
      return 'streetphare-dev-key-change-in-production';
    }
    return key;
  })(),

  // ── Consensus ───────────────────────────────────────────────────────
  consensusThreshold: parseInt(process.env.CONSENSUS_THRESHOLD || '3', 10),

  // ── Synchronisation ─────────────────────────────────────────────────
  syncIntervalSeconds: parseInt(process.env.SYNC_INTERVAL_SECONDS || '30', 10),

  // ── Logs ────────────────────────────────────────────────────────────
  logDir: process.env.LOG_DIR || './logs',

  // ── TTL (en minutes) ────────────────────────────────────────────────
  ttls: {
    mobileDanger: 10,   // barrage, casseurs, danger mobile
    staticDanger: 1,    // policiers, autopompes, filtre statique
    panic: 2,           // panic individuel
    collectiveDanger: 10, // danger collectif
    absoluteRgpd: 1440,  // 24h — limite RGPD absolue
  },

  // ── Panic aggrégation ───────────────────────────────────────────────
  panic: {
    proximityMeters: 50,     // 5 pings < 50m
    timeWindowMinutes: 2,    // en < 2 minutes
    threshold: 5,            // seuil de 5 pings
    autoZoneRadius: 100,     // rayon zone de danger auto-générée
  },

  /// Retourne true si ce serveur est le PRIMARY.
  get isPrimary() { return this.serverType === 'PRIMARY'; },

  /// Retourne true si ce serveur est le BACKUP.
  get isBackup() { return this.serverType === 'BACKUP'; },

  /// Résumé de la configuration pour les logs.
  summary() {
    return `StreetPhare Server v3.0 — ${this.serverType} — :${this.port} — partner: ${this.partnerUrl}`;
  },
};

module.exports = config;