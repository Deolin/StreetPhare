// lib/features/admin/presentation/admin_dashboard_screen.dart
//
// Tableau de Bord d'Administration StreetPhare (Web).
//
// Layout responsive :
//   - Grand écran (≥ 900px) : carte à gauche, panneaux analytiques à droite
//   - Petit écran (< 900px)  : carte en haut, panneaux en dessous (scroll)
//
// Fonctionnalités :
//   1. Carte flutter_map temps réel (AdminMapWidget) — suivi réseau live.
//   2. Panneau de métriques ValueNotifier :
//      - Utilisateurs simulés actifs
//      - Alertes injectées
//      - Messages Hive P2P échangés
//      - Événements créés
//      - Cooldown anti-spam (secondes restantes)
//      - État de connexion sandbox
//   3. Contrôles Sandbox :
//      - Bouton "Injecter Alertes" → fait apparaître des marqueurs sur la carte
//      - Bouton "Injecter Événements" → crée des événements simulés
//      - Bouton "Messages Hive" → injecte des messages P2P
//      - Bouton "Simuler Utilisateurs" → démarre/arrête des users fictifs
//   4. Scrollbar globale pour éviter tout bug d'overflow au redimensionnement.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../network/transports/loopback_transport.dart';
import '../../sandbox/sandbox_controller.dart';
import 'admin_map_widget.dart';

/// Point de rupture responsive : largeur écran ≥ 900px → layout côte à côte.
const double _kResponsiveBreakpoint = 900.0;

