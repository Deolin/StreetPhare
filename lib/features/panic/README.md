# features/panic/

> **TODO: Module Panic — À extraire**
>
> Ce dossier est prévu pour le module de déclenchement d'alerte panique.
> Actuellement, la logique « panic » est implémentée de façon éparse :
> - `network/collective_panic_service.dart` — détection de panique collective
> - `features/settings/data/panic_contact_store.dart` — contacts d'urgence
> - `features/settings/data/panic_contact.dart` — modèle contact
>
> **Plan** : Extraire la logique panique vers `features/panic/` :
> ```
> features/panic/
> ├── domain/
> │   └── models/panic_alert.dart
> ├── data/
> │   └── panic_contact_repository.dart
> └── presentation/
>     ├── panic_screen.dart
>     └── widgets/panic_button.dart
> ```
>
> Références :
> - [docs/plan_et_audit_complet_28062026.md](../../../docs/plan_et_audit_complet_28062026.md) — Anomalie N2
> - [docs/reste_a_faire.md](../../../docs/reste_a_faire.md)