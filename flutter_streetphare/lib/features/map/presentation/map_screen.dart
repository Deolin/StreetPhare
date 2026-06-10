// lib/features/map/presentation/map_screen.dart
//
// Écran principal de StreetPhare.
//
// Nouveautés :
//   1. CORRECTION MODE SOMBRE : TileLayer réagit instantanément au
//      changement de thème grâce à `key: ValueKey(isDark)` + surveillance
//      de ThemeController. Tuiles CartoDB Dark Matter en mode sombre.
//   2. MULTI-ÉVÉNEMENTS : Jusqu'à 3 tracés simultanés en couleurs distinctes
//      (ambre, bleu, vert) avec chips d'identification en haut de la carte.
//   3. ÉTAPES ÉPHÉMÈRES : Seul le segment de l'étape courante + le waypoint
//      suivant sont affichés. Les étapes passées/futures restent masquées.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/peer_counter_service.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../events/domain/models/event_model.dart';
import '../../events/presentation/event_manager.dart';
import '../../reports/presentation/report_bottom_sheet.dart';
import '../../settings/data/panic_contact_store.dart';
import '../../settings/presentation/settings_screen.dart';

// ── Couleurs des 3 événements (synchronisées avec events_screen) ─────────────
const _kEventColors = [
  Color(0xFFFFB300), // Ambre
  Color(0xFF2196F3), // Bleu
  Color(0xFF4CAF50), // Vert
];

const _kTileUrlLight = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _kTileUrlDark =
    'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

