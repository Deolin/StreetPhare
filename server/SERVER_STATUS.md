# StreetPhare Server — Status & Observabilité

> **Généré automatiquement par le serveur au démarrage.**
> Dernière mise à jour : `{{ timestamp }}`

## Identité du nœud

| Propriété | Valeur |
|-----------|--------|
| **Rôle** | `{{ serverType }}` (PRIMARY / BACKUP) |
| **Port** | `{{ port }}` |
| **Adresse** | `http://{{ host }}:{{ port }}` |
| **Partenaire** | `{{ partnerUrl }}` |

## Synchronisation

| Métrique | Valeur |
|----------|--------|
| Dernière synchronisation | `{{ lastSyncAt }}` |
| Succès dernière synchro | `{{ lastSyncSuccess }}` |
| Intervalle de synchro | `{{ syncIntervalSeconds }}s` |

## Données en mémoire

| Type | Total |
|------|-------|
| **Alertes totales** | `{{ totalAlerts }}` |
| **Alertes actives** (≥3 votes, TTL OK) | `{{ activeAlerts }}` |
| **Événements** | `{{ eventCount }}` |
| **Pings PANIC** (fenêtre 5 min) | `{{ panicPings }}` |
| **Clients Mesh WebSocket** | `{{ meshClients }}` |
| **Clients Admin WebSocket** | `{{ adminClients }}` |

## Routes API sollicitées (compteurs)

| Route | Compteur |
|-------|----------|
| `POST /api/alerts` | `{{ counter.alerts }}` |
| `GET /api/alerts/active` | `{{ counter.alertsActive }}` |
| `POST /api/events/join` | `{{ counter.eventsJoin }}` |
| `POST /api/panic/collective` | `{{ counter.panic }}` |
| `POST /api/sync/alert` | `{{ counter.syncAlert }}` |
| `POST /api/sync/check` | `{{ counter.syncCheck }}` |
| `POST /api/sync/full` | `{{ counter.syncFull }}` |

## Uptime

`{{ uptime }}` secondes

---

_Ce fichier est régénéré toutes les 30 secondes par le processus serveur._
