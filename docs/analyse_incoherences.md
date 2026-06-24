# StreetPhare — Analyse des Incohérences

> **Version** : 2.2.0+1  
> **Date du document** : 22/06/2026  

---

## 1. Incohérences Architecturales

### 1.1 Double Implémentation Serveur (Dart vs Node.js)

**Problème** : Deux serveurs font double emploi.

- `server/` : Serveur Dart autonome (HTTP + WebSocket + Admin Dashboard + QR + Tile Proxy)
- `test_servers/` : Serveurs Node.js (Primary + Secondary + Admin Dashboard + Sandbox + Crypto)

**Impact** : Maintenance en double, risque de divergence fonctionnelle, code mort probable côté Dart.
**Question** : Le serveur Dart est-il encore utilisé ou a-t-il été remplacé par les serveurs Node.js ?

### 1.2 Deux Dashboards Admin

**Problème** : Trois dashboards admin coexistent.

- `lib/features/admin/` : Dashboard intégré dans l'app Flutter
- `server/lib/web/admin_dashboard.dart` : Dashboard web côté Dart
- `test_servers/admin_dashboard_v2.js` : Dashboard web Node.js

**Impact** : Triple maintenance, incohérence visuelle et fonctionnelle probable.

### 1.3 Redondance Event Manager

**Problème** : La gestion d'événements est implémentée à trois endroits.

- `lib/features/events/domain/models/event_model.dart` : Modèle Flutter
- `lib/features/events/presentation/event_manager.dart` : Manager Flutter
- `server/lib/event_manager.dart` : Manager côté serveur Dart
- `test_servers/server_primary_v2.js` : Gestion événements côté Node.js

**Impact** : Risque de divergence des règles de gestion (validation, TTL, consensus).

### 1.4 Redondance Crypto

**Problème** : Le chiffrement est implémenté deux fois.

- `lib/database/crypto_utils.dart` : Dart (AES-256-CBC + HMAC-SHA256)
- `test_servers/server_crypto.js` : Node.js (même algo, "compatible Dart")

**Impact** : Risque de désynchronisation si l'un évolue sans l'autre.

---

## 2. Incohérences de Structure

### 2.1 Features incomplètes

**Problème** : Des dossiers features existent mais semblent vides ou squelettiques.

- `lib/features/panic/` : Présent dans l'arborescence, mais aucun détail d'implémentation confirmé
- `lib/features/alerts/` : Structure domain/presentation listée mais fichiers non tous vérifiés
- `lib/features/splash/` : Présent mais contenu minimal

### 2.2 Fichiers Core non vérifiés

**Problème** : Le dossier `lib/core/` est référencé mais le contenu exact (theme, i18n, router, auth, di, config, utils) n'a pas été intégralement lu. L'existence réelle de ces fichiers doit être confirmée.

### 2.3 Scripts shell vs PowerShell

**Problème** : Mix de scripts shell (`.sh`) et PowerShell (`.ps1`).

- `scripts/test_orchestrator.ps1` : PowerShell (Windows)
- `scripts/build_runner.sh`, `scripts/test_unit.sh`, etc. : Shell (Linux/macOS)
- `test_servers/start_tests.bat` : Batch Windows
- `test_servers/start_tests.sh` : Shell

**Impact** : Risque d'incompatibilité selon l'environnement. Les scripts `.sh` sont inutilisables nativement sous Windows.

### 2.4 Deux package.json

**Problème** : Deux fichiers de configuration Node.js coexistent.

- `package.json` à la racine
- `test_servers/package.json`

**Impact** : Confusion sur le point d'entrée npm, dépendances potentiellement en conflit.

---

## 3. Incohérences de Données

### 3.1 Modèles Alert divergents

**Problème** : Le modèle Alert existe en plusieurs versions.

- `lib/database/alert_model.dart` : Modèle Hive persistant
- `lib/features/alerts/domain/models/` : Modèle domaine
- `server/lib/models/alert.dart` : Modèle côté serveur Dart
- Formats JSON dans `server_primary_v2.js` et `server_secondary_v2.js`

**Risque** : Sérialisation/désérialisation incompatible entre client et serveur.

### 3.2 Modèles Event divergents

**Problème** : Même situation pour les événements.

- `lib/features/events/domain/models/event_model.dart` : 528 lignes
- `server/lib/models/event.dart` : 293 lignes

**Risque** : Les champs ne sont probablement pas synchronisés (528 vs 293 lignes).

### 3.3 Coordonnées GPS en dur (Fixtures Fleurus)

**Problème** : `event_manager.dart` contient des fixtures Fleurus avec coordonnées GPS réelles codées en dur. Ces données de test sont mélangées au code de production.

**Risque** : Données de test visibles en production, maintenance compliquée.

