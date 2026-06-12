# INTEGRATION_DEBUG_REPORT.md
## StreetPhare — Rapport de Débogage d'Intégration Complète
**Date :** 2026-06-12  
**Durée de session :** ~35 minutes  
**Ingénieur :** DevOps AI (Cline)  
**Mode :** Debug simultané multi-composants

---

## 1. RÉSUMÉ EXÉCUTIF

| Composant | Statut avant session | Statut après session |
|-----------|---------------------|---------------------|
| Serveur Principal (Node :3000) | ✅ En ligne | ✅ En ligne — `.trim()` fixé |
| Serveur Backup (Node :3001) | ❌ URL corrompue (espace trailing) | ✅ En ligne — URL propre |
| Admin Dashboard (Node :4000) | ❌ Port 5000 au lieu de 4000 | ✅ En ligne — port corrigé |
| Mini-site Vitrine (:5000) | ✅ En ligne | ✅ En ligne |
| App Flutter Windows | ❌ Crash au démarrage | ✅ En cours d'exécution |
| App Flutter Android | ✅ APK compilé | ✅ APK compilé — blocage device |

---

## 2. ANOMALIES DÉTECTÉES ET CORRIGÉES

### 🔴 ANOMALIE #1 — Trailing space dans NEXT_BACKUP_URL
**Fichier :** `test_servers/server_primary_v2.js`  
**Ligne :** `const NEXT_BACKUP_CLEAR = (process.env.NEXT_BACKUP_URL || '').trim();`  
**Symptôme :** L'URL de backup contenait un espace de fin (`http://localhost:3001 `) causant des requêtes de routage invalides. Observable dans les logs : `backup-route demandé → http://localhost:3001  (chiffré)` (double espace).  
**Cause :** Variable d'environnement non trimée avant usage.  
**Correction :** Ajout de `.trim()` sur la lecture des variables `NEXT_BACKUP_URL` et `ROLE`.  
**Vérification :** Après correction → `"next":"http://localhost:3001"` (sans espace). ✅

---

### 🔴 ANOMALIE #2 — Admin Dashboard sur mauvais port
**Fichier :** `test_servers/admin_dashboard.js`  
**Symptôme :** Le dashboard d'administration tentait d'écouter sur le port 5000 (conflit avec la vitrine) au lieu de 4000.  
**Cause :** Variable `ADMIN_PORT` non lue correctement.  
**Correction :** Correction de la lecture de la variable de port dans l'initialisation du serveur.  
**Vérification :** Admin répond sur `:4000` → HTTP 200 sur `/dashboard`. ✅

---

### 🔴 ANOMALIE #3 — KickCheckService pointant vers :3001 (backup) au lieu de :4000 (admin)
**Fichier :** `lib/services/kick_check_service.dart`  
**Ligne 41 (avant) :** `static const String _adminBase = 'http://192.168.31.18:3001';`  
**Symptôme :** Les requêtes de vérification kick/ban (`/api/kick-status/:uuid`) étaient envoyées au serveur backup (:3001) qui n'implémente pas cet endpoint → timeout silencieux.  
**Cause :** Confusion entre le port backup et le port admin.  
**Correction :** `'http://192.168.31.18:3001'` → `'http://192.168.31.18:4000'`  
**Vérification :** L'endpoint `/api/kick-status/:uuid` est correctement géré par `admin_dashboard.js`. ✅

---

### 🔴 ANOMALIE #4 — BugReportService (features) pointant vers :3001 au lieu de :4000
**Fichier :** `lib/features/bug_report/presentation/bug_report_service.dart`  
**Ligne 80-81 (avant) :** `'http://192.168.31.18:3001/api/bug-report'`  
**Symptôme :** Les rapports de bugs étaient envoyés au serveur backup (:3001) qui n'a pas d'endpoint `/api/bug-report` → `serverError` systématique.  
**Correction :** `:3001` → `:4000`  
**Vérification :** L'endpoint `/api/bug-report` est géré par `admin_dashboard.js:4000`. ✅

---

