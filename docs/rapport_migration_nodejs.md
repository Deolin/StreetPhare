# Rapport de Migration — Nettoyage des Artefacts Node.js Orphelins

> **Date** : 24/06/2026
> **Version** : 2.2.0+1

## Contexte

Le projet StreetPhare référençait une infrastructure serveur Node.js (`server/`) qui n'existe plus physiquement sur le disque. Les artefacts résiduels (scripts npm, `node_modules/`, `package-lock.json`) étaient orphelins et généraient de la confusion.

## Éléments nettoyés

| Artefact | Action | Raison |
|----------|--------|--------|
| `node_modules/` (12 Mo) | Supprimé | Orphelin — le dossier `server/` cible n'existe plus |
| `package-lock.json` | Supprimé | Orphelin — aucune dépendance de production restante |
| `package.json` | Simplifié | Suppression de `express`, `ws`, `eslint-config-prettier`, et des 11 scripts npm morts. Conservé `prettier` en devDep |
| `scripts/orchestrate.js` | Nettoyé | Suppression des commandes `start`/`all` et de la fonction `node()` qui référençait `server/launch_all.js` |
| `.gitignore` | Mis à jour | Ajout de `node_modules/` et `package-lock.json` ; suppression des 4 entrées `server/` orphelines |

## État après migration

- **`package.json`** : contient uniquement `prettier: 3.8.4` en devDep
- **`scripts/orchestrate.js`** : 6 commandes conservées (`analyze`, `format`, `test`, `lint`, `ci`), les commandes serveur supprimées
- **`.gitignore`** : couvre désormais `node_modules/` et `package-lock.json`
- **`server_dart/`** : conservé en l'état (pas de dépendant dans le code Flutter, ADR-001 documente l'avenir de ce module)
- **`.github/workflows/`** : 4 workflows CI/CD existent (build.yml, ci.yml, flutter.yml, static.yml) — tous ciblent exclusivement l'app Flutter, aucun ne référence le serveur Dart ou Node.js

## Ce qui n'a PAS été fait

| Élément | Raison |
|---------|--------|
| Suppression de `server_dart/` | Conservé à la demande de l'utilisateur — le module est totalement isolé, sans dépendant |
| Suppression de `package.json` | Conservé car `prettier` est utilisé pour le formatage (`.prettierrc`, `.prettierignore` présents) |
| Merge des workflows CI dupliqués | Hors scope de cette migration — `ci.yml` et `flutter.yml` font essentiellement la même chose, à traiter en Phase 3 |
