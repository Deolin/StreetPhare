// lib/features/settings/presentation/settings_screen.dart
//
// Page "Paramètres" de StreetPhare.
//
// On y trouve :
//   1. La section "Thème de l'application" (Radio : Système, Clair, Sombre).
//   2. La section "Contacts d'urgence (Bouton Panic)" avec la liste
//      des contacts, et les actions d'ajout / modification / suppression.
//   3. (Plus tard) d'autres réglages.
//
// L'UI écoute `ThemeController.instance` et `PanicContactStore.instance`
// via `ValueListenableBuilder` : tout changement est reflété en
// temps réel, sans rebuild global.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../events/presentation/events_screen.dart';
import '../../routing/data/avoidance_filter_store.dart';
import '../../routing/domain/models/avoidance_filters.dart';
import '../data/panic_contact.dart';
import '../data/panic_contact_store.dart';

/// Page de paramètres (full-screen, avec AppBar).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Column(
          children: [
            _ThemeSection(),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<AppThemeMode>(
          valueListenable: ThemeController.instance,
          builder: (context, current, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined,
                        color: StreetPhareTheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Thème de l\'application',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    'Le mode sombre est optimisé pour les écrans OLED '
                    'et reste discret la nuit.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 8),
                // Flutter 3.32+ : RadioListTile déprécié.
                // On utilise le nouveau RadioGroup<T> qui encapsule
                // un ensemble de Radio<T> et gère la sélection.
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
                          title: Text(mode.label),
                          subtitle: Text(_subtitleFor(mode)),
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
// Section CONTACTS PANIC
// ============================================================================

class _PanicContactsSection extends StatelessWidget {
  const _PanicContactsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emergency,
                    color: StreetPhareTheme.danger, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Contacts d\'urgence (Bouton Panic)',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                'Ces contacts recevront un SMS d\'alerte avec votre '
                'position GPS quand vous appuierez sur PANIC.',
                style: theme.textTheme.bodyMedium,
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
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final c in contacts)
                      _ContactTile(
                        contact: c,
                        onEdit: () => _openContactForm(context, c),
                        onDelete: () =>
                            _confirmDelete(context, c),
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
      ),
    );
  }

  // -------- Formulaire d'ajout / édition --------

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
        title: const Text('Supprimer ce contact ?'),
        content: Text('${c.name} (${c.phoneNumber}) sera retiré de la liste.'),
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
    final theme = Theme.of(context);
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
      title: Text(contact.name, style: theme.textTheme.bodyLarge),
      subtitle: Text(contact.phoneNumber, style: theme.textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Modifier',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Supprimer',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Dialogue de formulaire (ajout / édition)
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
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(isEdit ? 'Modifier le contact' : 'Nouveau contact'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
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
// Section ÉVÉNEMENTS (lien vers la page de codes d'invitation)
// ============================================================================

class _EventsSection extends StatelessWidget {
  const _EventsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: const Icon(Icons.event, color: StreetPhareTheme.primary, size: 26),
        title: const Text('Événements'),
        subtitle: const Text(
          'Rejoindre une manifestation via un code d\'invitation.\n'
          'Le trajet est révélé uniquement à l\'heure dite.',
        ),
        trailing: const Icon(Icons.chevron_right,
            color: StreetPhareTheme.textSecondary),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EventsScreen()),
        ),
      ),
    );
  }
}

// ============================================================================
// Section FILTRES D'ÉVITEMENT (préférences Safe Path)
// ============================================================================

class _AvoidanceFiltersSection extends StatelessWidget {
  const _AvoidanceFiltersSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<AvoidanceFilters>(
          valueListenable: AvoidanceFilterStore.instance,
          builder: (context, filters, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield,
                        color: StreetPhareTheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Filtres d\'évitement (Route Safe)',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    'Cochez les types de dangers que vous voulez '
                    'ABSOLUMENT ÉVITER. Le moteur de routage traitera '
                    'les autres comme franchissables (avec une légère '
                    'pénalité de proximité).',
                    style: theme.textTheme.bodyMedium,
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
    return SwitchListTile(
      title: Text(title,
          style: const TextStyle(
              color: StreetPhareTheme.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: StreetPhareTheme.textSecondary, fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: StreetPhareTheme.primary,
      contentPadding: EdgeInsets.zero,
      dense: true,
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.info_outline,
            color: StreetPhareTheme.primary, size: 26),
        title: const Text('À propos de StreetPhare'),
        subtitle: const Text('Version, licence, open source'),
        trailing: const Icon(Icons.chevron_right,
            color: StreetPhareTheme.textSecondary),
        onTap: () => _showAboutDialog(context),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lightbulb, color: StreetPhareTheme.primary, size: 28),
            SizedBox(width: 10),
            Text('StreetPhare',
                style: TextStyle(
                    color: StreetPhareTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AboutRow(label: 'Version', value: '1.0.0'),
              SizedBox(height: 6),
              _AboutRow(label: 'Plateforme', value: 'Flutter / Dart'),
              SizedBox(height: 6),
              _AboutRow(label: 'Licence', value: 'GNU GPL v3'),
              SizedBox(height: 12),
              Text(
                'Projet open-source citoyen',
                style: TextStyle(
                    color: StreetPhareTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              SizedBox(height: 6),
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
                    color: StreetPhareTheme.textSecondary, fontSize: 13),
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

/// Ligne clé/valeur pour le dialogue À propos.
class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label : ',
            style: const TextStyle(
                color: StreetPhareTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: const TextStyle(
                color: StreetPhareTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
