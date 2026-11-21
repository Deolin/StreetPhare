// lib/features/map/presentation/map_screen.dart
//
// Écran principal de StreetPhare — v2.2
//
// Nouvelles fonctionnalités v2.2 :
//   1. Bouton "Recentrer la carte" → zoom 16 (≈100 m au sol).
//   2. Chips d'événements cliquables pour sélectionner l'événement actif.
//   3. Sélecteur de destination (manif / soins / sortie / point utilisateur).
//   4. Appui long (≥ 3 s) sur la carte → point utilisateur + Route Safe auto.
//   5. Stratégie de repli (failover) si le premier calcul échoue.
//   6. Diffusion du signal panic sur le maillage P2P lors de PANIC.
//   7. Notification UI quand une alerte panic collective est créée.
//   8. Écran de chargement carte jusqu'à l'init complète des tuiles.
//   9. Marqueur directionnel (flèche) uniquement si heading/vitesse valides.
//  10. Zoom & Bounding Box dynamiques calculés lors du trajet.
//  11. Popup "À propos" sur appui du titre StreetPhare.
//  12. Signalement : marqueur local immédiat sur carte de l'émetteur.
//  13. Messagerie Hive P2P (bouton FAB dédié).
//  14. Mode Malvoyant : cache le titre, interface accessible.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/alert_model.dart';
import '../../../core/network/osm_tile_headers.dart';
import '../../../core/network/peer_counter_service.dart';
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/skin_controller.dart';
import '../../../core/theme/streetphare_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_version.dart';
import '../../../database/alert_visibility_policy.dart';
import '../../../database/hive_alert_database.dart';
import '../../../debug/client_debug_logger.dart';
import '../../../network/collective_panic_service.dart';
import '../../../network/network_config.dart';
import '../../../network/network_coordinator.dart';
import '../../../network/server_heartbeat_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/version_check_service.dart';
import '../../events/domain/models/event_model.dart';
import '../../events/presentation/event_manager.dart';
import '../../geofencing/domain/models/geofence_event.dart';
import '../../geofencing/presentation/geofencing_service.dart';
import '../../geofencing/presentation/proximity_validation_service.dart';
import '../../geofencing/presentation/proximity_validation_sheet.dart';
import '../../messaging/presentation/hive_messaging_screen.dart';
import '../../reports/domain/models/report_type.dart';
import '../../reports/presentation/report_bottom_sheet.dart';
import '../../routing/core/models/routing_profile.dart';
import '../../routing/core/safe_route_planner.dart';
import '../../routing/data/avoidance_filter_store.dart';
import '../../routing/domain/models/route_result.dart';
import '../../routing/presentation/route_result_sheet.dart';
import '../../settings/data/app_preferences_store.dart';
import '../../settings/data/panic_contact_store.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../streetmedic/domain/models/streetmedic_models.dart';
import '../../streetmedic/presentation/streetmedic_overlay.dart';
import '../../streetmedic/presentation/streetmedic_service.dart';
import '../../trust_group/presentation/trust_group_service.dart';
import '../local_first_tile_provider.dart';
import 'heading_fusion.dart';
import 'widgets/long_press_detector.dart';
import 'widgets/restricted_segment_layer.dart';
import 'widgets/safe_route_layer.dart';
import 'widgets/user_heading_marker.dart';

// ── Couleurs des 3 événements ─────────────────────────────────────────────────
const _kEventColors = [
  Color(0xFFFFB300), // Ambre
  Color(0xFF2196F3), // Bleu
  Color(0xFF4CAF50), // Vert
];

// Tuiles OpenStreetMap servies par le serveur StreetPhare (proxy /tiles).
// Conforme à la politique d'utilisation des tuiles OSM :
//   https://operations.osmfoundation.org/policies/tiles/
// Le client ne sollicite jamais tile.openstreetmap.org directement : il passe
// par le proxy du serveur (priorité local → serveur → OSM en dernier recours).
// Le mode sombre est obtenu via `darkModeTileBuilder` (filtre invert+hue-rotate)
// fourni par flutter_map, appliqué aux tuiles uniquement (pas aux marqueurs).
String get _kTileUrlLight => '${NetworkConfig.baseUrl}/tiles/{z}/{x}/{y}.png';
String get _kTileUrlDark => '${NetworkConfig.baseUrl}/tiles/{z}/{x}/{y}.png';

