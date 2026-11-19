// lib/features/streetmedic/presentation/streetmedic_service.dart
//
// Service applicatif "Street-medic" :
//   - Demander le statut street-medic à un administrateur (message contact
//     chiffré sur un canal dédié).
//   - Activer/désactiver le partage de position temps réel.
//   - Appeler le street-medic le plus proche (mission d'intervention).
//   - Côté medic : accepter/refuser/clôturer, vibrer toutes les 5 min.

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../database/crypto_utils.dart';
import '../../../network/failover_manager.dart';
import '../../../network/network_config.dart';
import '../../../services/notification_service.dart';
import '../domain/models/streetmedic_models.dart';

/// URL de base du serveur actif, résolue par le FailoverManager
/// (production HTTPS ou fallback local), au lieu d'une adresse codée en dur.
String get _apiBase {
  final address = FailoverManager.instance.currentAddress;
  if (address.isNotEmpty) return address;
  return NetworkConfig.baseUrl;
}

/// Service singleton pilotant le cycle de vie street-medic.
class StreetMedicService extends ValueNotifier<StreetMedic?> {
  StreetMedicService._() : super(null);
  static final StreetMedicService instance = StreetMedicService._();

  static const String _userIdKey = 'streetmedic_user_id_v1';
  static const String _sharingKey = 'streetmedic_sharing_v1';

  String? _userId;
  String? _eventCode;
  bool _sharing = false;
  bool _initialized = false;
  double _lastLat = 0;
  double _lastLng = 0;

  Timer? _positionTimer;
  Timer? _vibrationTimer;
  Timer? _streetMedicRefreshTimer;
  Timer? _myCallTrackTimer;

  /// Mission acceptée (vue medic en intervention).
  MedicMission? _activeMission;

  /// Dernière mission en attente vue par ce medic — permet de détecter une
  /// réaffectation (timeout de réponse de 30 s) au prochain polling.
  String? _lastPendingMissionId;

  /// Dernière mission déclenchée par cet utilisateur (vue blessé).
  /// Exposé en [ValueNotifier] pour que le bouton « Appeler / Annuler
  /// l'appel » réagisse immédiatement sur la carte.
  final ValueNotifier<MedicMission?> myCallNotifier = ValueNotifier(null);

  /// Street-medics actifs (partage de position) — pour la carte publique.
  final ValueNotifier<List<StreetMedic>> activeStreetmedics =
      ValueNotifier(const []);

  /// Mission à traiter par le medic (active en priorité, sinon en attente).
  final ValueNotifier<MedicMission?> medicMission = ValueNotifier(null);

  /// Cible de navigation (position du blessé) déclenchée à l'acceptation
  /// d'une mission : la carte calcule automatiquement une « route safe ».
  final ValueNotifier<LatLng?> medicNavigationTarget = ValueNotifier(null);

  String get userId => _userId ??= generateEphemeralUserId();
  StreetMedic? get streetMedic => value;
  bool get isAuthorized => value?.isAuthorized ?? false;
  bool get isSharing => _sharing;
  MedicMission? get activeMission => _activeMission;
  MedicMission? get myCall => myCallNotifier.value;

  /// `true` si cet utilisateur a un appel au street-medic en cours
  /// (en attente ou en intervention) : le bouton doit alors basculer
  /// en « Annuler l'appel » pour éviter les faux signalements.
  bool get hasActiveCall {
    final m = myCallNotifier.value;
    return m != null &&
        (m.status == MedicMissionStatus.pending ||
            m.status == MedicMissionStatus.accepted);
  }

  /// Définit le code d'événement courant (secret de dérivation de la clé
  /// du message de contact destiné aux administrateurs).
  void setEventCode(String? code) => _eventCode = code;

