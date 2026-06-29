# core/di/

> ✅ **IMPLÉMENTÉ — v2.2.0 Phase 3**
>
> Conteneur d'injection de dépendances léger (Service Locator pattern).

## Fichiers

| Fichier | Description |
|---------|-------------|
| `injection_container.dart` | Conteneur DI avec `register<T>()`, `resolve<T>()`, `override<T>()` et `reset()` |

## Utilisation

```dart
// Enregistrement au démarrage (main.dart)
InjectionContainer.register<MyService>(MyService());

// Résolution dans les écrans/services
final service = InjectionContainer.resolve<MyService>();

// Tests unitaires — mock injection
InjectionContainer.override<MyService>(mockService);
```

## Pourquoi pas get_it ?

Le projet utilise déjà 30+ dépendances. Un conteneur interne sans dépendance externe évite :

- Un package supplémentaire à maintenir
- Des conflits de version avec d'autres packages
- Une courbe d'apprentissage pour les contributeurs

Si le projet grossit significativement (>50 services), migrer vers `get_it` sera trivial
car l'API est volontairement similaire (`register`/`resolve`).

## Migration depuis le pattern singleton

```dart
// AVANT : couplage fort, impossible à mocker
final alerts = HiveAlertDatabase.instance;

// APRÈS : découplé, testable
final alerts = InjectionContainer.resolve<HiveAlertDatabase>();
```

Référence : [docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md](../../../docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md) — Anomalie M8