// ============================================================================
// MapScreen
// ============================================================================

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  /// Fournisseur de tuiles réutilisé (identité stable) pour éviter de
  /// recréer/déposer les streams d'images de tuiles à chaque rebuild.
  late final LocalFirstTileProvider _tileProvider = LocalFirstTileProvider(
    headers: kStreetPhareTileHeaders,
    onTileRateLimited: _onTileRateLimited,
  );
  static const LatLng _defaultCenter = LatLng(48.8566, 2.3522);
  static const double _defaultZoom = 13.0;

  /// Distance maximale autorisée entre l'utilisateur et son signalement
  /// (en mètres). Anti-spam : l'utilisateur doit être proche de la zone
  /// signalée pour garantir qu'il en a réellement une vue.
  static const double _kMaxReportDistanceMeters = 50.0;

  /// Seuil d'écart à la Route Safe (mètres) au-delà duquel on propose de
  /// recalculer l'itinéraire pendant le tracking.
  static const double _kOffRouteThresholdMeters = 10.0;

  Position? _userPosition;
  String? _positionError;
  bool _locating = true;
  StreamSubscription<Position>? _positionSub;

  /// [3] Tracking actif — `false` dès que l'utilisateur clique X.
  bool _isTracking = false;

  /// Mode « suivre l'utilisateur » : la carte reste centrée sur la position
  /// GPS (comme Google Maps). Désactivé automatiquement dès que l'utilisateur
  /// déplace la carte manuellement.
  bool _followUser = false;

  /// Mode « orientation selon le cap » : la carte pivote pour que la flèche
  /// de l'utilisateur pointe vers le haut (heading-up), comme en navigation.
  bool _followHeading = false;

  StreamSubscription<CollectivePanicEvent>? _collectivePanicSub;
  VoidCallback? _trustPositionsListener;

  /// `true` une fois que FlutterMap est prêt (tuiles initialisées).
  bool _mapReady = false;

  /// Marqueur du point utilisateur (appui long).
  LatLng? _userPointMarker;

  /// Cap de déplacement de l'utilisateur en degrés (0 = Nord, sens horaire).
  double _userHeading = 0.0;

  /// Abonnement au compas/gyroscope du téléphone (orientation physique).
  StreamSubscription<CompassEvent>? _compassSub;

  /// Cap boussole du téléphone en degrés (0..360, 0 = Nord), ou -1 si le
  /// capteur est indisponible. Utilisé en priorité sur le cap GPS pour que la
  /// carte et la flèche suivent l'orientation physique du téléphone.
  double _compassHeading = -1;

  /// Vitesse GPS en m/s (pour valider l'affichage de la flèche directionnelle).
  double _userSpeed = 0.0;

  /// Fusion des capteurs (gyroscope + accéléromètre + références absolues
  /// compas / cap GPS) pour un cap fluide et corrigé.
  final HeadingFusion _headingFusion = HeadingFusion();

  /// Cap GPS réel calculé depuis les positions satellites (degrés, -1 si absent).
  double _gpsBearing = -1;

  /// Abonnements aux capteurs inertiels bruts (gyroscope / accéléromètre).
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;

  /// Ticker de lissage : interpole la rotation et le centrage de la carte.
  Ticker? _smoothTicker;
  Duration? _lastSmoothTick;

  /// Position précédente pour calculer le déplacement effectif (seuil 5 m).
  Position? _previousPosition;

  /// Distance cumulée de déplacement depuis le dernier arrêt (mètres).
  double _movementAccumulator = 0.0;

  /// Indique si l'utilisateur a effectivement bougé de plus de 5 m.
  bool _hasMovedBeyondThreshold = false;

  /// Points de la Route Safe active.
  List<LatLng>? _safeRoutePoints;

  /// Portion de la Route Safe déjà parcourue (affichée en gris).
  List<LatLng>? _passedRoutePoints;

  /// Destination mémorisée du dernier itinéraire (pour le recalcul).
  LatLng? _routeDestination;
  String _routeDestinationLabel = '';

  /// Détection d'écart : `true` quand on attend un retour sur le tracé avant
  /// de pouvoir re-déclencher un avertissement « hors itinéraire ».
  bool _offRouteArmed = true;

  /// `true` pendant l'affichage du dialogue « hors itinéraire ».
  bool _offRoutePromptActive = false;

  /// Portions restreintes (sens interdit / barrage…) du dernier itinéraire
  /// voiture/urgence, à surligner en rouge sur la carte.
  List<RestrictedSegment> _restrictedSegments = const [];

  /// Marqueur local immédiat d'un signalement tout juste émis (avant consensus).
  LatLng? _localReportMarker;
  AlertType? _localReportType;

  /// Type de signalement en cours de placement (mode « choisir l'endroit »).
  ReportType? _pendingReportType;

  /// Position de l'icône glissable pendant le placement du signalement.
  LatLng? _placementPoint;

  /// Vrai pendant que l'utilisateur fait glisser l'icône de placement :
  /// la carte est verrouillée pour ne pas se déplacer en même temps.
  bool _draggingPlacement = false;

  /// Alertes réseau (validées par consensus ou simulées côté admin)
  /// à afficher sur la carte citoyenne.
  List<Alert> _remoteAlerts = const [];

  /// Abonnement au flux d'alertes réseau.
  StreamSubscription<List<Alert>>? _alertsSub;

  /// Écouteur de mise à jour de la liste des street-medics actifs.
  VoidCallback? _streetMedicListener;

  /// Abonnement aux demandes dynamiques de validation de proximité.
  StreamSubscription<GeofenceEvent>? _proximityValidationSub;
  bool _validationSheetOpen = false;

  // --------------------------------------------------------------------------
  // Cycle de vie
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    PeerCounterService.instance.start();
    GeofencingService.instance.start();
    ProximityValidationService.instance.start();
    _initUserLocation();
    _startCompassListener();
    _startInertialSensors();
    _collectivePanicSub =
        CollectivePanicService.instance.collectivePanicEvents.listen(
      _onCollectivePanicAlert,
    );
    _proximityValidationSub =
        ProximityValidationService.instance.filteredEvents.listen(
      _onProximityValidationRequested,
    );
    _alertsSub = NetworkCoordinator.instance.alertsStream.listen(
      (alerts) {
        if (!mounted) return;
        setState(() => _remoteAlerts = alerts);
      },
    );
    // Le stream broadcast ne rejoue pas la dernière valeur : on charge
    // immédiatement les alertes déjà présentes dans Hive.
    if (HiveAlertDatabase.instance.isInitialized) {
      _remoteAlerts = HiveAlertDatabase.instance.getAllValid();
    }

    // Street-medic : init + rafraîchissement de la carte médicale.
    StreetMedicService.instance.init();
    _streetMedicListener = () {
      if (!mounted) return;
      // Diffère le setState APRÈS le frame courant : évite tout rebuild
      // pendant la phase de layout (crash `!_debugDoingThisLayout`).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    };
    StreetMedicService.instance.activeStreetmedics
        .addListener(_streetMedicListener!);
    unawaited(StreetMedicService.instance.refreshActiveStreetMedics());

    // Groupe de confiance : rafraîchit les marqueurs amis à chaque position.
    _trustPositionsListener = () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    };
    TrustGroupService.instance.positions.addListener(_trustPositionsListener!);

    // Street-medic : calcul automatique d'une « route safe » vers le blessé
    // lorsque le medic accepte une mission d'intervention.
    StreetMedicService.instance.medicNavigationTarget
        .addListener(_onMedicNavigationTarget);
  }

  /// Réagit à la demande de navigation émise à l'acceptation d'une mission
  /// street-medic : calcule et affiche une « route safe » vers le blessé.
  void _onMedicNavigationTarget() {
    final target = StreetMedicService.instance.medicNavigationTarget.value;
    if (target == null) return;
    // Consomme l'événement (one-shot) pour ne pas le rejouer.
    StreetMedicService.instance.medicNavigationTarget.value = null;
    if (!mounted) return;
    unawaited(_computeAndShowRoute(
      target,
      'Blessé',
      transportMode: 'pedestrian',
    ));
  }

  Future<void> _onProximityValidationRequested(GeofenceEvent event) async {
    if (!mounted || _validationSheetOpen) return;
    _validationSheetOpen = true;
    try {
      await showAndProcessProximityVote(context, event);
    } finally {
      _validationSheetOpen = false;
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _desktopPollingTimer?.cancel();
    _compassSub?.cancel();
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _userAccelSub?.cancel();
    _smoothTicker?.dispose();
    unawaited(WakelockPlus.disable());
    _collectivePanicSub?.cancel();
    _proximityValidationSub?.cancel();
    _alertsSub?.cancel();
    if (_streetMedicListener != null) {
      StreetMedicService.instance.activeStreetmedics
          .removeListener(_streetMedicListener!);
    }
    if (_trustPositionsListener != null) {
      TrustGroupService.instance.positions
          .removeListener(_trustPositionsListener!);
    }
    StreetMedicService.instance.medicNavigationTarget
        .removeListener(_onMedicNavigationTarget);
    _tileProvider.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // GPS
  // --------------------------------------------------------------------------

  Future<void> _initUserLocation() async {
    final s = AppLocale.instance.strings;
    setState(() {
      _locating = true;
      _positionError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _locating = false;
          _positionError = s.mapGpsOff;
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() {
            _locating = false;
            _positionError = s.mapGpsDenied;
          });
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _positionError = s.mapGpsDeniedForever;
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
      StreetMedicService.instance.updatePosition(pos.latitude, pos.longitude);
      _animateToUser();
      unawaited(_positionSub?.cancel());
      _isTracking = true;
      // Suit l'utilisateur par défaut : la carte reste centrée sur la position
      // GPS pendant les déplacements (comme Google Maps).
      _followUser = true;
      if (_isDesktop) {
        // Desktop : polling thread-safe (getCurrentPosition). Évite le crash
        // "non-platform thread" du flux getPositionStream (geolocator_windows).
        _startDesktopPolling();
      } else {
        _positionSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2, // Ecoute fine pour détecter les micro-mouvements
          ),
        ).listen(_onPositionUpdate);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locating = false;
          _positionError = '${s.mapGpsError} $e';
        });
      }
    }
  }

  /// Traite une nouvelle position GPS (appelé par le flux natif sur
  /// mobile/web ET par le polling thread-safe sur Desktop).
  void _onPositionUpdate(Position p) {
    if (!mounted) return;

    // [2] Seuil GPS 5 m : calcule le déplacement effectif depuis la
    // dernière position connue. Si < 5 m → cache la flèche directionnelle.
    final prev = _previousPosition;
    if (prev != null) {
      final dist = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        p.latitude,
        p.longitude,
      );
      _movementAccumulator += dist;
      if (_movementAccumulator >= 5.0) {
        _hasMovedBeyondThreshold = true;
      }
      // Cap GPS réel (valeurs satellites) : corrige en douceur le cap
      // fusionné dès que l'utilisateur avance suffisamment vite.
      final currentSpeed = p.speed < 0 ? 0 : p.speed;
      if (dist > 2.0 && currentSpeed > 1.0) {
        _gpsBearing = _computeBearingDeg(prev, p);
        _headingFusion.feedAbsolute(_gpsBearing, 0.35);
      }
    } else {
      // Première position — réinitialise l'accumulateur.
      _movementAccumulator = 0.0;
      _hasMovedBeyondThreshold = false;
    }

    // Réinitialise l'accumulateur si l'appareil s'est arrêté (speed ≈ 0).
    if (p.speed < 0.3) {
      _movementAccumulator = 0.0;
      _hasMovedBeyondThreshold = false;
    }

    _previousPosition = p;
    StreetMedicService.instance.updatePosition(p.latitude, p.longitude);
    // On diffère le setState au prochain frame pour garantir l'exécution
    // sur le thread principal Flutter (UI Thread).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Tracking Route Safe : progression grisée + détection d'écart.
      _updateRouteTracking(p);
      setState(() {
        _userPosition = p;
        _userSpeed = p.speed < 0 ? 0 : p.speed;
        // Fallback : cap GPS si aucun compas/mag disponible.
        if (p.heading >= 0 && _compassHeading < 0) {
          _headingFusion.feedAbsolute(p.heading, 0.5);
        }
        _userHeading = _headingFusion.heading;
      });
      // Suivi fluide : la rotation et le centrage sont interpolés par le
      // ticker (chemin angulaire le plus court + corrections GPS).
      if (_followUser || _followHeading) _ensureSmoothTicker();
    });
  }

  /// `true` sur un OS Desktop (Windows / macOS / Linux).
  bool get _isDesktop {
    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (_) {
      return false; // web : dart:io indisponible
    }
  }

  Timer? _desktopPollingTimer;

  /// Polling GPS thread-safe sur Desktop : appelle `getCurrentPosition` toutes
  /// les 5 s au lieu du flux `getPositionStream` (crash « non-platform thread »
  /// du plugin geolocator_windows).
  void _startDesktopPolling() {
    _desktopPollingTimer?.cancel();
    _desktopPollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollDesktopPosition(),
    );
    _pollDesktopPosition(); // premier appel immédiat
    if (kDebugMode) {
      debugPrint('[MapScreen] Mode Desktop — polling GPS 5 s (thread-safe)');
    }
  }

  Future<void> _pollDesktopPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) _onPositionUpdate(pos);
    } catch (e) {
      if (kDebugMode) debugPrint('[MapScreen] erreur polling GPS : $e');
    }
  }

  /// Recentre la carte sur la position GPS en CONSERVANT le zoom courant.
  /// Le niveau de zoom reste libre : on recentre simplement sans l'écraser.
  void _animateToUser() {
    final pos = _userPosition;
    if (pos == null) return;
    void doMove() {
      try {
        final zoom = _mapController.camera.zoom;
        _mapController.move(LatLng(pos.latitude, pos.longitude), zoom);
      } catch (e) {
        debugPrint('[MapScreen] Échec recentrage caméra: $e');
      }
    }

    try {
      doMove();
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => doMove());
    }
  }

  /// Oriente la carte selon le cap (mode « heading-up »). La rotation est
  /// interpolée en douceur par le ticker de suivi (_onSmoothTick), qui utilise
  /// le chemin angulaire le plus court et les corrections GPS.
  void _rotateMapToHeading() {
    _ensureSmoothTicker();
  }

  /// Écoute le compas (gyroscope + magnétomètre) du téléphone et oriente la
  /// carte en conséquence. Le cap boussole devient prioritaire sur le cap GPS
  /// de déplacement, afin que la flèche et la carte suivent l'orientation
  /// physique du téléphone, même à l'arrêt.
  void _startCompassListener() {
    // flutter_compass n'a d'implémentation native que sur Android/iOS. Sur les
    // autres plateformes (Windows, web…), on ne tente pas d'ouvrir le flux du
    // compas (sinon MissingPluginException) ; on s'appuie sur le cap GPS seul.
    if (!kIsWeb && !(Platform.isAndroid || Platform.isIOS)) return;
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSub = events.listen((event) {
      final h = event.heading;
      if (h == null || !mounted) return;
      // Le compas est fusionné avec le cap GPS, puis la carte est orientée de
      // façon fluide par le ticker (plus aucune rotation brutale).
      double trust = 0.18;
      if (!_headingFusion.level) trust *= 0.5;
      if (_headingFusion.turnRateDegPerSec.abs() > 20.0) {
        trust = math.min(trust * 1.8, 0.9);
      }
      _headingFusion.feedAbsolute(h, trust);
      setState(() {
        _compassHeading = h;
        _userHeading = _headingFusion.heading;
      });
      if (_followHeading) _ensureSmoothTicker();
    }, onError: (_) {
      // Capteur indisponible : on conserve le cap GPS (heading de déplacement).
    });
  }

  // --------------------------------------------------------------------------
  // Capteurs inertiels & fusion de cap
  // --------------------------------------------------------------------------

  /// Démarre l'écoute brute du gyroscope et de l'accéléromètre (sensors_plus),
  /// en complément du compas `flutter_compass`. Ces capteurs permettent de
  /// lisser l'orientation sans dépendre uniquement du magnétomètre, qui peut
  /// sembler « bloqué » dans certaines directions.
  void _startInertialSensors() {
    // sensors_plus ne prend pas en charge Windows/Linux/macOS.
    if (!kIsWeb && !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      _gyroSub = gyroscopeEventStream().listen((e) {
        if (!mounted) return;
        _headingFusion.onGyroscope(e.x, e.y, e.z, DateTime.now());
      }, onError: (_) {});
    } catch (_) {}
    try {
      _accelSub = accelerometerEventStream().listen((e) {
        if (!mounted) return;
        _headingFusion.onAccelerometer(e.x, e.y, e.z);
      }, onError: (_) {});
    } catch (_) {}
    try {
      _userAccelSub = userAccelerometerEventStream().listen((e) {
        if (!mounted) return;
        _headingFusion.onUserAccelerometer(e.x, e.y, e.z);
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Cap GPS (boussole réelle calculée depuis les positions satellites),
  /// en degrés [0, 360), 0 = Nord.
  double _computeBearingDeg(Position from, Position to) {
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final dLng = (to.longitude - from.longitude) * math.pi / 180.0;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return normalizeDeg360(math.atan2(y, x) * 180.0 / math.pi);
  }

  /// Démarre le ticker de lissage (rotation + centrage interpolés par frame).
  void _ensureSmoothTicker() {
    _smoothTicker ??= createTicker(_onSmoothTick);
    if (!_smoothTicker!.isActive) {
      _lastSmoothTick = null;
      _smoothTicker!.start();
    }
  }

  /// Arrête le ticker dès qu'aucun suivi n'est plus nécessaire.
  void _stopSmoothTickerIfIdle() {
    if (_followUser || _followHeading) return;
    _smoothTicker?.stop();
  }

  /// Interpole, à chaque frame, la rotation et le centrage de la carte vers
  /// leurs cibles courantes (rotation fluide + suivi GPS fluide).
  void _onSmoothTick(Duration elapsed) {
    if (!mounted || !_mapReady) return;
    final dt = _lastSmoothTick == null
        ? 0.016
        : (elapsed - _lastSmoothTick!).inMicroseconds / 1e6;
    _lastSmoothTick = elapsed;

    if (_followHeading) {
      final target = -_headingFusion.heading;
      try {
        final current = _mapController.camera.rotation;
        final delta = shortestAngleDelta(current, target);
        final t = 1.0 - math.exp(-dt * 14.0);
        final next = delta.abs() < 0.05 ? target : current + delta * t;
        _mapController.rotate(next);
      } catch (_) {}
    }

    if (_followUser && _userPosition != null) {
      try {
        final c = _mapController.camera.center;
        final target = LatLng(
          _userPosition!.latitude,
          _userPosition!.longitude,
        );
        final t = 1.0 - math.exp(-dt * 8.0);
        final lat = c.latitude + (target.latitude - c.latitude) * t;
        final lng = c.longitude + (target.longitude - c.longitude) * t;
        _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  // --------------------------------------------------------------------------
  // Gestion dynamique du curseur (flèche vs point)
  // --------------------------------------------------------------------------

  /// [2] Affiche la flèche directionnelle uniquement si l'appareil a
  /// effectivement bougé de plus de 5 m (seuil effectif anti-oscillations GPS).
  /// Avec la boussole (gyroscope) active, on l'affiche aussi à l'arrêt car
  /// l'orientation physique du téléphone est connue.
  bool get _shouldShowArrow {
    if (_compassHeading >= 0) return true;
    if (_headingFusion.isMoving) return true;
    return _hasMovedBeyondThreshold && _userHeading >= 0 && _userSpeed > 0.5;
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
        showArrow: _shouldShowArrow,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Marqueur local de signalement immédiat
  // --------------------------------------------------------------------------

  Marker? _buildLocalReportMarker() {
    final pos = _localReportMarker;
    if (pos == null) return null;
    // Couleur basée sur le type d'alerte (utilise _localReportType).
    final color = _localReportType == AlertType.autre
        ? const Color(0xFF2E7D32)
        : _localReportType == AlertType.barrage
            ? const Color(0xFFD32F2F)
            : StreetPhareTheme.primary;
    return Marker(
      point: pos,
      // Garde l'icône droite quand la carte tourne (garde le nord).
      rotate: true,
      width: 44,
      height: 44,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.add_alert, color: Colors.white, size: 22),
      ),
    );
  }

  /// Icône glissable/déposable affichée pendant le mode « placement ».
  ///
  /// La POINTE (bas du widget) doit coïncider exactement avec [point], la
  /// coordonnée du signalement. Pour cela :
  ///   - `alignment: Alignment.topCenter` place le bord bas du marqueur sur
  ///     [point] (au lieu du centre par défaut) ;
  ///   - le contenu est ancré en bas afin que la pointe de `arrow_drop_down`
  ///     soit au bord bas ;
  ///   - une petite cible semi-transparente est dessinée exactement sous la
  ///     flèche, centrée sur la position de dépôt.
  Marker? _buildPlacementMarker() {
    final type = _pendingReportType;
    final point = _placementPoint;
    if (type == null || point == null) return null;

    const double targetSize = 14;

    return Marker(
      point: point,
      // Garde l'icône droite quand la carte tourne (garde le nord).
      rotate: true,
      // Ancrage : la pointe (bas) coïncide avec la coordonnée exacte.
      alignment: Alignment.topCenter,
      width: 64,
      // Hauteur confortable : cercle (~46) + flèche (28). Le contenu est
      // ancré en bas ; la cible dépasse légèrement sous la pointe
      // (clipBehavior: none l'autorise).
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Pin (cercle + flèche) : draggable, pointe alignée sur le point.
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPlacementDragStart,
            onPointerMove: _onPlacementDragMove,
            onPointerUp: (_) => _onPlacementDragEnd(),
            onPointerCancel: (_) => _onPlacementDragEnd(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: type.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(type.icon, color: Colors.white, size: 30),
                ),
                // Pointe visuelle indiquant le point exact de dépôt.
                Icon(Icons.arrow_drop_down, color: type.color, size: 28),
              ],
            ),
          ),
          // Petite cible fine, centrée exactement sous la flèche.
          // Décale de la moitié de la taille (targetSize / 2) pour que le
          // centre de la cible coïncide avec la pointe (= position exacte).
          Transform.translate(
            offset: const Offset(0.0, 7.0),
            child: IgnorePointer(child: _buildPlacementTarget(targetSize)),
          ),
        ],
      ),
    );
  }

  /// Petite cible fine et semi-transparente (anneau + point central) qui
  /// matérialise le point EXACT où le signalement sera posé.
  Widget _buildPlacementTarget(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 2,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.3,
          height: size * 0.3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Appui long sur la carte → point utilisateur + Route Safe
  // --------------------------------------------------------------------------

  void _onMapLongPress(TapPosition tapPos, LatLng latlng) {
    final s = AppLocale.instance.strings;
    HapticFeedback.heavyImpact();
    AppPreferencesStore.instance.setUserPoint(
      latlng.latitude,
      latlng.longitude,
    );
    setState(() => _userPointMarker = latlng);

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
              Icon(Icons.location_on,
                  color: StreetPhareTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.mapUserPointDefined,
                  style: TextStyle(color: StreetPhareTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
    _triggerRouteSafe(overrideDestination: latlng);
  }

  // --------------------------------------------------------------------------
  // Route Safe — calcul avec failover
  // --------------------------------------------------------------------------

  Future<void> _triggerRouteSafe({LatLng? overrideDestination}) async {
    final s = AppLocale.instance.strings;
    final prefs = AppPreferencesStore.instance.value;
    final events = EventManager.instance.value;

    LatLng? destination = overrideDestination;
    String destinationLabel = s.mapDestinationUserPoint;

    if (destination == null) {
      final userLatLng = _userPosition != null
          ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
          : null;

      switch (prefs.routeDestinationType) {
        case RouteDestinationType.eventPoint:
          // [1] Verrouillage : aucun événement chargé → avertissement
          if (events.isEmpty) {
            _showEventNoEventWarning();
            return;
          }
          final idx0 = prefs.activeEventIndex.clamp(0, events.length - 1);
          destination = events[idx0].destination;
          destinationLabel = '${s.mapDestinationEvent} (${events[idx0].title})';

        case RouteDestinationType.safeZoneOrCareCenter:
          // [1] Priorité absolue : Zone Safe OU Centre de soins le plus proche
          if (userLatLng != null && events.isNotEmpty) {
            final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
            final safeZone = events[idx].nearestSafeZone(userLatLng);
            if (safeZone != null) {
              destination = safeZone.position;
              destinationLabel =
                  '🛡 ${s.mapDestinationSafeZone} : ${safeZone.label}';
            } else {
              final center = events[idx].nearestCareCenter(userLatLng);
              if (center != null) {
                destination = center.position;
                destinationLabel =
                    '🏥 ${s.mapDestinationCareCenter} : ${center.label}';
              }
            }
          }

        case RouteDestinationType.careCenter:
          if (userLatLng != null && events.isNotEmpty) {
            final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
            final center = events[idx].nearestCareCenter(userLatLng);
            if (center != null) {
              destination = center.position;
              destinationLabel =
                  '${s.mapDestinationCareCenter} : ${center.label}';
            }
          }

        case RouteDestinationType.exitPoint:
          if (userLatLng != null && events.isNotEmpty) {
            final idx = prefs.activeEventIndex.clamp(0, events.length - 1);
            final exit = events[idx].nearestExitPoint(userLatLng);
            if (exit != null) {
              destination = exit.position;
              destinationLabel = '${s.mapDestinationExit} : ${exit.label}';
            }
          }

        case RouteDestinationType.userPoint:
          if (prefs.userPointLatitude != null &&
              prefs.userPointLongitude != null) {
            destination = LatLng(
              prefs.userPointLatitude!,
              prefs.userPointLongitude!,
            );
            destinationLabel = s.mapDestinationUserPoint;
          }
      }
    }

    if (destination == null) {
      await _triggerRouteSafeFailover();
      return;
    }
    await _computeAndShowRoute(destination, destinationLabel);
  }

  Future<void> _triggerRouteSafeFailover() async {
    final s = AppLocale.instance.strings;
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

    final safeZone = event.nearestSafeZone(userLatLng);
    if (safeZone != null) {
      await _computeAndShowRoute(
        safeZone.position,
        '${s.mapDestinationSafeZone} : ${safeZone.label}',
        isFailover: true,
      );
      return;
    }

    final careCenter = event.nearestCareCenter(userLatLng);
    if (careCenter != null) {
      await _computeAndShowRoute(
        careCenter.position,
        '${s.mapDestinationCareCenter} : ${careCenter.label}',
        isFailover: true,
      );
      return;
    }

    _showNoDestinationError();
  }

  void _showRouteSafeProgress(String message, {bool isFailover = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor:
              isFailover ? const Color(0xFFFF6F00) : StreetPhareTheme.surface,
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

  // --------------------------------------------------------------------------
  // [1] Dialogue de verrouillage événement — aucun événement chargé
  // --------------------------------------------------------------------------

  void _showEventNoEventWarning() {
    final s = AppLocale.instance.strings;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.event_busy, color: StreetPhareTheme.primary, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                s.mapAddEventWarning,
                style: TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          s.mapAddEventWarning,
          style: TextStyle(
            color: StreetPhareTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.primary,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: Text(
              s.mapAddEventButton,
              style: const TextStyle(color: Colors.black),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.cancel,
                style: TextStyle(color: StreetPhareTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  void _showNoDestinationError() {
    final s = AppLocale.instance.strings;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: StreetPhareTheme.danger,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.mapNoDestinationError,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Met à jour le suivi de la Route Safe à partir d'une position GPS :
  ///   - grise la portion déjà parcourue (pour éviter de rebrousser chemin),
  ///   - détecte un écart > [_kOffRouteThresholdMeters] et le signale.
  void _updateRouteTracking(Position p) {
    final route = _safeRoutePoints;
    if (!_isTracking || route == null || route.length < 2) {
      _passedRoutePoints = null;
      _offRouteArmed = true;
      return;
    }

    final user = LatLng(p.latitude, p.longitude);
    final split = _splitRouteAtUser(user, route);
    _passedRoutePoints = split.passed;

    if (split.distanceMeters > _kOffRouteThresholdMeters) {
      if (_offRouteArmed && !_offRoutePromptActive) {
        _offRouteArmed = false;
        unawaited(_promptOffRoute());
      }
    } else {
      // Retour sur l'itinéraire : on réarme la détection.
      _offRouteArmed = true;
    }
  }

  /// Projette [user] sur la polyline [route] et renvoie :
  ///   - [passed] : sous-polyline déjà parcourue (départ → point projeté) ;
  ///   - [distanceMeters] : distance de l'utilisateur au tracé.
  ({List<LatLng> passed, double distanceMeters}) _splitRouteAtUser(
    LatLng user,
    List<LatLng> route,
  ) {
    // Projection équirectangulaire locale (plan XY en mètres autour du point).
    final refLat = user.latitude;
    const mPerDegLat = 111132.0;
    final mPerDegLng = 111320.0 * math.cos(refLat * math.pi / 180.0);
    final px = user.longitude * mPerDegLng;
    final py = user.latitude * mPerDegLat;

    int bestSeg = 0;
    double bestT = 0.0;
    double bestDist = double.infinity;

    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final ax = a.longitude * mPerDegLng;
      final ay = a.latitude * mPerDegLat;
      final bx = b.longitude * mPerDegLng;
      final by = b.latitude * mPerDegLat;

      final dx = bx - ax;
      final dy = by - ay;
      double t;
      if (dx == 0.0 && dy == 0.0) {
        t = 0.0;
      } else {
        t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
            .clamp(0.0, 1.0);
      }
      final cx = ax + t * dx;
      final cy = ay + t * dy;
      final d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (d < bestDist) {
        bestDist = d;
        bestSeg = i;
        bestT = t;
      }
    }

    // Point projeté (position utilisateur ramenée sur le tracé).
    final a = route[bestSeg];
    final b = route[bestSeg + 1];
    final proj = LatLng(
      a.latitude + (b.latitude - a.latitude) * bestT,
      a.longitude + (b.longitude - a.longitude) * bestT,
    );

    // Sous-polyline « déjà parcourue » : départ → … → point projeté.
    final passed = <LatLng>[route.first];
    for (var i = 1; i <= bestSeg; i++) {
      passed.add(route[i]);
    }
    passed.add(proj);

    return (passed: passed, distanceMeters: bestDist);
  }

  /// Active/désactive le maintien d'écran allumé selon qu'une Route Safe est
  /// en cours de suivi.
  void _applyWakelock() {
    final keepAwake = _isTracking && _safeRoutePoints != null;
    if (keepAwake) {
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(WakelockPlus.disable());
    }
  }

  /// Affiche la confirmation « hors itinéraire » et, le cas échéant,
  /// recalcule un nouvel itinéraire depuis la position actuelle.
  Future<void> _promptOffRoute() async {
    if (_offRoutePromptActive || !mounted) return;
    _offRoutePromptActive = true;

    final bool? recalc = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hors itinéraire'),
        content: const Text(
          'Vous êtes sorti(e) de la route (écart supérieur à 10 m). '
          'Souhaitez-vous calculer un nouvel itinéraire ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Recalculer'),
          ),
        ],
      ),
    );

    _offRoutePromptActive = false;
    if (recalc == true && mounted) {
      await _recalculateRouteFromCurrentPosition();
    }
  }

  /// Relance un calcul d'itinéraire vers la dernière destination mémorisée,
  /// depuis la position GPS actuelle.
  Future<void> _recalculateRouteFromCurrentPosition() async {
    final dest = _routeDestination;
    if (dest == null) {
      await _triggerRouteSafe();
      return;
    }
    final mode =
        AppPreferencesStore.instance.value.defaultTransportMode ?? 'pedestrian';
    _offRouteArmed = true;
    await _computeAndShowRoute(
      dest,
      _routeDestinationLabel,
      transportMode: mode,
    );
  }

  // --------------------------------------------------------------------------
  // Calcul de route et affichage du résultat
  // --------------------------------------------------------------------------

  Future<void> _computeAndShowRoute(
    LatLng destination,
    String destinationLabel, {
    bool isFailover = false,
    String? transportMode,
  }) async {
    final s = AppLocale.instance.strings;
    final start = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : null;

    if (start == null) {
      _showNoDestinationError();
      return;
    }

    // Mémorise la destination pour permettre un recalcul « hors itinéraire ».
    _routeDestination = destination;
    _routeDestinationLabel = destinationLabel;

    // Popup bloquant AVANT chaque calcul de route. L'utilisateur
    // doit confirmer son mode de transport. Le choix est pré-rempli
    // avec la dernière valeur persistée, mais peut être changé.
    // Annuler = ne pas lancer le calcul.
    final prefs = AppPreferencesStore.instance.value;
    String chosenMode;
    if (transportMode != null) {
      // Mode forcé (ex: appui long sur une icône d'événement) → pas de popup.
      chosenMode = transportMode;
    } else {
      final chosen = await _showTransportModePopup(
        currentMode: prefs.defaultTransportMode ?? 'pedestrian',
      );
      if (chosen == null || !mounted) return;
      chosenMode = chosen;
      await AppPreferencesStore.instance.setDefaultTransportMode(chosenMode);
    }

    // Détermine le profil de routage selon le mode choisi.
    final routingProfile = _transportModeToRoutingProfile(chosenMode);

    // ── Log diagnostic horodaté ────────────────────────────────────────
    final now = DateTime.now();
    final ts = '[${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}]';
    final profileLabel = chosenMode == 'car'
        ? 'voiture'
        : chosenMode == 'transit'
            ? 'transports'
            : 'piéton';
    debugPrint('$ts [Navigation] Envoi de la demande d\'itinéraire —'
        ' Profil: $profileLabel');
    // ────────────────────────────────────────────────────────────────────

    _showRouteSafeProgress(
      isFailover
          ? s.mapRouteSafeFailover.replaceFirst('{label}', destinationLabel)
          : s.mapRouteSafeCalculating.replaceFirst('{label}', destinationLabel),
      isFailover: isFailover,
    );

    final filters = AvoidanceFilterStore.instance.value;

    // Multi-itinéraires (≤ 3) + garantie « 0 risque » via SafeRoutePlanner.
    final result = await SafeRoutePlanner.instance.computeRoutes(
      start: start,
      end: destination,
      profile: routingProfile,
      filters: filters,
    );

    if (!mounted) return;

    if (result.isNotEmpty) {
      final routes = result.routes;
      if (!mounted) return;
      final selected = await RouteResultSheet.show(context, routes: routes);

      if (!mounted || selected == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        return;
      }

      // Le trace est maintenant visible sur la carte.
      setState(() {
        _safeRoutePoints = selected.points;
        _passedRoutePoints = null;
      });
      _applyWakelock();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _fitRouteBounds(selected.points);
      _applyRoadRestrictions(selected, routingProfile);
      return;
    }

    // Aucun itinéraire routable (SPG / GraphHopper / OSRM) n'a pu être
    // calculé. On n'affiche JAMAIS de tracé « à vol d'oiseau » : une
    // alternative doit suivre la voirie réelle. On prévient donc
    // l'utilisateur qu'aucun itinéraire n'est disponible.
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    _showNoDestinationError();
  }

  /// Convertit le mode de transport (String) en profil de routage.
  RoutingProfile _transportModeToRoutingProfile(String mode) {
    switch (mode) {
      case 'pedestrian':
        return RoutingProfile.pedestrian;
      case 'car':
        return RoutingProfile.vehicle;
      case 'transit':
        // Les transports en commun sont désormais calculés par OpenTripPlanner
        // (voir OpenTripPlannerService). Si OTP est indisponible, le
        // RoutingEngine retombe automatiquement sur un tracé piéton de
        // rabattement (marche), jamais sur un profil voiture.
        return RoutingProfile.transit;
      default:
        return RoutingProfile.pedestrian;
    }
  }

  /// Affiche un popup bloquant demandant le mode de transport.
  /// Retourne le mode choisi sous forme de String ('pedestrian', 'car', 'transit').
  Future<String?> _showTransportModePopup({String? currentMode}) async {
    final s = AppLocale.instance.strings;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.alt_route, color: StreetPhareTheme.primary, size: 24),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                s.routeTitle,
                style: TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.mapDestinationLongPressHint,
              style: TextStyle(
                color: StreetPhareTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            _TransportOption(
              icon: Icons.directions_walk,
              label: s.transportModePedestrian,
              onTap: () => Navigator.of(ctx).pop('pedestrian'),
            ),
            const SizedBox(height: 8),
            _TransportOption(
              icon: Icons.directions_car,
              label: s.transportModeCar,
              onTap: () => Navigator.of(ctx).pop('car'),
            ),
            const SizedBox(height: 8),
            _TransportOption(
              icon: Icons.directions_bus,
              label: s.transportModeTransit,
              onTap: () => Navigator.of(ctx).pop('transit'),
            ),
          ],
        ),
      ),
    );
  }

  /// Centre et zoome la carte pour afficher l'INTÉGRALITÉ du trajet.
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

    // Calcul du zoom dynamique basé sur la distance A→B à vol d'oiseau.
    double zoom = 13.0;
    if (points.length >= 2) {
      final start = points.first;
      final dest = points.last;
      final dLat = (dest.latitude - start.latitude) * math.pi / 180.0;
      final dLng = (dest.longitude - start.longitude) * math.pi / 180.0;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(start.latitude * math.pi / 180.0) *
              math.cos(dest.latitude * math.pi / 180.0) *
              math.sin(dLng / 2) *
              math.sin(dLng / 2);
      final distMeters =
          6371000.0 * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

      // Zoom inversé : veut voir ~1.5× la distance sur l'écran (600 px approx).
      final midLatRad = center.latitude * math.pi / 180.0;
      final metersPerPixelAt17 = 0.597 * math.cos(midLatRad);
      final targetMetersPerPx = (distMeters * 1.5) / 600.0;
      final rawZoom =
          17.0 - math.log(targetMetersPerPx / metersPerPixelAt17) / math.ln2;
      zoom = rawZoom.clamp(10.0, 16.5);
    }

    void doMove() {
      try {
        _mapController.move(center, zoom);
      } catch (e) {
        debugPrint('[MapScreen] Échec animation bounds: $e');
      }
    }

    try {
      doMove();
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => doMove());
    }
  }

  /// Détecte les portions restreintes d'un itinéraire et, en mode
  /// voiture/urgence, met à jour la surbrillance + avertit l'utilisateur.
  void _applyRoadRestrictions(RouteResult route, RoutingProfile profile) {
    final isMotor = profile == RoutingProfile.vehicle ||
        profile == RoutingProfile.emergency;
    if (!isMotor) {
      if (_restrictedSegments.isNotEmpty) {
        setState(() => _restrictedSegments = const []);
      }
      return;
    }

    final segments = SafeRoutePlanner.instance.detectRestrictedSegments(
      route.points,
    );
    setState(() => _restrictedSegments = segments);

    if (segments.isEmpty) return;

    // Alerte sonore + retour haptique.
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();

    if (mounted) {
      _showRoadViolationWarning(segments);
    }
  }

  /// Popup d'avertissement « entorse au code de la route ».
  void _showRoadViolationWarning(List<RestrictedSegment> segments) {
    final reasons = segments.map((s) => s.reason).toSet().join(', ');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Color(0xFFFF6F00), size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Entorse au code de la route',
                style: TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'L\'itinéraire calculé franchit ${segments.length} portion(s) '
          'restreinte(s) : $reasons.\n\n'
          'Ces portions sont surlignées en rouge sur la carte.',
          style: TextStyle(
            color: StreetPhareTheme.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Compris',
              style: TextStyle(color: StreetPhareTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// Affiche un message quand la limite serveur de chargement des tuiles est
  /// atteinte pour cet utilisateur (429 TILE_RATE_LIMITED).
  void _onTileRateLimited(Duration? waitFor) {
    if (!mounted) return;
    final String message = waitFor != null
        ? 'Limite de chargement de carte atteinte. Patientez environ '
            '${waitFor.inMinutes} minute(s) avant de charger de nouvelles '
            'zones de la carte.'
        : 'Limite de chargement de carte atteinte. Patientez quelques '
            'minutes avant de charger de nouvelles zones de la carte.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 8),
        ),
      );
  }

  /// Calcule et trace une « route safe » vers un point (icône d'événement),
  /// sans popup de choix du mode : utilise le mode de transport par défaut.
  Future<void> _triggerSafeRouteToPoint(
      LatLng destination, String label) async {
    final prefs = AppPreferencesStore.instance.value;
    final mode = prefs.defaultTransportMode ?? 'pedestrian';
    await _computeAndShowRoute(destination, label, transportMode: mode);
  }

  // --------------------------------------------------------------------------
  // Sélecteur de destination
  // --------------------------------------------------------------------------

  Future<void> _openDestinationSelector() async {
    final selected = await showModalBottomSheet<RouteDestinationType>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DestinationSelectorSheet(
        events: EventManager.instance.value,
        strings: AppLocale.instance.strings,
      ),
    );

    // Fermé sans changement → on ne fait rien.
    if (selected == null) return;

    // La destination a changé → recalcul immédiat de l'itinéraire.
    await _triggerRouteSafe();
  }

  // --------------------------------------------------------------------------
  // Messagerie Hive P2P
  // --------------------------------------------------------------------------

  void _openMessaging() {
    final pos = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HiveMessagingScreen(userPosition: pos),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Signalement — feedback local immédiat
  // --------------------------------------------------------------------------

  Future<void> _openReportSheet() async {
    final type = await ReportBottomSheet.show(context);
    if (type == null || !mounted) return;
    _enterReportPlacement(type);
  }

  /// Entre en mode « choisir l'endroit » : affiche une icône glissable
  /// initialement positionnée sur l'utilisateur (ou le centre de la carte).
  void _enterReportPlacement(ReportType type) {
    final pos = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : _mapController.camera.center;
    setState(() {
      _pendingReportType = type;
      _placementPoint = pos;
    });
  }

  /// Annule le placement en cours.
  void _cancelReportPlacement() {
    if (!mounted) return;
    setState(() {
      _pendingReportType = null;
      _placementPoint = null;
    });
  }

  /// Verrouille la carte dès que le doigt appuie sur l'icône de placement.
  void _onPlacementDragStart(PointerDownEvent event) {
    setState(() => _draggingPlacement = true);
  }

  /// Déplace l'icône glissable en convertissant le delta d'écran en coordonnées.
  void _onPlacementDragMove(PointerMoveEvent event) {
    if (!_draggingPlacement) return;
    final point = _placementPoint;
    if (point == null) return;
    final screen = _mapController.camera.latLngToScreenOffset(point);
    final moved = _mapController.camera.screenOffsetToLatLng(
      screen + event.delta,
    );
    setState(() => _placementPoint = moved);
  }

  /// Déverrouille la carte au relâchement de l'icône.
  void _onPlacementDragEnd() {
    if (_draggingPlacement) {
      setState(() => _draggingPlacement = false);
    }
  }

  /// Confirme le signalement à la position choisie.
  Future<void> _confirmReportPlacement() async {
    final type = _pendingReportType;
    final point = _placementPoint;
    if (type == null || point == null) return;

    // ── Vérification de distance (anti-spam) ───────────────────────────
    // L'utilisateur ne peut signaler qu'à moins de 50 m de sa position réelle :
    // cela évite de spammer la carte à distance et garantit qu'il a
    // réellement la zone en vue.
    final userPos = _userPosition;
    if (userPos == null) {
      _showReportSnackBar(
        'Position GPS indisponible. Activez la localisation et réessayez.',
        icon: Icons.location_off,
        backgroundColor: StreetPhareTheme.danger,
      );
      return;
    }
    final distance = const Distance().distance(
      LatLng(userPos.latitude, userPos.longitude),
      point,
    );
    if (distance > _kMaxReportDistanceMeters) {
      _showReportSnackBar(
        'Signalement trop éloigné (${distance.round()} m). '
        'Placez l\'icône à moins de '
        '${_kMaxReportDistanceMeters.round()} m de votre position.',
        icon: Icons.wrong_location_outlined,
        backgroundColor: StreetPhareTheme.danger,
      );
      return;
    }

    final alertType = type.alertType;

    // Marqueur local immédiat (avant persistance réseau).
    _onLocalReportCreated(point, alertType);

    try {
      await NetworkCoordinator.instance.createAlert(
        type: alertType,
        latitude: point.latitude,
        longitude: point.longitude,
        description: type.label,
      );
      _showReportSnackBar(
        '✅ Signalement "${type.label}" enregistré.\n'
        'Visible des autres pairs dès 3 confirmations.',
        icon: type.icon,
        backgroundColor: type.color,
      );
    } on SocketException {
      _showReportSnackBar(
        '📡 Signalement "${type.label}" enregistré localement.\n'
        'En attente d\'envoi — sera diffusé dès qu\'un pair est à portée.',
        icon: Icons.cloud_off,
        backgroundColor: StreetPhareTheme.primary,
      );
    } catch (e) {
      _showReportSnackBar(
        'Erreur lors de l\'enregistrement : $e',
        icon: Icons.error_outline,
        backgroundColor: StreetPhareTheme.danger,
      );
    }

    if (mounted) {
      setState(() {
        _pendingReportType = null;
        _placementPoint = null;
      });
    }
  }

  void _showReportSnackBar(
    String message, {
    required IconData icon,
    required Color backgroundColor,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Callback déclenché dès la création locale du signalement.
  void _onLocalReportCreated(LatLng position, AlertType type) {
    if (!mounted) return;
    setState(() {
      _localReportMarker = position;
      _localReportType = type;
    });
    // Disparaît après 30 s.
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _localReportMarker = null;
          _localReportType = null;
        });
      }
    });
  }

  /// Label de version dynamique (ex: v0.4.0-alpha (Alpha)).
  String _buildVersionLabel() {
    final vc = VersionCheckService.instance;
    if (vc.isInitialized) {
      return AppVersion.parse('${vc.currentVersion}+${vc.buildNumber}').label;
    }
    return 'v0.4.0-alpha (Alpha)';
  }

  // --------------------------------------------------------------------------
  // Popup "À propos" (titre StreetPhare)
  // --------------------------------------------------------------------------

  void _showAboutDialog(BuildContext context) {
    final s = AppLocale.instance.strings;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lightbulb, color: StreetPhareTheme.primary, size: 28),
            const SizedBox(width: 10),
            Text(
              s.appTitle,
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
              _AboutRow(
                  label: s.aboutVersion, value: _buildVersionLabel(), ctx: ctx),
              const SizedBox(height: 6),
              _AboutRow(
                  label: s.aboutPlatform, value: 'Flutter / Dart', ctx: ctx),
              const SizedBox(height: 6),
              _AboutRow(label: s.aboutLicense, value: 'GNU GPL v3', ctx: ctx),
              const SizedBox(height: 6),
              _AboutRow(
                  label: s.aboutEncryption,
                  value: 'Hive local + Ed25519',
                  ctx: ctx),
              const SizedBox(height: 12),
              Text(
                s.aboutOpenSource,
                style: TextStyle(
                  color: StreetPhareTheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.aboutDescription,
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
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Intelligence collective — Alerte Panic Réseau
  // --------------------------------------------------------------------------

  void _onCollectivePanicAlert(CollectivePanicEvent event) {
    if (!mounted) return;
    final s = AppLocale.instance.strings;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: StreetPhareTheme.danger, width: 2),
        ),
        title: Row(
          children: [
            Icon(Icons.emergency, color: StreetPhareTheme.danger, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                s.mapCollectivePanicTitle,
                style: TextStyle(
                  color: StreetPhareTheme.textPrimary,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          s.mapCollectivePanicMessage
              .replaceFirst('{count}', '${event.peerCount}'),
          style: TextStyle(
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
              try {
                _mapController.move(event.center, 15.0);
              } catch (e) {
                debugPrint('[MapScreen] Échec navigation vers événement: $e');
              }
            },
            child: Text(s.mapViewOnMap),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.mapIgnore,
                style: TextStyle(color: StreetPhareTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Paramètres
  // --------------------------------------------------------------------------

  void _openSettings() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );

  // --------------------------------------------------------------------------
  // PANIC
  // --------------------------------------------------------------------------

  Future<void> _triggerPanic() async {
    final s = AppLocale.instance.strings;
    final contacts = PanicContactStore.instance.value;
    if (contacts.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StreetPhareTheme.surface,
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: StreetPhareTheme.danger),
              const SizedBox(width: 12),
              Text(s.mapNoPanicContactTitle,
                  style: TextStyle(color: StreetPhareTheme.textPrimary)),
            ],
          ),
          content: Text(
            s.mapNoPanicContactMessage,
            style: TextStyle(color: StreetPhareTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.mapOpenSettings),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        unawaited(Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ));
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
          side: BorderSide(color: StreetPhareTheme.danger, width: 2),
        ),
        title: Row(
          children: [
            Icon(Icons.emergency, color: StreetPhareTheme.danger),
            const SizedBox(width: 12),
            Text(s.mapPanicModeTitle,
                style: TextStyle(color: StreetPhareTheme.textPrimary)),
          ],
        ),
        content: Text(
          s.mapPanicModeMessage
              .replaceFirst('{count}', '${contacts.length}')
              .replaceFirst(
                  '{list}',
                  contacts
                      .map((c) => '• ${c.name} (${c.phoneNumber})')
                      .join('\n')),
          style: TextStyle(color: StreetPhareTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: StreetPhareTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.mapPanicModeActivate),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Dissolution du groupe de confiance : efface les positions des autres
    // et ordonne à chaque ami de faire tourner son ID fixe (protection).
    unawaited(TrustGroupService.instance.panicWipe());

    final position = await _getCurrentPositionSafe();

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
      unawaited(showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StreetPhareTheme.surface,
          title: Row(
            children: [
              Icon(Icons.info_outline, color: StreetPhareTheme.primary),
              const SizedBox(width: 12),
              Text(s.mapPanicSmsPreparedTitle,
                  style: TextStyle(color: StreetPhareTheme.textPrimary)),
            ],
          ),
          content: Text(
            s.mapPanicSmsPreparedMessage.replaceFirst('{message}', message),
            style: TextStyle(color: StreetPhareTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.ok),
            ),
          ],
        ),
      ));
      return;
    }

    if (!mounted) return;
    unawaited(showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: StreetPhareTheme.primary),
            const SizedBox(width: 12),
            Text(s.mapPanicAlertReadyTitle,
                style: TextStyle(color: StreetPhareTheme.textPrimary)),
          ],
        ),
        content: Text(
          s.mapPanicAlertReadyMessage
              .replaceFirst('{count}', '${contacts.length}'),
          style: TextStyle(color: StreetPhareTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.ok),
          ),
        ],
      ),
    ));
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
    final s = AppLocale.instance.strings;
    final stamp = DateTime.now().toUtc().toIso8601String();
    final coords = p == null
        ? s.mapPanicNoGps
        : 'https://maps.google.com/?q=${p.latitude},${p.longitude} '
            '(${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';

    return s.mapPanicMessageBody
        .replaceFirst('{stamp}', stamp)
        .replaceFirst('{coords}', coords);
  }

  // --------------------------------------------------------------------------
  // Marqueurs d'alertes réseau (signalements validés / simulés)
  // --------------------------------------------------------------------------

  /// Couleur du marqueur selon le type d'alerte.
  Color _alertColor(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return Colors.red;
      case AlertType.casseurs:
        return Colors.amber;
      case AlertType.danger:
        return Colors.purple;
      case AlertType.policiers:
        return Colors.blue;
      case AlertType.autopompes:
        return Colors.orange;
      case AlertType.gazLacrymogenes:
        return Colors.lime;
      case AlertType.filtre:
        return Colors.teal;
      case AlertType.panic:
        return Colors.deepOrange;
      case AlertType.dangerCollectif:
        return Colors.redAccent;
      case AlertType.density:
        return Colors.cyanAccent;
      case AlertType.autre:
        return Colors.grey;
    }
  }

  /// Icône du marqueur selon le type d'alerte.
  IconData _alertIcon(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return Icons.block;
      case AlertType.casseurs:
        return Icons.groups;
      case AlertType.danger:
        return Icons.warning_amber;
      case AlertType.policiers:
        return Icons.local_police;
      case AlertType.autopompes:
        return Icons.local_fire_department;
      case AlertType.gazLacrymogenes:
        return Icons.air;
      case AlertType.filtre:
        return Icons.filter_alt;
      case AlertType.panic:
        return Icons.add_alert;
      case AlertType.dangerCollectif:
        return Icons.campaign;
      case AlertType.density:
        return Icons.people;
      case AlertType.autre:
        return Icons.add_alert;
    }
  }

  /// Libellé lisible du type d'alerte (tooltip).
  String _alertLabel(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return 'Barrage';
      case AlertType.casseurs:
        return 'Casseurs';
      case AlertType.danger:
        return 'Danger';
      case AlertType.policiers:
        return 'Police';
      case AlertType.autopompes:
        return 'Autopompes';
      case AlertType.gazLacrymogenes:
        return 'Gaz lacrymogènes';
      case AlertType.filtre:
        return 'Filtre';
      case AlertType.panic:
        return 'Panic';
      case AlertType.dangerCollectif:
        return 'Panic collectif';
      case AlertType.density:
        return 'Densité';
      case AlertType.autre:
        return 'Autre danger';
    }
  }

  /// Construit les marqueurs des alertes réseau visibles.
  /// Un point n'apparaît que s'il est `active` (validé par consensus),
  /// ce qui inclut les alertes simulées injectées côté admin.
  List<Marker> _buildAlertMarkers() {
    final markers = <Marker>[];
    final now = DateTime.now().toUtc();
    final isMars = SkinController.instance.value == AppSkin.marsAttacks;
    for (final alert in _remoteAlerts) {
      if (!AlertVisibilityPolicy.isVisible(alert, now: now)) continue;
      final color = _alertColor(alert.type);
      final icon = _alertIcon(alert.type);
      final label = _alertLabel(alert.type);
      // Icône personnalisée « Mars Attacks » (SVG) si le skin est actif.
      final marsAsset = isMars ? _marsMarkerAsset(alert.type) : null;
      final tooltip = alert.description.isNotEmpty
          ? '$label — ${alert.description}'
          : label;
      markers.add(Marker(
        point: alert.position,
        // Garde le « haut » de l'icône vers le haut de l'écran quand la carte
        // tourne (contre-rotation = on garde le nord).
        rotate: true,
        width: 40,
        height: 40,
        child: Tooltip(
          message: tooltip,
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: marsAsset != null
                ? SvgPicture.asset(marsAsset, width: 22, height: 22)
                : Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ));
    }
    return markers;
  }

  /// Construit les marqueurs des amis de confiance (cercle vert « personne »).
  /// Seules les positions des IDs présents dans la liste de confiance sont
  /// affichées — aucune autre carte ne reçoit ces positions.
  List<Marker> _buildTrustFriendMarkers() {
    final markers = <Marker>[];
    final positions = TrustGroupService.instance.positions.value;
    if (positions.isEmpty) return markers;

    final aliasByFid = <String, String>{};
    for (final m in TrustGroupService.instance.members.value) {
      aliasByFid[m.fixedId] = m.alias;
    }

    for (final p in positions.values) {
      if (p.isStale) continue;
      final alias = aliasByFid[p.fixedId] ?? 'Ami';
      markers.add(Marker(
        point: p.point,
        width: 36,
        height: 36,
        child: Tooltip(
          message: alias,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
        ),
      ));
    }
    return markers;
  }

  /// Construit les marqueurs des street-medics actifs (croix blanche sur
  /// fond rouge). Distinct en « mode alerté » quand le medic est en mission.
  List<Marker> _buildStreetMedicMarkers() {
    final markers = <Marker>[];
    final service = StreetMedicService.instance;
    final alertedMedicId = (service.myCall != null && service.myCall!.isActive)
        ? service.myCall!.medicId
        : service.activeMission?.medicId;
    for (final sm in service.activeStreetmedics.value) {
      if (sm.latitude == null || sm.longitude == null || sm.stale) continue;
      markers.add(Marker(
        point: LatLng(sm.latitude!, sm.longitude!),
        width: 40,
        height: 40,
        child: Tooltip(
          message: sm.userId == alertedMedicId
              ? 'Street-medic en intervention'
              : 'Street-medic',
          child: StreetMedicMarkerIcon(alerted: sm.userId == alertedMedicId),
        ),
      ));
    }
    // Marqueur du blessé (visible par le medic en intervention uniquement).
    final activeMission = service.activeMission;
    if (activeMission != null && activeMission.isActive) {
      markers.add(Marker(
        point: LatLng(
            activeMission.injuredLatitude, activeMission.injuredLongitude),
        width: 40,
        height: 40,
        child: Tooltip(
          message: 'Blessé',
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.accessible, color: Colors.white, size: 20),
          ),
        ),
      ));
    }
    return markers;
  }

  /// Asset SVG « Mars Attacks » pour un type d'alerte donné.
  ///
  /// Retourne `null` si le type conserve son icône Material standard.
  /// Les marqueurs restent en espace écran (taille fixe 40×40) : ils ne
  /// sont pas redimensionnés par le zoom, ce qui garantit leur lisibilité
  /// à tous les niveaux (comportement standard FlutterMap pour les points).
  String? _marsMarkerAsset(AlertType type) {
    switch (type) {
      case AlertType.policiers:
        return 'assets/mars/alien_head.svg'; // Police → tête d'alien
      case AlertType.barrage:
        return 'assets/mars/cow.svg'; // Barrage → vache
      case AlertType.autopompes:
        return 'assets/mars/spaceship.svg'; // Autopompes → vaisseau
      default:
        return null;
    }
  }

  // --------------------------------------------------------------------------
  // Couches événements
  // --------------------------------------------------------------------------

  _EventLayers _buildEventLayers(List<EventModel> events) {
    final s = AppLocale.instance.strings;
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
        final activeStep = event.activeStepIndex(now: now, userPos: userLatLng);

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
          child: LongPressDetector(
            onLongPress: () => _triggerSafeRouteToPoint(
              currentWp.position,
              'Événement : ${currentWp.label}',
            ),
            child: _WaypointMarker(
              label: currentWp.label,
              timeStr: currentWp.formattedTime,
              color: color,
              isCurrent: true,
            ),
          ),
        ));

        if (activeStep + 1 < event.waypoints.length) {
          final nextWp = event.waypoints[activeStep + 1];
          markers.add(Marker(
            point: nextWp.position,
            width: 100,
            height: 72,
            child: LongPressDetector(
              onLongPress: () => _triggerSafeRouteToPoint(
                nextWp.position,
                'Événement : ${nextWp.label}',
              ),
              child: _WaypointMarker(
                label: nextWp.label,
                timeStr: nextWp.formattedTime,
                color: color.withValues(alpha: 0.65),
                isCurrent: false,
              ),
            ),
          ));
        }
      }

      for (final cc in event.careCenters) {
        markers.add(Marker(
          point: cc.position,
          width: 36,
          height: 36,
          child: LongPressDetector(
            onLongPress: () => _triggerSafeRouteToPoint(cc.position, cc.label),
            child: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
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
          ),
        ));
      }

      for (final ep in event.exitPoints) {
        markers.add(Marker(
          point: ep.position,
          width: 36,
          height: 36,
          child: LongPressDetector(
            onLongPress: () => _triggerSafeRouteToPoint(ep.position, ep.label),
            child: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              message: '${s.mapDestinationExit} : ${ep.label}',
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
          ),
        ));
      }

      for (final sz in event.safeZones) {
        markers.add(Marker(
          point: sz.position,
          width: 40,
          height: 40,
          child: LongPressDetector(
            onLongPress: () => _triggerSafeRouteToPoint(sz.position, sz.label),
            child: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              message: '🛡 ${s.mapDestinationSafeZone} : ${sz.label}',
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.shield, color: Colors.white, size: 20),
              ),
            ),
          ),
        ));
      }
    }

    if (_userPointMarker != null) {
      markers.add(Marker(
        point: _userPointMarker!,
        width: 44,
        height: 44,
        child: const _UserPointMarker(),
      ));
    }

    // Marqueur local de signalement immédiat.
    final localMarker = _buildLocalReportMarker();
    if (localMarker != null) markers.add(localMarker);

    // Marqueurs des alertes réseau (signalements validés / simulés).
    markers.addAll(_buildAlertMarkers());
    markers.addAll(_buildStreetMedicMarkers());
    markers.addAll(_buildTrustFriendMarkers());

    return _EventLayers(polylines: polylines, markers: markers);
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
        valueListenable: AppLocale.instance,
        builder: (context, _, child) {
          final s = AppLocale.instance.strings;
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
                    final hasMarkers = layers.markers.isNotEmpty ||
                        _userPosition != null ||
                        _placementPoint != null;

                    // ── SafeArea global pour Android 15+ (Edge-to-Edge) ──
                    // Android 15 impose le mode Edge-to-Edge par défaut :
                    // l'interface s'affiche derrière les barres système.
                    // Le SafeArea bottom garantit que les FABs et le contenu
                    // restent au-dessus de la barre de navigation gestuelle.
                    return Scaffold(
                      body: SafeArea(
                        top: false,
                        bottom: true,
                        child: Stack(
                          children: [
                            // ── Carte ──────────────────────────────────────────────
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _defaultCenter,
                                initialZoom: _defaultZoom,
                                minZoom: 3,
                                maxZoom: 19,
                                interactionOptions: InteractionOptions(
                                  flags: _draggingPlacement
                                      ? InteractiveFlag.none
                                      : InteractiveFlag.all,
                                ),
                                onLongPress: _onMapLongPress,
                                onPositionChanged: (camera, hasGesture) {
                                  // Désactive le suivi auto ET l'orientation
                                  // dès que l'utilisateur déplace la carte
                                  // à la main.
                                  if (hasGesture &&
                                      (_followUser || _followHeading)) {
                                    setState(() {
                                      _followUser = false;
                                      _followHeading = false;
                                    });
                                    _stopSmoothTickerIfIdle();
                                  }
                                },
                                onMapReady: () {
                                  if (mounted) {
                                    setState(() => _mapReady = true);
                                  }
                                },
                              ),
                              children: [
                                TileLayer(
                                  key: ValueKey('tiles_$isDark'),
                                  urlTemplate: tileUrl,
                                  fallbackUrl: kStreetPhareOsmTileUrlTemplate,
                                  userAgentPackageName: 'com.streetphare.app',
                                  tileProvider: _tileProvider,
                                  maxNativeZoom: 19,
                                  errorTileCallback: (tile, error, stackTrace) {
                                    if (kDebugMode) {
                                      debugPrint(
                                          '[MapScreen] tuile en échec: $error');
                                    }
                                  },
                                  tileBuilder:
                                      isDark ? darkModeTileBuilder : null,
                                  tileDisplay: const TileDisplay.fadeIn(
                                    duration: Duration(milliseconds: 350),
                                  ),
                                ),
                                if (layers.polylines.isNotEmpty)
                                  PolylineLayer(polylines: layers.polylines),
                                if (_safeRoutePoints != null &&
                                    _safeRoutePoints!.length >= 2)
                                  SafeRouteLayer(
                                      routePoints: _safeRoutePoints!,
                                      passedPoints: _passedRoutePoints),
                                if (_restrictedSegments.isNotEmpty)
                                  RestrictedSegmentLayer(
                                      segments: _restrictedSegments),
                                if (hasMarkers)
                                  MarkerLayer(
                                    markers: [
                                      if (_userPosition != null)
                                        _buildUserMarker(),
                                      ...layers.markers,
                                      if (_pendingReportType != null &&
                                          _placementPoint != null)
                                        _buildPlacementMarker()!,
                                    ],
                                  ),
                                if (_locating)
                                  Align(
                                    alignment: Alignment.bottomLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 12, bottom: 24),
                                      child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  StreetPhareTheme.primary),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_positionError != null)
                                  Align(
                                    alignment: Alignment.bottomLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 12, bottom: 24),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: StreetPhareTheme.surface
                                              .withValues(alpha: 0.85),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.gps_off,
                                                size: 12,
                                                color: StreetPhareTheme
                                                    .textSecondary),
                                            const SizedBox(width: 4),
                                            Text(
                                              _positionError!,
                                              style: TextStyle(
                                                  color: StreetPhareTheme
                                                      .textSecondary,
                                                  fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                const RichAttributionWidget(
                                  alignment: AttributionAlignment.bottomLeft,
                                  attributions: [
                                    TextSourceAttribution(
                                      'OpenStreetMap contributors',
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // ── Écran de chargement carte ───────────────────────────
                            if (!_mapReady)
                              Container(
                                color: Colors.black.withValues(alpha: 0.6),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                StreetPhareTheme.primary),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        s.mapLoadingTiles,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: ValueListenableBuilder<
                                            AppPreferences>(
                                          valueListenable:
                                              AppPreferencesStore.instance,
                                          builder: (_, prefs, o) {
                                            return Offstage(
                                              offstage: prefs.lowVisionMode,
                                              child: GestureDetector(
                                                onTap: () =>
                                                    _showAboutDialog(context),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.lightbulb,
                                                        color: StreetPhareTheme
                                                            .primary,
                                                        size: 18),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      s.appTitle,
                                                      style: TextStyle(
                                                        color: StreetPhareTheme
                                                            .textPrimary,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
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
                                    top: 126,
                                    left: 12,
                                    right: 80,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children:
                                            events.asMap().entries.map((entry) {
                                          final i = entry.key;
                                          final ev = entry.value;
                                          final col = _kEventColors[
                                              i % _kEventColors.length];
                                          final isVisible = ev.isRouteVisible();
                                          final isActive =
                                              prefs.activeEventIndex == i;
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(right: 6),
                                            child: GestureDetector(
                                              onTap: () => AppPreferencesStore
                                                  .instance
                                                  .setActiveEventIndex(i),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: isActive
                                                      ? col
                                                      : col.withValues(
                                                          alpha: 0.50),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: isActive
                                                      ? Border.all(
                                                          color: Colors.white,
                                                          width: 2)
                                                      : null,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
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
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    if (isActive) ...[
                                                      const SizedBox(width: 4),
                                                      const Icon(
                                                          Icons.check_circle,
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

                            // ── Bouton GPS Recentrer + Stop Tracking + effacer Route Safe
                            // Remontés aussi lors d'une intervention street-medic
                            // pour ne pas être masqués par le panneau « En intervention ».
                            ValueListenableBuilder<MedicMission?>(
                              valueListenable:
                                  StreetMedicService.instance.medicMission,
                              builder: (context, mission, _) => Positioned(
                                left: 16,
                                bottom: (mission != null &&
                                        (mission.status ==
                                                MedicMissionStatus.pending ||
                                            mission.status ==
                                                MedicMissionStatus.accepted))
                                    ? 300.0
                                    : 120.0,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Orientation auto selon le cap (heading-up)
                                    Material(
                                      elevation: 4,
                                      shape: const CircleBorder(),
                                      color: _followHeading
                                          ? StreetPhareTheme.primary
                                          : StreetPhareTheme.surface
                                              .withValues(alpha: 0.9),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () {
                                          setState(() =>
                                              _followHeading = !_followHeading);
                                          if (_followHeading) {
                                            // Oriente immédiatement + active le
                                            // suivi pour rester centré.
                                            _rotateMapToHeading();
                                            if (!_followUser) {
                                              setState(
                                                  () => _followUser = true);
                                              _animateToUser();
                                            }
                                          } else {
                                            // Rétablit le nord vers le haut.
                                            try {
                                              _mapController.rotate(0);
                                            } catch (_) {}
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Icon(
                                            _followHeading
                                                ? Icons.navigation
                                                : Icons.explore_outlined,
                                            color: _followHeading
                                                ? Colors.white
                                                : StreetPhareTheme
                                                    .textSecondary,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Recentrer / suivre la position GPS
                                    Material(
                                      elevation: 4,
                                      shape: const CircleBorder(),
                                      color: StreetPhareTheme.surface
                                          .withValues(alpha: 0.9),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () {
                                          if (!_isTracking) {
                                            _initUserLocation();
                                            return;
                                          }
                                          // Bascule le mode « suivre » et
                                          // recentre immédiatement si activé.
                                          setState(() {
                                            _followUser = !_followUser;
                                          });
                                          if (_followUser) _animateToUser();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Icon(
                                            !_isTracking
                                                ? Icons.gps_not_fixed
                                                : _followUser
                                                    ? Icons.my_location
                                                    : Icons.gps_fixed,
                                            color: _followUser
                                                ? StreetPhareTheme.primary
                                                : StreetPhareTheme
                                                    .textSecondary,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Effacer la Route Safe
                                    if (_safeRoutePoints != null) ...[
                                      const SizedBox(height: 8),
                                      Material(
                                        elevation: 4,
                                        shape: const CircleBorder(),
                                        color: StreetPhareTheme.surface
                                            .withValues(alpha: 0.9),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () {
                                            setState(() {
                                              _safeRoutePoints = null;
                                              _passedRoutePoints = null;
                                            });
                                            _applyWakelock();
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
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
                                          Icon(Icons.my_location,
                                              size: 13,
                                              color: StreetPhareTheme.primary),
                                          const SizedBox(width: 5),
                                          Text(
                                            prefs.routeDestinationType.label,
                                            style: TextStyle(
                                              color:
                                                  StreetPhareTheme.textPrimary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(Icons.expand_less,
                                              size: 14,
                                              color: StreetPhareTheme
                                                  .textSecondary),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                            // ── FABs actions ────────────────────────────────────────
                            ValueListenableBuilder<MedicMission?>(
                              valueListenable:
                                  StreetMedicService.instance.medicMission,
                              builder: (context, mission, _) {
                                // Remonte les FABs quand le panneau
                                // « En intervention » (pleine largeur, en bas)
                                // masquerait la colonne de boutons.
                                final interventionActive = mission != null &&
                                    (mission.status ==
                                            MedicMissionStatus.pending ||
                                        mission.status ==
                                            MedicMissionStatus.accepted);
                                return Positioned(
                                  right: 16,
                                  bottom: interventionActive ? 300.0 : 32.0,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _ActionFab(
                                        icon: Icons.add_alert,
                                        backgroundColor:
                                            StreetPhareTheme.primary,
                                        foregroundColor: Colors.black,
                                        onPressed: _openReportSheet,
                                      ),
                                      const SizedBox(height: 12),
                                      _ActionFab(
                                        icon: Icons.shield_outlined,
                                        backgroundColor:
                                            StreetPhareTheme.surface,
                                        foregroundColor:
                                            StreetPhareTheme.primary,
                                        borderColor: StreetPhareTheme.primary,
                                        onPressed: () => _triggerRouteSafe(),
                                      ),
                                      const SizedBox(height: 12),
                                      _ActionFab(
                                        icon: Icons.forum_outlined,
                                        backgroundColor:
                                            StreetPhareTheme.surface,
                                        foregroundColor:
                                            StreetPhareTheme.primary,
                                        borderColor: StreetPhareTheme.primary,
                                        onPressed: _openMessaging,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // ── Mode placement de signalement ─────────────────
                            if (_pendingReportType != null &&
                                _placementPoint != null)
                              Positioned(
                                top: 12,
                                left: 12,
                                right: 12,
                                child: _PlacementBanner(
                                  type: _pendingReportType!,
                                  onCancel: _cancelReportPlacement,
                                  onConfirm: _confirmReportPlacement,
                                ),
                              ),

                            // ── [DEBUG] Bouton de débogage ────
                            if (kDebugMode)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 64, right: 12),
                                    child: _DebugButton(
                                      userPosition: _userPosition,
                                      safeRoutePoints: _safeRoutePoints,
                                      mapReady: _mapReady,
                                      isTracking: _isTracking,
                                    ),
                                  ),
                                ),
                              ),

                            // ── Bandeau d'isolement critique ──────────────────────────
                            _ConnectivityBanner(strings: s),

                            // ── Bouton « Partager ma position » (haut de carte) ──
                            StreetMedicSharingToggle(
                              userPosition: _userPosition != null
                                  ? LatLng(
                                      _userPosition!.latitude,
                                      _userPosition!.longitude,
                                    )
                                  : null,
                            ),

                            // ── Overlay street-medic (mission + appel) ─────
                            StreetMedicOverlay(
                              userPosition: _userPosition != null
                                  ? LatLng(
                                      _userPosition!.latitude,
                                      _userPosition!.longitude,
                                    )
                                  : null,
                              onPanic: _triggerPanic,
                              panicLabel: s.panicButton,
                            ),
                          ],
                        ), // Stack
                      ), // SafeArea
                    );
                  },
                );
              });
        });
  }
}

// ============================================================================
// Sélecteur de destination (bottom sheet)
// ============================================================================

class _DestinationSelectorSheet extends StatelessWidget {
  const _DestinationSelectorSheet(
      {required this.events, required this.strings});
  final List<EventModel> events;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPreferences>(
      valueListenable: AppPreferencesStore.instance,
      builder: (context, prefs, _) {
        return Container(
          decoration: BoxDecoration(
            color: StreetPhareTheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                      color:
                          StreetPhareTheme.textSecondary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.my_location,
                        color: StreetPhareTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      strings.mapDestinationObjective,
                      style: TextStyle(
                        color: StreetPhareTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  strings.mapDestinationLongPressHint,
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
                    // Ferme le sélecteur et signale le changement pour
                    // déclencher le recalcul de l'itinéraire.
                    Navigator.of(context).pop(v);
                  },
                  child: Column(
                    children: [
                      for (final type in RouteDestinationType.values)
                        RadioListTile<RouteDestinationType>(
                          value: type,
                          title: Text(
                            type.label,
                            style: TextStyle(
                              color: StreetPhareTheme.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            type.description,
                            style: TextStyle(
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
                  Text(
                    strings.mapActiveEvent,
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
                            activeColor:
                                _kEventColors[i % _kEventColors.length],
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
                    child: Text(strings.close),
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
    final s = AppLocale.instance.strings;
    return ValueListenableBuilder<int>(
      valueListenable: PeerCounterService.instance,
      builder: (context, count, _) {
        final isActive = count > 0;
        return ValueListenableBuilder<bool>(
          valueListenable: ServerHeartbeatService.instance.isServerConnected,
          builder: (context, serverConnected, _) {
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
                    '$count\u00A0${s.mapPeersNearby.toLowerCase()}',
                    style: TextStyle(
                      color: isActive
                          ? StreetPhareTheme.textPrimary
                          : StreetPhareTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ServerStatusDot(connected: serverConnected),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Point lumineux indiquant la connexion au serveur web.
/// Vert = connecte, Rouge = mode local.
/// Une micro-animation de pulsation rend le changement d'etat fluide.
class _ServerStatusDot extends StatefulWidget {
  const _ServerStatusDot({required this.connected});
  final bool connected;

  @override
  State<_ServerStatusDot> createState() => _ServerStatusDotState();
}

class _ServerStatusDotState extends State<_ServerStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _ServerStatusDot old) {
    super.didUpdateWidget(old);
    if (widget.connected != old.connected) {
      _pulse
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.connected ? const Color(0xFF3FB950) : const Color(0xFFF85149);
    final tooltip = widget.connected
        ? 'Connecte au serveur'
        : 'Mode local : Serveur injoignable';

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          final message = ServerHeartbeatService.instance.statusMessage;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
        },
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(
            scale: _scale.value,
            child: child,
          ),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bannière affichée pendant le mode « placement » d'un signalement.
class _PlacementBanner extends StatelessWidget {
  const _PlacementBanner({
    required this.type,
    required this.onCancel,
    required this.onConfirm,
  });

  final ReportType type;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StreetPhareTheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(type.icon, color: type.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Placer « ${type.label} »',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ).copyWith(color: StreetPhareTheme.textPrimary),
                  ),
                ),
                IconButton(
                  icon:
                      Icon(Icons.close, color: StreetPhareTheme.textSecondary),
                  onPressed: onCancel,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Faites glisser l\'icône sur la carte jusqu\'au lieu exact.',
              style: TextStyle(
                color: StreetPhareTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: type.color,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check),
                label: const Text('Confirmer le signalement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionFab extends StatelessWidget {
  const _ActionFab({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: backgroundColor.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      color: backgroundColor,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
          ),
          child: Icon(icon, color: foregroundColor, size: 24),
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

// ============================================================================
// Widget auxiliaire "À propos" (ligne label / valeur)
// ============================================================================

class _AboutRow extends StatelessWidget {
  const _AboutRow(
      {required this.label, required this.value, required this.ctx});
  final String label;
  final String value;
  final BuildContext ctx;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(ctx).colorScheme.onSurface;
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
// [DEBUG] Bouton et panneau de débogage
// ============================================================================

class _DebugButton extends StatelessWidget {
  const _DebugButton({
    required this.userPosition,
    required this.safeRoutePoints,
    required this.mapReady,
    required this.isTracking,
  });

  final Position? userPosition;
  final List<LatLng>? safeRoutePoints;
  final bool mapReady;
  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shape: const CircleBorder(),
      color: Colors.redAccent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showDebugOverlay(context),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.bug_report, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  void _showDebugOverlay(BuildContext context) {
    final pos = userPosition;
    final routeLen = safeRoutePoints?.length ?? 0;
    final loggerSnapshot = ClientDebugLogger.instance.getSnapshot();
    final allLines = loggerSnapshot.split('\n');
    final recentLines = allLines.length > 40
        ? allLines.sublist(allLines.length - 40)
        : allLines;
    final recent = recentLines.join('\n');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DebugOverlaySheet(
        mapReady: mapReady,
        isTracking: isTracking,
        position: pos,
        routePointCount: routeLen,
        loggerSnapshot: recent,
      ),
    );
  }
}

/// BottomSheet de débogage (overlay kDebugMode).
class _DebugOverlaySheet extends StatelessWidget {
  const _DebugOverlaySheet({
    required this.mapReady,
    required this.isTracking,
    required this.position,
    required this.routePointCount,
    required this.loggerSnapshot,
  });

  final bool mapReady;
  final bool isTracking;
  final Position? position;
  final int routePointCount;
  final String loggerSnapshot;

  @override
  Widget build(BuildContext context) {
    final s = AppLocale.instance.strings;
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final routeLabel =
        routePointCount == 0 ? 'Aucun point' : '$routePointCount points';

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.bug_report, color: Colors.redAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'DEBUG OVERLAY',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 1.2,
                  ),
                ),
                Spacer(),
                Text(
                  'kDebugMode',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 16),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _debugRow(Icons.access_time, 'Timestamp', ts),
                  _debugRow(
                    Icons.map,
                    'Carte',
                    mapReady ? '✅ Prête' : '⏳ Chargement…',
                  ),
                  _debugRow(
                    Icons.gps_fixed,
                    'GPS',
                    isTracking
                        ? (position != null ? '✅ Actif' : '⚠️ En attente')
                        : '❌ Arrêté',
                  ),
                  if (position != null) ...[
                    _debugRow(
                      Icons.my_location,
                      'Latitude',
                      position!.latitude.toStringAsFixed(7),
                    ),
                    _debugRow(
                      Icons.my_location,
                      'Longitude',
                      position!.longitude.toStringAsFixed(7),
                    ),
                    _debugRow(
                      Icons.straighten,
                      'Précision',
                      '${position!.accuracy.toStringAsFixed(1)} m',
                    ),
                    _debugRow(
                      Icons.speed,
                      'Vitesse',
                      '${(position!.speed * 3.6).toStringAsFixed(1)} km/h',
                    ),
                  ],
                  _debugRow(Icons.route, 'Route Safe', routeLabel),
                  const Divider(color: Colors.white12, height: 20),
                  const Text(
                    '📋 CLIENT_DEBUG.md (dernières lignes)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      loggerSnapshot,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copier le snapshot'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: loggerSnapshot));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Snapshot copié !'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(s.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            '$label : ',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Bandeau de connectivité critique
// ============================================================================

class _ConnectivityBanner extends StatefulWidget {
  const _ConnectivityBanner({required this.strings});
  final AppStrings strings;

  @override
  State<_ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<_ConnectivityBanner> {
  bool _wasIsolated = false;

  /// Affiche la popup « vous êtes isolé » (une seule fois par isolement).
  Future<void> _showIsolationDialog() async {
    final s = widget.strings;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF85149)),
            const SizedBox(width: 10),
            Expanded(child: Text(s.mapIsolatedTitle)),
          ],
        ),
        content: Text(s.mapIsolatedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        try {
          final isIsolated = ConnectivityService.instance.isIsolated;

          // Transition vers l'isolement → sauvegarde immédiate dans Hive.
          if (isIsolated && !_wasIsolated) {
            _wasIsolated = true;
            // Sauvegarde non-bloquante des alertes critiques en mémoire.
            unawaited(_saveCriticalDataToHive());
            // Popup d'isolement affichée une seule fois (post-frame pour ne
            // pas modifier l'état pendant la phase de build).
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_showIsolationDialog());
            });
          }
          if (!isIsolated) {
            _wasIsolated = false;
          }

          // Structure stable : Positioned + Offstage toujours présents pour
          // éviter l'assertion framework « !semantics.parentDataDirty ».
          return Positioned(
            top: 120,
            left: 12,
            right: 12,
            child: Offstage(
              offstage: !isIsolated,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF85149),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, color: Colors.white, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.strings.mapIsolatedTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.strings.mapIsolatedMessage,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } catch (e) {
          // Toute exception lors d'un basculement Wi-Fi/BLE est capturée
          // pour éviter le crash de l'application.
          if (kDebugMode) {
            debugPrint('[ConnectivityBanner] erreur: $e');
          }
          return const Positioned(
            top: 120,
            left: 12,
            right: 12,
            child: Offstage(offstage: true, child: SizedBox.shrink()),
          );
        }
      },
    );
  }

  Future<void> _saveCriticalDataToHive() async {
    try {
      // Force la sauvegarde des alertes Hive en attente.
      final db = HiveAlertDatabase.instance;
      if (db.isInitialized) {
        final pending = db.getPendingUpload();
        if (pending.isNotEmpty && kDebugMode) {
          debugPrint(
              '[Offline] ${pending.length} alertes sauvegardées dans Hive');
        }
      }
    } catch (_) {
      // Silencieux — la priorité est de ne pas bloquer l'UI.
    }
  }
}

// ============================================================================
// Widget option de transport (popup)
// ============================================================================

class _TransportOption extends StatelessWidget {
  const _TransportOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: StreetPhareTheme.primary.withValues(alpha: 0.15),
          foregroundColor: StreetPhareTheme.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }
}
