# 🏮 StreetPhare

**Application citoyenne de cartographie collaborative en temps réel**
*Compatible Android, iOS et Windows — Open Source*

Soutenez-moi via [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L8X321888R) 
---

## 📁 Architecture du projet

L'application suit une **architecture orientée fonctionnalités** (feature-first),
organisée en couches :

```
lib/
├── core/                                # Cœur de l'application
│   ├── cache/
│   │   └── cache_manager.dart           # Gestion du cache local + horodatage 24h
│   └── theme/
│       └── streetphare_theme.dart       # Thème "Nuit" de l'application
│
├── features/                            # Fonctionnalités métier
│   ├── splash/                          # Écran de chargement
│   │   └── presentation/
│   │       └── splash_screen.dart
│   ├── map/                             # Écran principal (carte)
│   │   └── presentation/
│   │       └── map_screen.dart          # Carte + 3 FAB
│   └── reports/                         # Signalements
│       ├── domain/
│       │   └── models/
│       │       └── report_type.dart     # Énumération des types
│       └── presentation/
│           └── report_bottom_sheet.dart # Feuille d'ancrage
│
├── streetphare_startup.dart             # Version alternative du main
├── streetphare_map_page.dart            # Page carte basique
└── main.dart                            # Point d'entrée (par défaut Flutter)
```

---

## 🚀 Installation et activation

### 1. Ajouter les dépendances

Modifier le fichier `pubspec.yaml` pour ajouter les dépendances suivantes
dans la section `dependencies:` :

```yaml
  # Cartographie OpenStreetMap
  flutter_map: ^7.0.2
  latlong2: ^0.9.1

  # Cache des tuiles
  flutter_map_cache: ^1.4.0

  # Stockage local
  shared_preferences: ^2.3.2

  # Géolocalisation (utilisé dans la version basique)
  geolocator: ^13.0.1
```

Puis exécuter :

```bash
flutter pub get
```

> 📝 Le fichier `INSTALLATION_DEPENDANCES.md` contient la liste complète
> ainsi que les permissions Android, iOS et Windows.

### 2. Activer le splash screen

Dans `lib/main.dart`, remplacer le contenu par :

```dart
import 'package:flutter/material.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'core/theme/streetphare_theme.dart';

void main() {
  runApp(const StreetPhareApp());
}

class StreetPhareApp extends StatelessWidget {
  const StreetPhareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreetPhare',
      debugShowCheckedModeBanner: false,
      theme: StreetPhareTheme.darkTheme(),
      home: const SplashScreen(),
    );
  }
}
```

### 3. Lancer l'application

```bash
flutter run
```

---

## ⚙️ Fonctionnement détaillé

### 🟡 Splash Screen — Logique de cache

1. **Initialisation** : `CacheManager.instance.initialize()` est appelé.
   Il :
   - Lit l'horodatage précédent depuis `SharedPreferences`
   - Met à jour l'horodatage (l'application est ouverte → reset du compteur 24h)
   - Retourne un statut : `valid` / `expired` / `fresh`

2. **Si `expired`** (≥ 24h sans ouverture) :
   - Purge complète des préférences
   - Téléchargement simulé des données initiales
   - Mise en cache des tuiles OpenStreetMap

3. **Si `valid` ou `fresh`** :
   - Chargement rapide
   - Redirection immédiate vers la carte

4. **Redirection automatique** vers `MapScreen`.

### 🗺️ Map Screen — 3 boutons d'action flottants

| Bouton | Icône | Couleur | Action |
|--------|-------|---------|--------|
| **SIGNALEMENT** | `add_alert` | Ambre (primaire) | Ouvre la `ReportBottomSheet` |
| **ROUTE SAFE** | `shield_outlined` | Surface + bordure ambre | Affiche un snackbar "Recherche d'un chemin sûr…" |
| **PANIC** | `emergency` | Rouge vif, étendu | Affiche une confirmation, puis alerte "Mode Panique Activé" |

### 📋 ReportBottomSheet — Types de signalement

7 types de signalements citoyens disponibles :

- 🔴 **Barrages**
- 🟠 **Zones filtrées**
- 🟡 **Nasses**
- 🔵 **Autopompes**
- 🟣 **Policiers**
- 🟧 **Dangers**
- 🟪 **Groupes de casseurs**

---

## 🔒 Respect de la vie privée

- ❌ **Aucune donnée nominative** n'est collectée
- ❌ **Aucun tracking** n'est implémenté
- ❌ **Aucune télémétrie** envoyée à un serveur tiers
- ✅ Seule la **date/heure d'ouverture** est conservée localement
  pour la gestion du cache

---

## 📦 Plateformes supportées

| Plateforme | Statut | Notes |
|------------|--------|-------|
| Android    | ✅     | Permissions `INTERNET` + `ACCESS_FINE_LOCATION` |
| iOS        | ✅     | Clés `NSLocationWhenInUseUsageDescription` |
| Windows    | ✅     | Cartographie en ligne uniquement |

---

## 📜 Licence

Application open source — voir le fichier `LICENSE` du projet.
