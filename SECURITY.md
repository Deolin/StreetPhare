# Security Policy

> **Version** : 2.2.0+1  
> **Date** : 22/06/2026  
> **Licence** : GPLv3  

## Supported Versions

The table below identifies the versions of StreetPhare that actively receive security updates and patches.

| Version | Supported |
| ------- | --------- |
| >= 1.0.x | :white_check_mark: Yes |
| < 1.0.0 | :x: No |

We only support the latest major release. We recommend all users and contributors update their application to the most recent version available to ensure they benefit from the latest security improvements.

## Reporting a Vulnerability

**DO NOT open a public GitHub Issue to report a security vulnerability.** Public disclosure risks exposing users to threats before a fix can be deployed.

If you discover a security vulnerability or a critical flaw within StreetPhare, please report it through one of the following private channels:

1. **GitHub Private Vulnerability Reporting:** Go to the "Security" tab of this repository, click on "Advisories", and select "Report a vulnerability" to submit a confidential report directly to the core development team.
2. **Secure Email:** Send a detailed report to `security@streetphare.org` (replace with your production security email address).

### What to Include in Your Report

To help us triage and resolve the issue efficiently, please include:

- A description of the vulnerability and its potential impact.
- Detailed step-by-step instructions to reproduce the issue (or a proof-of-concept script/exploit).
- Any specific configuration or environment details required to trigger the flaw.

### Our Response and Disclosure Process

- **Acknowledgement:** We will acknowledge receipt of your report within 48 hours.
- **Triage and Investigation:** The engineering team will investigate the issue privately to assess its severity and validate the findings.
- **Remediation:** We aim to develop, test, and release a security patch within a reasonable timeframe (typically under 30 days, depending on complexity).
- **Coordinated Disclosure:** A public security advisory along with credit to the reporter (if desired) will be published only after a fix has been successfully merged and deployed to users.

## Network Protection Philosophy

StreetPhare is built with user safety, resilience, and privacy as fundamental core principles. To ensure a secure environment for all users, the platform implements strict operational safeguards:

- **Decentralized Consensus & Anti-Spam:** The network uses multi-party verification and distributed validation thresholds. An alert or report is only propagated and displayed to the wider community once it reaches a defined consensus baseline, preventing spam, malicious data injection, or coordinate poisoning.
- **Privacy by Design:** Location tracking and session data are ephemeral. The architecture is explicitly designed to minimize the retention of personally identifiable information (PII) or telemetry, ensuring that physical movements cannot be cross-referenced or tracked over time.
- **Proactive Abuse Mitigation:** The application includes localized, automated mechanisms to detect and ignore erratic network behavior or bulk data flooding at the edge, maintaining mesh availability even under high-stress conditions.

## FR 1. Principes Fondateurs

StreetPhare est conçu selon un modèle **RGPD by design**. L'application ne collecte, ne stocke et ne transmet aucune donnée personnelle identifiable. Toute l'architecture est pensée pour que l'utilisateur reste anonyme, même vis-à-vis des autres utilisateurs du mesh.

| Principe                               | Implémentation                                        |
|----------------------------------------|-------------------------------------------------------|
| **Anonymat**                           | UUIDs éphémères rotatifs, aucune donnée personnelle   |
| **Confidentialité**                    | Chiffrement de bout en bout AES-256-CBC + HMAC-SHA256 |
| **Intégrité**                          | Signature Ed25519 par alerte, vérification HMAC       |
| **Durée limitée**                      | TTL strict par type d'alerte (1min à 24h max)         |
| **Pas de serveur central obligatoire** | Mesh P2P BLE / Wi-Fi Direct prioritaire               |
| **Droit à l'oubli**                    | Purge automatique Hive après expiration TTL           |
| **Kill Switch**                        | Désactivation à distance si compromission             |

---

## 2. Identité Éphémère (UUID Rotatif)

### 2.1 Génération

Chaque appareil génère un identifiant éphémère aléatoire à chaque nouvelle session :

```dart
String generateEphemeralUserId() => randomId(12);
// → base64Url(16 octets aléatoires) sans padding
// → ex: "aB3xK9mWqL7vR2tY"
```