---

## 4. Incohérences UI/UX

### 4.1 Site Vitrine vs App

**Problème** : Le site vitrine (`web_vitrine/`) présente un produit fini et poli avec landing page complète, multilingue, sections marketing, etc. L'état réel de l'application Flutter (version 2.2.0+1, non publiée sur les stores) ne correspond pas nécessairement à cette maturité affichée.

**Risque** : Décalage entre la communication marketing et la réalité technique.

### 4.2 PWA vs App Native

**Problème** : `web/index.html` configure une PWA Flutter, mais les builds natifs Android/iOS existent aussi. Quelle est la cible prioritaire ?

---

## 5. Incohérences de Qualité

### 5.1 Couverture de Tests Insuffisante

**Problème** : Un seul fichier de test unitaire.

- `test/streetphare_core_test.dart` : 52 lignes seulement

**Écart** : Pour un projet de cette ampleur (52+ fichiers Dart), un seul fichier de test est très insuffisant.

### 5.2 Absence de CI/CD

**Problème** : Aucune configuration CI/CD trouvée (pas de `.github/workflows/`, `.gitlab-ci.yml`, Jenkinsfile, etc.).

### 5.3 Absence de Documentation Technique

**Problème** : Le dossier `docs/` existe mais avant la création de ce fichier, il ne contenait aucune documentation technique. La documentation se limitait au site vitrine marketing.

### 5.4 Fichiers de Résultats de Debug

**Problème** : `results_clientdebug.txt` et `results_kdebug.txt` sont à la racine du projet. Ce sont des artefacts de debug qui devraient être dans `.gitignore` ou dans un dossier dédié.

### 5.5 Fichiers .metadata et .iml

**Problème** : `.metadata` et `flutter_streetphare.iml` sont présents. `.metadata` devrait être dans `.gitignore` (généré par Flutter). Le `.iml` est un fichier IntelliJ/Android Studio.

---

## 6. Incohérences de Configuration

### 6.1 SDK Dart Version

**Problème** : `pubspec.yaml` spécifie `sdk: >=3.12.0 <4.0.0`.

- Dart 3.12 n'existe pas (versions stables : 3.5, 3.6, 3.7...). La contrainte est probablement invalide ou fait référence à une version future.

### 6.2 package.json Version

**Problème** : Le `package.json` racine existe mais son contenu exact et sa version ne sont pas corrélés avec `test_servers/package.json`.

### 6.3 Fichiers d'Icônes

**Problème** : `flutter_launcher_icons.yaml` est configuré mais les icônes générées dans `assets/icon/` n'ont pas été vérifiées.

---

## 7. Incohérences Git

### 7.1 Dernier Commit

**Problème** : Dernier commit `4fcc5e23d91e7a8ba82132a5e8141897e32acd04` sur `main`. Aucune information sur les branches actives, les PRs en cours, ou le rythme de développement.

### 7.2 Fichiers Potentiellement Non Commit

**Problème** : `results_clientdebug.txt`, `results_kdebug.txt`, `.metadata` sont présents. Si non ignorés, ils polluent le repository.

---

## 8. Synthèse des Risques

| Risque                      | Gravité    | Description                               |
|-----------------------------|------------|-------------------------------------------|
| Double serveur Dart/Node.js | 🔴 Élevée  | Maintenance double, code mort probable    |
| Modèles divergents          | 🔴 Élevée  | Risque de bugs de sérialisation           |
| Tests inexistants           | 🔴 Élevée  | Aucune garantie de non-régression         |
| SDK Dart invalide           | 🟠 Moyenne | Build potentiellement cassé               |
| Dashboards triplés          | 🟠 Moyenne | Confusion utilisateur, maintenance lourde |
| Docs absentes               | 🟠 Moyenne | Onboarding développeur impossible         |
| Scripts multi-OS            | 🟡 Faible  | Incompatibilité selon environnement       |
| Debug files racine          | 🟡 Faible  | Pollution du repo                         |
| Fixtures en prod            | 🟡 Faible  | Données de test visibles                  |

---

## 9. Recommandations Immédiates

1. **Clarifier le choix serveur** : Dart OU Node.js, pas les deux
2. **Unifier les modèles** : Source unique de vérité pour Alert et Event
3. **Ajouter une CI/CD** : GitHub Actions minimum
4. **Compléter les tests** : Objectif >60% de couverture
5. **Corriger le SDK Dart** : Utiliser une contrainte valide (`>=3.6.0 <4.0.0`)
6. **Nettoyer le repo** : Déplacer les fichiers debug, mettre à jour `.gitignore`
7. **Documenter** : README technique, architecture, guide de contribution
8. **Externaliser les fixtures** : Dans des fichiers JSON séparés
