# StreetPhare — Plan des Actions Restantes

> **Version** : 2.2.0+1  
> **Date du document** : 22/06/2026  

---

## Objectif

Ce document liste les actions à réaliser pour que le projet StreetPhare corresponde aux exigences fonctionnelles, techniques et de qualité énoncées dans sa vision.

---

## Phase 1 — Nettoyage et Stabilisation (Priorité 🔴)

### 1.1 Résoudre l'ambiguïté du serveur

- [ ] Décider entre serveur Dart (`server/`) et serveurs Node.js (`test_servers/`)
- [ ] Supprimer la solution non retenue
- [ ] Si Node.js retenu : renommer `test_servers/` en `servers/`, déplacer au niveau `server/`
- [ ] Si Dart retenu : porter les fonctionnalités manquantes (sandbox, failover, LiveMonitor)

### 1.2 Corriger la contrainte SDK Dart

- [ ] Remplacer `sdk: >=3.12.0 <4.0.0` par `sdk: >=3.6.0 <4.0.0` dans `pubspec.yaml`
- [ ] Vérifier la compatibilité de toutes les dépendances
- [ ] Lancer `dart pub outdated` et mettre à jour si nécessaire

### 1.3 Nettoyer le repository

- [ ] Déplacer `results_clientdebug.txt` et `results_kdebug.txt` vers `status/` ou `.gitignore`
- [ ] Ajouter `.metadata` au `.gitignore`
- [ ] Ajouter `*.iml` au `.gitignore`
- [ ] Supprimer `flutter_streetphare.iml` du repo
- [ ] Clarifier les deux `package.json` (fusion ou documentation du rôle de chacun)

---

## Phase 2 — Unification des Modèles (Priorité 🔴)

### 2.1 Modèle Alert unique

- [ ] Comparer `lib/database/alert_model.dart`, `lib/features/alerts/domain/models/`, `server/lib/models/alert.dart`
- [ ] Définir un modèle canonique (JSON Schema ou modèle Dart partagé)
- [ ] Aligner les sérialisations JSON entre client et serveur
- [ ] Documenter les champs obligatoires et optionnels

### 2.2 Modèle Event unique

- [ ] Comparer `lib/features/events/domain/models/event_model.dart` et `server/lib/models/event.dart`
- [ ] Réconcilier les 528 lignes (Flutter) et 293 lignes (Serveur)
- [ ] Identifier les champs manquants de part et d'autre
- [ ] Créer un modèle partagé

### 2.3 Crypto unifié

- [ ] Comparer `lib/database/crypto_utils.dart` et `test_servers/server_crypto.js`
- [ ] Ajouter des tests de compatibilité cross-plateforme (Dart ↔ Node.js)
- [ ] Documenter l'algorithme, les paramètres (IV, sel, iterations)

---

## Phase 3 — Tests (Priorité 🔴)

### 3.1 Augmenter la couverture de tests

- [ ] Tests unitaires pour `lib/core/` : theme, router, auth, utils
- [ ] Tests unitaires pour `lib/database/` : alert_model, crypto_utils, hive_alert_database
- [ ] Tests unitaires pour `lib/network/` : p2p_alert_manager, websocket_client, relay_client
- [ ] Tests unitaires pour `lib/features/alerts/` : domain models, business logic
- [ ] Tests unitaires pour `lib/features/events/` : event_model, event_manager
- [ ] Tests d'intégration : client ↔ serveur (WebSocket mesh relay)
- [ ] Tests end-to-end : scénario complet (création alerte → propagation → réception)
- [ ] Objectif cible : >60% de couverture de code

### 3.2 Tests de sécurité

- [ ] Tests de chiffrement/déchiffrement inter-plateforme
- [ ] Tests de consensus (≥3 confirmations)
- [ ] Tests de TTL (expiration automatique)
- [ ] Tests de Kill Switch
- [ ] Tests d'anonymat (rotation UUID)

---

## Phase 4 — CI/CD et Qualité (Priorité 🟠)

### 4.1 Mise en place CI/CD

- [ ] Créer `.github/workflows/ci.yml` pour GitHub Actions
  - [ ] `dart analyze` (analyse statique)
  - [ ] `flutter test` (tests unitaires)
  - [ ] `dart format --output=none --set-exit-if-changed .` (format check)
- [ ] Ajouter workflow de build (Android APK, iOS, Web)
- [ ] Ajouter badge de statut dans le README

### 4.2 Qualité de code

- [ ] Vérifier `analysis_options.yaml` (activer les règles strictes Dart)
- [ ] Lancer `dart fix --apply` sur tout le projet
- [ ] Configurer un linter cohérent
- [ ] Ajouter pre-commit hooks (format, analyze, test)

---

## Phase 5 — Documentation (Priorité 🟠)

### 5.1 Documentation technique

