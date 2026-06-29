# features/alerts/

> **TODO: Module Alertes — À séparer de database/ et network/**
>
> Ce dossier est prévu pour le module fonctionnel de gestion des alertes.
> Actuellement, la logique « alerte » est intégralement dans :
> - `database/alert_model.dart` — modèle Alert + sérialisation
> - `database/alert_ttl_policy.dart` — politique TTL par type
> - `database/alert_visibility_policy.dart` — règles de visibilité
> - `database/hive_alert_database.dart` — persistance Hive
> - `network/network_coordinator.dart` — orchestration réseau
>
> **Plan** : Extraire la logique métier des alertes depuis `database/` et `network/`
> vers `features/alerts/` en architecture feature-based (Clean Architecture) :
> ```
> features/alerts/
> ├── domain/
> │   ├── models/alert.dart (depuis database/alert_model.dart)
> │   ├── policies/alert_ttl_policy.dart
> │   └── policies/alert_visibility_policy.dart
> ├── data/
> │   └── hive_alert_repository.dart (depuis database/hive_alert_database.dart)
> └── presentation/
>     ├── alert_list_screen.dart
>     └── alert_detail_screen.dart
> ```
>
> Références :
> - [docs/plan_et_audit_complet_28062026.md](../../../docs/plan_et_audit_complet_28062026.md) — Anomalie N1
> - [docs/reste_a_faire.md](../../../docs/reste_a_faire.md)