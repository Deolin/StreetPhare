# Rapport d'Audit & Plan d'Action — StreetPhare v3.3.3

**Date** : 2 juillet 2026
**Auteur** : Cline (audit automatisé)
**Périmètre** : Workspace complet (Flutter + Node.js + Caddy)

---

## 1. ÉTAT DES LIEUX

### 1.1 Architecture réseau actuelle

```text
[Client Flutter Android]
    │
    ├──▶ wss://streetphare.ddns.net/mesh        (WebSocket mesh, port 443 → Caddy → Node.js :3000)
    ├──▶ https://streetphare.ddns.net/api/*      (API REST, port 443 → Caddy → Node.js :3000)
    ├──▶ https://streetphare.ddns.net:3001/*     (Backup, port 3001 → Caddy → Node.js :3001)
    └──▶ https://streetphare.ddns.net:4000/*     (Admin dashboard, port 4000 → Caddy → :4000)

[Caddy (TLS termination)]
    ├── :443 → 127.0.0.1:3000 (Primary Node.js)
    ├── :3001 (TLS) → 127.0.0.1:3001 (Backup Node.js)
    └── :4000 (TLS) → 127.0.0.1:4000 (Admin)

[Node.js Primary]  127.0.0.1:3000  (HTTP)
[Node.js Backup]   127.0.0.1:3001  (HTTP)
```

### 1.2 Analyse des erreurs critiques

#### A. WebSocket `/mesh` — Fermeture après 2ms (code 1002/1006)

**Symptômes** :

- Client Dart se connecte à `wss://streetphare.ddns.net/mesh`
- Le serveur envoie le `welcome` avec succès
- 2ms après, la connexion se ferme avec code 1002 (Protocol Error) ou 1006 (Abnormal Closure)
- Le serveur loggue `Origin: N/A` dans les diagnostics d'upgrade

**Diagnostic** :

1. **Côté client (DÉJÀ CORRIGÉ v3.3.3)** : `RelayMeshTransport._connect()` injecte `Origin: https://streetphare.ddns.net` dans le handshake WebSocket (ligne 128-132 de `relay_transport.dart`). Utilise `dart:io WebSocket.connect()` directement (bypass GuaranteeChannel depuis v3.3.0).

2. **Côté Caddy — PROBLÈME IDENTIFIÉ** : Dans le bloc `handle /mesh*` du `Caddyfile` (lignes 16-30), Caddy fait `header_up Host {host}` et `header_up X-Forwarded-For {remote_host}`, mais **ne transmet PAS l'en-tête `Origin`** du client mobile vers Node.js. Sans `header_up Origin {header.origin}`, Node.js reçoit `Origin: N/A` car Caddy ne forward pas cet en-tête.

3. **Côté Node.js — PROBLÈME IDENTIFIÉ** : `app.use(cors())` à la ligne 58 de `primary.js` utilise la configuration CORS par défaut. La config par défaut de `cors()` n'autorise les requêtes qu'avec un en-tête Origin valide. Les connexions WebSocket (upgrade HTTP) sans Origin peuvent être rejetées ou mal gérées, surtout quand le middleware CORS intercepte la requête d'upgrade avant qu'elle n'atteigne le WebSocketServer.

**Action corrective** :

- [Caddy] Ajouter `header_up Origin {header.origin}` dans le bloc `/mesh*`
- [Node.js] Configurer CORS avec `origin: true` ou une liste blanche explicite pour accepter les connexions provenant de Caddy (qui forwardera désormais l'Origin)

#### B. FailoverManager / SyncService — Timeout 15s sur IP locale

**Symptômes** :

- Le FailoverManager ping `https://streetphare.ddns.net:3001/healthz` (adresse de secours)
- Échec → fallback local `http://10.0.2.2:3001/healthz`
- Timeout de 15s car `10.0.2.2` est l'adresse de l'hôte **pour l'émulateur Android uniquement**, pas pour un appareil physique
- Le SyncService tente `https://streetphare.ddns.net:3001/api/sync-check` avec le même timeout

**Diagnostic** :

1. `NetworkConfig._localFallbackHost` (lignes 155-163 de `network_config.dart`) retourne `10.0.2.2` pour Android — **cette adresse n'est valide que sur l'émulateur Android**. Sur un appareil physique Android connecté en USB, l'hôte PC est accessible via son adresse IP sur le réseau local (ex: `192.168.31.63`) ou via `adb reverse` (qui mappe un port du device vers l'hôte).

