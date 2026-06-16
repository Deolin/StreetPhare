---
name: StartStreet
description: Promt de départ streetphare
invokable: true
---

Voici le prompt de contexte initial optimisé pour StreetPhare, conçu pour être collé au début de chaque nouvelle session de développement afin de garantir une immersion instantanée et une qualité de code maximale.

```markdown
# CONTEXTE INITIAL : PROJET STREETPHARE
StreetPhare est une application Flutter de cartographie citoyenne collaborative et décentralisée. Son but est de renforcer la sécurité collective lors de rassemblements via un réseau P2P ("ruche") et un calcul d'itinéraires sûrs.

## 1. ARCHITECTURE & TECH STACK
- **Framework** : Flutter (Dart) — Orientation portrait verrouillée.
- **State Management** : Réactif via `ValueNotifier` et `ValueListenableBuilder`. Utilisation stricte de Singletons pour les services/stores.
- **Persistence locale** : 
    - **Hive** : Base P2P chiffrée pour alertes et messages (TTL 24h, purge auto).
    - **SharedPreferences** : Préférences UI, flags de démarrage, thèmes.
- **Réseau (La Ruche)** : Architecture décentralisée multi-transports.
    - Transports : BLE (maillage), Wi-Fi Direct (Nearby), WebSockets (Relais chiffrés).
    - Consensus : 3 validations locales nécessaires avant synchronisation serveur.
- **i18n** : Système sur mesure (`AppLocale`) supportant FR (défaut), EN, NL, DE.
- **Routing** : Safe Path Engine — Algorithme de Dijkstra sur grille (20m) avec pénalités diagonales fortes pour suivre la voirie et éviter les bâtiments.

## 2. CORE LOGIC & FLOW
1. **Bootstrap** : Chargement des stores (`Future.wait`) -> Initialisation `NetworkCoordinator` -> SplashScreen.
2. **Alertes** : Création locale -> Broadcast P2P -> Accumulation de confirmations -> Consensus atteint -> Upload via `FailoverManager` vers serveurs primaires/secondaires.
3. **Sécurité** : Identifiants utilisateurs éphémères et rotatifs. Chiffrement Ed25519 pour les signatures d'alertes.
4. **Navigation** : `MapScreen` est le hub central utilisant `flutter_map` avec cache local des tuiles (7 jours).

## 3. RÈGLES DE CODAGE & STANDARDS
- **Langue** : Commentaires et documentation technique en Français (FR).
- **State** : Ne jamais mettre de logique lourde dans les widgets. Utiliser les Singletons (`...Store.instance` ou `...Service.instance`).
- **Erreurs** : Logger via `ClientDebugLogger.instance.log` (produit `CLIENT_DEBUG.md`).
- **UI** : Respecter scrupuleusement le thème `StreetPhareTheme`. Mode Malvoyant à supporter systématiquement.
- **Concision** : Préférer `replace_in_file` ciblé plutôt que `write_to_file` massif.

## 4. CARTOGRAPHIE DES FICHIERS CLÉS
- `lib/main.dart` : Point d'entrée, initialisation réactive et routing racine.
- `lib/network/network_coordinator.dart` : Cœur de la logique P2P et orchestration réseau.
- `lib/core/i18n/strings.dart` : Source de vérité pour toutes les traductions.
- `lib/features/routing/presentation/safe_path_engine.dart` : Algorithme de calcul d'itinéraire.
- `lib/database/hive_alert_database.dart` : Gestionnaire de la base locale Hive.
- `lib/features/settings/data/app_preferences_store.dart` : Store central des préférences utilisateur.

## 5. DIRECTIVES D'ÉCONOMIE DE CRÉDITS (IA)
- **Analyse d'abord** : Lis uniquement les fichiers nécessaires au ticket actuel.
- **Modifications chirurgicales** : Ne réécris jamais un fichier entier pour un changement de fonction. Utilise des blocs SEARCH/REPLACE précis.
- **Validation** : Vérifie systématiquement la cohérence avec les Singletons existants.
- **Briefing** : Sois technique, directe, et évite les explications verbeuses non sollicitées.
```