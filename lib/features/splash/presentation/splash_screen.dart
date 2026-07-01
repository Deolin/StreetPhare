import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/cache/cache_manager.dart';
import '../../../core/services/permission_guard_screen.dart';
import '../../../core/services/permission_guard_service.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../../services/version_check_service.dart';
import '../../map/map_cache_manager.dart';
import '../../map/presentation/map_screen.dart';
import '../../start_screen/data/start_screen_store.dart';
import '../../start_screen/presentation/start_screen.dart';
import '../../tutorial/data/tutorial_store.dart';
import '../../tutorial/presentation/tutorial_screen.dart';

/// Écran de chargement (Splash Screen) de StreetPhare.
///
/// Logique métier appliquée :
///   1. Initialisation du `CacheManager` :
///       - Mise à jour de l'horodatage d'ouverture
///       - Vérification de la validité du cache (< 24h)
///   2. Si le cache a expiré : purge puis téléchargement simulé
///      des données initiales (tuiles de la zone locale).
///   3. Géolocalisation précoce : obtention de la position pour
///      vérifier que les tuiles locales sont en cache avant de
///      quitter le loader (bloquant).
///   4. Redirection automatique vers `MapScreen`.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Étape de progression affichée à l'utilisateur
  String _statusMessage = 'Initialisation…';
  double _progress = 0.0;

  // Contrôleur d'animation pour le logo
  late final AnimationController _logoController;
  late final Animation<double> _logoAnimation;

  // Index courant du tooltip affiché
  int _tooltipIndex = 0;

  // Tooltips aléatoires (astuces + messages d'attente)
  static const List<String> _tooltips = [
    '💡 Appuyez longuement sur la carte pour définir votre destination.',
    '📍 Activez le GPS pour une navigation précise en temps réel.',
    '🛡 La Route Safe vous guide vers la zone sécurisée la plus proche.',
    '📱 Scannez un QR code pour rejoindre un événement StreetPhare.',
    '🔒 Toutes vos communications sont chiffrées de bout en bout.',
    '🚨 En cas d\'urgence, utilisez le bouton PANIC pour alerter vos contacts.',
    '🗺️ Les tuiles de carte sont mises en cache pour fonctionner hors-ligne.',
    '👥 StreetPhare fonctionne en P2P, sans dépendre d\'un serveur central.',
    '🌙 Le mode sombre économise la batterie et préserve votre vision nocturne.',
    '🔄 Les itinéraires s\'adaptent en temps réel selon les signalements.',
    '📊 Consultez les statistiques de votre événement depuis le dashboard.',
    '🔔 Activez les notifications pour recevoir les alertes de proximité.',
  ];

  @override
  void initState() {
    super.initState();

    // Tooltip aléatoire au lancement
    _tooltipIndex = math.Random().nextInt(_tooltips.length);

    // Animation du logo : pulsation continue
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _logoAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // Lancement de la séquence de démarrage
    _bootstrap();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  /// Séquence complète de démarrage
  Future<void> _bootstrap() async {
    try {
      // Étape 0 : Vérification des permissions indispensables (maillage P2P)
      _updateProgress(0.05, 'Vérification des permissions…');
      if (mounted) {
        final guardResult = await PermissionGuardService.instance.checkAll();
        if (!guardResult.allGranted) {
          // Bloque le démarrage : affiche l'écran de permission.
          // L'utilisateur doit accorder toutes les permissions pour continuer.
          await _showPermissionGuard();
          // Après le guard, on revérifie ; si toujours pas accordé,
          // on laisse l'utilisateur bloqué (le guard ne pop que si OK).
          return;
        }
      }

      // Étape 1 : Vérification de la version (Kill Switch)
      _updateProgress(0.15, 'Vérification de la version…');
      if (mounted) {
        await VersionCheckService.instance.checkVersion(context);
        if (VersionCheckService.instance.isObsolete) return;
      }

      // Étape 2 : Vérification du cache
      _updateProgress(0.25, 'Vérification du cache local…');
      final status = await CacheManager.instance.initialize();
      debugPrint('[Splash] Statut du cache : $status');

      // Étape 3 : Si le cache a expiré, on le purge
      if (status == CacheStatus.expired) {
        _updateProgress(0.35, 'Cache expiré, purge en cours…');
        await CacheManager.instance.purge();
        await Future.delayed(const Duration(milliseconds: 400));
      }

      // Étape 4 : Géolocalisation précoce (bloquante pour le loader)
      _updateProgress(0.45, 'Recherche de votre position…');
      _tooltipIndex = (_tooltipIndex + 1) % _tooltips.length;
      final position = await _getInitialPosition();

      // Étape 5 : Vérification des tuiles en cache autour de la position
      _updateProgress(0.65, 'Vérification des tuiles locales…');
      _tooltipIndex = (_tooltipIndex + 1) % _tooltips.length;
      final tilesReady = await _ensureLocalTilesReady(position);

      if (!tilesReady) {
        _updateProgress(0.80, 'Téléchargement des tuiles de votre zone…');
        _tooltipIndex = (_tooltipIndex + 1) % _tooltips.length;
        // Le téléchargement effectif sera fait par flutter_map au premier
        // affichage. On laisse un délai pour que le cache manager s'initialise.
        await Future.delayed(const Duration(milliseconds: 1200));
      }

      _updateProgress(0.90, 'Finalisation…');
      _tooltipIndex = (_tooltipIndex + 1) % _tooltips.length;
      await Future.delayed(const Duration(milliseconds: 500));

      _updateProgress(1.0, 'Prêt !');
      await Future.delayed(const Duration(milliseconds: 400));

      // Étape 6 : Redirection vers l'écran principal.
      if (!mounted) return;

      if (StartScreenStore.instance.isFirstLaunch) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _StartScreenBridge(),
          ),
        );
      } else if (TutorialStore.instance.isFirstLaunch) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _TutorialThenMapBridge(),
          ),
        );
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
      }
    } catch (e) {
      debugPrint('[Splash] Erreur de démarrage : $e');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Erreur : $e';
      });
    }
  }

  /// Affiche l'écran de blocage des permissions et attend que
  /// l'utilisateur les accorde toutes. Redirige vers la carte
  /// une fois les permissions obtenues, ou reste bloqué.
  Future<void> _showPermissionGuard() async {
    final granted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PermissionGuardScreen(),
      ),
    );

    // Si l'utilisateur a accordé toutes les permissions, on reprend
    // le flux de démarrage normal (sans repasser par le splash).
    if (granted == true && mounted) {
      // On saute directement à l'écran principal approprié.
      if (StartScreenStore.instance.isFirstLaunch) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _StartScreenBridge(),
          ),
        );
      } else if (TutorialStore.instance.isFirstLaunch) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _TutorialThenMapBridge(),
          ),
        );
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
      }
    }
  }

  /// Obtient la position GPS initiale de manière sécurisée.
  /// En cas d'échec, retourne une position par défaut (Paris).
  Future<Position> _getInitialPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('[Splash] GPS désactivé, position par défaut.');
        return Position(
          latitude: 48.8566,
          longitude: 2.3522,
          timestamp: DateTime.now(),
          accuracy: 999,
          altitude: 0,
          altitudeAccuracy: 999,
          heading: 0,
          headingAccuracy: 999,
          speed: 0,
          speedAccuracy: 999,
        );
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          debugPrint('[Splash] Permission GPS refusée.');
          return Position(
            latitude: 48.8566,
            longitude: 2.3522,
            timestamp: DateTime.now(),
            accuracy: 999,
            altitude: 0,
            altitudeAccuracy: 999,
            heading: 0,
            headingAccuracy: 999,
            speed: 0,
            speedAccuracy: 999,
          );
        }
      }
      if (perm == LocationPermission.deniedForever) {
        return Position(
          latitude: 48.8566,
          longitude: 2.3522,
          timestamp: DateTime.now(),
          accuracy: 999,
          altitude: 0,
          altitudeAccuracy: 999,
          heading: 0,
          headingAccuracy: 999,
          speed: 0,
          speedAccuracy: 999,
        );
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 7),
        ),
      );
    } catch (e) {
      debugPrint('[Splash] Erreur GPS : $e');
      return Position(
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
        accuracy: 999,
        altitude: 0,
        altitudeAccuracy: 999,
        heading: 0,
        headingAccuracy: 999,
        speed: 0,
        speedAccuracy: 999,
      );
    }
  }

  /// Vérifie que les tuiles autour de la position sont présentes dans
  /// le cache local. Initialise le [MapCacheManager] au passage.
  ///
  /// Retourne `true` si des tuiles sont déjà en cache, `false` sinon.
  Future<bool> _ensureLocalTilesReady(Position position) async {
    try {
      await MapCacheManager.instance.init();
      final hasTiles = await MapCacheManager.instance.hasCachedTiles();

      // Marque la zone comme préchargée (centre sur la position)
      if (!hasTiles) {
        await MapCacheManager.instance.preloadZone(
          zoneLabel: 'Position actuelle',
          centerLat: position.latitude,
          centerLng: position.longitude,
          radiusKm: 2.0,
        );
      }

      debugPrint('[Splash] Tuiles en cache : $hasTiles');
      return hasTiles;
    } catch (e) {
      debugPrint('[Splash] Erreur vérification tuiles : $e');
      return false;
    }
  }

  void _updateProgress(double value, String message) {
    if (!mounted) return;
    setState(() {
      _progress = value;
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StreetPhareTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // --- Logo (placeholder pulsant) ---
                ScaleTransition(
                  scale: _logoAnimation,
                  child: _LogoPlaceholder(),
                ),
                const SizedBox(height: 32),

                // --- Nom de l'application ---
                const Text(
                  'StreetPhare',
                  style: TextStyle(
                    color: StreetPhareTheme.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cartographie citoyenne en temps réel',
                  style: TextStyle(
                    color: StreetPhareTheme.textSecondary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // --- Tooltip aléatoire (astuce / message d'attente) ---
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: Container(
                    key: ValueKey(_tooltipIndex),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: StreetPhareTheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _tooltips[_tooltipIndex],
                      style: const TextStyle(
                        color: StreetPhareTheme.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // --- Indicateur de chargement ---
                SizedBox(
                  width: 220,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 6,
                          backgroundColor: StreetPhareTheme.surface,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            StreetPhareTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: StreetPhareTheme.textSecondary,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Bridge tutoriel → MapScreen (premier démarrage uniquement)
// ============================================================================

/// Widget intermédiaire affiché lors du premier démarrage.
///
/// Il affiche le [TutorialScreen] en mode `isFirstLaunch = true`.
/// Lorsque l'utilisateur ferme le tutoriel ("Passer" ou "Terminer"),
/// [TutorialStore.markTutorialSeen] est appelé et on redirige
/// automatiquement vers [MapScreen].
class _TutorialThenMapBridge extends StatefulWidget {
  const _TutorialThenMapBridge();

  @override
  State<_TutorialThenMapBridge> createState() => _TutorialThenMapBridgeState();
}

class _TutorialThenMapBridgeState extends State<_TutorialThenMapBridge> {
  @override
  void initState() {
    super.initState();
    // On pousse le TutorialScreen immédiatement après le premier build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTutorial());
  }

  Future<void> _showTutorial() async {
    if (!mounted) return;
    // Attend que l'utilisateur ferme le tutoriel (pop).
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TutorialScreen(isFirstLaunch: true),
      ),
    );
    // Une fois le tutoriel fermé, on navigue vers MapScreen.
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MapScreen()),
    );
  }

  /// Fond neutre pendant la transition (pas de flash blanc/noir).
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: StreetPhareTheme.background,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(StreetPhareTheme.primary),
        ),
      ),
    );
  }
}

// ============================================================================
// Bridge StartScreen → MapScreen (tout premier lancement)
// ============================================================================

/// Widget intermédiaire affiché lors du tout premier lancement.
///
/// Il affiche le [StartScreen] pour le choix de la langue.
/// Lorsque l'utilisateur clique sur "Commencer",
/// [StartScreen] redirige automatiquement vers [MapScreen].
class _StartScreenBridge extends StatefulWidget {
  const _StartScreenBridge();

  @override
  State<_StartScreenBridge> createState() => _StartScreenBridgeState();
}

class _StartScreenBridgeState extends State<_StartScreenBridge> {
  @override
  void initState() {
    super.initState();
    // On pousse le StartScreen immédiatement après le premier build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showStartScreen());
  }

  Future<void> _showStartScreen() async {
    if (!mounted) return;
    // Attend que l'utilisateur ferme le StartScreen (pop).
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StartScreen(),
      ),
    );
    // Une fois le StartScreen fermé, on navigue vers MapScreen.
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MapScreen()),
    );
  }

  /// Fond neutre pendant la transition (pas de flash blanc/noir).
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: StreetPhareTheme.background,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(StreetPhareTheme.primary),
        ),
      ),
    );
  }
}

// ============================================================================
// Logo placeholder
// ============================================================================

/// Placeholder pour le logo de StreetPhare.
///
/// Pour le MVP, on utilise un cercle ambré stylisé évoquant un
/// lampadaire. Remplaçable par une image `Image.asset('assets/logo.png')`
/// lorsque les assets seront disponibles.
class _LogoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [StreetPhareTheme.primary, StreetPhareTheme.accent],
        ),
        boxShadow: [
          BoxShadow(
            color: StreetPhareTheme.primary.withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(
        Icons.lightbulb_outline,
        size: 60,
        color: Colors.white,
      ),
    );
  }
}
