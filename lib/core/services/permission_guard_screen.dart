// lib/core/services/permission_guard_screen.dart
//
// Écran de blocage affiché au démarrage si des permissions indispensables
// au maillage P2P sont manquantes.
//
// L'utilisateur ne peut pas accéder à la carte tant que toutes les
// permissions requises ne sont pas accordées. Deux actions sont proposées :
//   1. « Activer les permissions » — demande native une par une.
//   2. « Ouvrir les paramètres » — redirige vers les paramètres Android
//      de l'application (utile pour les permissions permanentlyDenied).

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'permission_guard_service.dart';

/// Écran plein écran bloquant l'accès à l'application tant que les
/// permissions indispensables au maillage P2P ne sont pas accordées.
class PermissionGuardScreen extends StatefulWidget {
  const PermissionGuardScreen({super.key});

  @override
  State<PermissionGuardScreen> createState() => _PermissionGuardScreenState();
}

class _PermissionGuardScreenState extends State<PermissionGuardScreen> {
  final _guard = PermissionGuardService.instance;

  /// Résultat courant de la vérification.
  PermissionGuardResult? _result;

  /// Indique si une demande est en cours (évite le double-clic).
  bool _isRequesting = false;

  /// Message d'état affiché sous les boutons.
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final result = await _guard.checkAll();
    if (!mounted) return;
    setState(() {
      _result = result;
      if (result.allGranted) {
        _redirectToMap();
      }
    });
  }

  /// Tente de demander toutes les permissions manquantes.
  Future<void> _onRequestPermissions() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
      _statusMessage = null;
    });

    try {
      final result = await _guard.requestMissing();
      if (!mounted) return;
      setState(() {
        _result = result;
        _isRequesting = false;
        if (result.allGranted) {
          _statusMessage = '✅ Toutes les permissions sont accordées !';
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _redirectToMap();
          });
        } else if (result.permanentlyDeniedPermissions.isNotEmpty) {
          _statusMessage =
              'Certaines permissions sont définitivement refusées.\n'
              'Ouvrez les paramètres pour les activer manuellement.';
        } else {
          _statusMessage = 'Permissions refusées. Veuillez réessayer.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRequesting = false;
        _statusMessage = 'Erreur : $e';
      });
    }
  }

  /// Ouvre les paramètres système de l'application.
  Future<void> _onOpenSettings() async {
    await _guard.openAppSettings();
    // On revérifie après le retour des paramètres.
    if (mounted) {
      await _checkPermissions();
    }
  }

  /// Redirige vers la carte (via pop).
  void _redirectToMap() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icône ─────────────────────────────────────────────
              Icon(
                Icons.shield_outlined,
                size: 72,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 24),

              // ── Titre ─────────────────────────────────────────────
              Text(
                'Permissions requises',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // ── Description ───────────────────────────────────────
              Text(
                'StreetPhare a besoin de ces autorisations pour faire '
                'fonctionner le réseau décentralisé P2P et détecter '
                'les appareils à proximité.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Liste des permissions ─────────────────────────────
              if (result != null) ...[
                for (final perm
                    in PermissionGuardService.indispensablePermissions)
                  _PermissionTile(
                    permission: perm,
                    isGranted: !result.missingPermissions.contains(perm) &&
                        !result.permanentlyDeniedPermissions.contains(perm),
                    isPermanentlyDenied:
                        result.permanentlyDeniedPermissions.contains(perm),
                  ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),

              const SizedBox(height: 32),

              // ── Message de statut ─────────────────────────────────
              if (_statusMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusMessage!.startsWith('✅')
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _statusMessage!.startsWith('✅')
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _statusMessage!.startsWith('✅')
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Boutons d'action ──────────────────────────────────
              if (result != null && !result.allGranted) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isRequesting ? null : _onRequestPermissions,
                    icon: _isRequesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      _isRequesting
                          ? 'Demande en cours…'
                          : 'Activer les permissions',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _onOpenSettings,
                    icon: const Icon(Icons.settings, size: 20),
                    label: const Text('Ouvrir les paramètres'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tuile décrivant une permission et son état.
class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.permission,
    required this.isGranted,
    required this.isPermanentlyDenied,
  });

  final Permission permission;
  final bool isGranted;
  final bool isPermanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    if (isGranted) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusLabel = 'Accordée';
    } else if (isPermanentlyDenied) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusLabel = 'Refusée (paramètres)';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.error_outline;
      statusLabel = 'Refusée';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(statusIcon, color: statusColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PermissionGuardResult.labelFor(permission),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    PermissionGuardResult.impactFor(permission),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}