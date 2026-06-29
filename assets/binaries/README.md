# Assets — Binaires Embarqués

> **Dernière mise à jour** : 28/06/2026

## Mini-Downloader StreetPhare (`streetphare_downloader.apk`)

Ce répertoire doit contenir le **mini-installer Android** (~50 ko) qui sera extrait
et partagé à la place de l'APK complet (20+ Mo).

### 🔧 Génération du Mini-Downloader

```bash
# Depuis la racine du projet StreetPhare :
cd android
./gradlew :mini_downloader:assembleRelease
# Le .apk produit est à copier ici :
cp mini_downloader/build/outputs/apk/release/mini_downloader-release.apk \
   ../assets/binaries/streetphare_downloader.apk
```

> **Note** : Le module `mini_downloader` doit être créé dans `android/mini_downloader/`
> avant de pouvoir exécuter cette commande. C'est un projet Android minimal
> (quelques centaines de ko) qui, une fois installé par le destinataire,
> télécharge automatiquement la dernière version de StreetPhare depuis
> GitHub Releases et l'installe.

### 📋 Comportement Attendu

| Étape | Action | Fichier |
|-------|--------|---------|
| 1 | Extraction des assets | `lib/services/apk_downloader_service.dart:44` — `rootBundle.load()` |
| 2 | Écriture en temporaire | `lib/services/apk_downloader_service.dart:57-63` — `path_provider` |
| 3 | Partage système | `lib/services/apk_downloader_service.dart:111-118` — `share_plus` |
| 4 | Nettoyage (5s) | `lib/services/apk_downloader_service.dart:125-127` — cleanup |

### ⚠️ État Actuel

| Élément | Statut |
|---------|--------|
| Code d'extraction | ✅ Implémenté |
| Code de partage | ✅ Implémenté |
| Intégration UI | ✅ Bouton dans Paramètres |
| Déclaration pubspec.yaml | ✅ `assets/binaries/` |
| **Fichier .apk** | ❌ **MANQUANT** — Placer le binaire ici |

La fonctionnalité est prête côté code. Elle nécessite uniquement le placement
du fichier `streetphare_downloader.apk` dans ce répertoire.