2. `FailoverManager._resolveLocalFallback()` (lignes 514-522) utilise ce fallback incorrect, menant à des timeouts.

3. **La chaîne de secours est correcte** : `NetworkConfig.initialSecondaryServer` retourne `https://streetphare.ddns.net:3001` (ligne 89-91), qui est chiffrée et déchiffrée correctement. Le Caddyfile expose bien le port 3001 avec TLS. **Le problème est purement dans la résolution DNS/NAT hairpinning** et le fallback local incorrect.

**Action corrective** :

- [Flutter] Ajouter une détection device physique vs émulateur dans `_localFallbackHost`
- [Flutter] Sur device physique, utiliser l'adresse IP locale du réseau (configurable) ou `127.0.0.1` après `adb reverse`
- [Alternative] S'assurer que le serveur est accessible depuis l'extérieur (DNS publique, ports ouverts) pour que le client n'ait pas besoin de fallback local

### 1.3 Caddyfile — Analyse complète

Le `Caddyfile` (v3.3.3, 100 lignes) gère correctement :

- ✅ TLS automatique Let's Encrypt pour `streetphare.ddns.net`
- ✅ `header_up Host {host}` et `header_up X-Forwarded-For` dans tous les blocs
- ✅ Exposition du Backup sur port 3001 avec TLS
- ✅ Exposition de l'admin dashboard sur port 4000 avec TLS
- ❌ **MANQUE** : `header_up Origin {header.origin}` dans le bloc `/mesh*`
- ❌ **MANQUE** : `header_up Upgrade {header.upgrade}` et `header_up Connection {header.connection}` dans le bloc `/mesh*` — Caddy devrait transmettre explicitement ces en-têtes pour le handshake WebSocket

### 1.4 Configuration Kotlin Gradle Plugin

| Composant | Version actuelle | Statut |
|-----------|-----------------|--------|
| KGP | 2.2.20 | Déclaré manuellement dans `settings.gradle.kts` |
| AGP | 9.0.1 | Déclaré manuellement |
| Built-in Kotlin | **DÉSACTIVÉ** | `android.builtInKotlin=false` dans `gradle.properties` |
| compileSdk | 36 | Correct |
| JVM Target (app) | 17 | Correct |

**Blocage de la migration** : plugins tiers (`connectivity_plus`, etc.) qui appliquent `kotlin-android` manuellement. Une migration forcée casserait la compilation. La désactivation est légitime pour le moment.

**Risque** : Flutter 3.x+ impose le built-in Kotlin. Rester sur KGP 2.2.20 manuel fonctionne mais pourrait casser lors d'une future mise à jour Flutter. Le warning KGP au build est cosmétique, pas bloquant.

**Recommandation** : Maintenir `builtInKotlin=false` pour le moment, mais planifier une migration progressive (vérifier que tous les plugins sont compatibles avec le built-in Kotlin).

### 1.5 Autres observations

- ✅ `relay_transport.dart` : Protection anti-1002 en place (try/catch autour du listener)
- ✅ `relay_transport.dart` : Injection d'Origin en place
- ✅ `primary.js` : Cooldown de reconnexion réduit à 500ms (anti-boucle)
- ✅ `primary.js` : Limitation du welcome backlog à 50 messages
- ✅ Heartbeat serveur (ping RFC 6455 natif toutes les 30s)
- ✅ `sync_service.dart` : Backoff rate-limit correct, push-pull bidirectionnel
- ✅ `Caddyfile` : TLS 1.2/1.3, HSTS, logs séparés par service
- ⚠️ `server/.env` : `PARTNER_URL=http://127.0.0.1:3001` — correct pour synchro Primary↔Backup locale

