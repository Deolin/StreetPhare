# 📡 Tableau de bord de Débogage - StreetPhare

> Dernière mise à jour : **2026-06-11 15:49:21** (UTC serveur). Ce fichier est généré automatiquement par `test_servers/logger.js`.

---

## 🖥️ Statut des Nœuds

| Serveur | URL | Statut | Rôle Actuel |
| --- | --- | --- | --- |
| Principal | http://localhost:3001 | 🟢 EN LIGNE | ⚪ Promu Principal (failover) |

## ⚡ Résumé Express

- 💓 Pings reçus : **278**
- 📨 Alertes connues : **0** (✅ validées : **0**)
- 🕒 Dernier ping : **2026-06-11 15:49:21**

## 🌐 Flux du Consensus (Dernières Alertes)

| ID Alerte | Type | Votes (Validations) | Statut Réseau |
| --- | --- | --- | --- |
| — | — | 0 / 3 | ⚪ Aucune alerte reçue pour l'instant |

## 📜 Journal d'Évènements (Flux Temps Réel)

| Heure | Niveau | Évènement | Détails |
| --- | --- | --- | --- |
| 15:46:31 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:46:26 | 🚨 FAILOVER | Failover automatique déclenché | Principal http://localhost:3000 hors ligne — Backup promu Principal |
| 15:46:26 | 🚀 PROMOTION | Promotion | Devient Principal |
| 15:46:26 | 🔁 FAILOVER | Basculement | Principal → Backup |
| 15:46:26 | 🔴 OFFLINE | Hors ligne | PANNE DÉTECTÉE après 3 échecs |
| 15:46:26 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:46:21 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #2 |
| 15:46:21 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:46:16 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #1 |
| 15:28:08 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:28:03 | 🚨 FAILOVER | Failover automatique déclenché | Principal http://localhost:3000 hors ligne — Backup promu Principal |
| 15:28:03 | 🚀 PROMOTION | Promotion | Devient Principal |
| 15:28:03 | 🧭 ROLE | Changement de rôle | En veille → Promu Principal (failover) |
| 15:28:03 | 🔁 FAILOVER | Basculement | Principal → Backup |
| 15:28:03 | 🔴 OFFLINE | Hors ligne | PANNE DÉTECTÉE après 3 échecs |
| 15:28:03 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:27:58 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #2 |
| 15:27:58 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:27:53 | 🔴 OFFLINE | Hors ligne | Heartbeat échoué #1 |
| 15:26:13 | 💓 PING | Ping reçu | BackupMonitor(:3001→:3000) → http://localhost:3000 |
| 15:26:13 | 🟢 INFO | Démarrage | Backup 1 en ligne sur http://localhost:3001 |

---

> ℹ️ Pour suivre en direct : `tail -f SERVER_STATUS.md` (le fichier est réécrit à chaque évènement).
