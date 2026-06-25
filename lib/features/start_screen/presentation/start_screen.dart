// lib/features/start_screen/presentation/start_screen.dart
//
// Écran de démarrage affiché au tout premier lancement de l'application.
//
// Fonctionnalités :
//   1. Carrousel automatique des langues (FR → EN → NL → DE → boucle)
//   2. Dropdown de sélection de langue (arrête le carrousel si utilisé)
//   3. Bouton "Commencer" activé après la sélection d'une langue
//   4. Persistance du choix et redirection vers MapScreen

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../map/presentation/map_screen.dart';
import '../data/start_screen_store.dart';

/// Écran de bienvenue / premier démarrage.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with SingleTickerProviderStateMixin {
  // Langue actuellement sélectionnée par l'utilisateur (ou null si auto)
  AppLanguage? _selectedLanguage;

  // Index du carrousel automatique
  int _carouselIndex = 0;

  // Timer du carrousel automatique
  Timer? _carouselTimer;

  // Contrôleur d'animation pour le logo
  late final AnimationController _logoController;
  late final Animation<double> _logoAnimation;

  // Les langues dans l'ordre du carrousel
  static const List<AppLanguage> _carouselLanguages = [
    AppLanguage.fr,
    AppLanguage.en,
    AppLanguage.nl,
    AppLanguage.de,
  ];

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

    // Démarrage du carrousel automatique
    _startCarousel();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _logoController.dispose();
    super.dispose();
  }

  /// Démarre le carrousel automatique des langues (rotation toutes les 2.5s).
  void _startCarousel() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) {
        if (_selectedLanguage != null) return; // Ne tourne pas si choix manuel
        if (!mounted) return;
        setState(() {
          _carouselIndex = (_carouselIndex + 1) % _carouselLanguages.length;
        });
      },
    );
  }

  /// Appelé quand l'utilisateur sélectionne une langue dans le dropdown.
  void _onLanguageSelected(AppLanguage? language) {
    if (language == null) return;
    setState(() {
      _selectedLanguage = language;
      _carouselIndex = _carouselLanguages.indexOf(language);
    });
    _carouselTimer?.cancel(); // Arrête le carrousel
  }

  /// Retourne les chaînes traduites pour la langue actuellement affichée.
  AppStrings get _displayStrings {
    final lang = _selectedLanguage ?? _carouselLanguages[_carouselIndex];
    return switch (lang) {
      AppLanguage.fr => AppStrings.fr(),
      AppLanguage.en => AppStrings.en(),
      AppLanguage.nl => AppStrings.nl(),
      AppLanguage.de => AppStrings.de(),
    };
  }

  /// Retourne la langue actuellement affichée.
  AppLanguage get _displayLanguage {
    return _selectedLanguage ?? _carouselLanguages[_carouselIndex];
  }

  /// Valide le choix et redirige vers l'écran principal.
  Future<void> _onContinue() async {
    if (_selectedLanguage == null) return;

    // Persiste la langue choisie
    await AppLocale.instance.setLanguage(_selectedLanguage!);
    // Marque le start screen comme vu
    await StartScreenStore.instance.markStartComplete();

    if (!mounted) return;
    // Navigue vers l'écran principal avec remplacement complet
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MapScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _displayStrings;

    return Scaffold(
      backgroundColor: StreetPhareTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // --- Logo (place holder pulsant) ---
                ScaleTransition(
                  scale: _logoAnimation,
                  child: _LogoPlaceholder(),
                ),
                const SizedBox(height: 32),

                // --- Texte de bienvenue (carrousel automatique) ---
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: Text(
                    strings.startScreenWelcome,
                    key: ValueKey('welcome_${_displayLanguage.code}'),
                    style: const TextStyle(
                      color: StreetPhareTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),

                // --- Sous-titre ---
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: Text(
                    strings.startScreenSubtitle,
                    key: ValueKey('subtitle_${_displayLanguage.code}'),
                    style: const TextStyle(
                      color: StreetPhareTheme.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 48),

                // --- Indicateur de carrousel (points) ---
                if (_selectedLanguage == null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _carouselLanguages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _carouselIndex == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _carouselIndex == i
                              ? StreetPhareTheme.primary
                              : StreetPhareTheme.textSecondary
                                  .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                if (_selectedLanguage == null) const SizedBox(height: 32),

                // --- Sélecteur de langue (Dropdown) ---
                Text(
                  strings.startScreenSelectLanguage,
                  style: const TextStyle(
                    color: StreetPhareTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  width: 240,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: StreetPhareTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: StreetPhareTheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AppLanguage>(
                      value: _selectedLanguage,
                      hint: Text(
                        _displayStrings.languageLabel,
                        style: const TextStyle(
                          color: StreetPhareTheme.textPrimary,
                        ),
                      ),
                      isExpanded: true,
                      dropdownColor: StreetPhareTheme.surface,
                      style: const TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontSize: 16,
                      ),
                      items: _carouselLanguages.map((lang) {
                        final langStrings = switch (lang) {
                          AppLanguage.fr => AppStrings.fr(),
                          AppLanguage.en => AppStrings.en(),
                          AppLanguage.nl => AppStrings.nl(),
                          AppLanguage.de => AppStrings.de(),
                        };
                        return DropdownMenuItem(
                          value: lang,
                          child: Row(
                            children: [
                              Text(
                                lang.flag,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(langStrings.languageLabel),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _onLanguageSelected,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // --- Bouton "Commencer" ---
                AnimatedOpacity(
                  opacity: _selectedLanguage != null ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 300),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward, size: 20),
                    label: Text(
                      strings.startScreenButton,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StreetPhareTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _selectedLanguage != null ? _onContinue : null,
                  ),
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Logo placeholder (copié du SplashScreen pour cohérence visuelle)
// ============================================================================

/// Placeholder pour le logo de StreetPhare.
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
