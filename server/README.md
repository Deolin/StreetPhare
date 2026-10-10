# Serveur StreetPhare — Node.js / Express

> **Stack** : Node.js + Express 4 (v3.0.0)
> **Rôle** : infrastructure serveur **optionnelle** (le mesh P2P BLE/Wi-Fi Direct est prioritaire).

Le serveur joue trois rôles :
1. **Relais WebSocket** `/mesh` — propagation des alertes entre clients hors portée BLE.
2. **API REST** `/api/*` — signalements, événements, PANIC, sync.
3. **Failover** Primary ↔ Backup — haute disponibilité derrière Caddy.

---

## Architecture

```text
[Caddy — TLS/HSTS]
    ├── :443   → 127.0.0.1:3000  (Primary)
    ├── :3001  → 127.0.0.1:3001  (Backup)
    └── :4000  → 127.0.0.1:4000  (Dashboard admin)

Primary (3000)  ⇄  Sync HTTP toutes les 30 s  ⇄  Backup (3001)
```

### Fichiers principaux

| Fichier | Rôle |
|---|---|
| `src/primary.js` | Serveur principal (Express + WebSocket + API) |
| `src/backup.js` | Serveur de secours (failover) |
| `src/sync.js` | Synchronisation Primary ↔ Backup |
| `src/store.js` | Stockage en mémoire + persistance (`data/store.json`) |
| `src/config.js` | Configuration centralisée (.env) + garde-fous production |
| `src/middleware/auth.js` | Authentification JWT + RBAC |
| `src/routes/api.js` | Routes REST + WebSocket `/mesh` et `/admin` |
| `scripts/build-sea.js` | Build Single Executable (Node SEA) |

---

## Installation & lancement

```bash
cd server
cp .env.example .env      # renseignez MASTER_KEY, JWT_SECRET, ADMIN_HASH
npm install

npm run dev:primary       # Primary  sur :3000
npm run dev:backup        # Backup   sur :3001
```

> ⚠️ **Production** : `config.js` refuse de démarrer avec les clés par défaut.
> Générez des secrets forts :
> ```bash
> openssl rand -hex 32                       # MASTER_KEY / JWT_SECRET
> node -e "require('bcryptjs').hash('motdepasse', 12).then(console.log)"   # ADMIN_HASH
> ```

---

## Endpoints HTTP

| Méthode | Route | Description |
|---|---|---|
| GET | `/api/ping` | Heartbeat (utilisé par le failover client) |
| GET | `/healthz` | Healthcheck failover |
| GET | `/status` | Topologie complète |
| GET | `/api/version/check` | Kill Switch version |
| GET | `/v1/events` | Catalogue événements |
| GET | `/v1/events/:id` | Détail événement + QR |
| POST | `/v1/events/:id/route` | Calcul Safe Route |
| POST | `/v1/reports` | Signalement danger |
| GET | `/v1/reports` | Liste signalements |
| POST | `/v1/panic` | Alerte PANIC |

## WebSocket

| Route | Description |
|---|---|
| `/mesh` | Relais maillage P2P (propagation des alertes) |
| `/admin` | Dashboard administrateur (validation des signalements) |

---

## Build autonome (Node SEA)

```bash
npm run build:all          # produit streetphare-primary.exe / -backup.exe
```

---

## Configuration (.env)

| Variable | Défaut | Description |
|---|---|---|
| `SERVER_TYPE` | `PRIMARY` | `PRIMARY` ou `BACKUP` |
| `SERVER_HOST` / `SERVER_PORT` | `0.0.0.0` / `3000` | Écoute HTTP |
| `PARTNER_URL` | `http://127.0.0.1:3001` | URL du serveur partenaire |
| `MASTER_KEY` | *(dev)* | Clé AES-256-CBC (partagée Primary/Backup) |
| `JWT_SECRET` | *(dev)* | Secret JWT (HS256, min 32 caractères) |
| `ADMIN_HASH` | *(dev)* | Hash bcrypt du mot de passe admin (12 rounds) |
| `CONSENSUS_THRESHOLD` | `3` | Votes requis pour valider un signalement |
| `SYNC_INTERVAL_SECONDS` | `30` | Intervalle de synchronisation |

> 🔐 `MASTER_KEY`, `JWT_SECRET` et `ADMIN_HASH` ne sont **jamais** versionnés
> (voir `.gitignore`). Seul `.env.example` sert de modèle.

---

*Licence GPLv3 — voir `../LICENSE`.*
