# core/auth/

> **TODO: Authentification — Module à implémenter**
>
> Ce dossier est prévu pour la gestion de l'authentification des utilisateurs et des appareils :
> - Génération et rotation des euid (Ephemeral User ID)
> - Signature Ed25519 des métadonnées d'alerte
> - Authentification P2P entre appareils
> - Gestion des sessions anonymes (pas d'authentification nominative)
>
> Actuellement, `generateEphemeralUserId()` est implémenté dans `database/hive_alert_database.dart`
> et la signature Ed25519 est dans `database/crypto_utils.dart`.
>
> **Plan** : Migrer la logique d'identité depuis `database/` vers `core/auth/`.
>
> Référence : [docs/plan_et_audit_complet_28062026.md](../../../docs/plan_et_audit_complet_28062026.md) — Anomalie N3