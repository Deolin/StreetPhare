# core/config/

> **TODO: Configuration — Module à implémenter**
>
> Ce dossier est prévu pour la configuration centralisée de l'application.
> Actuellement, les constantes sont dans `constants/app_constants.dart` et
> la configuration réseau est dans `network/network_config.dart`.
>
> **Plan** : Centraliser la configuration :
> - Constantes d'application (version, URLs, timeouts)
> - Configuration par environnement (dev/staging/prod)
> - Feature flags
> - Configuration de build (via `--dart-define` ou fichier .env)
>
> Référence : [docs/plan_et_audit_complet_28062026.md](../../../docs/plan_et_audit_complet_28062026.md) — Anomalie N8