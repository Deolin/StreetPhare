// lib/features/events/presentation/events_screen.dart
//
// Écran "Événements" — gestion multi-événements (jusqu'à 3 simultanés).
//
// Fonctionnalités :
//   1. Afficher la liste des événements chargés (max 3) sous forme de
//      cartes avec leur état (countdown, étape active, etc.).
//   2. Saisir un CODE D'INVITATION pour rejoindre un événement.
//   3. Scanner un QR CODE contenant les données JSON de l'événement.
//   4. Supprimer un événement individuel ou tous les événements.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/event_model.dart';
import 'event_manager.dart';
import 'qr_scanner_screen.dart';

/// Couleurs distinctives pour les 3 événements simultanés.
const _kEventColors = [
  Color(0xFFFFB300), // Ambre (thème primaire)
  Color(0xFF2196F3), // Bleu
  Color(0xFF4CAF50), // Vert
];

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  Future<void> _loadCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Veuillez saisir un code d\'invitation.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    if (EventManager.instance.count >= EventManager.maxEvents) {
      setState(() {
        _loading = false;
        _error =
            'Maximum ${EventManager.maxEvents} événements simultanés. '
            'Supprimez-en un avant d\'en ajouter un nouveau.';
      });
      return;
    }

    final ok = await EventManager.instance.loadByCode(code);
    if (!mounted) return;

    setState(() {
      _loading = false;
            if (!ok) {
                _error = 'Code inconnu ou événement introuvable.\n'
                    'Codes Fleurus : FLEURUS-TOUR, FLEURUS-ECOLES, FLEURUS-CORTEGE.';
      } else {
        _codeController.clear();
      }
    });
  }

  Future<void> _openQrScanner() async {
    if (EventManager.instance.count >= EventManager.maxEvents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum ${EventManager.maxEvents} événements simultanés. '
            'Supprimez-en un d\'abord.',
          ),
          backgroundColor: StreetPhareTheme.danger,
        ),
      );
      return;
    }

    final json = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (json == null || !mounted) return;

    final ok = await EventManager.instance.addFromSource(json);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'ajouter l\'événement (déjà présent ou limite '
            'de 3 événements atteinte).',
          ),
          backgroundColor: StreetPhareTheme.danger,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Événement ajouté depuis le QR Code !'),
        ),
      );
    }
  }

  void _removeEvent(String code) {
    EventManager.instance.removeByCode(code);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Événement retiré.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Événements'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      body: ValueListenableBuilder<List<EventModel>>(
        valueListenable: EventManager.instance,
        builder: (context, events, _) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── Section : Mes événements ─────────────────────────────────
              _SectionHeader(
                icon: Icons.event_note,
                color: StreetPhareTheme.primary,
                title: 'Mes événements (${events.length}/${EventManager.maxEvents})',
              ),
              const SizedBox(height: 8),

              if (events.isEmpty)
                _EmptyEventsCard()
              else
                ...events.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EventCard(
                      event: e.value,
                      color: _kEventColors[e.key % _kEventColors.length],
                      onRemove: () => _removeEvent(e.value.code),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // ── Section : Rejoindre un événement ─────────────────────────
              if (events.length < EventManager.maxEvents) ...[
                _SectionHeader(
                  icon: Icons.add_circle_outline,
                  color: StreetPhareTheme.primary,
                  title: 'Rejoindre un événement',
                ),
                const SizedBox(height: 8),
                _JoinCard(
                  codeController: _codeController,
                  loading: _loading,
                  error: _error,
                  onLoadCode: _loadCode,
                  onScanQr: _openQrScanner,
                ),
                const SizedBox(height: 16),
              ],

              // ── Section : Sécurité juste-à-temps ─────────────────────────
              _SectionHeader(
                icon: Icons.lock_clock,
                color: StreetPhareTheme.accent,
                title: 'Sécurité juste-à-temps',
              ),
              const SizedBox(height: 8),
              _InfoCard(
                child: const Text(
                  'Pour éviter que le tracé d\'un événement ne soit '
                  'détourné en amont, StreetPhare ne révèle le trajet '
                  'qu\'à l\'heure paramétrée par les organisateurs.\n\n'
                  'De plus, chaque étape (point de rassemblement) '
                  'disparaît automatiquement de la carte dès que son '
                  'heure est dépassée de 5 minutes, ou que vous vous '
                  'trouvez à moins de 30 m de ce point.',
                  style: TextStyle(
                    color: StreetPhareTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// Widgets internes
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

// ── Carte "aucun événement" ──────────────────────────────────────────────────

class _EmptyEventsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.event_busy,
                size: 48, color: StreetPhareTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'Aucun événement chargé',
              style: TextStyle(
                color: StreetPhareTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Saisissez un code d\'invitation ou scannez un QR Code '
              'pour rejoindre jusqu\'à 3 événements simultanément.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: StreetPhareTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Carte d'un événement chargé ──────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.color,
    required this.onRemove,
  });

  final EventModel event;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final isVisible = event.isRouteVisible(now);
    final remaining = event.remainingBeforeReveal(now);
    final activeStep = event.waypoints.isNotEmpty
        ? event.activeStepIndex(now: now)
        : null;

    return Card(
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête ──────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      color: StreetPhareTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: StreetPhareTheme.textSecondary),
                  tooltip: 'Retirer l\'événement',
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Infos basiques ───────────────────────────────────────────
            Text(
              'Code : ${event.code}',
              style: const TextStyle(
                  color: StreetPhareTheme.textSecondary, fontSize: 11),
            ),
            Text(
              'Début : ${_fmt(event.startAt)}',
              style: const TextStyle(
                  color: StreetPhareTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 10),

            // ── Statut du tracé ──────────────────────────────────────────
            if (!isVisible)
              _StatusBlock(
                icon: Icons.lock_clock,
                iconColor: StreetPhareTheme.danger,
                bgColor: StreetPhareTheme.danger.withValues(alpha: 0.12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trajet masqué — révélation dans :',
                      style: TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCountdown(remaining),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              )
            else if (activeStep != null &&
                activeStep < event.waypoints.length)
              _StatusBlock(
                icon: Icons.navigation,
                iconColor: color,
                bgColor: color.withValues(alpha: 0.12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Étape ${activeStep + 1}/${event.waypoints.length} active :',
                      style: const TextStyle(
                        color: StreetPhareTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.waypoints[activeStep].label,
                      style: const TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Heure prévue : '
                      '${event.waypoints[activeStep].formattedTime}',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              _StatusBlock(
                icon: Icons.check_circle,
                iconColor: StreetPhareTheme.primary,
                bgColor: StreetPhareTheme.primary.withValues(alpha: 0.12),
                child: const Text(
                  'Trajet visible — toutes les étapes complétées ou '
                  'événement sans étapes.',
                  style: TextStyle(
                    color: StreetPhareTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Carte "Rejoindre" avec champ code + bouton QR ───────────────────────────

class _JoinCard extends StatelessWidget {
  const _JoinCard({
    required this.codeController,
    required this.loading,
    required this.error,
    required this.onLoadCode,
    required this.onScanQr,
  });

  final TextEditingController codeController;
  final bool loading;
  final String? error;
  final VoidCallback onLoadCode;
  final VoidCallback onScanQr;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Saisissez le code d\'invitation (ex. MANIF-123) '
              'ou scannez un QR Code.',
              style: TextStyle(
                color: StreetPhareTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),

            // Champ de saisie + bouton charger
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(32),
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Z0-9\-]')),
                    ],
                    decoration: InputDecoration(
                      hintText: 'MANIF-123',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                      errorText: error,
                      errorMaxLines: 3,
                    ),
                    onSubmitted: (_) => onLoadCode(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: loading ? null : onLoadCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StreetPhareTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.black),
                          ),
                        )
                      : const Text('Charger'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Bouton QR Code
            OutlinedButton.icon(
              onPressed: onScanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un QR Code'),
              style: OutlinedButton.styleFrom(
                foregroundColor: StreetPhareTheme.primary,
                side: const BorderSide(color: StreetPhareTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 8),
            const Text(
              'Codes Fleurus : FLEURUS-TOUR · FLEURUS-ECOLES · FLEURUS-CORTEGE',
              style: TextStyle(
                  color: StreetPhareTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
