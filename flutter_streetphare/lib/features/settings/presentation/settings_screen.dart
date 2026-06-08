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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _ThemeSection(),
          _PanicContactsSection(),
        ],
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
                ...AppThemeMode.values.map(
                  (mode) => RadioListTile<AppThemeMode>(
                    value: mode,
                    groupValue: current,
                    onChanged: (v) {
                      if (v == null) return;
                      ThemeController.instance.setMode(v);
                    },
                    title: Text(mode.label),
                    subtitle: Text(_subtitleFor(mode)),
                    activeColor: StreetPhareTheme.primary,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
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
