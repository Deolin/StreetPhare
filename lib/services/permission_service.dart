// lib/services/permission_service.dart
//
// Service de routage des états d'autorisations vers l'UI.
//
// Responsabilités :
//   1. Vérifier l'état des permissions critiques (Bluetooth, Localisation,
//      Arrière-plan, Notifications).
//   2. Émettre des états d'erreur clairs quand une autorisation manque.
//   3. Fournir des callbacks pour afficher des popups de réactivation
//      automatique (openAppSettings()).
//   4. Détecter les changements à chaud et notifier l'UI.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Énumération des permissions critiques pour StreetPhare.
enum StreetPharePermission {
  bluetoothScan,
  bluetoothConnect,
  location,
  locationAlways,
  notification,
}

/// État d'une permission spécifique.
enum PermissionState {
  /// Accordée et active.
  granted,

  /// Refusée mais peut être redemandée.
  denied,

  /// Refusée définitivement (l'utilisateur doit aller dans les paramètres).
  permanentlyDenied,

  /// Le service système correspondant est désactivé.
  serviceDisabled,

  /// Non supportée sur cette plateforme.
  unsupported,
}

/// Modèle décrivant une permission manquante et son impact utilisateur.
class MissingPermission {
  const MissingPermission({
    required this.permission,
    required this.state,
    required this.label,
    required this.description,
    required this.impactDescription,
  });

  final StreetPharePermission permission;
  final PermissionState state;
  final String label;
  final String description;
  final String impactDescription;

  /// Indique si l'utilisateur peut résoudre via `openAppSettings()`.
  bool get canOpenSettings =>
      state == PermissionState.permanentlyDenied ||
      state == PermissionState.serviceDisabled;
}

/// Service singleton de gestion des permissions.
class PermissionService extends ChangeNotifier {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  final Map<StreetPharePermission, PermissionState> _states = {};

  List<MissingPermission> _missing = const [];
  List<MissingPermission> get missingPermissions => _missing;

  bool get hasMissingPermissions => _missing.isNotEmpty;
  bool get allGranted => !hasMissingPermissions;

  static String labelForPermission(StreetPharePermission p) {
    switch (p) {
      case StreetPharePermission.bluetoothScan:
        return 'Scan Bluetooth';
      case StreetPharePermission.bluetoothConnect:
        return 'Connexion Bluetooth';
      case StreetPharePermission.location:
        return 'Localisation';
      case StreetPharePermission.locationAlways:
        return 'Localisation en arrière-plan';
      case StreetPharePermission.notification:
        return 'Notifications';
    }
  }

  static String descriptionForPermission(StreetPharePermission p) {
    switch (p) {
      case StreetPharePermission.bluetoothScan:
        return 'Permet de scanner les pairs BLE pour le maillage décentralisé.';
      case StreetPharePermission.bluetoothConnect:
        return 'Permet de se connecter aux pairs BLE pour échanger des alertes.';
      case StreetPharePermission.location:
        return 'Nécessaire pour afficher votre position sur la carte et détecter les dangers proches.';
      case StreetPharePermission.locationAlways:
        return 'Permet de recevoir des alertes même quand l\'application est en arrière-plan.';
      case StreetPharePermission.notification:
        return 'Permet de vous avertir des dangers confirmés à proximité.';
    }
  }

  /// Vérifie toutes les permissions critiques.
  Future<void> checkAll() async {
    final checks = <Future<void>>[
      _check(StreetPharePermission.bluetoothScan, ph.Permission.bluetoothScan),
      _check(StreetPharePermission.bluetoothConnect, ph.Permission.bluetoothConnect),
      _check(StreetPharePermission.location, ph.Permission.location),
      _check(StreetPharePermission.locationAlways, ph.Permission.locationAlways),
      _check(StreetPharePermission.notification, ph.Permission.notification),
    ];
    await Future.wait(checks);
    _rebuildMissingList();
    notifyListeners();
  }

  Future<PermissionState> requestPermission(StreetPharePermission sp) async {
    final perm = _toHandler(sp);
    if (perm == null) return PermissionState.unsupported;

    if (sp == StreetPharePermission.location ||
        sp == StreetPharePermission.locationAlways) {
      final svc = await ph.Permission.location.serviceStatus.isEnabled;
      if (!svc) {
        _states[sp] = PermissionState.serviceDisabled;
        _rebuildMissingList();
        notifyListeners();
        return PermissionState.serviceDisabled;
      }
    }

    final status = await perm.request();
    final mapped = _map(status);
    _states[sp] = mapped;
    _rebuildMissingList();
    notifyListeners();
    return mapped;
  }

