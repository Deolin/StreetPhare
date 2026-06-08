import 'package:flutter/material.dart';

import '../../../core/cache/cache_manager.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../map/presentation/map_screen.dart';

/// Écran de chargement (Splash Screen) de StreetPhare.
///
/// Logique métier appliquée :
///   1. Initialisation du `CacheManager` :
///       - Mise à jour de l'horodatage d'ouverture
///       - Vérification de la validité du cache (< 24h)
///   2. Si le cache a expiré : purge puis téléchargement simulé
///      des données initiales (tuiles de la zone locale).
///   3. Sinon : chargement rapide.
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

  @override
  void initState() {
    super.initState();

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
      // Étape 1 : Vérification du cache
      _updateProgress(0.15, 'Vérification du cache local…');
      final status = await CacheManager.instance.initialize();
      debugPrint('[Splash] Statut du cache : $status');

      // Étape 2 : Si le cache a expiré, on le purge
      if (status == CacheStatus.expired) {
        _updateProgress(0.35, 'Cache expiré, purge en cours…');
        await CacheManager.instance.purge();
        // Petite pause pour donner du sens à l'étape
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // Étape 3 : Téléchargement / chargement des données initiales
      _updateProgress(0.55, 'Chargement de la carte locale…');
      await _loadInitialData();

      _updateProgress(0.85, 'Mise en cache des tuiles…');
      // Les tuiles OpenStreetMap sont mises en cache automatiquement
      // par `flutter_map_cache` lors de leur premier affichage.
      // Ici, on simule le temps de mise en cache.
      await Future.delayed(const Duration(milliseconds: 700));

      _updateProgress(1.0, 'Prêt !');
      await Future.delayed(const Duration(milliseconds: 400));

      // Étape 4 : Redirection vers l'écran principal
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MapScreen()),
      );
    } catch (e) {
      debugPrint('[Splash] Erreur de démarrage : $e');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Erreur : $e';
      });
    }
  }

  /// Simule le téléchargement des données initiales (zone locale).
  ///
  /// Pour le MVP, on se contente d'un délai. Une version ultérieure
  /// pourra déclencher un téléchargement réel de tuiles OSM via
  /// `flutter_map_cache` ou précharger des données via l'API.
  Future<void> _loadInitialData() async {
    await Future.delayed(const Duration(milliseconds: 900));
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

                const SizedBox(height: 64),

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
