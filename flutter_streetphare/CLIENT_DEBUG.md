# 🐛 Tableau de bord de Débogage Client - StreetPhare

> Dernière mise à jour : **2026-06-10 10:52:06** (heure locale). Ce fichier est généré par `lib/debug/client_debug_logger.dart` uniquement en mode `kDebugMode`.

---

## 🎯 Statut Global

| Plateforme | État | Serveur Principal Courant |
| --- | --- | --- |
| windows | 🛑 **Mode dégradé** | `http://localhost:3000` |

## 🔐 Chaîne de Secours (déchiffrée en mémoire)

| Position | Adresse (en clair) | Rôle |
| --- | --- | --- |
| ⭐ 0 (Principal) | `http://localhost:3000` | 🟢 **Actif** |
| 1 | `http://localhost:3001` | 🟡 En veille |
| 2 | `https://backup1.streetphare.local` | 🟡 En veille |

## 🔁 Étapes de Basculement (Décisions Client)

| Heure | Étape | Détail |
| --- | --- | --- |
| 10:52:06 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:51:36 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:51:06 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:50:36 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:50:06 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:49:36 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:49:08 | Basculement impossible | Tous les secours sont injoignables. L'app reste connectée à `http://localhost:3000` (marqué défaillant) jusqu'à relance de la session. |
| 10:47:36 | Bootstrap terminé | Principal verrouillé sur `http://localhost:3000`. 2 serveur(s) de secours déchiffré(s). |

## 📜 Journal Temps Réel (Debug Client)

| Heure | Niveau | Évènement | Détails |
| --- | --- | --- | --- |
| 10:47:36 | 🟢 INFO | Logger client initialisé | windows |
| 10:47:36 | 🚀 INFO | Démarrage app | NetworkConfig{debug=true loopback=localhost primary=http://localhost:3000 secondary=http://localhost:3001 relay=ws://localhost:3000/mesh} |
| 10:47:36 | 🔓 DECRYPT | Adresse de backup déchiffrée | `UBuHcmGf…AmnSU=` → `http://localhost:3001` |
| 10:47:36 | 🔓 DECRYPT | Adresse de backup déchiffrée | `u7qj6Y-M…3fjIAH` → `https://backup1.streetphare.local` |
| 10:47:36 | 🧭 BOOT | Bootstrap réseau | Principal=http://localhost:3000, chaîne de secours=2 entrée(s) |
| 10:48:06 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:48:36 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:49:06 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:49:06 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:49:08 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3001 (plus jamais retenté pour cette session) |
| 10:49:08 | 💀 DEAD | Serveur marqué défaillant | https://backup1.streetphare.local (plus jamais retenté pour cette session) |
| 10:49:08 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |
| 10:49:36 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:49:36 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:49:36 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |
| 10:50:06 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:50:06 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:50:06 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |
| 10:50:36 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:50:36 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:50:36 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |
| 10:51:06 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:51:06 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:51:06 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |
| 10:51:36 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:51:36 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:51:36 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |
| 10:52:06 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 10:52:06 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 10:52:06 | 🛑 FAILOVER | Basculement impossible | Aucun serveur de secours disponible (perdu depuis `http://localhost:3000`) |

---

> ℹ️ Pour suivre en direct : `tail -f CLIENT_DEBUG.md` (le fichier est réécrit à chaque évènement).