  Future<void> openSettings() async {
    await ph.openAppSettings();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  ph.Permission? _toHandler(StreetPharePermission sp) {
    switch (sp) {
      case StreetPharePermission.bluetoothScan:
        return ph.Permission.bluetoothScan;
      case StreetPharePermission.bluetoothConnect:
        return ph.Permission.bluetoothConnect;
      case StreetPharePermission.location:
        return ph.Permission.location;
      case StreetPharePermission.locationAlways:
        return ph.Permission.locationAlways;
      case StreetPharePermission.notification:
        return ph.Permission.notification;
    }
  }

  Future<void> _check(StreetPharePermission sp, ph.Permission perm) async {
    try {
      final status = await perm.status;
      _states[sp] = _map(status);
    } catch (e) {
      _states[sp] = PermissionState.unsupported;
      if (kDebugMode) {
        debugPrint('[PermissionService] $sp non supporté: $e');
      }
    }
  }

  PermissionState _map(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
        return PermissionState.granted;
      case ph.PermissionStatus.denied:
        return PermissionState.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return PermissionState.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return PermissionState.permanentlyDenied;
      case ph.PermissionStatus.limited:
        return PermissionState.granted;
      case ph.PermissionStatus.provisional:
        return PermissionState.granted;
    }
  }

  void _rebuildMissingList() {
    final missing = <MissingPermission>[];
    for (final entry in _states.entries) {
      final state = entry.value;
      if (state == PermissionState.granted ||
          state == PermissionState.unsupported) {
        continue;
      }
      missing.add(MissingPermission(
        permission: entry.key,
        state: state,
        label: labelForPermission(entry.key),
        description: descriptionForPermission(entry.key),
        impactDescription: _impact(entry.key),
      ));
    }
    _missing = missing;
  }

  String _impact(StreetPharePermission p) {
    switch (p) {
      case StreetPharePermission.bluetoothScan:
      case StreetPharePermission.bluetoothConnect:
        return 'Sans cette permission, le maillage décentralisé (BLE) est désactivé. '
            'Les alertes ne peuvent pas être échangées directement avec les appareils proches.';
      case StreetPharePermission.location:
        return 'Sans cette permission, votre position ne peut pas être affichée '
            'sur la carte et les alertes de proximité sont désactivées.';
      case StreetPharePermission.locationAlways:
        return 'Sans cette permission, les alertes en arrière-plan sont désactivées. '
            'L\'application ne pourra pas vous avertir quand elle est en veille.';
      case StreetPharePermission.notification:
        return 'Sans cette permission, vous ne recevrez pas de notifications '
            'pour les dangers confirmés à proximité.';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widgets UI — Popups de permission
// ══════════════════════════════════════════════════════════════════════════════

class MissingPermissionsDialog extends StatelessWidget {
  const MissingPermissionsDialog({
    super.key,
    required this.missing,
    this.onOpenSettings,
  });

  final List<MissingPermission> missing;
  final VoidCallback? onOpenSettings;

  static Future<void> show(
    BuildContext context, {
    required List<MissingPermission> missing,
    VoidCallback? onOpenSettings,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MissingPermissionsDialog(
        missing: missing,
        onOpenSettings: onOpenSettings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber, color: Color(0xFFFF6F00), size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Permissions requises',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Certaines fonctions de StreetPhare sont désactivées car les '
              'permissions suivantes sont manquantes :',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            for (final m in missing) ...[
              _PermissionItem(missing: m),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Plus tard'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onOpenSettings?.call();
            PermissionService.instance.openSettings();
          },
          icon: const Icon(Icons.settings, size: 18),
          label: const Text('Ouvrir les paramètres'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6F00),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({required this.missing});
  final MissingPermission missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF6F00).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForState(missing.state),
                  color: const Color(0xFFFF6F00), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  missing.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (missing.canOpenSettings)
                const Icon(Icons.settings, size: 14, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            missing.description,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            missing.impactDescription,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFFF6F00),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForState(PermissionState state) {
    switch (state) {
      case PermissionState.denied:
        return Icons.block;
      case PermissionState.permanentlyDenied:
        return Icons.gpp_bad;
      case PermissionState.serviceDisabled:
        return Icons.settings_power;
      default:
        return Icons.warning_amber;
    }
  }
}

class PermissionWarningBanner extends StatelessWidget {
  const PermissionWarningBanner({
    super.key,
    required this.missing,
    this.onTap,
  });

  final List<MissingPermission> missing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty) return const SizedBox.shrink();
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFFFF6F00).withValues(alpha: 0.95),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Permissions manquantes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      missing.map((m) => m.label).join(', '),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}