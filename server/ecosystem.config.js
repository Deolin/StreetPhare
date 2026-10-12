// server/ecosystem.config.js
// ============================================================================
// Configuration PM2 — gestionnaire de processus avec redémarrage automatique.
//
// StreetPhare lance DEUX processus Node.js :
//   - streetphare-primary : serveur principal (port 3000)
//   - streetphare-backup  : serveur miroir   (port 3001)
//
// PM2 garantit :
//   - redémarrage automatique en cas de crash (uncaughtException → exit 1) ;
//   - relance au démarrage de la machine (`pm2 save` + `pm2 startup`) ;
//   - redémarrage si la mémoire dépasse 512 Mo (fuite mémoire) ;
//   - logs séparés par processus (dans server/logs/).
//
// Usage (depuis le dossier server/) :
//   npm run pm2:start    → démarre les deux processus
//   npm run pm2:stop     → arrête les deux
//   npm run pm2:restart  → redémarre
//   npm run pm2:logs     → suit les logs en direct
//   npm run pm2:status   → état des processus
//   npm run pm2:save     → sauvegarde la liste pour le boot automatique
//
// Les secrets (MASTER_KEY, JWT_SECRET, ADMIN_HASH) sont lus depuis le
// fichier `.env` (chargé par dotenv dans src/config.js). Les variables
// propres au rôle (SERVER_TYPE, PARTNER_URL) sont surchargées ici pour
// que le même `.env` puisse piloter les deux rôles.
// ============================================================================

module.exports = {
  apps: [
    {
      name: 'streetphare-primary',
      script: 'src/primary.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 20,
      restart_delay: 2000,
      kill_timeout: 10000,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        SERVER_TYPE: 'PRIMARY',
        PARTNER_URL: 'http://127.0.0.1:3001',
      },
      out_file: './logs/primary-out.log',
      error_file: './logs/primary-error.log',
      time: true,
    },
    {
      name: 'streetphare-backup',
      script: 'src/backup.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 20,
      restart_delay: 2000,
      kill_timeout: 10000,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        SERVER_TYPE: 'BACKUP',
        PARTNER_URL: 'http://127.0.0.1:3000',
      },
      out_file: './logs/backup-out.log',
      error_file: './logs/backup-error.log',
      time: true,
    },
  ],
};