- [ ] Rédiger `README.md` technique (installation, build, run, architecture)
- [ ] Rédiger `CONTRIBUTING.md` (guide de contribution)
- [ ] Rédiger `ARCHITECTURE.md` (documentation détaillée de l'architecture)
- [ ] Rédiger `SECURITY.md` (politique de sécurité, signalement de vulnérabilités)
- [ ] Documenter l'API WebSocket (endpoints, messages, protocole)
- [ ] Documenter le protocole P2P mesh

### 5.2 Documentation utilisateur

- [ ] Guide d'utilisation de l'application
- [ ] Explication du modèle de confiance (consensus, TTL, anonymat)

---

## Phase 6 — Fixtures et Données de Test (Priorité 🟡)

### 6.1 Externaliser les fixtures

- [ ] Extraire les données Fleurus de `event_manager.dart`
- [ ] Créer `test/fixtures/fleurus_event.json`
- [ ] Créer `test/fixtures/` pour toutes les données de test
- [ ] Charger les fixtures depuis les JSON plutôt que code en dur

### 6.2 Jeux de données de test

- [ ] Créer un jeu d'alertes de test varié (tous types, tous états)
- [ ] Créer un jeu d'événements de test
- [ ] Créer un générateur de données aléatoires pour tests de charge

---

## Phase 7 — Consolidation des Features (Priorité 🟠)

### 7.1 Vérifier les features existantes

- [ ] Feature Alerts : compléter si incomplet (formulaire, validation, liste)
- [ ] Feature Maps : vérifier l'intégration avec les alertes et événements
- [ ] Feature Panic : compléter l'implémentation si squelettique
- [ ] Feature Geofencing : tester et stabiliser
- [ ] Feature Settings : vérifier l'exhaustivité des paramètres
- [ ] Feature Bug Report : connecter au serveur admin

### 7.2 Unifier les dashboards admin

- [ ] Conserver UN SEUL dashboard admin
- [ ] Supprimer les deux autres
- [ ] Assurer que le dashboard retenu couvre tous les besoins (métriques, sandbox, contrôle)

---

## Phase 8 — Scripts Cross-Plateforme (Priorité 🟡)

### 8.1 Uniformiser les scripts

- [ ] Décider d'un environnement cible prioritaire (Windows ou Unix)
- [ ] Créer des scripts équivalents pour l'autre environnement OU
- [ ] Remplacer les scripts `.sh`/`.bat`/`.ps1` par un orchestrateur unique (Dart ou Node.js)
- [ ] Documenter les prérequis et alternatives

---

## Phase 9 — Performance et Optimisation (Priorité 🟡)

### 9.1 Performance

- [ ] Profiler l'application Flutter (DevTools)
- [ ] Optimiser les requêtes Hive (index, batch)
- [ ] Optimiser le rendu de la carte (clustering de marqueurs)
- [ ] Mesurer la latence du mesh P2P
- [ ] Tester la consommation batterie (BLE continu)

### 9.2 Scalabilité

- [ ] Tester avec 50+ alertes simultanées
- [ ] Tester avec 100+ nœuds mesh simulés
- [ ] Tester la mémoire avec usage prolongé

---

## Phase 10 — Déploiement et Publication (Priorité 🟡)

### 10.1 Préparation store

- [ ] Générer les icônes (`flutter_launcher_icons.yaml`)
- [ ] Préparer les captures d'écran pour Google Play et App Store
- [ ] Rédiger la description store (multilingue)
- [ ] Configurer les policies de confidentialité
- [ ] Vérifier la conformité RGPD

### 10.2 Build et signature

- [ ] Configurer la signature Android (keystore)
- [ ] Configurer le provisioning iOS
- [ ] Automatiser les builds de release
- [ ] Tester les builds de release sur appareils physiques

### 10.3 Site vitrine

- [ ] Mettre à jour le site vitrine avec la version actuelle
- [ ] Ajouter les liens de téléchargement (Google Play, App Store)
- [ ] Vérifier le multilingue (AR/EN/NL/DE)

---

## Résumé des Priorités

| Phase                         | Priorité    | Effort estimé |
|-------------------------------|-------------|---------------|
| 1. Nettoyage et Stabilisation | 🔴 Critique | 0.5 jour      |
| 2. Unification des Modèles    | 🔴 Critique | 1.5 jours     |
| 3. Tests                      | 🔴 Critique | 3 jours       |
| 4. CI/CD et Qualité           | 🟠 Haute    | 1 jour        |
| 5. Documentation              | 🟠 Haute    | 1 jour        |
| 6. Fixtures et Données        | 🟡 Normale  | 0.5 jour      |
| 7. Consolidation Features     | 🟠 Haute    | 2 jours       |
| 8. Scripts Cross-Plateforme   | 🟡 Normale  | 0.5 jour      |
| 9. Performance                | 🟡 Normale  | 1 jour        |
| 10. Déploiement               | 🟡 Normale  | 1 jour        |

**Effort total estimé** : ~12 jours-homme
