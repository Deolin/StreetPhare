// lib/features/map/map_cache_manager.dart
//
// Gestionnaire de cache des tuiles cartographiques.
//
// Règles métier :
//   - Durée minimale de rétention : 7 jours.
//   - Durée maximale de rétention : 30 jours (strict).
//   - La valeur est pilotée par `AppPreferencesStore.mapCacheMaxAgeDays`
//     (plage 7–30, défaut 7).
//   - Les tuiles au-delà de la durée configurée sont signalées
//     comme expirées.
//   - Un avertissement proactif est levé si un événement est planifié
//     à plus de 30 jours (cf. events_screen.dart).
//
// v2.3 — Intégration avec MapTileDownloadService :
//   `preloadZone()` déclenche désormais de vrais téléchargements natifs
//   via le DownloadManager Android (fallback automatique OSM si le
//   serveur privé est inaccessible).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/map_tile_download_service.dart';
import '../settings/data/app_preferences_store.dart';

/// Gestionnaire singleton du cache de tuiles cartographiques.
class MapCacheManager {
  MapCacheManager._();
  static final MapCacheManager instance = MapCacheManager._();

  /// Durée minimale de rétention du cache (en jours).
  static const int minCacheDays = 7;

  /// Durée maximale de rétention du cache (en jours).
  static const int maxCacheDays = 30;

  /// Durée par défaut (en jours).
  static const int defaultCacheDays = 7;

  /// Clé SharedPreferences pour l'horodatage du dernier nettoyage.
  static const String _keyLastPurge = 'map_cache_last_purge';

  Directory? _cacheDir;

  /// Expose la durée actuelle de rétention depuis les préférences,
  /// clampée entre [minCacheDays] et [maxCacheDays].
  int get currentMaxAgeDays {
    final prefs = AppPreferencesStore.instance.value;
    return prefs.mapCacheMaxAgeDays.clamp(minCacheDays, maxCacheDays);
  }

