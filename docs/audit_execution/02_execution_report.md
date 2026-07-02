# Rapport de Clôture — Exécution des Correctifs StreetPhare v3.3.4

**Date** : 2 juillet 2026
**Auteur** : Cline (exécution automatisée)
**Statut** : ✅ Corrections appliquées, build en cours de déploiement

---

## 1. RÉSUMÉ DES MODIFICATIONS

### Fichiers modifiés (ordre d'exécution)

| # | Fichier | Modification | Justification |
|---|---------|-------------|---------------|
| 1 | `server/Caddyfile` | Ajout `header_up Origin`, `Upgrade`, `Connection` dans `/mesh*` | Transmettre les en-têtes de handshake WebSocket du client mobile vers Node.js. Sans cela, Node.js recevait Origin: N/A → code 1006 |
| 2 | `server/src/primary.js` | CORS `{ origin: true, credentials: true }` au lieu de `cors()` par défaut | Accepter les connexions WebSocket dont l'Origin est transmise par Caddy |
| 3 | `lib/network/failover_manager.dart` | `/healthz` → `/api/ping` (lignes 456 et 479) | Le serveur expose `/api/ping` (pas `/healthz`). Le heartbeat échouait systématiquement → boucle de failover infinie |
| 4 | `lib/network/network_config.dart` | Fallback local : `10.0.2.2` → `127.0.0.1` + support `--dart-define` | Sur device physique Android, `10.0.2.2` (émulateur) ne fonctionne pas. `127.0.0.1` fonctionne avec `adb reverse` |
| 5 | `lib/features/bug_report/presentation/bug_report_fab.dart` | Correction import `../../../../main.dart` → `../../../main.dart` | Chemin d'import incorrect causait une erreur de compilation |

### Fichiers NON modifiés

| Fichier | Raison |
|---------|--------|
| `android/gradle.properties` | `builtInKotlin=false` maintenu — plugins tiers incompatibles (connectivity_plus, cryptography_flutter, etc.) |
| `server/.env` | Configuration correcte pour l'infrastructure actuelle |
| `server/src/config.js` | Aucune modification nécessaire |
| `lib/network/relay_transport.dart` | Déjà corrigé en v3.3.3 (injection Origin + bypass GuaranteeChannel) |

---

## 2. DÉTAIL DES CORRECTIFS

### 2A — Correction WebSocket / Mesh

#### Problème

- Client Dart `RelayMeshTransport` injectait `Origin: https://streetphare.ddns.net`
- Caddy ne transmettait PAS cet en-tête à Node.js
- Node.js voyait `Origin: N/A` → le middleware CORS + WebSocket fermait la connexion (code 1006)
- Résultat : boucle de reconnexion toutes les 5 secondes

#### Solution

1. **Caddyfile** (bloc `/mesh*`) : ajout de `header_up Origin {header.origin}`, `header_up Upgrade {header.upgrade}`, `header_up Connection {header.connection}`
2. **primary.js** : `cors({ origin: true, credentials: true })` pour accepter toutes les origines transmises

#### Impact attendu

- Le handshake WebSocket RFC 6455 aboutit complètement
- Le `welcome` est envoyé ET reçu sans déconnexion
- Heartbeat stable, pas de boucle de reconnexion

### 2B — Correction FailoverManager / SyncService

#### Problème

- `FailoverManager._ping()` utilisait l'endpoint `/healthz`
- Le serveur expose `/api/ping` (route définie dans `api.js`)
- Résultat : heartbeat toujours KO → failover déclenché → timeout 15s
- Fallback local utilisait `10.0.2.2` (émulateur uniquement), inopérant sur device physique

#### Solution

1. **failover_manager.dart** : `/healthz` → `/api/ping` (2 occurrences)
2. **network_config.dart** : `_localFallbackHost` utilise `127.0.0.1` (compatible `adb reverse`) + flag compile-time `--dart-define=STREETPHARE_LOCAL_HOST=<ip>`
3. **adb reverse** : exécuté pour rediriger ports 3000, 3001, 4000 du device vers l'hôte

#### Impact attendu

- Heartbeat OK immédiatement (pas de tentative de failover systématique)
- SyncService push-pull bidirectionnel fonctionnel
- Si le serveur est vraiment down, le failover vers `https://streetphare.ddns.net:3001` fonctionne

### 2C — Migration Kotlin

#### Statut : BLOQUÉE (pas une régression)

- Le `builtInKotlin=false` est volontaire et documenté
- 7 plugins tiers appliquent Kotlin manuellement : `cryptography_flutter`, `flutter_foreground_task`, `mobile_scanner`, `objectbox_flutter_libs`, `package_info_plus`, `reactive_ble_mobile`, `share_plus`
- Le build fonctionne avec KGP 2.2.20 + AGP 9.0.1
- La migration sera nécessaire quand Flutter l'imposera, mais ce n'est pas le cas aujourd'hui

---

## 3. INFRASTRUCTURE DE DÉPLOIEMENT

### Commandes exécutées pour le déploiement

```bash
# Redirection des ports pour le débogage USB
adb reverse tcp:3000 tcp:3000  # Primary Node.js
adb reverse tcp:3001 tcp:3001  # Backup Node.js
adb reverse tcp:4000 tcp:4000  # Dashboard admin

# Build + déploiement sur tablette
flutter run -d 8796AGCFEJ00167500 --debug
```

### Appareil cible

- **Modèle** : T65Plus EEA
- **ID** : 8796AGCFEJ00167500
- **Architecture** : android-arm64
- **OS** : Android 15 (API 35)

---

## 4. VALIDATION ATTENDUE

Une fois l'application déployée, les critères suivants doivent être vérifiés :

| # | Test | Indicateur de succès |
|---|------|---------------------|
| V1 | Connexion WebSocket mesh | `[Relay] ws connecté` + pas de déconnexion < 5s |
| V2 | Heartbeat FailoverManager | `[FailoverManager] heartbeat OK` consécutifs |
| V3 | Welcome serveur reçu | Pas de code 1002/1006 après 2ms |
| V4 | Sync push-pull | `[SyncService] Push-pull bidirectionnel réussi` |
| V5 | Interface UI | Carte interactive chargée, icône 🟢 dans la barre de statut |

---

## 5. INSTRUCTIONS DE MAINTENANCE

### Redémarrage du serveur après modifications du Caddyfile

```bash
cd server
# Recharger Caddy avec la nouvelle configuration
caddy reload --config Caddyfile
# OU redémarrer le serveur Node.js (qui relance Caddy automatiquement)
npm run dev:primary
```

### Déploiement sur device physique (sans émulateur)

```bash
# 1. Rediriger les ports
adb reverse tcp:3000 tcp:3000
adb reverse tcp:3001 tcp:3001
adb reverse tcp:4000 tcp:4000

# 2. Lancer avec l'IP locale si le serveur est sur une autre machine
flutter run --dart-define=STREETPHARE_LOCAL_HOST=192.168.1.42
```

### Vérification de l'infrastructure

```bash
# Vérifier que le serveur répond
curl https://streetphare.ddns.net/api/ping

# Vérifier le backup
curl https://streetphare.ddns.net:3001/api/ping

# Vérifier le WebSocket
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Origin: https://streetphare.ddns.net" https://streetphare.ddns.net/mesh
```

---

*Rapport généré automatiquement le 2 juillet 2026.*
