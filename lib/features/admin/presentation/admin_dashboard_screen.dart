// lib/features/admin/presentation/admin_dashboard_screen.dart
//
// Panneau minimal de débogage sandbox StreetPhare.
// Le dashboard d'administration global est désormais géré par
// le serveur Node.js (server/admin_dashboard_v2.js) accessible
// via navigateur. Cette vue Flutter ne conserve QUE les contrôles
// sandbox d'injection à usage local développeur.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../sandbox/sandbox_controller.dart';

/// Écran de débogage sandbox — contrôles d'injection uniquement.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      SandboxController.instance.connect();
    }
  }

  @override
  void dispose() {
    SandboxController.instance.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StreetPhareTheme.darkBackground,
      appBar: AppBar(
        title: const Text('StreetPhare — Sandbox Débogage'),
        backgroundColor: StreetPhareTheme.darkSurface,
        actions: [
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Contrôles Sandbox',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: StreetPhareTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dashboard global → server/admin_dashboard_v2.js',
                  style: TextStyle(
                    fontSize: 12,
                    color: StreetPhareTheme.darkTextSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                _SandboxButton(
                  label: 'Injecter Alertes (×3)',
                  icon: Icons.warning_amber,
                  color: Colors.redAccent,
                  onTap: () =>
                      SandboxController.instance.injectAlerts(count: 3),
                ),
                const SizedBox(height: 8),
                _SandboxButton(
                  label: 'Injecter Événement',
                  icon: Icons.event,
                  color: Colors.greenAccent,
                  onTap: () =>
                      SandboxController.instance.injectEvents(count: 1),
                ),
                const SizedBox(height: 8),
                _SandboxButton(
                  label: 'Messages Hive (×5)',
                  icon: Icons.message,
                  color: Colors.amberAccent,
                  onTap: () =>
                      SandboxController.instance.injectMessages(count: 5),
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
          ),
        ),
      ),
    );
  }

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

/// Bouton d'injection sandbox avec effet de pression.
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
