// lib/features/settings/presentation/settings_screen.dart
//
// Page "Paramètres" de StreetPhare — v2.2
//
// Sections (dans l'ordre d'affichage) :
//   1. ★ Événements (EN PREMIER — accès rapide rejoindre une manif)
//   2. Mode Malvoyant / Accessibilité
//   3. Messagerie Hive P2P (filtre messages)
//   4. Thème de l'application
//   5. Mode Économe + Filtre de notifications
//   6. Filtres d'évitement (Route Safe)
//   7. Cartes — Cache & Mise à jour
//   8. Service arrière-plan (notifications persistantes)
//   9. Contacts d'urgence (Bouton Panic)
//  10. Guide de l'application (tutoriel)
//  11. À propos

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../services/app_share_service.dart';
import '../../bug_report/presentation/bug_report_fab.dart';
import '../../events/presentation/events_screen.dart';
import '../../routing/data/avoidance_filter_store.dart';
import '../../routing/domain/models/avoidance_filters.dart';
import '../../tutorial/presentation/tutorial_screen.dart';
import '../../messaging/data/hive_block_service.dart';
import '../data/app_preferences_store.dart';
import '../data/panic_contact.dart';
import '../data/panic_contact_store.dart';

// ============================================================================
// SettingsScreen
// ============================================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<AppLanguage>(
          valueListenable: AppLocale.instance,
          builder: (context, _, child) => Text(
            AppLocale.instance.strings.settingsTitle,
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: onSurface),
      ),
      body: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLocale.instance,
            builder: (context, _, child) {
              final s = AppLocale.instance.strings;
              return Column(
                children: [
                  _EventsSection(strings: s),
                  _LanguageSection(strings: s),
                  _LowVisionSection(strings: s),
                  _MessageFilterSection(strings: s),
                  _BlockedUsersSection(strings: s),
                  _ThemeSection(strings: s),
                  _BatterySaverSection(strings: s),
                  _AndroidNotificationSection(strings: s),
                  _AvoidanceFiltersSection(strings: s),
                  _MapCacheSection(strings: s),
                  _BackgroundServiceSection(strings: s),
                  _PanicContactsSection(strings: s),
                  _ShareApkSection(strings: s),
                  _TutorialSection(strings: s),
                  _AboutSection(strings: s),
                  _BugReportSection(strings: s),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// [1] Section ÉVÉNEMENTS (EN TÊTE DE LISTE)
// ============================================================================

class _EventsSection extends StatelessWidget {
  const _EventsSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ListTile(
        leading: const Icon(Icons.event,
            color: StreetPhareTheme.primary, size: 26),
        title: Text(
          strings.eventsTitle,
          style: TextStyle(
              color: onSurface, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Text(
          strings.eventsJoin,
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
// [1b] Section CHOIX DE LA LANGUE
// ============================================================================

class _LanguageSection extends StatelessWidget {
  const _LanguageSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.language,
            title: strings.languageSectionTitle,
            color: const Color(0xFF00897B),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              strings.languageSectionDescription,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: DropdownButtonFormField<AppLanguage>(
              initialValue: AppLocale.instance.value,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              dropdownColor: Theme.of(context).colorScheme.surface,
              style: TextStyle(color: onSurface, fontSize: 14),
              items: AppLanguage.values.map((lang) {
                return DropdownMenuItem(
                  value: lang,
                  child: Row(
                    children: [
                      Text(lang.flag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Text(lang.code.toUpperCase() == 'FR' ? 'Français' : 
                           lang.code.toUpperCase() == 'EN' ? 'English' :
                           lang.code.toUpperCase() == 'NL' ? 'Nederlands' : 'Deutsch'),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (lang) {
                if (lang != null) {
                  AppLocale.instance.setLanguage(lang);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// [2] Section MODE MALVOYANT / ACCESSIBILITÉ
// ============================================================================

class _LowVisionSection extends StatelessWidget {
  const _LowVisionSection({required this.strings});
  final AppStrings strings;

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
              _SectionHeader(
                icon: Icons.accessibility_new,
                title: strings.lowVisionTitle,
                color: const Color(0xFF7B1FA2),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  strings.lowVisionDescription,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                title: Text(
                  prefs.lowVisionMode
                      ? strings.lowVisionEnabled
                      : strings.lowVisionDisabled,
                  style: TextStyle(color: onSurface, fontSize: 14),
                ),
                subtitle: Text(
                  prefs.lowVisionMode
                      ? strings.lowVisionStatusEnabled
                      : strings.lowVisionStatusDisabled,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                value: prefs.lowVisionMode,
                onChanged: (v) =>
                    AppPreferencesStore.instance.setLowVisionMode(v),
                activeThumbColor: const Color(0xFF7B1FA2),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    const Icon(Icons.text_fields, size: 20, color: Color(0xFF7B1FA2)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: prefs.textScaleFactor,
                        min: 1.0,
                        max: 2.0,
                        divisions: 10,
                        activeColor: const Color(0xFF7B1FA2),
                        label: '${prefs.textScaleFactor.toStringAsFixed(1)}×',
                        onChanged: (v) =>
                            AppPreferencesStore.instance.setTextScaleFactor(v),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${prefs.textScaleFactor.toStringAsFixed(1)}×',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// [3] Section MESSAGERIE HIVE P2P — FILTRE
// ============================================================================

class _MessageFilterSection extends StatelessWidget {
  const _MessageFilterSection({required this.strings});
  final AppStrings strings;

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
              _SectionHeader(
                icon: Icons.forum_outlined,
                title: strings.messageFilterTitle,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  strings.messageFilterDescription,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<MessageFilter>(
                groupValue: prefs.messageFilter,
                onChanged: (v) {
                  if (v == null) return;
                  AppPreferencesStore.instance.setMessageFilter(v);
                },
                child: Column(
                  children: [
                    for (final f in MessageFilter.values)
                      RadioListTile<MessageFilter>(
                        value: f,
                        title: Text(
                          f.label,
                          style: TextStyle(color: onSurface, fontSize: 13),
                        ),
                        subtitle: Text(
                          f.description,
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
// [4] Section THEME
// ============================================================================

class _ThemeSection extends StatelessWidget {
  const _ThemeSection({required this.strings});
  final AppStrings strings;

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
                title: strings.themeSectionTitle,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  strings.themeDescription,
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
                          mode.subtitle,
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
}

// ============================================================================
// [5] Section MODE ÉCONOME + NOTIFICATIONS
// ============================================================================

class _BatterySaverSection extends StatelessWidget {
  const _BatterySaverSection({required this.strings});
  final AppStrings strings;

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
              _SectionHeader(
                icon: Icons.battery_saver_outlined,
                title: strings.batterySaverTitle,
                color: const Color(0xFF388E3C),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  strings.batterySaverDescription,
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
                      ? strings.batterySaverEnabledLabel
                      : strings.batterySaverDisabledLabel,
                  style: TextStyle(color: onSurface, fontSize: 14),
                ),
                subtitle: Text(
                  prefs.batterySaverEnabled
                      ? strings.batterySaverStatusEnabled
                      : strings.batterySaverStatusDisabled,
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
              _SectionHeader(
                icon: Icons.notifications_outlined,
                title: strings.backgroundAlertsTitle,
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
// [6] Section FILTRES D'ÉVITEMENT
// ============================================================================

class _AvoidanceFiltersSection extends StatelessWidget {
  const _AvoidanceFiltersSection({required this.strings});
  final AppStrings strings;

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
                title: strings.avoidanceFiltersTitle,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  strings.avoidanceFiltersDescription,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _AvoidanceTile(
                title: strings.avoidBarragesTitle,
                subtitle: strings.avoidBarragesSubtitle,
                value: filters.avoidBarrages,
                onChanged: (v) => AvoidanceFilterStore.instance
                    .update(filters.copyWith(avoidBarrages: v)),
              ),
              _AvoidanceTile(
                title: strings.avoidNassesTitle,
                subtitle: strings.avoidNassesSubtitle,
                value: filters.avoidNasses,
                onChanged: (v) => AvoidanceFilterStore.instance
                    .update(filters.copyWith(avoidNasses: v)),
              ),
              _AvoidanceTile(
                title: strings.avoidControlesTitle,
                subtitle: strings.avoidControlesSubtitle,
                value: filters.avoidControles,
                onChanged: (v) => AvoidanceFilterStore.instance
                    .update(filters.copyWith(avoidControles: v)),
              ),
              _AvoidanceTile(
                title: strings.avoidAccidentsTitle,
                subtitle: strings.avoidAccidentsSubtitle,
                value: filters.avoidAccidents,
                onChanged: (v) => AvoidanceFilterStore.instance
                    .update(filters.copyWith(avoidAccidents: v)),
              ),
              _AvoidanceTile(
                title: strings.avoidRassemblementsTitle,
                subtitle: strings.avoidRassemblementsSubtitle,
                value: filters.avoidRassemblements,
                onChanged: (v) => AvoidanceFilterStore.instance
                    .update(filters.copyWith(avoidRassemblements: v)),
              ),
              _AvoidanceTile(
                title: strings.avoidAutresTitle,
                subtitle: strings.avoidAutresSubtitle,
                value: filters.avoidAutres,
                onChanged: (v) => AvoidanceFilterStore.instance
                    .update(filters.copyWith(avoidAutres: v)),
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
      title: Text(title, style: TextStyle(color: onSurface, fontSize: 14)),
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
// [7] Section CARTES & CACHE
// ============================================================================

class _MapCacheSection extends StatelessWidget {
  const _MapCacheSection({required this.strings});
  final AppStrings strings;

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
              _SectionHeader(
                icon: Icons.map_outlined,
                title: strings.mapCacheTitle,
                color: const Color(0xFF0277BD),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  '${strings.mapCacheDescription} (${prefs.mapCacheMaxAgeDays} ${strings.mapCacheDays})',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Sélecteur durée cache
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      strings.mapCacheRetentionLabel,
                      style:
                          TextStyle(color: onSurface, fontSize: 13),
                    ),
                  ),
                  DropdownButton<int>(
                    value: prefs.mapCacheMaxAgeDays,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    style: TextStyle(
                        color: onSurface, fontSize: 13),
                    items: [1, 3, 7, 14, 30].map((v) => 
                      DropdownMenuItem(value: v, child: Text('$v ${strings.mapCacheDays}'))
                    ).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        AppPreferencesStore.instance
                            .setMapCacheMaxAgeDays(v);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Bouton "Forcer la mise à jour"
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: OutlinedButton.icon(
                    onPressed: () => _forceMapUpdate(context),
                    icon: const Icon(Icons.refresh,
                        size: 18, color: Color(0xFF0277BD)),
                    label: Text(
                      strings.mapCacheForceUpdate,
                      style: const TextStyle(
                          color: Color(0xFF0277BD), fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0277BD)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _forceMapUpdate(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.refresh, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.mapCacheCleaned,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0277BD),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
    AppPreferencesStore.instance.setMapCacheMaxAgeDays(
      AppPreferencesStore.instance.value.mapCacheMaxAgeDays,
    );
  }
}

// ============================================================================
// [8] Section SERVICE ARRIÈRE-PLAN
// ============================================================================

class _BackgroundServiceSection extends StatelessWidget {
  const _BackgroundServiceSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.notifications_active_outlined,
            title: strings.backgroundServiceTitle,
            color: const Color(0xFFFFB300),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              strings.backgroundServiceDescription,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 30),
              child: ElevatedButton.icon(
                onPressed: () {
                   // Appel futur : showBackgroundPermissionDialog(context)
                },
                icon: const Icon(Icons.battery_saver, size: 18),
                label: Text(strings.backgroundServiceEnable),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB300),
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// [9] Section CONTACTS PANIC
// ============================================================================

class _PanicContactsSection extends StatelessWidget {
  const _PanicContactsSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.emergency,
            title: strings.panicContactsTitle,
            color: StreetPhareTheme.danger,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              strings.panicContactsDescription,
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
                    strings.panicContactsConfigError,
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
                      strings: strings,
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
              label: Text(strings.panicContactsAdd),
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
      builder: (_) => _ContactFormDialog(existing: existing, strings: strings),
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

  Future<void> _confirmDelete(BuildContext context, PanicContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          strings.panicContactsDeleteTitle,
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: Text(
          '${c.name} (${c.phoneNumber}) ${strings.panicContactsDeleteMessage}',
          style: TextStyle(
            color: Theme.of(ctx)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PanicContactStore.instance.remove(c.id);
    }
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.strings,
    required this.onEdit,
    required this.onDelete,
  });

  final PanicContact contact;
  final AppStrings strings;
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
      title: Text(contact.name,
          style: TextStyle(color: onSurface, fontSize: 15)),
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
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: onSurface.withValues(alpha: 0.6)),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _ContactFormResult {
  const _ContactFormResult(this.name, this.phone);
  final String name;
  final String phone;
}

class _ContactFormDialog extends StatefulWidget {
  const _ContactFormDialog({this.existing, required this.strings});
  final PanicContact? existing;
  final AppStrings strings;

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
    final s = widget.strings;
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        isEdit ? s.panicContactsEditTitle : s.panicContactsNewTitle,
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
              decoration: InputDecoration(
                labelText: s.panicContactsFieldName,
                hintText: s.panicContactsNameHint,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.panicContactsNameRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: onSurface),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9+\s\-().]')),
              ],
              decoration: InputDecoration(
                labelText: s.panicContactsFieldPhone,
                hintText: s.panicContactsPhoneHint,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return s.panicContactsPhoneRequired;
                if (v.trim().length < 4) return s.panicContactsPhoneTooShort;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
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
          child: Text(isEdit ? s.save : s.panicContactsAdd),
        ),
      ],
    );
  }
}

// ============================================================================
// [10] Section TUTORIEL
// ============================================================================

class _TutorialSection extends StatelessWidget {
  const _TutorialSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ListTile(
        leading: const Icon(Icons.help_outline,
            color: StreetPhareTheme.primary, size: 26),
        title: Text(
          strings.tutorialTitle,
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          strings.tutorialDescription,
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: onSurface.withValues(alpha: 0.4)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TutorialScreen(isFirstLaunch: false),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// [11] Section À PROPOS
// ============================================================================

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline,
            color: StreetPhareTheme.primary, size: 26),
        title: Text(
          strings.aboutApp,
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${strings.aboutVersion} 1.2.0 — ${strings.aboutLicense} GNU GPL v3',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: onSurface.withValues(alpha: 0.4)),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lightbulb,
                color: StreetPhareTheme.primary, size: 28),
            const SizedBox(width: 10),
            Text(
              strings.appTitle,
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
              _AboutRow(label: strings.aboutVersion, value: '1.2.0'),
              const SizedBox(height: 6),
              _AboutRow(label: strings.aboutPlatform, value: 'Flutter / Dart'),
              const SizedBox(height: 6),
              _AboutRow(label: strings.aboutLicense, value: 'GNU GPL v3'),
              const SizedBox(height: 6),
              _AboutRow(
                  label: strings.aboutEncryption, value: 'Hive local + Ed25519'),
              const SizedBox(height: 12),
              Text(
                strings.aboutOpenSource,
                style: const TextStyle(
                  color: StreetPhareTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                strings.aboutDescription,
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
            child: Text(strings.close),
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
// [4b] Section NOTIFICATIONS ANDROID SYSTÈME (canal séparé)
// ============================================================================

class _AndroidNotificationSection extends StatelessWidget {
  const _AndroidNotificationSection({required this.strings});
  final AppStrings strings;

  List<_AndroidChannel> get _channels => [
    _AndroidChannel(
      id: 'alerts',
      icon: Icons.warning_amber_outlined,
      title: strings.androidChannelAlertsTitle,
      subtitle: strings.androidChannelAlertsSubtitle,
      color: const Color(0xFFFF6F00),
    ),
    _AndroidChannel(
      id: 'events',
      icon: Icons.event_note_outlined,
      title: strings.androidChannelEventsTitle,
      subtitle: strings.androidChannelEventsSubtitle,
      color: const Color(0xFF1565C0),
    ),
    _AndroidChannel(
      id: 'panic',
      icon: Icons.emergency_outlined,
      title: strings.androidChannelPanicTitle,
      subtitle: strings.androidChannelPanicSubtitle,
      color: const Color(0xFFC62828),
    ),
    _AndroidChannel(
      id: 'messages',
      icon: Icons.forum_outlined,
      title: strings.androidChannelMessagesTitle,
      subtitle: strings.androidChannelMessagesSubtitle,
      color: const Color(0xFF00695C),
    ),
  ];

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
              _SectionHeader(
                icon: Icons.notification_important_outlined,
                title: strings.androidChannelSectionTitle,
                color: const Color(0xFF6A1B9A),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  // Un peu long à traduire exactement, on garde la structure
                  strings.notificationFilterTitle, 
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final ch in _channels)
                _AndroidChannelTile(
                  channel: ch,
                  enabled: prefs.isAndroidChannelEnabled(ch.id),
                  onChanged: (v) => AppPreferencesStore.instance
                      .setAndroidChannelEnabled(ch.id, v),
                ),
              const Divider(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: Text(
                      strings.androidChannelManageSystem,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _openAndroidNotificationSettings(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF6A1B9A)),
                      foregroundColor: const Color(0xFF6A1B9A),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _openAndroidNotificationSettings() async {
    try {
      const channel =
          MethodChannel('com.streetphare.app/system');
      await channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }
}

class _AndroidChannel {
  const _AndroidChannel({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _AndroidChannelTile extends StatelessWidget {
  const _AndroidChannelTile({
    required this.channel,
    required this.enabled,
    required this.onChanged,
  });
  final _AndroidChannel channel;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SwitchListTile(
      secondary: Icon(channel.icon, color: channel.color, size: 22),
      title: Text(channel.title,
          style: TextStyle(color: onSurface, fontSize: 13)),
      subtitle: Text(
        channel.subtitle,
        style: TextStyle(
            color: onSurface.withValues(alpha: 0.6), fontSize: 11),
      ),
      value: enabled,
      onChanged: onChanged,
      activeThumbColor: channel.color,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

// ============================================================================
// [3b] Section UTILISATEURS BLOQUÉS (Messagerie P2P)
// ============================================================================

class _BlockedUsersSection extends StatelessWidget {
  const _BlockedUsersSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final blockSvc = HiveBlockService.instance;
    return _Card(
      child: ListenableBuilder(
        listenable: blockSvc,
        builder: (context, _) {
          final blockedIds = blockSvc.blockedIds;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.block_outlined,
                title: strings.blockedUsersTitle,
                color: StreetPhareTheme.danger,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  strings.blockedUsersDescription,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (blockedIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 8),
                  child: Text(
                    strings.blockedUsersEmpty,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 30, bottom: 4),
                  child: Text(
                    strings.blockedUsersCount
                        .replaceFirst('{count}', '${blockedIds.length}'),
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                for (final id in blockedIds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor:
                          StreetPhareTheme.danger.withValues(alpha: 0.15),
                      radius: 16,
                      child: Text(
                        id.length >= 2 ? id.substring(0, 2).toUpperCase() : id,
                        style: const TextStyle(
                          color: StreetPhareTheme.danger,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      _truncateId(id),
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: TextButton.icon(
                      onPressed: () async {
                        await HiveBlockService.instance.unblockUser(id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_truncateId(id)} débloqué(e). Ses messages sont à nouveau visibles.',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: StreetPhareTheme.primary,
                              duration: const Duration(seconds: 3),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.lock_open,
                          size: 16, color: StreetPhareTheme.primary),
                      label: Text(
                        strings.blockedUsersUnblock,
                        style: const TextStyle(
                          color: StreetPhareTheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Tronque un UUID éphémère pour l'affichage.
  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
  }
}

// ============================================================================
// [5b] Section SIGNALEMENT DE BUGS
// ============================================================================

class _BugReportSection extends StatelessWidget {
  const _BugReportSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.bug_report_outlined,
            title: strings.bugReportSectionTitle,
            color: const Color(0xFF00838F),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00838F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF00838F).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '${strings.bugReportSectionDescription}\n\n'
              '${strings.bugReportDescription}\n\n'
              '${strings.bugReportPrivacy}',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.75),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.bug_report, size: 18),
                label: Text(strings.bugReportButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00838F),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => BugReportDialog.show(context),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(strings.bugReportSuggest),
                onPressed: () => BugReportDialog.show(context),
                style: OutlinedButton.styleFrom(
                  side:
                      const BorderSide(color: Color(0xFF00838F)),
                  foregroundColor: const Color(0xFF00838F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// [12] Section PARTAGE DE L'APK (BLUETOOTH / PROXIMITÉ)
// ============================================================================

class _ShareApkSection extends StatelessWidget {
  const _ShareApkSection({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      child: ListTile(
        leading: const Icon(Icons.share,
            color: StreetPhareTheme.primary, size: 26),
        title: Text(
          'Partager StreetPhare',
          style: TextStyle(
              color: onSurface, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Text(
          'Envoyez l\'APK de StreetPhare via Bluetooth, WiFi Direct ou autre application.',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: onSurface.withValues(alpha: 0.4)),
        onTap: () => _showInstructionsDialog(context),
      ),
    );
  }

  /// Affiche la boîte de dialogue de procédure guidée en français, puis lance
  /// le partage après confirmation explicite de l'utilisateur.
  void _showInstructionsDialog(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.share, color: StreetPhareTheme.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Partager StreetPhare',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Introduction
              Text(
                'Cette fonction vous permet d\'envoyer le fichier d\'installation '
                '(APK) de StreetPhare directement à un autre appareil Android, '
                'sans passer par le Play Store ni aucun autre store.',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              // Étape 1
              _InstructionStep(
                number: '1',
                title: 'Vérifiez la source',
                description:
                    'L\'APK partagé est celui actuellement installé sur votre '
                    'appareil. Assurez-vous de partager une version à jour et de '
                    'confiance (v2.2.0+).',
                color: StreetPhareTheme.primary,
                onSurface: onSurface,
              ),
              const SizedBox(height: 10),

              // Étape 2
              _InstructionStep(
                number: '2',
                title: 'Choisissez le canal de partage',
                description:
                    'Après avoir appuyé sur "Partager maintenant", la feuille de '
                    'partage Android s\'ouvrira. Choisissez Bluetooth, WiFi Direct, '
                    'ou une application de messagerie (Signal, Telegram, etc.).',
                color: const Color(0xFF0277BD),
                onSurface: onSurface,
              ),
              const SizedBox(height: 10),

              // Étape 3
              _InstructionStep(
                number: '3',
                title: 'Autorisez les sources inconnues',
                description:
                    'Sur l\'appareil destinataire, avant d\'installer l\'APK, '
                    'il sera nécessaire d\'autoriser les « sources inconnues » '
                    'dans les Paramètres Android → Sécurité → Installer des apps '
                    'inconnues.',
                color: const Color(0xFFE65100),
                onSurface: onSurface,
              ),
              const SizedBox(height: 10),

              // Étape 4
              _InstructionStep(
                number: '4',
                title: '⚠️ Avertissement de sécurité',
                description:
                    'Partagez cet APK uniquement avec des personnes de confiance. '
                    'Vérifiez toujours l\'intégrité du fichier avant installation. '
                    'StreetPhare est un projet open-source sous licence GNU GPL v3.',
                color: StreetPhareTheme.danger,
                onSurface: onSurface,
              ),
              const SizedBox(height: 16),

              // Note légale
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StreetPhareTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: StreetPhareTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '📦 Aucune donnée personnelle n\'est incluse dans l\'APK. '
                  'Le code source est vérifiable sur GitHub.\n'
                  '🔒 Toutes les communications StreetPhare sont chiffrées '
                  'de bout en bout via Hive P2P et Ed25519.',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.75),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Partager maintenant'),
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AppShareService.instance.shareApk(context: context);
            },
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Widget de numérotation des étapes d'instructions
// --------------------------------------------------------------------------

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.number,
    required this.title,
    required this.description,
    required this.color,
    required this.onSurface,
  });

  final String number;
  final String title;
  final String description;
  final Color color;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cercle numéroté
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Widgets utilitaires partagés
// ============================================================================

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
