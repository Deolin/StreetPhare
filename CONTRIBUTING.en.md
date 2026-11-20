# Contributing to StreetPhare 🏮

Thank you for your interest in contributing to **StreetPhare** — a citizen
application for real-time collaborative mapping, designed to make pedestrian
journeys safer during public events and gatherings.

This document sets the project's **code of conduct** so that every contribution
stays consistent with the architecture, conventions, and above all StreetPhare's
**security / privacy** commitments. Please read it in full before opening an
issue or a pull request.

> 📄 Also read: [`README.md`](README.md) (purpose & architecture),
> [`SECURITY.md`](SECURITY.md) (security policy and GDPR).

---

## 1. Non-negotiable principles

These rules stem directly from the nature of the project. No contribution will
be accepted if it violates them:

1. **GDPR by design**: StreetPhare does not collect, store, or transmit **any
   personally identifiable information**. Every feature must preserve anonymity
   (rotating ephemeral UUIDs, no PII).
2. **No tracking SDKs**: integrating Firebase, Crashlytics, Analytics or any
   other third-party tracker is **forbidden** (see `SECURITY.md`, §8).
3. **Offline-first / decentralized**: the P2P mesh (BLE, Wi-Fi Direct, WebSocket
   relay) stays the priority; the central server is **optional**. Do not create
   a dependency that would make the app unusable offline.
4. **No secrets in the code**: no keys, passwords, tokens, or `server/.env`.
   Server secrets go through environment variables.
5. **Multilingual**: every user-visible string must exist in the **4 languages**
   (fr, en, nl, de).
6. **License**: every contribution is released under **GPLv3** (see [`LICENSE`](LICENSE)).

---

## 2. Project architecture

The Flutter client follows a **feature-first** architecture:

```text
lib/
├── constants/     # shared application constants
├── core/          # auth, cache, config, di, i18n, models, network, router,
│                  #   security, services, theme, utils
├── features/      # splash, start_screen, tutorial, map, reports, alerts,
│                  #   panic, events, geofencing, messaging, routing, admin,
│                  #   bug_report, settings, sandbox, streetmedic, trust_group
├── network/       # P2P (BLE, WebSocket, Wi-Fi Direct, relay), failover, sync
├── services/      # notifications, APK, version, GitHub update, tiles…
├── database/      # Hive CE + crypto (AES/HMAC) + TTL/visibility policies
├── debug/         # ClientDebugLogger (local observability)
└── l10n/          # ARB files (fr, en, nl, de) + generated localizations
```

Placement rules:

- **Domain** code goes in `lib/features/<domain>/` (layered as `data/`,
  `domain/`, `presentation/` when relevant).
- **Reusable cross-cutting** code goes in `lib/core/` or `lib/services/`.
- **P2P networking** stays in `lib/network/`.
- Do not create a new root folder without a real need.

### Tech stack

