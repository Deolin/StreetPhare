# core/models/

> **TODO: Modèles Partagés — Module à implémenter**
>
> Ce dossier est prévu pour les modèles de données partagés entre les features.
> Actuellement, `alert_model.dart` réside dans `database/` et `event_model.dart`
> dans `features/events/domain/`. Aucun modèle n'est centralisé.
>
> **Plan** : Migrer les modèles partagés vers `core/models/` :
> - `Alert` — depuis `database/alert_model.dart`
> - `Event` — depuis `features/events/domain/`
> - Tout nouveau modèle partagé (User, Message, Route...)
>
> Les imports devront être mis à jour dans tous les fichiers dépendants.
>
> Référence : [docs/plan_et_audit_complet_28062026.md](../../../docs/plan_et_audit_complet_28062026.md) — Anomalies A2, N6