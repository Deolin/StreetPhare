# 📡 Tableau de bord de Débogage - StreetPhare

> Dernière mise à jour : **2026-06-16 16:54:50** (UTC serveur). Ce fichier est généré automatiquement par `test_servers/logger.js`.

---

## 🖥️ Statut des Nœuds

| Serveur | URL | Statut | Rôle Actuel |
| --- | --- | --- | --- |
| Principal | http://localhost:3001 | 🟢 EN LIGNE | ⚪ Promu Principal (failover) |

## ⚡ Résumé Express

- 💓 Pings reçus : **172**
- 📨 Alertes connues : **1** (✅ validées : **0**)
- 🕒 Dernier ping : **2026-06-16 16:54:50**

## 🌐 Flux du Consensus (Dernières Alertes)

| ID Alerte | Type | Votes (Validations) | Statut Réseau |
| --- | --- | --- | --- |
| #density_n0Tq1hZPzetSOr4v | Density | 0 / 3 | ⏳ En attente de consensus (P2P) |

## 📜 Journal d'Évènements (Flux Temps Réel)

| Heure | Niveau | Évènement | Détails |
| --- | --- | --- | --- |
| 16:51:50 | 💓 PING | Ping reçu | GET /healthz |
| 16:51:48 | 🚨 FAILOVER | Failover automatique déclenché | Principal http://localhost:3000 hors ligne — Backup promu Principal |
| 16:51:48 | 🚀 PROMOTION | Promotion | Devient Principal |
| 16:51:48 | 🔁 FAILOVER | Basculement | Principal → Backup |
| 16:51:48 | 🔴 OFFLINE | Hors ligne | PANNE DÉTECTÉE après 3 échecs |
| 16:51:45 | 💓 PING | Ping reçu | GET /healthz |
| 16:51:43 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #2 |
| 16:51:40 | 💓 PING | Ping reçu | GET /healthz |
| 16:51:38 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #1 |
| 16:50:42 | 🔄 SYNC | Sync alertes (backup) | 1 alerte(s) |
| 16:50:42 | 📨 ALERT | Alerte reçue | #density_n0Tq1hZPzetSOr4v (Density) — 0/3 |
| 16:50:42 | 💓 PING | Ping reçu | GET /healthz |
| 16:50:38 | 🚨 FAILOVER | Failover automatique déclenché | Principal http://localhost:3000 hors ligne — Backup promu Principal |
| 16:50:38 | 🚀 PROMOTION | Promotion | Devient Principal |
| 16:50:38 | 🧭 ROLE | Changement de rôle | En veille → Promu Principal (failover) |
| 16:50:38 | 🔁 FAILOVER | Basculement | Principal → Backup |
| 16:50:38 | 🔴 OFFLINE | Hors ligne | PANNE DÉTECTÉE après 3 échecs |
| 16:50:38 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 16:50:33 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #2 |
| 16:50:33 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 16:50:28 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #1 |
| 16:44:47 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 16:44:47 | 🟢 INFO | Démarrage | Backup 1 en ligne sur http://localhost:3001 |

---

> ℹ️ Pour suivre en direct : `tail -f SERVER_STATUS.md` (le fichier est réécrit à chaque évènement).
