# 📡 Tableau de bord StreetPhare — Topologie Serveurs

> Dernière mise à jour : **2026-06-11 15:27:53** — Uptime orchestrateur : **94623s**
> Fichier généré par `test_servers/start_servers_v2.js`

---

## 🖥️ Statut des Nœuds

| Serveur | Port | URL | Statut | Redémarrages |
| --- | --- | --- | --- | --- |
| ⭐ Principal | 3000 | http://localhost:3000 | ⚫ ARRÊTÉ | 0/3 |
| 🛡️ Backup    | 3001  | http://localhost:3001  | 🟢 EN LIGNE  | 1/3 |

---

## 🔗 Endpoints Disponibles

### Serveur Principal (`http://localhost:3000`)

| Méthode | Endpoint | Description |
| --- | --- | --- |
| GET | `/ping` | Heartbeat simple |
| GET | `/healthz` | Heartbeat FailoverManager |
| GET | `/status` | Topologie JSON complète |
| GET | `/v1/events` | Liste des événements (Fleurus) |
| GET | `/v1/events/:id` | Détails + QR payload |
| POST | `/v1/events/:id/route` | Calcul Safe Route (1+3 alt.) |
| POST | `/v1/reports` | Soumettre un signalement |
| GET | `/v1/reports` | Signalements actifs (votes≥3) |
| GET | `/v1/reports/stats` | Statistiques Panic Collectif |
| POST | `/v1/alerts/sync` | Sync alertes v1 + next_backup chiffré |
| GET | `/backup-route` | Adresse backup chiffrée AES |
| GET | `/_debug/reports` | Debug store v2 complet |
| POST | `/_debug/demote` | Forcer failover (test) |

### Serveur Backup (`http://localhost:3001`)

| Méthode | Endpoint | Description |
| --- | --- | --- |
| GET | `/status` | Topologie + état HeartbeatMonitor |
| POST | `/v1/events/:id/route` | Safe Route (mirror principal) |
| POST | `/v1/reports` | Signalement (mirror principal) |
| POST | `/_debug/promote` | Simuler promotion failover |
| POST | `/_debug/demote` | Arrêter ce backup |

---

## ⚙️ Règles Métier

### TTL des Signalements

| Type | TTL | Diffusé si votes ≥ |
| --- | --- | --- |
| barrage / casseurs / danger | 600 s (10 min) | 3 |
| policiers / autopompes / filtre | 60 s (1 min) | 3 |
| panic (individuel) | 120 s | — (alimente Panic Collectif) |
| danger_collectif (auto) | 600 s | 0 (toujours visible) |

### Algorithme Panic Collectif

> Si **5 requêtes `panic`** géolocalisées dans un rayon de **200 m**
> arrivent en **< 2 minutes**, le serveur génère automatiquement
> un point **Danger Collectif** centré sur le barycentre du cluster.

---

## 🧪 Tests Rapides (curl)

```bash
# Heartbeat
curl http://localhost:3000/ping
curl http://localhost:3001/healthz

# Topologie
curl http://localhost:3001/status | jq .topology_summary

# Événements
curl http://localhost:3000/v1/events
curl http://localhost:3000/v1/events/fleurus-tour

# Safe Route
curl -X POST http://localhost:3000/v1/events/fleurus-tour/route \
     -H "Content-Type: application/json" \
     -d '{"from":{"lat":50.4891,"lon":4.5452}}'

# Signalement (vote 1/3)
curl -X POST http://localhost:3000/v1/reports \
     -H "Content-Type: application/json" \
     -d '{"id":"test-001","type":"barrage","lat":50.489,"lon":4.545,"reporter_id":"dev-1"}'

# Test Failover — couper le principal
curl -X POST http://localhost:3000/_debug/demote -H "Content-Type: application/json" -d '{"reason":"test failover"}'
# → Le backup (port 3001) devrait se promouvoir en ~15s
curl http://localhost:3001/status
```

---

> ℹ️ Pour suivre en direct : `tail -f SERVER_STATUS.md`
> Orchestrateur démarré le : **2026-06-10 13:10:50**
