// lib/features/tutorial/presentation/tutorial_screen.dart
//
// Écran de tutoriel StreetPhare — affiché automatiquement au premier
// démarrage (via le flag `isFirstLaunch`) et consultable à tout moment
// depuis l'écran Paramètres.
//
// Structure de l'interface :
//   - En-tête de bienvenue avec bouton "Passer" visible dès l'ouverture.
//   - Tableau de données catégorisées :
//       Catégorie | Fonctionnalité | Description utilisateur
//   - Les lignes peuvent être filtrées par catégorie (onglets / chips).
//   - Bouton "Terminer" en bas de page (= même effet que "Passer").
//
// FORMALISME DE SÉCURITÉ D'INTERFACE :
//   Toutes les descriptions sont FONCTIONNELLES et ABSTRAITES.
//   Aucun terme technique (protocole, identifiant, mécanisme interne)
//   n'apparaît dans l'interface. Le code source, lui, reste documenté
//   et limpide pour tout auditeur technique.

import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../data/tutorial_store.dart';
import '../domain/tutorial_entry.dart';

/// Écran de tutoriel — peut être poussé via `Navigator.push` ou
/// affiché en remplacement de la SplashScreen lors du premier démarrage.
///
/// [isFirstLaunch] : si `true`, affiche le bandeau de bienvenue et le
///   bouton "Passer" en haut. Sinon, affiche juste le contenu (mode
///   consultation depuis Paramètres).
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, this.isFirstLaunch = false});

  /// `true` = premier démarrage → bouton "Passer" visible dès le départ.
  /// `false` = consultation depuis les Paramètres.
  final bool isFirstLaunch;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  /// Catégorie sélectionnée pour le filtre (null = toutes).
  TutorialCategory? _selectedCategory;

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  /// Marque le tutoriel comme vu et ferme l'écran.
  /// Identique pour "Passer" et "Terminer".
  Future<void> _dismiss() async {
    // Persiste le flag uniquement si c'est le premier démarrage.
    if (widget.isFirstLaunch) {
      await TutorialStore.instance.markTutorialSeen();
    }
    if (mounted) Navigator.of(context).pop();
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Filtre les entrées selon la catégorie sélectionnée.
    final entries = _selectedCategory == null
        ? kTutorialEntries
        : kTutorialEntries
            .where((e) => e.category == _selectedCategory)
            .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: onSurface),
        title: Text(
          'Guide de l\'application',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        ),
        // Bouton "Passer" visible dès le premier démarrage,
        // remplace le bouton retour standard.
        automaticallyImplyLeading: !widget.isFirstLaunch,
        actions: [
          if (widget.isFirstLaunch)
            TextButton(
              onPressed: _dismiss,
              child: const Text(
                'Passer',
                style: TextStyle(
                  color: StreetPhareTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Bandeau de bienvenue (premier démarrage uniquement) ────────────
          if (widget.isFirstLaunch) _WelcomeBanner(onSkip: _dismiss),

          // ── Chips de filtre par catégorie ─────────────────────────────────
          _CategoryFilterBar(
            selected: _selectedCategory,
            onSelected: (cat) => setState(() => _selectedCategory = cat),
          ),

          // ── Tableau des fonctionnalités ───────────────────────────────────
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'Aucune fonctionnalité dans cette catégorie.',
                      style: TextStyle(
                          color: onSurface.withValues(alpha: 0.5),
                          fontSize: 14),
                    ),
                  )
                : _TutorialTable(entries: entries),
          ),

          // ── Bouton de clôture ─────────────────────────────────────────────
          _DismissButton(
            isFirstLaunch: widget.isFirstLaunch,
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Widgets internes
// ============================================================================

/// Bandeau de bienvenue affiché uniquement lors du premier démarrage.
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.onSkip});
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            StreetPhareTheme.primary.withValues(alpha: 0.15),
            StreetPhareTheme.accent.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                color: StreetPhareTheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bienvenue dans StreetPhare',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Découvrez les fonctionnalités de l\'application. '
            'Ce guide est consultable à tout moment depuis les Paramètres.',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre de filtres par catégorie (chips horizontaux scrollables).
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final TutorialCategory? selected;
  final ValueChanged<TutorialCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Chip "Toutes"
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: const Text('Toutes'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
                selectedColor: StreetPhareTheme.primary.withValues(alpha: 0.25),
                checkmarkColor: StreetPhareTheme.primary,
                labelStyle: TextStyle(
                  color: selected == null
                      ? StreetPhareTheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: selected == null
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
            // Un chip par catégorie
            for (final cat in TutorialCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(cat.label),
                  selected: selected == cat,
                  onSelected: (_) =>
                      onSelected(selected == cat ? null : cat),
                  selectedColor:
                      StreetPhareTheme.primary.withValues(alpha: 0.25),
                  checkmarkColor: StreetPhareTheme.primary,
                  labelStyle: TextStyle(
                    color: selected == cat
                        ? StreetPhareTheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: selected == cat
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tableau principal des entrées du tutoriel.
///
/// Le tableau a trois colonnes :
///   1. Catégorie  (avec badge coloré)
///   2. Fonctionnalité  (nom court, gras)
///   3. Description  (texte fonctionnel, abstraite)
class _TutorialTable extends StatelessWidget {
  const _TutorialTable({required this.entries});
  final List<TutorialEntry> entries;

  // Couleur associée à chaque catégorie pour les badges.
  static Color _catColor(TutorialCategory cat) {
    switch (cat) {
      case TutorialCategory.navigation:
        return const Color(0xFF2196F3); // Bleu
      case TutorialCategory.coordination:
        return const Color(0xFF9C27B0); // Violet
      case TutorialCategory.securite:
        return StreetPhareTheme.danger; // Rouge
      case TutorialCategory.alertes:
        return const Color(0xFFFF9800); // Orange
      case TutorialCategory.configuration:
        return StreetPhareTheme.primary; // Ambre
    }
  }

  // Icône associée à chaque catégorie.
  static IconData _catIcon(TutorialCategory cat) {
    switch (cat) {
      case TutorialCategory.navigation:
        return Icons.map_outlined;
      case TutorialCategory.coordination:
        return Icons.groups_outlined;
      case TutorialCategory.securite:
        return Icons.shield_outlined;
      case TutorialCategory.alertes:
        return Icons.warning_amber_outlined;
      case TutorialCategory.configuration:
        return Icons.settings_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final color = _catColor(entry.category);
        final icon = _catIcon(entry.category);
        final onSurface = Theme.of(context).colorScheme.onSurface;

        return Card(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: color.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Colonne 1 : badge catégorie ────────────────────────────
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 60,
                      child: Text(
                        entry.category.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // ── Colonne 2 + 3 : fonctionnalité + description ───────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nom de la fonctionnalité
                      Text(
                        entry.feature,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Description fonctionnelle (abstraite)
                      Text(
                        entry.description,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.7),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bouton de clôture du tutoriel en bas de page.
class _DismissButton extends StatelessWidget {
  const _DismissButton({
    required this.isFirstLaunch,
    required this.onPressed,
  });

  final bool isFirstLaunch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(
            isFirstLaunch ? Icons.rocket_launch_outlined : Icons.close,
            color: Colors.black,
          ),
          label: Text(
            isFirstLaunch ? 'Commencer l\'application' : 'Fermer le guide',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: StreetPhareTheme.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