---

## 2. PLAN D'ACTION

### Étape 2A — Correction WebSocket / Mesh

| # | Action | Fichier | Impact |
|---|--------|---------|--------|
| A1 | Ajouter `header_up Origin {header.origin}` dans le bloc `/mesh*` du Caddyfile | `server/Caddyfile` | Transmet l'Origin du client mobile à Node.js |
| A2 | Ajouter `header_up Upgrade {header.upgrade}` et `header_up Connection {header.connection}` | `server/Caddyfile` | Assure la transmission correcte du handshake WebSocket |
| A3 | Configurer CORS avec `origin: true` pour accepter toutes les origines (la sécurité est gérée par Caddy/TLS) | `server/src/primary.js` | Évite le rejet des connexions sans Origin |
| A4 | Vérifier que le serveur répond correctement aux pings/pongs RFC 6455 | `server/src/primary.js` | ✅ Déjà OK (lignes 192-234) |

### Étape 2B — Correction FailoverManager / SyncService / Caddyfile

| # | Action | Fichier | Impact |
|---|--------|---------|--------|
| B1 | Ajouter une détection device physique vs émulateur dans `_localFallbackHost` | `lib/network/network_config.dart` | Évite le fallback vers 10.0.2.2 sur device physique |
| B2 | Sur device physique Android, utiliser une IP configurable (variable d'environnement `STREETPHARE_LOCAL_HOST`) ou par défaut l'IP du réseau local | `lib/network/network_config.dart` | Permet le fallback local correct |
| B3 | Ajouter `adb reverse` automatique au script de déploiement | `scripts/` | Redirige les ports du device vers l'hôte |
| B4 | Vérifier que le endpoint `/healthz` existe côté serveur | `server/src/` | Le FailoverManager ping `/healthz` mais ce endpoint n'est peut-être pas défini |
| B5 | Le Caddyfile pour le Backup (port 3001) est correct | `server/Caddyfile` | ✅ Déjà OK |

### Étape 2C — Migration Kotlin

| # | Action | Fichier | Impact |
|---|--------|---------|--------|
| C1 | Tester l'activation du built-in Kotlin (`builtInKotlin=true`) | `android/gradle.properties` | Vérifier la compatibilité des plugins |
| C2 | Si échec, documenter le blocage et maintenir la config actuelle | `android/gradle.properties` | Pas de régression |

### Étape 3 — Déploiement & Validation

| # | Action | Outil | Critère de succès |
|---|--------|-------|-------------------|
| V1 | `flutter build apk --debug` | Flutter | Build sans erreur |
| V2 | `flutter run -d <tablette>` | Flutter | App déployée et lancée |
| V3 | Observer les logs WebSocket | `adb logcat` + console | `[Relay] ws connecté` sans déconnexion < 5s |
| V4 | Vérifier le heartbeat | Logs FailoverManager | `heartbeat OK` consécutifs |
| V5 | Vérifier la synchro | Logs SyncService | `Push-pull bidirectionnel réussi` |

---

## 3. FICHIERS DEVANT ÊTRE MODIFIÉS

| Fichier | Modification prévue | Priorité |
|---------|-------------------|----------|
| `server/Caddyfile` | Ajout `header_up Origin`, `Upgrade`, `Connection` dans `/mesh*` | **CRITIQUE** |
| `server/src/primary.js` | Configuration CORS plus permissive | **CRITIQUE** |
| `lib/network/network_config.dart` | Détection device physique + fallback local correct | **CRITIQUE** |
| `lib/core/network/peer_counter_service.dart` | Vérification endpoint `/healthz` | HAUTE |
| `android/gradle.properties` | Test built-in Kotlin (optionnel) | BASSE |

---

*Fin du rapport d'audit. Prêt pour l'exécution du plan.*