| Layer | Technology |
|---|---|
| Client | Flutter / Dart (SDK ≥ 3.6.0) |
| Mapping | `flutter_map` + `latlong2` (OSM tiles, offline cache) |
| Routing | Embedded GraphHopper 7.0 (Android) + A*/Dijkstra/SPG (Dart) + OsmAnd |
| P2P network | BLE (`flutter_reactive_ble`), WebSocket (`ws`), Wi-Fi Direct |
| Local storage | Hive CE, `shared_preferences` |
| Client security | `cryptography` (AES-256-CBC, Ed25519), `flutter_secure_storage` |
| Server | Node.js + Express 5 (primary/backup, JWT, rate-limiting) |
| Reverse proxy | Caddy (TLS Let's Encrypt, HSTS) |
| Server packaging | `esbuild` + Node SEA |
| CI/CD | GitHub Actions (analysis, tests, multi-platform builds, releases) |

---

## 3. Prerequisites & setup

### Flutter client

- Recent **stable** Flutter (validated on 3.50.x), Dart ≥ 3.6.0.
- For Android builds: **JDK 21** (⚠️ required by AGP 9.3.x), Android SDK.
- For desktop builds: Windows/Linux/macOS toolchains (CMake, ninja, GTK3,
  `libsecret-1-dev` on Linux).

```bash
flutter pub get
flutter run                     # run
flutter build apk --release     # Android build
flutter build windows --release # Windows build
```

### Node.js server

```bash
cd server
cp .env.example .env            # set MASTER_KEY, JWT_SECRET, ADMIN_HASH
npm install
npm run dev:primary             # primary on :3000
npm run dev:backup              # backup on :3001
```

> ⚠️ In production, the server **refuses to start** with the default keys.
> Generate strong secrets: `openssl rand -hex 32`.

---

## 4. Code conventions

### Dart / Flutter

- **Strict analysis**: `flutter analyze` must return **0 issues** (errors and
  warnings). The rules are defined in [`analysis_options.yaml`](analysis_options.yaml)
  (based on `flutter_lints` + strict rules: `unawaited_futures: error`,
  `avoid_print`, `prefer_single_quotes`, `prefer_const_*`, `close_sinks`,
  `always_declare_return_types`, `directives_ordering`, …).
- **Formatting**: `dart format .` (CI checks with
  `dart format --output=none --set-exit-if-changed .`).
- **Logging**: never `print()` (rule `avoid_print`). Use `debugPrint` or
  `ClientDebugLogger.instance.log(...)`.
- **Comments**: in **French**, like the rest of the code.
- **Line endings**: **LF** required (normalized by `.gitattributes`).
- **Strings**: single quotes (`prefer_single_quotes`).

### Internationalization

- Every user string goes in `lib/l10n/app_*.arb` (**fr, en, nl, de**).
- Regenerate localizations after editing ARB files: `flutter gen-l10n`.

### JavaScript / server

- Format with Prettier (config `.prettierrc`).
- Keep the existing `server/src/` structure (auth, mesh, sync…).
- No hardcoded secrets; everything goes through `.env`.

---

## 5. Tests & static analysis

Before opening a PR, at minimum run:

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed .
node scripts/sync_branding.js --check   # branding consistency (where applicable)
```

- Tests use **`mocktail`** (see `test/`).
- Test coverage is still low on critical layers (`network/`, `routing/`,
  `database/`): any contribution to these layers must be **accompanied by tests**.

---

## 6. Git: branches, commits, tags

### Branches

The repository uses **per-platform/domain** branches:

| Branch | Purpose |
|---|---|
| `main` | main branch (global CI) |
| `admin` | administration features |
| `android` / `ios` / `windows` | platform-specific builds |
| `server` | Node.js server |

Recommended flow:

1. Create a descriptive branch: `feature/…` or `fix/…`.
2. Open a **pull request** against `main` (or the relevant platform branch).
3. CI (`ci.yml`) must be green (analysis + tests + format + branding).

### Commits

Keep commits **small and atomic**, with a clear message. Examples of the style
already used:

```text
fix(android): force compileSdk 36 on reactive_ble_mobile in CI
chore: automate GitHub releases
docs: document the release process
```

### Version tags (⚠️ important)

Releases are **only** triggered by a tag in the **`vX.Y.Z`** format
(e.g. `v2.3.0`). This is the format expected by the app's update manager
(`GithubUpdateService`). Do **not** use any other format.

---

## 7. CI/CD & publishing a release

GitHub Actions workflows:

| Workflow | Trigger | Role |
|---|---|---|
| `ci.yml` | push/PR on `main` | analysis, tests, format, branding |
| `buildAndroid.yml` / `buildIOS.yml` / `buildWindows.yml` / `buildServer.yml` | push/PR on the dedicated branch | per-platform builds |
| `release.yml` | tag `v*` (or manual) | builds the executables **and** creates the GitHub release |
| `static.yml` | push on `main` | deploys the showcase site to GitHub Pages |

### Publishing a version

From a workstation:

```powershell
# Bump the version and push the tag (triggers release.yml)
powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Bump patch

# … or force a specific version
powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 2.3.0
```

The script updates `pubspec.yaml` (version + build number), commits, creates the
`vX.Y.Z` tag, and pushes it. GitHub Actions then builds **Windows (EXE)**,
**Linux (tar.gz)** and **Android (APK + AAB)** and publishes the release.

---

## 8. Security & privacy

StreetPhare is built **GDPR by design**. Read [`SECURITY.md`](SECURITY.md)
before touching any network, encryption, identity, or persistence logic.

Key points:

- **Anonymity**: rotating ephemeral UUIDs (`Random.secure`), no personal data.
- **Confidentiality**: end-to-end encryption AES-256-CBC + HMAC-SHA256.
- **Integrity**: Ed25519 signatures, HMAC verification.
- **Limited retention**: strict TTLs per alert type, right to be forgotten (Hive purge).
- **Kill switch**: remote deactivation in case of compromise.

**Forbidden**: any tracking SDK, any telemetry, any UUID/location logging,
any PII storage.

### Reporting a vulnerability

**Do NOT open a public issue.** Use:

1. The repository's **Security → Advisories → Report a vulnerability** tab; or
2. `security@streetphare.org`.

---

## 9. Technical constraints not to break (anti-drift)

Some values are the result of documented trade-offs. **Do not change them
without explicit validation**:

### Android build

- **AGP 9.3.1**, **Gradle 9.5.0**, **Kotlin 2.4.20** (`android/settings.gradle.kts`).
- **JDK 21** required (AGP 9.3's lint/R8 requires Java 21 APIs).
- `android.builtInKotlin=false` and `android.newDsl=false` (the "Built-in Kotlin"
  migration is **deliberately deferred**: several plugins still apply KGP manually).
- Gradle Metaspace set to **2048m** (`android/gradle.properties`): do not reduce
  it, otherwise `OutOfMemoryError: Metaspace`.

### Pinned dependencies (`pubspec.yaml`)

The following `dependency_overrides` must **not be removed** without full testing:

```yaml
dependency_overrides:
  shared_preferences_android: 2.4.27   # avoids the Pigeon/JNI migration (incompatible with AGP 9 / R8)
  permission_handler_android: 13.0.1
  reactive_ble_mobile: 5.5.0           # 5.6.0 requires Built-in Kotlin
```

### CI patch for `reactive_ble_mobile`

The `reactive_ble_mobile` 5.5.0 plugin (pub.dev) declares `compileSdk 33`, which
is insufficient for its AndroidX dependencies. The script
`scripts/patch_reactive_blemobile.sh` forces `compileSdk/targetSdk 36` in CI.
Do not remove this patch.

---

## 10. Reporting a bug (non-security)

- Open a **GitHub issue** describing: app version, platform, reproduction steps,
  expected vs. observed behavior, screenshots/logs.
- Label it appropriately (bug, enhancement, …).

---

## 11. License

StreetPhare is distributed under **GPLv3** (see [`LICENSE`](LICENSE)). By
contributing, you agree that your contributions are released under this license.



