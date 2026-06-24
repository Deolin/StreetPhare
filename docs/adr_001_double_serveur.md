# ADR-001 — Choix du Serveur : Dart vs Node.js

> **Date** : 24/06/2026
> **Statut** : Proposé
> **Version** : 2.2.0+1

## Contexte

Le projet StreetPhare maintient actuellement **deux implémentations serveur** :

### Serveur Dart (`server_dart/`)

- **4 fichiers Dart** : `bin/server.dart` (1245 lignes, monolithique), `bin/server_gui.dart` (CLI interactive), `lib/crypto_utils.dart`, `test/crypto_compatibility_test.dart`
- Stockage **volatil** (tout en mémoire : `_reports` List, `_events` List, `_meshClients` Set, `_adminClients` Set)
- 16 endpoints HTTP REST + 2 endpoints WebSocket (`/mesh`, `/admin`)
- RBAC simple (admin/moderator), tokens session en mémoire
- Dépendances inutilisées : `hive_ce`, `cryptography` (déclarées dans pubspec.yaml mais jamais importées)
- Dashboard web intégré (fichiers statiques shelf_static)

### Serveur Node.js (référencé dans `docs/ARCHITECT.md`)

- Primary (port 3000) + Secondary (port 3001)
- Persistance MongoDB/Redis
- Dashboard admin v2
- Crypto compatible Dart (AES-256-CBC + HMAC-SHA256)

## Problème

1. **Maintenance double** : deux codebases pour la même fonction, risque de divergence
2. **Serveur Dart non viable en production** : stockage volatil, RBAC minimal, pas de persistance
3. **Dépendances inutilisées** : `hive_ce` et `cryptography` déclarées mais non utilisées dans le serveur Dart
4. **Code mort suspecté** : le serveur Dart semble être un prototype initial jamais nettoyé

## Décision

**Archiver `server_dart/`** et standardiser sur le serveur Node.js pour tout l'infrastructure backend.

## Conséquences

- **Suppression** de `server_dart/` du repository (après archivage dans une branche `archive/server_dart`)
- **Nettoyage** du `package.json` racine (suppression des scripts liés au serveur Dart)
- **Mise à jour** de la documentation (`ARCHITECT.md`, `plan_du_projet.md`)
- **Gain** : 4 fichiers Dart, 1 pubspec.yaml, 1 pubspec.lock en moins à maintenir

## Alternatives considérées

1. **Garder les deux serveurs** → Rejeté : coût de maintenance trop élevé
2. **Migrer tout en Dart (Shelf)** → Rejeté : écosystème Node.js plus mature pour le backend (middleware, sécurité, déploiement)
3. **Garder le serveur Dart pour les tests locaux uniquement** → Acceptable à court terme, mais le serveur Node.js peut aussi tourner en local

## Actions

- [ ] Créer une branche `archive/server_dart` avec le contenu actuel de `server_dart/`
- [ ] Supprimer `server_dart/` de `main`
- [ ] Supprimer `package.json` racine (s'il ne sert qu'au serveur Dart)
- [ ] Mettre à jour `docs/ARCHITECT.md` pour ne référencer que le serveur Node.js
- [ ] Mettre à jour `docs/plan_du_projet.md`
