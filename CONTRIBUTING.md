# Contribuer à StreetPhare 🏮

Merci de votre intérêt pour contribuer à **StreetPhare** — application citoyenne de
cartographie collaborative en temps réel, pensée pour sécuriser les déplacements
piétons lors d'événements et de rassemblements publics.

Ce document fixe la **ligne de conduite** du projet afin que toutes les
contributions restent cohérentes avec l'architecture, les conventions et surtout
les engagements de **sécurité / vie privée** de StreetPhare. Merci de le lire en
entier avant d'ouvrir une issue ou une pull request.

> 📄 À lire aussi : [`README.md`](README.md) (objectif & architecture),
> [`SECURITY.md`](SECURITY.md) (politique de sécurité et RGPD).

---

## 1. Principes non négociables

Ces règles découlent directement de la nature du projet. Aucune contribution ne
sera acceptée si elle les enfreint :

1. **RGPD by design** : StreetPhare ne collecte, ne stocke et ne transmet **aucune
   donnée personnelle identifiable**. Toute fonctionnalité doit préserver
   l'anonymat (UUID éphémères rotatifs, pas de PII).
2. **Aucun SDK de tracking** : l'intégration de Firebase, Crashlytics, Analytics
   ou tout autre traceur tiers est **interdite** (voir `SECURITY.md`, §8).
3. **Offline-first / décentralisé** : le mesh P2P (BLE, Wi-Fi Direct, WebSocket
   relay) reste prioritaire ; le serveur central est **optionnel**. Ne créez pas
   de dépendance qui rendrait l'application inutilisable hors-ligne.
4. **Pas de secret dans le code** : ni clés, ni mots de passe, ni tokens, ni
   `server/.env`. Les secrets serveur passent par variables d'environnement.
5. **Multi-langue** : toute chaîne visible par l'utilisateur doit exister dans les
   **4 langues** (fr, en, nl, de).
6. **Licence** : toute contribution est placée sous **GPLv3** (voir [`LICENSE`](LICENSE)).

---

## 2. Architecture du projet

Le client Flutter suit une architecture **feature-first** :

```text
lib/
├── constants/     # constantes applicatives partagées
├── core/          # auth, cache, config, di, i18n, models, network, router,
│                  #   security, services, theme, utils
├── features/      # splash, start_screen, tutorial, map, reports, alerts,
│                  #   panic, events, geofencing, messaging, routing, admin,
│                  #   bug_report, settings, sandbox, streetmedic, trust_group
├── network/       # P2P (BLE, WebSocket, Wi-Fi Direct, relay), failover, sync
├── services/      # notifications, APK, version, mise à jour GitHub, tuiles…
├── database/      # Hive CE + crypto (AES/HMAC) + politiques TTL/visibilité
├── debug/         # ClientDebugLogger (observabilité locale)
└── l10n/          # fichiers ARB (fr, en, nl, de) + localisations générées
```

Règles de placement :

- Le code **métier** va dans `lib/features/<domaine>/` (en couches `data/`,
  `domain/`, `presentation/` quand pertinent).
- Le code **transverse réutilisable** va dans `lib/core/` ou `lib/services/`.
- Le **réseau P2P** reste dans `lib/network/`.
- Ne créez pas de nouveau dossier racine sans nécessité réelle.

### Stack technique

