// lib/features/settings/presentation/settings_screen.dart
//
// Page "Paramètres" de StreetPhare — version enrichie.
//
// Sections :
//   1. Thème de l'application (Système / Clair / Sombre)
//   2. Mode Économe (battery saver) + filtre de notifications
//   3. Événements (lien vers la page d'invitation)
//   4. Filtres d'évitement (Route Safe)
//   5. Contacts d'urgence (Bouton Panic)
//   6. À propos
//
// CORRECTION MODE DIURNE : toutes les couleurs de texte utilisent
// désormais `Theme.of(context).colorScheme.onSurface` (et sa variante
// `.withValues(alpha: 0.6)` pour les textes secondaires) au lieu des
// constantes `StreetPhareTheme.textPrimary` / `textSecondary` qui
// sont codées en dur sur les couleurs du thème SOMBRE (blanc sur fond
// clair = invisible). Cela garantit un contraste parfait dans les
// deux modes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../events/presentation/events_screen.dart';
import '../../routing/data/avoidance_filter_store.dart';
import '../../routing/domain/models/avoidance_filters.dart';
import '../data/app_preferences_store.dart';
import '../data/panic_contact.dart';
import '../data/panic_contact_store.dart';

// ============================================================================
// SettingsScreen
// ============================================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Paramètres',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: const [
            _ThemeSection(),
            _BatterySaverSection(),
            _EventsSection(),
            _AvoidanceFiltersSection(),
            _PanicContactsSection(),
            _AboutSection(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Section THEME
// ============================================================================

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return _Card(
      child: ValueListenableBuilder<AppThemeMode>(
        valueListenable: ThemeController.instance,
        builder: (context, current, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.palette_outlined,
                title: 'Thème de l\'application',
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  'Le mode sombre est optimisé pour les écrans OLED '
                  'et reste discret la nuit.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: onSurface.withValues(alpha: 0.65)),
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<AppThemeMode>(
                groupValue: current,
                onChanged: (v) {
                  if (v == null) return;
                  ThemeController.instance.setMode(v);
                },
                child: Column(
                  children: [
                    for (final mode in AppThemeMode.values)
                      RadioListTile<AppThemeMode>(
                        value: mode,
                        title: Text(
                          mode.label,
                          style: TextStyle(color: onSurface, fontSize: 14),
                        ),
                        subtitle: Text(
                          _subtitleFor(mode),
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                        activeColor: StreetPhareTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _subtitleFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'Suit le réglage du système';
      case AppThemeMode.light:
        return 'Fond clair, lecture diurne';
      case AppThemeMode.dark:
        return 'Vrai noir OLED, économie de batterie';
    }
  }
}

// ============================================================================
// Section MODE ÉCONOME + NOTIFICATIONS
// ============================================================================

class _BatterySaverSection extends StatelessWidget {
  const _BatterySaverSection();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ValueListenableBuilder<AppPreferences>(
        valueListenable: AppPreferencesStore.instance,
        builder: (context, prefs, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── En-tête mode économe ───────────────────────────────────
              _SectionHeader(
                icon: Icons.battery_saver_outlined,
                title: 'Mode Économe',
                color: const Color(0xFF388E3C),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  'Réduit la fréquence des scans GPS/BLE et '
                  'coupe l\'affichage de la carte en arrière-plan. '
                  'Prolonge significativement l\'autonomie.',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                title: Text(
                  prefs.batterySaverEnabled
                      ? 'Mode Économe activé'
                      : 'Mode Économe désactivé',
                  style: TextStyle(color: onSurface, fontSize: 14),
                ),
                subtitle: Text(
                  prefs.batterySaverEnabled
                      ? 'Scans réduits, carte suspendue'
                      : 'Fonctionnement normal',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                value: prefs.batterySaverEnabled,
                onChanged: (v) =>
                    AppPreferencesStore.instance.setBatterySaver(v),
                activeThumbColor: const Color(0xFF388E3C),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),

              const Divider(height: 20),

              // ── Filtre de notifications ────────────────────────────────
              _SectionHeader(
                icon: Icons.notifications_outlined,
                title: 'Alertes en arrière-plan',
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  'Choisissez quelles alertes vous souhaitez '
                  'recevoir quand l\'application est en fond.',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<NotificationFilter>(
                groupValue: prefs.notificationFilter,
                onChanged: (v) {
                  if (v == null) return;
                  AppPreferencesStore.instance.setNotificationFilter(v);
                },
                child: Column(
                  children: [
                    for (final filter in NotificationFilter.values)
                      RadioListTile<NotificationFilter>(
                        value: filter,
                        title: Text(
                          filter.label,
                          style: TextStyle(color: onSurface, fontSize: 13),
                        ),
                        subtitle: Text(
                          filter.description,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                        activeColor: StreetPhareTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// Section ÉVÉNEMENTS
// ============================================================================

class _EventsSection extends StatelessWidget {
  const _EventsSection();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ListTile(
        leading: const Icon(Icons.event, color: StreetPhareTheme.primary, size: 26),
        title: Text(
          'Événements',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          'Rejoindre une manifestation via un code d\'invitation.\n'
          'Le trajet est révélé uniquement à l\'heure dite.',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: onSurface.withValues(alpha: 0.4),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EventsScreen()),
        ),
      ),
    );
  }
}

// ============================================================================
// Section FILTRES D'ÉVITEMENT
// ============================================================================

class _AvoidanceFiltersSection extends StatelessWidget {
  const _AvoidanceFiltersSection();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ValueListenableBuilder<AvoidanceFilters>(
        valueListenable: AvoidanceFilterStore.instance,
        builder: (context, filters, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.shield,
                title: 'Filtres d\'évitement (Route Safe)',
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  'Cochez les types de dangers que vous voulez '
                  'ABSOLUMENT ÉVITER. Le moteur de routage traitera '
                  'les autres comme franchissables (avec une légère '
                  'pénalité de proximité).',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _AvoidanceTile(
                title: 'Éviter les barrages',
                subtitle: 'Barrages filtrants ou durs',
                value: filters.avoidBarrages,
                onChanged: (v) => AvoidanceFilterStore.instance.update(
                    filters.copyWith(avoidBarrages: v)),
              ),
              _AvoidanceTile(
                title: 'Éviter les nasses',
                subtitle: 'Pièges, zones encerclées',
                value: filters.avoidNasses,
                onChanged: (v) => AvoidanceFilterStore.instance.update(
                    filters.copyWith(avoidNasses: v)),
              ),
              _AvoidanceTile(
                title: 'Éviter les contrôles de police',
                subtitle: 'Filtrages, contrôles d\'identité',
                value: filters.avoidControles,
                onChanged: (v) => AvoidanceFilterStore.instance.update(
                    filters.copyWith(avoidControles: v)),
              ),
              _AvoidanceTile(
                title: 'Éviter les accidents / autopompes',
                subtitle: 'Camions de pompiers, zones accidentées',
                value: filters.avoidAccidents,
                onChanged: (v) => AvoidanceFilterStore.instance.update(
                    filters.copyWith(avoidAccidents: v)),
              ),
              _AvoidanceTile(
                title: 'Éviter les manifestations / casseurs',
                subtitle: 'Zones de rassemblement à risque',
                value: filters.avoidManifestations,
                onChanged: (v) => AvoidanceFilterStore.instance.update(
                    filters.copyWith(avoidManifestations: v)),
              ),
              _AvoidanceTile(
                title: 'Éviter les dangers "autres"',
                subtitle: 'Tout autre signalement non catégorisé',
                value: filters.avoidAutres,
                onChanged: (v) => AvoidanceFilterStore.instance.update(
                    filters.copyWith(avoidAutres: v)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AvoidanceTile extends StatelessWidget {
  const _AvoidanceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(color: onSurface, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: onSurface.withValues(alpha: 0.6),
          fontSize: 12,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: StreetPhareTheme.primary,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

// ============================================================================
// Section CONTACTS PANIC
// ============================================================================

class _PanicContactsSection extends StatelessWidget {
  const _PanicContactsSection();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.emergency,
            title: 'Contacts d\'urgence (Bouton Panic)',
            color: StreetPhareTheme.danger,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              'Ces contacts recevront un SMS d\'alerte avec votre '
              'position GPS quand vous appuierez sur PANIC.',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<PanicContact>>(
            valueListenable: PanicContactStore.instance,
            builder: (context, contacts, _) {
              if (contacts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aucun contact configuré.\n'
                    'Ajoutez au moins un contact pour pouvoir utiliser '
                    'le bouton PANIC.',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final c in contacts)
                    _ContactTile(
                      contact: c,
                      onEdit: () => _openContactForm(context, c),
                      onDelete: () => _confirmDelete(context, c),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openContactForm(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un contact'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openContactForm(
    BuildContext context,
    PanicContact? existing,
  ) async {
    final result = await showDialog<_ContactFormResult>(
      context: context,
      builder: (_) => _ContactFormDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await PanicContactStore.instance.add(
        name: result.name,
        phone: result.phone,
      );
    } else {
      await PanicContactStore.instance.update(
        existing.id,
        name: result.name,
        phone: result.phone,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PanicContact c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          'Supprimer ce contact ?',
          style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: Text(
          '${c.name} (${c.phoneNumber}) sera retiré de la liste.',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PanicContactStore.instance.remove(c.id);
    }
  }
}

// ============================================================================
// Tuile d'un contact
// ============================================================================

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  final PanicContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: StreetPhareTheme.primary.withValues(alpha: 0.2),
        child: Text(
          contact.name.isEmpty ? '?' : contact.name[0].toUpperCase(),
          style: const TextStyle(
            color: StreetPhareTheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        contact.name,
        style: TextStyle(color: onSurface, fontSize: 15),
      ),
      subtitle: Text(
        contact.phoneNumber,
        style: TextStyle(
          color: onSurface.withValues(alpha: 0.65),
          fontSize: 13,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 20, color: onSurface.withValues(alpha: 0.6)),
            tooltip: 'Modifier',
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: onSurface.withValues(alpha: 0.6)),
            tooltip: 'Supprimer',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Formulaire contact
// ============================================================================

class _ContactFormResult {
  const _ContactFormResult(this.name, this.phone);
  final String name;
  final String phone;
}

class _ContactFormDialog extends StatefulWidget {
  const _ContactFormDialog({this.existing});
  final PanicContact? existing;

  @override
  State<_ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<_ContactFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        isEdit ? 'Modifier le contact' : 'Nouveau contact',
        style: TextStyle(color: onSurface),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              style: TextStyle(color: onSurface),
              decoration: const InputDecoration(
                labelText: 'Nom',
                hintText: 'Ex. Maman, Samu 112',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: onSurface),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-().]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                hintText: '+33 6 12 34 56 78',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Numéro requis';
                if (v.trim().length < 4) return 'Numéro trop court';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: StreetPhareTheme.primary,
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(
              _ContactFormResult(_name.text, _phone.text),
            );
          },
          child: Text(isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}

// ============================================================================
// Section À PROPOS
// ============================================================================

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline,
            color: StreetPhareTheme.primary, size: 26),
        title: Text(
          'À propos de StreetPhare',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          'Version, licence, open source',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: onSurface.withValues(alpha: 0.4),
        ),
        onTap: () => _showAboutDialog(context),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lightbulb,
                color: StreetPhareTheme.primary, size: 28),
            const SizedBox(width: 10),
            Text(
              'StreetPhare',
              style: TextStyle(
                color: onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AboutRow(label: 'Version', value: '1.1.0'),
              const SizedBox(height: 6),
              _AboutRow(label: 'Plateforme', value: 'Flutter / Dart'),
              const SizedBox(height: 6),
              _AboutRow(label: 'Licence', value: 'GNU GPL v3'),
              const SizedBox(height: 12),
              Text(
                'Projet open-source citoyen',
                style: TextStyle(
                  color: StreetPhareTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'StreetPhare est une application de cartographie '
                'collaborative en temps réel conçue pour renforcer '
                'la sécurité collective lors de rassemblements citoyens.\n\n'
                'Aucune donnée personnelle n\'est collectée ni transmise '
                'à des tiers. Toutes les données restent locales ou '
                'transitent uniquement via des relais pair-à-pair '
                'chiffrés.\n\n'
                'Le code source est disponible sous licence GNU GPL v3, '
                'garantissant votre liberté de l\'étudier, le modifier '
                'et le redistribuer.',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Text(
          '$label : ',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.65),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Widgets utilitaires partagés dans cet écran
// ============================================================================

/// Carte arrondie réutilisable pour chaque section.
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}

/// En-tête d'une section (icône + titre).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.color = StreetPhareTheme.primary,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