L'UUID est :

- **Aléatoire** — `Random.secure()` (source cryptographique)
- **Court** — 12 octets (16 caractères base64) pour limiter la taille P2P
- **Rotatif** — régénéré à intervalles réguliers (chaque nouvelle session)
- **Non lié** — aucune corrélation possible entre deux UUIDs successifs
- **Non stocké** — jamais persisté au-delà de la session

### 2.2 Rotation

La rotation d'UUID est déclenchée par :

1. Redémarrage de l'application
2. Expiration d'un timer interne (configurable, défaut 24h)
3. Kill Switch distant
4. Demande explicite de l'utilisateur (bouton "Nouvelle identité")

```dart
// Mécanisme simplifié
void rotateIdentity() {
  _currentEphemeralId = generateEphemeralUserId();
  _lastRotation = DateTime.now().toUtc();
  _peerCounterService.reset(); // réinitialise le compteur de pairs
}
```

### 2.3 Pourquoi c'est important sur le terrain

Dans un contexte de manifestation ou de rassemblement public :

- Les autorités ne peuvent pas tracer un utilisateur d'alerte à l'autre
- Les autres participants ne peuvent pas identifier la source d'un signalement
- Une interception réseau ne révèle qu'un UUID temporaire sans lien avec l'appareil
- Le pistage Bluetooth/Wi-Fi est rendu inefficace par la rotation

---

## 3. Chiffrement de Bout en Bout

### 3.1 Algorithme

| Paramètre              | Valeur                               |
|------------------------|--------------------------------------|
| Chiffrement symétrique | AES-256-CBC                          |
| Authentification       | HMAC-SHA256                          |
| Taille de clé          | 256 bits (32 octets)                 |
| Taille IV              | 128 bits (16 octets)                 |
| Taille MAC             | 256 bits (32 octets)                 |
| Dérivation de clé      | SHA-256(passphrase)                  |
| Format de sortie       | base64Url( IV \|\| MAC \|\| CIPHER ) |

### 3.2 Signature des Alertes

Chaque alerte est signée avec Ed25519 :

```dart
final signed = await CryptoUtils.instance.signAlert(
  alertId: alert.id,
  type: alert.type.name,
  lat: alert.latitude,
  lng: alert.longitude,
  createdAt: alert.createdAt,
);
```

La clé privée n'est **jamais stockée** (one-shot). La clé publique est incluse dans le bundle applicatif pour vérification côté serveur.

### 3.3 Chaîne de Secours des Serveurs

Les adresses des serveurs relais sont chiffrées avec AES-256-CBC + HMAC. Le serveur primaire expose l'adresse du secondaire sous forme chiffrée :

```json
{
  "next": "http://localhost:3001",
  "encrypted_next": "base64Url(IV||MAC||CIPHER)",
  "algorithm": "AES-256-CBC+HMAC-SHA256"
}
```

Le client Flutter déchiffre via `CryptoUtils.decryptAddress()` avec la passphrase maître partagée.

---

## 4. Cycle de Vie des Données (RGPD)

### 4.1 Données Stockées Localement