  /// Initialise le gestionnaire de cache de tuiles.
  ///
  /// Localise le répertoire de cache des tuiles et purge
  /// les entrées expirées.
  Future<void> init() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/map_tiles_cache');
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }

      if (kDebugMode) {
        debugPrint(
          '[MapCacheManager] Cache tuiles initialisé '
          '(TTL = $currentMaxAgeDays jours, '
          'répertoire: ${_cacheDir!.path}).',
        );
      }

      await purgeExpired();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapCacheManager] Erreur initialisation: $e');
      }
    }
  }

  /// Met à jour la durée de rétention du cache suite à un changement
  /// des préférences utilisateur (via le slider des paramètres).
  Future<void> updateRetention(int days) async {
    final clamped = days.clamp(minCacheDays, maxCacheDays);
    await AppPreferencesStore.instance.setMapCacheMaxAgeDays(clamped);

    if (kDebugMode) {
      debugPrint('[MapCacheManager] TTL mis à jour → $clamped jours.');
    }

    await purgeExpired();
  }

  /// Purge les tuiles dont l'âge dépasse la durée configurée.
  ///
  /// Parcourt le répertoire de cache local et supprime les fichiers
  /// plus vieux que [currentMaxAgeDays] jours.
  Future<void> purgeExpired() async {
    if (_cacheDir == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPurgeMillis = prefs.getInt(_keyLastPurge);
      final now = DateTime.now();

      // Ne purge pas plus d'une fois par jour pour éviter
      // des opérations disque trop fréquentes.
      if (lastPurgeMillis != null) {
        final lastPurge = DateTime.fromMillisecondsSinceEpoch(lastPurgeMillis);
        if (now.difference(lastPurge).inHours < 24) {
          return;
        }
      }

      final maxAge = Duration(days: currentMaxAgeDays);
      final cutoff = now.subtract(maxAge);
      int purgedCount = 0;
      int totalSize = 0;

      final files = _cacheDir!.listSync(recursive: true);
      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            try {
              totalSize += await entity.length();
              await entity.delete();
              purgedCount++;
            } catch (e) {
              debugPrint(
                  '[MapCacheManager] ⚠ Impossible de supprimer le fichier cache: $e');
            }
          }
        }
      }

      // Nettoie les dossiers vides.
      _cleanEmptyDirs(_cacheDir!);

      await prefs.setInt(_keyLastPurge, now.millisecondsSinceEpoch);

      if (kDebugMode && purgedCount > 0) {
        debugPrint(
          '[MapCacheManager] Purge terminée : '
          '$purgedCount fichiers supprimés '
          '(${_formatBytes(totalSize)}).',
        );
      }

      if (kDebugMode) {
        debugPrint(
          '[MapCacheManager] Cache nettoyé. '
          'Seuil : $currentMaxAgeDays jours.',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapCacheManager] Erreur purge: $e');
      }
    }
  }

  /// Supprime récursivement les dossiers vides.
  void _cleanEmptyDirs(Directory dir) {
    final entities = dir.listSync();
    for (final entity in entities) {
      if (entity is Directory) {
        _cleanEmptyDirs(entity);
        if (entity.listSync().isEmpty) {
          try {
            entity.deleteSync();
          } catch (e) {
            debugPrint(
                '[MapCacheManager] ⚠ Dossier vide impossible à supprimer: $e');
          }
        }
      }
    }
  }

  /// Déclenche un téléchargement d'arrière-plan des tuiles pour la
  /// zone couverte par une commune donnée.
  ///
  /// Utilise le [MapTileDownloadService] qui délègue au
  /// DownloadManager Android natif avec fallback automatique OSM.
  ///
  /// [zoneLabel] : nom de la commune (ex: "Bruxelles").
  /// [centerLat] / [centerLng] : coordonnées du centre approximatif.
  /// [radiusKm] : rayon de couverture en km (défaut 5 km).
  ///
  /// Les tuiles sont téléchargées pour les niveaux de zoom 12 à 15
  /// (échelle région → rue).
  Future<void> preloadZone({
    required String zoneLabel,
    required double centerLat,
    required double centerLng,
    double radiusKm = 5.0,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[MapCacheManager] Préchargement zone "$zoneLabel" '
        '($radiusKm km autour de $centerLat, $centerLng)…',
      );
    }

    // ── Persistance de la zone dans les préférences ───────────────────
    final prefs = await SharedPreferences.getInstance();
    const zonesKey = 'map_cache_preloaded_zones';
    final existing = prefs.getStringList(zonesKey) ?? [];
    if (!existing.contains(zoneLabel)) {
      existing.add(zoneLabel);
      if (existing.length > 20) existing.removeAt(0);
      await prefs.setStringList(zonesKey, existing);
    }

    // ── Déclenchement des téléchargements via DownloadManager ─────────
    // Calcule le rectangle géographique approximatif.
    const kmPerDeg = 1.0 / 111.32; // 1° ≈ 111.32 km
    final delta = radiusKm * kmPerDeg;
    final swLat = centerLat - delta;
    final swLng = centerLng - delta;
    final neLat = centerLat + delta;
    final neLng = centerLng + delta;

    // Niveaux de zoom : 12 (ville) à 15 (rue).
    const minZoom = 12;
    const maxZoom = 15;

    final service = MapTileDownloadService.instance;
    service.startTracking();

    for (var z = minZoom; z <= maxZoom; z++) {
      final bounds = MapTileDownloadService.tileBoundsForArea(
        swLat: swLat,
        swLng: swLng,
        neLat: neLat,
        neLng: neLng,
        z: z,
      );

      final tileCount =
          (bounds.maxX - bounds.minX + 1) * (bounds.maxY - bounds.minY + 1);

      if (kDebugMode) {
        debugPrint(
          '[MapCacheManager] Zoom $z → $tileCount tuiles '
          '(x:${bounds.minX}–${bounds.maxX}, y:${bounds.minY}–${bounds.maxY})',
        );
      }

      await service.downloadTileBatch(
        minZ: z,
        maxZ: z,
        minX: bounds.minX,
        maxX: bounds.maxX,
        minY: bounds.minY,
        maxY: bounds.maxY,
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[MapCacheManager] ✅ Zone "$zoneLabel" : '
        'téléchargements planifiés (zoom $minZoom–$maxZoom).',
      );
    }
  }

  /// Vérifie si des tuiles sont déjà présentes pour une zone donnée.
  ///
  /// Retourne `true` si le cache contient au moins un fichier.
  Future<bool> hasCachedTiles() async {
    if (_cacheDir == null) return false;
    try {
      final files = _cacheDir!.listSync(recursive: true);
      return files.any((e) => e is File);
    } catch (e) {
      debugPrint('[MapCacheManager] ⚠ Erreur vérification tuiles: $e');
      return false;
    }
  }

  /// Retourne la taille totale du cache en octets.
  Future<int> getCacheSize() async {
    if (_cacheDir == null) return 0;
    int total = 0;
    try {
      final files = _cacheDir!.listSync(recursive: true);
      for (final entity in files) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (e) {
      debugPrint('[MapCacheManager] ⚠ Erreur calcul taille cache: $e');
    }
    return total;
  }

  /// Formate un nombre d'octets en chaîne lisible.
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / 1048576).toStringAsFixed(1)} Mo';
  }
}