  /// Diffère une mutation de notifieur après le frame courant, pour éviter
  /// tout rebuild pendant la phase de layout/paint (crash « RenderBox was
  /// not laid out » sur l'overlay street-medic).
  void _defer(void Function() fn) {
    SchedulerBinding.instance.addPostFrameCallback((_) => fn());
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_userIdKey);
    _userId = (stored != null && stored.isNotEmpty)
        ? stored
        : generateEphemeralUserId();
    await prefs.setString(_userIdKey, _userId!);
    _sharing = prefs.getBool(_sharingKey) ?? false;
    await refreshStatus();
    _streetMedicRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        unawaited(refreshStatus());
        unawaited(refreshActiveStreetMedics());
        unawaited(pollMissions());
      },
    );
    unawaited(refreshActiveStreetMedics());
    unawaited(pollMissions());
  }

  /// Récupère le statut street-medic courant et notifie l'UI.
  Future<void> refreshStatus() async {
    try {
      final uri = Uri.parse('$_apiBase/api/streetmedic/me')
          .replace(queryParameters: {'userId': userId});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final sm = data['streetmedic'] as Map<String, dynamic>?;
      final model = sm != null ? StreetMedic.fromJson(sm) : null;
      // N'émet que si le statut change réellement — sinon `refreshStatus`
      // (appelé toutes les 20 s) recréerait un objet et déclencherait un
      // rebuild inutile de l'overlay (crash « RenderBox was not laid out »).
      final prev = value;
      final statusChanged = (model == null) != (prev == null) ||
          (model != null && prev != null && model.status != prev.status);
      if (statusChanged) {
        _defer(() => value = model);
      }
      if (model == null || model.status == StreetMedicStatus.disabled) {
        await _setSharing(false, persistLocal: false);
      }
    } catch (_) {
      // Hors-ligne : le statut local reste inchangé.
    }
  }

  /// Chiffre un message destiné à l'administrateur (AES-256-CBC + HMAC,
  /// sel aléatoire par message) avec la clé dérivée du code d'événement.
  Future<String> encryptAdminMessage(String plain) async {
    final secretText = _eventCode ?? 'streetphare';
    final secret = SecretKey(utf8.encode(secretText));
    return CryptoUtils.instance.encryptAddress(plain, secret);
  }

  /// Envoie une demande de statut street-medic à l'administrateur.
  /// [contactMessage] (optionnel) est chiffré avant envoi.
  Future<StreetMedic?> requestAuthorization({
    String? eventId,
    double? lat,
    double? lng,
    String? contactMessage,
  }) async {
    try {
      final cipher = (contactMessage != null && contactMessage.isNotEmpty)
          ? await encryptAdminMessage(contactMessage)
          : '';
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'eventId': eventId,
              'lat': lat,
              'lng': lng,
              'contactCipher': cipher,
              'contactMessage': contactMessage,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final sm = data['streetmedic'] as Map<String, dynamic>?;
      if (sm != null) _defer(() => value = StreetMedic.fromJson(sm));
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<bool> startSharing({double? lat, double? lng, String? eventId}) async {
    if (lat != null) _lastLat = lat;
    if (lng != null) _lastLng = lng;
    final ok = await _sendPosition(sharing: true, eventId: eventId);
    if (ok) {
      await _setSharing(true);
      _startPositionTimer();
    }
    return ok;
  }

  /// Désactive le partage de position (à tout moment).
  Future<bool> stopSharing() async {
    final ok = await _sendPosition(sharing: false);
    await _setSharing(false);
    _stopPositionTimer();
    return ok;
  }

  /// Arrête tout traçage de position (partage street-medic + suivi d'appel)
  /// — appelé à la fermeture de l'application pour préserver la vie privée.
  Future<void> stopAllTracking() async {
    if (_sharing) {
      // Envoie `sharing:false` au serveur (le medic disparaît de la carte
      // publique), stoppe le timer et persiste `sharing=false` localement.
      await stopSharing();
    } else {
      _stopPositionTimer();
    }
    // Cesse de transmettre la position du blessé (suivi d'appel en cours).
    _myCallTrackTimer?.cancel();
    _myCallTrackTimer = null;
  }

  /// Met à jour la position connue (appelée par le GPS / geofencing).
  void updatePosition(double lat, double lng) {
    _lastLat = lat;
    _lastLng = lng;
  }

  Future<bool> _sendPosition({required bool sharing, String? eventId}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/position'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'lat': _lastLat,
              'lng': _lastLng,
              'sharing': sharing,
              'eventId': eventId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final sm = data['streetmedic'] as Map<String, dynamic>?;
      if (sm != null) {
        final model = StreetMedic.fromJson(sm);
        final prev = value;
        // N'émet que si le statut ou le partage change (évite un rebuild
        // inutile de l'overlay à chaque battement de position).
        final changed = prev == null ||
            prev.status != model.status ||
            prev.sharing != model.sharing;
        if (changed) _defer(() => value = model);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_sharing) _sendPosition(sharing: true);
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  Future<void> _setSharing(bool sharing, {bool persistLocal = true}) async {
    _sharing = sharing;
    if (persistLocal) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sharingKey, sharing);
    }
    if (_sharing) {
      _startPositionTimer();
    } else {
      _stopPositionTimer();
    }
  }

  // ---------------------------------------------------------------------------
  // Missions d'intervention — vue blessé
  // ---------------------------------------------------------------------------

  Future<MedicMission?> callNearestMedic({
    required double lat,
    required double lng,
    String? note,
  }) async {
    try {
      _lastLat = lat;
      _lastLng = lng;
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'lat': lat,
              'lng': lng,
              'note': note,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 201) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      myCallNotifier.value =
          MedicMission.fromJson(data['mission'] as Map<String, dynamic>);
      _startCallerTracking();
      return myCallNotifier.value;
    } catch (_) {
      return null;
    }
  }

  /// Annule l'appel au street-medic déclenché par cet utilisateur (blessé)
  /// afin d'éviter qu'un faux signalement ne mobilise un medic pour rien.
  Future<bool> cancelMyCall() async {
    final m = myCallNotifier.value;
    if (m == null) return true;
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions/${m.id}/cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
    } catch (_) {
      return false;
    }
    _myCallTrackTimer?.cancel();
    myCallNotifier.value = null;
    _lastPendingMissionId = null;
    return true;
  }

  Future<MedicMission?> acceptMission(
    String missionId, {
    double? lat,
    double? lng,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions/$missionId/accept'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'lat': lat, 'lng': lng}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _activeMission =
          MedicMission.fromJson(data['mission'] as Map<String, dynamic>);
      _defer(() => medicMission.value = _activeMission);
      _startVibrationTimer();
      _lastPendingMissionId = null;
      // Demande automatiquement une « route safe » vers le blessé.
      final accepted = _activeMission;
      if (accepted != null) {
        _defer(() => medicNavigationTarget.value =
            LatLng(accepted.injuredLatitude, accepted.injuredLongitude));
      }
      return _activeMission;
    } catch (_) {
      return null;
    }
  }

  Future<void> refuseMission(String missionId) async {
    _lastPendingMissionId = null;
    try {
      await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions/$missionId/refuse'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Marque l'intervention terminée et notifie l'administration du résultat.
  ///
  /// [outcome] peut être :
  ///   * `treated`   → victime soignée sur place (clôture normale) ;
  ///   * `emergency` → victime non soignable sur place : une alerte « 112 »
  ///                   est remontée dans la section administration.
  Future<void> completeMission(String missionId, {String outcome = 'treated'}) async {
    try {
      await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions/$missionId/complete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId, 'outcome': outcome}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    _activeMission = null;
    _lastPendingMissionId = null;
    _defer(() => medicMission.value = null);
    _stopVibrationTimer();
  }

  /// Lance l'appel de détresse au 112 (numéro unique des urgences en Europe).
  ///
  /// L'appel est déclenché côté victime non soignable sur place. On l'exécute
  /// APRÈS [completeMission] pour que l'alerte d'administration soit partie.
  /// En cas d'échec de l'appel (émulateur, pas de SIM…), on informe l'appelant.
  Future<bool> launchEmergencyCall() async {
    final uri = Uri.parse('tel:112');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // `canLaunchUrl`/`launchUrl` peut lever sur certaines plateformes.
    }
    return false;
  }

  Future<void> pollMissions() async {
    try {
      final uri = Uri.parse('$_apiBase/api/streetmedic/missions')
          .replace(queryParameters: {'userId': userId});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final active = data['active'] as Map<String, dynamic>?;
      if (active != null) {
        _activeMission = MedicMission.fromJson(active);
        _startVibrationTimer();
      }
      final missions = (data['missions'] as List<dynamic>?) ?? const [];
      final all = missions
          .whereType<Map<String, dynamic>>()
          .map(MedicMission.fromJson)
          .toList();

      final pending =
          all.where((m) => m.medicId == userId && m.isPending).toList();
      final newPending = pending.isNotEmpty ? pending.first : null;

      // ── Réception d'une nouvelle mission → vibration du téléphone ──────
      if (newPending != null) {
        if (_lastPendingMissionId != newPending.id) {
          _lastPendingMissionId = newPending.id;
          unawaited(_vibrateAlert());
          unawaited(
            NotificationService.instance.showAlertNotification(
              title: '🚑 Mission street-medic',
              body: 'Un blessé à ${newPending.injuredLatitude.toStringAsFixed(4)}, '
                  '${newPending.injuredLongitude.toStringAsFixed(4)} vous attend. '
                  'Répondez dans les 30 secondes.',
            ),
          );
        }
      } else if (_lastPendingMissionId != null) {
        // Plus de mission en attente : si elle a disparu de notre liste
        // (réaffectée après timeout), on prévient le medic silencieux.
        final stillMine = all.any((m) =>
            m.id == _lastPendingMissionId && m.medicId == userId);
        if (!stillMine) {
          unawaited(_notifyMissionTimeout());
        }
        _lastPendingMissionId = null;
      }

      _defer(() {
        medicMission.value =
            _activeMission ?? (pending.isNotEmpty ? pending.first : null);
      });

      // Mise à jour de la mission côté blessé (appelant).
      final myCalls = all.where((m) => m.callerUserId == userId).toList();
      myCallNotifier.value = myCalls.isNotEmpty ? myCalls.first : null;
    } catch (_) {}
  }

  Future<void> refreshActiveStreetMedics() async {
    try {
      final res = await http
          .get(Uri.parse('$_apiBase/api/streetmedic/active'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['streetmedics'] as List<dynamic>?) ?? const [];
      _defer(() {
        activeStreetmedics.value = list
            .whereType<Map<String, dynamic>>()
            .map(StreetMedic.fromJson)
            .toList();
      });
    } catch (_) {}
  }

  void _startCallerTracking() {
    _myCallTrackTimer?.cancel();
    _myCallTrackTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final m = myCallNotifier.value;
      if (m == null) {
        _myCallTrackTimer?.cancel();
        return;
      }
      if (m.status == MedicMissionStatus.completed ||
          m.status == MedicMissionStatus.cancelled) {
        _myCallTrackTimer?.cancel();
        myCallNotifier.value = null;
        return;
      }
      trackMyCallPosition(m.id);
    });
  }

  /// Le blessé transmet sa position au medic assigné.
  Future<void> trackMyCallPosition(String missionId) async {
    try {
      await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions/$missionId/track'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'lat': _lastLat,
              'lng': _lastLng,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Alertes vibratoires & notification de timeout
  // ───────────────────────────────────────────────────────────────────────────

  /// Fait vibrer le téléphone à la réception d'une nouvelle mission.
  Future<void> _vibrateAlert() async {
    try {
      for (var i = 0; i < 3; i++) {
        await HapticFeedback.vibrate();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } catch (_) {}
  }

  /// Message local : la mission a expiré sans réponse — le medic est
  /// considéré « occupé » et la mission est passée au street-medic suivant.
  Future<void> _notifyMissionTimeout() async {
    try {
      await NotificationService.instance.showAlertNotification(
        title: '🕒 Mission refusée',
        body: 'Vous n\'avez pas répondu à temps. '
            'La mission a été transmise à un autre street-medic.',
      );
    } catch (_) {}
  }

  // Rappel vibratoire (intervention en cours) — stoppé si l'app est fermée.
  void _startVibrationTimer() {
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      HapticFeedback.vibrate();
    });
  }

  void _stopVibrationTimer() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  @override
  void dispose() {
    _stopPositionTimer();
    _stopVibrationTimer();
    _streetMedicRefreshTimer?.cancel();
    _myCallTrackTimer?.cancel();
    super.dispose();
  }
}
