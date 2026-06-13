import 'package:shared_preferences/shared_preferences.dart';

/// Service responsable de la gestion du cache de l'application.
///
/// Règles métier :
///   - L'horodatage de la dernière ouverture est conservé dans
///     `SharedPreferences` sous la clé `last_open_timestamp`.
///   - Si l'application n'a pas été ouverte depuis plus de 24 heures,
///     le cache est considéré comme invalide et doit être purgé.
///   - Si l'application est ouverte, le compteur de 24 heures est
///     réinitialisé automatiquement (mise à jour de l'horodatage).
///
/// Respect de la vie privée : aucune donnée nominative n'est stockée.
/// Seule la date/heure d'ouverture est conservée localement.
class CacheManager {
  CacheManager._();

  /// Instance singleton
  static final CacheManager instance = CacheManager._();

  /// Clé SharedPreferences pour l'horodatage
  static const String _keyLastOpen = 'last_open_timestamp';

  /// Durée de validité du cache (24 heures)
  static const Duration cacheValidity = Duration(hours: 24);

  // -------- API publique --------

  /// Initialise le cache :
  ///   1. Met à jour l'horodatage d'ouverture
  ///   2. Vérifie la validité du cache
  ///   3. Retourne `true` si le cache est valide, `false` sinon
  Future<CacheStatus> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // 1) Lecture de l'horodatage précédent
    final lastOpenMillis = prefs.getInt(_keyLastOpen);
    final lastOpen = lastOpenMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastOpenMillis)
        : null;

    // 2) Mise à jour de l'horodatage (l'application est ouverte)
    await prefs.setInt(_keyLastOpen, now.millisecondsSinceEpoch);

    // 3) Vérification de la validité
    if (lastOpen == null) {
      // Première ouverture
      return CacheStatus.fresh;
    }

    final age = now.difference(lastOpen);
    if (age >= cacheValidity) {
      // Cache expiré
      return CacheStatus.expired;
    }

    return CacheStatus.valid;
  }

  /// Purge le cache de l'application.
  ///
  /// Pour le MVP, on supprime toutes les préférences. Une version
  /// plus avancée pourra purger spécifiquement le cache des tuiles
  /// (répertoire géré par `flutter_map_cache`).
  Future<void> purge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Indique si le cache est encore valide.
  ///
  /// Utile pour vérifier périodiquement (ex. : retour au premier plan)
  /// sans initialiser complètement.
  Future<bool> isValid() async {
    final prefs = await SharedPreferences.getInstance();
    final lastOpenMillis = prefs.getInt(_keyLastOpen);
    if (lastOpenMillis == null) return false;

    final lastOpen = DateTime.fromMillisecondsSinceEpoch(lastOpenMillis);
    final age = DateTime.now().difference(lastOpen);
    return age < cacheValidity;
  }

  /// Retourne l'âge du cache actuel (depuis la dernière ouverture).
  Future<Duration> getCacheAge() async {
    final prefs = await SharedPreferences.getInstance();
    final lastOpenMillis = prefs.getInt(_keyLastOpen);
    if (lastOpenMillis == null) return Duration.zero;

    final lastOpen = DateTime.fromMillisecondsSinceEpoch(lastOpenMillis);
    return DateTime.now().difference(lastOpen);
  }
}

/// État du cache au démarrage
enum CacheStatus {
  /// Le cache est encore valide (< 24h)
  valid,

  /// Le cache a expiré (>= 24h) et doit être purgé / rechargé
  expired,

  /// Première ouverture de l'application
  fresh,
}
