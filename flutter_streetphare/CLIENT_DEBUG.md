# 🐛 Tableau de bord de Débogage Client - StreetPhare

> Dernière mise à jour : **2026-06-11 13:19:24** (heure locale). Ce fichier est généré par `lib/debug/client_debug_logger.dart` uniquement en mode `kDebugMode`.

---

## 🎯 Statut Global

| Plateforme | État | Serveur Principal Courant |
| --- | --- | --- |
| windows | 🔁 **Basculement effectué** | `http://localhost:3001` |

## 🔐 Chaîne de Secours (déchiffrée en mémoire)

| Position | Adresse (en clair) | Rôle |
| --- | --- | --- |
| ⭐ 0 (Principal) | `http://localhost:3001` | 🟢 **Actif** |
| 1 | `http://localhost:3001` | 🟡 En veille |
| 2 | `https://backup1.streetphare.local` | 🟡 En veille |

## 🔁 Étapes de Basculement (Décisions Client)

| Heure | Étape | Détail |
| --- | --- | --- |
| 13:08:54 | Basculement réussi | Nouveau principal = `http://localhost:3001`. L'ancien `http://localhost:3000` est marqué DÉFAILLANT pour la session. |
| 13:07:24 | Bootstrap terminé | Principal verrouillé sur `http://localhost:3000`. 2 serveur(s) de secours déchiffré(s). |

## 📜 Journal Temps Réel (Debug Client)

| Heure | Niveau | Évènement | Détails |
| --- | --- | --- | --- |
| 13:06:27 | 🟢 INFO | Logger client initialisé | windows |
| 13:06:27 | 🚀 INFO | Démarrage app | NetworkConfig{debug=true loopback=localhost primary=http://localhost:3000 secondary=http://localhost:3001 relay=ws://localhost:3000/mesh} |
| 13:07:24 | 🔓 DECRYPT | Adresse de backup déchiffrée | `-ZQcx9Ar…zupeA=` → `http://localhost:3001` |
| 13:07:24 | 🔓 DECRYPT | Adresse de backup déchiffrée | `yJRLlpOb…jQEHcl` → `https://backup1.streetphare.local` |
| 13:07:24 | 🧭 BOOT | Bootstrap réseau | Principal=http://localhost:3000, chaîne de secours=2 entrée(s) |
| 13:07:54 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 13:08:24 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 13:08:54 | ❌ PING | Heartbeat KO | http://localhost:3000 |
| 13:08:54 | 💀 DEAD | Serveur marqué défaillant | http://localhost:3000 (plus jamais retenté pour cette session) |
| 13:08:54 | 🔁 FAILOVER | Basculement réussi | http://localhost:3000 → http://localhost:3001 |
| 13:09:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:09:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:10:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:10:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:11:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:11:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:12:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:12:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:13:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:13:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:14:25 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:14:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:15:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:15:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:16:25 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:16:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:17:25 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:17:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:18:27 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:18:54 | 💓 PING | Heartbeat OK | http://localhost:3001 |
| 13:19:24 | 💓 PING | Heartbeat OK | http://localhost:3001 |

---

> ℹ️ Pour suivre en direct : `tail -f CLIENT_DEBUG.md` (le fichier est réécrit à chaque évènement).

