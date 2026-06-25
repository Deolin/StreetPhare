# Serveur StreetPhare — Dart

Serveur 100% Dart pour StreetPhare, remplaçant l'infrastructure Node.js.

## Dépendances

- `shelf` — framework HTTP
- `shelf_router` — routage HTTP
- `shelf_web_socket` + `web_socket_channel` — WebSocket mesh
- `cryptography` — AES-256-CBC + HMAC-SHA256
- `hive_ce` — stockage persistant
- `logging` — logs structurés

## Installation

```bash
cd server_dart
dart pub get
```

## Lancement

```bash
# Serveur principal (port 3000)
dart run bin/server.dart

# Serveur backup (port 3001)
ROLE=backup PORT=3001 dart run bin/server.dart
```

## Compilation native

```bash
# Windows (.exe)
dart compile exe bin/server.dart -o build/server.exe

# Linux
dart compile exe bin/server.dart -o build/server

# macOS
dart compile exe bin/server.dart -o build/server
```

L'exécutable est autonome — aucun runtime Dart requis.

## Endpoints HTTP

| Méthode | Route                 | Description           |
|---------|----------------------|-----------------------|
| GET     | /ping                | Heartbeat             |
| GET     | /healthz             | Healthcheck failover  |
| GET     | /status              | Topologie complète    |
| GET     | /api/version/check   | Kill Switch version   |
| GET     | /v1/events           | Catalogue événements  |
| GET     | /v1/events/:id       | Détail événement + QR |
| POST    | /v1/events/:id/route | Calcul Safe Route     |
| POST    | /v1/reports          | Signalement danger    |
| GET     | /v1/reports          | Liste signalements    |
| POST    | /v1/panic            | Alerte PANIC          |

## WebSocket

| Route  | Description                     |
|--------|---------------------------------|
| /mesh  | Relais maillage P2P (propagation alertes) |
| /admin | Dashboard administrateur (validation signalements) |

## Cryptographie

Le module `lib/crypto_utils.dart` implémente AES-256-CBC + HMAC-SHA256 en stricte compatibilité avec le client Flutter (`lib/database/crypto_utils.dart`).

Format : `base64Url( nonce(16) || ciphertext || mac(32) )`

## Variables d'environnement

| Variable               | Défaut          | Description                |
|------------------------|-----------------|----------------------------|
| PORT                   | 3000            | Port d'écoute              |
| ROLE                   | primary         | primary ou backup          |
| PRIMARY_URL            | <http://127.0.0.1:3000> | URL du serveur principal |
| STREETPHARE_MASTER_KEY | clé de dev      | Passphrase AES-256-CBC     |
