// lib/features/map/presentation/map_screen.dart
//
// Écran principal de StreetPhare.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/peer_counter_service.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../reports/presentation/report_bottom_sheet.dart';
import '../../settings/data/panic_contact_store.dart';
import '../../settings/presentation/settings_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  static const LatLng _defaultCenter = LatLng(48.8566, 2.3522);
  static const double _defaultZoom = 13.0;

  Timer? _demoPeerTimer;
  final int _rng = DateTime.now().microsecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    PeerCounterService.instance.start();
    _demoPeerTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _injectDemoPeer(),
    );
  }

  @override
  void dispose() {
    _demoPeerTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _injectDemoPeer() {
    final hit = (_rng + DateTime.now().second) % 2 == 0;
    if (hit) {
      PeerCounterService.instance.recordPeer(
        'demo_${DateTime.now().millisecondsSinceEpoch}',
      );
    }
  }

  void _openReportSheet() => ReportBottomSheet.show(context);

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _triggerRouteSafe() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: StreetPhareTheme.surface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  StreetPhareTheme.primary,
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Recherche d\'un chemin sûr…',
                style: TextStyle(color: StreetPhareTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerPanic() async {
    final contacts = PanicContactStore.instance.value;
    if (contacts.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StreetPhareTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: StreetPhareTheme.danger),
              SizedBox(width: 12),
              Text('Aucun contact d\'urgence',
                  style: TextStyle(color: StreetPhareTheme.textPrimary)),
            ],
          ),
          content: const Text(
            'Vous devez d\'abord configurer au moins un contact dans '
            'les Paramètres pour pouvoir utiliser le bouton PANIC.',
            style: TextStyle(color: StreetPhareTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ouvrir les Paramètres'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: StreetPhareTheme.danger, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.emergency, color: StreetPhareTheme.danger),
            SizedBox(width: 12),
            Text('Mode Panique',
                style: TextStyle(color: StreetPhareTheme.textPrimary)),
          ],
        ),
        content: Text(
          'Activer le mode panique enverra un SMS d\'alerte avec votre '
          'position GPS à ${contacts.length} contact(s) :\n\n'
          '${contacts.map((c) => '• ${c.name} (${c.phoneNumber})').join('\n')}\n\n'
          'Continuer ?',
          style: const TextStyle(color: StreetPhareTheme.textSecondary),
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
            child: const Text('ACTIVER'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final position = await _getCurrentPositionSafe();
    final message = _buildPanicMessage(position);

    final phones = contacts.map((c) => c.phoneNumber).join(',');
    final uri = Uri(
      scheme: 'sms',
      path: phones,
      queryParameters: {'body': message},
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('launchUrl returned false');
    } catch (e) {
      debugPrint('[Panic] impossible d\'ouvrir l\'app SMS : $e');
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: message));
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StreetPhareTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: StreetPhareTheme.primary),
              SizedBox(width: 12),
              Text('SMS préparé',
                  style: TextStyle(color: StreetPhareTheme.textPrimary)),
            ],
          ),
          content: Text(
            'Impossible d\'ouvrir l\'app SMS automatiquement.\n'
            'Le message a été copié dans le presse-papier :\n\n$message',
            style: const TextStyle(color: StreetPhareTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: StreetPhareTheme.primary),
            SizedBox(width: 12),
            Text('Alerte prête',
                style: TextStyle(color: StreetPhareTheme.textPrimary)),
          ],
        ),
        content: Text(
          'Un SMS d\'urgence va être envoyé à ${contacts.length} '
          'contact(s) avec votre position GPS.',
          style: const TextStyle(color: StreetPhareTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<Position?> _getCurrentPositionSafe() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('[Panic] erreur GPS : $e');
      return null;
    }
  }

  String _buildPanicMessage(Position? p) {
    final stamp = DateTime.now().toUtc().toIso8601String();
    final coords = p == null
        ? 'position GPS indisponible'
        : 'https://maps.google.com/?q=${p.latitude},${p.longitude} '
            '(${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';
    return '[STREETPHARE] Alerte d\'urgence envoyée le $stamp UTC.\n'
        'Position : $coords\n'
        'Merci de me contacter ou de prévenir les secours.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _defaultZoom,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.streetphare.app',
                maxNativeZoom: 19,
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: StreetPhareTheme.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lightbulb,
                              color: StreetPhareTheme.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'StreetPhare',
                            style: TextStyle(
                              color: StreetPhareTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _PeerCounterBadge(),
                    const Spacer(),
                    _CircleIconButton(
                      icon: Icons.settings_outlined,
                      onTap: _openSettings,
                    ),
                    const SizedBox(width: 8),
                    _CircleIconButton(
                      icon: Icons.info_outline,
                      onTap: () => _showInfoDialog(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ActionFab(
                  icon: Icons.add_alert,
                  label: 'Signalement',
                  backgroundColor: StreetPhareTheme.primary,
                  foregroundColor: Colors.black,
                  onPressed: _openReportSheet,
                ),
                const SizedBox(height: 12),
                _ActionFab(
                  icon: Icons.shield_outlined,
                  label: 'Route Safe',
                  backgroundColor: StreetPhareTheme.surface,
                  foregroundColor: StreetPhareTheme.primary,
                  borderColor: StreetPhareTheme.primary,
                  onPressed: _triggerRouteSafe,
                ),
                const SizedBox(height: 12),
                _ActionFab(
                  icon: Icons.emergency,
                  label: 'PANIC',
                  backgroundColor: StreetPhareTheme.danger,
                  foregroundColor: Colors.white,
                  isExtended: true,
                  onPressed: _triggerPanic,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        title: const Text('À propos de StreetPhare',
            style: TextStyle(color: StreetPhareTheme.textPrimary)),
        content: const Text(
          'Application citoyenne de cartographie collaborative en temps réel.\n\n'
          'Aucune donnée personnelle n\'est collectée.\n'
          'Version 1.0.0 - Open Source',
          style: TextStyle(color: StreetPhareTheme.textSecondary),
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

// ============================================================================
// Badge "Appareils proches : [X]"
// ============================================================================

class _PeerCounterBadge extends StatelessWidget {
  const _PeerCounterBadge();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PeerCounterService.instance,
      builder: (context, count, _) {
        final isActive = count > 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: StreetPhareTheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? StreetPhareTheme.primary.withValues(alpha: 0.6)
                  : StreetPhareTheme.textSecondary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? Icons.bolt : Icons.bolt_outlined,
                size: 14,
                color: isActive
                    ? StreetPhareTheme.primary
                    : StreetPhareTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Appareils proches : $count',
                style: TextStyle(
                  color: isActive
                      ? StreetPhareTheme.textPrimary
                      : StreetPhareTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Bouton d'action FAB
// ============================================================================

class _ActionFab extends StatelessWidget {
  const _ActionFab({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderColor,
    this.isExtended = false,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool isExtended;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final content = isExtended
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foregroundColor, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          )
        : Icon(icon, color: foregroundColor, size: 24);
    return Material(
      elevation: 6,
      shadowColor: backgroundColor.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(isExtended ? 28 : 16),
      color: backgroundColor,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(isExtended ? 28 : 16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isExtended ? 20 : 16,
            vertical: isExtended ? 14 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isExtended ? 28 : 16),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

// ============================================================================
// Bouton circulaire de la barre supérieure
// ============================================================================

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: StreetPhareTheme.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: StreetPhareTheme.textPrimary, size: 22),
        ),
      ),
    );
  }
}