| Couche | Technologie |
|---|---|
| Client | Flutter / Dart (SDK ≥ 3.6.0) |
| Cartographie | `flutter_map` + `latlong2` (tuiles OSM, cache hors-ligne) |
| Routage | GraphHopper 7.0 embarqué (Android) + A*/Dijkstra/SPG (Dart) + OsmAnd |
| Réseau P2P | BLE (`flutter_reactive_ble`), WebSocket (`ws`), Wi-Fi Direct |
| Stockage local | Hive CE, `shared_preferences` |
| Sécurité client | `cryptography` (AES-256-CBC, Ed25519), `flutter_secure_storage` |
| Serveur | Node.js + Express 5 (primary/backup, JWT, rate-limiting) |
| Reverse proxy | Caddy (TLS Let's Encrypt, HSTS) |
| Packaging serveur | `esbuild` + Node SEA |
| CI/CD | GitHub Actions (analyse, tests, builds multi-plateformes, release) |

---

## 3. Prérequis & installation

### Client Flutter

- Flutter **stable** récent (projet validé sur 3.50.x), Dart ≥ 3.6.0.
- Pour les builds Android : **JDK 21** (⚠️ requis par AGP 9.3.x), Android SDK.
- Pour les builds de bureau : toolchains Windows/Linux/macOS (CMake, ninja,
  GTK3, `libsecret-1-dev` sur Linux).

```bash
flutter pub get
flutter run                     # exécution
flutter build apk --release     # build Android
flutter build windows --release # build Windows
```

### Serveur Node.js

```bash
cd server
cp .env.example .env            # renseigner MASTER_KEY, JWT_SECRET, ADMIN_HASH
npm install
npm run dev:primary             # primary sur :3000
npm run dev:backup              # backup sur :3001
```

> ⚠️ En production, le serveur **refuse de démarrer** avec les clés par défaut.
> Générez des secrets forts : `openssl rand -hex 32`.

---

## 4. Conventions de code

### Dart / Flutter

- **Analyse stricte** : `flutter analyze` doit rendre **0 issue** (erreurs et
  avertissements). Les règles sont définies dans [`analysis_options.yaml`](analysis_options.yaml)
  (basées sur `flutter_lints` + règles strictes : `unawaited_futures: error`,
  `avoid_print`, `prefer_single_quotes`, `prefer_const_*`, `close_sinks`,
  `always_declare_return_types`, `directives_ordering`, …).
- **Formatage** : `dart format .` (le CI vérifie via
  `dart format --output=none --set-exit-if-changed .`).
- **Logs** : jamais `print()` (règle `avoid_print`). Utilisez `debugPrint` ou
  `ClientDebugLogger.instance.log(...)`.
- **Commentaires** : en **français**, comme le reste du code.
- **Fins de ligne** : **LF** obligatoire (normalisées par `.gitattributes`).
- **Chaînes** : guillemets simples (`prefer_single_quotes`).

### Internationalisation

- Toute chaîne utilisateur va dans `lib/l10n/app_*.arb` (**fr, en, nl, de**).
- Régénérez les localisations si vous modifiez les ARB : `flutter gen-l10n`.

### JavaScript / serveur

- Formatage avec Prettier (config `.prettierrc`).
- Garder la structure `server/src/` existante (auth, mesh, sync…).
- Aucun secret en dur ; tout passe par `.env`.

---

## 5. Tests & analyse statique

Avant d'ouvrir une PR, vérifiez au minimum :

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed .
node scripts/sync_branding.js --check   # cohérence du branding (le cas échéant)
```

- Les tests utilisent **`mocktail`** (voir `test/`).
- La couverture de tests est encore faible sur les couches critiques
  (`network/`, `routing/`, `database/`) : toute contribution sur ces couches doit
  être **accompagnée de tests**.

---

## 6. Git : branches, commits, tags

### Branches

Le dépôt utilise des branches **par plateforme/domaine** :

| Branche | Usage |
|---|---|
| `main` | branche principale (CI globale) |
| `admin` | fonctionnalités d'administration |
| `android` / `ios` / `windows` | builds spécifiques à la plateforme |
| `server` | serveur Node.js |

Flux recommandé :

1. Créez une branche descriptive : `feature/…` ou `fix/…`.
2. Ouvrez une **pull request** vers `main` (ou la branche plateforme concernée).
3. La CI (`ci.yml`) doit être verte (analyse + tests + format + branding).

### Commits

Gardez des commits **petits et atomiques**, avec un message clair. Exemples de
style déjà utilisés :

```text
fix(android): forcer compileSdk 36 sur reactive_ble_mobile en CI
chore: automatisation des releases GitHub
docs: documenter le processus de publication
```

### Tags de version (⚠️ important)

Les releases sont **uniquement** déclenchées par un tag au format **`vX.Y.Z`**
(ex. `v2.3.0`). C'est ce format qu'attend le gestionnaire de mises à jour de
l'application (`GithubUpdateService`). N'utilisez **pas** d'autre format.

---

## 7. CI/CD & publication d'une release

Workflows GitHub Actions :

| Workflow | Déclencheur | Rôle |
|---|---|---|
| `ci.yml` | push/PR sur `main` | analyse, tests, format, branding |
| `buildAndroid.yml` / `buildIOS.yml` / `buildWindows.yml` / `buildServer.yml` | push/PR sur la branche dédiée | builds par plateforme |
| `release.yml` | tag `v*` (ou manuel) | construit les exécutables **et** crée la release GitHub |
| `static.yml` | push sur `main` | déploie le site vitrine sur GitHub Pages |

### Publier une version

Depuis un poste de travail :

```powershell
# Bumper la version et pousser le tag (déclenche release.yml)
powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Bump patch

# … ou forcer une version précise
powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 2.3.0
```

Le script met à jour `pubspec.yaml` (version + numéro de build), commite, crée le
tag `vX.Y.Z` et le pousse. GitHub Actions construit alors **Windows (EXE)**,
**Linux (tar.gz)** et **Android (APK + AAB)** puis publie la release.

---

## 8. Sécurité & vie privée

StreetPhare est conçu en **RGPD by design**. Lisez [`SECURITY.md`](SECURITY.md)
avant de toucher à toute logique réseau, chiffrement, identité ou persistance.

Points essentiels :

- **Anonymat** : UUID éphémères rotatifs (`Random.secure`), aucune donnée personnelle.
- **Confidentialité** : chiffrement de bout en bout AES-256-CBC + HMAC-SHA256.
- **Intégrité** : signatures Ed25519, vérification HMAC.
- **Durée limitée** : TTL stricts par type d'alerte, droit à l'oubli (purge Hive).
- **Kill switch** : désactivation à distance en cas de compromission.

**Interdits** : tout SDK de tracking, toute télémétrie, tout log d'UUID/position,
tout stockage de PII.

### Signaler une vulnérabilité

**N'ouvrez PAS d'issue publique.** Utilisez :

1. L'onglet **Security → Advisories → Report a vulnerability** du dépôt GitHub ; ou
2. `security@streetphare.org`.

---

## 9. Contraintes techniques à ne pas casser (anti-dérive)

Certaines valeurs sont le fruit de compromis documentés. **Ne les modifiez pas
sans validation explicite** :

### Build Android

- **AGP 9.3.1**, **Gradle 9.5.0**, **Kotlin 2.4.20** (`android/settings.gradle.kts`).
- **JDK 21** requis (le lint/R8 d'AGP 9.3 exige des API Java 21).
- `android.builtInKotlin=false` et `android.newDsl=false` (migration « Built-in
  Kotlin » **volontairement différée** : plusieurs plugins appliquent encore KGP
  manuellement).
- Metaspace Gradle à **2048m** (`android/gradle.properties`) : ne pas réduire,
  sous peine d'`OutOfMemoryError: Metaspace`.

### Dépendances épinglées (`pubspec.yaml`)

Les `dependency_overrides` suivants ne doivent **pas être retirés** sans test
complet :

```yaml
dependency_overrides:
  shared_preferences_android: 2.4.27   # évite la migration Pigeon/JNI (incompatible AGP 9 / R8)
  permission_handler_android: 13.0.1
  reactive_ble_mobile: 5.5.0           # la 5.6.0 impose le Built-in Kotlin
```

### Patch CI `reactive_ble_mobile`

Le plugin `reactive_ble_mobile` 5.5.0 (pub.dev) déclare `compileSdk 33`, insuffisant
pour ses dépendances AndroidX. Le script `scripts/patch_reactive_blemobile.sh`
force `compileSdk/targetSdk 36` en CI. Ne supprimez pas ce patch.

---

## 10. Signaler un bug (non sécurité)

- Ouvrez une **issue GitHub** en décrivant : version de l'app, plateforme, étapes
  de reproduction, comportement attendu vs observé, captures/logs.
- Étiquetez correctement (bug, enhancement, …).

---

## 11. Licence

StreetPhare est distribué sous **GPLv3** (voir [`LICENSE`](LICENSE)). En
contribuant, vous acceptez que vos contributions soient placées sous cette licence.