/// Écran Dashboard Admin.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  LoopbackMeshTransport? _loopback;

  @override
  void initState() {
    super.initState();
    _initSandbox();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    SandboxController.instance.disconnect();
    super.dispose();
  }

  /// Initialise la connexion sandbox si on est sur le Web.
  Future<void> _initSandbox() async {
    // Tente de récupérer le transport loopback depuis le NetworkCoordinator.
    // En pratique, sur le Web, le bootstrap l'a déjà instancié.
    // On connecte simplement le contrôleur sandbox au backend Node.js.
    if (kIsWeb) {
      await SandboxController.instance.connect();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StreetPhareTheme.darkBackground,
      appBar: AppBar(
        title: const Text('StreetPhare — Administration'),
        backgroundColor: StreetPhareTheme.darkSurface,
        actions: [
          // Indicateur d'état de connexion sandbox
          ValueListenableBuilder<SandboxConnectionState>(
            valueListenable: SandboxController.instance.connectionState,
            builder: (context, state, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _statusIcon(state),
                      size: 12,
                      color: _statusColor(state),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _statusLabel(state),
                      style: TextStyle(
                        fontSize: 12,
                        color: _statusColor(state),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kResponsiveBreakpoint;

          if (isWide) {
            return _buildWideLayout(constraints);
          } else {
            return _buildNarrowLayout(constraints);
          }
        },
      ),
    );
  }

  /// Layout grand écran : carte à gauche, panneaux à droite.
  Widget _buildWideLayout(BoxConstraints constraints) {
    final mapWidth = constraints.maxWidth * 0.55;

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: SizedBox(
          height: constraints.maxHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Carte (55 %) ──────────────────────────────────────────────
              SizedBox(
                width: mapWidth,
                child: const AdminMapWidget(
                  darkMode: true,
                  showAttribution: true,
                ),
              ),

              // Séparateur vertical
              Container(
                width: 2,
                color: StreetPhareTheme.darkSurface.withValues(alpha: 0.5),
              ),

              // ── Panneaux analytiques (45 %) ───────────────────────────────
              Expanded(
                child: _buildAnalyticsPanel(scrollable: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Layout petit écran : carte en haut, panneaux en dessous.
  Widget _buildNarrowLayout(BoxConstraints constraints) {
    final mapHeight = constraints.maxHeight * 0.45;

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            // ── Carte (45 % hauteur) ──────────────────────────────────────
            SizedBox(
              height: mapHeight,
              width: double.infinity,
              child: const AdminMapWidget(
                darkMode: true,
                showAttribution: true,
              ),
            ),

            // ── Panneaux analytiques ─────────────────────────────────────
            _buildAnalyticsPanel(scrollable: false),
          ],
        ),
      ),
    );
  }

  /// Panneau de métriques + contrôles sandbox.
  ///
  /// [scrollable] : si true, ajoute un scroll interne pour le panneau.
  Widget _buildAnalyticsPanel({required bool scrollable}) {
    final panel = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Titre ────────────────────────────────────────────────────────
          Text(
            'Métriques Réseau',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: StreetPhareTheme.darkTextPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // ── Cartes de métriques ──────────────────────────────────────────
          _MetricCard(
            label: 'Utilisateurs simulés',
            notifier: SandboxController.instance.userCount,
            icon: Icons.people,
            color: Colors.cyanAccent,
          ),
          const SizedBox(height: 8),
          _MetricCard(
            label: 'Alertes injectées',
            notifier: SandboxController.instance.alertCount,
            icon: Icons.warning_amber,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 8),
          _MetricCard(
            label: 'Messages Hive P2P',
            notifier: SandboxController.instance.messageCount,
            icon: Icons.message,
            color: Colors.amberAccent,
          ),
          const SizedBox(height: 8),
          _MetricCard(
            label: 'Événements créés',
            notifier: SandboxController.instance.eventCount,
            icon: Icons.event,
            color: Colors.greenAccent,
          ),
          const SizedBox(height: 8),
          _MetricCard(
            label: 'Cooldown (s)',
            notifier: SandboxController.instance.cooldownSec,
            icon: Icons.timer,
            color: Colors.white70,
            suffix: 's',
          ),

          const SizedBox(height: 24),

          // ── Contrôles Sandbox ────────────────────────────────────────────
          Text(
            'Contrôles Sandbox',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: StreetPhareTheme.darkTextPrimary,
            ),
          ),
          const SizedBox(height: 12),

          _SandboxButton(
            label: 'Injecter Alertes (×3)',
            icon: Icons.warning_amber,
            color: Colors.redAccent,
            onTap: () => SandboxController.instance.injectAlerts(count: 3),
          ),
          const SizedBox(height: 8),
          _SandboxButton(
            label: 'Injecter Événement',
            icon: Icons.event,
            color: Colors.greenAccent,
            onTap: () => SandboxController.instance.injectEvents(count: 1),
          ),
          const SizedBox(height: 8),
          _SandboxButton(
            label: 'Messages Hive (×5)',
            icon: Icons.message,
            color: Colors.amberAccent,
            onTap: () => SandboxController.instance.injectMessages(count: 5),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: SandboxController.instance.userCount,
            builder: (context, count, _) {
              final isActive = count > 0;
              return _SandboxButton(
                label: isActive
                    ? 'Arrêter Utilisateurs ($count)'
                    : 'Simuler 5 Utilisateurs',
                icon: isActive ? Icons.stop : Icons.play_arrow,
                color: isActive ? Colors.red : Colors.cyanAccent,
                onTap: () =>
                    SandboxController.instance.simulateUsers(count: 5),
              );
            },
          ),
        ],
      ),
    );

    if (scrollable) {
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(child: panel),
      );
    }
    return panel;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _statusIcon(SandboxConnectionState state) {
    switch (state) {
      case SandboxConnectionState.connected:
        return Icons.check_circle;
      case SandboxConnectionState.connecting:
        return Icons.sync;
      case SandboxConnectionState.error:
        return Icons.error;
      case SandboxConnectionState.disconnected:
        return Icons.circle_outlined;
    }
  }

  Color _statusColor(SandboxConnectionState state) {
    switch (state) {
      case SandboxConnectionState.connected:
        return Colors.greenAccent;
      case SandboxConnectionState.connecting:
        return Colors.amberAccent;
      case SandboxConnectionState.error:
        return Colors.redAccent;
      case SandboxConnectionState.disconnected:
        return Colors.grey;
    }
  }

  String _statusLabel(SandboxConnectionState state) {
    switch (state) {
      case SandboxConnectionState.connected:
        return 'Sandbox connectée';
      case SandboxConnectionState.connecting:
        return 'Connexion...';
      case SandboxConnectionState.error:
        return 'Erreur sandbox';
      case SandboxConnectionState.disconnected:
        return 'Sandbox déconnectée';
    }
  }
}

// ============================================================================
// Widgets privés
// ============================================================================

/// Carte de métrique réactive (ValueListenableBuilder).
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.notifier,
    required this.icon,
    required this.color,
    this.suffix = '',
  });

  final String label;
  final ValueNotifier<int> notifier;
  final IconData icon;
  final Color color;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (context, value, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: StreetPhareTheme.darkSurface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                  color: StreetPhareTheme.darkTextSecondary,
                  ),
                ),
              ),
              Text(
                '$value$suffix',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bouton d'injection sandbox avec effet de clic.
class _SandboxButton extends StatefulWidget {
  const _SandboxButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SandboxButton> createState() => _SandboxButtonState();
}

class _SandboxButtonState extends State<_SandboxButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.color.withValues(alpha: 0.25)
              : widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.color.withValues(alpha: _pressed ? 0.7 : 0.35),
            width: _pressed ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: widget.color, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}