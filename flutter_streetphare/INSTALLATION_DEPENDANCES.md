# 📦 Dépendances à ajouter pour StreetPhare

Pour faire fonctionner l'application, ajouter ces dépendances dans
`pubspec.yaml` puis exécuter :

```bash
flutter pub get
```

## Bloc `dependencies:` à ajouter

```yaml
  # Cartographie OpenStreetMap
  flutter_map: ^7.0.2
  latlong2: ^0.9.1

  # Cache des tuiles de la carte
  flutter_map_cache: ^1.4.0

  # Stockage local (SharedPreferences)
  shared_preferences: ^2.3.2

  # Géolocalisation
  geolocator: ^13.0.1
```

## Permissions

### Android — `android/app/src/main/AndroidManifest.xml`

À l'intérieur de la balise `<manifest ...>` :

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>StreetPhare a besoin de votre position pour vous localiser sur la carte.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>StreetPhare utilise votre position en arrière-plan uniquement en cas d'alerte panique.</string>
```

### Windows — `windows/runner/main.cpp`

Aucune permission spéciale n'est nécessaire pour Windows, mais la
cartographie fonctionnera uniquement si une connexion Internet est
disponible.
