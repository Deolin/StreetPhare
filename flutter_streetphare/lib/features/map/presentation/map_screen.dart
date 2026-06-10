// lib/features/map/presentation/map_screen.dart
//
// Écran principal de StreetPhare — v2.
//
// Nouvelles fonctionnalités :
//   1. Bouton "Recentrer la carte" (GPS) flottant.
//   2. Chips d'événements cliquables pour sélectionner l'événement actif.
//   3. Sélecteur de destination (manif / soins / sortie / point utilisateur).
//   4. Appui long (≥ 3 s) sur la carte → point utilisateur + Route Safe auto.
//   5. Stratégie de repli (failover) si le premier calcul échoue.
//   6. Diffusion du signal panic sur le maillage P2P lors de PANIC.
//   7. Notification UI quand une alerte panic collective est créée.

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
import '../../settings/data/app_preferences_store.dart';
import '../../settings/data/panic_contact_store.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../../network/collective_panic_service.dart';
import '../../../network/network_coordinator.dart';

import '../../routing/data/avoidance_filter_store.dart';
import '../../routing/presentation/route_result_sheet.dart';
import '../../routing/presentation/safe_path_engine.dart';
import 'widgets/safe_route_layer.dart';
import 'widgets/user_heading_marker.dart';

// ── Couleurs des 3 événements ─────────────────────────────────────────────────
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

  StreamSubscription<CollectivePanicEvent>? _collectivePanicSub;

  /// Marqueur du point utilisateur (appui long).
  LatLng? _userPointMarker;

  /// Cap de déplacement de l'utilisateur en degrés (0 = Nord, sens horaire).
  /// Alimenté par [Geolocator.getPositionStream] en temps réel.
  double _userHeading = 0.0;

  /// Points de la Route Safe active (null = aucune route affichée sur la carte).
  List<LatLng>? _safeRoutePoints;

  @override
  void initState() {
    super.initState();
    PeerCounterService.instance.start();
    _demoPeerTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _injectDemoPeer(),
    );
    _initUserLocation();
    // Écoute les alertes panic collectives automatiques.
    _collectivePanicSub =
        CollectivePanicService.instance.collectivePanicEvents.listen(
      _onCollectivePanicAlert,
    );
  }

  @override
  void dispose() {
    _demoPeerTimer?.cancel();
    _positionSub?.cancel();
    _collectivePanicSub?.cancel();
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
        if (mounted) {
          setState(() {
            _userPosition = p;
            // Position.heading retourne -1 sur les appareils sans boussole
            // (ou quand le cap n'est pas encore disponible). On ne met à
            // jour _userHeading que si la valeur est positive (valide).
            if (p.heading >= 0) _userHeading = p.heading;
          });
        }
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
      child: UserHeadingMarker(
        heading: _userHeading,
        accuracy: pos.accuracy,
      ),
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
  // Appui long sur la carte → point utilisateur + Route Safe
  // --------------------------------------------------------------------------

  void _onMapLongPress(TapPosition tapPos, LatLng latlng) {
    // Feedback haptique
    HapticFeedback.heavyImpact();

    // Enregistre le point utilisateur.
    AppPreferencesStore.instance.setUserPoint(
      latlng.latitude,
      latlng.longitude,
    );

    // Met à jour l'affichage.
    setState(() {
      _userPointMarker = latlng;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: StreetPhareTheme.surface,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.location_on,
                  color: StreetPhareTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Point utilisateur défini — Route Safe lancée…',
                  style: const TextStyle(color: StreetPhareTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );

    // Déclenche la Route Safe vers ce point.
    _triggerRouteSafe(overrideDestination: latlng);
  }

  // --------------------------------------------------------------------------
  // Route Safe — calcul avec failover
  // --------------------------------------------------------------------------

  Future<void> _triggerRouteSafe({LatLng? overrideDestination}) async {
    final prefs = AppPreferencesStore.instance.value;
    final events = EventManager.instance.value;

    LatLng? destination = overrideDestination;
    String destinationLabel = 'Point utilisateur';

    if (destination == null) {
      // Résolution de la destination selon le sélecteur.
      final userLatLng = _userPosition != null
          ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
          : null;

      switch (prefs.routeDestinationType) {
        case RouteDestinationType.manifestPoint:
          if (events.isNotEmpty) {
            final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
            destination = events[idx].destination;
            destinationLabel = 'Point de manif (${events[idx].title})';
          }

        case RouteDestinationType.careCenter:
          if (userLatLng != null && events.isNotEmpty) {
            final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
            final center = events[idx].nearestCareCenter(userLatLng);
            if (center != null) {
              destination = center.position;
              destinationLabel = 'Centre de soins : ${center.label}';
            }
          }

        case RouteDestinationType.exitPoint:
          if (userLatLng != null && events.isNotEmpty) {
            final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
            final exit = events[idx].nearestExitPoint(userLatLng);
            if (exit != null) {
              destination = exit.position;
              destinationLabel = 'Sortie : ${exit.label}';
            }
          }

        case RouteDestinationType.userPoint:
          if (prefs.userPointLatitude != null &&
              prefs.userPointLongitude != null) {
            destination = LatLng(
              prefs.userPointLatitude!,
              prefs.userPointLongitude!,
            );
            destinationLabel = 'Point utilisateur';
          }
      }
    }

    // Aucune destination résolue → tentative de failover.
    if (destination == null) {
      await _triggerRouteSafeFailover();
      return;
    }

    // Lance le calcul et affiche le sélecteur d'itinéraires.
    await _computeAndShowRoute(destination, destinationLabel);
  }

  /// Stratégie de repli : si la destination principale échoue,
  /// on cherche une Zone Safe ou un Centre de soins dans l'événement actif.
  Future<void> _triggerRouteSafeFailover() async {
    final prefs = AppPreferencesStore.instance.value;
    final events = EventManager.instance.value;
    final userLatLng = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : null;

    if (userLatLng == null || events.isEmpty) {
      _showNoDestinationError();
      return;
    }

    final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
    final event = events[idx];

    // Essai 1 : zone safe.
    final safeZone = event.nearestSafeZone(userLatLng);
    if (safeZone != null) {
      await _computeAndShowRoute(
        safeZone.position,
        'Zone Safe : ${safeZone.label}',
        isFailover: true,
      );
      return;
    }

    // Essai 2 : centre de soins.
    final careCenter = event.nearestCareCenter(userLatLng);
    if (careCenter != null) {
      await _computeAndShowRoute(
        careCenter.position,
        'Centre de soins : ${careCenter.label}',
        isFailover: true,
      );
      return;
    }

    // Aucun repli possible.
    _showNoDestinationError();
  }

  void _showRouteSafeProgress(String message, {bool isFailover = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isFailover
              ? const Color(0xFFFF6F00)
              : StreetPhareTheme.surface,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFailover ? Colors.white : StreetPhareTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isFailover
                        ? Colors.white
                        : StreetPhareTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _showNoDestinationError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          backgroundColor: StreetPhareTheme.danger,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Aucune destination disponible. '
                  'Rejoignez un événement ou placez un point manuellement '
                  '(appui long 3 s sur la carte).',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // --------------------------------------------------------------------------
  // Calcul de route et affichage du résultat
  // --------------------------------------------------------------------------

  /// Calcule les itinéraires "safe path" de la position courante vers
  /// [destination] et ouvre [RouteResultSheet] pour laisser l'utilisateur
  /// choisir. Si un trajet est accepté, sa polyline et ses flèches
  /// directionnelles sont affichées via [SafeRouteLayer].
  Future<void> _computeAndShowRoute(
    LatLng destination,
    String destinationLabel, {
    bool isFailover = false,
  }) async {
    final start = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : null;

    if (start == null) {
      _showNoDestinationError();
      return;
    }

    // Indicateur de progression (calcul local, pas de réseau).
    _showRouteSafeProgress(
      isFailover
          ? 'Repli vers $destinationLabel…'
          : 'Calcul de la Route Safe vers $destinationLabel…',
      isFailover: isFailover,
    );

    // Calcul Dijkstra sur grille GPS locale.
    final filters = AvoidanceFilterStore.instance.value;
    final routes = SafePathEngine.computeRoutes(
      start: start,
      end: destination,
      filters: filters,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (routes.isEmpty) {
      _showNoDestinationError();
      return;
    }

    // Ouvre le sélecteur d'itinéraires.
    final selected = await RouteResultSheet.show(context, routes: routes);

    if (!mounted || selected == null) return;

    // Stocke la polyline et anime la carte pour l'afficher.
    setState(() => _safeRoutePoints = selected.points);
    _fitRouteBounds(selected.points);
  }

  /// Centre et zoome la carte pour englober l'itinéraire [points].
  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );
    try {
      _mapController.move(center, 14.0);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(center, 14.0);
        } catch (_) {}
      });
    }
  }

  // --------------------------------------------------------------------------
  // Sélecteur de destination
  // --------------------------------------------------------------------------

  void _openDestinationSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DestinationSelectorSheet(
        events: EventManager.instance.value,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Intelligence collective — Alerte Panic Réseau
  // --------------------------------------------------------------------------

  void _onCollectivePanicAlert(CollectivePanicEvent event) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: StreetPhareTheme.danger, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.emergency, color: StreetPhareTheme.danger, size: 28),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Alerte Panic Collective',
                style: TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '⚠️ ${event.peerCount} appareils proches ont déclenché une '
          'alerte Panic simultanément.\n\n'
          'Un point "Tension importante" a été créé automatiquement '
          'au centre géographique de ces signaux.\n\n'
          'Restez vigilant et consultez la carte.',
          style: const TextStyle(
            color: StreetPhareTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.danger,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              // Recentre la carte sur l'alerte.
              try {
                _mapController.move(event.center, 15.0);
              } catch (_) {}
            },
            child: const Text('Voir sur la carte'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ignorer',
                style: TextStyle(color: StreetPhareTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  void _openReportSheet() => ReportBottomSheet.show(context);

  void _openSettings() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );

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

    // Diffuse le signal panic local sur le maillage P2P.
    if (position != null) {
      unawaited(NetworkCoordinator.instance.broadcastLocalPanic(
        latitude: position.latitude,
        longitude: position.longitude,
      ));
    }

    final message = _buildPanicMessage(position);
    final phones = contacts.map((c) => c.phoneNumber).join(',');
    final uri = Uri(
      scheme: 'sms',
      path: phones,
      queryParameters: {'body': message},
    );

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
  // Couches événements
  // --------------------------------------------------------------------------

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
        polylines.add(Polyline(
          points: allPoints,
          color: color,
          strokeWidth: 4.5,
        ));
      } else {
        final activeStep =
            event.activeStepIndex(now: now, userPos: userLatLng);

        if (activeStep >= event.waypoints.length) {
          polylines.add(Polyline(
            points: allPoints,
            color: color.withValues(alpha: 0.30),
            strokeWidth: 2.5,
          ));
          continue;
        }

        final segmentPoints = event.getSegmentPoints(activeStep, allPoints);
        if (segmentPoints.length >= 2) {
          polylines.add(Polyline(
            points: segmentPoints,
            color: color,
            strokeWidth: 5,
          ));
        }

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

      // Affiche les centres de soins de l'événement.
      for (final cc in event.careCenters) {
        markers.add(Marker(
          point: cc.position,
          width: 36,
          height: 36,
          child: Tooltip(
            message: cc.label,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.medical_services,
                  color: Colors.white, size: 18),
            ),
          ),
        ));
      }

      // Affiche les points de sortie.
      for (final ep in event.exitPoints) {
        markers.add(Marker(
          point: ep.position,
          width: 36,
          height: 36,
          child: Tooltip(
            message: 'Sortie : ${ep.label}',
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.exit_to_app,
                  color: Colors.white, size: 18),
            ),
          ),
        ));
      }

      // Affiche les zones safes.
      for (final sz in event.safeZones) {
        markers.add(Marker(
          point: sz.position,
          width: 40,
          height: 40,
          child: Tooltip(
            message: '🛡 Zone Safe : ${sz.label}',
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.shield,
                  color: Colors.white, size: 20),
            ),
          ),
        ));
      }
    }

    // Marqueur du point utilisateur.
    if (_userPointMarker != null) {
      markers.add(Marker(
        point: _userPointMarker!,
        width: 44,
        height: 44,
        child: const _UserPointMarker(),
      ));
    }

    return _EventLayers(polylines: polylines, markers: markers);
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) {
        final brightness = MediaQuery.platformBrightnessOf(context);
        final isDark = themeMode == AppThemeMode.dark ||
            (themeMode == AppThemeMode.system &&
                brightness == Brightness.dark);
        final tileUrl = isDark ? _kTileUrlDark : _kTileUrlLight;

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
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onLongPress: _onMapLongPress,
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey('tiles_$isDark'),
                        urlTemplate: tileUrl,
                        userAgentPackageName: 'com.streetphare.app',
                        maxNativeZoom: 19,
                      ),
                      if (layers.polylines.isNotEmpty)
                        PolylineLayer(polylines: layers.polylines),
                      // ── Route Safe active (polyline + flèches) ────────
                      if (_safeRoutePoints != null &&
                          _safeRoutePoints!.length >= 2)
                        SafeRouteLayer(routePoints: _safeRoutePoints!),
                      if (hasMarkers)
                        MarkerLayer(
                          markers: [
                            if (_userPosition != null) _buildUserMarker(),
                            ...layers.markers,
                          ],
                        ),
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

                  // ── Chips d'événements (sélection active) ──────────────
                  if (events.isNotEmpty)
                    ValueListenableBuilder<AppPreferences>(
                      valueListenable: AppPreferencesStore.instance,
                      builder: (context, prefs, _) {
                        return Positioned(
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
                                final isActive =
                                    prefs.activeEventIndex == i;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () => AppPreferencesStore.instance
                                        .setActiveEventIndex(i),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? col
                                            : col.withValues(alpha: 0.50),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: isActive
                                            ? Border.all(
                                                color: Colors.white,
                                                width: 2)
                                            : null,
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
                                          if (isActive) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.check_circle,
                                                color: Colors.white,
                                                size: 12),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),

                  // ── Bouton GPS Recentrer + effacer la Route Safe ────────
                  Positioned(
                    left: 16,
                    bottom: 120,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Recentrer sur la position GPS
                        Material(
                          elevation: 4,
                          shape: const CircleBorder(),
                          color: StreetPhareTheme.surface
                              .withValues(alpha: 0.9),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _animateToUser,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(
                                Icons.gps_fixed,
                                color: StreetPhareTheme.primary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        // Effacer la Route Safe active
                        if (_safeRoutePoints != null) ...[
                          const SizedBox(height: 8),
                          Material(
                            elevation: 4,
                            shape: const CircleBorder(),
                            color: StreetPhareTheme.surface
                                .withValues(alpha: 0.9),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () =>
                                  setState(() => _safeRoutePoints = null),
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(
                                  Icons.clear,
                                  color: StreetPhareTheme.danger,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Indicateur de destination actuelle ─────────────────
                  ValueListenableBuilder<AppPreferences>(
                    valueListenable: AppPreferencesStore.instance,
                    builder: (context, prefs, _) {
                      return Positioned(
                        right: 80,
                        bottom: 120,
                        child: GestureDetector(
                          onTap: _openDestinationSelector,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: StreetPhareTheme.surface
                                  .withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: StreetPhareTheme.primary
                                    .withValues(alpha: 0.5),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.my_location,
                                    size: 13,
                                    color: StreetPhareTheme.primary),
                                const SizedBox(width: 5),
                                Text(
                                  prefs.routeDestinationType.label,
                                  style: const TextStyle(
                                    color: StreetPhareTheme.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.expand_less,
                                    size: 14,
                                    color: StreetPhareTheme.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
                          onPressed: () => _triggerRouteSafe(),
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

// ============================================================================
// Sélecteur de destination (bottom sheet)
// ============================================================================

class _DestinationSelectorSheet extends StatelessWidget {
  const _DestinationSelectorSheet({required this.events});
  final List<EventModel> events;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPreferences>(
      valueListenable: AppPreferencesStore.instance,
      builder: (context, prefs, _) {
        return Container(
          decoration: const BoxDecoration(
            color: StreetPhareTheme.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: StreetPhareTheme.textSecondary
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.my_location,
                        color: StreetPhareTheme.primary, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Objectif de la Route Safe',
                      style: TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Appui long 3 s sur la carte → "Point utilisateur"',
                  style: TextStyle(
                    color: StreetPhareTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                RadioGroup<RouteDestinationType>(
                  groupValue: prefs.routeDestinationType,
                  onChanged: (v) {
                    if (v == null) return;
                    AppPreferencesStore.instance.setRouteDestination(v);
                  },
                  child: Column(
                    children: [
                      for (final type in RouteDestinationType.values)
                        RadioListTile<RouteDestinationType>(
                          value: type,
                          title: Text(
                            type.label,
                            style: const TextStyle(
                              color: StreetPhareTheme.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            type.description,
                            style: const TextStyle(
                              color: StreetPhareTheme.textSecondary,
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
                if (events.length > 1) ...[
                  const Divider(height: 20),
                  const Text(
                    'Événement actif',
                    style: TextStyle(
                      color: StreetPhareTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<int>(
                    groupValue: prefs.activeEventIndex,
                    onChanged: (v) {
                      if (v == null) return;
                      AppPreferencesStore.instance.setActiveEventIndex(v);
                    },
                    child: Column(
                      children: [
                        for (int i = 0; i < events.length; i++)
                          RadioListTile<int>(
                            value: i,
                            title: Text(
                              events[i].title,
                              style: TextStyle(
                                color: _kEventColors[i % _kEventColors.length],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            activeColor: _kEventColors[i % _kEventColors.length],
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// Données des layers événements
// ============================================================================

class _EventLayers {
  const _EventLayers({required this.polylines, required this.markers});
  final List<Polyline> polylines;
  final List<Marker> markers;
}

// ============================================================================
// Markers
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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


/// Marqueur du point utilisateur (appui long).
class _UserPointMarker extends StatelessWidget {
  const _UserPointMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF7B1FA2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B1FA2).withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.place, color: Colors.white, size: 22),
    );
  }
}

// ============================================================================
// Widgets UI de l'écran carte
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
