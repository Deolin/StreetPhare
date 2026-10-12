// lib/core/network/osm_tile_headers.dart
//
// En-têtes HTTP conformes à la politique d'utilisation des tuiles
// OpenStreetMap — https://operations.osmfoundation.org/policies/tiles/
//
// OSM exige un User-Agent valide et identifiable (nom d'application stable
// + moyen de contact), sous peine de blocage HTTP 403. Un User-Agent
// générique de bibliothèque (ex. `flutter_map (...)`) est insuffisant.
//
// Ces constantes sont réutilisées par toutes les couches de tuiles
// `flutter_map` de l'application afin de garantir une identification
// cohérente et conforme.

/// Version de l'application, synchronisée avec `pubspec.yaml` (version: 2.2.0).
const String kStreetPhareAppVersion = '2.2';

/// User-Agent identifiant clairement l'application StreetPhare.
const String kStreetPhareUserAgent = 'StreetPhareApp/$kStreetPhareAppVersion '
    '(com.streetphare.app; contact@streetphare.app)';

/// Referer (page/origine) transmis avec les requêtes de tuiles.
const String kStreetPhareReferer = 'https://streetphare.app/';

/// En-têtes à appliquer sur chaque `NetworkTileProvider` de `flutter_map`.
///
/// ⚠️ IMPORTANT : ce `Map` doit être MUTABLE (pas `const`). `flutter_map`
/// appelle `headers.putIfAbsent(...)` dans le constructeur de `TileLayer`,
/// ce qui lèverait `UnsupportedError: Cannot modify unmodifiable map` sur
/// un map immuable.
final Map<String, String> kStreetPhareTileHeaders = {
  'User-Agent': kStreetPhareUserAgent,
  'Referer': kStreetPhareReferer,
};
