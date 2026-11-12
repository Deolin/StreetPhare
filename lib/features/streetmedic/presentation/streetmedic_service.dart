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
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Dernière mission déclenchée par cet utilisateur (vue blessé).
  MedicMission? _myCall;

  /// Street-medics actifs (partage de position) — pour la carte publique.
  final ValueNotifier<List<StreetMedic>> activeStreetmedics =
      ValueNotifier(const []);

  /// Mission à traiter par le medic (active en priorité, sinon en attente).
  final ValueNotifier<MedicMission?> medicMission = ValueNotifier(null);

  String get userId => _userId ??= generateEphemeralUserId();
  StreetMedic? get streetMedic => value;
  bool get isAuthorized => value?.isAuthorized ?? false;
  bool get isSharing => _sharing;
  MedicMission? get activeMission => _activeMission;
  MedicMission? get myCall => _myCall;

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
      _myCall = MedicMission.fromJson(data['mission'] as Map<String, dynamic>);
      _startCallerTracking();
      return _myCall;
    } catch (_) {
      return null;
    }
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
      return _activeMission;
    } catch (_) {
      return null;
    }
  }

  Future<void> refuseMission(String missionId) async {
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

  /// Marque l'intervention terminée → le medic redevient disponible.
  Future<void> completeMission(String missionId) async {
    try {
      await http
          .post(
            Uri.parse('$_apiBase/api/streetmedic/missions/$missionId/complete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    _activeMission = null;
    _defer(() => medicMission.value = null);
    _stopVibrationTimer();
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
      for (final m in all.where((m) => m.isPending && m.medicId == userId)) {
        unawaited(
          NotificationService.instance.showAlertNotification(
            title: '🚑 Mission street-medic',
            body:
                'Un blessé à ${m.injuredLatitude.toStringAsFixed(4)}, '
                '${m.injuredLongitude.toStringAsFixed(4)} vous attend.',
          ),
        );
      }
      final pending =
          all.where((m) => m.medicId == userId && m.isPending).toList();
      _defer(() {
        medicMission.value =
            _activeMission ?? (pending.isNotEmpty ? pending.first : null);
      });

      // Mise à jour de la mission côté blessé (appelant).
      final myCalls = all.where((m) => m.callerUserId == userId).toList();
      if (myCalls.isNotEmpty) _myCall = myCalls.first;
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
      final m = _myCall;
      if (m == null ||
          m.status == MedicMissionStatus.completed ||
          m.status == MedicMissionStatus.cancelled) {
        _myCallTrackTimer?.cancel();
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