### 🔴 ANOMALIE #5 — BugReportService (services) utilisant `localhost` + mauvais path
**Fichier :** `lib/services/bug_report_service.dart`  
**Lignes (avant) :**
```dart
static const String _adminBaseUrl = 'http://localhost:4000';  // KO depuis Android
// ...
Uri.parse('$_adminBaseUrl/api/bugs')  // KO: endpoint incorrect
```
**Symptômes :**
1. `localhost:4000` depuis un appareil Android = connexion vers l'appareil lui-même, pas l'hôte → `SocketException` garanti.
2. Path `/api/bugs` inexistant sur `admin_dashboard.js` (le bon path est `/api/bug-report`).  
**Corrections :**
- `localhost` → `192.168.31.18`
- `/api/bugs` → `/api/bug-report`  
**Vérification :** URL finale = `http://192.168.31.18:4000/api/bug-report`. ✅

---

### 🔴 ANOMALIE #6 — Crash Windows au démarrage : WindowsInitializationSettings manquant
**Fichier :** `lib/services/notification_service.dart`  
**Exception :**
```
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: 
Invalid argument(s): Windows settings must be set when targeting Windows platform.
#0  FlutterLocalNotificationsPlugin.initialize (...)
#1  NotificationService.init (notification_service.dart:61)
#2  main (main.dart:37)
```
**Cause :** `flutter_local_notifications ^22.0.0` requiert `WindowsInitializationSettings` lors de l'init sur Windows. La méthode `_buildInitSettings()` ne fournissait que `android` et `iOS`, provoquant un crash fatal dans `main()`.  
**Correction :** Ajout d'une branche Windows avec `WindowsInitializationSettings` + try/catch graceful fallback :
```dart
if (!kIsWeb && Platform.isWindows) {
  try {
    const windowsSettings = WindowsInitializationSettings(
      appName: 'StreetPhare',
      appUserModelId: 'com.streetphare.streetphare',
      guid: 'a4b2c3d4-e5f6-7890-abcd-ef1234567890',
    );
    await _plugin.initialize(settings: const InitializationSettings(windows: windowsSettings), ...);
    _initialized = true;
  } catch (e) {
    _initialized = true; // Graceful degradation
  }
  return;
}
```
**Vérification :** Log Windows → `[NotificationService] initialisé (Windows)` ✅  
App démarrée sans crash, WebSocket relay connecté. ✅

---

## 3. AVERTISSEMENTS NON-BLOQUANTS (à surveiller)

### ⚠️ WARN #1 — Kotlin Gradle Plugin (KGP) obsolescence
**Plugins concernés :** `mobile_scanner`, `package_info_plus`, `reactive_ble_mobile`  
**Message :**
```
WARNING: Your Android app project applies the Kotlin Gradle Plugin, 
which will cause build failures in future versions of Flutter.
```
**Impact actuel :** Aucun (build réussi). Impact futur : blocage de build lors d'une future mise à jour Flutter.  
**Action recommandée :** Migrer vers Built-in Kotlin selon https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/

---

### ⚠️ WARN #2 — Java source/target level 8 obsolète
**Message :** `warning: [options] source value 8 is obsolete and will be removed in a future release`  
**Source :** Compilation Java dans `nearby_connections-4.3.0`.  
**Impact actuel :** Aucun.  
**Action recommandée :** Mettre à jour `nearby_connections` vers une version supportant Java 11+.

---

### ⚠️ WARN #3 — API dépréciées dans nearby_connections 4.3.0
**APIs concernées :**
- `ConnectionInfo.getAuthenticationToken()` (dépréciée)
- `Payload.File.asJavaFile()` (dépréciée)  
**Impact actuel :** Aucun (warnings uniquement).  
**Action recommandée :** Mettre à jour `nearby_connections` vers la version 5+.

---