| Donnée                                 | Durée de vie                        | Base                 |
|----------------------------------------|-------------------------------------|----------------------|
| Alerte (barrage, casseurs, danger)     | 10 minutes (TTL) + 24h max (RGPD)   | Hive                 |
| Alerte (policiers, autopompes, filtre) | 1 minute (TTL) + 24h max (RGPD)     | Hive                 |
| Alerte (panic individuel)              | 2 minutes (TTL) + 24h max (RGPD)    | Hive                 |
| Danger collectif                       | 10 minutes (TTL) + 24h max (RGPD)   | Hive                 |
| UUID éphémère                          | Durée de la session                 | Mémoire volatile     |
| Préférences utilisateur                | Permanent (jusqu'à désinstallation) | SharedPreferences    |
| Cache cartographique                   | 7 jours                             | Fichiers temporaires |

### 4.2 Données Transmises

| Donnée         | Destinataire                 | Chiffrée                     |
|----------------|------------------------------|------------------------------|
| Alerte P2P     | Appareils à portée BLE/Wi-Fi | Oui (AES-256)                |
| Alerte relay   | Serveur Node.js              | Oui (AES-256)                |
| UUID éphémère  | Pairs mesh                   | Non (anonyme par conception) |
| Position GPS   | Pairs mesh + serveur         | Oui (dans l'alerte chiffrée) |
| Rapport de bug | Serveur admin                | Non (debug uniquement)       |

### 4.3 Données JAMAIS Collectées

- Nom, prénom, pseudonyme
- Adresse email
- Numéro de téléphone
- Identifiants d'appareil (IMEI, MAC, IDFA, AAID)
- Contacts du répertoire
- Photos (pas d'accès à la galerie)
- Localisation en arrière-plan (hors alerte active)

---

## 5. Panic Collectif et Anonymat

L'algorithme Panic Collectif détecte automatiquement une situation de danger :

- **5 signalements "panic"** en moins de **2 minutes**
- Dans un rayon de **200 mètres**
- Génère un **danger_collectif** automatique

L'anonymat est préservé :

- Les panics individuels ne contiennent que l'UUID éphémère
- Le danger collectif généré est signé par le serveur (pas de lien avec les émetteurs)
- Les UUIDs des émetteurs ne sont jamais exposés dans la réponse

---

## 6. Kill Switch

Un mécanisme de désactivation à distance est intégré :

```http
GET /api/version/check
→ { "min_version": "2.3.0", "kill_switch": false, "message": "..." }
```

Si `kill_switch: true` ou si la version de l'appareil est inférieure à `min_version`, l'application :

1. Cesse toute émission d'alerte
2. Purge la base Hive locale
3. Régénère l'UUID éphémère
4. Affiche un message à l'utilisateur

---

## 7. Surface d'Attaque et Mitigations

| Vecteur                   | Risque | Mitigation                                              |
|---------------------------|--------|---------------------------------------------------------|
| Interception BLE          | Élevé  | Chiffrement AES-256 de la charge utile                  |
| Interception Wi-Fi Direct | Élevé  | Chiffrement AES-256 + HMAC                              |
| Usurpation d'UUID         | Moyen  | Signature Ed25519 + consensus ≥3                        |
| Rejeu d'alerte            | Moyen  | Timestamp + TTL + nonce dans le HMAC                    |
| Corrélation temporelle    | Moyen  | Rotation d'UUID, délai aléatoire de propagation         |
| Analyse de trafic         | Faible | Volume minimal, pas de heartbeat continu                |
| Compromission du serveur  | Faible | Données chiffrées, pas de lien avec l'identité réelle   |
| Rétro-ingénierie APK      | Faible | Code open source (GPLv3), pas de secret dans le binaire |

---

## 8. Responsabilités

- **Développeurs** : Ne pas intégrer de SDK de tracking tiers (Firebase, Crashlytics, etc.)
- **Utilisateurs** : Vérifier l'authenticité de l'APK (signature GPL, hash communiqué)
- **Opérateurs serveur** : Utiliser une passphrase maître forte, ne pas logger les UUIDs

---

## 9. Signalement de Vulnérabilités

Les vulnérabilités de sécurité doivent être signalées via :

- Email : `security@streetphare.org` (à créer)
- Issue GitHub avec le label `security` (données sensibles : PGP à disposition)

Délai de réponse cible : 72 heures ouvrées.

---

## 10. Conformité RGPD

| Obligation RGPD           | Implémentation StreetPhare                             |
|---------------------------|--------------------------------------------------------|
| Consentement              | Aucune donnée personnelle → pas de consentement requis |
| Droit d'accès             | Aucune donnée stockée côté serveur                     |
| Droit de rectification    | N/A (pas de données personnelles)                      |
| Droit à l'effacement      | Purge Hive automatique, Kill Switch                    |
| Portabilité               | N/A (pas de données personnelles)                      |
| Notification de violation | Transparence via GitHub + site vitrine                 |
| DPO                       | Non requis (pas de traitement de données personnelles) |
| Registre des traitements  | Documenté dans ce fichier                              |
