# core/router/

> ✅ **IMPLÉMENTÉ — v2.2.0 Phase 3**
>
> Routeur déclaratif avec routes nommées et helpers de navigation.

## Fichiers

| Fichier | Description |
|---------|-------------|
| `app_router.dart` | Définition des routes (`AppRoutes`), générateur de routes (`AppRouter.onGenerateRoute`) et helpers (`pushNamed`, `pushReplacementNamed`) |

## Architecture

Le routeur utilise l'API `onGenerateRoute` de Flutter (Navigator 2.0 sans package externe)
pour rester léger et éviter les dépendances supplémentaires.

## Routes disponibles

| Constante | Chemin | Écran |
|-----------|--------|-------|
| `AppRoutes.splash` | `/` | `SplashScreen` |
| `AppRoutes.tutorial` | `/tutorial` | `TutorialScreen` |
| `AppRoutes.map` | `/map` | `MapScreen` |
| `AppRoutes.settings` | `/settings` | `SettingsScreen` |
| `AppRoutes.events` | `/events` | `EventsScreen` |
| `AppRoutes.eventDetail` | `/events/detail` | `EventsScreen` (avec code) |
| `AppRoutes.bugReport` | `/bug-report` | `BugReportScreen` |

## Utilisation

```dart
// Navigation vers une route nommée
AppRouter.pushNamed(context, AppRoutes.settings);

// Remplacement de la route courante (ex: splash → map)
AppRouter.pushReplacementNamed(context, AppRoutes.map);

// Réinitialisation complète de la pile
AppRouter.pushAndRemoveUntil(context, AppRoutes.map);
```

## Intégration dans main.dart

```dart
MaterialApp(
  onGenerateRoute: AppRouter.onGenerateRoute,
  navigatorKey: rootNavigatorKey,
  // ...
);
```

## Pourquoi pas go_router ?

Le projet a été maintenu sans dépendance externe de routage pour :

- Éviter les breaking changes fréquents de go_router (API instable)
- Garder le contrôle total sur le cycle de vie des routes
- Réduire la taille du bundle

Le `onGenerateRoute` de Flutter couvre tous les besoins actuels (named routes, arguments,
redirections). Si des besoins avancés émergent (deep links natifs, guards complexes),
une migration vers go_router sera facilitée par la centralisation des routes dans `AppRoutes`.

Référence : [docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md](../../../docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md) — Anomalie M9