// ============================================================================
// MapScreen
// ============================================================================

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

  Position? _userPosition;
  String? _positionError;
  bool _locating = true;
  StreamSubscription<Position>? _positionSub;

  @override
  void initState() {
    super.initState();
    PeerCounterService.instance.start();
    _demoPeerTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _injectDemoPeer(),
    );
    _initUserLocation();
  }

  @override
  void dispose() {
    _demoPeerTimer?.cancel();
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // GPS
  // --------------------------------------------------------------------------

  Future<void> _initUserLocation() async {
    setState(() {
      _locating = true;
      _positionError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _locating = false;
          _positionError = 'Service GPS désactivé';
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() {
            _locating = false;
            _positionError = 'Autorisation GPS refusée';
          });
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _positionError = 'Autorisation GPS refusée définitivement';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _locating = false;
      });
      _animateToUser();
      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((p) {
        if (mounted) setState(() => _userPosition = p);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _locating = false;
          _positionError = 'Erreur GPS : $e';
        });
      }
    }
  }

  void _animateToUser() {
    final pos = _userPosition;
    if (pos == null) return;
    try {
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
        } catch (_) {}
      });
    }
  }

  Marker _buildUserMarker() {
    final pos = _userPosition!;
    return Marker(
      point: LatLng(pos.latitude, pos.longitude),
      width: 56,
      height: 56,
      child: _UserPhareMarker(accuracy: pos.accuracy),
    );
  }

  void _injectDemoPeer() {
    final hit = (_rng + DateTime.now().second) % 2 == 0;
    if (hit) {
      PeerCounterService.instance
          .recordPeer('demo_${DateTime.now().millisecondsSinceEpoch}');
    }
  }

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  void _openReportSheet() => ReportBottomSheet.show(context);

  void _openSettings() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );

  void _triggerRouteSafe() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
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
                backgroundColor: StreetPhareTheme.danger),
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
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;
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

  // --------------------------------------------------------------------------
  // Logique des événements sur la carte
  // --------------------------------------------------------------------------

  /// Construit les polylines et markers pour tous les événements actifs.
  _EventLayers _buildEventLayers(List<EventModel> events) {
    final polylines = <Polyline>[];
    final markers = <Marker>[];
    final now = DateTime.now().toUtc();
    final userLatLng = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : null;

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final color = _kEventColors[i % _kEventColors.length];

      if (!event.isRouteVisible(now)) continue;

      final allPoints = event.decodeRoute();
      if (allPoints.isEmpty) continue;

      if (event.waypoints.isEmpty) {
        // Pas d'étapes définies : on affiche la route complète.
        polylines.add(Polyline(
          points: allPoints,
          color: color,
          strokeWidth: 4.5,
        ));
      } else {
        final activeStep = event.activeStepIndex(now: now, userPos: userLatLng);

        if (activeStep >= event.waypoints.length) {
          // Toutes les étapes sont passées : on affiche le tracé complet
          // en grisé pour indiquer que l'événement est terminé.
          polylines.add(Polyline(
            points: allPoints,
            color: color.withValues(alpha: 0.30),
            strokeWidth: 2.5,
          ));
          continue;
        }

        // ── Segment de l'étape active ────────────────────────────────────
        final segmentPoints = event.getSegmentPoints(activeStep, allPoints);
        if (segmentPoints.length >= 2) {
          polylines.add(Polyline(
            points: segmentPoints,
            color: color,
            strokeWidth: 5,
          ));
        }

        // ── Marker waypoint actif ────────────────────────────────────────
        final currentWp = event.waypoints[activeStep];
        markers.add(Marker(
          point: currentWp.position,
          width: 100,
          height: 72,
          child: _WaypointMarker(
            label: currentWp.label,
            timeStr: currentWp.formattedTime,
            color: color,
            isCurrent: true,
          ),
        ));

        // ── Marker waypoint suivant (révélé à l'avance) ──────────────────
        if (activeStep + 1 < event.waypoints.length) {
          final nextWp = event.waypoints[activeStep + 1];
          markers.add(Marker(
            point: nextWp.position,
            width: 100,
            height: 72,
            child: _WaypointMarker(
              label: nextWp.label,
              timeStr: nextWp.formattedTime,
              color: color.withValues(alpha: 0.65),
              isCurrent: false,
            ),
          ));
        }
      }
    }

    return _EventLayers(polylines: polylines, markers: markers);
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // ── Surveillance du thème pour la correction du mode sombre ───────────
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) {
        final brightness = MediaQuery.platformBrightnessOf(context);
        final isDark = themeMode == AppThemeMode.dark ||
            (themeMode == AppThemeMode.system &&
                brightness == Brightness.dark);
        final tileUrl = isDark ? _kTileUrlDark : _kTileUrlLight;

        // ── Surveillance des événements ──────────────────────────────────
        return ValueListenableBuilder<List<EventModel>>(
          valueListenable: EventManager.instance,
          builder: (context, events, _) {
            final layers = _buildEventLayers(events);
            final hasMarkers =
                layers.markers.isNotEmpty || _userPosition != null;

            return Scaffold(
              body: Stack(
                children: [
                  // ── Carte ──────────────────────────────────────────────
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _defaultCenter,
                      initialZoom: _defaultZoom,
                      minZoom: 3,
                      maxZoom: 19,
                      interactionOptions: const InteractionOptions(
                        flags:
                            InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      // FIX MODE SOMBRE : key force la destruction/recréation
                      // du TileLayer quand le thème change.
                      TileLayer(
                        key: ValueKey('tiles_$isDark'),
                        urlTemplate: tileUrl,
                        userAgentPackageName: 'com.streetphare.app',
                        maxNativeZoom: 19,
                      ),

                      // ── Tracés des événements ──────────────────────────
                      if (layers.polylines.isNotEmpty)
                        PolylineLayer(polylines: layers.polylines),

                      // ── Marqueurs (user + waypoints) ───────────────────
                      if (hasMarkers)
                        MarkerLayer(
                          markers: [
                            if (_userPosition != null) _buildUserMarker(),
                            ...layers.markers,
                          ],
                        ),

                      // ── Indicateur GPS ─────────────────────────────────
                      if (_locating)
                        const Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: 12, bottom: 24),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    StreetPhareTheme.primary),
                              ),
                            ),
                          ),
                        ),

                      if (_positionError != null)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(left: 12, bottom: 24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: StreetPhareTheme.surface
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.gps_off,
                                      size: 12,
                                      color: StreetPhareTheme.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    _positionError!,
                                    style: const TextStyle(
                                        color: StreetPhareTheme.textSecondary,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ── Attribution ────────────────────────────────────
                      RichAttributionWidget(
                        alignment: AttributionAlignment.bottomLeft,
                        attributions: [
                          TextSourceAttribution(
                            isDark
                                ? 'CartoDB / OpenStreetMap contributors'
                                : 'OpenStreetMap contributors',
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ── Barre supérieure ────────────────────────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Logo
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: StreetPhareTheme.surface
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lightbulb,
                                      color: StreetPhareTheme.primary,
                                      size: 18),
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
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Chips d'événements (sous la barre) ─────────────────
                  if (events.isNotEmpty)
                    Positioned(
                      top: 80,
                      left: 12,
                      right: 80,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: events.asMap().entries.map((entry) {
                            final i = entry.key;
                            final ev = entry.value;
                            final col =
                                _kEventColors[i % _kEventColors.length];
                            final isVisible = ev.isRouteVisible();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isVisible
                                          ? Icons.navigation
                                          : Icons.lock_clock,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ev.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                  // ── FABs actions ────────────────────────────────────────
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
          },
        );
      },
    );
  }
}

// ── Données brutes des layers événements ─────────────────────────────────────

class _EventLayers {
  const _EventLayers({required this.polylines, required this.markers});
  final List<Polyline> polylines;
  final List<Marker> markers;
}

// ============================================================================
// Marker waypoint sur la carte
// ============================================================================

class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.label,
    required this.timeStr,
    required this.color,
    required this.isCurrent,
  });

  final String label;
  final String timeStr;
  final Color color;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 100),
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '$label\n$timeStr',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Icon(
          isCurrent ? Icons.location_on : Icons.location_on_outlined,
          color: color,
          size: isCurrent ? 22 : 16,
        ),
      ],
    );
  }
}

// ============================================================================
// Marqueur position utilisateur
// ============================================================================

class _UserPhareMarker extends StatelessWidget {
  const _UserPhareMarker({required this.accuracy});
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: StreetPhareTheme.primary.withValues(alpha: 0.15),
            border: Border.all(
              color: StreetPhareTheme.primary.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: StreetPhareTheme.primary,
            boxShadow: [
              BoxShadow(
                color: StreetPhareTheme.primary.withValues(alpha: 0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Badge "Appareils proches"
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
// FAB action
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
// Bouton circulaire barre supérieure
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
          child:
              Icon(icon, color: StreetPhareTheme.textPrimary, size: 22),
        ),
      ),
    );
  }
}
