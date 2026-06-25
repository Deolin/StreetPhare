# StreetPhare — Chantiers restants

> **Date** : 25/06/2026
> **Version** : 2.2.0+1

---

## Backlog Prioritaire

| # | Chantier | Priorité | Fichier(s) | TODO |
|---|----------|----------|-----------|------|
| 1 | Mode malvoyant : slider dynamique 1.0x → 2.0x (ne pas verrouiller à 1.5x) | 🟠 P1 | `lib/features/settings/presentation/settings_screen.dart` | `// TODO: Mode malvoyant — rendre le slider libre (1.0x-2.0x), 1.5x comme preset initial non bloquant` |
| 2 | Cache maps : supprimer options 1j et 3j, garder 7j / 14j / 30j | 🟡 P2 | `lib/features/settings/presentation/settings_screen.dart` | `// TODO: Cache maps — supprimer 1j et 3j, ne garder que 7j, 14j, 30j` |
| 3 | Bouton surveillance arrière-plan interactif (SnackBar confirmation + toggle texte Activation/Désactivation) | 🟠 P1 | `lib/features/settings/presentation/settings_screen.dart` | `// TODO: Surveillance arrière-plan — ajouter SnackBar confirmation, toggle texte Activer/Désactiver` |
| 4 | À propos : version+build dynamique via `package_info_plus` | 🟡 P2 | `lib/features/map/presentation/map_screen.dart` (méthode `_showAboutDialog`) | `// TODO: Remplacer '1.2.0' statique par PackageInfo.version + PackageInfo.buildNumber` |
| 5 | Notifications Android : canaux (Channels) + SnackBar confirmation slider + ouvrir paramètres Android via `open_settings` | 🟠 P1 | `lib/features/settings/presentation/settings_screen.dart` | `// TODO: Notifications — intégrer flutter_local_notifications Android channels, SnackBar au changement de slider, open_settings pour paramètres système` |
| 6 | QR Code sortant : générer et afficher un QR Code pour partager un événement | 🟡 P2 | `lib/features/events/presentation/events_screen.dart` ou `lib/features/settings/presentation/settings_screen.dart` | `// TODO: QR Code — ajouter bouton générant un QR code (package qr_flutter) pour l'événement actif, exportable sans internet` |
| 7 | Bug report / Suggérer : corriger le POST HTTP vers le serveur, unifier les deux modes | 🟠 P1 | `lib/features/bug_report/presentation/bug_report_service.dart` | `// TODO: Bug report — corriger POST /api/bug-report, unifier 'bug' et 'suggestion' dans un seul flux` |
| 8 | Cache BLE : corriger `discoverAllServices` → `getDiscoveredServices` (API flutter_reactive_ble) | 🔴 P0 | `lib/network/transports/ble_transport.dart` (méthode `_discoverServices`) | `// TODO: BLE — vérifier compatibilité API flutter_reactive_ble pour discoverServices (actuellement .first sur un Future<List>)` |

---

## Instructions par fichier

### `lib/features/settings/presentation/settings_screen.dart`

- **Section Mode Malvoyant** : le slider `textScaleFactor` doit rester libre (1.0 → 2.0). Le toggle "Mode Malvoyant" applique 1.5x en preset mais ne doit pas verrouiller le slider.
- **Section Cache Cartes** : remplacer le groupe de radio par 3 options uniquement : `[MapCacheDuration.days7, MapCacheDuration.days14, MapCacheDuration.days30]`.
- **Section Service Arrière-plan** : le bouton doit afficher "Activer la surveillance" ou "Désactiver la surveillance" selon l'état. Un tap montre une SnackBar de confirmation.
- **Section Notifications** : ajouter `flutter_local_notifications` Android notification channels. Au changement de slider, afficher une SnackBar. Le bouton "Paramètres Android" doit ouvrir `open_settings`.

### `lib/features/map/presentation/map_screen.dart`

- **Méthode `_showAboutDialog`** : remplacer `'1.2.0'` par un appel à `PackageInfo.fromPlatform()` pour obtenir `version` et `buildNumber`.

### `lib/features/bug_report/presentation/bug_report_service.dart`

- **Méthode `sendReport`** : le POST vers `/api/bug-report` doit envoyer un payload JSON structuré `{type: 'bug'|'suggestion', message, logs}`. Le serveur doit logger la requête.

### `lib/features/events/presentation/events_screen.dart`

- **Bouton QR Code** : ajouter un `IconButton` ou `FloatingActionButton` qui, pour l'événement actif, génère un QR code (package `qr_flutter`) contenant le JSON complet de l'événement, affiché dans un dialog.