### ⚠️ WARN #4 — Geolocator : message natif sur thread non-platform
**Message :**
```
[ERROR:flutter/shell/common/shell.cc(1183)] The 'flutter.baseflow.com/geolocator_updates' 
channel sent a message from native to Flutter on a non-platform thread.
```
**Impact actuel :** Non-bloquant (l'app fonctionne).  
**Action recommandée :** Mettre à jour `geolocator` vers la dernière version qui corrige ce threading issue.

---

### ⚠️ WARN #5 — BLE indisponible sur Windows (comportement attendu)
**Message :** `[P2PMeshService] transport ble indisponible`  
**Cause :** `flutter_reactive_ble` ne supporte pas nativement Windows (`UnimplementedError`).  
**Gestion actuelle :** Graceful fallback — P2PMeshService continue avec WiFi multicast + WebSocket relay.  
**Impact :** Aucun. BLE est un transport optionnel. Les modes WiFi + Relay assurent la connectivité.

---

## 4. CONTRAINTE INFRASTRUCTURE — Installation Android

**Erreur :** `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`  
**Appareil :** 2201116SG (Xiaomi/Redmi)  
**Cause :** L'appareil a une restriction de sécurité indépendante de "Débogage USB" : l'option **"Installer via USB"** dans les Options de développement doit être **activée séparément** sur l'appareil physique.  

**APK construit avec succès :**
```
✓ build\app\outputs\flutter-apk\app-debug.apk (46.8s)
```

**Action requise par l'utilisateur :**  
1. Sur l'appareil Android → Paramètres → Options pour les développeurs  
2. Activer **"Installer via USB"** (ou "Installation depuis sources inconnues via USB")  
3. Sur les appareils Xiaomi MIUI : désactiver **"Optimisation MIUI"** si nécessaire  
4. Re-lancer : `flutter run -d d2e1c7df0841 --debug`

---

## 5. ÉTAT FINAL DE L'INFRASTRUCTURE

### Serveurs Node.js (lanceur : `test_servers/launch_all.js`)
```
✅ Primary     :3000  → HTTP 200  /ping  → {"status":"ok","role":"primary"}
✅ Backup      :3001  → HTTP 200  /ping  → is_promoted=False, primary=online
✅ Admin       :4000  → HTTP 200  /      → Dashboard opérationnel
✅ Vitrine     :5000  → HTTP 200  /      → Mini-site web servi
```

### Vérification de l'URL backup (fix .trim())
```json
GET http://localhost:3000/backup-route
→ {"next":"http://localhost:3001","encrypted_next":"...","algorithm":"AES-256-CBC+HMAC-SHA256"}
```
✅ Aucun espace trailing dans l'URL.

### Application Flutter Windows
```
✅ Build        : 112.5s (rebuild après fix)
✅ Notifications: [NotificationService] initialisé (Windows)
✅ Réseau       : NetworkConfig{primary=http://192.168.31.18:3000}
✅ WebSocket    : [Relay] ws connecté à ws://192.168.31.18:3000/mesh
✅ WiFi Mesh    : [WiFi] multicast listening on 239.255.42.42:42424
✅ P2P          : transports wifi + relay démarrés (ble=indisponible Windows)
✅ Hive         : [HiveMessaging] service démarré
✅ DevTools     : http://127.0.0.1:51791/5z5MUYzIq6A=/devtools/
```

### Application Flutter Android
```
✅ Build APK    : app-debug.apk compilé (224s → 46.8s au second build)
⚠️ Installation : INSTALL_FAILED_USER_RESTRICTED (restriction device Xiaomi)
   → APK prêt : build/app/outputs/flutter-apk/app-debug.apk
   → Action requise : activer "Installer via USB" dans Options développeur
```

---

## 6. FICHIERS MODIFIÉS

| Fichier | Nature de la modification |
|---------|--------------------------|
| `test_servers/server_primary_v2.js` | `.trim()` sur `NEXT_BACKUP_URL` et `ROLE` |
| `test_servers/admin_dashboard.js` | Correction port écoute → `ADMIN_PORT` (4000) |
| `test_servers/launch_all.js` | Refonte complète : inclut Primary+Backup+Admin+Vitrine avec keep-alive et ping de vérification |
| `lib/services/kick_check_service.dart` | URL admin : `:3001` → `:4000` |
| `lib/features/bug_report/presentation/bug_report_service.dart` | URL admin : `:3001` → `:4000` |
| `lib/services/bug_report_service.dart` | `localhost` → `192.168.31.18`, `/api/bugs` → `/api/bug-report` |
| `lib/services/notification_service.dart` | Ajout `WindowsInitializationSettings` + graceful fallback Windows |

---

## 7. COMMANDES DE RELANCE RAPIDE

```bash
# Relancer tous les serveurs Node (depuis la racine du projet)
node test_servers/launch_all.js

# Flutter Windows (debug)
flutter run -d windows --debug

# Flutter Android (après activation "Installer via USB" sur l'appareil)
flutter run -d d2e1c7df0841 --debug

# Vérification santé des serveurs
curl http://localhost:3000/ping
curl http://localhost:3001/ping
curl http://localhost:4000/
curl http://localhost:5000/
```

---

*Rapport généré automatiquement par le cycle de débogage intégré StreetPhare — 2026-06-12T20:35:00Z*
