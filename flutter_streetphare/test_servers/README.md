# StreetPhare — Serveurs de test locaux

Ce dossier contient un mini-environnement Node.js/Express qui
permet de tester localement, sans déploiement cloud :

* le **basculement** (failover) entre serveur principal et
  secondaire géré par `lib/network/failover_manager.dart`,
* la **chaîne chiffrée de secours** (AES-256-CBC + HMAC-SHA256)
  compatible avec `lib/database/crypto_utils.dart`,
* le **consensus à 3 validations** attendu par les alertes,
* les routes réellement consommées par l'app
  (`/healthz`, `/v1/alerts/sync`) **et** les routes décrites
  dans la spec (`/ping`, `/alerts`, `/backup-route`).

## Fichiers

| Fichier                | Rôle                                                         |
| ---------------------- | ------------------------------------------------------------ |
| `server_primary.js`    | Serveur PRINCIPAL — port 3000                                |
| `server_secondary.js`  | Serveur SECONDAIRE (backup #1) — port 3001                   |
| `server_crypto.js`     | Module AES-CBC + HMAC-SHA256 partagé (miroir du client Dart)|
| `start_servers.js`     | Orchestrateur Node unique (`npm start`)                      |
| `start_tests.bat`      | Lance les deux serveurs dans 2 fenêtres cmd (Windows)        |
| `start_tests.sh`       | Équivalent Linux/macOS (bash)                                |
| `package.json`         | Dépendances (uniquement `express`)                           |

## Lancement

### Windows (double-clic)

Double-cliquez sur `start_tests.bat`, OU depuis un terminal :

```
test_servers\start_tests.bat
```

Deux fenêtres cmd s'ouvrent (une par serveur). Le script
s'occupe d'installer `express` au premier lancement.

### Linux / macOS

```bash
cd test_servers
chmod +x start_tests.sh
./start_tests.sh
```

### Variante multiplateforme (un seul terminal)

```bash
cd test_servers
npm start
```

## Endpoints exposés

Les deux serveurs exposent **les mêmes routes** (pour pouvoir
être le `primary` ou le `secondary` indistinctement) :

| Méthode | Route                | Description                                                    |
| ------- | -------------------- | -------------------------------------------------------------- |
| GET     | `/ping`              | Heartbeat — spec. Retourne `{status:"ok"}`.                    |
| GET     | `/healthz`           | Alias `/ping` consommé par `FailoverManager._ping()`.          |
| POST    | `/alerts`            | Reçoit une alerte. À 3 validations → `{status:"stored"}`.      |
| POST    | `/v1/alerts/sync`    | Endpoint RÉEL appelé par `FailoverManager.uploadAlerts()`.     |
| GET     | `/backup-route`      | Renvoie l'adresse **chiffrée** du prochain serveur de secours. |
| GET     | `/_debug/store`      | Dump JSON de l'état interne (alertes validées, etc.).          |

Le body accepté par `POST /alerts` (ou `/v1/alerts/sync`) peut
prendre deux formes équivalentes :

```jsonc
// 1) Format "spec" (un seul objet)
{ "id": "abc123", "confirmations": ["peerA", "peerB", "peerC"] }

// 2) Format "réel" envoyé par FailoverManager
{ "alerts": [ { "id": "abc123", "confirmations": ["..."] } ] }
```

## Tests rapides (avec curl)

```bash
# Heartbeat
curl http://localhost:3000/ping
curl http://localhost:3001/ping

# 1ère confirmation
curl -X POST http://localhost:3000/alerts \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"alert-001\",\"confirmations\":[\"u1\"]}"
# 2e confirmation
curl -X POST http://localhost:3000/alerts \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"alert-001\",\"confirmations\":[\"u2\"]}"
# 3e confirmation -> "stored"
curl -X POST http://localhost:3000/alerts \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"alert-001\",\"confirmations\":[\"u3\"]}"

# Endpoint réel /v1/alerts/sync (renvoie next_backup chiffré)
curl -X POST http://localhost:3000/v1/alerts/sync \
  -H "Content-Type: application/json" \
  -d "{\"alerts\":[{\"id\":\"alert-001\",\"confirmations\":[\"u1\",\"u2\",\"u3\"]}]}"

# Backup route
curl http://localhost:3000/backup-route
```

## Tester le failover

1. Lancez `start_tests.bat` (les 2 serveurs tournent).
2. Lancez l'app Flutter en mode debug :
   `flutter run -d windows` (ou `chrome`, `android`, etc.).
   Le `FailoverManager` initialisera le primary à
   `http://localhost:3000`.
3. Dans la console de l'app, observez les logs
   `[FailoverManager] heartbeat ok` toutes les 30 s.
4. **Tuez le serveur principal** (Ctrl+C dans sa fenêtre).
5. Attendez 3 heartbeats échoués (≈ 1 min 30 s) — ou
   réduisez `heartbeatInterval` à 5 s pour tester vite.
6. Le `FailoverManager` bascule sur
   `http://localhost:3001`, le déchiffre depuis la chaîne
   qu'il a reçue via `next_backup`, et l'upload reprend.

## Configuration côté Flutter

Toute la résolution des URL est centralisée dans :

* `lib/network/network_config.dart` — choisit automatiquement
  `localhost` (ou `10.0.2.2` pour émulateur Android) en debug,
  et `https://api.streetphare.org` en prod.
* `lib/main.dart` — appelle `NetworkConfig.*` au lieu de
  hardcoder.
* `lib/network/bootstrap.dart` — chiffre en AES l'URL du
  secondaire local en mode debug, pour amorcer la chaîne de
  secours.

Pour overrider en production :

```bash
flutter build apk \
  --dart-define=STREETPHARE_PRIMARY=https://api.streetphare.org \
  --dart-define=STREETPHARE_RELAY=wss://relay.streetphare.org/mesh \
  --dart-define=STREETPHARE_MASTER_KEY=<votre clé>
```

## Sécurité

**Ces serveurs sont UNIQUEMENT pour le développement local.**
La master-passphrase `streetphare-dev-key-CHANGE_ME_IN_PROD` est
publique, les endpoints n'ont aucune auth, le store est en RAM.
Ne JAMAIS déployer cette configuration telle quelle.
